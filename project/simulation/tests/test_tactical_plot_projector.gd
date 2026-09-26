extends SceneTree
const TacticalPlotProjector = preload("res://scripts/tactical_plot_projector.gd")
## Headless unit test for the pure world->plot mapping (ТЗ §56.2 items
## A/B tactical plot). Run:
## godot4 --headless --script res://simulation/tests/test_tactical_plot_projector.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_contact_dead_ahead_has_zero_bearing()
	failures += _test_contact_to_starboard_has_90deg_bearing()
	failures += _test_contact_astern_has_180deg_bearing()
	failures += _test_range_m_is_true_distance_even_when_clamped()
	failures += _test_within_range_is_not_clamped_and_scales_linearly()
	failures += _test_beyond_range_is_clamped_to_rim()
	failures += _test_same_position_as_origin_does_not_crash()
	failures += _test_farther_contact_has_larger_pixel_offset_until_clamped()
	failures += _test_unproject_is_inverse_of_project_within_range()
	failures += _test_unproject_center_click_is_origin()
	failures += _test_unproject_keeps_origin_y()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_contact_dead_ahead_has_zero_bearing() -> int:
	# -Z = "north"/bearing 0, matching attack_geometry.gd's own
	# "-Z = bow/forward" convention (see tactical_plot_projector.gd doc).
	var result: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, -1000.0), Vector3.ZERO, 10000.0, 100.0)
	var ok: bool = is_equal_approx(result["bearing_rad"], 0.0) or is_equal_approx(result["bearing_rad"], TAU)
	if not ok:
		printerr("FAIL contact_dead_ahead_has_zero_bearing: bearing=%s" % result["bearing_rad"])
		return 1
	return 0

func _test_contact_to_starboard_has_90deg_bearing() -> int:
	var result: Dictionary = TacticalPlotProjector.project(Vector3(1000.0, 0, 0), Vector3.ZERO, 10000.0, 100.0)
	var ok: bool = is_equal_approx(result["bearing_rad"], PI * 0.5)
	if not ok:
		printerr("FAIL contact_to_starboard_has_90deg_bearing: bearing=%s (expected %s)" % [result["bearing_rad"], PI * 0.5])
		return 1
	return 0

func _test_contact_astern_has_180deg_bearing() -> int:
	var result: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, 1000.0), Vector3.ZERO, 10000.0, 100.0)
	var ok: bool = is_equal_approx(result["bearing_rad"], PI)
	if not ok:
		printerr("FAIL contact_astern_has_180deg_bearing: bearing=%s (expected %s)" % [result["bearing_rad"], PI])
		return 1
	return 0

func _test_range_m_is_true_distance_even_when_clamped() -> int:
	var far_pos := Vector3(0, 0, -9_000_000.0)
	var result: Dictionary = TacticalPlotProjector.project(far_pos, Vector3.ZERO, 100_000.0, 100.0)
	var ok: bool = is_equal_approx(result["range_m"], 9_000_000.0) and result["clamped"] == true
	if not ok:
		printerr("FAIL range_m_is_true_distance_even_when_clamped: range_m=%s clamped=%s" % [result["range_m"], result["clamped"]])
		return 1
	return 0

func _test_within_range_is_not_clamped_and_scales_linearly() -> int:
	# Half the plot_range_m away should land at half the pixel radius --
	# the whole point of "linear radial scale" (class doc).
	var result: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, -5000.0), Vector3.ZERO, 10000.0, 100.0)
	var offset: Vector2 = result["plot_offset_px"]
	var ok: bool = result["clamped"] == false and is_equal_approx(offset.length(), 50.0)
	if not ok:
		printerr("FAIL within_range_is_not_clamped_and_scales_linearly: offset=%s clamped=%s" % [offset, result["clamped"]])
		return 1
	return 0

func _test_beyond_range_is_clamped_to_rim() -> int:
	var result: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, -50_000.0), Vector3.ZERO, 10000.0, 100.0)
	var offset: Vector2 = result["plot_offset_px"]
	var ok: bool = result["clamped"] == true and is_equal_approx(offset.length(), 100.0)
	if not ok:
		printerr("FAIL beyond_range_is_clamped_to_rim: offset=%s len=%s clamped=%s" % [offset, offset.length(), result["clamped"]])
		return 1
	return 0

func _test_same_position_as_origin_does_not_crash() -> int:
	var result: Dictionary = TacticalPlotProjector.project(Vector3.ZERO, Vector3.ZERO, 10000.0, 100.0)
	var offset: Vector2 = result["plot_offset_px"]
	var ok: bool = is_equal_approx(result["range_m"], 0.0) and is_equal_approx(offset.length(), 0.0)
	if not ok:
		printerr("FAIL same_position_as_origin_does_not_crash: range_m=%s offset=%s" % [result["range_m"], offset])
		return 1
	return 0

func _test_farther_contact_has_larger_pixel_offset_until_clamped() -> int:
	var near: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, -1000.0), Vector3.ZERO, 10000.0, 100.0)
	var far: Dictionary = TacticalPlotProjector.project(Vector3(0, 0, -8000.0), Vector3.ZERO, 10000.0, 100.0)
	var ok: bool = far["plot_offset_px"].length() > near["plot_offset_px"].length()
	if not ok:
		printerr("FAIL farther_contact_has_larger_pixel_offset_until_clamped: near=%s far=%s" % [near["plot_offset_px"], far["plot_offset_px"]])
		return 1
	return 0

## ТЗ §56.3 item C ("RMB по точке пространства"): unproject() must be the
## exact algebraic inverse of project() for any UNCLAMPED point -- a click
## on the plot should recover the same world point a contact drawn there
## would represent.
func _test_unproject_is_inverse_of_project_within_range() -> int:
	var origin := Vector3(1000.0, 0.0, -2000.0)
	var world_pos := Vector3(1000.0, 0.0, -7000.0)  # dead ahead, within range
	var projected: Dictionary = TacticalPlotProjector.project(world_pos, origin, 10000.0, 100.0)
	var recovered: Vector3 = TacticalPlotProjector.unproject(projected["plot_offset_px"], origin, 10000.0, 100.0)
	if recovered.distance_to(world_pos) > 0.01:
		printerr("FAIL unproject_is_inverse_of_project_within_range: recovered=%s expected=%s" % [recovered, world_pos])
		return 1
	return 0

func _test_unproject_center_click_is_origin() -> int:
	var origin := Vector3(500.0, 0.0, 500.0)
	var recovered: Vector3 = TacticalPlotProjector.unproject(Vector2.ZERO, origin, 10000.0, 100.0)
	if recovered.distance_to(origin) > 0.001:
		printerr("FAIL unproject_center_click_is_origin: recovered=%s expected=%s" % [recovered, origin])
		return 1
	return 0

## The plot is a flat top-down display with no altitude axis -- a click
## always resolves to the origin's own Y, regardless of plot_offset_px.
func _test_unproject_keeps_origin_y() -> int:
	var origin := Vector3(0.0, 12345.0, 0.0)
	var recovered: Vector3 = TacticalPlotProjector.unproject(Vector2(30.0, -20.0), origin, 10000.0, 100.0)
	if not is_equal_approx(recovered.y, 12345.0):
		printerr("FAIL unproject_keeps_origin_y: recovered.y=%s expected=12345.0" % recovered.y)
		return 1
	return 0
