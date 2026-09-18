extends SceneTree
## Headless test runner for the §25 Subsystem Damage consumers wired this
## pass: WEAPONS/POINT_DEFENSE/MISSILE_SYSTEMS condition now synced each
## tick from ShipSubsystems into WeaponMount/PointDefenseMount/MissileTube
## (SimulationWorld._sync_subsystem_driven_conditions), and
## COUNTER_MISSILE_SYSTEMS now scaling CounterMissileResolution's
## effective kill radius via the counter-missile's launching ship. Closes
## 4 of the 8 previously-honest "no consumer wired" gaps recorded in
## ASSUMPTIONS.md/ship_subsystems.gd.
## Run via: godot --headless --path . --script res://simulation/tests/test_subsystem_damage_consumers.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const CounterMissileResolution = preload("res://simulation/counter_missile_resolution.gd")

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
	s.defense = ShipDefenseState.new()
	s.subsystems = ShipSubsystems.new()
	return s

func _test_weapon_mount_condition_synced_and_reduces_damage() -> void:
	var world := SimulationWorld.new()
	# Attacker at +Z, target at origin: per AttackGeometry's convention
	# (-Z = bow), the target sits at the attacker's BOW, so a bow-chaser
	# mount can bear on it.
	var attacker := _make_ship(Vector3(0, 0, 100.0))
	# Deliberately no `defense` on the target (left null): routes
	# WeaponResolution.fire() through its HIT_UNPROTECTED path, which
	# transmits 100% of damage -- makes the expected damage_dealt a
	# simple, deterministic function of mount.condition alone, rather
	# than also depending on wedge/sidewall geometry resolution (already
	# covered by weapon_resolution's own tests).
	var target := ShipPhysicsState.new()
	target.position = Vector3.ZERO
	world.add_ship("attacker", attacker)
	world.add_ship("target", target)

	var weapon := WeaponData.new()
	weapon.damage_per_hit = 200.0
	weapon.max_range_m = 10_000.0
	var mount := WeaponMount.new(weapon, WeaponMount.bow_chaser_arc())
	world.add_weapon_mount("attacker", mount)

	# Halve the attacker's WEAPONS subsystem before any tick runs.
	attacker.subsystems.apply_damage(SubsystemType.Type.WEAPONS, 0.5)  # condition -> 0.5
	world.tick_simulation(1.0 / 60.0)
	_assert(is_equal_approx(mount.condition, 0.5), "mount.condition should be synced from the ship's WEAPONS subsystem condition each tick")

	# Fire directly (bow chaser vs a target dead ahead) and confirm the
	# actual damage output is halved by the synced mount.condition.
	mount.cooldown_remaining_s = 0.0
	var result = world.fire_weapon("attacker", mount, "target")
	_assert(is_equal_approx(result.damage_dealt, 100.0), "damaged WEAPONS subsystem should proportionally reduce actual weapon damage output (200 * 0.5 = 100), got %s" % result.damage_dealt)

func _test_weapon_mount_disabled_when_weapons_subsystem_destroyed() -> void:
	var world := SimulationWorld.new()
	var attacker := _make_ship(Vector3(0, 0, -100.0))
	var target := _make_ship(Vector3.ZERO)
	world.add_ship("attacker", attacker)
	world.add_ship("target", target)

	var weapon := WeaponData.new()
	weapon.max_range_m = 10_000.0
	var mount := WeaponMount.new(weapon, WeaponMount.bow_chaser_arc())
	world.add_weapon_mount("attacker", mount)

	attacker.subsystems.apply_damage(SubsystemType.Type.WEAPONS, 1.0)  # fully disabled
	world.tick_simulation(1.0 / 60.0)
	_assert(mount.condition == 0.0, "fully disabled WEAPONS subsystem should zero out mount.condition")
	_assert(not mount.is_ready(), "a mount with condition 0.0 should not be ready to fire")

func _test_ship_with_no_subsystems_leaves_mount_condition_untouched() -> void:
	var world := SimulationWorld.new()
	var attacker := ShipPhysicsState.new()  # subsystems left null, pre-§25 behavior
	world.add_ship("attacker", attacker)
	var mount := WeaponMount.new(WeaponData.new(), WeaponMount.bow_chaser_arc())
	mount.condition = 0.73
	world.add_weapon_mount("attacker", mount)

	world.tick_simulation(1.0 / 60.0)
	_assert(is_equal_approx(mount.condition, 0.73), "a ship with subsystems == null should never have its mounts' condition touched by the sync step")

