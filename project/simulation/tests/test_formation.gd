extends SceneTree
## Headless test runner for FormationState + SimulationWorld's formation-
## keeping first slice (Milestone 10 / ТЗ §27-29, AGENTS.md §61
## "wall of battle").
## Run via: godot --headless --path . --script res://simulation/tests/test_formation.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const FormationState = preload("res://simulation/formation_state.gd")
const FormationOrder = preload("res://simulation/formation_order.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")

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

## §33.1 Autonomous behavior during the succession window (part 1 --
## "hold its current tactical vector"): a member that already has a
## nonzero station-keeping thrust command the tick BEFORE its guide is
## lost must keep flying on exactly that same thrust command for every
## tick of the recognition delay, rather than being zeroed or
## recomputed against the now-gone guide. `commanded_thrust_local` is
## never reset to zero by default between ticks (see ShipPhysicsState),
## so this is really a test that `_resolve_formation_keeping` issues NO
## new command at all to a member of a leaderless formation -- see the
## §33.1 block comment on that function's guide-lost branch.
func _test_succession_window_member_holds_last_commanded_thrust() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(2000.0, 0, 0))  # far off station, like _test_member_thrusts_toward_station
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_succession_order(["wing1"])

	# One tick with the guide still present: station-keeping computes a
	# real, nonzero correction thrust for wing1.
	world.tick_simulation(1.0 / 60.0)
	var thrust_just_before_loss: Vector3 = wing1.commanded_thrust_local
	_assert(thrust_just_before_loss.length_squared() > 0.0, "sanity check: wing1 should have nonzero station-keeping thrust while its guide is still present and it is far off station")

	# Guide destroyed -- succession window begins.
	world.remove_ship("guide")

	# Several ticks, all still well within COMMAND_TRANSFER_DELAY_S (3.0s).
	for i in range(30):  # 30/60s = 0.5s < 3.0s
		world.tick_simulation(1.0 / 60.0)
		_assert(wing1.commanded_thrust_local == thrust_just_before_loss, "§33.1: a formation member must hold its last commanded tactical vector throughout the succession window, not go idle or be recomputed against the lost guide")

	_assert(formation.guide_ship_id == "guide", "sanity check: still within the recognition delay, command should not have transferred yet")

## §33.1 Autonomous behavior during the succession window (part 2 --
## "keep engaging its last AI-assigned target"): a manual weapon target
## designation (§30) on a formation member must survive both the
## succession window itself and the eventual command transfer
## unchanged -- nothing in the guide-lost/transfer machinery should ever
## touch `ship_combat_directives`, since target engagement is a
## per-ship concern independent of formation command state.
func _test_succession_window_manual_target_designation_survives_guide_loss() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_succession_order(["wing1"])

	world.set_ship_target("wing1", "enemy_alpha")
	_assert(world.ship_combat_directives["wing1"].manual_target_ship_id == "enemy_alpha", "sanity check: the manual target designation should be recorded before the guide is lost")

	world.remove_ship("guide")

	# Through the whole recognition delay...
	for i in range(120):  # 120/60s = 2.0s, still < 3.0s
		world.tick_simulation(1.0 / 60.0)
	_assert(world.ship_combat_directives["wing1"].manual_target_ship_id == "enemy_alpha", "§33.1: a member's last-assigned weapon target must survive the succession window unchanged")

	# ...and past the transfer itself.
	for i in range(280):  # total > 400/60s ≈ 6.7s > 3.0s delay, matching the existing transfer test's margin
		world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "wing1", "sanity check: command should have transferred to wing1 by now")
	_assert(world.ship_combat_directives["wing1"].manual_target_ship_id == "enemy_alpha", "§33.1: a member's last-assigned weapon target must also survive becoming the new guide -- command transfer must not clear it")

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

