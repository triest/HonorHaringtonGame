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
	if OS.get_environment("SCREENSHOT_RADAR_BIG") == "1":
		main.get("tactical_plot").set_enlarged(true)
	main.call("_on_tick", 0.0, 0, 0.0)

func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited == 3 and not _presimmed:
		_presim()
	if _frames_waited < FRAMES_TO_WAIT:
		return

	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = OS.get_environment("SCREENSHOT_OUTPUT_PATH")
	if output_path.is_empty():
		output_path = "user://screenshot.png"
	image.save_png(output_path)
	print("SCREENSHOT_SAVED: %s" % output_path)
	get_tree().quit()
