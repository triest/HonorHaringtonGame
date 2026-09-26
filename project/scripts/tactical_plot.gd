extends Control
## TacticalPlot
##
## ТЗ §56.2 items A/B ("Tactical plot / contacts display, including
## missiles"): a top-down, God's-eye 2D tactical display -- the user's
## explicit replacement for judging the battle by eye through a close
## 3D camera (see AGENTS.md §56.2, user decision 2026-09-23: "every UI
## decision in this section should be checked against [tactical
## strategy], not against space-combat-game conventions in general").
##
## Pure rendering readout of already-resolved SimulationWorld state
## (§42, same convention as Hud/WeaponFx): this class invents no
## detection/targeting/combat logic of its own. TacticalPlotProjector
## (this dir) does the pure world->screen geometry and is unit-tested
## headlessly (simulation/tests/test_tactical_plot_projector.gd); this
## class only reads world.sensor_contacts/world.ships and draws.
##
## SOURCE OF CONTACTS -- deliberately `world.sensor_contacts[pov_ship_id]`,
## NOT `world.ships`/`world.missiles` directly: SimulationWorld.
## _update_sensors() already writes BOTH ship AND missile contacts into
## that one dictionary (keyed by ship_id or missile_id respectively --
## confirmed by reading simulation_world.gd._update_sensors, which
## calls SensorResolution.update_contacts for every ship AND every
## missile into the same `contacts` dict). Reading it here means the
## plot honestly reflects §23 sensor detection/fog-of-war (a contact
## the ship's SENSORS subsystem has not actually detected does not
## appear, and a lost contact fades rather than vanishing/updating
## instantly) instead of omnisciently drawing world truth -- more
## correct for a "tactical plot" (the whole point of which, per §56.2's
## own reasoning, is that it shows the tactical officer's SENSOR
## picture, not reality). WeaponFx's missile markers (§56.1 item 3) are
## a different, already-shipped capability that intentionally draws
## world.missiles directly for the 3D view; this file does not change
## that. Ship vs missile contacts are told apart the exact same way
## SimulationWorld._update_missiles already does for counter-missiles:
## `contact.target is MissileState`.
##
## ТЗ §56.3 item A ("Multi-select"): this is also now the plot's mouse
## INPUT surface -- LMB click/CTRL+LMB/SHIFT+LMB/drag-box against a
## shared SelectionState (see that file's own doc comment for the
## selection semantics chosen for each modifier). Hit-testing is pure
## geometry (scripts/tactical_plot_selection.gd, unit-tested headlessly
## the same way TacticalPlotProjector is) against `_last_icons`, a flat
## list of {id, pos, radius} rebuilt every _draw() call -- the single
## source of truth for "where is each icon actually drawn right now",
## per the leftover note this file's own §56.2 planning left in
## state.md ("keep each contact's last-drawn icon_pos/radius for
## hit-testing, not recompute a parallel copy"). §56.3 items B-D (named
## command groups, move/attack orders, weapon panel) build on top of
## `selection` but are NOT this file's job -- this file only tracks
## "what is currently selected" and draws a highlight around it.
class_name TacticalPlot

