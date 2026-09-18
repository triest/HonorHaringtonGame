extends SceneTree
## Headless test runner for §25's "propulsion damage -> degraded
## acceleration" example, as implemented via ShipPhysicsState.subsystems.
## Run via: godot --headless --script res://simulation/tests/test_propulsion_subsystem_damage.gd

const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
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

func _test_no_subsystems_keeps_legacy_behavior() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	_assert(is_equal_approx(s.effective_max_acceleration(), 1000.0), "no subsystems (null, default) should keep legacy effective_max_acceleration")

func _test_undamaged_subsystems_no_change() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	s.subsystems = ShipSubsystems.new()
	_assert(is_equal_approx(s.effective_max_acceleration(), 1000.0), "fresh (undamaged) ShipSubsystems should not change effective_max_acceleration")

func _test_propulsion_damage_degrades_acceleration() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	s.subsystems = ShipSubsystems.new()
	s.subsystems.apply_damage(SubsystemType.Type.PROPULSION, 0.6)  # condition -> 0.4
	_assert(is_equal_approx(s.effective_max_acceleration(), 400.0), "damaged PROPULSION subsystem should proportionally degrade effective_max_acceleration")

func _test_maneuvering_damage_also_degrades_acceleration() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	s.subsystems = ShipSubsystems.new()
	s.subsystems.apply_damage(SubsystemType.Type.MANEUVERING, 0.5)  # condition -> 0.5
	_assert(is_equal_approx(s.effective_max_acceleration(), 500.0), "damaged MANEUVERING subsystem should also degrade effective_max_acceleration")

func _test_disabled_propulsion_zeroes_acceleration() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	s.subsystems = ShipSubsystems.new()
	s.subsystems.apply_damage(SubsystemType.Type.PROPULSION, 1.0)  # fully disabled
	_assert(s.effective_max_acceleration() == 0.0, "fully disabled PROPULSION should zero out effective_max_acceleration")

func _test_legacy_condition_fields_and_subsystems_compound() -> void:
	var s := ShipPhysicsState.new()
	s.max_acceleration_mps2 = 1000.0
	s.propulsion_condition = 0.5  # pre-existing field
	s.subsystems = ShipSubsystems.new()
	s.subsystems.apply_damage(SubsystemType.Type.PROPULSION, 0.5)  # ShipSubsystems condition -> 0.5
	_assert(is_equal_approx(s.effective_max_acceleration(), 250.0), "legacy propulsion_condition and ShipSubsystems PROPULSION condition should compound multiplicatively (0.5 * 0.5 = 0.25)")

func _init() -> void:
	_test_no_subsystems_keeps_legacy_behavior()
	_test_undamaged_subsystems_no_change()
	_test_propulsion_damage_degrades_acceleration()
	_test_maneuvering_damage_also_degrades_acceleration()
	_test_disabled_propulsion_zeroes_acceleration()
	_test_legacy_condition_fields_and_subsystems_compound()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
