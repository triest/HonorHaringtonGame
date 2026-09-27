extends Control
## BattleOverlay
##
## 2026-09-27 live user report: "no missiles visible", "no mouse control,
## no squadron selection". At the canon-scale demo (squadrons ~5 million km
## apart) the 3D hull meshes are far below one pixel, so the 3D view showed
## nothing useful. This overlay projects every ship and missile into
## screen space each frame (Camera3D.unproject_position) and draws
## readable tactical symbols over the 3D view -- IFF-coloured ship icons
## with name + hull %, missile dots with short motion streaks coloured by
## side -- and makes those symbols the MAIN mouse surface:
##
##   LMB click own ship       select it (Ctrl = toggle, Shift = add)
##   LMB drag                 box-select own ships
##   LMB click enemy ship     with own ships selected: designate target +
##                            open the order menu (ATTACK / APPROACH / ...)
##   LMB click empty space    clear selection
##   RMB click (no drag)      move order for the selection to that point
##                            (on the horizontal plane through the
##                            selection); RMB DRAG still orbits the camera
##
## Sensor honesty (§23): hostile ships/missiles are drawn from the player's
## own sensor contacts (estimated positions), never ground truth; own ships
## and own missiles from true state. Pure view + input routing: every
## order goes through the existing controllers (MoveOrderController,
## OrderMenuController) -- no new order logic here.
class_name BattleOverlay

const UiTheme = preload("res://scripts/ui_theme.gd")
const ContactState = preload("res://simulation/contact_state.gd")

const OWN_COLOR := Color(0.55, 0.95, 1.0)
const HOSTILE_COLOR := Color(1.0, 0.35, 0.3)
const WRECK_COLOR := Color(0.55, 0.55, 0.55, 0.8)
const OWN_MISSILE_COLOR := Color(0.6, 1.0, 0.6, 0.95)
const HOSTILE_MISSILE_COLOR := Color(1.0, 0.8, 0.2, 0.95)
const SELECT_COLOR := Color(1, 1, 1, 0.95)
const TARGET_COLOR := Color(1.0, 0.55, 0.1, 0.95)
const MOVE_COLOR := Color(1.0, 0.8, 0.3, 0.9)
const CLUSTER_PX: float = 16.0
const PICK_RADIUS_PX: float = 14.0
const DRAG_THRESHOLD_PX: float = 6.0
const MISSILE_STREAK_S: float = 2.0

var world: SimulationWorld
var selection: SelectionState
var camera: Camera3D
var player_team: String = ""
var move_order_controller: MoveOrderController
var order_menu_controller: OrderMenuController

var _icons: Array = []  # {id, pos: Vector2, own: bool, hostile: bool}
var _lmb_down: bool = false
var _lmb_start: Vector2 = Vector2.ZERO
var _lmb_cur: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _rmb_down: bool = false
var _rmb_start: Vector2 = Vector2.ZERO
var _rmb_moved: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # drawing only; input via _unhandled_input (after real GUI panels)

func _process(_delta: float) -> void:
	queue_redraw()

## Any alive own ship whose sensor picture we show (flagship preferred).
func _pov_ship_id() -> String:
	if world == null:
		return ""
	var best: String = ""
	for sid in world.ships.keys():
		if String(world.teams.get(sid, "")) == player_team and not world.ships[sid].is_wreck:
			if best == "" or sid == "alpha":
				best = sid
	return best

func _visible_objects() -> Array:
	# Returns [{id, pos3, vel3, kind: "ship"/"missile", own, wreck}]
	var out: Array = []
	if world == null:
		return out
	var pov: String = _pov_ship_id()
	var contacts: Dictionary = world.sensor_contacts.get(pov, {}) if pov != "" else {}
	for sid in world.ships.keys():
		var ship: ShipPhysicsState = world.ships[sid]
		var own: bool = String(world.teams.get(sid, "")) == player_team
		if own:
			out.append({"id": sid, "pos3": ship.position, "vel3": ship.velocity, "kind": "ship", "own": true, "wreck": ship.is_wreck})
		else:
			var c = contacts.get(sid)
			if c == null or c.state == ContactState.Type.UNKNOWN:
				continue
			out.append({"id": sid, "pos3": c.estimated_position, "vel3": c.estimated_velocity, "kind": "ship", "own": false, "wreck": ship.is_wreck})
	for mid in world.missiles.keys():
		var m = world.missiles[mid]
		if not m.is_active():
			continue
		var owner_team: String = String(world.teams.get(world.missile_owners.get(mid, ""), ""))
		var own_m: bool = owner_team == player_team
		if own_m:
			out.append({"id": mid, "pos3": m.position, "vel3": m.velocity, "kind": "missile", "own": true, "wreck": false})
		else:
			var mc = contacts.get(mid)
			if mc == null or mc.state == ContactState.Type.UNKNOWN:
				continue
			out.append({"id": mid, "pos3": mc.estimated_position, "vel3": mc.estimated_velocity, "kind": "missile", "own": false, "wreck": false})
	return out

