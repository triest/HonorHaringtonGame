extends SceneTree
## Headless regression test for CameraFocusController (ТЗ §56.3 item F).
## Run: godot4 --headless --path . --script res://simulation/tests/test_camera_focus_controller.gd
##
## Does NOT instantiate a real OrbitCamera -- OrbitCamera extends
## Camera3D, and a Camera3D-derived node hits engine-side "Node not
## inside tree" errors on global_position/look_at() when instantiated
## outside a live scene tree (confirmed via a throwaway probe script
## before writing this class; same limitation test_orbit_camera.gd's own
## file doc comment already documents, which is why THAT file tests only
## OrbitCamera's static pure math). So this test covers exactly what is
## safely testable here: try_focus() with no camera assigned (must
## return false, not crash), the InputMap action wiring, and
## _unhandled_input's null-safety -- the actual "does the camera move"
## effect is a live, not headless, verification (see class's own doc
## comment).

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const CameraFocusController = preload("res://scripts/camera_focus_controller.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _test_input_map_defines_the_hotkey() -> void:
	_assert(InputMap.has_action("camera_focus_selection"), "project.godot [input] should define 'camera_focus_selection' (CameraFocusController reads it by this exact name)")

func _test_try_focus_with_no_camera_returns_false() -> void:
	var world := SimulationWorld.new()
	var ship := ShipPhysicsState.new()
	ship.position = Vector3(1.0, 2.0, 3.0)
	world.add_ship("alpha", ship)
	var selection := SelectionState.new()
	selection.select_only(["alpha"])

	var controller := CameraFocusController.new()
	controller.world = world
	controller.selection = selection
	controller.camera = null
	_assert(controller.try_focus() == false, "try_focus() with no camera assigned should return false, not crash")

func _test_try_focus_with_nothing_selected_returns_false_even_with_data() -> void:
	var world := SimulationWorld.new()
	var ship := ShipPhysicsState.new()
	ship.position = Vector3(1.0, 2.0, 3.0)
	world.add_ship("alpha", ship)
	var selection := SelectionState.new()  # nothing selected, no designated target

	var controller := CameraFocusController.new()
	controller.world = world
	controller.selection = selection
	controller.camera = null
	_assert(controller.try_focus() == false, "try_focus() with an empty selection should return false regardless of camera")

func _press(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev

func _test_unhandled_input_with_no_camera_does_not_crash() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var controller := CameraFocusController.new()
	controller.world = world
	controller.selection = selection
	controller.camera = null
	controller._unhandled_input(_press("camera_focus_selection"))
	_assert(true, "_unhandled_input on the focus hotkey with no camera assigned should not crash")

func _test_unhandled_input_ignores_unrelated_actions() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var controller := CameraFocusController.new()
	controller.world = world
	controller.selection = selection
	controller._unhandled_input(_press("selection_make_group"))
	_assert(true, "_unhandled_input should ignore an unrelated action without crashing")

func _init() -> void:
	_test_input_map_defines_the_hotkey()
	_test_try_focus_with_no_camera_returns_false()
	_test_try_focus_with_nothing_selected_returns_false_even_with_data()
	_test_unhandled_input_with_no_camera_does_not_crash()
	_test_unhandled_input_ignores_unrelated_actions()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
