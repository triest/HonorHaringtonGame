extends SceneTree
## Headless test runner for IndividualOrder/IndividualCommandState +
## SimulationWorld's individual-ship-order resolution (Milestone 11 first
## slice, ТЗ §30 Individual Ship Orders / §31 Individual Override).
## Run via: godot --headless --path . --script res://simulation/tests/test_individual_orders.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const FormationOrder = preload("res://simulation/formation_order.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")
const IndividualCommandState = preload("res://simulation/individual_command_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")

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
	s.max_angular_speed_rad_s = 0.3
	return s

## -- IndividualCommandState basics -----------------------------------

func _test_command_state_starts_inactive() -> void:
	var state := IndividualCommandState.new()
	_assert(not state.is_active(), "a fresh IndividualCommandState should not be active")

func _test_issue_order_activates_state() -> void:
	var state := IndividualCommandState.new()
	state.issue_order(IndividualOrder.hold())
	_assert(state.is_active(), "issuing an order (even just queued) should make the state active")

func _test_clear_orders_deactivates_state() -> void:
	var state := IndividualCommandState.new()
	state.issue_order_now(IndividualOrder.hold())
	state.clear_orders()
	_assert(not state.is_active(), "clear_orders (§30 return to formation) should deactivate the state")

func _test_issue_order_now_interrupts_queue() -> void:
	var state := IndividualCommandState.new()
	state.issue_order(IndividualOrder.hold())
	state.issue_order(IndividualOrder.hold())
	var urgent := IndividualOrder.change_speed(_make_ship(Vector3.ZERO), 50.0, Vector3.FORWARD)
	state.issue_order_now(urgent)
	_assert(state.current_order == urgent, "issue_order_now should replace current_order immediately")
	_assert(state.order_queue.is_empty(), "issue_order_now should clear the queue")

## -- No-op / API sanity on SimulationWorld ----------------------------

func _test_ship_with_no_individual_order_is_untouched() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.commanded_thrust_local = Vector3(0.25, 0, 0)
	world.add_ship("lone", ship)
	world.tick_simulation(1.0 / 60.0)
	_assert(not world.is_ship_overriding_formation("lone"), "a ship never given an individual order should not be 'overriding'")

func _test_is_ship_overriding_formation_reflects_active_order() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.hold())
	_assert(world.is_ship_overriding_formation("lone"), "an actively-ordered ship should report as overriding")
	world.return_ship_to_formation("lone")
	_assert(not world.is_ship_overriding_formation("lone"), "return_ship_to_formation should clear the override state")

## -- HOLD ---------------------------------------------------------------

func _test_hold_zeroes_thrust_and_angular_velocity_every_tick() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.commanded_thrust_local = Vector3(1, 0, 0)
	ship.angular_velocity = Vector3(0, 0.2, 0)
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.hold())
	world.tick_simulation(1.0 / 60.0)
	_assert(ship.commanded_thrust_local == Vector3.ZERO, "HOLD should zero commanded_thrust_local")
	_assert(ship.angular_velocity == Vector3.ZERO, "HOLD should zero angular_velocity")
	_assert(world.is_ship_overriding_formation("lone"), "HOLD is a standing order and should never auto-complete")

## -- CHANGE_COURSE / CHANGE_SPEED (standalone ship, no formation) ------

func _test_change_course_turns_a_lone_ships_velocity_and_completes() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.velocity = Vector3(100.0, 0, 0)
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.change_course(ship, Vector3(0, 0, 1)))

	for i in range(2000):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "change_course should complete within a generous tick budget")
	_assert(ship.velocity.normalized().distance_to(Vector3(0, 0, 1)) < 0.05, "velocity direction should have turned to +Z")
	_assert(abs(ship.velocity.length() - 100.0) < 1.0, "change_course should preserve speed while turning")

func _test_change_speed_accelerates_a_lone_ship_and_completes() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.velocity = Vector3(10.0, 0, 0)
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.change_speed(ship, 300.0, Vector3(1, 0, 0)))

	for i in range(2000):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "change_speed should complete within a generous tick budget")
	_assert(abs(ship.velocity.length() - 300.0) < 1.0, "speed should have converged to 300 m/s")

