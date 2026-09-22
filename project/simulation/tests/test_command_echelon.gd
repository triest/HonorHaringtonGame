extends SceneTree
## Headless test runner for CommandEchelon + SimulationWorld's §28 Command
## Hierarchy first slice (order cascading down a configurable echelon
## tree -- see command_echelon.gd class doc for scope).
## Run via: godot --headless --path . --script res://simulation/tests/test_command_echelon.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const CommandEchelon = preload("res://simulation/command_echelon.gd")
const FormationOrder = preload("res://simulation/formation_order.gd")
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
	return s

# ---------------------------------------------------------------------
# CommandEchelon class basics
# ---------------------------------------------------------------------

func _test_new_echelon_is_not_a_leaf() -> void:
	var echelon := CommandEchelon.new()
	echelon.echelon_id = "sq1"
	echelon.kind = "Squadron"
	_assert(not echelon.is_leaf(), "a freshly created echelon with no commanded formation should not be a leaf")

func _test_echelon_becomes_leaf_once_commanded_formation_set() -> void:
	var echelon := CommandEchelon.new()
	echelon.commanded_formation_id = "wall1"
	_assert(echelon.is_leaf(), "an echelon with a non-empty commanded_formation_id should be a leaf")

func _test_echelon_to_dict_from_dict_round_trip() -> void:
	var echelon := CommandEchelon.new()
	echelon.echelon_id = "div1"
	echelon.kind = "Division"
	echelon.parent_id = "sq1"
	echelon.child_echelon_ids = ["el1", "el2"]
	echelon.commanded_formation_id = ""

	var restored := CommandEchelon.from_dict(echelon.to_dict())
	_assert(restored.echelon_id == "div1", "echelon_id should survive to_dict/from_dict")
	_assert(restored.kind == "Division", "kind should survive to_dict/from_dict")
	_assert(restored.parent_id == "sq1", "parent_id should survive to_dict/from_dict")
	_assert(restored.child_echelon_ids == ["el1", "el2"], "child_echelon_ids should survive to_dict/from_dict")
	_assert(not restored.is_leaf(), "a restored internal echelon should still not be a leaf")

func _test_echelon_to_dict_duplicates_child_array_defensively() -> void:
	var echelon := CommandEchelon.new()
	echelon.echelon_id = "sq1"
	var d := echelon.to_dict()
	echelon.child_echelon_ids.append("intruder")
	_assert(not d["child_echelon_ids"].has("intruder"), "to_dict's snapshot should not be mutated by later changes to the live echelon")

# ---------------------------------------------------------------------
# SimulationWorld tree-building API
# ---------------------------------------------------------------------

func _test_add_command_echelon_registers_a_root() -> void:
	var world := SimulationWorld.new()
	var fleet := world.add_command_echelon("fleet1", "Fleet")
	_assert(world.get_command_echelon("fleet1") == fleet, "add_command_echelon should register the echelon so get_command_echelon finds it")
	_assert(fleet.parent_id == "", "an echelon created with no parent_id argument should be a root (empty parent_id)")

func _test_add_command_echelon_links_parent_and_child() -> void:
	var world := SimulationWorld.new()
	var squadron := world.add_command_echelon("sq1", "Squadron")
	var division := world.add_command_echelon("div1", "Division", "sq1")
	_assert(division.parent_id == "sq1", "the child echelon's parent_id should be set")
	_assert(squadron.child_echelon_ids.has("div1"), "the parent echelon's child_echelon_ids should include the new child")

func _test_add_command_echelon_refuses_self_parent() -> void:
	var world := SimulationWorld.new()
	var sq := world.add_command_echelon("sq1", "Squadron", "sq1")
	_assert(sq.parent_id == "", "self-parenting should be refused, leaving the echelon a root instead of crashing")

func _test_add_command_echelon_refuses_missing_parent() -> void:
	var world := SimulationWorld.new()
	var div := world.add_command_echelon("div1", "Division", "no_such_squadron")
	_assert(div.parent_id == "", "a parent_id that does not exist yet should be refused, leaving the echelon a root rather than crashing")

