extends SceneTree
## Headless unit test for MoveOrderController (ТЗ §56.3 item C).
## Run: godot --headless --path . --script res://simulation/tests/test_move_order_controller.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const MoveOrderController = preload("res://scripts/move_order_controller.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")
const CommandGroupController = preload("res://scripts/command_group_controller.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	_test_empty_selection_is_noop()
	_test_excludes_other_team_ships()
	_test_excludes_non_ship_ids()
	_test_lone_ship_gets_individual_order_after_comm_delay()
	_test_lone_ship_keeps_current_speed_if_already_fast()
	_test_click_on_own_position_is_noop()
	_test_single_formation_member_selected_gets_individual_override()
	_test_two_of_three_formation_members_selected_gets_individual_overrides_each()
	_test_two_members_of_same_formation_issue_only_once()
	_test_active_move_orders_records_target_for_visualization()
	_test_prune_completed_removes_arrived_entries()
	_test_prune_completed_removes_entries_for_gone_ships()

	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _passed)
	else:
		printerr("%d TEST(S) FAILED (%d passed)" % [_failures, _passed])
	quit(_failures)

func _make_ship(pos: Vector3, velocity: Vector3 = Vector3.ZERO) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.velocity = velocity
	return s

func _make_controller(world: SimulationWorld, selection: SelectionState, player_team: String = "red") -> MoveOrderController:
	var controller := MoveOrderController.new()
	controller.world = world
	controller.selection = selection
	controller.player_team = player_team
	return controller

func _tick_seconds(world: SimulationWorld, seconds: float, step: float = 0.1) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt: float = minf(step, remaining)
		world.tick_simulation(dt)
		remaining -= dt

func _test_empty_selection_is_noop() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	var controller := _make_controller(world, selection)

	var anchors: Array = controller.issue_move_order(Vector3(1000.0, 0.0, 0.0))
	_assert(anchors.is_empty(), "empty selection must issue no orders")
	_assert(controller.active_move_orders.is_empty(), "empty selection must record no visualization entries")

func _test_excludes_other_team_ships() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	world.add_ship("beta", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	world.set_team("beta", "blue")
	var selection := SelectionState.new()
	selection.select_only(["beta"])  # an enemy ship, not the player's own
	var controller := _make_controller(world, selection, "red")

	var anchors: Array = controller.issue_move_order(Vector3(1000.0, 0.0, 0.0))
	_assert(anchors.is_empty(), "a non-player-team ship in the selection must never be moveable")
	_tick_seconds(world, 5.0)
	_assert(not world.is_ship_overriding_formation("beta"), "beta must never receive an individual order it wasn't eligible for")

func _test_excludes_non_ship_ids() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["missile_1", "alpha"])  # missile_1 is not a real ship
	var controller := _make_controller(world, selection, "red")

	var anchors: Array = controller.issue_move_order(Vector3(1000.0, 0.0, 0.0))
	_assert(anchors == ["alpha"], "only the real own-team ship id should be eligible, got %s" % [anchors])

func _test_lone_ship_gets_individual_order_after_comm_delay() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	var target := Vector3(0.0, 0.0, -10000.0)
	controller.issue_move_order(target)
	_assert(not world.is_ship_overriding_formation("alpha"), "a transmitted move order must not take effect before the comm delay elapses")
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.is_ship_overriding_formation("alpha"), "the move order should have landed as an individual order once the comm delay elapses")

	var current_order: IndividualOrder = world.individual_orders["alpha"].current_order
	_assert(current_order.kind == IndividualOrder.Kind.CHANGE_SPEED, "a lone-ship move order must be a CHANGE_SPEED order carrying an explicit heading, got kind=%d" % current_order.kind)
	var expected_heading: Vector3 = target.normalized()
	var actual_heading: Vector3 = current_order.target_velocity_mps.normalized()
	_assert(actual_heading.distance_to(expected_heading) < 0.001, "order heading %s does not point at the clicked target %s" % [actual_heading, expected_heading])
	_assert(is_equal_approx(current_order.target_velocity_mps.length(), controller.DEFAULT_MOVE_SPEED_MPS), "a stationary ship's move order should ramp up to DEFAULT_MOVE_SPEED_MPS, got %s" % current_order.target_velocity_mps.length())

