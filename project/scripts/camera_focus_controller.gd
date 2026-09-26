extends Node
## CameraFocusController
##
## §56.3 item F: translates the quick-center hotkey (project.godot
## [input] "camera_focus_selection") into a CameraFocus.compute() call
## fed to OrbitCamera.focus_on(). Same convention as PlayerInput
## (scripts/player_input.gd, ТЗ §56.1 item 5): a plain Node added to the
## tree so it can receive _unhandled_input, reading a named Input Map
## action rather than a raw key check (unlike OrbitCamera's own existing
## orbit/zoom controls -- see that file's updated class doc comment for
## why those were left alone).
##
## Split into _unhandled_input (the only Input-touching line) and
## try_focus() (everything else) so a headless test can call try_focus()
## directly with a synthetic world/selection and no InputEvent at all --
## same split as OrderMenuController.try_open(), and same reasoning as
## PlayerInput's own test file (simulation/tests/test_player_input.gd)
## for why _unhandled_input itself is still exercised too, via a
## synthetic InputEventAction (no live window/mouse needed for that
## either).
##
## `camera` is deliberately NOT exercised by this class's own headless
## test with a REAL OrbitCamera instance -- OrbitCamera extends
## Camera3D, and instantiating a Camera3D-derived node outside a live
## scene tree hits the exact same engine-side "not inside tree"
## limitation already logged in test_orbit_camera.gd's own file doc
## comment (confirmed again this pass with a throwaway probe script
## before writing this class, not just assumed). So this file's own test
## exercises try_focus() with `camera = null` (must return false, not
## crash) and CameraFocus.compute() directly and thoroughly (pure, no
## such limitation) -- the actual live "does pressing Home move the
## camera" effect is headless-unverifiable, same honest-gap status as
## every other §56.3 item's live-input effect (B/C/D/E) before a real
## player's own pass.
class_name CameraFocusController

var world: SimulationWorld = null
var selection: SelectionState = null
var camera: OrbitCamera = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_focus_selection"):
		try_focus()

## Returns true if a focus point was resolved and applied, false if
## there was nothing to focus on (no camera assigned, or CameraFocus.
## compute() came back empty) -- callers may ignore the return value;
## it exists purely to make this testable without inspecting camera
## state.
func try_focus() -> bool:
	if camera == null:
		return false
	var result: Dictionary = CameraFocus.compute(world, selection)
	if result.is_empty():
		return false
	camera.focus_on(result["pivot"], result["spread"])
	return true
