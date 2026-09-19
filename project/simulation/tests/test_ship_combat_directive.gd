extends SceneTree
## Headless test runner for ShipCombatDirective + SimulationWorld's §30
## "target"/"target priority"/"weapon mode" slice (Milestone 11, second
## slice). Run via: godot --headless --path . --script res://simulation/tests/test_ship_combat_directive.gd
##
## Deliberately full-tick (`SimulationWorld.tick_simulation`) integration
## tests, not just unit tests of ShipCombatDirective's own trivial getters/
## setters (see test_tactical_ai.gd for the unit-level
## select_directed_weapon_target coverage) -- the actual behavior this
## pass adds only exists at the seam between ShipCombatDirective,
## SimulationWorld._resolve_weapon_target, and the pre-existing
## _resolve_weapons_ai/_resolve_missile_launch_ai loops, exactly the kind
## of stitch-point bug AGENTS.md asks every new mechanic's tests to cover.

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipCombatDirective = preload("res://simulation/ship_combat_directive.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")

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
	return s

func _make_hull() -> HullState:
	var h := HullState.new()
	h.max_integrity = 1000.0
	h.integrity = 1000.0
	return h

func _make_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.id = "test_laser"
	w.max_range_m = 5_000_000.0  # comfortably covers every distance used below
	w.damage_per_hit = 100.0
	w.recharge_time_s = 4.0
	return w

## Both hostiles sit along -Z from alpha (bow) so a bow-chaser mount's arc
## check never interferes -- this test is about TARGET selection, not
## firing arcs (already covered by test_weapon_resolution.gd).
func _test_directive_defaults_to_automatic_and_free_fire() -> void:
	var directive := ShipCombatDirective.new()
	_assert(directive.manual_target_ship_id == "", "a fresh ShipCombatDirective should have no manual target designated")
	_assert(directive.weapons_free == true, "a fresh ShipCombatDirective should default to weapons free -- identical to all pre-existing behavior")

func _test_no_manual_target_hits_nearest_hostile() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	var near_hull := _make_hull()
	var far_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("near", near, near_hull)
	world.add_ship("far", far, far_hull)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))

	world.tick_simulation(1.0 / 60.0)

	_assert(near_hull.integrity < 1000.0, "with no manual target designated, the pre-existing automatic nearest-hostile selection should still fire on the nearer ship")
	_assert(far_hull.integrity == 1000.0, "the farther hostile should be untouched when no manual target overrides the automatic nearest pick")

func _test_manual_target_overrides_nearest_selection() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	var near_hull := _make_hull()
	var far_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("near", near, near_hull)
	world.add_ship("far", far, far_hull)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))

	world.set_ship_target("alpha", "far")
	world.tick_simulation(1.0 / 60.0)

	_assert(far_hull.integrity < 1000.0, "a manually designated target should be fired on even though it is not the nearest hostile")
	_assert(near_hull.integrity == 1000.0, "the nearer, non-designated hostile should be left alone while a manual designation is active")

func _test_clear_ship_target_reverts_to_automatic() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	var near_hull := _make_hull()
	var far_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("near", near, near_hull)
	world.add_ship("far", far, far_hull)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))

	world.set_ship_target("alpha", "far")
	world.clear_ship_target("alpha")
	world.tick_simulation(1.0 / 60.0)

	_assert(near_hull.integrity < 1000.0, "clearing a manual target should revert to automatic nearest-hostile selection")
	_assert(far_hull.integrity == 1000.0, "after clearing the manual designation, the previously-designated farther ship should no longer be singled out")

func _test_manual_target_falls_back_when_destroyed_before_tick() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var designated := _make_ship(Vector3(0, 0, -700_000.0))
	var fallback := _make_ship(Vector3(0, 0, -500_000.0))
	var fallback_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("designated", designated)
	world.add_ship("fallback", fallback, fallback_hull)
	world.set_team("alpha", "red")
	world.set_team("designated", "blue")
	world.set_team("fallback", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))

	world.set_ship_target("alpha", "designated")
	world.remove_ship("designated")  # destroyed/removed before this tick resolves
	world.tick_simulation(1.0 / 60.0)

	_assert(fallback_hull.integrity < 1000.0, "once a manually designated target is gone, weapon target selection should honestly fall back to automatic selection among the remaining hostiles, not silently hold fire")