func _test_order_queue_advances_from_course_to_speed() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.velocity = Vector3(50.0, 0, 0)
	world.add_ship("lone", ship)
	world.issue_individual_orders("lone", IndividualOrder.withdraw_orders(ship, Vector3(0, 1, 0), 200.0))

	for i in range(3000):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "the withdraw_orders composite should fully drain its queue")
	_assert(ship.velocity.normalized().distance_to(Vector3(0, 1, 0)) < 0.05, "final heading should be +Y (the withdraw direction)")
	_assert(abs(ship.velocity.length() - 200.0) < 1.0, "final speed should be the withdrawal speed")

## -- CHANGE_ORIENTATION ---------------------------------------------

func _test_change_orientation_from_identity_faces_target_and_completes() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	# identity orientation: world_forward starts as Vector3.FORWARD.
	world.add_ship("lone", ship)
	var target := Vector3(1, 0, 0)
	world.issue_individual_order_now("lone", IndividualOrder.change_orientation(target))

	for i in range(600):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "change_orientation should complete within a generous tick budget")
	var world_forward: Vector3 = ship.orientation * Vector3.FORWARD
	_assert(world_forward.distance_to(target.normalized()) < 0.05, "nose should now point along +X")
	_assert(ship.angular_velocity == Vector3.ZERO, "angular_velocity should be zeroed on completion, not left spinning")

## Discriminating test against a body-frame/world-frame mixup: the ship
## starts ALREADY rotated 90 degrees about world Y (so its nose currently
## points along world -X, since Vector3.FORWARD rotated -90 deg about Y
## lands on -X for Godot's basis convention -- the exact starting facing
## doesn't matter, what matters is that it is NOT the identity case,
## which is the one case where body frame and world frame coincide and
## would hide a sign/frame error). Ordered to face world +Z; if the
## resolver's axis/angle math were done in the wrong frame this would
## converge to the wrong direction or fail to converge/oscillate.
func _test_change_orientation_from_non_identity_orientation_converges_correctly() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.orientation = Quaternion(Vector3.UP, deg_to_rad(90.0)).normalized()
	world.add_ship("lone", ship)
	var target := Vector3(0, 0, 1)
	world.issue_individual_order_now("lone", IndividualOrder.change_orientation(target))

	for i in range(600):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "change_orientation from a non-identity start should still complete")
	var world_forward: Vector3 = ship.orientation * Vector3.FORWARD
	_assert(world_forward.distance_to(target.normalized()) < 0.05, "nose should have turned to world +Z regardless of starting orientation (catches a body/world frame mixup)")

func _test_change_orientation_handles_180_degree_reversal() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	var start_forward: Vector3 = ship.orientation * Vector3.FORWARD
	var target: Vector3 = -start_forward
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.change_orientation(target))

	# A full 180-degree reversal at max_angular_speed_rad_s=0.3 rad/s takes
	# at least PI/0.3 =~ 10.47s -- comfortably more than the ~5.2s a 90-
	# degree turn (the other orientation tests) needs, so this one gets a
	# larger dedicated tick budget rather than sharing the 600-tick (10s)
	# budget that is otherwise sufficient for every other orientation case.
	for i in range(900):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("lone"):
			break

	_assert(not world.is_ship_overriding_formation("lone"), "a 180-degree reversal should still converge (arbitrary-axis fallback)")
	var world_forward: Vector3 = ship.orientation * Vector3.FORWARD
	_assert(world_forward.distance_to(target.normalized()) < 0.05, "nose should have reversed to point the opposite way")

## -- Override of formation station-keeping (§31) ------------------------

