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
const CLOSE_UP_M: float = 25_000.0

var world: SimulationWorld
var selection: SelectionState
var camera: Camera3D
var player_team: String = ""
var move_order_controller: MoveOrderController
var order_menu_controller: OrderMenuController
## Double-click on an own ship/squadron symbol: select it and fly the
## camera to it (follows it; Esc releases). Set by main.gd.
var camera_focus_controller: CameraFocusController

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
	var ship_by_obj: Dictionary = {}
	for sid2 in world.ships.keys():
		ship_by_obj[world.ships[sid2]] = sid2
	for mid in world.missiles.keys():
		var m = world.missiles[mid]
		if not m.is_active():
			continue
		if world.counter_missile_ids.has(mid):
			continue  # counter-missiles are not salvo symbols (2026-09-29)
		var tgt_id: String = ship_by_obj.get(m.target, "") if m.target != null else ""
		var owner_team: String = String(world.teams.get(world.missile_owners.get(mid, ""), ""))
		var own_m: bool = owner_team == player_team
		if own_m:
			out.append({"id": mid, "pos3": m.position, "vel3": m.velocity, "kind": "missile", "own": true, "wreck": false, "target": tgt_id})
		else:
			var mc = contacts.get(mid)
			if mc == null or mc.state == ContactState.Type.UNKNOWN:
				continue
			out.append({"id": mid, "pos3": mc.estimated_position, "vel3": mc.estimated_velocity, "kind": "missile", "own": false, "wreck": false, "target": tgt_id})
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
		if camera.is_position_behind(RenderOrigin.to_render(o["pos3"])):
			continue
		var p: Vector2 = camera.unproject_position(RenderOrigin.to_render(o["pos3"]))
		var col: Color = OWN_MISSILE_COLOR if o["own"] else HOSTILE_MISSILE_COLOR
		var tail3: Vector3 = o["pos3"] - o["vel3"] * MISSILE_STREAK_S
		if not camera.is_position_behind(RenderOrigin.to_render(tail3)):
			var tp: Vector2 = camera.unproject_position(RenderOrigin.to_render(tail3))
			draw_line(tp, p, Color(col, 0.45), 1.0)
		draw_circle(p, 2.2, col)

	# Move-order course lines (from MoveOrderController bookkeeping).
	if move_order_controller != null:
		for anchor_id in move_order_controller.active_move_orders.keys():
			var ship: ShipPhysicsState = world.ships.get(anchor_id)
			if ship == null:
				continue
			var tgt: Vector3 = move_order_controller.active_move_orders[anchor_id]["target_point"]
			if camera.is_position_behind(RenderOrigin.to_render(ship.position)) or camera.is_position_behind(RenderOrigin.to_render(tgt)):
				continue
			var a: Vector2 = camera.unproject_position(RenderOrigin.to_render(ship.position))
			var b: Vector2 = camera.unproject_position(RenderOrigin.to_render(tgt))
			draw_dashed_line(a, b, MOVE_COLOR, 1.5, 8.0)
			draw_arc(b, 6.0, 0.0, TAU, 16, MOVE_COLOR, 1.5)

	# Ships, clustered so a 4-ship line 60 km wide seen from millions of
	# km reads as one labelled squadron symbol instead of 4 stacked labels.
	var clusters: Array = []  # {pos, own, ids: Array, wreck_count}
	for o in objs:
		if o["kind"] != "ship":
			continue
		if camera.is_position_behind(RenderOrigin.to_render(o["pos3"])):
			continue
		var p: Vector2 = camera.unproject_position(RenderOrigin.to_render(o["pos3"]))
		_icons.append({"id": o["id"], "pos": p, "own": o["own"], "hostile": not o["own"], "wreck": o["wreck"], "cam_dist": camera.global_position.distance_to(RenderOrigin.to_render(o["pos3"]))})
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
		# Close enough to see the actual hull mesh: don't paint a symbol
		# over it, just the selection brackets + label.
		var close_up: bool = ic.get("cam_dist", INF) < CLOSE_UP_M
		if close_up:
			pass
		elif ic["wreck"]:
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

	# Labels: a lone ship gets "name hull%"; a stacked squadron gets a
	# header plus ONE LINE PER SHIP (name + hull %), and every line is a
	# click target selecting exactly that ship -- the user asked to see
	# and pick individual ships even when the whole line is one dot.
	_label_hits.clear()
	for c in clusters:
		var ids: Array = c["ids"]
		var col2: Color = OWN_COLOR if c["own"] else HOSTILE_COLOR
		var at: Vector2 = c["pos"] + Vector2(12, -8)
		if ids.size() > 1:
			var alive: int = 0
			for sid in ids:
				if not world.ships[sid].is_wreck:
					alive += 1
			_outlined(font, at, "%s  (%d/%d)" % ["ЭСКАДРА" if c["own"] else "ПРОТИВНИК", alive, ids.size()], 14, col2)
			at.y += 16
		for sid in ids:
			var line: String = _ship_label(sid)
			var lc: Color = WRECK_COLOR if world.ships[sid].is_wreck else col2
			if selection != null and selection.is_selected(sid):
				line = "> " + line
				lc = SELECT_COLOR
			elif selection != null and selection.designated_target_id == sid:
				line = "◎ " + line
				lc = TARGET_COLOR
			var fs: int = 13 if ids.size() > 1 else 14
			_outlined(font, at, line, fs, lc)
			var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_label_hits.append({"rect": Rect2(at + Vector2(0, -fs), Vector2(w, fs + 3)), "id": sid, "own": c["own"], "wreck": world.ships[sid].is_wreck})
			at.y += 15

	_draw_salvos(objs, font)
	_draw_formations()
	_draw_offscreen(objs, font)

	if _dragging:
		var r := Rect2(_lmb_start, _lmb_cur - _lmb_start).abs()
		draw_rect(r, Color(0.6, 0.9, 1.0, 0.12), true)
		draw_rect(r, Color(0.6, 0.9, 1.0, 0.8), false, 1.0)

