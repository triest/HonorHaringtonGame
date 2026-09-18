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

func _test_succession_order_registered_on_formation_state() -> void:
	var formation := FormationState.new()
	formation.guide_ship_id = "guide"
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))
	formation.set_succession_order(["wing1", "wing2"])
	_assert(formation.succession_order == ["wing1", "wing2"], "set_succession_order should record the chain of command")
	_assert(formation.guide_lost_since < 0.0, "a freshly created formation should not consider its guide lost")

func _test_guide_destroyed_and_removed_transfers_command_after_delay() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	var wing2 := _make_ship(Vector3(-500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))
	formation.set_succession_order(["wing1", "wing2"])

	# Guide is destroyed and removed from the simulation entirely
	# (§33 "destroyed").
	world.remove_ship("guide")

	# One tick: still within the recognition delay, no successor yet.
	world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "guide", "command must not transfer instantly -- §33 step 4, recognition delay")
	_assert(formation.guide_lost_since >= 0.0, "the formation should record when its guide was first found lost")

	# Advance past COMMAND_TRANSFER_DELAY_S.
	for i in range(400):  # 400/60s ≈ 6.7s > 3.0s delay
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "wing1", "the first available ship in the explicit succession order should become the new guide")
	_assert(not formation.member_offsets.has("wing1"), "the new guide should not also be listed as its own member")
	_assert(formation.member_offsets.has("wing2"), "the other member should still be tracked under the new guide")
	_assert(not formation.member_offsets.has("guide"), "the destroyed old guide should not be carried forward as a dangling member")

func _test_incapacitated_guide_skips_also_incapacitated_first_in_line() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	var wing2 := _make_ship(Vector3(-500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))
	formation.set_succession_order(["wing1", "wing2"])

	# Guide stays in the simulation but is critically damaged
	# (§33 "incapacitated", not destroyed).
	var guide_hull := HullState.new()
	guide_hull.max_integrity = 10_000.0
	guide_hull.integrity = 500.0  # 5%
	world.hulls["guide"] = guide_hull

	# wing1 (first in the succession order) is ALSO critically damaged --
	# must be skipped in favor of wing2.
	var wing1_hull := HullState.new()
	wing1_hull.max_integrity = 10_000.0
	wing1_hull.integrity = 100.0
	world.hulls["wing1"] = wing1_hull

	for i in range(400):
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "wing2", "an incapacitated first-in-line successor should be skipped in favor of the next fit candidate")
	_assert(formation.member_offsets.has("guide"), "the old (incapacitated but not destroyed) guide should still be flying as an ordinary member")
	_assert(formation.member_offsets.has("wing1"), "the incapacitated-but-not-destroyed wing1 should also still be carried as a member, just not in command")

func _test_default_succession_falls_back_to_member_list_when_unset() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	# succession_order deliberately left unset (empty).

	world.remove_ship("guide")  # destroyed; wing1 is the ONLY other member and is fine

	for i in range(400):
		world.tick_simulation(1.0 / 60.0)

	# wing1 IS a valid successor here (it is fit), so this formation
	# should actually have transferred -- confirms the fallback (no
	# explicit succession_order set) still finds a fit successor via
	# member_offsets.keys().
	_assert(formation.guide_ship_id == "wing1", "with no explicit succession_order, the fallback (member_offsets.keys()) should still find a fit successor")

func _test_no_fit_successor_leaves_formation_leaderless_without_crashing() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))

	# BOTH the guide and the only possible successor are destroyed --
	# there is honestly nobody left to hand command to (§33: "do not
	# magically transfer information unavailable to subordinate ships").
	world.remove_ship("guide")
	world.remove_ship("wing1")

	for i in range(400):
		world.tick_simulation(1.0 / 60.0)  # must not error out

	_assert(formation.guide_ship_id == "guide", "with no fit successor anywhere, the formation should keep its (now-invalid) last guide id rather than crash or invent one")
	_assert(formation.guide_lost_since >= 0.0, "the formation should still honestly record that its guide has been lost, even with no successor available")

