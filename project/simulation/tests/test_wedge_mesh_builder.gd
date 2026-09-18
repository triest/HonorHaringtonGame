extends SceneTree
const WedgeMeshBuilder = preload("res://scripts/wedge_mesh_builder.gd")
## Headless smoke test for the procedural wedge mesh (V-cross-section,
## flaring toward bow/stern). Run: godot4 --headless --script res://simulation/tests/test_wedge_mesh_builder.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_mesh_builds_and_extends_past_hull_length()
	failures += _test_top_and_bottom_mirror_correctly()
	failures += _test_width_profile_narrow_amidships_wide_at_ends()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_mesh_builds_and_extends_past_hull_length() -> int:
	var mesh: ArrayMesh = WedgeMeshBuilder.build(500.0, 99.0, 54.0, 1.0)
	var ok: bool = mesh != null and mesh.get_surface_count() == 1
	var aabb: AABB = mesh.get_aabb()
	# Wedge is meant to extend a bit past the 500m hull length (bow/stern
	# generators), and its ridge sits at +ridge_height (top wedge, sign=1).
	ok = ok and aabb.size.z > 500.0
	ok = ok and aabb.position.y >= 0.0  # top wedge should not dip below y=0
	if not ok:
		printerr("FAIL mesh_builds_and_extends_past_hull_length: surfaces=%s aabb=%s" % [mesh.get_surface_count() if mesh else -1, aabb])
		return 1
	return 0

func _test_top_and_bottom_mirror_correctly() -> int:
	var top: ArrayMesh = WedgeMeshBuilder.build(500.0, 99.0, 54.0, 1.0)
	var bottom: ArrayMesh = WedgeMeshBuilder.build(500.0, 99.0, 54.0, -1.0)
	var top_aabb: AABB = top.get_aabb()
	var bottom_aabb: AABB = bottom.get_aabb()
	var ok: bool = top_aabb.position.y >= 0.0 and (bottom_aabb.position.y + bottom_aabb.size.y) <= 0.01
	if not ok:
		printerr("FAIL top_and_bottom_mirror_correctly: top=%s bottom=%s" % [top_aabb, bottom_aabb])
		return 1
	return 0

func _test_width_profile_narrow_amidships_wide_at_ends() -> int:
	var mid: float = WedgeMeshBuilder._width_profile(0.0)
	var end: float = WedgeMeshBuilder._width_profile(1.0)
	var ok: bool = end > mid
	if not ok:
		printerr("FAIL width_profile_narrow_amidships_wide_at_ends: mid=%s end=%s" % [mid, end])
		return 1
	return 0
