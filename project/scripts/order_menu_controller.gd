extends Node
## OrderMenuController
##
## ТЗ §56.3 item D ("Contextual order menu after selecting own +
## designating enemy") / §1.10.7. Pure INTERACTION + ORDER-ROUTING logic,
## same division of labor as MoveOrderController (item C): TacticalPlot
## (scripts/tactical_plot.gd) turns a plain LMB click that hit a contact
## into a call to `try_open(contact_id, screen_pos)`; this class decides
## whether that click actually opens the menu (see try_open's own doc),
## builds the (filtered) order list, and -- once the player picks one --
## constructs and issues the real order via ShipCombatDirective/
## FormationOrder/IndividualOrder (§1.10.7's own explicit text: "Не
## создавать отдельную UI-only модель приказов").
##
## DELIBERATELY HOLDS NO REFERENCE TO THE MENU'S UI CONTROL -- same §42
## "pure readout" convention as every other controller/view pair in this
## codebase (MoveOrderController never references TacticalPlot;
## CommandGroupController never references CommandGroupPanel): this
## class only exposes plain state (`is_open`/`menu_screen_pos`/
## `menu_entries` below) that OrderMenu (scripts/order_menu.gd) reads
## once per tick via `sync()`, called from main.gd._on_tick exactly like
## Hud.update()/TacticalPlot.update(). This keeps this whole class
## headless-testable with zero Viewport/Control dependency (see
## simulation/tests/test_order_menu_controller.gd), and keeps the same
## clean separation the rest of §56.3 already established.
##
## INTERACTION CHOSEN (ASSUMPTION -- §1.10.7's own text only says the
## menu appears "after selecting own ship/group and designating an enemy
## object with the mouse", without pinning down the exact gesture; logged
## in ASSUMPTIONS.md "§56.3 item D" the same way items A/B/C each logged
## their own interaction-model interpretation): a PLAIN (no Ctrl/Shift)
## LMB click on a hostile ship contact, made while the CURRENT selection
## already contains at least one ship this player may command. This
## reuses the exact same click TacticalPlot's own hit-testing already
## produces (TacticalPlotSelection.hit_test) rather than inventing a
## second hit-testing path, and requires no new modifier key. If
## `try_open` returns false (target not a commandable-against hostile
## ship, or nothing eligible in the current selection), TacticalPlot
## falls back to its own pre-existing plain-click behavior
## (select_only([hit_id])) -- this class is purely additive, it never
## overrides normal selection when there is nothing to command.
##
## DESIGNATION is a single `SelectionState.designated_target_id` (see
## that class's own doc comment for why this is not a second multi-
## select), set the moment the menu opens and cleared the moment it
## closes (by a chosen action OR by an outside-click dismiss) -- it is
## the "target half" of the current order-menu interaction only, not a
## persistent "manual target" concept (that already exists separately as
## ShipCombatDirective.manual_target_ship_id, set by ATTACK/FOCUS FIRE
## below, not by designation itself).
class_name OrderMenuController

var world: SimulationWorld
var selection: SelectionState

## Same restriction/reasoning as MoveOrderController.player_team: only
## ships on THIS team may ever be given an order through this menu, and
## only ships on a DIFFERENT non-empty team may ever be designated as
## the target -- set once by main.gd from world.teams.get(HUD_POV_SHIP_ID),
## same convention as every other §56.3 controller.
var player_team: String = ""

## §1.10.7 "APPROACH" is reused AS-IS from §56.3 item C's move-order
## machinery (see execute()'s APPROACH branch) -- an "approach the
## designated enemy" order is mechanically identical to a move order
## aimed at that enemy's current position, and `selection` here is the
## SAME shared SelectionState MoveOrderController itself reads, so no
## order-construction logic is duplicated for this entry.
var move_order_controller: MoveOrderController

## ASSUMPTION, same status as MoveOrderController.DEFAULT_MOVE_SPEED_MPS
## -- no canon figure for a "withdraw" transit speed, chosen purely so a
## withdraw order produces a visible transit within this demo's short
## observation window.
const WITHDRAWAL_SPEED_MPS: float = 2000.0

## Read once per tick by OrderMenu.sync() -- see class doc comment.
var is_open: bool = false
var menu_screen_pos: Vector2 = Vector2.ZERO
var menu_entries: Array = []  # Array[{"label": String, "kind": String}]

var _pending_target_id: String = ""
var _pending_eligible_ids: Array = []