const MissileState = preload("res://simulation/missile_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const TacticalPlotProjector = preload("res://scripts/tactical_plot_projector.gd")
const TacticalPlotSelection = preload("res://scripts/tactical_plot_selection.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const MoveOrderController = preload("res://scripts/move_order_controller.gd")

## Plot auto-scales each update() to comfortably fit the farthest
## currently-live contact -- keeps every known contact on-plot without a
## manual zoom control, which §56.2 item C (mouse-first control, NOT yet
## implemented -- see state.md) is expected to add explicit zoom/pan
## input for later. ASSUMPTION: a floor so the plot does not zoom in to
## a meaningless scale when there are zero/very-close contacts.
const MIN_PLOT_RANGE_M: float = 50_000.0
const AUTO_SCALE_MARGIN: float = 1.15

const PLOT_SIZE_PX: float = 320.0
const PLOT_MARGIN_PX: float = 12.0
const RING_COUNT: int = 4

## How many seconds of travel a contact's velocity-vector leader line
## represents. Purely a legibility scale (ASSUMPTION), same status as
## WeaponFx's BEAM_WIDTH_M/MISSILE_MARKER_RADIUS_M placeholder
## constants -- not a canon figure.
const VELOCITY_LEADER_SECONDS: float = 60.0

const OWN_SHIP_COLOR := Color(0.55, 0.95, 1.0)
const HOSTILE_COLOR := Color(1.0, 0.3, 0.25)
const FRIENDLY_COLOR := Color(0.4, 1.0, 0.5)
const NEUTRAL_COLOR := Color(0.85, 0.85, 0.3)
const MISSILE_COLOR := Color(1.0, 0.85, 0.2)  # matches WeaponFx's 3D missile marker colour, so the same threat reads the same hue in both views
const BACKGROUND_COLOR := Color(0.02, 0.05, 0.04, 0.85)
const RIM_COLOR := Color(0.3, 0.6, 0.5, 0.6)
const RING_COLOR := Color(0.25, 0.45, 0.4, 0.35)
const RING_LABEL_COLOR := Color(0.4, 0.65, 0.6, 0.7)
## Contacts not currently DETECTED/TRACKED (i.e. ESTIMATED/UNCERTAIN/
## LOST -- dead-reckoned, not a live detection this tick) are drawn
## dimmer so stale data reads as stale, a real §23 distinction this
## plot would otherwise flatten away.
const STALE_ALPHA: float = 0.45

## §56.3 item A: selection visuals + hit-testing geometry.
const SELECTION_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const SHIP_HIT_RADIUS_PX: float = 10.0
const MISSILE_HIT_RADIUS_PX: float = 8.0
const OWN_SHIP_HIT_RADIUS_PX: float = 10.0
## Minimum pointer travel (px) before a held LMB counts as a drag rather
## than a click -- ASSUMPTION, purely a game-feel debounce so a slightly
## shaky click does not get misread as an empty drag-box that clears the
## selection.
const DRAG_THRESHOLD_PX: float = 4.0
const DRAG_BOX_FILL_COLOR := Color(0.6, 0.9, 1.0, 0.12)
const DRAG_BOX_BORDER_COLOR := Color(0.6, 0.9, 1.0, 0.8)

## §56.3 item C: RMB move-order visualization (§1.10.6 -- "линия курса;
## стрелка; конечная точка; прогнозируемый vector"). Colour deliberately
## distinct from SELECTION_COLOR/every contact colour so a pending move
## order reads as its own category of overlay, not a selection ring.
const MOVE_ORDER_COLOR := Color(1.0, 0.8, 0.3, 0.95)
const MOVE_ORDER_ENDPOINT_RADIUS_PX: float = 5.0
const MOVE_ORDER_ARROW_LENGTH_PX: float = 10.0
const MOVE_ORDER_ARROW_WIDTH_PX: float = 5.0

var pov_ship_id: String = ""
var plot_range_m: float = MIN_PLOT_RANGE_M

## Shared with other §56.3 UI (squadron-list panel, order menu) via
## main.gd -- see class doc comment above. Assigned by main.gd right
## after instantiation; guarded against null everywhere it's read since
## a plot with no selection assigned should just behave as a
## read-only display (matches every other optional collaborator in this
## codebase, e.g. Hud/WeaponFx never assume a fully-wired scene either).
var selection: SelectionState = null

## §56.3 item C: same shared collaborator pattern as `selection` above --
## assigned by main.gd, guarded against null everywhere it's read. Owns
## the RMB-click-to-move-order routing/order-construction (see that
## class's own doc comment); this file only (a) turns a RMB release into
## a world-space point via TacticalPlotProjector.unproject and forwards
## it, and (b) draws whatever `move_order_controller.active_move_orders`
## currently holds -- no order-issuing logic of its own.
var move_order_controller: MoveOrderController = null

var _contacts: Array = []  # Array[Dictionary], rebuilt each update()
var _origin_present: bool = false
var _pov_position: Vector3 = Vector3.ZERO
var _pov_velocity: Vector3 = Vector3.ZERO

## Rebuilt every _draw() call: Array[{"id": String, "pos": Vector2,
## "radius": float}] in the exact screen positions just drawn --
## hit-testing (mouse input) always reads THIS, never a parallel
## recomputation, so "what you see is what you can click" by
## construction.
var _last_icons: Array = []

var _drag_active: bool = false
var _drag_start_px: Vector2 = Vector2.ZERO
var _drag_current_px: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(PLOT_SIZE_PX, PLOT_SIZE_PX)
	size = Vector2(PLOT_SIZE_PX, PLOT_SIZE_PX)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, int(PLOT_MARGIN_PX))
	# §56.3 item A: the plot is now a real input surface (click/drag
	# select) -- STOP so it actually receives mouse events instead of
	# passing them through to whatever's behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP

## Call once per simulation tick (same call site/order as Hud.update /
## WeaponFx.update, see main.gd._on_tick) with the world and which ship
## this plot is a point of view for.
func update(world: SimulationWorld, ship_id: String) -> void:
	pov_ship_id = ship_id
	_contacts.clear()

	var pov_ship: ShipPhysicsState = world.ships.get(ship_id)
	_origin_present = pov_ship != null
	if not _origin_present:
		queue_redraw()
		return

	_pov_position = pov_ship.position
	_pov_velocity = pov_ship.velocity

	var farthest_m: float = MIN_PLOT_RANGE_M
	var contacts: Dictionary = world.sensor_contacts.get(ship_id, {})
	for contact_id in contacts.keys():
		var contact = contacts[contact_id]
		if contact.state == ContactState.Type.UNKNOWN:
			continue  # never actually detected -- nothing to show yet (§23)
		var is_missile: bool = contact.target is MissileState
		var range_m: float = _pov_position.distance_to(contact.estimated_position)
		farthest_m = maxf(farthest_m, range_m)
		_contacts.append({
			"id": contact_id,
			"is_missile": is_missile,
			"estimated_position": contact.estimated_position,
			"estimated_velocity": contact.estimated_velocity,
			"state": contact.state,
			"hostile": (not is_missile) and world.is_hostile(ship_id, contact_id),
			"friendly": (not is_missile) and contact_id != ship_id
				and world.teams.get(contact_id, "") != ""
				and world.teams.get(contact_id, "") == world.teams.get(ship_id, ""),
		})

	plot_range_m = maxf(farthest_m * AUTO_SCALE_MARGIN, MIN_PLOT_RANGE_M)
	queue_redraw()

func _draw() -> void:
	_last_icons.clear()

	var radius: float = minf(size.x, size.y) * 0.5 - PLOT_MARGIN_PX
	if radius <= 4.0:
		return
	var center: Vector2 = size * 0.5

	draw_circle(center, radius + PLOT_MARGIN_PX * 0.5, BACKGROUND_COLOR)
	draw_arc(center, radius, 0.0, TAU, 48, RIM_COLOR, 1.5)

	for i in range(1, RING_COUNT + 1):
		var ring_r: float = radius * float(i) / float(RING_COUNT)
		draw_arc(center, ring_r, 0.0, TAU, 48, RING_COLOR, 1.0)
		var ring_range_m: float = plot_range_m * float(i) / float(RING_COUNT)
		draw_string(ThemeDB.fallback_font, center + Vector2(4, -ring_r + 12), _format_range(ring_range_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_LABEL_COLOR)

	if not _origin_present:
		draw_string(ThemeDB.fallback_font, center - Vector2(70, 0), "NO PLOT (own ship unknown)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HOSTILE_COLOR)
		_draw_drag_box()
		return

	# Own ship: small square at the plot's centre (it is, by definition,
	# its own origin), plus its own velocity leader so the player can
	# read their own vector at a glance the same way as any contact's.
	draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)), OWN_SHIP_COLOR, false, 2.0)
	_draw_velocity_leader(center, _pov_velocity, radius, OWN_SHIP_COLOR)
	draw_string(ThemeDB.fallback_font, center + Vector2(8, 18), pov_ship_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, OWN_SHIP_COLOR)
	_register_icon(pov_ship_id, center, OWN_SHIP_HIT_RADIUS_PX)
	if selection != null and selection.is_selected(pov_ship_id):
		_draw_selection_ring(center, OWN_SHIP_HIT_RADIUS_PX + 4.0)

	for contact in _contacts:
		var projection: Dictionary = TacticalPlotProjector.project(contact["estimated_position"], _pov_position, plot_range_m, radius)
		var icon_pos: Vector2 = center + projection["plot_offset_px"]
		var color: Color = _contact_color(contact)
		if contact["state"] != ContactState.Type.DETECTED and contact["state"] != ContactState.Type.TRACKED:
			color.a = STALE_ALPHA

		if contact["is_missile"]:
			_draw_missile_icon(icon_pos, color)
			_register_icon(contact["id"], icon_pos, MISSILE_HIT_RADIUS_PX)
		else:
			_draw_ship_icon(icon_pos, color, projection["clamped"])
			var lead_target: Vector3 = contact["estimated_position"] + contact["estimated_velocity"] * VELOCITY_LEADER_SECONDS
			var lead_projection: Dictionary = TacticalPlotProjector.project(lead_target, _pov_position, plot_range_m, radius)
			draw_line(icon_pos, center + lead_projection["plot_offset_px"], color, 1.5)
			_register_icon(contact["id"], icon_pos, SHIP_HIT_RADIUS_PX)

		if selection != null and selection.is_selected(contact["id"]):
			_draw_selection_ring(icon_pos, (MISSILE_HIT_RADIUS_PX if contact["is_missile"] else SHIP_HIT_RADIUS_PX) + 4.0)

		var label: String = "%s  %s  %s" % [contact["id"], _format_range(projection["range_m"]), _format_bearing(projection["bearing_rad"])]
		draw_string(ThemeDB.fallback_font, icon_pos + Vector2(8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

	_draw_move_orders(center, radius)
	_draw_drag_box()

func _draw_ship_icon(pos: Vector2, color: Color, clamped: bool) -> void:
	var s: float = 6.0
	var points := PackedVector2Array([pos + Vector2(0, -s), pos + Vector2(s, s), pos + Vector2(-s, s)])
	draw_polygon(points, PackedColorArray([color]))
	if clamped:
		draw_arc(pos, s + 3.0, 0.0, TAU, 12, color, 1.0)  # ring: "known to be further out, pulled to the rim"

func _draw_missile_icon(pos: Vector2, color: Color) -> void:
	# Distinct shape from the ship triangle (item B: "own distinctly-
	# marked icon/track... separate from ship contacts") -- an X/cross,
	# not a triangle, so missiles read as a different class of contact
	# at a glance, not just a different colour.
	var s: float = 4.0
	draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), color, 2.0)
	draw_line(pos + Vector2(-s, s), pos + Vector2(s, -s), color, 2.0)

