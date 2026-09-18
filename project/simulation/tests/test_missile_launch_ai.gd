extends SceneTree
## Headless test runner for MissileTube + TacticalAI/SimulationWorld's
## missile-launch DECISION slice (ТЗ §26 "launch missiles").
## Run via: godot --headless --path . --script res://simulation/tests/test_missile_launch_ai.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")

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

func _init() -> void:
	_test_missile_tube_ready_and_cooldown()
	_test_ai_launches_missile_at_hostile_within_range()
	_test_ai_does_not_launch_beyond_tube_range()
	_test_ai_does_not_launch_without_a_team_or_hostile()
	_test_disengaging_ship_does_not_launch()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
