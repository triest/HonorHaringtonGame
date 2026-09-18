extends SceneTree
## Headless test runner for PointDefenseResolution's §23 Sensors gating
## (the optional sensor_contact parameter on engage()).
## Run via: godot --headless --script res://simulation/tests/test_point_defense_sensors.gd

const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship() -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = Vector3.ZERO
	return s

func _make_missile(pos: Vector3) -> MissileState:
	var m := MissileState.new()
	m.position = pos
	m.guidance_state = MissileState.GuidanceState.MIDCOURSE
	return m

func _test_no_contact_arg_keeps_legacy_behavior() -> void:
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	var ship := _make_ship()
	var missile := _make_missile(Vector3(1000, 0, 0))
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(result.outcome != PointDefenseResolution.Outcome.NOT_DETECTED, "omitting sensor_contact should not sensor-gate (legacy behavior)")

func _test_undetected_contact_blocks_engagement() -> void:
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	var ship := _make_ship()
	var missile := _make_missile(Vector3(1000, 0, 0))
	var contact := SensorContact.new(missile)
	contact.state = ContactState.Type.UNKNOWN
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1, contact)
	_assert(result.outcome == PointDefenseResolution.Outcome.NOT_DETECTED, "UNKNOWN sensor contact should block PD engagement (can't shoot what you can't see)")

func _test_lost_contact_blocks_engagement() -> void:
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	var ship := _make_ship()
	var missile := _make_missile(Vector3(1000, 0, 0))
	var contact := SensorContact.new(missile)
	contact.state = ContactState.Type.LOST
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1, contact)
	_assert(result.outcome == PointDefenseResolution.Outcome.NOT_DETECTED, "LOST sensor contact should block PD engagement")

func _test_tracked_contact_allows_engagement() -> void:
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	var ship := _make_ship()
	var missile := _make_missile(Vector3(1000, 0, 0))
	var contact := SensorContact.new(missile)
	contact.state = ContactState.Type.TRACKED
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1, contact)
	_assert(result.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "TRACKED sensor contact should allow PD to engage")

func _test_estimated_contact_still_allows_engagement() -> void:
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	var ship := _make_ship()
	var missile := _make_missile(Vector3(1000, 0, 0))
	var contact := SensorContact.new(missile)
	contact.state = ContactState.Type.ESTIMATED
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1, contact)
	_assert(result.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "ESTIMATED (dead-reckoned) sensor contact should still allow PD to engage")

func _init() -> void:
	_test_no_contact_arg_keeps_legacy_behavior()
	_test_undetected_contact_blocks_engagement()
	_test_lost_contact_blocks_engagement()
	_test_tracked_contact_allows_engagement()
	_test_estimated_contact_still_allows_engagement()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
