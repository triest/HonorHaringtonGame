extends SceneTree
## Headless test runner for MissileGuidance's §23 Sensors wiring
## (update_target_tracking / resolve_thrust_direction).
## Run via: godot --headless --script res://simulation/tests/test_missile_guidance_sensors.gd

const MissileState = preload("res://simulation/missile_state.gd")
const MissileGuidance = preload("res://simulation/missile_guidance.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_missile(pos: Vector3, target) -> MissileState:
	var m := MissileState.new()
	m.position = pos
	m.velocity = Vector3(0, 0, 100)
	m.target = target
	return m

func _make_ship(pos: Vector3, wedge_up: bool = true) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.velocity = Vector3.ZERO
	s.defense = ShipDefenseState.new()
	s.defense.wedge_up = wedge_up
	return s

func _test_no_target_holds_heading() -> void:
	var m := _make_missile(Vector3.ZERO, null)
	var dir := MissileGuidance.resolve_thrust_direction(m, 1.0)
	_assert(dir.is_equal_approx(m.velocity.normalized()), "no target should hold current velocity heading")

func _test_first_tick_before_detection_holds_heading() -> void:
	# Target far out of sensor range on the very first tick: sensor_contact
	# starts UNKNOWN, not yet DETECTED -- must not steer at Vector3.ZERO.
	var target := _make_ship(Vector3(10_000_000_000, 0, 0), true)
	var m := _make_missile(Vector3.ZERO, target)
	var dir := MissileGuidance.resolve_thrust_direction(m, 1.0, 1_000_000.0)
	_assert(m.sensor_state == ContactState.Type.UNKNOWN, "out-of-range target should leave sensor_state UNKNOWN")
	_assert(dir.is_equal_approx(m.velocity.normalized()), "undetected target should hold heading, not aim at Vector3.ZERO")

func _test_detected_target_steers_toward_estimate() -> void:
	var target := _make_ship(Vector3(0, 0, 5000), true)
	var m := _make_missile(Vector3.ZERO, target)
	var dir := MissileGuidance.resolve_thrust_direction(m, 1.0, 1_000_000.0)
	_assert(m.sensor_state == ContactState.Type.DETECTED, "in-range emitting target should be DETECTED")
	_assert(dir.z > 0.9, "thrust direction should steer toward the detected target ahead on +Z")

func _test_sensor_contact_created_and_reused() -> void:
	var target := _make_ship(Vector3(0, 0, 5000), true)
	var m := _make_missile(Vector3.ZERO, target)
	_assert(m.sensor_contact == null, "sensor_contact should start null (lazy)")
	MissileGuidance.update_target_tracking(m, 1.0, 1_000_000.0)
	_assert(m.sensor_contact != null, "sensor_contact should be created on first tracking update")
	var contact_ref = m.sensor_contact
	MissileGuidance.update_target_tracking(m, 1.0, 1_000_000.0)
	_assert(m.sensor_contact == contact_ref, "sensor_contact should be reused, not recreated, on later ticks")

func _test_loss_of_contact_falls_back_to_hold_heading() -> void:
	var target := _make_ship(Vector3(0, 0, 5000), true)
	var m := _make_missile(Vector3.ZERO, target)
	MissileGuidance.resolve_thrust_direction(m, 1.0, 1_000_000.0)
	_assert(m.sensor_state == ContactState.Type.DETECTED, "should be DETECTED after first tick")

	target.defense.wedge_up = false
	var dir := MissileGuidance.resolve_thrust_direction(m, 1.0, 1_000_000.0)
	_assert(m.sensor_state == ContactState.Type.ESTIMATED, "wedge-down target should decay to ESTIMATED, not vanish instantly")
	# Still usable (dead-reckoned) -- should still steer roughly toward it.
	_assert(dir.z > 0.5, "ESTIMATED (dead-reckoned) contact should still be usable for steering")

func _init() -> void:
	_test_no_target_holds_heading()
	_test_first_tick_before_detection_holds_heading()
	_test_detected_target_steers_toward_estimate()
	_test_sensor_contact_created_and_reused()
	_test_loss_of_contact_falls_back_to_hold_heading()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
