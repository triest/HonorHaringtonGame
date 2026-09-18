extends SceneTree
## Headless test runner for §25's "sensor damage -> degraded tracking"
## example, as implemented via SensorResolution's observer_subsystems arg.
## Run via: godot --headless --script res://simulation/tests/test_sensor_subsystem_damage.gd

const SensorContact = preload("res://simulation/sensor_contact.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(pos: Vector3) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.velocity = Vector3.ZERO
	s.defense = ShipDefenseState.new()
	s.defense.wedge_up = true
	return s

func _test_undamaged_sensors_detect_normally() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var observer_subsystems := ShipSubsystems.new()
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, null, observer_subsystems)
	_assert(contact.state == ContactState.Type.DETECTED, "undamaged (full condition) sensors should detect normally")

func _test_damaged_sensors_shrink_effective_range() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var observer_subsystems := ShipSubsystems.new()
	observer_subsystems.apply_damage(SubsystemType.Type.SENSORS, 0.6)  # condition -> 0.4
	var contact := SensorContact.new(target)
	# Base range 2000m * 0.4 condition = 800m effective; target at 1000m
	# should NOT be detected -- directly implements the ТЗ §25 example
	# "sensor damage -> degraded tracking".
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, null, observer_subsystems)
	_assert(contact.state == ContactState.Type.UNKNOWN, "damaged sensors should shrink effective range enough to prevent detection at 1000m with 0.4 condition on a 2000m base range")

func _test_disabled_sensors_block_detection_entirely() -> void:
	var target := _make_ship(Vector3(10, 0, 0))  # very close
	var observer_subsystems := ShipSubsystems.new()
	observer_subsystems.apply_damage(SubsystemType.Type.SENSORS, 1.0)  # fully disabled
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, null, observer_subsystems)
	_assert(contact.state == ContactState.Type.UNKNOWN, "fully disabled sensors should block detection even at point-blank range")

func _test_no_subsystems_arg_keeps_legacy_behavior() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "omitting observer_subsystems should not affect detection (legacy/undamaged behavior)")

func _test_damage_and_ecm_compound() -> void:
	const ECMState = preload("res://simulation/ecm_state.gd")
	var target := _make_ship(Vector3(500, 0, 0))
	var ecm := ECMState.new()
	ecm.jamming_active = true
	ecm.jamming_range_multiplier = 0.5
	var observer_subsystems := ShipSubsystems.new()
	observer_subsystems.apply_damage(SubsystemType.Type.SENSORS, 0.5)  # condition 0.5
	var contact := SensorContact.new(target)
	# Effective range = 2000 * 0.5 (jamming) * 0.5 (damage) = 500m; target
	# exactly at 500m should just barely be detected.
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, ecm, observer_subsystems)
	_assert(contact.state == ContactState.Type.DETECTED, "jamming and sensor damage should compound multiplicatively, not override each other")

func _init() -> void:
	_test_undamaged_sensors_detect_normally()
	_test_damaged_sensors_shrink_effective_range()
	_test_disabled_sensors_block_detection_entirely()
	_test_no_subsystems_arg_keeps_legacy_behavior()
	_test_damage_and_ecm_compound()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
