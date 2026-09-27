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

## §56.3 item J sub-piece 2: styled background panel must exist, sit
## behind the label (lower child index), ignore mouse, and hug the label
## with PANEL_PADDING_PX on every side; get_bottom_y() must report the
## background's real bottom edge.
func _test_background_panel_hugs_label() -> void:
	var world := SimulationWorld.new()
	var selection := SelectionState.new()
	var panel := CommandGroupPanel.new()
	get_root().add_child(panel)
	panel._ready()
	panel.update(world, selection, 200.0)
	var bg: Panel = panel.get_node_or_null("CommandGroupBackground")
	var label: Label = panel.get_node_or_null("CommandGroupLabel")
	_assert(bg != null, "CommandGroupPanel._ready() should create CommandGroupBackground")
	if bg != null and label != null:
		_assert(bg.get_index() < label.get_index(), "background must be added before (drawn behind) the label")
		_assert(bg.mouse_filter == Control.MOUSE_FILTER_IGNORE, "background must not consume mouse events")
		var pad: float = CommandGroupPanel.PANEL_PADDING_PX
		_assert(bg.position.is_equal_approx(label.position - Vector2(pad, pad)), "background top-left should be label.position - padding, got %s vs label %s" % [bg.position, label.position])
		_assert(bg.size.is_equal_approx(label.get_minimum_size() + Vector2(pad, pad) * 2.0), "background size should be label min size + 2*padding")
		_assert(is_equal_approx(panel.get_bottom_y(), bg.position.y + bg.size.y), "get_bottom_y() should be the background's bottom edge")
		_assert(bg.get_theme_stylebox("panel") is StyleBoxFlat, "background should use UiTheme's StyleBoxFlat override")
	panel.queue_free()

func _init() -> void:
	_test_background_panel_hugs_label()
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
