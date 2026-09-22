extends SceneTree
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
## Headless unit test for OrbitCamera's pure spherical-offset math (ТЗ
## §56.1 item 1: free/orbit camera). OrbitCamera extends Camera3D, so a
## camera-facing engine object requires a rendering context to fully
## instantiate in some Godot versions; this test exercises the pure
## static math directly (mirrors WedgeMeshBuilder._width_profile /
## ShipView._broadside_sidewall_visible's testable-pure-helper pattern)
## rather than instantiating the node.
## Run: godot4 --headless --script res://simulation/tests/test_orbit_camera.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_zero_yaw_zero_pitch_looks_along_positive_z()
	failures += _test_positive_pitch_raises_camera_above_pivot_plane()
	failures += _test_quarter_turn_yaw_moves_to_positive_x_axis()
	failures += _test_offset_magnitude_always_equals_distance()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_zero_yaw_zero_pitch_looks_along_positive_z() -> int:
	var offset: Vector3 = OrbitCamera._spherical_offset(0.0, 0.0, 1000.0)
	var ok: bool = is_equal_approx(offset.x, 0.0) and is_equal_approx(offset.y, 0.0) and is_equal_approx(offset.z, 1000.0)
	if not ok:
		printerr("FAIL zero_yaw_zero_pitch_looks_along_positive_z: offset=%s" % [offset])
		return 1
	return 0

func _test_positive_pitch_raises_camera_above_pivot_plane() -> int:
	var offset: Vector3 = OrbitCamera._spherical_offset(0.0, deg_to_rad(90.0), 1000.0)
	var ok: bool = is_equal_approx(offset.y, 1000.0) and absf(offset.x) < 0.01 and absf(offset.z) < 0.01
	if not ok:
		printerr("FAIL positive_pitch_raises_camera_above_pivot_plane: offset=%s" % [offset])
		return 1
	return 0

func _test_quarter_turn_yaw_moves_to_positive_x_axis() -> int:
	var offset: Vector3 = OrbitCamera._spherical_offset(deg_to_rad(90.0), 0.0, 1000.0)
	var ok: bool = is_equal_approx(offset.x, 1000.0) and absf(offset.z) < 0.01
	if not ok:
		printerr("FAIL quarter_turn_yaw_moves_to_positive_x_axis: offset=%s" % [offset])
		return 1
	return 0

func _test_offset_magnitude_always_equals_distance() -> int:
	var ok: bool = true
	for yaw_deg in [0, 37, 91, 200, 315]:
		for pitch_deg in [-70, -10, 0, 25, 60]:
			var offset: Vector3 = OrbitCamera._spherical_offset(deg_to_rad(yaw_deg), deg_to_rad(pitch_deg), 500.0)
			ok = ok and is_equal_approx(offset.length(), 500.0)
	if not ok:
		printerr("FAIL offset_magnitude_always_equals_distance")
		return 1
	return 0