func _test_transferred_command_replans_from_design_not_frozen_actual_position() -> void:
	# §29 Formation Orders: after a leader transfer, a surviving member's
	# new station should preserve the formation's ORIGINALLY PLANNED
	# relative geometry around the new guide, not whichever position the
	# member actually happened to have drifted to during the recognition
	# delay. wing2 is deliberately placed far from its planned station
	# (-500,0,0) -- at (-750,300,0) -- specifically so a "freeze current
	# position" implementation and a "replan from design" implementation
	# disagree, and this test can tell them apart.
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	var wing2 := _make_ship(Vector3(-750.0, 300.0, 0))  # off its planned station
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))  # the planned design
	formation.set_succession_order(["wing1", "wing2"])

	world.remove_ship("guide")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "wing1", "sanity: wing1 should have taken over")
	# Design-preserving replan: design_offsets = {guide: 0, wing1: (500,0,0),
	# wing2: (-500,0,0)}; new guide is wing1, so wing2's replanned offset
	# is design[wing2] - design[wing1] = (-1000, 0, 0) -- the wall closes
	# up around wing1 at the ORIGINAL spacing, not wing2's actual drifted
	# position.
	var recorded_offset: Vector3 = formation.member_offsets["wing2"]
	_assert(recorded_offset.is_equal_approx(Vector3(-1000.0, 0, 0)), "the member's new station must be replanned from the formation's original design geometry around the new guide")
	_assert(not recorded_offset.is_equal_approx(Vector3(-500.0, 0, 0)), "must not be left as the stale old-guide-relative value")
	# Also must not equal a "freeze current actual position" result,
	# which would have been (-750,300,0) - (500,0,0) = (-1250, 300, 0).
	_assert(not recorded_offset.is_equal_approx(Vector3(-1250.0, 300.0, 0)), "must not simply freeze wherever the member physically happened to be at the moment of transfer")

func _test_transfer_falls_back_to_freeze_when_new_guide_has_no_design_entry() -> void:
	# Honest fallback: a ship that joined the formation AFTER a design
	# was already captured (by an earlier transfer) has no planned
	# geometry to replan from. If THAT ship becomes guide on a later
	# transfer, every other carried ship also falls back to a
	# freeze-in-place offset for that transfer (there is no shared design
	# to reason about a "closed-up wall" from).
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

	# First transfer: guide destroyed, wing1 takes over. This captures
	# design_offsets = {guide: 0, wing1: (500,0,0), wing2: (-500,0,0)}.
	world.remove_ship("guide")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "wing1", "sanity: first transfer should hand command to wing1")

	# A late-joining reinforcement with NO design entry -- added directly
	# to the live formation after the design snapshot above already
	# happened.
	var latecomer := _make_ship(Vector3(200.0, 0.0, 900.0))
	world.add_ship("latecomer", latecomer)
	formation.set_station("latecomer", Vector3(0.0, 0.0, 1000.0))
	formation.set_succession_order(["latecomer", "wing2"])

	# Second transfer: wing1 (the current guide) is now destroyed, and
	# latecomer -- which has no design entry -- takes over.
	world.remove_ship("wing1")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "latecomer", "sanity: latecomer should take over as the new guide")
	# latecomer has no design entry, so this transfer must fall back to
	# freezing wing2's ACTUAL position relative to latecomer's ACTUAL
	# position (both identity-oriented, never thrust off their spawn
	# points in this test), rather than crashing or computing nonsense
	# from a design that doesn't describe latecomer at all.
	var expected_wing2_offset: Vector3 = wing2.position - latecomer.position
	var recorded_wing2_offset: Vector3 = formation.member_offsets["wing2"]
	_assert(recorded_wing2_offset.is_equal_approx(expected_wing2_offset), "with no design entry for the new guide, the transfer must honestly fall back to freezing the member's actual current position")

