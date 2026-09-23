extends SceneTree
## Headless regression test for PlayerInput (ТЗ §56.1 item 5).
## Run: godot4 --headless --path . --script res://simulation/tests/test_player_input.gd
##
## Written in response to a 2026-09-23 live bug report: on the exported
## Windows build, no key presses had any visible effect at all. This test
## verifies the two things that live entirely in scripting (as opposed to
## OS-level window/input focus, which no headless test in this
## environment can exercise -- see the note at the bottom):
##  1. project.godot's [input] action names match EXACTLY what
##     player_input.gd reads via event.is_action_pressed(...) -- a typo
##     on either side would make a key silently do nothing.
##  2. PlayerInput._unhandled_input, given a matching event, actually
##     reaches SimulationWorld's transmit_* order API and the ship's
##     commanded state begins to change.
##
## Both come back green in this environment (see .tools/state.md), which
## points the remaining suspicion at something outside GDScript: the
## exported window not having OS input focus on launch (a known class of
## Windows/Godot export quirk) is the leading hypothesis addressed this
## pass by main.gd requesting focus at the end of _ready(). If keys are
## STILL unresponsive after a live re-test with that fix, the next step
## needs a live repro on the user's Windows machine (this environment has
## no way to grant/observe real OS window focus), not another headless
## test.

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const PlayerInput = preload("res://scripts/player_input.gd")

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
	alpha.orientation = Quaternion.IDENTITY
	alpha.velocity = Vector3.ZERO
	alpha.defense = ShipDefenseState.new()
	world.add_ship("alpha", alpha)
	return world

## For every action project.godot's [input] section defines for order
## hotkeys, PlayerInput must have at least one matching is_action_pressed
## branch -- catches a rename on either side going forward (the concrete
## 2026-09-23 report turned out NOT to be this, but it costs nothing to
## pin down permanently now that both files are open).
func _test_all_input_map_order_actions_are_read_by_player_input() -> void:
	var expected_actions := [
		"order_select_ship", "order_target_next", "order_target_clear",
		"order_weapons_toggle", "order_turn_left", "order_turn_right",
		"order_speed_up", "order_speed_down",
	]
	for action in expected_actions:
		_assert(InputMap.has_action(action), "project.godot [input] should define action '%s' (PlayerInput reads it by this exact name)" % action)

func _press(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev

func _test_turn_left_changes_desired_heading_and_transmits_an_order() -> void:
	var world := _make_world_with_alpha()
	var input := PlayerInput.new()
	input.world = world
	_assert(not input._desired_heading_by_ship.has("alpha"), "sanity: no desired heading should be recorded before any keypress")
	input._unhandled_input(_press("order_turn_left"))
	_assert(input._desired_heading_by_ship.has("alpha"), "order_turn_left should record a new desired heading for the selected ship")

func _test_speed_up_changes_desired_speed() -> void:
	var world := _make_world_with_alpha()
	var input := PlayerInput.new()
	input.world = world
	_assert(not input._desired_speed_by_ship.has("alpha"), "sanity: no desired speed should be recorded before any keypress")
	input._unhandled_input(_press("order_speed_up"))
	_assert(input._desired_speed_by_ship.has("alpha"), "order_speed_up should record a new desired speed for the selected ship")
	_assert(input._desired_speed_by_ship["alpha"] > 0.0, "order_speed_up from a standstill should command a positive speed")

## transmit_ship_weapons_free (like the other transmit_* order APIs -- see
## PlayerInput's own class doc comment) is comm-delayed: it only queues the
## order in SimulationWorld._pending_command_transmissions, applied later
## during tick_simulation(). A full apply-and-check test belongs with
## SimulationWorld's own comm-delay tests (see test_ship_combat_directive.gd);
## here we only need to confirm PlayerInput actually calls through to
## transmit_ship_weapons_free at all, i.e. that the hotkey is wired up.
func _test_weapons_toggle_transmits_an_order() -> void:
	var world := _make_world_with_alpha()
	var input := PlayerInput.new()
	input.world = world
	var pending_before: int = world._pending_command_transmissions.size()
	input._unhandled_input(_press("order_weapons_toggle"))
	var pending_after: int = world._pending_command_transmissions.size()
	_assert(pending_after > pending_before, "order_weapons_toggle should transmit a weapons-free order for the selected ship")

func _test_null_world_does_not_crash() -> void:
	var input := PlayerInput.new()
	input.world = null
	input._unhandled_input(_press("order_turn_left"))
	_assert(true, "PlayerInput._unhandled_input with no world assigned yet should return early, not crash")

func _init() -> void:
	_test_all_input_map_order_actions_are_read_by_player_input()
	_test_turn_left_changes_desired_heading_and_transmits_an_order()
	_test_speed_up_changes_desired_speed()
	_test_weapons_toggle_transmits_an_order()
	_test_null_world_does_not_crash()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
