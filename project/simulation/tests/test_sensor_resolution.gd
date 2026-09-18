extends SceneTree
## Headless test runner for SensorResolution (ТЗ §23 Sensors).
## Run via: godot --headless --script res://simulation/tests/test_sensor_resolution.gd

const SensorContact = preload("res://simulation/sensor_contact.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(pos: Vector3, wedge_up: bool = true) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.velocity = Vector3.ZERO
	s.defense = ShipDefenseState.new()
	s.defense.wedge_up = wedge_up
	return s

func _test_detection_when_in_range_and_emitting() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "in-range emitting target should become DETECTED")
	_assert(contact.estimated_position.is_equal_approx(Vector3(1000, 0, 0)), "estimated position should match true position on detection")

func _test_no_detection_when_wedge_down() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), false)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.UNKNOWN, "wedge-down target in range should NOT be detected")

func _test_no_detection_when_out_of_range() -> void:
	var target := _make_ship(Vector3(10_000_000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.UNKNOWN, "out-of-range target should not be detected")

func _test_missile_detectable_while_burning_not_while_coasting() -> void:
	var missile := MissileState.new()
	missile.position = Vector3(500, 0, 0)
	missile.velocity = Vector3.ZERO
	missile.drive_burn_remaining_s = 10.0
	var contact := SensorContact.new(missile)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "burning missile should be detected")

	var coasting := MissileState.new()
	coasting.position = Vector3(500, 0, 0)
	coasting.velocity = Vector3.ZERO
	coasting.drive_burn_remaining_s = 0.0
	var contact2 := SensorContact.new(coasting)
	SensorResolution.update_contact(contact2, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact2.state == ContactState.Type.UNKNOWN, "coasting (unpowered) missile should not be freshly detected")

func _test_detected_upgrades_to_tracked_after_sustained_contact() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	for i in range(10):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.TRACKED, "sustained detection should upgrade DETECTED -> TRACKED")

func _test_loss_of_detection_goes_to_estimated_then_lost() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	for i in range(3):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "losing detection should transition to ESTIMATED")

	for i in range(60):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.LOST, "ESTIMATED should decay to LOST after grace period expires")

func _test_estimated_dead_reckons_position() -> void:
	var target := _make_ship(Vector3(0, 0, 0), true)
	target.velocity = Vector3(100, 0, 0)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3(0, 0, -1_000), 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3(0, 0, -1_000), 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "should be ESTIMATED after loss")
	_assert(contact.estimated_position.x > 0.0, "dead reckoning should advance estimated position using last known velocity")

func _test_contact_resumes_detection_after_reappearing() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "should be ESTIMATED after loss")
	target.defense.wedge_up = true
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "reappearing target should re-detect as DETECTED")

func _init() -> void:
	_test_detection_when_in_range_and_emitting()
	_test_no_detection_when_wedge_down()
	_test_no_detection_when_out_of_range()
	_test_missile_detectable_while_burning_not_while_coasting()
	_test_detected_upgrades_to_tracked_after_sustained_contact()
	_test_loss_of_detection_goes_to_estimated_then_lost()
	_test_estimated_dead_reckons_position()
	_test_contact_resumes_detection_after_reappearing()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