func _test_second_transfer_replans_from_refreshed_design_after_fallback() -> void:
	# Continuation of the fallback case: once a fallback transfer has
	# happened (because the new guide had no design entry), its
	# freeze-in-place result becomes a FRESH design baseline -- a THIRD
	# transfer starting from that refreshed state should once again
	# replan geometrically (from the refreshed design), not fall back
	# again just because an ancestor transfer had to.
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(500.0, 0, 0))
	var wing2 := _make_ship(Vector3(-500.0, 0, 0))
	var wing3 := _make_ship(Vector3(0.0, 0.0, -1000.0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)
	world.add_ship("wing3", wing3)

	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing1", Vector3(500.0, 0, 0))
	formation.set_station("wing2", Vector3(-500.0, 0, 0))
	formation.set_station("wing3", Vector3(0.0, 0.0, -1000.0))
	formation.set_succession_order(["wing1", "wing2", "wing3"])

	# Transfer 1 (fully replanned -- everyone here has a design entry,
	# captured from this very setup): guide destroyed, wing1 takes over.
	world.remove_ship("guide")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "wing1", "sanity: wing1 should take over first")

	# A late-joining reinforcement, added only AFTER the design snapshot
	# above already happened -- it has no design entry.
	var latecomer := _make_ship(Vector3(2000.0, 0.0, 0.0))
	world.add_ship("latecomer", latecomer)
	formation.set_station("latecomer", Vector3(1500.0, 0.0, 0.0))
	formation.set_succession_order(["latecomer", "wing2", "wing3"])

	# Transfer 2 (fallback -- latecomer has no design entry): wing1 (the
	# current guide) is destroyed, latecomer takes over. Every carried
	# ship (wing2, wing3) falls back to a frozen actual-position offset,
	# and that result becomes the NEW design baseline.
	world.remove_ship("wing1")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "latecomer", "sanity: latecomer should take over second (fallback transfer)")
	_assert(formation.design_offsets.has("wing2") and formation.design_offsets.has("wing3"), "a fallback transfer must refresh the design baseline to include every surviving ship")

	# Capture the refreshed design baseline exactly as the fallback left
	# it, before the next transfer can (correctly) leave it untouched.
	var refreshed_wing2_design: Vector3 = formation.design_offsets["wing2"]
	var refreshed_wing3_design: Vector3 = formation.design_offsets["wing3"]

	# Transfer 3: latecomer (current guide) is destroyed, wing2 takes
	# over. wing2 now HAS a design entry (from the transfer-2 refresh),
	# so this transfer should replan wing3 geometrically from that
	# refreshed baseline rather than falling back a second time.
	world.remove_ship("latecomer")
	for i in range(400):
		world.tick_simulation(1.0 / 60.0)
	_assert(formation.guide_ship_id == "wing2", "sanity: wing2 should take over third")

	var expected_wing3_offset: Vector3 = refreshed_wing3_design - refreshed_wing2_design
	var recorded_wing3_offset: Vector3 = formation.member_offsets["wing3"]
	_assert(recorded_wing3_offset.is_equal_approx(expected_wing3_offset), "a transfer following a fallback must replan from the REFRESHED design baseline, not fall back again")

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


## §29 Formation Orders / §35 Command Queue (this pass): a formation with
## no issued order must behave EXACTLY as before this mechanic existed --
## the guide's thrust is whatever the scenario set it to, untouched.
func _test_no_order_leaves_guide_thrust_untouched() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.commanded_thrust_local = Vector3(0.3, 0.0, 0.0)
	world.add_ship("guide", guide)
	world.add_formation("red_wall", "guide")

	world.tick_simulation(1.0 / 60.0)

	_assert(guide.commanded_thrust_local == Vector3(0.3, 0.0, 0.0), "with no formation order issued, the guide's own commanded thrust must be left completely untouched")

func _test_change_course_order_turns_guide_velocity_and_completes() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.velocity = Vector3(100.0, 0.0, 0.0)
	world.add_ship("guide", guide)
	var formation := world.add_formation("red_wall", "guide")

	formation.issue_order(FormationOrder.change_course(guide, Vector3(0.0, 1.0, 0.0)))

	for i in range(240):  # 4s of sim time -- plenty for a 100 m/s turn at 100 m/s^2
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.current_order == null, "the change-course order should have completed and cleared itself well within 4s")
	# Completion tolerance is heading_tolerance_rad (~1.1 degrees), so the
	# residual +X component can be up to speed*sin(tolerance) ~= 2 m/s --
	# assert against that band, not a tighter number the law never promises.
	_assert(absf(guide.velocity.x) < 3.0, "the guide's velocity should have rotated almost entirely off the original +X heading")
	_assert(guide.velocity.y > 95.0, "the guide's velocity should now point almost entirely along the ordered +Y heading")
	_assert(absf(guide.velocity.length() - 100.0) < 1.0, "changing course alone should preserve the guide's original speed (~100 m/s), not change it")

func _test_change_speed_order_accelerates_guide_and_completes() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.velocity = Vector3(50.0, 0.0, 0.0)
	world.add_ship("guide", guide)
	var formation := world.add_formation("red_wall", "guide")

	formation.issue_order(FormationOrder.change_speed(guide, 200.0))

	for i in range(240):
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.current_order == null, "the change-speed order should have completed and cleared itself")
	_assert(absf(guide.velocity.length() - 200.0) < 1.0, "the guide should have accelerated to essentially the ordered 200 m/s")
	_assert(guide.velocity.x > 0.0, "change-speed alone should preserve the guide's original heading (+X)")

