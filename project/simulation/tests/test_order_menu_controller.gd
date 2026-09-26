extends SceneTree
## Headless unit test for OrderMenuController (ТЗ §56.3 item D). Run:
## godot --headless --script res://simulation/tests/test_order_menu_controller.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const OrderMenuController = preload("res://scripts/order_menu_controller.gd")
const MoveOrderController = preload("res://scripts/move_order_controller.gd")
const CommandGroupController = preload("res://scripts/command_group_controller.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")
const FormationOrder = preload("res://simulation/formation_order.gd")
const CommandEchelon = preload("res://simulation/command_echelon.gd")
const FormationState = preload("res://simulation/formation_state.gd")

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
	_test_own_ship_target_is_noop()
	_test_non_ship_target_is_noop()
	_test_eligible_hostile_click_opens_menu_and_designates_target()
	_test_entries_omit_maintain_formation_for_lone_ship()
	_test_entries_include_maintain_formation_for_formation_member()
	_test_dismiss_clears_designation_and_issues_nothing()
	_test_attack_sets_target_and_weapons_free_after_comm_delay()
	_test_hold_fire_sets_weapons_free_false()
	_test_approach_reuses_move_order_controller()
	_test_withdraw_lone_ship_issues_course_then_speed_away_from_target()
	_test_maintain_formation_issues_hold_formation_once_per_formation()
	_test_execute_closes_menu_and_clears_designation()

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

func _make_controller(world: SimulationWorld, selection: SelectionState, player_team: String = "red") -> OrderMenuController:
	var controller := OrderMenuController.new()
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

func _basic_two_side_world() -> SimulationWorld:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	world.add_ship("bravo", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	world.set_team("bravo", "blue")
	return world

func _test_empty_selection_is_noop() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()  # nothing selected
	var controller := _make_controller(world, selection)

	var opened: bool = controller.try_open("bravo", Vector2(10, 10))
	_assert(not opened, "an empty selection has nothing to command -- the menu must not open")
	_assert(not controller.is_open, "controller.is_open must stay false")
	_assert(not selection.has_designated_target(), "no designation should be made when the menu doesn't open")

func _test_own_ship_target_is_noop() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)

	var opened: bool = controller.try_open("alpha", Vector2(10, 10))  # clicking your OWN ship, not a hostile
	_assert(not opened, "clicking an own-team ship must never open the order menu")
	_assert(not selection.has_designated_target(), "an own ship must never become a designated target")

func _test_non_ship_target_is_noop() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)

	var opened: bool = controller.try_open("missile_1", Vector2(10, 10))  # not in world.ships
	_assert(not opened, "a non-ship contact id (e.g. a missile) must never open the order menu")

func _test_eligible_hostile_click_opens_menu_and_designates_target() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)

	var opened: bool = controller.try_open("bravo", Vector2(42, 84))
	_assert(opened, "an own-ship selection + a real hostile ship click must open the menu")
	_assert(controller.is_open, "controller.is_open must be true after a successful try_open")
	_assert(controller.menu_screen_pos == Vector2(42, 84), "menu_screen_pos must record the click position passed in")
	_assert(selection.designated_target_id == "bravo", "the hostile contact must become the designated target")
	_assert(selection.selected_ids == ["alpha"], "the own-ship selection must be left completely untouched by designation")

	var kinds: Array = []
	for entry in controller.menu_entries:
		kinds.append(entry["kind"])
	for expected in ["ATTACK", "FOCUS_FIRE", "HOLD_FIRE", "WEAPONS_FREE", "APPROACH", "WITHDRAW"]:
		_assert(kinds.has(expected), "menu_entries must include %s" % expected)
	for unimplemented in ["DEFEND", "COVER", "FOLLOW", "INTERCEPT"]:
		_assert(not kinds.has(unimplemented), "menu_entries must NOT offer %s -- no backing primitive exists yet (honest gap)" % unimplemented)

func _test_entries_omit_maintain_formation_for_lone_ship() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])  # alpha is not in any formation
	var controller := _make_controller(world, selection)

	controller.try_open("bravo", Vector2.ZERO)
	var kinds: Array = []
	for entry in controller.menu_entries:
		kinds.append(entry["kind"])
	_assert(not kinds.has("MAINTAIN_FORMATION"), "MAINTAIN FORMATION must not be offered for a lone ship with nothing to maintain")

func _test_entries_include_maintain_formation_for_formation_member() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.add_ship("charlie", _make_ship(Vector3(1000.0, 0.0, 0.0)))
	world.set_team("alpha", "red")
	world.set_team("charlie", "red")
	world.add_ship("bravo", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	world.set_team("bravo", "blue")

	var selection := SelectionState.new()
	selection.select_only(["alpha", "charlie"])
	var group_controller := CommandGroupController.new()
	group_controller.world = world
	group_controller.selection = selection
	var echelon_id: String = group_controller.make_group_from_selection()
	_assert(echelon_id != "", "test setup: group creation must succeed")

	selection.select_only(["alpha"])  # now just the guide, still a formation member
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	var kinds: Array = []
	for entry in controller.menu_entries:
		kinds.append(entry["kind"])
	_assert(kinds.has("MAINTAIN_FORMATION"), "MAINTAIN FORMATION must be offered once at least one eligible ship is a formation member")

func _test_dismiss_clears_designation_and_issues_nothing() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)

	controller.try_open("bravo", Vector2.ZERO)
	controller.dismiss()
	_assert(not controller.is_open, "dismiss() must close the menu")
	_assert(not selection.has_designated_target(), "dismiss() must clear the designation")
	_assert(selection.selected_ids == ["alpha"], "dismiss() must not touch the own-ship selection")

	_tick_seconds(world, 5.0)
	var directive: ShipCombatDirective = world.ship_combat_directives.get("alpha")
	_assert(directive == null or directive.manual_target_ship_id == "", "dismiss() must never issue any order")