func _draw() -> void:
	_icons.clear()
	if world == null or camera == null:
		return
	var font: Font = get_theme_default_font()
	var objs: Array = _visible_objects()

	# Missiles first (under the ship symbols).
	for o in objs:
		if o["kind"] != "missile":
			continue
		if camera.is_position_behind(o["pos3"]):
			continue
		var p: Vector2 = camera.unproject_position(o["pos3"])
		var col: Color = OWN_MISSILE_COLOR if o["own"] else HOSTILE_MISSILE_COLOR
		var tail3: Vector3 = o["pos3"] - o["vel3"] * MISSILE_STREAK_S
		if not camera.is_position_behind(tail3):
			var tp: Vector2 = camera.unproject_position(tail3)
			draw_line(tp, p, Color(col, 0.45), 1.0)
		draw_circle(p, 2.2, col)

	# Move-order course lines (from MoveOrderController bookkeeping).
	if move_order_controller != null:
		for anchor_id in move_order_controller.active_move_orders.keys():
			var ship: ShipPhysicsState = world.ships.get(anchor_id)
			if ship == null:
				continue
			var tgt: Vector3 = move_order_controller.active_move_orders[anchor_id]["target_point"]
			if camera.is_position_behind(ship.position) or camera.is_position_behind(tgt):
				continue
			var a: Vector2 = camera.unproject_position(ship.position)
			var b: Vector2 = camera.unproject_position(tgt)
			draw_dashed_line(a, b, MOVE_COLOR, 1.5, 8.0)
			draw_arc(b, 6.0, 0.0, TAU, 16, MOVE_COLOR, 1.5)

	# Ships, clustered so a 4-ship line 60 km wide seen from millions of
	# km reads as one labelled squadron symbol instead of 4 stacked labels.
	var clusters: Array = []  # {pos, own, ids: Array, wreck_count}
	for o in objs:
		if o["kind"] != "ship":
			continue
		if camera.is_position_behind(o["pos3"]):
			continue
		var p: Vector2 = camera.unproject_position(o["pos3"])
		_icons.append({"id": o["id"], "pos": p, "own": o["own"], "hostile": not o["own"], "wreck": o["wreck"]})
		var joined: bool = false
		for c in clusters:
			if c["own"] == o["own"] and c["pos"].distance_to(p) < CLUSTER_PX:
				c["ids"].append(o["id"])
				joined = true
				break
		if not joined:
			clusters.append({"pos": p, "own": o["own"], "ids": [o["id"]]})

	for ic in _icons:
		var col: Color = WRECK_COLOR if ic["wreck"] else (OWN_COLOR if ic["own"] else HOSTILE_COLOR)
		var p: Vector2 = ic["pos"]
		if ic["wreck"]:
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), col, 2.0)
		elif ic["own"]:
			var tri := PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)])
			draw_colored_polygon(tri, Color(col, 0.35))
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), col, 1.5)
		else:
			var dia := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)])
			draw_colored_polygon(dia, Color(col, 0.35))
			draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), col, 1.5)
		if selection != null and selection.is_selected(ic["id"]):
			_draw_brackets(p, 11.0, SELECT_COLOR)
		if selection != null and selection.designated_target_id == ic["id"]:
			_draw_brackets(p, 14.0, TARGET_COLOR)

	for c in clusters:
		var ids: Array = c["ids"]
		var text: String
		if ids.size() == 1:
			text = _ship_label(ids[0])
		else:
			var alive: int = 0
			for sid in ids:
				if not world.ships[sid].is_wreck:
					alive += 1
			text = "%s  (%d/%d)" % ["ЭСКАДРА" if c["own"] else "ПРОТИВНИК", alive, ids.size()]
		var col2: Color = OWN_COLOR if c["own"] else HOSTILE_COLOR
		draw_string_outline(font, c["pos"] + Vector2(12, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.9))
		draw_string(font, c["pos"] + Vector2(12, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col2)

	if _dragging:
		var r := Rect2(_lmb_start, _lmb_cur - _lmb_start).abs()
		draw_rect(r, Color(0.6, 0.9, 1.0, 0.12), true)
		draw_rect(r, Color(0.6, 0.9, 1.0, 0.8), false, 1.0)

func _ship_label(sid: String) -> String:
	var h = world.hulls.get(sid)
	if world.ships[sid].is_wreck:
		return "%s  УНИЧТОЖЕН" % sid
	if h != null and h.max_integrity > 0.0:
		return "%s  %d%%" % [sid, int(round(100.0 * h.integrity / h.max_integrity))]
	return sid

func _draw_brackets(p: Vector2, r: float, col: Color) -> void:
	var l: float = r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = p + Vector2(sx * r, sy * r)
			draw_line(corner, corner - Vector2(sx * l, 0), col, 1.5)
			draw_line(corner, corner - Vector2(0, sy * l), col, 1.5)

func _pick(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = PICK_RADIUS_PX
	for ic in _icons:
		if ic["wreck"]:
			continue
		var d: float = ic["pos"].distance_to(pos)
		if d <= best_d:
			best_d = d
			best = ic
	return best

## Own, alive ships near a clicked own icon: a click on a squadron
## cluster selects the whole cluster (ships drawn on top of each other
## cannot be told apart by clicking anyway; zoom in to pick one).
func _cluster_ids_at(pos: Vector2, own: bool) -> Array:
	var ids: Array = []
	for ic in _icons:
		if ic["wreck"] or ic["own"] != own:
			continue
		if ic["pos"].distance_to(pos) <= CLUSTER_PX:
			ids.append(ic["id"])
	return ids

func _own_selected_count() -> int:
	var n: int = 0
	if selection == null:
		return 0
	for sid in selection.selected_ids:
		if String(world.teams.get(sid, "")) == player_team:
			n += 1
	return n

func _unhandled_input(event: InputEvent) -> void:
	if world == null or camera == null or selection == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down = true
				_dragging = false
				_lmb_start = mb.position
				_lmb_cur = mb.position
			elif _lmb_down:
				_lmb_down = false
				if _dragging:
					_dragging = false
					_box_select(Rect2(_lmb_start, _lmb_cur - _lmb_start).abs(), mb.shift_pressed or mb.ctrl_pressed)
				else:
					_click(mb.position, mb.ctrl_pressed, mb.shift_pressed)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down = true
				_rmb_moved = false
				_rmb_start = mb.position
			elif _rmb_down:
				_rmb_down = false
				if not _rmb_moved:
					_move_order_at(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _lmb_down:
			_lmb_cur = mm.position
			if not _dragging and _lmb_cur.distance_to(_lmb_start) > DRAG_THRESHOLD_PX:
				_dragging = true
		if _rmb_down and mm.position.distance_to(_rmb_start) > DRAG_THRESHOLD_PX:
			_rmb_moved = true

func _click(pos: Vector2, ctrl: bool, shift: bool) -> void:
	var hit: Dictionary = _pick(pos)
	if hit.is_empty():
		if not ctrl and not shift:
			selection.clear()
		return
	if hit["hostile"]:
		if _own_selected_count() > 0 and order_menu_controller != null:
			order_menu_controller.try_open(hit["id"], pos)
		else:
			selection.designate_target(hit["id"])
		return
	var ids: Array = _cluster_ids_at(hit["pos"], true)
	if ids.size() > 1 and not ctrl:
		# First click on a stacked squadron symbol selects the whole
		# squadron; clicking again while it is already the full selection
		# narrows to the single nearest ship.
		var all_sel: bool = selection.selected_ids.size() == ids.size()
		for sid in ids:
			if not selection.is_selected(sid):
				all_sel = false
		if all_sel:
			selection.select_only([hit["id"]])
		elif shift:
			selection.add_only(ids)
		else:
			selection.select_only(ids)
		return
	if ctrl:
		selection.toggle(hit["id"])
	elif shift:
		selection.add_only([hit["id"]])
	else:
		selection.select_only([hit["id"]])

func _box_select(r: Rect2, additive: bool) -> void:
	var ids: Array = []
	for ic in _icons:
		if ic["own"] and not ic["wreck"] and r.has_point(ic["pos"]):
			ids.append(ic["id"])
	if additive:
		selection.add_only(ids)
	else:
		selection.select_only(ids)

## RMB click: world point where the camera ray meets the horizontal plane
## through the selection's centre (all demo ships fly in y = 0).
func _move_order_at(pos: Vector2) -> void:
	if move_order_controller == null or _own_selected_count() == 0:
		return
	var plane_y: float = 0.0
	var n: int = 0
	for sid in selection.selected_ids:
		var s: ShipPhysicsState = world.ships.get(sid)
		if s != null:
			plane_y += s.position.y
			n += 1
	if n > 0:
		plane_y /= float(n)
	var origin: Vector3 = camera.project_ray_origin(pos)
	var dir: Vector3 = camera.project_ray_normal(pos)
	if absf(dir.y) < 1e-6:
		return
	var t: float = (plane_y - origin.y) / dir.y
	if t <= 0.0:
		return
	move_order_controller.issue_move_order(origin + dir * t)