func _test_point_defense_mount_condition_synced_and_gates_readiness() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	world.add_ship("defender", ship)
	var pd := PointDefenseMount.new()
	world.add_pd_mount("defender", pd)

	ship.subsystems.apply_damage(SubsystemType.Type.POINT_DEFENSE, 1.0)  # fully disabled
	world.tick_simulation(1.0 / 60.0)
	_assert(pd.condition == 0.0, "PointDefenseMount.condition should be synced from the ship's POINT_DEFENSE subsystem")
	_assert(not pd.is_ready(), "a PD mount with condition 0.0 should not be ready to engage")

func _test_missile_tube_condition_synced_and_gates_readiness() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	world.add_ship("launcher", ship)
	var tube := MissileTube.new()
	world.add_missile_tube("launcher", tube)

	ship.subsystems.apply_damage(SubsystemType.Type.MISSILE_SYSTEMS, 1.0)  # fully disabled
	world.tick_simulation(1.0 / 60.0)
	_assert(tube.condition == 0.0, "MissileTube.condition should be synced from the ship's MISSILE_SYSTEMS subsystem")
	_assert(not tube.is_ready(), "a missile tube with condition 0.0 should not be ready to launch, even with ammo and no cooldown")

func _test_counter_missile_kill_radius_scaled_by_owner_condition() -> void:
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -4000.0)
	var cm := MissileState.new()
	cm.target = incoming
	cm.position = Vector3.ZERO
	# Distance is 4000m: within the full 5000m radius, but not within a
	# radius halved by a degraded COUNTER_MISSILE_SYSTEMS condition.
	var result_undamaged := CounterMissileResolution.check_intercept(cm, incoming, 1.0)
	_assert(result_undamaged.outcome == CounterMissileResolution.Outcome.INTERCEPTED, "full COUNTER_MISSILE_SYSTEMS condition should intercept at 4000m (within the 5000m nominal radius)")

	var incoming2 := MissileState.new()
	incoming2.position = Vector3(0, 0, -4000.0)
	var cm2 := MissileState.new()
	cm2.target = incoming2
	cm2.position = Vector3.ZERO
	var result_damaged := CounterMissileResolution.check_intercept(cm2, incoming2, 0.5)
	_assert(result_damaged.outcome == CounterMissileResolution.Outcome.TOO_FAR, "halved COUNTER_MISSILE_SYSTEMS condition should shrink the effective kill radius to 2500m, missing at 4000m")

func _test_counter_missile_default_condition_backward_compatible() -> void:
	# Every pre-existing caller (test_counter_missile.gd, etc.) calls
	# check_intercept with only 2 args -- must behave exactly as before.
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -1000.0)
	var cm := MissileState.new()
	cm.target = incoming
	cm.position = Vector3.ZERO
	var result = CounterMissileResolution.check_intercept(cm, incoming)
	_assert(result.outcome == CounterMissileResolution.Outcome.INTERCEPTED, "omitting counter_missile_system_condition should default to 1.0 (full nominal radius), unchanged pre-§25 behavior")

func _test_world_resolves_counter_missile_owner_condition_via_missile_owners() -> void:
	var world := SimulationWorld.new()
	var launcher := _make_ship(Vector3.ZERO)
	world.add_ship("launcher", launcher)
	launcher.subsystems.apply_damage(SubsystemType.Type.COUNTER_MISSILE_SYSTEMS, 1.0)  # fully disabled -> radius 0

	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -10.0)  # well within the nominal 5000m radius
	var cm := MissileState.new()
	cm.position = Vector3.ZERO
	cm.target = incoming
	world.add_missile("cm1", cm, "launcher")
	world.add_missile("incoming1", incoming, "")

	world.tick_simulation(1.0 / 60.0)
	_assert(cm.is_active() and incoming.is_active(), "a counter-missile owned by a ship with fully disabled COUNTER_MISSILE_SYSTEMS should fail to intercept even at point-blank range (effective radius scaled to 0)")

func _init() -> void:
	_test_weapon_mount_condition_synced_and_reduces_damage()
	_test_weapon_mount_disabled_when_weapons_subsystem_destroyed()
	_test_ship_with_no_subsystems_leaves_mount_condition_untouched()
	_test_point_defense_mount_condition_synced_and_gates_readiness()
	_test_missile_tube_condition_synced_and_gates_readiness()
	_test_counter_missile_kill_radius_scaled_by_owner_condition()
	_test_counter_missile_default_condition_backward_compatible()
	_test_world_resolves_counter_missile_owner_condition_via_missile_owners()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
