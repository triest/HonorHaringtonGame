extends SceneTree
## Headless test runner for MissileTube + TacticalAI/SimulationWorld's
## missile-launch DECISION slice (ТЗ §26 "launch missiles").
## Run via: godot --headless --path . --script res://simulation/tests/test_missile_launch_ai.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const KinematicsUtils = preload("res://simulation/kinematics_utils.gd")
const MissileState = preload("res://simulation/missile_state.gd")

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

func _test_missile_tube_ready_and_cooldown() -> void:
	var tube := MissileTube.new()
	tube.ammo_count = 2
	tube.reload_time_s = 5.0
	_assert(tube.is_ready(), "a fresh tube (time_since_last_launch_s = INF) with ammo should be ready immediately")

	tube.mark_launched()
	_assert(tube.ammo_count == 1, "mark_launched should consume one round of ammo")
	_assert(not tube.is_ready(), "a tube should not be ready right after launching (cooldown not elapsed)")

	tube.advance(4.9)
	_assert(not tube.is_ready(), "a tube should not be ready just before its reload time elapses")
	tube.advance(0.2)
	_assert(tube.is_ready(), "a tube should be ready again once its reload time has fully elapsed")

	tube.mark_launched()
	tube.advance(100.0)
	_assert(not tube.is_ready(), "a tube out of ammo should never be ready again, no matter how long it waits")

func _test_ai_launches_missile_at_hostile_within_range() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3(1_000_000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")

	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 5_000_000.0  # comfortably covers the 1,000,000 m separation
	world.add_missile_tube("alpha", tube)

	_assert(world.missiles.is_empty(), "no missile should exist before the world ticks")

	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.size() == 1, "alpha's AI should have launched exactly one missile at the hostile beta once its tube was ready and beta was within range")
	_assert(tube.ammo_count == 2, "launching should consume one round from the tube")

	var launched_missile = world.missiles.values()[0]
	_assert(launched_missile.target == beta, "the launched missile's target should be the AI-selected hostile ship, not something else")

func _test_ai_does_not_launch_beyond_tube_range() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3(1_000_000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")

	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 1_000.0  # far shorter than the 1,000,000 m separation
	world.add_missile_tube("alpha", tube)

	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.is_empty(), "a hostile far beyond the tube's max_range_m should not trigger a launch")
	_assert(tube.ammo_count == 3, "ammo should be untouched when no launch happened")

func _test_ai_does_not_launch_without_a_team_or_hostile() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3(1_000_000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	# No teams assigned to either ship -- beta is neutral to alpha.

	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 5_000_000.0
	world.add_missile_tube("alpha", tube)

	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.is_empty(), "no team assigned should mean no launch, same rule as weapons fire (no default-hostile fallback)")
	_assert(tube.ammo_count == 3, "the tube's own cooldown/ammo state should still be tracked even though it did not fire")

func _test_disengaging_ship_does_not_launch() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3(1_000_000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")

	var alpha_hull := HullState.new()
	alpha_hull.max_integrity = 10_000.0
	alpha_hull.integrity = 500.0  # 5% -- critically damaged, should be disengaging
	world.hulls["alpha"] = alpha_hull

	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 5_000_000.0
	world.add_missile_tube("alpha", tube)

	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.is_empty(), "a critically damaged, disengaging ship should not launch new missiles at a hostile")

## ТЗ §34.2 Missile Time-on-Target: two formation-mates at DIFFERENT
## ranges to the SAME §34.1-assigned hostile should NOT both launch the
## instant they are ready -- the farther ship (longer flight time) is the
## "pacing shot" and fires immediately, while the nearer ship (shorter
## flight time, would otherwise arrive EARLY and alone) is held back so
## its missile is estimated to land at the same time as the pacing shot's.
func _test_formation_mates_stagger_missile_launch_for_simultaneous_arrival() -> void:
	var world := SimulationWorld.new()
	# "guide" is far from the hostile (long flight time -- the pacing shot);
	# "wing" is much closer (short flight time -- should be held).
	var guide := _make_ship(Vector3(2_000_000.0, 0, 0))
	var wing := _make_ship(Vector3(500_000.0, 0, 0))
	var hostile := _make_ship(Vector3.ZERO)
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	world.add_ship("hostile", hostile)
	world.set_team("guide", "red")
	world.set_team("wing", "red")
	world.set_team("hostile", "blue")
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(-1_500_000.0, 0, 0))

	var guide_tube := MissileTube.new()
	guide_tube.ammo_count = 1
	guide_tube.reload_time_s = 0.0
	guide_tube.max_range_m = 10_000_000.0
	world.add_missile_tube("guide", guide_tube)

	var wing_tube := MissileTube.new()
	wing_tube.ammo_count = 1
	wing_tube.reload_time_s = 0.0
	wing_tube.max_range_m = 10_000_000.0
	world.add_missile_tube("wing", wing_tube)

	var dt := 1.0 / 60.0
	world.tick_simulation(dt)

	_assert(world.missiles.size() == 1, "only the farther ship (the pacing shot) should launch on the very first tick, not both formation-mates at once")
	_assert(guide_tube.ammo_count == 0, "the far ship (guide) should be the one that fired immediately -- it has the longer flight time and needs no hold")
	_assert(wing_tube.ammo_count == 1, "the near ship (wing) should be HELD this tick, not fire immediately, so its shorter-flight-time missile doesn't arrive early and alone")
	_assert(world._missile_salvo_fire_at.has("wing"), "the near ship should have a §34.2 scheduled hold entry")
	_assert(not world._missile_salvo_fire_at.has("guide"), "the pacing shot (far ship) needs no schedule -- it already fired")

	# Compute the expected hold with the exact same formula the production
	# code uses, then verify the actual scheduled fire_at matches it.
	var guide_flight_time: float = KinematicsUtils.estimate_boost_coast_time_to_distance_s(2_000_000.0, MissileState.DEFAULT_DRIVE_MAX_ACCELERATION_MPS2, MissileState.DEFAULT_DRIVE_BURN_TIME_S)
	var wing_flight_time: float = KinematicsUtils.estimate_boost_coast_time_to_distance_s(500_000.0, MissileState.DEFAULT_DRIVE_MAX_ACCELERATION_MPS2, MissileState.DEFAULT_DRIVE_BURN_TIME_S)
	var expected_hold: float = guide_flight_time - wing_flight_time
	_assert(expected_hold > 0.0, "sanity: the closer ship's missile really should be faster than the farther ship's")
	var scheduled_fire_at: float = world._missile_salvo_fire_at["wing"]["fire_at"]
	_assert(is_equal_approx(scheduled_fire_at, dt + expected_hold), "the scheduled fire_at should be now (after this tick's world_sim_time advance) plus exactly (far flight time - near flight time), the boost-coast estimate two missiles need to land together")

	# Advance time until just before the hold should elapse -- wing must
	# still not have fired.
	var ticks_before: int = int((expected_hold - 0.05) / dt)
	for i in range(ticks_before):
		world.tick_simulation(dt)
	_assert(wing_tube.ammo_count == 1, "the held ship must not fire before its scheduled coordinated launch time")

	# Advance past the hold -- wing should now fire.
	for i in range(20):
		world.tick_simulation(dt)
		if wing_tube.ammo_count < 1:
			break
	_assert(wing_tube.ammo_count == 0, "the held ship should fire once its scheduled §34.2 coordinated launch time arrives")
	_assert(not world._missile_salvo_fire_at.has("wing"), "the schedule entry should be consumed (erased) once the held shot actually fires")
	_assert(world.missiles.size() == 2, "both formation-mates should have launched exactly one missile each by now")

