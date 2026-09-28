extends SceneTree
const HullMeshBuilder = preload("res://scripts/hull_mesh_builder.gd")
## Headless smoke test for the procedural hull mesh (rendering-layer, but
## pure-data enough to sanity check headless): builds without error, has
## a plausible vertex count, and its bounding box roughly matches the
## requested dimensions (within the "flattened spindle" taper -- bow/stern
## points are individual vertices at radius_scale ~0.02, not exactly 0,
## so the box should be close to but not exceed the requested envelope).
## Run: godot4 --headless --script res://simulation/tests/test_hull_mesh_builder.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_mesh_builds_with_plausible_geometry()
	failures += _test_radius_profile_is_narrow_at_ends_wide_in_middle()
	failures += _test_radius_profile_never_fully_degenerate()
	failures += _test_cross_section_cardinal_points_stay_on_unit_bounds()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_mesh_builds_with_plausible_geometry() -> int:
	var mesh: ArrayMesh = HullMeshBuilder.build(500.0, 90.0, 60.0, 14, 16)
	var ok: bool = mesh != null and mesh.get_surface_count() == 1

	var aabb: AABB = mesh.get_aabb()
	ok = ok and aabb.size.z <= 500.1 and aabb.size.z > 400.0
	ok = ok and aabb.size.x <= 90.1
	ok = ok and aabb.size.y <= 60.1

	if not ok:
		printerr("FAIL mesh_builds_with_plausible_geometry: surfaces=%s aabb=%s" % [mesh.get_surface_count() if mesh else -1, aabb])
		return 1
	return 0

func _test_radius_profile_is_narrow_at_ends_wide_in_middle() -> int:
	var at_bow: float = HullMeshBuilder._radius_profile(-1.0)
	var at_mid: float = HullMeshBuilder._radius_profile(0.0)
	var at_stern: float = HullMeshBuilder._radius_profile(1.0)
	var ok: bool = at_mid > at_bow and at_mid > at_stern and at_mid > 0.9
	if not ok:
		printerr("FAIL radius_profile_is_narrow_at_ends_wide_in_middle: bow=%s mid=%s stern=%s" % [at_bow, at_mid, at_stern])
		return 1
	return 0

func _test_radius_profile_never_fully_degenerate() -> int:
	# Every sampled point along the profile must stay > 0 so no ring
	# collapses to a single degenerate point except the explicit tip caps.
	var ok: bool = true
	for i in range(21):
		var t: float = -1.0 + 2.0 * float(i) / 20.0
		var r: float = HullMeshBuilder._radius_profile(t)
		if r <= 0.0:
			ok = false
			break
	if not ok:
		printerr("FAIL radius_profile_never_fully_degenerate")
		return 1
	return 0

## 2026-09-28 (user: "модели кораблей и импеллеров то улучши"): the new
## superellipse cross-section (_cross_section_unit, CROSS_SECTION_
## EXPONENT) must still land EXACTLY on the unit circle's cardinal points
## for any exponent -- that's what keeps the mesh's overall bounding box
## identical to the old pure-circle version (see
## _test_mesh_builds_with_plausible_geometry's aabb.size checks above,
## which this guards the precondition for).
func _test_cross_section_cardinal_points_stay_on_unit_bounds() -> int:
	var right: Vector2 = HullMeshBuilder._cross_section_unit(0.0)
	var top: Vector2 = HullMeshBuilder._cross_section_unit(PI * 0.5)
	var left: Vector2 = HullMeshBuilder._cross_section_unit(PI)
	var bottom: Vector2 = HullMeshBuilder._cross_section_unit(PI * 1.5)
	var ok: bool = right.is_equal_approx(Vector2(1.0, 0.0))
	ok = ok and top.is_equal_approx(Vector2(0.0, 1.0))
	ok = ok and left.is_equal_approx(Vector2(-1.0, 0.0))
	ok = ok and bottom.is_equal_approx(Vector2(0.0, -1.0))
	if not ok:
		printerr("FAIL cross_section_cardinal_points_stay_on_unit_bounds: right=%s top=%s left=%s bottom=%s" % [right, top, left, bottom])
		return 1
	return 0