func _test_add_command_echelon_refuses_parent_that_is_already_a_leaf() -> void:
	var world := SimulationWorld.new()
	var div := world.add_command_echelon("div1", "Division")
	world.attach_formation_to_echelon("div1", "wall1")  # div1 is now a leaf
	var element := world.add_command_echelon("el1", "Element", "div1")
	_assert(element.parent_id == "", "adding a child echelon under a LEAF echelon should be refused, leaving the child a root")
	_assert(div.child_echelon_ids.is_empty(), "the leaf echelon should not have gained a child")
	_assert(div.commanded_formation_id == "wall1", "the leaf echelon's own commanded formation should be untouched by the refused attach")

func _test_attach_formation_to_echelon_makes_it_a_leaf() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("div1", "Division")
	world.attach_formation_to_echelon("div1", "wall1")
	_assert(world.get_command_echelon("div1").commanded_formation_id == "wall1", "attach_formation_to_echelon should set commanded_formation_id")
	_assert(world.get_command_echelon("div1").is_leaf(), "the echelon should now be a leaf")

func _test_attach_formation_refuses_when_echelon_has_children() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.attach_formation_to_echelon("sq1", "wall1")
	_assert(world.get_command_echelon("sq1").commanded_formation_id == "", "an internal echelon with children should refuse becoming a leaf")

# ---------------------------------------------------------------------
# Formation-id collection (the recursive subtree walk)
# ---------------------------------------------------------------------

func _test_collect_formation_ids_single_leaf() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("div1", "Division")
	world.attach_formation_to_echelon("div1", "wall1")
	_assert(world._collect_formation_ids_under_echelon("div1") == ["wall1"], "a single leaf echelon should collect exactly its own formation")

func _test_collect_formation_ids_multi_level_tree() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.add_command_echelon("div2", "Division", "sq1")
	world.attach_formation_to_echelon("div1", "wallA")
	world.attach_formation_to_echelon("div2", "wallB")

	var collected: Array = world._collect_formation_ids_under_echelon("sq1")
	_assert(collected.size() == 2, "a two-division squadron should collect two formations")
	_assert(collected.has("wallA") and collected.has("wallB"), "both divisions' formations should be collected")

func _test_collect_formation_ids_empty_internal_echelon_is_empty() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("sq1", "Squadron")
	_assert(world._collect_formation_ids_under_echelon("sq1") == [], "an internal echelon with no children attached yet should collect nothing, not crash")

func _test_collect_formation_ids_deduplicates_shared_formation() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.add_command_echelon("div2", "Division", "sq1")
	world.attach_formation_to_echelon("div1", "wallShared")
	world.attach_formation_to_echelon("div2", "wallShared")

	var collected: Array = world._collect_formation_ids_under_echelon("sq1")
	_assert(collected == ["wallShared"], "the same formation_id attached under two echelons should be collected only once")

func _test_collect_formation_ids_unknown_echelon_is_empty() -> void:
	var world := SimulationWorld.new()
	_assert(world._collect_formation_ids_under_echelon("no_such_echelon") == [], "an unknown echelon_id should collect nothing rather than crashing")

# ---------------------------------------------------------------------
# issue_echelon_order: real cascading through SimulationWorld.tick_simulation()
# ---------------------------------------------------------------------

func _test_issue_echelon_order_cascades_change_course_to_every_child_formation() -> void:
	var world := SimulationWorld.new()
	var guideA := _make_ship(Vector3(0, 0, 0))
	guideA.velocity = Vector3(100, 0, 0)
	var guideB := _make_ship(Vector3(10000, 0, 0))
	guideB.velocity = Vector3(100, 0, 0)
	world.add_ship("guideA", guideA)
	world.add_ship("guideB", guideB)
	world.add_formation("wallA", "guideA")
	world.add_formation("wallB", "guideB")

	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.add_command_echelon("div2", "Division", "sq1")
	world.attach_formation_to_echelon("div1", "wallA")
	world.attach_formation_to_echelon("div2", "wallB")

	var new_heading := Vector3(0, 1, 0)  # turn from +X to +Y
	world.issue_echelon_order("sq1", FormationOrder.change_course(guideA, new_heading))

	for i in range(600):
		world.tick_simulation(1.0 / 60.0)

	_assert(guideA.velocity.normalized().angle_to(new_heading) < 0.05, "guideA's formation should have turned toward the echelon-cascaded new heading")
	_assert(guideB.velocity.normalized().angle_to(new_heading) < 0.05, "guideB's formation should ALSO have turned toward the same echelon-cascaded new heading")