## A single ship (no formation-mate also targeting the same hostile this
## tick) must fire the instant it is ready -- §34.2 coordination must
## degenerate to old behavior exactly like §34.1 already does, not
## introduce an unexplained hold for a lone shooter.
func _test_lone_formation_member_still_fires_immediately() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3(1_000_000.0, 0, 0))
	var hostile := _make_ship(Vector3.ZERO)
	world.add_ship("guide", guide)
	world.add_ship("hostile", hostile)
	world.set_team("guide", "red")
	world.set_team("hostile", "blue")
	world.add_formation("red_wall", "guide")  # a formation of exactly one member

	var tube := MissileTube.new()
	tube.ammo_count = 2
	tube.reload_time_s = 0.0
	tube.max_range_m = 10_000_000.0
	world.add_missile_tube("guide", tube)

	world.tick_simulation(1.0 / 60.0)

	_assert(world.missiles.size() == 1, "a lone formation member with no one else sharing its target should launch immediately, unaffected by §34.2")
	_assert(not world._missile_salvo_fire_at.has("guide"), "a lone shooter should never get a coordination hold entry")

## §34.2's schedule must not survive a §30 manual target override that
## redirects the held ship at a DIFFERENT hostile before its hold
## elapses -- holding a shot timed for hostile A makes no sense once the
## ship's actual target this tick is hostile B.
func _test_manual_target_override_cancels_a_stale_tot_hold() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3(2_000_000.0, 0, 0))
	var wing := _make_ship(Vector3(500_000.0, 0, 0))
	var hostile_a := _make_ship(Vector3.ZERO)
	var hostile_b := _make_ship(Vector3(500_000.0, 0, 2_000_000.0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	world.add_ship("hostile_a", hostile_a)
	world.add_ship("hostile_b", hostile_b)
	world.set_team("guide", "red")
	world.set_team("wing", "red")
	world.set_team("hostile_a", "blue")
	world.set_team("hostile_b", "blue")
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(-1_500_000.0, 0, 0))

	var guide_tube := MissileTube.new()
	guide_tube.ammo_count = 1
	guide_tube.reload_time_s = 0.0
	guide_tube.max_range_m = 10_000_000.0
	world.add_missile_tube("guide", guide_tube)

	var wing_tube := MissileTube.new()
	wing_tube.ammo_count = 1
	wing_tube.reload_time_s = 0.0
	wing_tube.max_range_m = 10_000_000.0
	world.add_missile_tube("wing", wing_tube)

	world.tick_simulation(1.0 / 60.0)
	_assert(world._missile_salvo_fire_at.has("wing"), "sanity: wing should be holding a §34.2 schedule against hostile_a, same setup as the main staggered-launch test")

	# Redirect wing at hostile_b via a §30 manual designation -- this now
	# outranks the §34.1 formation assignment the stale hold was built for.
	world.set_ship_target("wing", "hostile_b")
	world.tick_simulation(1.0 / 60.0)

	_assert(wing_tube.ammo_count == 0, "wing should fire immediately at its newly-designated target instead of continuing to hold a schedule timed for the old one")
	var wing_missile = null
	for m in world.missiles.values():
		if m.target == hostile_b:
			wing_missile = m
	_assert(wing_missile != null, "the missile wing actually launched should be aimed at the manually-designated hostile_b, not the stale hostile_a schedule's target")

func _init() -> void:
	_test_missile_tube_ready_and_cooldown()
	_test_ai_launches_missile_at_hostile_within_range()
	_test_ai_does_not_launch_beyond_tube_range()
	_test_ai_does_not_launch_without_a_team_or_hostile()
	_test_disengaging_ship_does_not_launch()
	_test_formation_mates_stagger_missile_launch_for_simultaneous_arrival()
	_test_lone_formation_member_still_fires_immediately()
	_test_manual_target_override_cancels_a_stale_tot_hold()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
