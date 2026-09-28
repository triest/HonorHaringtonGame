extends Node3D
## ScreenshotCapture (DEV TOOL, not part of the shipped game)
##
## Instances the main demo scene, waits a few frames for it to settle, then
## saves a PNG of the viewport and quits. Used to visually verify the
## procedural hull/wedge rendering without a human sitting at the Godot
## editor -- run with a real (non-headless) display, e.g. via Xvfb:
##   xvfb-run -a godot4 --path . res://scenes/dev/screenshot_capture.tscn
## Output path is read from the OS environment variable
## SCREENSHOT_OUTPUT_PATH, defaulting to user://screenshot.png.
class_name ScreenshotCapture

var _frames_waited: int = 0
const FRAMES_TO_WAIT: int = 10

func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	add_child(main_scene.instantiate())

var _presimmed: bool = false

## 2026-09-27: optional fast-forward before the shot (env SCREENSHOT_PRESIM_S,
## sim seconds, stepped at 0.1 s) so the capture can show a mid-battle state
## (missiles in flight) instead of only t=0. SCREENSHOT_RADAR_BIG=1 enlarges
## the tactical plot first.
func _presim() -> void:
	_presimmed = true
	var main: Node = get_child(0)
	var world: SimulationWorld = main.get("world")
	var secs: float = float(OS.get_environment("SCREENSHOT_PRESIM_S")) if OS.get_environment("SCREENSHOT_PRESIM_S") != "" else 0.0
	var dt: float = 0.1
	for i in range(int(secs / dt)):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
	world.clock.paused = true
	if OS.get_environment("SCREENSHOT_KEEP_BRIEFING") != "1" and main.get("mission_panel") != null:
		main.get("mission_panel").visible = false
	# 2026-09-28: the mission editor overlay (shown on top of the already-
	# built default mission, see main.gd's own doc comment) would otherwise
	# obscure every capture below it -- same hide as mission_panel above.
	if OS.get_environment("SCREENSHOT_KEEP_BRIEFING") != "1" and main.get("mission_editor") != null:
		main.get("mission_editor").visible = false
	if OS.get_environment("SCREENSHOT_KEEP_EDITOR") == "1" and main.get("mission_editor") != null:
		main.get("mission_editor").visible = true
		main.get("mission_panel").visible = false
	if OS.get_environment("SCREENSHOT_MIXED_SETUP") == "1":
		var setup := {
			"red": [{"class_id": "destroyer", "count": 2}, {"class_id": "battlecruiser", "count": 1}],
			"blue": [{"class_id": "light_cruiser", "count": 3}],
		}
		main.mission_editor.on_confirm.call(setup)
		main.get("mission_panel").visible = false
	# 2026-09-28 (dev-only, for verifying ShipCardsPanel scrolling with a
	# full 8-ship roster incl. the biggest module grids): SCREENSHOT_BIG_SETUP=1
	# builds the max-size mission (8 dreadnoughts a side).
	if OS.get_environment("SCREENSHOT_BIG_SETUP") == "1":
		var big_setup := {
			"red": [{"class_id": "dreadnought", "count": 4}, {"class_id": "superdreadnought", "count": 4}],
			"blue": [{"class_id": "dreadnought", "count": 4}, {"class_id": "superdreadnought", "count": 4}],
		}
		main.mission_editor.on_confirm.call(big_setup)
		main.get("mission_panel").visible = false
	var cfc0 = main.get("camera_focus_controller")
	var cam0 = main.get_node("Camera3D")
	if OS.get_environment("SCREENSHOT_VIEW") == "squadron":
		cfc0.view_own_squadron()
	elif OS.get_environment("SCREENSHOT_VIEW") == "all":
		cfc0.view_all()
	cam0._fly_t = 1.0
	cam0._pivot_offset = Vector3.ZERO
	if cam0.target_distance > 0.0:
		cam0.distance = cam0.target_distance
	cam0.target_distance = -1.0
	if OS.get_environment("SCREENSHOT_RADAR_BIG") == "1":
		main.get("tactical_plot").set_enlarged(true)
	var focus_id: String = OS.get_environment("SCREENSHOT_FOCUS")
	if focus_id != "":
		main.get("selection").select_only([focus_id])
		main.get("camera_focus_controller").try_focus()
		var zd: String = OS.get_environment("SCREENSHOT_ZOOM_M")
		if zd != "":
			var cam = main.get_node("Camera3D")
			cam._fly_t = 1.0
			cam._pivot_offset = Vector3.ZERO
			cam.target_distance = -1.0
			cam.distance = float(zd)
			cam._update_transform()
	if OS.get_environment("SCREENSHOT_CUBE") == "1":
		var cube := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(300, 300, 300)
		cube.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0, 0)
		cube.material_override = mat
		add_child(cube)
		cube.global_position = Vector3(600, 0, 0)
	if OS.get_environment("SCREENSHOT_DEBUG") == "1":
		var cam2 = main.get_node("Camera3D")
		print("DEBUG origin=", RenderOrigin.origin, " cam pos=", cam2.global_position, " near=", cam2.near, " far=", cam2.far)
		for ch in main.get_children():
			if ch is ShipView:
				print("DEBUG shipview ", ch.global_position, " vis=", ch.visible)
	main.call("_on_tick", 0.0, 0, 0.0)

func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited == 3 and not _presimmed:
		_presim()
	if _frames_waited < FRAMES_TO_WAIT:
		return

	if OS.get_environment("SCREENSHOT_DEBUG") == "1":
		var mainn: Node = get_child(0)
		var camx = mainn.get_node("Camera3D")
		print("DEBUG2 origin=", RenderOrigin.origin, " cam=", camx.global_position, " cur=", camx.current, " near=", camx.near, " far=", camx.far)
		for ch in mainn.get_children():
			if ch is ShipView:
				print("DEBUG2 shipview ", ch.global_position, " hull=", ch.hull_mesh_instance.global_position, " ", ch.hull_mesh_instance.get_aabb())
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = OS.get_environment("SCREENSHOT_OUTPUT_PATH")
	if output_path.is_empty():
		output_path = "user://screenshot.png"
	image.save_png(output_path)
	print("SCREENSHOT_SAVED: %s" % output_path)
	get_tree().quit()