func _test_issue_echelon_order_gives_each_formation_an_independent_order_instance() -> void:
	# Two formations approach the SAME world point from two different
	# starting positions. If the cascaded order were a single SHARED
	# FormationOrder instance, _approach_target_velocity's per-tick
	# mutation of target_velocity_mps for one guide would clobber the
	# other's -- this test proves that does not happen.
	var world := SimulationWorld.new()
	var guideA := _make_ship(Vector3(-5000, 0, 0))
	var guideB := _make_ship(Vector3(0, 5000, 0))
	world.add_ship("guideA", guideA)
	world.add_ship("guideB", guideB)
	world.add_formation("wallA", "guideA")
	world.add_formation("wallB", "guideB")

	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.add_command_echelon("div2", "Division", "sq1")
	world.attach_formation_to_echelon("div1", "wallA")
	world.attach_formation_to_echelon("div2", "wallB")

	var target_point := Vector3(0, 0, 0)
	world.issue_echelon_order("sq1", FormationOrder.approach(target_point, 100.0))
	world.tick_simulation(1.0 / 60.0)

	var order_a = world.get_formation("wallA").current_order
	var order_b = world.get_formation("wallB").current_order
	_assert(order_a != order_b, "each formation should hold its OWN order instance, not a shared reference")
	# guideA is due -X of the target, guideB is due +Y -- their computed target
	# velocities must point in two clearly different directions.
	_assert(order_a.target_velocity_mps.normalized().angle_to(order_b.target_velocity_mps.normalized()) > 0.5, "independent per-formation target velocities should differ (guideA heads +X, guideB heads -Y)")

func _test_issue_echelon_order_on_unknown_echelon_is_safe_noop() -> void:
	var world := SimulationWorld.new()
	world.issue_echelon_order("no_such_echelon", FormationOrder.hold_formation())  # must not crash
	_assert(true, "issuing an order to an unregistered echelon_id should be a safe no-op")

func _test_issue_echelon_order_to_formation_missing_from_world_is_safe() -> void:
	var world := SimulationWorld.new()
	world.add_command_echelon("div1", "Division")
	world.attach_formation_to_echelon("div1", "never_registered")
	world.issue_echelon_order("div1", FormationOrder.hold_formation())  # must not crash
	_assert(true, "cascading to a formation_id that was never registered with add_formation should be a safe no-op")

# ---------------------------------------------------------------------
# Replay recording
# ---------------------------------------------------------------------

func _test_issue_echelon_order_is_recorded_once_not_per_formation() -> void:
	var world := SimulationWorld.new()
	var guideA := _make_ship(Vector3.ZERO)
	var guideB := _make_ship(Vector3(10000, 0, 0))
	world.add_ship("guideA", guideA)
	world.add_ship("guideB", guideB)
	world.add_formation("wallA", "guideA")
	world.add_formation("wallB", "guideB")
	world.add_command_echelon("sq1", "Squadron")
	world.add_command_echelon("div1", "Division", "sq1")
	world.add_command_echelon("div2", "Division", "sq1")
	world.attach_formation_to_echelon("div1", "wallA")
	world.attach_formation_to_echelon("div2", "wallB")

	world.start_recording()
	world.issue_echelon_order("sq1", FormationOrder.hold_formation())

	_assert(world.replay_log.commands.size() == 1, "an echelon order cascading to two formations should still be recorded as ONE command, not one per formation")
	_assert(world.replay_log.commands[0]["name"] == "issue_echelon_order", "the recorded command name should be issue_echelon_order")
	_assert(world.replay_log.commands[0]["args"]["echelon_id"] == "sq1", "the recorded args should carry the echelon_id, not individual formation_ids")

