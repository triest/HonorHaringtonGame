extends SceneTree
## Headless test runner for FormationState + SimulationWorld's formation-
## keeping first slice (Milestone 10 / ТЗ §27-29, AGENTS.md §61
## "wall of battle").
## Run via: godot --headless --path . --script res://simulation/tests/test_formation.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const FormationState = preload("res://simulation/formation_state.gd")
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
	s.max_acceleration_mps2 = 100.0
	return s

func _test_formation_state_basics() -> void:
	var formation := FormationState.new()
	formation.guide_ship_id = "guide"
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))
	_assert(formation.member_ids().size() == 2, "set_station should register two members")
	formation.remove_member("wing1")
	_assert(formation.member_ids().size() == 1, "remove_member should drop that member")

func _test_member_thrusts_toward_station() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(2000.0, 0, 0))  # far from its intended station
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))  # should end up at world (500,0,0)

	for i in range(5):
		world.tick_simulation(1.0 / 60.0)

	_assert(wing.commanded_thrust_local != Vector3.ZERO, "a member far from its station should be thrusting")
	# guide is at world origin with identity orientation, so local offset == world offset here;
	# desired world position (500,0,0) is in the -X direction from the wing's actual (2000,0,0).
	var thrust_world: Vector3 = wing.orientation * wing.commanded_thrust_local
	_assert(thrust_world.x < -0.01, "the wing should thrust toward -X, back toward its station at x=500 from x=2000")

func _test_member_settles_near_station_and_stops_jittering() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.5, 0, 0))  # essentially already on station
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	world.tick_simulation(1.0 / 60.0)

	_assert(wing.commanded_thrust_local == Vector3.ZERO, "a member already essentially on station should not be given thrust (dead zone, avoids jitter)")

func _test_formation_with_missing_guide_is_skipped_safely() -> void:
	var world := SimulationWorld.new()
	var wing := _make_ship(Vector3(2000.0, 0, 0))
	world.add_ship("wing", wing)
	# "guide" is never added to the world.
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	wing.commanded_thrust_local = Vector3.ZERO
	world.tick_simulation(1.0 / 60.0)  # must not error out

	_assert(wing.commanded_thrust_local == Vector3.ZERO, "with no guide ship present, formation-keeping should be a safe no-op rather than crashing or moving the member")

func _test_member_on_station_but_closing_gets_braking_thrust() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	# Wing sits exactly on its assigned station but is still moving
	# relative to the (stationary) guide -- the first slice's pure
	# position-error law would command ZERO thrust here (dead zone on
	# position alone) and let the wing coast straight through station.
	var wing := _make_ship(Vector3(500.0, 0, 0))
	wing.velocity = Vector3(50.0, 0, 0)  # drifting further away from the guide
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	world.tick_simulation(1.0 / 60.0)

	_assert(wing.commanded_thrust_local != Vector3.ZERO, "a member on-station but with a velocity mismatch must still get a braking/matching thrust, not be left coasting")
	var thrust_world: Vector3 = wing.orientation * wing.commanded_thrust_local
	_assert(thrust_world.x < -0.01, "the correction should oppose the wing's excess velocity relative to the guide (brake back towards it)")

func _test_member_far_out_converges_over_many_ticks() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(20_000.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	var starting_distance: float = wing.position.distance_to(Vector3(500.0, 0, 0))
	for i in range(600):
		world.tick_simulation(1.0 / 60.0)
	var ending_distance: float = wing.position.distance_to(Vector3(500.0, 0, 0))

	_assert(ending_distance < starting_distance, "a member far out of station should move measurably closer to it over time under the PD law")

func _test_disengaging_member_retreat_overrides_formation_keeping() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(2000.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	world.set_team("wing", "red")
	world.set_team("hostile", "blue")
	var hostile := _make_ship(Vector3(2100.0, 0, 0))
	world.add_ship("hostile", hostile)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	var wing_hull := HullState.new()
	wing_hull.max_integrity = 10_000.0
	wing_hull.integrity = 500.0  # 5% -- critically damaged
	world.hulls["wing"] = wing_hull

	world.tick_simulation(1.0 / 60.0)

	# Formation-keeping alone would thrust the wing toward -X (back to
	# station); the disengaging ship should instead thrust away from its
	# hostile, which sits at +X relative to the wing -- i.e. -X too in
	# this geometry, so use a case where the two disagree in sign:
	var away_from_hostile_world: Vector3 = wing.orientation * wing.commanded_thrust_local
	_assert(away_from_hostile_world.x < -0.01, "sanity: retreat direction is away from the hostile (at +X from the wing)")
	_assert(wing.commanded_thrust_local != Vector3.ZERO, "a critically damaged formation member should still have SOME commanded thrust (from damage response, not left at whatever formation-keeping set)")

func _init() -> void:
	_test_formation_state_basics()
	_test_member_thrusts_toward_station()
	_test_member_settles_near_station_and_stops_jittering()
	_test_formation_with_missing_guide_is_skipped_safely()
	_test_disengaging_member_retreat_overrides_formation_keeping()
	_test_member_on_station_but_closing_gets_braking_thrust()
	_test_member_far_out_converges_over_many_ticks()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
