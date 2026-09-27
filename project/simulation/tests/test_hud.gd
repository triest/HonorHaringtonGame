extends SceneTree
## Headless regression test for Hud (ТЗ §56.1 item 4).
## Run: godot4 --headless --path . --script res://simulation/tests/test_hud.gd
##
## Written in response to a 2026-09-23 live bug report: the exported
## Windows build showed the 3D scene fine but NO on-screen HUD text at
## all. Investigation (see CHANGELOG.md / .tools/state.md for that date)
## found that Hud's own data pipeline -- _ready() creating the Label,
## update() setting its text, CanvasLayer/Label visibility -- is correct:
## reproduced both in pure --headless (dummy renderer, this test) and in
## an actual Xvfb-rendered run (real OpenGL display, screenshot verified).
## This test locks that in as a regression guard: if a future change ever
## makes Hud stop creating a visible, non-empty Label after one update(),
## this test catches it without needing a real window.
##
## What this test CANNOT verify (documented, not a gap in this test):
## whether the label's pixels actually get composited to screen on a real
## Windows machine under the project's configured Forward+/Vulkan
## renderer and that machine's specific GPU/driver -- there is no Vulkan
## implementation available in this headless environment. If the HUD is
## still reported invisible after a live re-test on real Windows with
## this test passing, the bug is downstream of Godot's own scripting
## layer (renderer/driver interaction) and needs a live Windows repro,
## not another headless test.
##
## §56.3 item J (visual polish pass): added coverage for the new styled
## background Panel (scripts/hud.gd's `_background`, scripts/ui_theme.gd)
## -- exists, uses a real StyleBoxFlat (not the engine default), is added
## BEFORE the label in child order (so it draws behind, not on top/hiding
## the text), and hugs the label's real measured bounds with padding.
## get_bottom_y()'s own expected-value formula was updated to match its
## new, more-correct meaning (the background panel's real bottom edge --
## see that method's own doc comment for why) rather than kept pointing
## at the pre-item-J bare-label formula, per this codebase's existing
## convention of rewriting a test whose old assertion encoded since-
## superseded behavior rather than leaving it checking the wrong thing
## (see e.g. §56.3 item I's test_move_order_controller.gd rewrite).

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const Hud = preload("res://scripts/hud.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_world_with_alpha() -> SimulationWorld:
	var world := SimulationWorld.new()
	var alpha := ShipPhysicsState.new()
	alpha.position = Vector3.ZERO
	alpha.defense = ShipDefenseState.new()
	alpha.subsystems = ShipSubsystems.new()
	world.add_ship("alpha", alpha)
	return world

func _test_ready_creates_a_visible_label_child() -> void:
	var hud := Hud.new()
	get_root().add_child(hud)
	hud._ready()  # not auto-flushed synchronously here -- see note below
	var label: Label = hud.get_node_or_null("HudLabel")
	_assert(label != null, "Hud._ready() should create a child Label named HudLabel")
	if label != null:
		_assert(label.visible, "the HudLabel should be visible by default (no code path hides it)")
	_assert(hud.visible, "the Hud CanvasLayer itself should be visible by default")
	hud.queue_free()

func _test_update_sets_non_empty_text_with_expected_sections() -> void:
	var world := _make_world_with_alpha()
	var hud := Hud.new()
	get_root().add_child(hud)
	hud._ready()
	hud.update(world, "alpha")
	var label: Label = hud.get_node_or_null("HudLabel")
	_assert(label != null, "sanity: HudLabel must exist before checking its text")
	if label != null:
		_assert(label.text.length() > 0, "after one update(), the HudLabel's text should be non-empty")
		_assert(label.text.find("ALPHA") != -1, "the HUD text should identify the POV ship")
		_assert(label.text.find("SUBSYSTEMS") != -1, "the HUD text should include the subsystems section")
		_assert(label.text.find("TARGET") != -1, "the HUD text should include the target section")
		_assert(label.text.find("CONTACTS") != -1, "the HUD text should include the contacts section")
		_assert(label.visible, "the HudLabel should still be visible after update()")
	hud.queue_free()

func _test_update_with_unknown_ship_id_still_shows_something() -> void:
	var world := SimulationWorld.new()
	var hud := Hud.new()
	get_root().add_child(hud)
	hud._ready()
	hud.update(world, "does_not_exist")
	var label: Label = hud.get_node_or_null("HudLabel")
	_assert(label != null and label.text.length() > 0, "an unknown ship id should still produce a non-empty diagnostic label, never a blank HUD")
	hud.queue_free()

## §56.3 item F ("first real shared UI-panel layout pass"): get_bottom_y()
## must reflect the label's REAL measured height after update(), not a
## fixed constant -- this is what lets CommandGroupPanel stack below Hud
## dynamically (see command_group_panel.gd/main.gd). A ship with a real
## ShipSubsystems + at least one contact produces a multi-line label, so
## this also incidentally guards against get_bottom_y() being hardcoded
## back to a single-line assumption.
##
## §56.3 item J: updated expected-value formula -- get_bottom_y() now
## returns the styled background panel's real bottom edge (label bottom +
## padding), not the bare label's bottom, since the background is what's
## actually visibly drawn now. See get_bottom_y()'s own doc comment.
func _test_get_bottom_y_reflects_real_label_height() -> void:
	var world := _make_world_with_alpha()
	var hud := Hud.new()
	get_root().add_child(hud)
	hud._ready()
	hud.update(world, "alpha")
	var label: Label = hud.get_node_or_null("HudLabel")
	var background: Panel = hud.get_node_or_null("HudBackground")
	_assert(label != null, "sanity: HudLabel must exist to measure its height")
	_assert(background != null, "sanity: HudBackground must exist to measure the panel's real bottom edge")
	if label != null and background != null:
		var expected: float = background.position.y + background.size.y
		_assert(is_equal_approx(hud.get_bottom_y(), expected), "get_bottom_y() should equal the background panel's real bottom edge, got %f expected %f" % [hud.get_bottom_y(), expected])
		_assert(hud.get_bottom_y() > label.position.y, "get_bottom_y() should be below the label's own top (position.y) once there is any text at all")

## §56.3 item J: the new styled background panel -- exists, is a real
## StyleBoxFlat (not the Godot default Panel theme, which would mean
## UiTheme.panel_stylebox() was never actually applied), drawn BEHIND the
## label (added earlier in child order, so it doesn't cover the text),
## and its rect fully encloses the label's real measured bounds with the
## documented padding rather than e.g. being left at its constructor
## default size (0,0) or some other stale/unrelated rect.
func _test_background_panel_is_styled_and_wraps_the_label() -> void:
	var world := _make_world_with_alpha()
	var hud := Hud.new()
	get_root().add_child(hud)
	hud._ready()
	hud.update(world, "alpha")
	var label: Label = hud.get_node_or_null("HudLabel")
	var background: Panel = hud.get_node_or_null("HudBackground")
	_assert(background != null, "Hud._ready() should create a child Panel named HudBackground")
	if background == null or label == null:
		hud.queue_free()
		return

	var label_index: int = label.get_index()
	var background_index: int = background.get_index()
	_assert(background_index < label_index, "HudBackground should be added before HudLabel in child order, so it draws behind the text, not over it")

	var stylebox: StyleBox = background.get_theme_stylebox("panel")
	_assert(stylebox is StyleBoxFlat, "HudBackground should use a real StyleBoxFlat (UiTheme.panel_stylebox()), not the engine's default flat panel theme")

	var label_size: Vector2 = label.get_minimum_size()
	_assert(background.position.x <= label.position.x and background.position.y <= label.position.y, "the background panel should start at or before the label's own top-left corner (padding), not inside it")
	var label_bottom_right: Vector2 = label.position + label_size
	var background_bottom_right: Vector2 = background.position + background.size
	_assert(background_bottom_right.x >= label_bottom_right.x and background_bottom_right.y >= label_bottom_right.y, "the background panel should fully enclose the label's real measured bounds, not clip it")
	_assert(background.position.y < label.position.y, "the background panel should extend above the label (real padding), not start exactly flush at the label's top")

	hud.queue_free()

func _init() -> void:
	_test_ready_creates_a_visible_label_child()
	_test_update_sets_non_empty_text_with_expected_sections()
	_test_update_with_unknown_ship_id_still_shows_something()
	_test_get_bottom_y_reflects_real_label_height()
	_test_background_panel_is_styled_and_wraps_the_label()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