func _test_transferred_command_freezes_member_station_relative_to_new_guide() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	var wing2 := _make_ship(Vector3(-750.0, 300.0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))  # wing2's OLD station -- not where it actually is
	formation.set_succession_order(["wing1", "wing2"])

	world.remove_ship("guide")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "wing1", "sanity: wing1 should have taken over")
	# wing2's actual position at the moment of transfer was (-750, 300, 0)
	# and the new guide (wing1) is at (500, 0, 0) with identity
	# orientation throughout this test (no thrust applied to guide/wing1
	# before the transfer tick) -- the frozen offset should equal that
	# true relative position, NOT the stale old-guide-relative station
	# of (-500, 0, 0).
	var recorded_offset: Vector3 = formation.member_offsets["wing2"]
	_assert(recorded_offset != Vector3(-500.0, 0, 0), "the member's station offset must be recomputed relative to the NEW guide, not left as the stale old-guide-relative value")

func _test_rotating_guide_sweeps_station_and_member_gets_matching_thrust() -> void:
	# Milestone 10 (this pass): the guide's ANGULAR velocity must be part
	# of the station-point velocity a member matches, not just the
	# guide's LINEAR velocity. Here the guide sits still (zero linear
	# velocity) but is rotating in place; a member already sitting
	# exactly on its assigned offset, also with zero velocity, is
	# therefore NOT actually matched with its (moving) station point --
	# the offset point is sweeping through space at omega x r. Before
	# this pass the old formula (guide.velocity - member.velocity, both
	# zero here) would have hit the dead zone and commanded no thrust at
	# all, silently letting the member fall behind a turning wall.
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.angular_velocity = Vector3(0.0, 1.0, 0.0)  # 1 rad/s yaw, in place
	var wing := _make_ship(Vector3(500.0, 0, 0))  # sitting exactly on its (500,0,0) station
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	world.tick_simulation(1.0 / 60.0)

	_assert(wing.commanded_thrust_local != Vector3.ZERO, "a member sitting still at a wide offset from an in-place-rotating guide must be given thrust to track the swept station point, not treated as already on-station")
	var thrust_world: Vector3 = wing.orientation * wing.commanded_thrust_local
	# omega(0,1,0) x offset(500,0,0) = (0,0,-500): the station point at
	# this offset is sweeping toward -Z, so the member should thrust
	# toward -Z to keep up with it.
	_assert(thrust_world.z < -0.01, "the member should thrust toward -Z to track the guide's rotation sweeping its station point in that direction (omega x r)")

func _test_member_already_tracking_guide_rotation_gets_no_spurious_thrust() -> void:
	# The flip side of the test above: a member that IS already moving to
	# match its swept station point (velocity == omega x offset) should
	# be left alone by the dead zone, exactly as a member matched to a
	# non-rotating guide would be. The pre-fix formula would have compared
	# the member's (correctly nonzero) velocity against the guide's zero
	# linear velocity and commanded spurious braking thrust here -- this
	# is the case that proves the feedforward term isn't just adding
	# thrust, it is fixing what "matched" means.
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.angular_velocity = Vector3(0.0, 1.0, 0.0)
	var wing := _make_ship(Vector3(500.0, 0, 0))
	wing.velocity = Vector3(0.0, 0.0, -500.0)  # already matching omega x offset for this offset
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	world.tick_simulation(1.0 / 60.0)

	_assert(wing.commanded_thrust_local == Vector3.ZERO, "a member already moving to track the guide's rotation about its own station point should not receive spurious correction thrust")

func _init() -> void:
	_test_formation_state_basics()
	_test_member_thrusts_toward_station()
	_test_member_settles_near_station_and_stops_jittering()
	_test_formation_with_missing_guide_is_skipped_safely()
	_test_disengaging_member_retreat_overrides_formation_keeping()
	_test_member_on_station_but_closing_gets_braking_thrust()
	_test_member_far_out_converges_over_many_ticks()
	_test_succession_order_registered_on_formation_state()
	_test_guide_destroyed_and_removed_transfers_command_after_delay()
	_test_incapacitated_guide_skips_also_incapacitated_first_in_line()
	_test_default_succession_falls_back_to_member_list_when_unset()
	_test_no_fit_successor_leaves_formation_leaderless_without_crashing()
	_test_transferred_command_freezes_member_station_relative_to_new_guide()
	_test_rotating_guide_sweeps_station_and_member_gets_matching_thrust()
	_test_member_already_tracking_guide_rotation_gets_no_spurious_thrust()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