func _test_lone_ship_keeps_current_speed_if_already_fast() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO, Vector3(0.0, 0.0, -9000.0)))  # already fast, 9000 m/s
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	controller.issue_move_order(Vector3(9000.0, 0.0, -9000.0))
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.individual_orders.has("alpha"), "an already-fast ship's redirect order must still land as an individual order")
	var current_order: IndividualOrder = world.individual_orders["alpha"].current_order
	_assert(current_order != null, "current_order must not be null right after the comm delay elapses -- change_course's heading-based is_complete() must not report done on the very first tick")
	_assert(current_order.kind == IndividualOrder.Kind.CHANGE_COURSE, "an already-fast ship's move order must be CHANGE_COURSE (holds speed, retargets heading only), got kind=%d -- a CHANGE_SPEED order with an unchanged target magnitude would be marked complete before ever turning the ship (see move_order_controller.gd's own doc comment on this trap)" % current_order.kind)
	_assert(is_equal_approx(current_order.target_velocity_mps.length(), 9000.0), "a move order for an already-fast ship must retarget heading only, keeping its current speed (got %s)" % current_order.target_velocity_mps.length())

func _test_click_on_own_position_is_noop() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3(500.0, 0.0, 500.0)))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	controller.issue_move_order(Vector3(500.0, 0.0, 500.0))  # clicked (almost) on the ship itself
	_tick_seconds(world, 5.0)
	_assert(not world.is_ship_overriding_formation("alpha"), "clicking on the ship's own position must not issue a degenerate zero-heading order")
	_assert(controller.active_move_orders.is_empty(), "a no-op click must not create a visualization entry either")

func _test_single_formation_member_selected_gets_individual_override() -> void:
	# §56.3 item I / §1.10.12 ("select one CA inside the group, COVER a
	# neighbour, the REST of the group keeps executing the original
	# order"): selecting exactly ONE member of an existing formation and
	# issuing it a move order must NOT re-route to the formation level --
	# that would silently redirect the WHOLE group from a single-member
	# click (this test used to assert exactly that broken behavior before
	# item I fixed it -- see move_order_controller.gd's class doc for the
	# full reasoning). It must give that one ship its own individual
	# order instead, leaving the formation's own current order (and every
	# OTHER member) completely untouched.
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.add_ship("beta", _make_ship(Vector3(1000.0, 0.0, 0.0)))
	world.set_team("alpha", "red")
	world.set_team("beta", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta"])
	var group_controller := CommandGroupController.new()
	group_controller.world = world
	group_controller.selection = selection
	var echelon_id: String = group_controller.make_group_from_selection()
	_assert(echelon_id != "", "test setup: group creation must succeed")

	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation_id: String = echelon.commanded_formation_id
	var formation: FormationState = world.get_formation(formation_id)
	# Give the formation an original order first, so we can check it is
	# left alone by the single-member override below.
	var original_target := Vector3(0.0, 0.0, -5000.0)
	world.issue_formation_order_now(formation_id, FormationOrder.approach(original_target, 2000.0))

	# Now select just the (non-guide) member and issue a move order.
	selection.select_only(["beta"])
	var controller := _make_controller(world, selection, "red")
	var override_target := Vector3(0.0, 0.0, -20000.0)
	var anchors: Array = controller.issue_move_order(override_target)

	_assert(anchors == ["beta"], "the visualization anchor for a single-member override must be that ship itself, got %s" % [anchors])
	_assert(formation.current_order != null and formation.current_order.kind == FormationOrder.Kind.APPROACH and formation.current_order.target_point_world.distance_to(original_target) < 0.001, "the formation's own order must be untouched by a single-member override")

	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.is_ship_overriding_formation("beta"), "the selected member must have an active individual order overriding formation station-keeping (§31)")
	_assert(not world.is_ship_overriding_formation("alpha"), "the guide/other member NOT selected must be untouched -- no individual override created for it")
	var current_order: IndividualOrder = world.individual_orders["beta"].current_order
	var expected_heading: Vector3 = (override_target - Vector3(1000.0, 0.0, 0.0)).normalized()
	var actual_heading: Vector3 = current_order.target_velocity_mps.normalized()
	_assert(actual_heading.distance_to(expected_heading) < 0.001, "beta's individual override must point at the newly clicked target, got heading %s" % actual_heading)