func _draw_velocity_leader(from_px: Vector2, velocity: Vector3, radius: float, color: Color) -> void:
	if velocity.length_squared() < 0.0001:
		return
	var lead_m := Vector2(velocity.x, velocity.z) * VELOCITY_LEADER_SECONDS
	var scale_px_per_m: float = radius / maxf(plot_range_m, 0.001)
	var lead_px: Vector2 = lead_m * scale_px_per_m
	if lead_px.length() > radius * 0.9:
		lead_px = lead_px.normalized() * radius * 0.9
	draw_line(from_px, from_px + lead_px, color, 1.5)

## §56.3 item C: draws every pending move order's course line, arrowhead
## and endpoint marker (§1.10.6) -- reads `move_order_controller.
## active_move_orders` (UI-side bookkeeping, see that class's own doc
## comment) and looks each anchor id's CURRENT on-screen position up in
## `_last_icons` (same "what you see is what's drawn" source hit-testing
## itself uses) so the line always starts from wherever the anchor is
## actually drawn this frame, not a stale remembered position. Silently
## skips an anchor no longer present in `_last_icons` (destroyed, or
## simply out of live sensor contact this tick -- §23 fog-of-war applies
## here exactly as everywhere else in this file).
##
## NOT drawn (ASSUMPTION, §1.10.6's own text makes it conditional --
## "при необходимости"): a distinct "predicted turn point" marker. This
## codebase's maneuver model treats thrust as omnidirectional relative to
## a ship's facing (see individual_order.gd/formation_order.gd class
## docs -- "change course" retargets the velocity vector, not the nose),
## so there is no discrete "ship turns, THEN burns" maneuver phase for a
## move order to mark a turn point for; the course line + velocity leader
## (drawn separately, already existing) together already show both the
## intended destination and the ship's actual current predicted vector.
## See ASSUMPTIONS.md "§56.3 item C".
func _draw_move_orders(center: Vector2, radius: float) -> void:
	if move_order_controller == null:
		return
	for anchor_id in move_order_controller.active_move_orders.keys():
		var anchor_icon = _find_icon(anchor_id)
		if anchor_icon == null:
			continue
		var target_point: Vector3 = move_order_controller.active_move_orders[anchor_id]["target_point"]
		var projection: Dictionary = TacticalPlotProjector.project(target_point, _pov_position, plot_range_m, radius)
		var target_px: Vector2 = center + projection["plot_offset_px"]
		var from_px: Vector2 = anchor_icon["pos"]

		draw_line(from_px, target_px, MOVE_ORDER_COLOR, 1.5)
		_draw_move_order_arrowhead(from_px, target_px)
		draw_arc(target_px, MOVE_ORDER_ENDPOINT_RADIUS_PX, 0.0, TAU, 12, MOVE_ORDER_COLOR, 1.5)