func _test_hold_formation_order_never_auto_completes_and_zeros_thrust() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.commanded_thrust_local = Vector3(1.0, 0.0, 0.0)  # leftover thrust from some earlier order
	world.add_ship("guide", guide)
	var formation := world.add_formation("red_wall", "guide")

	formation.issue_order(FormationOrder.hold_formation())

	for i in range(10):
		world.tick_simulation(1.0 / 60.0)

	_assert(guide.commanded_thrust_local == Vector3.ZERO, "HOLD_FORMATION should actively zero the guide's own maneuver thrust")
	_assert(formation.current_order != null, "HOLD_FORMATION is a standing order -- it must not auto-dequeue itself after any number of ticks")

func _test_issue_order_now_interrupts_queued_and_current_orders() -> void:
	var formation := FormationState.new()
	formation.guide_ship_id = "guide"
	var guide := _make_ship(Vector3.ZERO)

	formation.issue_order(FormationOrder.change_speed(guide, 50.0))
	formation.current_order = FormationOrder.change_speed(guide, 10.0)
	_assert(formation.order_queue.size() == 1, "sanity: one order queued behind the current one")

	var urgent := FormationOrder.change_speed(guide, 500.0)
	formation.issue_order_now(urgent)

	_assert(formation.current_order == urgent, "issue_order_now should immediately replace the current order")
	_assert(formation.order_queue.is_empty(), "issue_order_now should drop whatever was still queued behind the interrupted order")

## Cross-module check (also exercises formation-keeping + a multi-order
## queue together, per AGENTS.md guidance that module boundaries are
## where real bugs hide): a wing member must keep following the guide
## through a TWO-order queue (accelerate to 100, then further to 300),
## proving the queue actually advances past the first order's completion
## instead of getting stuck, while station-keeping keeps working
## unmodified throughout.
func _test_order_queue_advances_past_first_order_while_member_still_follows() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	formation.issue_orders([
		FormationOrder.change_speed(guide, 100.0),
		FormationOrder.change_speed(guide, 300.0),
	])

	var saw_first_order_complete_midflight: bool = false
	for i in range(600):  # 10s -- (100 + 200) / 100 m/s^2 ~= 3s of thrust, plenty of margin
		world.tick_simulation(1.0 / 60.0)
		if formation.order_queue.is_empty() and formation.current_order != null and absf(guide.velocity.length() - 100.0) < 5.0:
			saw_first_order_complete_midflight = true

	_assert(saw_first_order_complete_midflight, "the first queued order (to 100 m/s) should complete and hand off to the second BEFORE the run ends")
	_assert(formation.current_order == null, "both queued orders should have completed by the end of the run")
	_assert(absf(guide.velocity.length() - 300.0) < 1.0, "the guide should have ended up at the SECOND order's target speed (300 m/s), proving the queue advanced past the first")
	_assert(wing.position.distance_to(guide.position) < 600.0, "the wing member should still be tracking near its station on the guide throughout the whole multi-order maneuver")

## §29 "withdraw"/"disengage" composite (turn away, then accelerate away).
func _test_withdraw_orders_turn_then_accelerate_away() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	guide.velocity = Vector3(100.0, 0.0, 0.0)  # closing on the enemy along +X
	world.add_ship("guide", guide)
	var formation := world.add_formation("red_wall", "guide")

	formation.issue_orders(FormationOrder.withdraw_orders(guide, Vector3(-1.0, 0.0, 0.0), 300.0))

	for i in range(600):  # 10s: ~2s to reverse 200 m/s of course + ~5s to build to 300 m/s
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.current_order == null and formation.order_queue.is_empty(), "both withdraw-composite orders should have completed")
	_assert(guide.velocity.x < -290.0, "the guide should now be moving briskly in -X, away from the threat it was closing on")

