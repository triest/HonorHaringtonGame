extends SceneTree
## Headless test runner for ShipSubsystems (ТЗ §25 Damage).
## Run via: godot --headless --script res://simulation/tests/test_ship_subsystems.gd

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

func _test_all_subsystems_start_full_condition() -> void:
	var s := ShipSubsystems.new()
	for t in SubsystemType.Type.values():
		_assert(s.get_condition(t) == 1.0, "subsystem %s should start at full (1.0) condition" % t)
		_assert(not s.is_disabled(t), "subsystem %s should not start disabled" % t)

func _test_apply_damage_reduces_condition() -> void:
	var s := ShipSubsystems.new()
	s.apply_damage(SubsystemType.Type.SENSORS, 0.3)
	_assert(is_equal_approx(s.get_condition(SubsystemType.Type.SENSORS), 0.7), "apply_damage should reduce condition by the given amount")
	_assert(s.get_condition(SubsystemType.Type.PROPULSION) == 1.0, "damage to one subsystem should not affect another")

func _test_damage_clamps_at_zero() -> void:
	var s := ShipSubsystems.new()
	s.apply_damage(SubsystemType.Type.WEAPONS, 5.0)
	_assert(s.get_condition(SubsystemType.Type.WEAPONS) == 0.0, "condition should clamp at 0.0, not go negative")
	_assert(s.is_disabled(SubsystemType.Type.WEAPONS), "condition at 0.0 should count as disabled")

func _test_repair_restores_condition() -> void:
	var s := ShipSubsystems.new()
	s.apply_damage(SubsystemType.Type.POWER, 0.6)
	s.repair(SubsystemType.Type.POWER, 0.2)
	_assert(is_equal_approx(s.get_condition(SubsystemType.Type.POWER), 0.6), "repair should restore condition by the given amount")

func _test_repair_clamps_at_one() -> void:
	var s := ShipSubsystems.new()
	s.repair(SubsystemType.Type.STRUCTURAL_INTEGRITY, 5.0)
	_assert(s.get_condition(SubsystemType.Type.STRUCTURAL_INTEGRITY) == 1.0, "condition should clamp at 1.0, not exceed full")

func _init() -> void:
	_test_all_subsystems_start_full_condition()
	_test_apply_damage_reduces_condition()
	_test_damage_clamps_at_zero()
	_test_repair_restores_condition()
	_test_repair_clamps_at_one()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