## Small filled triangle at `to_px`, pointing along the from->to
## direction -- the "стрелка" (arrow) item of §1.10.6's visualization
## list, drawn as its own shape rather than an arrowhead baked into
## draw_line (Godot's CanvasItem API has no built-in arrow primitive).
func _draw_move_order_arrowhead(from_px: Vector2, to_px: Vector2) -> void:
	var dir: Vector2 = (to_px - from_px)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = to_px
	var base_center: Vector2 = to_px - dir * MOVE_ORDER_ARROW_LENGTH_PX
	var left: Vector2 = base_center + perp * (MOVE_ORDER_ARROW_WIDTH_PX * 0.5)
	var right: Vector2 = base_center - perp * (MOVE_ORDER_ARROW_WIDTH_PX * 0.5)
	draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([MOVE_ORDER_COLOR]))

## Looks `id` up in `_last_icons` (rebuilt fresh every _draw() call --
## see that Array's own doc comment on top of this file) -- null if not
## currently drawn. Small linear scan: `_last_icons` is at most a
## handful of live contacts, same cost class as TacticalPlotSelection's
## own hit_test/box_test.
func _find_icon(id: String):
	for icon in _last_icons:
		if icon["id"] == id:
			return icon
	return null

## §56.3 item A: a plain ring around a selected icon's already-drawn
## position -- deliberately not a re-draw of the icon itself (own shape/
## colour stay exactly as drawn above; selection is an ADDITIONAL cue,
## per §1.10.4 "После выбора объект получает визуальное выделение").
func _draw_selection_ring(pos: Vector2, ring_radius: float) -> void:
	draw_arc(pos, ring_radius, 0.0, TAU, 16, SELECTION_COLOR, 1.5)

