extends Node
## PlayerInput
##
## ТЗ §56.1 item 5 ("Order input wiring"): "Minimal player input wired
## DIRECTLY to the already-implemented backend order APIs (FormationOrder,
## IndividualOrder, ShipCombatDirective) -- a handful of buttons/hotkeys
## (select ship, set course/speed, designate target, weapons free/hold),
## not a polished command UI and not the general Scenario/editor system."
##
## This is a pure INPUT-TO-ORDER translator: it reads discrete Input Map
## actions (project.godot [input], added this pass) and calls straight
## into SimulationWorld's existing order-issuing API -- it invents no new
## order semantics of its own, exactly like WeaponFx/Hud invent no new
## simulation state (§42). Specifically uses the `transmit_*` family
## (transmit_individual_order_now / transmit_ship_target /
## transmit_clear_ship_target / transmit_ship_weapons_free), not the
## instant `issue_*`/`set_*` ones -- per simulation_world.gd's own doc
## comment on that family: "Use these to represent a commander issuing an
## order through the normal chain of command", which is exactly what a
## human player pressing a key represents. This also means player orders
## honestly incur the same §25/§31 communications-delay-based-on-
## COMMUNICATIONS-subsystem-condition modeling as any other commander
## order -- not an unexplained instant-effect special case for the
## player.
##
## WHICH SHIP THE PLAYER CONTROLS (decided this pass, see state.md/
## CHANGELOG.md): "alpha" -- the same ship Hud (scripts/hud.gd, item 4)
## already shows. There is exactly one entry in `_controllable_ship_ids`
## right now, so `order_select_ship` (TAB) is wired but currently a
## visible no-op (cycling a 1-element list always lands back on itself) --
## kept because the checklist item explicitly lists "select ship" as one
## of the hotkeys to wire, and this is the honest, minimal way to have it
## present without inventing a second player-controlled ship or a
## side-selection mechanic that doesn't exist yet. Extending this to a
## real multi-ship roster later is just adding entries to
## `_controllable_ship_ids`, nothing else changes.
##
## Course/speed hotkeys track a per-ship DESIRED heading/speed locally
## (`_desired_heading_by_ship` / `_desired_speed_by_ship`), incrementing
## from the last value THIS SCRIPT COMMANDED rather than re-reading the
## ship's current actual velocity every keypress -- an order just
## transmitted has not taken effect yet (comm delay, then the ship still
## has to accelerate/turn to match), so re-reading live velocity on a
## rapid second keypress would make the turn/speed step size inconsistent
## depending on how much the previous order has already been achieved.
## Falls back to the ship's actual current velocity/orientation only the
## FIRST time a given ship receives a course/speed hotkey this session.
class_name PlayerInput

var world: SimulationWorld

## Ships the player may select and command. Exactly one entry for this
## slice -- see class doc comment above.
var _controllable_ship_ids: Array = ["alpha"]
var selected_ship_id: String = "alpha"

var _desired_heading_by_ship: Dictionary = {}  # ship_id -> Vector3 (unit, world-space)
var _desired_speed_by_ship: Dictionary = {}    # ship_id -> float (m/s)

## §29/§30-style game-feel constants (ASSUMPTION, not canon -- same status
## as FormationOrder/IndividualOrder's own tolerance constants): how much
## one keypress changes heading/speed. Chosen so a few presses produce a
## visible course change within this demo's short observation window, not
## tuned against any source.
const TURN_STEP_RAD: float = 0.2618  # 15 degrees
const SPEED_STEP_MPS: float = 200.0

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return

	if event.is_action_pressed("order_select_ship"):
		_select_next_ship()
	elif event.is_action_pressed("order_target_next"):
		_select_next_target()
	elif event.is_action_pressed("order_target_clear"):
		world.transmit_clear_ship_target(selected_ship_id)
	elif event.is_action_pressed("order_weapons_toggle"):
		_toggle_weapons_free()
	elif event.is_action_pressed("order_turn_left"):
		_turn(1.0)
	elif event.is_action_pressed("order_turn_right"):
		_turn(-1.0)
	elif event.is_action_pressed("order_speed_up"):
		_change_speed(SPEED_STEP_MPS)
	elif event.is_action_pressed("order_speed_down"):
		_change_speed(-SPEED_STEP_MPS)

