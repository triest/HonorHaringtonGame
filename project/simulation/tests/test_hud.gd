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

func _init() -> void:
	_test_ready_creates_a_visible_label_child()
	_test_update_sets_non_empty_text_with_expected_sections()
	_test_update_with_unknown_ship_id_still_shows_something()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