func _draw_drag_box() -> void:
	if not _drag_active:
		return
	var rect := Rect2(_drag_start_px, _drag_current_px - _drag_start_px).abs()
	draw_rect(rect, DRAG_BOX_FILL_COLOR, true)
	draw_rect(rect, DRAG_BOX_BORDER_COLOR, false, 1.0)

func _register_icon(id: String, pos: Vector2, hit_radius: float) -> void:
	_last_icons.append({"id": id, "pos": pos, "radius": hit_radius})

func _contact_color(contact: Dictionary) -> Color:
	if contact["is_missile"]:
		return MISSILE_COLOR
	if contact["hostile"]:
		return HOSTILE_COLOR
	if contact["friendly"]:
		return FRIENDLY_COLOR
	return NEUTRAL_COLOR

static func _format_range(range_m: float) -> String:
	if range_m >= 1_000_000.0:
		return "%.2f Mkm" % (range_m / 1_000_000.0)
	return "%.0f km" % (range_m / 1000.0)

static func _format_bearing(bearing_rad: float) -> String:
	return "%03d°" % [int(round(rad_to_deg(bearing_rad))) % 360]

## §56.3 item A: LMB click / CTRL+LMB / SHIFT+LMB / LMB drag-box, per
## §1.10.4 and SelectionState's own doc comment for the exact semantics
## chosen for each modifier. A no-op entirely if `selection` was never
## assigned (see that var's own doc comment).
func _gui_input(event: InputEvent) -> void:
	if selection == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = false
			_drag_start_px = event.position
			_drag_current_px = event.position
			accept_event()
		else:
			_on_left_release(event)
			accept_event()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			_on_right_release(event)
		accept_event()
		return

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_drag_current_px = event.position
		if not _drag_active and _drag_start_px.distance_to(_drag_current_px) >= DRAG_THRESHOLD_PX:
			_drag_active = true
		if _drag_active:
			queue_redraw()
		accept_event()