var _label_hits: Array = []

func _outlined(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# ------------------------------------------------------------------
# 2026-09-27 (user: "no formation, confusing exchanges, confusing view")

const SALVO_CLUSTER_PX: float = 40.0

## Missiles grouped into SALVOS: all active missiles with the same target
## that are close together on screen get one label --
## "12 ракет → КЕВ «Отважный» · 38 с" -- plus a bracket, so a stream of
## dots reads as "which salvo is going where, and when does it land".
func _draw_salvos(objs: Array, font: Font) -> void:
	var groups: Array = []  # {pos, n, target, own, eta}
	for o in objs:
		if o["kind"] != "missile":
			continue
		var r3: Vector3 = RenderOrigin.to_render(o["pos3"])
		if camera.is_position_behind(r3):
			continue
		var p: Vector2 = camera.unproject_position(r3)
		var tgt: String = o.get("target", "")
		var eta: float = -1.0
		if world.ships.has(tgt):
			var tpos: Vector3 = world.ships[tgt].position
			var tvel: Vector3 = world.ships[tgt].velocity
			var rel: Vector3 = tpos - o["pos3"]
			var closing: float = -(tvel - o["vel3"]).dot(rel.normalized())
			if closing > 1.0:
				eta = rel.length() / closing
		var joined: bool = false
		for g in groups:
			if g["target"] == tgt and g["own"] == o["own"] and g["pos"].distance_to(p) < SALVO_CLUSTER_PX:
				g["n"] += 1
				g["sum"] += p
				if eta >= 0.0:
					g["eta"] = eta if g["eta"] < 0.0 else minf(g["eta"], eta)
				joined = true
				break
		if not joined:
			groups.append({"pos": p, "sum": p, "n": 1, "target": tgt, "own": o["own"], "eta": eta})
	var salvo_label_rects: Array = []
	for g in groups:
		if g["n"] < 2:
			continue
		var c: Vector2 = g["sum"] / float(g["n"])
		# Just-launched salvos still sit on top of their launcher: the ship
		# label is there already, skip until they separate.
		var near_ship: bool = false
		for ic in _icons:
			if ic["pos"].distance_to(c) < 30.0:
				near_ship = true
				break
		if near_ship:
			continue
		var col: Color = OWN_MISSILE_COLOR if g["own"] else HOSTILE_MISSILE_COLOR
		draw_arc(c, 14.0, 0.0, TAU, 20, Color(col, 0.7), 1.2)
		# Never stack salvo labels on top of each other: a label that would
		# overlap an earlier one is dropped (its ring stays).
		var lr := Rect2(c + Vector2(16, -10), Vector2(260, 16))
		var clash: bool = false
		for r in salvo_label_rects:
			if r.intersects(lr):
				clash = true
				break
		if clash:
			continue
		salvo_label_rects.append(lr)
		var txt: String = "%d ракет%s → %s" % [g["n"], _plural_ru(g["n"]), ShipNames.of(g["target"])]
		if g["eta"] >= 0.0:
			txt += " · %d с" % int(g["eta"])
		_outlined(font, c + Vector2(16, 4), txt, 12, col)

static func _plural_ru(n: int) -> String:
	var n10: int = n % 10
	var n100: int = n % 100
	if n10 == 1 and n100 != 11:
		return "а"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "ы"
	return ""

const FORMATION_LINE_COLOR := Color(0.55, 0.95, 1.0, 0.55)
const ENEMY_FORMATION_LINE_COLOR := Color(1.0, 0.35, 0.3, 0.5)

## The formation itself made visible: members joined in slot order (by
## their station's lateral offset) with a line, and the formation's shape
## named. Drawn only when the line is at least a few pixels long -- from
## millions of km it is one symbol anyway (then the squadron label says it).
func _draw_formations() -> void:
	var font: Font = get_theme_default_font()
	for fid in world.formations.keys():
		var f: FormationState = world.formations[fid]
		var guide: ShipPhysicsState = world.ships.get(f.guide_ship_id)
		if guide == null or guide.is_wreck:
			continue
		var own: bool = String(world.teams.get(f.guide_ship_id, "")) == player_team
		var ids: Array = [f.guide_ship_id]
		for m in f.member_ids():
			if world.ships.has(m) and not world.ships[m].is_wreck:
				ids.append(m)
		if ids.size() < 2:
			continue
		ids.sort_custom(func(a, b): return _slot_x(f, a) < _slot_x(f, b))
		var pts := PackedVector2Array()
		for sid in ids:
			var r3: Vector3 = RenderOrigin.to_render(world.ships[sid].position)
			if camera.is_position_behind(r3):
				pts = PackedVector2Array()
				break
			pts.append(camera.unproject_position(r3))
		if pts.size() < 2 or pts[0].distance_to(pts[pts.size() - 1]) < 10.0:
			continue
		var col: Color = FORMATION_LINE_COLOR if own else ENEMY_FORMATION_LINE_COLOR
		draw_polyline(pts, col, 1.5)
		var mid: Vector2 = (pts[0] + pts[pts.size() - 1]) * 0.5
		_outlined(font, mid + Vector2(-40, 28), "строй: фронт, %d кор." % ids.size(), 12, col)

func _slot_x(f: FormationState, sid: String) -> float:
	if sid == f.guide_ship_id:
		return 0.0
	return (f.member_offsets.get(sid, Vector3.ZERO) as Vector3).x

## Edge-of-screen arrows for things that matter but are out of view: the
## enemy squadron, our squadron, and incoming salvos aimed at our ships.
func _draw_offscreen(objs: Array, font: Font) -> void:
	var vr: Rect2 = get_viewport_rect()
	if vr.size.x < 200.0 or vr.size.y < 200.0:
		return  # headless / degenerate viewport
	var rect: Rect2 = vr.grow(-60.0)
	var targets: Array = []
	var en = _centroid_ids(false)
	if en != null:
		targets.append({"pos3": en, "col": HOSTILE_COLOR, "text": "ПРОТИВНИК"})
	var ow = _centroid_ids(true)
	if ow != null:
		targets.append({"pos3": ow, "col": OWN_COLOR, "text": "ЭСКАДРА"})
	var inc_n: int = 0
	var inc_sum := Vector3.ZERO
	for o in objs:
		if o["kind"] == "missile" and not o["own"]:
			inc_n += 1
			inc_sum += o["pos3"]
	if inc_n > 0:
		targets.append({"pos3": inc_sum / float(inc_n), "col": HOSTILE_MISSILE_COLOR, "text": "ракеты: %d" % inc_n})
	var center: Vector2 = get_viewport_rect().size * 0.5
	var look: Vector3 = RenderOrigin.origin
	for t in targets:
		var r3: Vector3 = RenderOrigin.to_render(t["pos3"])
		var behind: bool = camera.is_position_behind(r3)
		var p: Vector2 = camera.unproject_position(r3)
		if not behind and rect.has_point(p):
			continue
		var dir: Vector2 = (p - center)
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		# Clamp to the inset rect edge.
		var tmax: float = INF
		if absf(dir.x) > 1e-4:
			tmax = minf(tmax, ((rect.size.x * 0.5) / absf(dir.x)))
		if absf(dir.y) > 1e-4:
			tmax = minf(tmax, ((rect.size.y * 0.5) / absf(dir.y)))
		var at: Vector2 = center + dir * tmax
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([at + dir * 12.0, at - dir * 6.0 + perp * 8.0, at - dir * 6.0 - perp * 8.0])
		draw_colored_polygon(tri, t["col"])
		var dist_m: float = (t["pos3"] as Vector3).distance_to(look)
		var dtxt: String = ("%.2f млн км" % (dist_m / 1.0e9)) if dist_m >= 1.0e9 else ("%.0f тыс. км" % (dist_m / 1.0e6))
		var label_at: Vector2 = at - dir * 30.0 + Vector2(-40, 4)
		_outlined(font, label_at, "%s  %s" % [t["text"], dtxt], 12, t["col"])

func _centroid_ids(own: bool):
	var c := Vector3.ZERO
	var n: int = 0
	for sid in world.ships.keys():
		if world.ships[sid].is_wreck:
			continue
		if (String(world.teams.get(sid, "")) == player_team) != own:
			continue
		c += world.ships[sid].position
		n += 1
	return c / float(n) if n > 0 else null

func _ship_label(sid: String) -> String:
	# No hit-point percentage (AGENTS.md §25.1): name + combat-capability
	# verdict from the ship's modules (ShipStatus).
	var own: bool = String(world.teams.get(sid, "")) == player_team
	var vd: Dictionary = ShipStatus.verdict(world, sid) if own else ShipStatus.verdict_observed(world, sid)
	if vd["text"] == "" or vd["text"] == "боеспособен" or vd["text"] == "без видимых повреждений":
		return ShipNames.of(sid)
	return "%s — %s" % [ShipNames.of(sid), vd["text"]]

func _draw_brackets(p: Vector2, r: float, col: Color) -> void:
	var l: float = r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = p + Vector2(sx * r, sy * r)
			draw_line(corner, corner - Vector2(sx * l, 0), col, 1.5)
			draw_line(corner, corner - Vector2(0, sy * l), col, 1.5)

func _pick(pos: Vector2) -> Dictionary:
	# Per-ship label lines first: exact single-ship pick.
	for lh in _label_hits:
		if not lh["wreck"] and lh["rect"].has_point(pos):
			for ic in _icons:
				if ic["id"] == lh["id"]:
					var d: Dictionary = ic.duplicate()
					d["from_label"] = true
					return d
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
			if mb.pressed and mb.double_click:
				var hit: Dictionary = _pick(mb.position)
				if not hit.is_empty() and camera_focus_controller != null:
					# Double-click = fly the camera in: a single ship (or a
					# per-ship label line) -> hull close-up; a stacked
					# squadron symbol -> frame that squadron. Esc = back.
					var ids: Array = [] if hit.get("from_label", false) else _cluster_ids_at(hit["pos"], hit["own"])
					if ids.size() > 1:
						camera_focus_controller.view_ids(ids, false)
					else:
						camera_focus_controller.view_ids([hit["id"]], true)
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
	var ids: Array = [] if hit.get("from_label", false) else _cluster_ids_at(hit["pos"], true)
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
	var origin: Vector3 = RenderOrigin.to_world(camera.project_ray_origin(pos))
	var dir: Vector3 = camera.project_ray_normal(pos)
	if absf(dir.y) < 1e-6:
		return
	var t: float = (plane_y - origin.y) / dir.y
	if t <= 0.0:
		return
	move_order_controller.issue_move_order(origin + dir * t)
