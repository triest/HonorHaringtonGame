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

func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited < FRAMES_TO_WAIT:
		return

	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = OS.get_environment("SCREENSHOT_OUTPUT_PATH")
	if output_path.is_empty():
		output_path = "user://screenshot.png"
	image.save_png(output_path)
	print("SCREENSHOT_SAVED: %s" % output_path)
	get_tree().quit()
