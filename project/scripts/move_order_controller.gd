extends Node
## MoveOrderController
##
## ТЗ §56.3 item C ("RMB по точке пространства -> приказ движения") /
## §1.10.6. Pure INPUT-TO-ORDER translator, same convention as
## PlayerInput/CommandGroupController: TacticalPlot (this dir) turns a
## right-mouse-button click on the plot into a world-space point (via
## TacticalPlotProjector.unproject -- the plot's own screen<->world
## math, not re-derived here) and calls `issue_move_order(point)` on
## this class. This class owns ONLY the routing decision (individual vs.
## formation) and the order construction -- it invents no new order
## kind/class of its own (§1.10.5: "must reuse the existing
## CommandEchelon, FormationState and IndividualOrder architecture, not
## a separate parallel system").
##
## ELIGIBILITY (ASSUMPTION, same status/reasoning as CommandGroupController's
## own eligibility filter -- see ASSUMPTIONS.md "§56.3 item C"): only ids
## in the current selection that are (a) real ships (world.ships.has(id))
## and (b) on `player_team` -- NOT merely "the same team as each other"
## like CommandGroupController (a group-NAMING action is harmless if
## mis-scoped to the wrong team; a MOVE order is not: it must never be
## possible to right-click and fly an enemy AI ship around). A selection
## containing zero eligible ids is a no-op.
##
## ROUTING (per state.md's item C plan / §1.10.5): for each eligible ship
## that is a formation member (guide OR ordinary member, checked live
## against `world.formations` every call -- never cached, so this stays
## correct across group creation/leader transfer/disbanding), the order
## is issued ONCE at that formation (world.issue_formation_order_now,
## see `_issue_formation_move`'s own doc for why the FORMATION-level
## immediate API is used rather than routing through the owning
## CommandEchelon -- ASSUMPTIONS.md "§56.3 item C"), deduplicated so
## selecting two members of the same formation together still issues
## exactly one order. A ship with no formation at all uses the plain
## IndividualOrder path via world.transmit_individual_order_now (the
## SAME comm-delayed family PlayerInput's own hotkeys already use for
## player-issued orders -- §25/§31 realism, not an unexplained instant-
## effect special case for mouse input specifically).
class_name MoveOrderController

var world: SimulationWorld
var selection: SelectionState

## Restricts eligibility to this team only (see class doc) -- set once by
## main.gd to whatever team the player's own ship is on, same convention
## as TacticalPlot/Hud being handed HUD_POV_SHIP_ID rather than
## discovering "which ship is the player's" some other way.
var player_team: String = ""

## Cruise speed used when an eligible ship/formation-guide is presently
## at (near) zero speed -- ASSUMPTION, no canon figure, same status as
## PlayerInput.SPEED_STEP_MPS/CommandGroupController's own documented
## interpretation constants: picked purely so a move order to a
## stationary ship visibly produces a transit within this demo's short
## observation window. A ship/guide already moving faster than
## `MIN_MOVE_SPEED_MPS` keeps its CURRENT speed and is simply redirected
## toward the target point -- "move order" retargets the destination, it
## does not force a specific transit speed on an already-underway ship.
const DEFAULT_MOVE_SPEED_MPS: float = 2000.0
const MIN_MOVE_SPEED_MPS: float = 200.0

## ТЗ §1.10.6 visualization ("course line, arrow, endpoint, predicted
## vector"): the plot's own _draw() reads this to know what to draw and
## where -- UI-side bookkeeping only (§1.10.6's own text allows
## "ASSUMPTION calls on exact visual style"), NOT a re-derivation of
## simulation truth. Keyed by "anchor id" (the lone ship's id, or the
## formation's GUIDE ship's id for a grouped order -- members keep
## following the guide exactly as before, so the guide's course is the
## only line worth drawing for the whole group, see formation_order.gd's
## own class doc on this) -> {"target_point": Vector3}. Entries are
## pruned once the anchor arrives (or the anchor ship no longer exists)
## by `prune_completed()`, called once per tick from main.gd._on_tick --
## same per-tick-readout convention as Hud/WeaponFx/TacticalPlot.
var active_move_orders: Dictionary = {}

const ARRIVAL_TOLERANCE_M: float = 300.0

## Returns the list of anchor ids an order was actually issued for (empty
## if the selection had nothing eligible) -- callers don't have to care,
## but headless tests find this more convenient than inspecting
## `active_move_orders` directly.
func issue_move_order(target_point_world: Vector3) -> Array:
	if world == null or selection == null:
		return []

	var eligible: Array = _eligible_ship_ids()
	if eligible.is_empty():
		return []

	var handled_formations: Dictionary = {}  # formation_id -> true, dedupe multi-member selections
	var anchors: Array = []
	for ship_id in eligible:
		var formation_id: String = _formation_id_for_ship(ship_id)
		if formation_id != "":
			if handled_formations.has(formation_id):
				continue
			handled_formations[formation_id] = true
			var anchor_id: String = _issue_formation_move(formation_id, target_point_world)
			if anchor_id != "":
				anchors.append(anchor_id)
		else:
			_issue_individual_move(ship_id, target_point_world)
			anchors.append(ship_id)

	return anchors

## ТЗ §56.3 item C, real ships on `player_team` only -- see class doc.
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
## (guide or member), else that formation's id. Checked live against
## `world.formations` every call -- see class doc.
func _formation_id_for_ship(ship_id: String) -> String:
	for formation_id in world.formations.keys():
		var formation: FormationState = world.formations[formation_id]
		if formation.guide_ship_id == ship_id or formation.member_offsets.has(ship_id):
			return formation_id
	return ""

