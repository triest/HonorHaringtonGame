extends SceneTree
## Headless test runner for SubsystemDamageResolution and its wiring into
## WeaponResolution / MissileResolution (ТЗ §25 Damage).
## Run via: godot --headless --script res://simulation/tests/test_subsystem_damage_resolution.gd

const SubsystemDamageResolution = preload("res://simulation/subsystem_damage_resolution.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _test_no_subsystems_arg_is_noop() -> void:
	var result := SubsystemDamageResolution.apply_hit(null, 100.0, AttackGeometry.Sector.PORT)
	_assert(result.is_empty(), "apply_hit with null subsystems should return {} and do nothing")

func _test_zero_damage_is_noop() -> void:
	var s := ShipSubsystems.new()
	var result := SubsystemDamageResolution.apply_hit(s, 0.0, AttackGeometry.Sector.PORT)
	_assert(result.is_empty(), "apply_hit with zero damage should return {} and do nothing")
	_assert(s.get_condition(SubsystemType.Type.WEAPONS) == 1.0, "zero damage should not touch any subsystem")

func _test_sector_maps_to_expected_primary_subsystem() -> void:
	var s := ShipSubsystems.new()
	SubsystemDamageResolution.apply_hit(s, 200.0, AttackGeometry.Sector.PORT)
	_assert(s.get_condition(SubsystemType.Type.WEAPONS) < 1.0, "a PORT hit should degrade WEAPONS (the mapped primary subsystem)")

func _test_structural_integrity_shares_every_hit() -> void:
	var s := ShipSubsystems.new()
	SubsystemDamageResolution.apply_hit(s, 200.0, AttackGeometry.Sector.BOW)
	_assert(s.get_condition(SubsystemType.Type.MANEUVERING) < 1.0, "BOW hit should degrade its primary (MANEUVERING)")
	_assert(s.get_condition(SubsystemType.Type.STRUCTURAL_INTEGRITY) < 1.0, "every hit should also share some damage to STRUCTURAL_INTEGRITY")

func _test_unclassified_sector_falls_back_to_structural() -> void:
	var s := ShipSubsystems.new()
	SubsystemDamageResolution.apply_hit(s, 200.0, null)
	_assert(s.get_condition(SubsystemType.Type.STRUCTURAL_INTEGRITY) < 1.0, "null sector should fall back to damaging STRUCTURAL_INTEGRITY")

func _test_weapon_resolution_wires_subsystem_damage() -> void:
	var attacker := ShipPhysicsState.new()
	attacker.position = Vector3(1000.0, 0, 0)
	var target := ShipPhysicsState.new()
	target.position = Vector3.ZERO
	target.defense = ShipDefenseState.new()
	target.defense.port_sidewall_condition = 0.4  # allow some damage through
	target.defense.starboard_sidewall_condition = 0.4

	var weapon := WeaponData.new()
	weapon.max_range_m = 100_000.0
	weapon.damage_per_hit = 500.0
	var mount := WeaponMount.new(weapon, WeaponMount.broadside_arc())

	var hull := HullState.new()
	var target_subsystems := ShipSubsystems.new()

	var result := WeaponResolution.fire(attacker, mount, target, hull, target_subsystems)
	_assert(result.damage_dealt > 0.0, "shot should deal some damage for this test setup")
	_assert(not result.subsystem_damage.is_empty(), "WeaponResolution.fire should report subsystem_damage when target_subsystems is passed")

func _test_weapon_resolution_omitting_subsystems_is_backward_compatible() -> void:
	var attacker := ShipPhysicsState.new()
	attacker.position = Vector3(1000.0, 0, 0)
	var target := ShipPhysicsState.new()
	target.position = Vector3.ZERO

	var weapon := WeaponData.new()
	weapon.max_range_m = 100_000.0
	weapon.damage_per_hit = 500.0
	var mount := WeaponMount.new(weapon, WeaponMount.broadside_arc())
	var hull := HullState.new()

	var result := WeaponResolution.fire(attacker, mount, target, hull)
	_assert(result.damage_dealt > 0.0, "legacy call (no target_subsystems) should still deal damage")
	_assert(result.subsystem_damage.is_empty(), "legacy call (no target_subsystems) should report empty subsystem_damage")

func _test_missile_resolution_wires_subsystem_damage() -> void:
	var target := ShipPhysicsState.new()
	target.position = Vector3.ZERO
	target.orientation = Quaternion.IDENTITY

	var missile := MissileState.new()
	missile.position = Vector3(0, 0, -500)
	missile.target = target
	missile.warhead_armed = true

	var hull := HullState.new()
	var target_subsystems := ShipSubsystems.new()
	var result := MissileResolution.resolve_detonation(missile, hull, target_subsystems)
	_assert(result.damage_dealt > 0.0, "detonation against an undefended target should deal damage")
	_assert(not result.subsystem_damage.is_empty(), "MissileResolution.resolve_detonation should report subsystem_damage when target_subsystems is passed")

func _init() -> void:
	_test_no_subsystems_arg_is_noop()
	_test_zero_damage_is_noop()
	_test_sector_maps_to_expected_primary_subsystem()
	_test_structural_integrity_shares_every_hit()
	_test_unclassified_sector_falls_back_to_structural()
	_test_weapon_resolution_wires_subsystem_damage()
	_test_weapon_resolution_omitting_subsystems_is_backward_compatible()
	_test_missile_resolution_wires_subsystem_damage()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
