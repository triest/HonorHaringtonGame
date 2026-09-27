extends SceneTree
## 2026-09-27: headless check of the camera view/back flow on the real
## main scene (user: "zoom into a ship at any moment, then go back").
## Run: godot4 --headless --path . --script res://simulation/tests/test_camera_views.gd
var main
var n: int = 0
var d0: float
var fails: int = 0
var passed: int = 0

func _check(c: bool, m: String) -> void:
	if c:
		passed += 1
	else:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)

func _process(_d: float) -> bool:
	n += 1
	var cam = main.get_node("Camera3D")
	var cfc = main.camera_focus_controller
	if n == 3:
		main.world.clock.paused = true
		d0 = cam.distance
		cfc.view_ids(["alpha_2"], true)
	elif n == 200:
		_check(absf(cam.distance - cfc.CLOSE_UP_DISTANCE_M) < 20.0, "close-up distance should settle at %f, got %f" % [cfc.CLOSE_UP_DISTANCE_M, cam.distance])
		_check(cam.look_point().distance_to(main.world.ships["alpha_2"].position) < 100.0, "camera should look at alpha_2, off by %f m" % cam.look_point().distance_to(main.world.ships["alpha_2"].position))
		_check(RenderOrigin.origin.distance_to(main.world.ships["alpha_2"].position) < 100.0, "render origin should be at the followed ship")
		cfc.back()
	elif n == 400:
		_check(absf(cam.distance / d0 - 1.0) < 0.01, "back() should restore the overview distance %f, got %f" % [d0, cam.distance])
		_check(cfc.follow_ids.is_empty(), "overview had no follow target; back() should restore that")
		cfc.view_all()
		cfc.view_own_squadron()
		cfc.back()
		cfc.back()
	elif n == 600:
		_check(absf(cam.distance / d0 - 1.0) < 0.05, "two backs after all+squadron should return near the overview distance")
		print("Passed: ", passed, " Failed: ", fails)
		print("ALL TESTS PASSED" if fails == 0 else "SOME TESTS FAILED")
		quit(1 if fails > 0 else 0)
	return false
