extends SceneTree
const BeamFxMeshBuilder = preload("res://scripts/beam_fx_mesh_builder.gd")
## Headless smoke test for the procedural energy-weapon beam mesh (ТЗ
## §56.1 item 3). Run:
## godot4 --headless --script res://simulation/tests/test_beam_fx_mesh_builder.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_spans_length_along_negative_z()
	failures += _test_width_matches_x_and_y()
	failures += _test_longer_shot_produces_longer_beam()
	failures += _test_has_two_crossed_quads()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_spans_length_along_negative_z() -> int:
	var mesh: ArrayMesh = BeamFxMeshBuilder.build(1000.0, 60.0)
	var ok: bool = mesh != null and mesh.get_surface_count() == 1
	var aabb: AABB = mesh.get_aabb()
	# Built from z=0 to z=-length_m -- aabb.position.z should be the
	# negative end, aabb.size.z the full length (attack_geometry.gd
	# convention: -Z = bow/forward, see this builder's own header).
	ok = ok and is_equal_approx(aabb.size.z, 1000.0)
	ok = ok and is_equal_approx(aabb.position.z, -1000.0)
	if not ok:
		printerr("FAIL spans_length_along_negative_z: surfaces=%s aabb=%s" % [mesh.get_surface_count() if mesh else -1, aabb])
		return 1
	return 0

func _test_width_matches_x_and_y() -> int:
	var mesh: ArrayMesh = BeamFxMeshBuilder.build(1000.0, 60.0)
	var aabb: AABB = mesh.get_aabb()
	var ok: bool = is_equal_approx(aabb.size.x, 60.0) and is_equal_approx(aabb.size.y, 60.0)
	if not ok:
		printerr("FAIL width_matches_x_and_y: aabb=%s" % [aabb])
		return 1
	return 0

func _test_longer_shot_produces_longer_beam() -> int:
	var short_mesh: ArrayMesh = BeamFxMeshBuilder.build(500.0, 60.0)
	var long_mesh: ArrayMesh = BeamFxMeshBuilder.build(50000.0, 60.0)
	var ok: bool = long_mesh.get_aabb().size.z > short_mesh.get_aabb().size.z
	if not ok:
		printerr("FAIL longer_shot_produces_longer_beam: short=%s long=%s" % [short_mesh.get_aabb(), long_mesh.get_aabb()])
		return 1
	return 0

func _test_has_two_crossed_quads() -> int:
	var mesh: ArrayMesh = BeamFxMeshBuilder.build(1000.0, 60.0)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Two quads, 6 vertices each (two triangles, non-indexed) = 12.
	var ok: bool = verts.size() == 12
	if not ok:
		printerr("FAIL has_two_crossed_quads: vertex_count=%d" % verts.size())
		return 1
	return 0