## Formation-level order: FormationOrder.APPROACH already does exactly
## what §1.10.6 asks for a formation guide (continuously re-aims at a
## fixed point, completes on arrival, real acceleration/inertia -- see
## formation_order.gd's own class doc) -- reused as-is, nothing new
## invented here.
##
## Issued via `world.issue_formation_order_now`, NOT
## `world.issue_echelon_order` -- ASSUMPTION/discovery this pass (see
## ASSUMPTIONS.md "§56.3 item C"): issue_echelon_order only QUEUES
## (`FormationState.issue_order`, not `issue_order_now`), so a fresh move
## order issued while the formation is already mid-order would sit
## BEHIND the old one instead of replacing it, unlike every other order
## path here (transmit_individual_order_now, and this same
## issue_formation_order_now) -- a move order is a fresh, immediate
## intention, exactly like PlayerInput's own hotkeys, not something that
## should ever visibly wait in a queue. There is no
## `issue_echelon_order_now` yet to give the same immediate semantics at
## the echelon level; since `selection` here only ever resolves to a
## SPECIFIC formation_id (never a whole echelon subtree -- there is no
## "select an echelon" UI concept yet), addressing the formation directly
## loses nothing today. Revisit if/when an echelon-level selection
## concept is added (would need a small additive
## issue_echelon_order_now, mirroring this one).
##
## Returns the guide's ship id (the visualization anchor) on success, ""
## if the formation has no guide/is otherwise unusable.
func _issue_formation_move(formation_id: String, target_point_world: Vector3) -> String:
	var formation: FormationState = world.get_formation(formation_id)
	if formation == null or formation.guide_ship_id == "":
		return ""
	var guide: ShipPhysicsState = world.ships.get(formation.guide_ship_id)
	if guide == null:
		return ""

	var speed_mps: float = guide.velocity.length()
	if speed_mps < MIN_MOVE_SPEED_MPS:
		speed_mps = DEFAULT_MOVE_SPEED_MPS
	var order: FormationOrder = FormationOrder.approach(target_point_world, speed_mps)
	world.issue_formation_order_now(formation_id, order)

	active_move_orders[formation.guide_ship_id] = {"target_point": target_point_world}
	return formation.guide_ship_id

## Lone-ship order: which IndividualOrder kind to issue depends on
## whether the ship is already underway (ASSUMPTION/discovery this pass,
## see ASSUMPTIONS.md "§56.3 item C" -- this is NOT an arbitrary style
## choice, it avoids a real completion-check trap):
##
## * Already moving faster than MIN_MOVE_SPEED_MPS: IndividualOrder.
##   change_course(ship, heading) -- holds the ship's CURRENT speed and
##   only retargets its heading. change_course's is_complete() checks the
##   ANGLE between current and target velocity, so it correctly keeps
##   applying turn thrust every tick until the new heading is actually
##   reached.
## * At/near zero speed: IndividualOrder.change_speed(ship,
##   DEFAULT_MOVE_SPEED_MPS, heading) -- ramps up to cruise speed along
##   the given heading.
##
## The tempting "just always use ONE change_speed(ship, current_or_
## default_speed, heading) order" (avoiding two static constructors) is a
## trap for the "already moving" case: change_speed's own is_complete()
## checks ONLY the target/current velocity MAGNITUDE, ignoring heading
## entirely -- if the new target speed equals the ship's current speed
## (exactly the "keep current speed, just redirect" case), is_complete()
## reads true on the very FIRST tick evaluation, BEFORE any turning
## thrust is ever applied (see SimulationWorld._resolve_individual_orders:
## the completion check runs before the thrust-application branch and
## zeroes thrust on completion) -- the ship would silently never turn at
## all. change_course's heading-based completion check has no such trap.
## Found by this pass's own headless test
## (test_move_order_controller.gd's already-fast-ship case) failing
## against the naive single-order version -- kept here as an explicit
## comment, not just a fixed test, so nobody "simplifies" this back.
func _issue_individual_move(ship_id: String, target_point_world: Vector3) -> void:
	var ship: ShipPhysicsState = world.ships.get(ship_id)
	if ship == null:
		return
	var to_target: Vector3 = target_point_world - ship.position
	if to_target.length_squared() < 0.0001:
		return  # clicked (almost) exactly on the ship itself -- nothing to order
	var heading: Vector3 = to_target.normalized()

	var order: IndividualOrder
	if ship.velocity.length() < MIN_MOVE_SPEED_MPS:
		order = IndividualOrder.change_speed(ship, DEFAULT_MOVE_SPEED_MPS, heading)
	else:
		order = IndividualOrder.change_course(ship, heading)

	world.transmit_individual_order_now(ship_id, order)
	active_move_orders[ship_id] = {"target_point": target_point_world}

## Drops any active-move-order visual whose anchor ship no longer exists,
## or has arrived within `ARRIVAL_TOLERANCE_M` of its target point. Pure
## UI-side bookkeeping (see `active_move_orders` doc) -- does not touch
## any actual order/simulation state, exactly like TacticalPlot's own
## per-tick update() never mutates `world`. Called once per tick from
## main.gd._on_tick.
func prune_completed() -> void:
	if active_move_orders.is_empty():
		return
	var still_active: Dictionary = {}
	for anchor_id in active_move_orders.keys():
		var ship: ShipPhysicsState = world.ships.get(anchor_id)
		if ship == null:
			continue
		var target_point: Vector3 = active_move_orders[anchor_id]["target_point"]
		if ship.position.distance_to(target_point) <= ARRIVAL_TOLERANCE_M:
			continue
		still_active[anchor_id] = active_move_orders[anchor_id]
	active_move_orders = still_active