## See class doc comment for the exact trigger condition. Returns true
## (and opens the menu) only if `contact_id` is a real hostile ship (per
## `player_team`, excluding missiles/neutrals/friendlies/own ships) AND
## the current selection contains at least one ship on `player_team`.
## Leaves `selection`/menu state completely untouched and returns false
## for every other case, so the caller can safely fall back to ordinary
## selection behavior.
func try_open(contact_id: String, screen_pos: Vector2) -> bool:
	if world == null or selection == null:
		return false
	if not _is_hostile_ship(contact_id):
		return false

	var eligible: Array = _eligible_ship_ids()
	if eligible.is_empty():
		return false

	_pending_target_id = contact_id
	_pending_eligible_ids = eligible
	selection.designate_target(contact_id)

	menu_screen_pos = screen_pos
	menu_entries = _build_entries(eligible)
	is_open = true
	return true

## Called by OrderMenu when the player clicks one of the offered rows.
## `kind` is one of the "kind" strings _build_entries put in that row's
## entry dictionary.
func execute(kind: String) -> void:
	if world != null and _pending_target_id != "":
		match kind:
			"ATTACK", "FOCUS_FIRE":
				# ТЗ §1.10.7: both route through the exact same
				# ShipCombatDirective primitives (manual target + weapons
				# free) -- see ASSUMPTIONS.md "§56.3 item D" for why
				# ATTACK and FOCUS FIRE are honestly identical given
				# today's primitives (there is no separate fire-
				# allocation/coordination mechanic yet to make "focus
				# fire" meaningfully different from "attack" for a
				# multi-ship selection).
				for ship_id in _pending_eligible_ids:
					world.transmit_ship_target(ship_id, _pending_target_id)
					world.transmit_ship_weapons_free(ship_id, true)
			"HOLD_FIRE":
				for ship_id in _pending_eligible_ids:
					world.transmit_ship_weapons_free(ship_id, false)
			"WEAPONS_FREE":
				for ship_id in _pending_eligible_ids:
					world.transmit_ship_weapons_free(ship_id, true)
			"APPROACH":
				_execute_approach()
			"WITHDRAW":
				_execute_withdraw()
			"MAINTAIN_FORMATION":
				_execute_maintain_formation()
	_close()

## Called by OrderMenu when the player clicks outside the menu (dismiss
## with no action chosen). Clears the designation but issues no order.
func dismiss() -> void:
	_close()

func _close() -> void:
	is_open = false
	menu_entries = []
	_pending_target_id = ""
	_pending_eligible_ids = []
	if selection != null:
		selection.clear_designated_target()

func _is_hostile_ship(contact_id: String) -> bool:
	if not world.ships.has(contact_id):
		return false  # excludes missile contacts (world.missiles) and unknown ids
	var team: String = String(world.teams.get(contact_id, ""))
	return team != "" and team != player_team

## Same eligibility rule as MoveOrderController._eligible_ship_ids (real
## ships, on `player_team` specifically) -- duplicated rather than
## shared, matching this codebase's own stated convention for small,
## order-routing eligibility helpers (see individual_order.gd's class
## doc on why FormationOrder/IndividualOrder's own kinematic blocks are
## duplicated rather than factored into a shared base).
func _eligible_ship_ids() -> Array:
	var result: Array = []
	for id in selection.selected_ids:
		if not world.ships.has(id):
			continue
		if String(world.teams.get(id, "")) != player_team:
			continue
		result.append(id)
	return result

## "" if `ship_id` is not currently part of any registered formation
## (guide or member), else that formation's id -- duplicated from
## MoveOrderController's identical helper, see that class's own doc
## comment for why this is checked live against `world.formations`
## every call rather than cached.
func _formation_id_for_ship(ship_id: String) -> String:
	for formation_id in world.formations.keys():
		var formation: FormationState = world.formations[formation_id]
		if formation.guide_ship_id == ship_id or formation.member_offsets.has(ship_id):
			return formation_id
	return ""

func _any_in_formation(eligible: Array) -> bool:
	for ship_id in eligible:
		if _formation_id_for_ship(ship_id) != "":
			return true
	return false

## ТЗ §1.10.7's minimal order set, filtered per this class's own doc
## comment: ATTACK/FOCUS FIRE/HOLD FIRE/WEAPONS FREE/APPROACH/WITHDRAW
## are always offered once the menu is eligible to open at all (all six
## map cleanly onto ShipCombatDirective/FormationOrder/IndividualOrder
## primitives regardless of whether the selection is a lone ship or a
## group). MAINTAIN FORMATION is offered only when at least one eligible
## ship is actually part of a formation -- offering it for a lone ship
## would be a dead button (nothing to "maintain"). DEFEND/COVER/FOLLOW/
## INTERCEPT are NOT offered at all this pass -- an honest gap, not an
## oversight: none of them map onto any existing primitive (there is no
## "follow/escort another ship" concept anywhere in simulation/*.gd,
## confirmed by grep before writing this class -- see ASSUMPTIONS.md
## "§56.3 item D"). Per item D's own checklist text ("a UI/routing item,
## not a request for new combat mechanics"), a dead menu entry that does
## nothing would be worse than honestly omitting it until a future pass
## adds the underlying mechanic.
func _build_entries(eligible: Array) -> Array:
	var entries: Array = [
		{"label": "ATTACK", "kind": "ATTACK"},
		{"label": "FOCUS FIRE", "kind": "FOCUS_FIRE"},
		{"label": "HOLD FIRE", "kind": "HOLD_FIRE"},
		{"label": "WEAPONS FREE", "kind": "WEAPONS_FREE"},
		{"label": "APPROACH", "kind": "APPROACH"},
		{"label": "WITHDRAW", "kind": "WITHDRAW"},
	]
	if _any_in_formation(eligible):
		entries.append({"label": "MAINTAIN FORMATION", "kind": "MAINTAIN_FORMATION"})
	return entries