func _on_left_release(event: InputEventMouseButton) -> void:
	var ctrl: bool = event.ctrl_pressed
	var shift: bool = event.shift_pressed

	if _drag_active:
		var rect := Rect2(_drag_start_px, event.position - _drag_start_px).abs()
		var hits: Array = TacticalPlotSelection.box_test(rect, _last_icons)
		if ctrl:
			for id in hits:
				selection.toggle(id)
		elif shift:
			selection.add_only(hits)
		else:
			selection.select_only(hits)
	else:
		var hit_id: String = TacticalPlotSelection.hit_test(event.position, _last_icons)
		if hit_id != "":
			if ctrl:
				selection.toggle(hit_id)
			elif shift:
				selection.add_only([hit_id])
			else:
				selection.select_only([hit_id])
		elif not ctrl and not shift:
			# Plain click on empty plot space clears the selection --
			# standard RTS-style convention, not spelled out verbatim in
			# §1.10.4 but implied by it always describing selection as
			# something the player actively builds up; CTRL/SHIFT click
			# on empty space intentionally does nothing (nothing to
			# add/toggle).
			selection.clear()

	_drag_active = false
	queue_redraw()

## ТЗ §56.3 item C / §1.10.6: RMB release against the plot -> a move
## order for the current selection. A no-op if `move_order_controller`
## was never assigned (same optional-collaborator convention as
## `selection`, see that var's own doc comment) or if the plot has no
## live origin yet (no pov ship -- nothing to compute a sensible world
## point relative to).
func _on_right_release(event: InputEventMouseButton) -> void:
	if move_order_controller == null or not _origin_present:
		return
	var radius: float = minf(size.x, size.y) * 0.5 - PLOT_MARGIN_PX
	if radius <= 4.0:
		return
	var center: Vector2 = size * 0.5
	var offset_px: Vector2 = event.position - center
	var target_point: Vector3 = TacticalPlotProjector.unproject(offset_px, _pov_position, plot_range_m, radius)
	move_order_controller.issue_move_order(target_point)
	queue_redraw()