## §30 "select ship" -- cycles through `_controllable_ship_ids`. See
## class doc comment: currently a no-op with only one controllable ship,
## wired for when that list grows.
func _select_next_ship() -> void:
	if _controllable_ship_ids.is_empty():
		return
	var idx: int = _controllable_ship_ids.find(selected_ship_id)
	idx = (idx + 1) % _controllable_ship_ids.size()
	selected_ship_id = _controllable_ship_ids[idx]

func _current_ship() -> ShipPhysicsState:
	return world.ships.get(selected_ship_id)

## Returns the heading this script should turn/accelerate FROM: the last
## value this script itself commanded for this ship, or (first use) the
## ship's actual current velocity direction, or (stationary) its nose
## orientation. See class doc comment for why this is not just always
## "read current velocity".
func _base_heading(ship: ShipPhysicsState) -> Vector3:
	if _desired_heading_by_ship.has(selected_ship_id):
		return _desired_heading_by_ship[selected_ship_id]
	if ship.velocity.length_squared() > 0.0001:
		return ship.velocity.normalized()
	return ship.orientation * Vector3.FORWARD

func _base_speed(ship: ShipPhysicsState) -> float:
	if _desired_speed_by_ship.has(selected_ship_id):
		return _desired_speed_by_ship[selected_ship_id]
	return ship.velocity.length()

## §30 "course": rotate the selected ship's desired heading by
## +/-TURN_STEP_RAD around world Y (yaw only -- this demo's ships
## maneuver in a single plane; a full 3D heading picker is out of scope
## for this minimal hotkey slice) and transmit it as an IndividualOrder.
func _turn(sign: float) -> void:
	var ship: ShipPhysicsState = _current_ship()
	if ship == null:
		return
	var heading: Vector3 = _base_heading(ship).rotated(Vector3.UP, TURN_STEP_RAD * sign)
	_desired_heading_by_ship[selected_ship_id] = heading
	world.transmit_individual_order_now(selected_ship_id, IndividualOrder.change_course(ship, heading))

## §30 "speed"/"acceleration"/"deceleration": adjust the selected ship's
## desired speed by +/-SPEED_STEP_MPS (floored at 0 -- no reverse thrust
## modeled anywhere in this codebase) along its current desired heading,
## and transmit it. Passes `heading` explicitly to change_speed (rather
## than leaving it to default off the ship's live velocity direction) for
## the same reason `_base_heading` above does not just read live
## velocity: a heading order transmitted moments ago may not have taken
## effect yet.
func _change_speed(delta_mps: float) -> void:
	var ship: ShipPhysicsState = _current_ship()
	if ship == null:
		return
	var heading: Vector3 = _base_heading(ship)
	var speed: float = maxf(0.0, _base_speed(ship) + delta_mps)
	_desired_speed_by_ship[selected_ship_id] = speed
	world.transmit_individual_order_now(selected_ship_id, IndividualOrder.change_speed(ship, speed, heading))

## §30 "target"/"target priority": cycle the selected ship's manual
## weapon-target designation through its own LIVE sensor contact list
## (`world.sensor_contacts[selected_ship_id]`) -- reads the same contact
## dictionary Hud already displays, so whatever the player can see on the
## HUD's CONTACTS list is exactly what this can designate; nothing here
## invents a separate "known contacts" list. Sorted for a deterministic
## cycle order (Dictionary key order is insertion order, not stable
## across runs). A no-op if there are currently no contacts.
func _select_next_target() -> void:
	var contacts: Dictionary = world.sensor_contacts.get(selected_ship_id, {})
	if contacts.is_empty():
		return
	var contact_ids: Array = contacts.keys()
	contact_ids.sort()

	var directive: ShipCombatDirective = world.ship_combat_directives.get(selected_ship_id)
	var current_target: String = directive.manual_target_ship_id if directive != null else ""
	var idx: int = contact_ids.find(current_target)
	idx = (idx + 1) % contact_ids.size()
	world.transmit_ship_target(selected_ship_id, contact_ids[idx])

## §30 "weapon mode": toggle weapons free/hold for the selected ship.
## Reads the CURRENT directive state (defaulting to the same
## weapons_free=true default ShipCombatDirective itself uses) so this is
## a true toggle, not an assumption about which state the ship is in.
func _toggle_weapons_free() -> void:
	var directive: ShipCombatDirective = world.ship_combat_directives.get(selected_ship_id)
	var currently_free: bool = directive.weapons_free if directive != null else true
	world.transmit_ship_weapons_free(selected_ship_id, not currently_free)