func _test_replayed_echelon_order_reproduces_the_cascade() -> void:
	var world_a := SimulationWorld.new()
	var guideA := _make_ship(Vector3.ZERO)
	guideA.velocity = Vector3(100, 0, 0)
	var guideB := _make_ship(Vector3(10000, 0, 0))
	guideB.velocity = Vector3(100, 0, 0)
	world_a.add_ship("guideA", guideA)
	world_a.add_ship("guideB", guideB)
	world_a.add_formation("wallA", "guideA")
	world_a.add_formation("wallB", "guideB")
	world_a.add_command_echelon("sq1", "Squadron")
	world_a.add_command_echelon("div1", "Division", "sq1")
	world_a.add_command_echelon("div2", "Division", "sq1")
	world_a.attach_formation_to_echelon("div1", "wallA")
	world_a.attach_formation_to_echelon("div2", "wallB")

	world_a.start_recording()
	world_a.issue_echelon_order("sq1", FormationOrder.change_course(guideA, Vector3(0, 1, 0)))
	var entry: Dictionary = world_a.replay_log.commands[0]

	# Rebuild an identical fresh world (same setup, no recording) and apply
	# the recorded command via the public replay dispatcher.
	var world_b := SimulationWorld.new()
	var guideA2 := _make_ship(Vector3.ZERO)
	guideA2.velocity = Vector3(100, 0, 0)
	var guideB2 := _make_ship(Vector3(10000, 0, 0))
	guideB2.velocity = Vector3(100, 0, 0)
	world_b.add_ship("guideA", guideA2)
	world_b.add_ship("guideB", guideB2)
	world_b.add_formation("wallA", "guideA")
	world_b.add_formation("wallB", "guideB")
	world_b.add_command_echelon("sq1", "Squadron")
	world_b.add_command_echelon("div1", "Division", "sq1")
	world_b.add_command_echelon("div2", "Division", "sq1")
	world_b.attach_formation_to_echelon("div1", "wallA")
	world_b.attach_formation_to_echelon("div2", "wallB")

	world_b.apply_recorded_command(entry)
	world_b.tick_simulation(1.0 / 60.0)  # dequeue order_queue -> current_order

	_assert(world_b.get_formation("wallA").current_order != null, "replaying issue_echelon_order should have queued/started an order on wallA")
	_assert(world_b.get_formation("wallB").current_order != null, "replaying issue_echelon_order should have cascaded to wallB too")

func _init() -> void:
	_test_new_echelon_is_not_a_leaf()
	_test_echelon_becomes_leaf_once_commanded_formation_set()
	_test_echelon_to_dict_from_dict_round_trip()
	_test_echelon_to_dict_duplicates_child_array_defensively()

	_test_add_command_echelon_registers_a_root()
	_test_add_command_echelon_links_parent_and_child()
	_test_add_command_echelon_refuses_self_parent()
	_test_add_command_echelon_refuses_missing_parent()
	_test_add_command_echelon_refuses_parent_that_is_already_a_leaf()
	_test_attach_formation_to_echelon_makes_it_a_leaf()
	_test_attach_formation_refuses_when_echelon_has_children()

	_test_collect_formation_ids_single_leaf()
	_test_collect_formation_ids_multi_level_tree()
	_test_collect_formation_ids_empty_internal_echelon_is_empty()
	_test_collect_formation_ids_deduplicates_shared_formation()
	_test_collect_formation_ids_unknown_echelon_is_empty()

	_test_issue_echelon_order_cascades_change_course_to_every_child_formation()
	_test_issue_echelon_order_gives_each_formation_an_independent_order_instance()
	_test_issue_echelon_order_on_unknown_echelon_is_safe_noop()
	_test_issue_echelon_order_to_formation_missing_from_world_is_safe()

	_test_issue_echelon_order_is_recorded_once_not_per_formation()
	_test_replayed_echelon_order_reproduces_the_cascade()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
