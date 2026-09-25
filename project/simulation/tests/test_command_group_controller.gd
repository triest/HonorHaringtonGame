extends SceneTree
## Headless unit test for CommandGroupController (ТЗ §56.3 item B). Run:
## godot --headless --script res://simulation/tests/test_command_group_controller.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const CommandGroupController = preload("res://scripts/command_group_controller.gd")

func _init() -> void:
	var failures: int = 0
	failures += _test_single_selection_is_noop()
	failures += _test_empty_selection_is_noop()
	failures += _test_creates_formation_and_echelon_for_two_own_ships()
	failures += _test_excludes_other_team_ships()
	failures += _test_excludes_non_ship_ids()
	failures += _test_group_index_increments_across_calls()
	failures += _test_offset_local_uses_guide_orientation()
	failures += _test_first_selected_becomes_guide()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _make_ship(pos: Vector3, orientation: Quaternion = Quaternion.IDENTITY) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.orientation = orientation
	return s

func _make_world_with_ships(ships: Dictionary, teams: Dictionary) -> SimulationWorld:
	var world := SimulationWorld.new()
	for ship_id in ships.keys():
		world.add_ship(ship_id, ships[ship_id])
	for ship_id in teams.keys():
		world.set_team(ship_id, teams[ship_id])
	return world

func _test_single_selection_is_noop() -> int:
	var world := _make_world_with_ships({"alpha": _make_ship(Vector3.ZERO)}, {"alpha": "red"})
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	if echelon_id != "" or not world.command_echelons.is_empty():
		printerr("FAIL single_selection_is_noop: echelon_id=%s echelons=%s" % [echelon_id, world.command_echelons.keys()])
		return 1
	return 0

func _test_empty_selection_is_noop() -> int:
	var world := _make_world_with_ships({}, {})
	var selection := SelectionState.new()
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	if controller.make_group_from_selection() != "":
		printerr("FAIL empty_selection_is_noop")
		return 1
	return 0

func _test_creates_formation_and_echelon_for_two_own_ships() -> int:
	var world := _make_world_with_ships(
		{"alpha": _make_ship(Vector3.ZERO), "beta": _make_ship(Vector3(1000.0, 0.0, 0.0))},
		{"alpha": "red", "beta": "red"}
	)
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	if echelon_id == "":
		printerr("FAIL creates_formation_and_echelon: got empty echelon_id")
		return 1

	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	if echelon == null or not echelon.is_leaf():
		printerr("FAIL creates_formation_and_echelon: echelon missing or not a leaf")
		return 1
	if echelon.kind == "":
		printerr("FAIL creates_formation_and_echelon: echelon has no name/kind")
		return 1

	var formation: FormationState = world.get_formation(echelon.commanded_formation_id)
	if formation == null:
		printerr("FAIL creates_formation_and_echelon: no formation attached")
		return 1
	if formation.guide_ship_id != "alpha":
		printerr("FAIL creates_formation_and_echelon: guide=%s, expected alpha" % formation.guide_ship_id)
		return 1
	if formation.member_ids() != ["beta"]:
		printerr("FAIL creates_formation_and_echelon: members=%s, expected [beta]" % [formation.member_ids()])
		return 1
	return 0