## §1.10.7 APPROACH: identical in effect to §56.3 item C's RMB move
## order aimed at the designated target's CURRENT position -- reuses
## `move_order_controller.issue_move_order` as-is (it reads the same
## shared `selection`, which was never replaced/cleared by this
## interaction, see class doc). No separate approach-tracking/order-
## construction code is written here.
func _execute_approach() -> void:
	if move_order_controller == null:
		return
	var target_ship: ShipPhysicsState = world.ships.get(_pending_target_id)
	if target_ship == null:
		return
	move_order_controller.issue_move_order(target_ship.position)

## §1.10.7 WITHDRAW: turn away from the designated target's CURRENT
## position, then accelerate to WITHDRAWAL_SPEED_MPS along that heading
## -- FormationOrder.withdraw_orders/IndividualOrder.withdraw_orders
## (already-existing composites, see those classes' own doc comments)
## reused as-is, per-eligible-ship (formations deduplicated by guide,
## same routing shape as MoveOrderController.issue_move_order).
##
## Issued via the QUEUED, NOT comm-delayed, `issue_formation_orders`/
## `issue_individual_orders` -- ASSUMPTION/deliberate choice, see
## ASSUMPTIONS.md "§56.3 item D": withdraw_orders() returns a two-order
## sequence (turn, THEN accelerate) that must be queued together. The
## public comm-delayed API only exposes a single-order "now" variant
## (`transmit_individual_order_now`/no formation equivalent for a list),
## and calling that twice in a row for a composite would let the SECOND
## call's "_now" interrupt-and-execute-immediately semantics cancel the
## first order before it ever took effect -- the exact same class of
## trap MoveOrderController's own doc comment already documents (there,
## for a single-order case; here, for why a composite can't safely go
## through the "_now" family at all). Skipping the comms-delay wrapper
## for this one order is an honest, logged simplification, not a claim
## that WITHDRAW is somehow exempt from §25 comms realism.
func _execute_withdraw() -> void:
	var target_ship: ShipPhysicsState = world.ships.get(_pending_target_id)
	if target_ship == null:
		return

	var handled_formations: Dictionary = {}
	for ship_id in _pending_eligible_ids:
		var formation_id: String = _formation_id_for_ship(ship_id)
		if formation_id != "":
			if handled_formations.has(formation_id):
				continue
			handled_formations[formation_id] = true
			var formation: FormationState = world.get_formation(formation_id)
			if formation == null or formation.guide_ship_id == "":
				continue
			var guide: ShipPhysicsState = world.ships.get(formation.guide_ship_id)
			if guide == null:
				continue
			var away: Vector3 = guide.position - target_ship.position
			if away.length_squared() < 0.0001:
				continue
			world.issue_formation_orders(formation_id, FormationOrder.withdraw_orders(guide, away, WITHDRAWAL_SPEED_MPS))
		else:
			var ship: ShipPhysicsState = world.ships.get(ship_id)
			if ship == null:
				continue
			var away2: Vector3 = ship.position - target_ship.position
			if away2.length_squared() < 0.0001:
				continue
			world.issue_individual_orders(ship_id, IndividualOrder.withdraw_orders(ship, away2, WITHDRAWAL_SPEED_MPS))

## §1.10.7 MAINTAIN FORMATION: FormationOrder.hold_formation() issued
## immediately (world.issue_formation_order_now, same "_now" semantics
## as MoveOrderController's own formation routing -- this is a single-
## order posture change, not a composite, so the WITHDRAW trap above
## does not apply here) at every formation among the eligible ships
## (deduplicated). Lone ships not in any formation are silently skipped
## -- there is nothing to "maintain" for them, and this entry is only
## ever offered (see _build_entries) when at least one eligible ship IS
## in a formation.
func _execute_maintain_formation() -> void:
	var handled: Dictionary = {}
	for ship_id in _pending_eligible_ids:
		var formation_id: String = _formation_id_for_ship(ship_id)
		if formation_id == "" or handled.has(formation_id):
			continue
		handled[formation_id] = true
		world.issue_formation_order_now(formation_id, FormationOrder.hold_formation())
