extends SceneTree
const SidewallMeshBuilder = preload("res://scripts/sidewall_mesh_builder.gd")
## Headless smoke test for the procedural sidewall panel meshes (flat
## broadside panel + flat bow/stern cap). Run:
## godot4 --headless --script res://simulation/tests/test_sidewall_mesh_builder.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_broadside_spans_length_and_height()
	failures += _test_broadside_is_flat_in_x()
	failures += _test_bow_stern_spans_width_and_height()
	failures += _test_bow_stern_is_flat_in_z()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_broadside_spans_length_and_height() -> int:
	var mesh: ArrayMesh = SidewallMeshBuilder.build_broadside(500.0, 54.0)
	var ok: bool = mesh != null and mesh.get_surface_count() == 1
	var aabb: AABB = mesh.get_aabb()
	# Broadside panel extends a bit past the 500m hull length (mirrors
	# WedgeMeshBuilder's own past-hull-length convention) and matches the
	# given height exactly.
	ok = ok and aabb.size.z > 500.0
	ok = ok and is_equal_approx(aabb.size.y, 54.0)
	if not ok:
		printerr("FAIL broadside_spans_length_and_height: surfaces=%s aabb=%s" % [mesh.get_surface_count() if mesh else -1, aabb])
		return 1
	return 0

func _test_broadside_is_flat_in_x() -> int:
	var mesh: ArrayMesh = SidewallMeshBuilder.build_broadside(500.0, 54.0)
	var aabb: AABB = mesh.get_aabb()
	var ok: bool = is_equal_approx(aabb.size.x, 0.0)
	if not ok:
		printerr("FAIL broadside_is_flat_in_x: aabb=%s" % [aabb])
		return 1
	return 0

func _test_bow_stern_spans_width_and_height() -> int:
	var mesh: ArrayMesh = SidewallMeshBuilder.build_bow_stern(99.0, 54.0)
	var ok: bool = mesh != null and mesh.get_surface_count() == 1
	var aabb: AABB = mesh.get_aabb()
	ok = ok and is_equal_approx(aabb.size.x, 99.0)
	ok = ok and is_equal_approx(aabb.size.y, 54.0)
	if not ok:
		printerr("FAIL bow_stern_spans_width_and_height: surfaces=%s aabb=%s" % [mesh.get_surface_count() if mesh else -1, aabb])
		return 1
	return 0

func _test_bow_stern_is_flat_in_z() -> int:
	var mesh: ArrayMesh = SidewallMeshBuilder.build_bow_stern(99.0, 54.0)
	var aabb: AABB = mesh.get_aabb()
	var ok: bool = is_equal_approx(aabb.size.z, 0.0)
	if not ok:
		printerr("FAIL bow_stern_is_flat_in_z: aabb=%s" % [aabb])
		return 1
	return 0