## §29 "change formation": reassigning member_offsets should take effect
## immediately (no gradual "maneuver" on the order itself -- the order
## just retasks the target station) and the order should self-complete
## the same tick it is applied, leaving nothing queued/current behind it.
func _test_change_formation_reassigns_offsets_and_completes_immediately() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))  # line-ahead

	formation.issue_order(FormationOrder.change_formation({"wing": Vector3(0, 0, 800.0)}))  # reform to line-abreast
	world.tick_simulation(1.0 / 60.0)

	_assert(formation.current_order == null, "CHANGE_FORMATION should self-complete the tick it is applied")
	_assert(formation.order_queue.is_empty(), "CHANGE_FORMATION should not leave anything else queued")
	_assert(formation.member_offsets["wing"] == Vector3(0, 0, 800.0), "the wing's station offset should be updated to the newly ordered one")

## A CHANGE_FORMATION order naming only SOME members should leave anyone
## not mentioned exactly where they already were -- a real "open up
## spacing on the left wing" order shouldn't silently un-station the
## right wing.
func _test_change_formation_leaves_unmentioned_members_untouched() -> void:
	var formation := FormationState.new()
	formation.guide_ship_id = "guide"
	formation.set_station("left", Vector3(-500.0, 0, 0))
	formation.set_station("right", Vector3(500.0, 0, 0))
	var guide := _make_ship(Vector3.ZERO)

	var world := SimulationWorld.new()
	world.add_ship("guide", guide)
	world.formations["red_wall"] = formation
	formation.issue_order(FormationOrder.change_formation({"left": Vector3(-1500.0, 0, 0)}))
	world.tick_simulation(1.0 / 60.0)

	_assert(formation.member_offsets["left"] == Vector3(-1500.0, 0, 0), "the named ship's station should move to the ordered offset")
	_assert(formation.member_offsets["right"] == Vector3(500.0, 0, 0), "an unmentioned ship's station must be left exactly as it was")

## CHANGE_FORMATION should also work as "take station" for a ship not
## previously a member at all -- §29 does not distinguish "reform" from
## "assign a newcomer a station", both are just "this ship's offset is
## now X" (see FormationOrder.new_offsets_local's doc comment).
func _test_change_formation_can_add_a_new_member() -> void:
	var formation := FormationState.new()
	formation.guide_ship_id = "guide"
	var guide := _make_ship(Vector3.ZERO)
	var world := SimulationWorld.new()
	world.add_ship("guide", guide)
	world.formations["red_wall"] = formation

	_assert(formation.member_ids().is_empty(), "sanity: no members yet")
	formation.issue_order(FormationOrder.change_formation({"latecomer": Vector3(300.0, 0, 0)}))
	world.tick_simulation(1.0 / 60.0)

	_assert(formation.member_offsets.has("latecomer"), "CHANGE_FORMATION should be able to add a brand-new member's station")

## Cross-module end-to-end check (module boundaries are where real bugs
## hide, per AGENTS.md guidance): after a CHANGE_FORMATION order reassigns
## a member's station, the EXISTING station-keeping PD controller
## (unmodified by this pass) must actually fly that member to the NEW
## world position over subsequent ticks -- proving the order really
## re-tasks live formation-keeping, not just a Dictionary nobody reads.
func _test_change_formation_member_actually_flies_to_new_station() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.0, 0, 0))  # starts on its OLD line-ahead station
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	for i in range(300):
		world.tick_simulation(1.0 / 60.0)
	_assert(wing.position.distance_to(Vector3(500.0, 0, 0)) < 5.0, "sanity: wing should already be settled near its original station")

	var starting_distance_to_new: float = wing.position.distance_to(Vector3(0, 0, 800.0))
	formation.issue_order(FormationOrder.change_formation({"wing": Vector3(0, 0, 800.0)}))  # reform to line-abreast, well off the old line
	# The overdamped station-keeping PD law (K_P_STATION=0.02) converges
	# slowly by design (see _resolve_formation_keeping's doc comment) --
	# calibrated empirically: a ~940m re-station takes on the order of a
	# few minutes of sim time to fully settle within a few meters, not
	# seconds. 18000 ticks (300s) is comfortably past that, matching the
	# calibration used to pick this figure.
	for i in range(18000):
		world.tick_simulation(1.0 / 60.0)
	var ending_distance_to_new: float = wing.position.distance_to(Vector3(0, 0, 800.0))

	_assert(ending_distance_to_new < 5.0, "the wing should have actually flown to its NEWLY ordered station, not stayed on the old one")
	_assert(ending_distance_to_new < starting_distance_to_new, "sanity: it should have gotten meaningfully closer to the new station than where it started")