func _test_individual_order_overrides_formation_thrust_then_returns_control() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.0, 0, 0))  # already on station, at rest
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	var formation := world.add_formation("wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))
	formation.current_order = FormationOrder.hold_formation()

	# Baseline: on station, station-keeping should leave the wing's thrust
	# at zero (dead zone).
	world.tick_simulation(1.0 / 60.0)
	_assert(wing.commanded_thrust_local == Vector3.ZERO, "sanity: a wing already on station should have zero station-keeping thrust")

	# §31 worked example: "Ship A: Intercept Incoming Missile" while the
	# formation still says "Hold Formation" -- issue an explicit
	# individual order that clearly conflicts with staying on station.
	world.issue_individual_order_now("wing", IndividualOrder.change_speed(wing, 400.0, Vector3(0, 1, 0)))
	world.tick_simulation(1.0 / 60.0)
	_assert(wing.commanded_thrust_local != Vector3.ZERO, "an active individual order should override formation station-keeping's zero thrust")
	_assert(world.is_ship_overriding_formation("wing"), "the wing should be reported as overriding its formation")

	# Formation's own order is untouched throughout -- it never learns
	# the wing is misbehaving, exactly as §31's diagram shows the
	# formation order unchanged while the ship-level order runs.
	_assert(formation.current_order.kind == FormationOrder.Kind.HOLD_FORMATION, "the formation's own order should be untouched by a member's individual override")

	# Let the individual order run to completion, then drift the wing
	# off-station (simulating it having flown off to intercept), and
	# verify formation control genuinely resumes once the override ends.
	for i in range(3000):
		world.tick_simulation(1.0 / 60.0)
		if not world.is_ship_overriding_formation("wing"):
			break
	_assert(not world.is_ship_overriding_formation("wing"), "the individual order should complete and hand control back")

	wing.position = Vector3(2000.0, 0, 0)  # now far from its station
	world.tick_simulation(1.0 / 60.0)
	_assert(wing.commanded_thrust_local != Vector3.ZERO, "return to formation should make station-keeping drive this ship again")
	var thrust_world: Vector3 = wing.orientation * wing.commanded_thrust_local
	_assert(thrust_world.x < -0.01, "the wing should be thrusting back toward its station at x=500 from x=2000, exactly as an ordinary member would")

func _test_return_ship_to_formation_cancels_an_in_progress_order() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var wing := _make_ship(Vector3(500.0, 0, 0))
	world.add_ship("guide", guide)
	world.add_ship("wing", wing)
	var formation := world.add_formation("wall", "guide")
	formation.set_station("wing", Vector3(500.0, 0, 0))

	world.issue_individual_order_now("wing", IndividualOrder.change_speed(wing, 500.0, Vector3(1, 0, 0)))
	world.tick_simulation(1.0 / 60.0)
	_assert(world.is_ship_overriding_formation("wing"), "sanity: the order should be active")

	world.return_ship_to_formation("wing")
	_assert(not world.is_ship_overriding_formation("wing"), "return_ship_to_formation should cancel an order that hasn't completed yet, not just a finished one")

func _test_ship_removed_mid_order_does_not_crash() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	world.add_ship("lone", ship)
	world.issue_individual_order_now("lone", IndividualOrder.change_speed(ship, 100.0, Vector3(1, 0, 0)))
	world.remove_ship("lone")
	world.tick_simulation(1.0 / 60.0)  # should not crash iterating a stale entry
	_assert(not world.individual_orders.has("lone"), "remove_ship should also drop any individual-order state for that ship")

func _init() -> void:
	_test_command_state_starts_inactive()
	_test_issue_order_activates_state()
	_test_clear_orders_deactivates_state()
	_test_issue_order_now_interrupts_queue()
	_test_ship_with_no_individual_order_is_untouched()
	_test_is_ship_overriding_formation_reflects_active_order()
	_test_hold_zeroes_thrust_and_angular_velocity_every_tick()
	_test_change_course_turns_a_lone_ships_velocity_and_completes()
	_test_change_speed_accelerates_a_lone_ship_and_completes()
	_test_order_queue_advances_from_course_to_speed()
	_test_change_orientation_from_identity_faces_target_and_completes()
	_test_change_orientation_from_non_identity_orientation_converges_correctly()
	_test_change_orientation_handles_180_degree_reversal()
	_test_individual_order_overrides_formation_thrust_then_returns_control()
	_test_return_ship_to_formation_cancels_an_in_progress_order()
	_test_ship_removed_mid_order_does_not_crash()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