func _test_hold_fire_suppresses_energy_weapons() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	var beta_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta, beta_hull)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	var mount := WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc())
	world.add_weapon_mount("alpha", mount)

	world.set_ship_weapons_free("alpha", false)
	world.tick_simulation(1.0 / 60.0)

	_assert(beta_hull.integrity == 1000.0, "a ship under a hold-fire directive should not fire its energy weapons even at a valid, in-range, in-arc hostile")
	_assert(mount.cooldown_remaining_s == 0.0, "a held-fire mount should never have been triggered at all, so its cooldown should be untouched")

func _test_hold_fire_suppresses_missile_launch_but_still_advances_cooldown() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0  # ready regardless of time_since_last_launch_s
	tube.max_range_m = 5_000_000.0
	tube.time_since_last_launch_s = 100.0  # finite, so advance() is observable below; tube is still READY (reload_time_s is 0)
	world.add_missile_tube("alpha", tube)

	world.set_ship_weapons_free("alpha", false)
	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.is_empty(), "a ship under a hold-fire directive should not launch missiles even from a fully ready tube at a valid, in-range hostile")
	_assert(tube.ammo_count == 3, "a held-fire tube should not have consumed any ammo")
	_assert(tube.time_since_last_launch_s > 100.0, "a held-fire tube's cooldown should still advance every tick -- holding fire is a fire-control decision, not equipment damage")

func _test_manual_target_applies_to_missile_launch_too() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("near", near)
	world.add_ship("far", far)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 5_000_000.0
	world.add_missile_tube("alpha", tube)

	world.set_ship_target("alpha", "far")
	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.size() == 1, "a manually designated target should still lead to exactly one launch when a tube is ready and the target is in range")
	var launched_missile = world.missiles.values()[0]
	_assert(launched_missile.target == far, "the launched missile should target the manually designated ship, not the automatically-nearest one")

func _test_set_and_clear_target_mutate_directive_state() -> void:
	var world := SimulationWorld.new()
	world.set_ship_target("alpha", "bravo")
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "bravo", "set_ship_target should record the designation on this ship's combat directive")
	world.clear_ship_target("alpha")
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "", "clear_ship_target should remove the designation")

func _test_set_weapons_free_mutates_directive_state() -> void:
	var world := SimulationWorld.new()
	world.set_ship_weapons_free("alpha", false)
	_assert(world.ship_combat_directives["alpha"].weapons_free == false, "set_ship_weapons_free(false) should record hold-fire on this ship's combat directive")
	world.set_ship_weapons_free("alpha", true)
	_assert(world.ship_combat_directives["alpha"].weapons_free == true, "set_ship_weapons_free(true) should restore free-fire")

func _test_remove_ship_erases_its_combat_directive() -> void:
	var world := SimulationWorld.new()
	world.set_ship_target("alpha", "bravo")
	_assert(world.ship_combat_directives.has("alpha"), "sanity check: the directive should exist before removal")
	world.remove_ship("alpha")
	_assert(not world.ship_combat_directives.has("alpha"), "removing a ship should erase its combat directive along with its other per-ship state")

func _init() -> void:
	_test_directive_defaults_to_automatic_and_free_fire()
	_test_no_manual_target_hits_nearest_hostile()
	_test_manual_target_overrides_nearest_selection()
	_test_clear_ship_target_reverts_to_automatic()
	_test_manual_target_falls_back_when_destroyed_before_tick()
	_test_hold_fire_suppresses_energy_weapons()
	_test_hold_fire_suppresses_missile_launch_but_still_advances_cooldown()
	_test_manual_target_applies_to_missile_launch_too()
	_test_set_and_clear_target_mutate_directive_state()
	_test_set_weapons_free_mutates_directive_state()
	_test_remove_ship_erases_its_combat_directive()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
