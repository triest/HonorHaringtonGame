extends SceneTree
## Headless unit test for CameraFocus.compute() (ТЗ §56.3 item F,
## quick-center on selection/group/contact).
## Run: godot4 --headless --path . --script res://simulation/tests/test_camera_focus.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const CameraFocus = preload("res://scripts/camera_focus.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(position: Vector3) -> ShipPhysicsState:
	var ship := ShipPhysicsState.new()
	ship.position = position
	return ship

func _test_empty_selection_and_no_target_returns_empty_dict() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var result: Dictionary = CameraFocus.compute(world, selection)
	_assert(result.is_empty(), "no selection and no designated target should return {} (nothing to focus on)")

func _test_null_world_or_selection_returns_empty_dict() -> void:
	var selection := SelectionState.new()
	_assert(CameraFocus.compute(null, selection).is_empty(), "null world should return {}, not crash")
	var world := SimulationWorld.new()
	_assert(CameraFocus.compute(world, null).is_empty(), "null selection should return {}, not crash")

func _test_single_selected_ship_centers_on_its_own_position() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3(1000.0, 0.0, 2000.0)))
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var result: Dictionary = CameraFocus.compute(world, selection)
	_assert(not result.is_empty(), "a single selected ship should resolve to a focus point")
	_assert(result["pivot"].is_equal_approx(Vector3(1000.0, 0.0, 2000.0)), "pivot should equal the lone selected ship's position, got %s" % [result.get("pivot")])
	_assert(result["spread"] >= CameraFocus.MIN_FOCUS_SPREAD_M, "spread for a single ship should be floored at MIN_FOCUS_SPREAD_M, got %f" % result.get("spread", -1.0))

func _test_multi_ship_selection_centers_on_centroid_with_real_spread() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3(-5000.0, 0.0, 0.0)))
	world.add_ship("beta", _make_ship(Vector3(5000.0, 0.0, 0.0)))
	var selection := SelectionState.new()
	selection.select_only(["alpha", "beta"])
	var result: Dictionary = CameraFocus.compute(world, selection)
	_assert(not result.is_empty(), "a two-ship selection should resolve to a focus point")
	_assert(result["pivot"].is_equal_approx(Vector3.ZERO), "pivot should be the midpoint of the two ships, got %s" % [result.get("pivot")])
	_assert(is_equal_approx(result["spread"], 5000.0), "spread should be the centroid-to-farthest-member distance (5000), got %f" % result.get("spread", -1.0))

func _test_missile_selection_resolves_via_world_missiles() -> void:
	var world := SimulationWorld.new()
	var missile := MissileState.new()
	missile.position = Vector3(100.0, 0.0, 0.0)
	world.missiles["m1"] = missile
	var selection := SelectionState.new()
	selection.select_only(["m1"])
	var result: Dictionary = CameraFocus.compute(world, selection)
	_assert(not result.is_empty(), "a selected missile id should resolve via world.missiles")
	_assert(result["pivot"].is_equal_approx(Vector3(100.0, 0.0, 0.0)), "pivot should equal the missile's position, got %s" % [result.get("pivot")])

func _test_unresolvable_ids_are_skipped_not_fatal() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3(10.0, 0.0, 0.0)))
	var selection := SelectionState.new()
	selection.select_only(["alpha", "ghost_id_nothing_has"])
	var result: Dictionary = CameraFocus.compute(world, selection)
	_assert(not result.is_empty(), "one resolvable id among several should still produce a result")
	_assert(result["pivot"].is_equal_approx(Vector3(10.0, 0.0, 0.0)), "the unresolvable id should simply be skipped, not counted into the centroid, got %s" % [result.get("pivot")])

	var selection_all_bad := SelectionState.new()
	selection_all_bad.select_only(["ghost_a", "ghost_b"])
	_assert(CameraFocus.compute(world, selection_all_bad).is_empty(), "if every selected id is unresolvable, compute() should return {}, not a garbage centroid")

func _test_designated_target_used_only_when_selection_is_empty() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3(1.0, 0.0, 0.0)))
	world.add_ship("hostile", _make_ship(Vector3(999.0, 0.0, 0.0)))

	var selection_with_own := SelectionState.new()
	selection_with_own.select_only(["alpha"])
	selection_with_own.designate_target("hostile")
	var result_with_own: Dictionary = CameraFocus.compute(world, selection_with_own)
	_assert(result_with_own["pivot"].is_equal_approx(Vector3(1.0, 0.0, 0.0)), "own selection should win over a designated target when both exist, got %s" % [result_with_own.get("pivot")])

	var selection_target_only := SelectionState.new()
	selection_target_only.designate_target("hostile")
	var result_target_only: Dictionary = CameraFocus.compute(world, selection_target_only)
	_assert(not result_target_only.is_empty(), "a designated target with no own selection should still resolve to a focus point")
	_assert(result_target_only["pivot"].is_equal_approx(Vector3(999.0, 0.0, 0.0)), "with no own selection, the designated target's position should be used, got %s" % [result_target_only.get("pivot")])

func _init() -> void:
	_test_empty_selection_and_no_target_returns_empty_dict()
	_test_null_world_or_selection_returns_empty_dict()
	_test_single_selected_ship_centers_on_its_own_position()
	_test_multi_ship_selection_centers_on_centroid_with_real_spread()
	_test_missile_selection_resolves_via_world_missiles()
	_test_unresolvable_ids_are_skipped_not_fatal()
	_test_designated_target_used_only_when_selection_is_empty()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