func _test_two_of_three_formation_members_selected_gets_individual_overrides_each() -> void:
	# Generalization of the single-member case above: selecting a STRICT
	# SUBSET larger than one (2 of 3 members) must still give each
	# SELECTED ship its own individual override rather than collapsing to
	# a formation-level order -- only selecting the formation's ENTIRE
	# current membership (see §1.10.12: exercised by
	# _test_two_members_of_same_formation_issue_only_once below) collapses
	# to one order.
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.add_ship("beta", _make_ship(Vector3(1000.0, 0.0, 0.0)))
	world.add_ship("charlie", _make_ship(Vector3(-1000.0, 0.0, 0.0)))
	world.set_team("alpha", "red")
	world.set_team("beta", "red")
	world.set_team("charlie", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta", "charlie"])
	var group_controller := CommandGroupController.new()
	group_controller.world = world
	group_controller.selection = selection
	var echelon_id: String = group_controller.make_group_from_selection()
	_assert(echelon_id != "", "test setup: 3-ship group creation must succeed")

	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation_id: String = echelon.commanded_formation_id
	var formation: FormationState = world.get_formation(formation_id)
	var original_target := Vector3(0.0, 0.0, -5000.0)
	world.issue_formation_order_now(formation_id, FormationOrder.approach(original_target, 2000.0))

	# Select only beta+charlie (NOT the guide alpha -- a strict subset).
	selection.select_only(["beta", "charlie"])
	var controller := _make_controller(world, selection, "red")
	var override_target := Vector3(9000.0, 0.0, 9000.0)
	var anchors: Array = controller.issue_move_order(override_target)

	_assert(anchors.size() == 2 and anchors.has("beta") and anchors.has("charlie"), "both selected subset members must be their own visualization anchors, got %s" % [anchors])
	_assert(formation.current_order != null and formation.current_order.kind == FormationOrder.Kind.APPROACH and formation.current_order.target_point_world.distance_to(original_target) < 0.001, "the formation's own order must be untouched by a 2-of-3 subset override")

	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.is_ship_overriding_formation("beta"), "beta (selected) must have an active individual override")
	_assert(world.is_ship_overriding_formation("charlie"), "charlie (selected) must have an active individual override")
	_assert(not world.is_ship_overriding_formation("alpha"), "alpha (NOT selected, the guide) must be untouched")

func _test_two_members_of_same_formation_issue_only_once() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.add_ship("beta", _make_ship(Vector3(1000.0, 0.0, 0.0)))
	world.set_team("alpha", "red")
	world.set_team("beta", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta"])
	var group_controller := CommandGroupController.new()
	group_controller.world = world
	group_controller.selection = selection
	group_controller.make_group_from_selection()

	# Both members of the SAME formation selected together -- must
	# collapse to a single formation-level order, not one per member.
	selection.select_only(["alpha", "beta"])
	var controller := _make_controller(world, selection, "red")
	var anchors: Array = controller.issue_move_order(Vector3(0.0, 0.0, -5000.0))
	_assert(anchors.size() == 1, "selecting both members of one formation must issue exactly one order (one anchor), got %s" % [anchors])

func _test_active_move_orders_records_target_for_visualization() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	var target := Vector3(3000.0, 0.0, -4000.0)
	controller.issue_move_order(target)
	_assert(controller.active_move_orders.has("alpha"), "issuing a move order must record a visualization entry keyed by the anchor ship id")
	_assert(controller.active_move_orders["alpha"]["target_point"].distance_to(target) < 0.001, "the recorded visualization target must match the clicked point")

func _test_prune_completed_removes_arrived_entries() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	controller.issue_move_order(Vector3(0.0, 0.0, -10000.0))
	_assert(controller.active_move_orders.has("alpha"), "test setup: entry must exist before arrival")

	controller.prune_completed()
	_assert(controller.active_move_orders.has("alpha"), "entry must survive prune_completed while still far from the target")

	alpha.position = Vector3(0.0, 0.0, -9999.0)  # well within ARRIVAL_TOLERANCE_M of the target
	controller.prune_completed()
	_assert(not controller.active_move_orders.has("alpha"), "entry must be pruned once the anchor ship has arrived at its target")

func _test_prune_completed_removes_entries_for_gone_ships() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection, "red")

	controller.issue_move_order(Vector3(0.0, 0.0, -10000.0))
	world.ships.erase("alpha")  # simulate destruction -- no dedicated remove_ship API exists yet
	controller.prune_completed()
	_assert(not controller.active_move_orders.has("alpha"), "a visualization entry for a ship no longer in world.ships must be pruned, not linger forever")