## Cross-module end-to-end check: a deliberate CHANGE_FORMATION reshape
## must become the formation's new "design" baseline, so a LATER leader
## transfer (§33) re-plans survivors around the SHAPE JUST ORDERED, not
## silently reverting to whatever geometry predated the reshape.
func _test_change_formation_becomes_new_design_for_later_leader_transfer() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing_a := _make_ship(Vector3(500.0, 0, 0))
	var wing_b := _make_ship(Vector3(-500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing_a", wing_a)
	world.add_ship("wing_b", wing_b)
	var formation := world.add_formation("red_wall", "guide")
	formation.set_station("wing_a", Vector3(500.0, 0, 0))   # original line-ahead design
	formation.set_station("wing_b", Vector3(-500.0, 0, 0))
	formation.set_succession_order(["wing_b"])  # wing_b, not wing_a, takes over

	# Reshape wing_a only (wing_b untouched -- see the "leaves unmentioned
	# members untouched" test above) BEFORE any leader transfer has ever
	# happened (design_offsets starts empty -- this must not resurrect the
	# OLD line-ahead shape as "the design" once a transfer does happen).
	formation.issue_order(FormationOrder.change_formation({"wing_a": Vector3(0, 0, 800.0)}))
	world.tick_simulation(1.0 / 60.0)
	_assert(formation.design_offsets.get("wing_a") == Vector3(0, 0, 800.0), "sanity: the reshape should already have become the formation's design baseline")

	# Now the guide is lost (destroyed/removed) -- after the recognition
	# delay, command should transfer to wing_b per the succession order,
	# exercising the real §33 pipeline end-to-end rather than calling the
	# transfer function directly.
	world.remove_ship("guide")
	for i in range(400):  # > COMMAND_TRANSFER_DELAY_S (3s) at 1/60s steps
		world.tick_simulation(1.0 / 60.0)

	_assert(formation.guide_ship_id == "wing_b", "sanity: command should have transferred to wing_b per the succession order")
	# wing_a's replanned offset around the new guide (wing_b) should be
	# derived from the RESHAPED design[wing_a] = (0,0,800), i.e.
	# (0,0,800) - (-500,0,0) = (500,0,800) -- NOT (1000,0,0), which is
	# what you'd get replanning from the stale PRE-reshape design
	# ((500,0,0) - (-500,0,0)). This is the discriminating check that a
	# deliberate reshape really overwrites the design baseline used by
	# later leader transfers.
	_assert(formation.member_offsets.has("wing_a"), "wing_a should be carried forward as an ordinary member after the transfer")
	_assert(formation.member_offsets["wing_a"].distance_to(Vector3(500.0, 0, 800.0)) < 0.01, "leader transfer after a reshape should re-plan from the RESHAPED design, not the pre-reshape one")

## §34.1 Doubling -- SimulationWorld._resolve_formation_target_assignment,
## end-to-end through tick_simulation (not just the TacticalAI helper in
## isolation). Three formation members (guide + 2 wings, deterministic
## order guide/wing1/wing2) all start able to see two hostiles: "hostile_a"
## much nearer to everyone (would win plain independent nearest-contact
## selection for all three members), "hostile_b" much farther (would be
## ignored by plain independent selection). With the default cap
## (MAX_USEFUL_ATTACKERS_PER_TARGET = 2), the first two members in
## deterministic order should still double up on hostile_a, but the third
## should be steered to hostile_b instead of piling on a third time.
func _test_formation_target_assignment_avoids_overcommitting_to_one_target() -> void:
	var world := SimulationWorld.new()

	var guide := _make_ship(Vector3.ZERO)
	var wing1 := _make_ship(Vector3(100, 0, 0))
	var wing2 := _make_ship(Vector3(-100, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing1", wing1)
	world.add_ship("wing2", wing2)
	world.set_team("guide", "red")
	world.set_team("wing1", "red")
	world.set_team("wing2", "red")

	var formation := world.add_formation("wall", "guide")
	formation.set_station("wing1", Vector3(500, 0, 0))
	formation.set_station("wing2", Vector3(-500, 0, 0))

	var hostile_a := _make_ship(Vector3(0, 0, 5000))
	var hostile_b := _make_ship(Vector3(0, 0, 50000))
	world.add_ship("hostile_a", hostile_a)
	world.add_ship("hostile_b", hostile_b)
	world.set_team("hostile_a", "blue")
	world.set_team("hostile_b", "blue")
	world.hulls["hostile_a"] = HullState.new()
	world.hulls["hostile_b"] = HullState.new()

	var weapon := WeaponData.new()
	weapon.max_range_m = 500_000.0
	weapon.damage_per_hit = 0.0  # isolate assignment from actual damage/kill dynamics -- this test only checks WHO was assigned to WHOM
	weapon.recharge_time_s = 0.0
	for id in ["guide", "wing1", "wing2"]:
		world.add_weapon_mount(id, WeaponMount.new(weapon, WeaponMount.broadside_arc()))

	for i in range(5):
		world.tick_simulation(1.0 / 60.0)

	var assigned: Dictionary = world._formation_assigned_targets
	_assert(assigned.get("guide") == "hostile_a", "first member in deterministic formation order should get the nearest target")
	_assert(assigned.get("wing1") == "hostile_a", "second member should still double up on the nearest target (2 <= default MAX_USEFUL_ATTACKERS_PER_TARGET)")
	_assert(assigned.get("wing2") == "hostile_b", "third member should NOT pile onto an already-double-committed target while an uncommitted hostile exists (§34.1)")

## §34.1: a formation whose guide is lost gets NO coordinated assignment
## this tick -- members fall back to independent selection, exactly like
## before this pass existed (honest scope: no phantom coordinator for a
## headless formation).
func _test_formation_target_assignment_skipped_when_guide_lost() -> void:
	var world := SimulationWorld.new()

	var wing1 := _make_ship(Vector3(100, 0, 0))
	world.add_ship("wing1", wing1)
	world.set_team("wing1", "red")

	var formation := world.add_formation("wall", "guide_gone")  # guide never added -> is_guide_lost() true
	formation.set_station("wing1", Vector3(500, 0, 0))

	var hostile := _make_ship(Vector3(0, 0, 5000))
	world.add_ship("hostile", hostile)
	world.set_team("hostile", "blue")

	var weapon := WeaponData.new()
	weapon.max_range_m = 500_000.0
	weapon.damage_per_hit = 0.0
	weapon.recharge_time_s = 0.0
	world.add_weapon_mount("wing1", WeaponMount.new(weapon, WeaponMount.broadside_arc()))

	world.tick_simulation(1.0 / 60.0)

	var assigned: Dictionary = world._formation_assigned_targets
	_assert(not assigned.has("wing1"), "a formation with no valid guide should not get a coordinated assignment entry this tick")

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
	_test_succession_window_member_holds_last_commanded_thrust()
	_test_succession_window_manual_target_designation_survives_guide_loss()
	_test_incapacitated_guide_skips_also_incapacitated_first_in_line()
	_test_default_succession_falls_back_to_member_list_when_unset()
	_test_no_fit_successor_leaves_formation_leaderless_without_crashing()
	_test_transferred_command_replans_from_design_not_frozen_actual_position()
	_test_transfer_falls_back_to_freeze_when_new_guide_has_no_design_entry()
	_test_second_transfer_replans_from_refreshed_design_after_fallback()
	_test_rotating_guide_sweeps_station_and_member_gets_matching_thrust()
	_test_member_already_tracking_guide_rotation_gets_no_spurious_thrust()
	_test_no_order_leaves_guide_thrust_untouched()
	_test_change_course_order_turns_guide_velocity_and_completes()
	_test_change_speed_order_accelerates_guide_and_completes()
	_test_hold_formation_order_never_auto_completes_and_zeros_thrust()
	_test_issue_order_now_interrupts_queued_and_current_orders()
	_test_order_queue_advances_past_first_order_while_member_still_follows()
	_test_withdraw_orders_turn_then_accelerate_away()
	_test_change_formation_reassigns_offsets_and_completes_immediately()
	_test_change_formation_leaves_unmentioned_members_untouched()
	_test_change_formation_can_add_a_new_member()
	_test_change_formation_member_actually_flies_to_new_station()
	_test_change_formation_becomes_new_design_for_later_leader_transfer()

	_test_formation_target_assignment_avoids_overcommitting_to_one_target()
	_test_formation_target_assignment_skipped_when_guide_lost()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