func _test_attack_sets_target_and_weapons_free_after_comm_delay() -> void:
	var world := _basic_two_side_world()
	world.transmit_ship_weapons_free("alpha", false)  # start held, so we can observe ATTACK explicitly re-freeing it
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.ship_combat_directives["alpha"].weapons_free == false, "test setup: alpha must start weapons-held")

	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("ATTACK")

	_assert(String(world.ship_combat_directives.get("alpha", null).manual_target_ship_id if world.ship_combat_directives.has("alpha") else "") != "bravo", "ATTACK must be comm-delayed, not instantaneous")
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	var directive: ShipCombatDirective = world.ship_combat_directives["alpha"]
	_assert(directive.manual_target_ship_id == "bravo", "ATTACK must designate the target ship via transmit_ship_target")
	_assert(directive.weapons_free == true, "ATTACK must also set weapons free")

func _test_hold_fire_sets_weapons_free_false() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("HOLD_FIRE")

	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	var directive: ShipCombatDirective = world.ship_combat_directives.get("alpha")
	_assert(directive != null and directive.weapons_free == false, "HOLD FIRE must set weapons_free to false")

func _test_approach_reuses_move_order_controller() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var move_controller := MoveOrderController.new()
	move_controller.world = world
	move_controller.selection = selection
	move_controller.player_team = "red"

	var controller := _make_controller(world, selection)
	controller.move_order_controller = move_controller
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("APPROACH")

	_assert(move_controller.active_move_orders.has("alpha"), "APPROACH must route through MoveOrderController.issue_move_order")
	var target_point: Vector3 = move_controller.active_move_orders["alpha"]["target_point"]
	_assert(target_point.distance_to(world.ships["bravo"].position) < 0.001, "APPROACH's target point must be the designated hostile's current position")

func _test_withdraw_lone_ship_issues_course_then_speed_away_from_target() -> void:
	# NOTE: alpha must already be moving -- IndividualOrder.change_course
	# (the first leg of withdraw_orders) holds the ship's CURRENT speed
	# while retargeting heading; if that current speed is ~0,
	# is_complete() reads true on the very first tick (0 == 0), before
	# any heading is ever actually applied, and the composite silently
	# "completes" doing nothing -- the same trap MoveOrderController's
	# own doc comment documents for a single change_course/change_speed
	# choice. Every existing withdraw_orders test in this codebase
	# (test_formation.gd, test_individual_orders.gd) starts from a
	# nonzero velocity for the same reason -- a "withdraw" is a combat
	# maneuver for an already-moving warship, not a cold start.
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO, Vector3(100.0, 0.0, 0.0))  # closing on bravo along +X
	world.add_ship("alpha", alpha)
	world.set_team("alpha", "red")
	world.add_ship("bravo", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	world.set_team("bravo", "blue")

	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("WITHDRAW")

	# WITHDRAW is issued via the immediate queued API (not comm-delayed --
	# see order_menu_controller.gd's own doc comment on why), so it should
	# be visible on the very next tick, not after a comm delay.
	world.tick_simulation(0.1)
	_assert(world.individual_orders.has("alpha"), "WITHDRAW must issue a real individual order for a lone ship")
	var state: IndividualCommandState = world.individual_orders["alpha"]
	_assert(state.current_order != null, "a WITHDRAW order must be actively executing")
	# away from bravo (+X) means alpha's ordered heading should point -X.
	var heading: Vector3 = state.current_order.target_velocity_mps.normalized()
	_assert(heading.x < -0.9, "WITHDRAW must point the ship AWAY from the designated target (got heading %s)" % heading)

func _test_maintain_formation_issues_hold_formation_once_per_formation() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.add_ship("charlie", _make_ship(Vector3(1000.0, 0.0, 0.0)))
	world.set_team("alpha", "red")
	world.set_team("charlie", "red")
	world.add_ship("bravo", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	world.set_team("bravo", "blue")

	var selection := SelectionState.new()
	selection.select_only(["alpha", "charlie"])
	var group_controller := CommandGroupController.new()
	group_controller.world = world
	group_controller.selection = selection
	var echelon_id: String = group_controller.make_group_from_selection()

	selection.select_only(["alpha", "charlie"])  # both members of the SAME formation
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("MAINTAIN_FORMATION")

	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation: FormationState = world.get_formation(echelon.commanded_formation_id)
	_assert(formation.current_order != null and formation.current_order.kind == FormationOrder.Kind.HOLD_FORMATION, "MAINTAIN FORMATION must issue a HOLD_FORMATION order at the formation level")

func _test_execute_closes_menu_and_clears_designation() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.try_open("bravo", Vector2.ZERO)
	controller.execute("HOLD_FIRE")

	_assert(not controller.is_open, "execute() must close the menu")
	_assert(controller.menu_entries.is_empty(), "execute() must clear menu_entries")
	_assert(not selection.has_designated_target(), "execute() must clear the designation once the order is issued")