func _test_excludes_other_team_ships() -> int:
	var world := _make_world_with_ships(
		{"alpha": _make_ship(Vector3.ZERO), "gamma": _make_ship(Vector3(500.0, 0.0, 0.0))},
		{"alpha": "red", "gamma": "blue"}
	)
	var selection := SelectionState.new()
	selection.select_only(["alpha", "gamma"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	if echelon_id != "":
		printerr("FAIL excludes_other_team_ships: expected no-op (mixed teams), got echelon_id=%s" % echelon_id)
		return 1
	return 0

func _test_excludes_non_ship_ids() -> int:
	var world := _make_world_with_ships(
		{"alpha": _make_ship(Vector3.ZERO), "beta": _make_ship(Vector3(1000.0, 0.0, 0.0))},
		{"alpha": "red", "beta": "red"}
	)
	var selection := SelectionState.new()
	# "missile_1" is not a key in world.ships -- must be silently excluded,
	# leaving exactly [alpha, beta] eligible (still >= 2, so the group
	# still forms, but must NOT include "missile_1" as a member).
	selection.select_only(["alpha", "missile_1", "beta"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation: FormationState = world.get_formation(echelon.commanded_formation_id)
	if formation.member_ids().has("missile_1"):
		printerr("FAIL excludes_non_ship_ids: missile_1 leaked into formation membership")
		return 1
	if formation.guide_ship_id != "alpha" or formation.member_ids() != ["beta"]:
		printerr("FAIL excludes_non_ship_ids: guide=%s members=%s" % [formation.guide_ship_id, formation.member_ids()])
		return 1
	return 0

func _test_group_index_increments_across_calls() -> int:
	var world := _make_world_with_ships(
		{
			"alpha": _make_ship(Vector3.ZERO),
			"beta": _make_ship(Vector3(1000.0, 0.0, 0.0)),
			"gamma": _make_ship(Vector3(2000.0, 0.0, 0.0)),
			"delta": _make_ship(Vector3(3000.0, 0.0, 0.0)),
		},
		{"alpha": "red", "beta": "red", "gamma": "red", "delta": "red"}
	)
	var selection := SelectionState.new()
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	selection.select_only(["alpha", "beta"])
	var first_id: String = controller.make_group_from_selection()
	selection.select_only(["gamma", "delta"])
	var second_id: String = controller.make_group_from_selection()

	if first_id == "" or second_id == "" or first_id == second_id:
		printerr("FAIL group_index_increments_across_calls: first=%s second=%s" % [first_id, second_id])
		return 1
	if world.command_echelons.size() != 2:
		printerr("FAIL group_index_increments_across_calls: expected 2 echelons, got %d" % world.command_echelons.size())
		return 1
	return 0

func _test_offset_local_uses_guide_orientation() -> int:
	# Guide facing rotated 180 deg around Y (mirrors main.gd's "beta"
	# demo-ship orientation): a member positioned 1000m along guide's
	# world -X should land as +1000 along the guide's LOCAL +X (since the
	# guide's local frame is rotated 180 deg from world).
	var guide := _make_ship(Vector3.ZERO, Quaternion(Vector3.UP, PI))
	var member := _make_ship(Vector3(-1000.0, 0.0, 0.0))
	var world := _make_world_with_ships({"alpha": guide, "beta": member}, {"alpha": "red", "beta": "red"})
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation: FormationState = world.get_formation(echelon.commanded_formation_id)
	var offset: Vector3 = formation.member_offsets.get("beta")
	# Loose tolerance, not is_equal_approx: rotating by Quaternion(UP, PI)
	# is not bit-exact 180 degrees in floating point, so the "should-be-
	# zero" components land at ~1e-4, not exactly 0.
	if offset == null or offset.distance_to(Vector3(1000.0, 0.0, 0.0)) > 0.01:
		printerr("FAIL offset_local_uses_guide_orientation: offset=%s" % [offset])
		return 1
	return 0

func _test_first_selected_becomes_guide() -> int:
	# Selection order, not id alphabetical order, decides the guide --
	# "beta" is selected first here despite sorting after "alpha".
	var world := _make_world_with_ships(
		{"alpha": _make_ship(Vector3(1000.0, 0.0, 0.0)), "beta": _make_ship(Vector3.ZERO)},
		{"alpha": "red", "beta": "red"}
	)
	var selection := SelectionState.new()
	selection.select_only(["beta", "alpha"])
	var controller := CommandGroupController.new()
	controller.world = world
	controller.selection = selection

	var echelon_id: String = controller.make_group_from_selection()
	var echelon: CommandEchelon = world.get_command_echelon(echelon_id)
	var formation: FormationState = world.get_formation(echelon.commanded_formation_id)
	if formation.guide_ship_id != "beta":
		printerr("FAIL first_selected_becomes_guide: guide=%s, expected beta" % formation.guide_ship_id)
		return 1
	return 0
