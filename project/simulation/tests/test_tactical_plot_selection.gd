extends SceneTree
const TacticalPlotSelection = preload("res://scripts/tactical_plot_selection.gd")
## Headless unit test for the pure plot hit-testing geometry (ТЗ §56.3
## item A). Run:
## godot4 --headless --script res://simulation/tests/test_tactical_plot_selection.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_hit_test_finds_icon_under_point()
	failures += _test_hit_test_misses_when_outside_radius()
	failures += _test_hit_test_returns_empty_for_no_icons()
	failures += _test_hit_test_prefers_closest_overlapping_icon()
	failures += _test_box_test_finds_icons_inside_rect()
	failures += _test_box_test_excludes_icons_outside_rect()
	failures += _test_box_test_returns_empty_for_no_icons_in_rect()
	failures += _test_box_test_works_with_reversed_drag_rect()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_hit_test_finds_icon_under_point() -> int:
	var icons: Array = [{"id": "alpha", "pos": Vector2(100, 100), "radius": 10.0}]
	var hit: String = TacticalPlotSelection.hit_test(Vector2(104, 98), icons)
	if hit != "alpha":
		printerr("FAIL hit_test_finds_icon_under_point: hit=%s" % hit)
		return 1
	return 0

func _test_hit_test_misses_when_outside_radius() -> int:
	var icons: Array = [{"id": "alpha", "pos": Vector2(100, 100), "radius": 10.0}]
	var hit: String = TacticalPlotSelection.hit_test(Vector2(200, 200), icons)
	if hit != "":
		printerr("FAIL hit_test_misses_when_outside_radius: hit=%s" % hit)
		return 1
	return 0

func _test_hit_test_returns_empty_for_no_icons() -> int:
	var hit: String = TacticalPlotSelection.hit_test(Vector2(0, 0), [])
	if hit != "":
		printerr("FAIL hit_test_returns_empty_for_no_icons: hit=%s" % hit)
		return 1
	return 0

func _test_hit_test_prefers_closest_overlapping_icon() -> int:
	# Two icons both within hit radius of the click point -- the nearer
	# one must win, not whichever happens to be earlier in the array.
	var icons: Array = [
		{"id": "far", "pos": Vector2(100, 100), "radius": 30.0},
		{"id": "near", "pos": Vector2(105, 100), "radius": 30.0},
	]
	var hit: String = TacticalPlotSelection.hit_test(Vector2(104, 100), icons)
	if hit != "near":
		printerr("FAIL hit_test_prefers_closest_overlapping_icon: hit=%s" % hit)
		return 1
	return 0

func _test_box_test_finds_icons_inside_rect() -> int:
	var icons: Array = [
		{"id": "inside", "pos": Vector2(50, 50), "radius": 5.0},
		{"id": "outside", "pos": Vector2(500, 500), "radius": 5.0},
	]
	var rect := Rect2(Vector2(0, 0), Vector2(100, 100))
	var hits: Array = TacticalPlotSelection.box_test(rect, icons)
	if hits != ["inside"]:
		printerr("FAIL box_test_finds_icons_inside_rect: hits=%s" % [hits])
		return 1
	return 0

func _test_box_test_excludes_icons_outside_rect() -> int:
	var icons: Array = [{"id": "outside", "pos": Vector2(500, 500), "radius": 5.0}]
	var rect := Rect2(Vector2(0, 0), Vector2(100, 100))
	var hits: Array = TacticalPlotSelection.box_test(rect, icons)
	if not hits.is_empty():
		printerr("FAIL box_test_excludes_icons_outside_rect: hits=%s" % [hits])
		return 1
	return 0

func _test_box_test_returns_empty_for_no_icons_in_rect() -> int:
	var hits: Array = TacticalPlotSelection.box_test(Rect2(Vector2(0, 0), Vector2(10, 10)), [])
	if not hits.is_empty():
		printerr("FAIL box_test_returns_empty_for_no_icons_in_rect: hits=%s" % [hits])
		return 1
	return 0

func _test_box_test_works_with_reversed_drag_rect() -> int:
	# Simulates a drag from bottom-right to top-left -- caller is
	# expected to normalize via Rect2(a, b - a).abs() before calling,
	# per this file's own doc comment; verify that normalized rect
	# still finds the icon regardless of drag direction.
	var drag_start := Vector2(100, 100)
	var drag_end := Vector2(20, 20)
	var rect := Rect2(drag_start, drag_end - drag_start).abs()
	var icons: Array = [{"id": "inside", "pos": Vector2(50, 50), "radius": 5.0}]
	var hits: Array = TacticalPlotSelection.box_test(rect, icons)
	if hits != ["inside"]:
		printerr("FAIL box_test_works_with_reversed_drag_rect: hits=%s rect=%s" % [hits, rect])
		return 1
	return 0
