extends SceneTree
## Headless regression test for CommandGroupPanel's §56.3 item F layout
## change: its position must now track a caller-supplied `hud_bottom_y`
## instead of a fixed guessed constant.
## Run: godot4 --headless --path . --script res://simulation/tests/test_command_group_panel.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const CommandGroupPanel = preload("res://scripts/command_group_panel.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _test_update_positions_label_below_given_hud_bottom_y() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var panel := CommandGroupPanel.new()
	get_root().add_child(panel)
	panel._ready()

	panel.update(world, selection, 100.0)
	var label: Label = panel.get_node_or_null("CommandGroupLabel")
	_assert(label != null, "sanity: CommandGroupPanel._ready() should create CommandGroupLabel")
	if label != null:
		_assert(is_equal_approx(label.position.y, 100.0 + CommandGroupPanel.TOP_MARGIN_PX), "label.position.y should be hud_bottom_y + TOP_MARGIN_PX (100 + %f), got %f" % [CommandGroupPanel.TOP_MARGIN_PX, label.position.y])
		_assert(is_equal_approx(label.position.x, 12.0), "label.position.x should stay at the fixed left margin (12), got %f" % label.position.x)

	panel.update(world, selection, 500.0)
	_assert(is_equal_approx(label.position.y, 500.0 + CommandGroupPanel.TOP_MARGIN_PX), "a later update() with a different hud_bottom_y should move the label again, not stick to the first value")
	panel.queue_free()

func _test_update_without_hud_bottom_y_uses_fallback() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var panel := CommandGroupPanel.new()
	get_root().add_child(panel)
	panel._ready()

	panel.update(world, selection)  # no third arg -- default param path
	var label: Label = panel.get_node_or_null("CommandGroupLabel")
	_assert(label != null, "sanity: CommandGroupLabel should exist")
	if label != null:
		_assert(is_equal_approx(label.position.y, CommandGroupPanel.FALLBACK_TOP_Y + CommandGroupPanel.TOP_MARGIN_PX), "update() called with no hud_bottom_y argument should fall back to FALLBACK_TOP_Y, got %f" % label.position.y)
	panel.queue_free()

func _init() -> void:
	_test_update_positions_label_below_given_hud_bottom_y()
	_test_update_without_hud_bottom_y_uses_fallback()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
