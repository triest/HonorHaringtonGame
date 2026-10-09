extends Node3D
## ImpactFxDirector
##
## Rendering-only node: turns the simulation's per-tick ImpactRecord snapshots
## (SimulationWorld.last_tick_impacts, see simulation/impact_record.gd) into
## readable strike feedback. ТЗ §42: it only READS already-resolved state; it
## never writes to the world, never decides what hit or how much damage, and
## holds no reference to live simulation objects between calls.
##
## Per outcome (all from the record, never from live state):
##  - every missile rod -> a short-lived bright line ending at the ACTUAL strike
##    point (wedge surface, sidewall panel plane or hull surface -- see
##    ImpactGeometry), coloured by outcome;
##  - WEDGE_BLOCKED         -> shockwave ripple on the wedge (ShipView.add_wedge_impact);
##  - SIDEWALL_ATTENUATED   -> amber spark crackle on the struck panel
##                             (ShipView.add_sidewall_impact);
##  - HIT_UNPROTECTED       -> flash + plasma ring + sparks, a persistent scorch
##                             mark and a vent (ShipDamageFx), plus hull plating
##                             damage (ShipView.set_hull_damage);
##  - any strike            -> merged into one "x N" badge per ship
##                             (ImpactBadgeModel, drawn by ImpactBadgeOverlay).
## Beam strikes (record kind "beam") take the same route; their beam line is
## drawn by WeaponFx, which asks strike_point_render() for the true end point.
##
## An optional "impact cam" emits impact_cam_requested when the player's side is
## struck so the UI layer (CommandBar) can hold the clock near real time. The
## director never touches the clock itself.
##
## All timing uses the wall clock (ShipView.fx_clock_s): at x2000 a detonation
## lasts one sim tick, but a human needs ~1 s to read it.
class_name ImpactFxDirector

const MissileResolution = preload("res://simulation/missile_resolution.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const ImpactGeometry = preload("res://scripts/impact_geometry.gd")
const ImpactBadgeModel = preload("res://scripts/impact_badge_model.gd")

## Emitted once per update() when a ship of `player_team` was struck.
signal impact_cam_requested(hold_s: float)

@export_group("Wedge ripple")
@export_range(0.3, 4.0, 0.05) var ripple_life_s: float = 1.4
@export_range(0.05, 1.0, 0.05) var ripple_min_energy: float = 0.3
## Energy added per unit of (absorbed yield / target hull max). The default
## laserhead (400) on a 10 000 hull is 0.04, so x14 makes one missile read ~0.9.
@export_range(0.0, 60.0, 0.5) var energy_per_hull_fraction: float = 14.0
@export_range(1, 8) var max_ripples_per_ship_per_update: int = 6
## "Almost invisible until hit" wedge (Fresnel rim) instead of the bright band.
## F9 toggles at runtime.
@export var wedge_fresnel: bool = false: set = set_wedge_fresnel

@export_group("Sidewall crackle")
@export_range(0.2, 3.0, 0.05) var crackle_life_s: float = 0.9
@export_range(1, 6) var max_crackles_per_panel_per_update: int = 3

@export_group("Hull hits")
@export_range(1, 4) var max_bursts_per_ship_per_update: int = 2
## Minimum wall-clock gap between bursts on one ship (stops beams from spamming).
@export_range(0.0, 1.0, 0.01) var min_burst_interval_s: float = 0.15

@export_group("Rod lines")
@export_range(0.05, 1.5, 0.05) var rod_line_life_s: float = 0.4
@export_range(0.5, 8.0, 0.5) var rod_line_pixels: float = 2.5
@export_range(4, 48) var max_rod_lines_per_update: int = 24
@export_range(8, 96) var rod_pool_size: int = 48

@export_group("Impact cam")
@export var impact_cam_enabled: bool = true
@export_range(0.2, 5.0, 0.1) var impact_cam_hold_s: float = 1.5
## Team whose losses trigger the impact cam (set by main.gd).
@export var player_team: String = ""

## Merged "x N" badges, read by ImpactBadgeOverlay.
var badge_model: ImpactBadgeModel = ImpactBadgeModel.new()

var _views: Dictionary = {}          # ship_id -> ShipView
var _rod_pool: Array = []            # Array[Dictionary]: {node, material, t0, life, base, active}
var _rod_cursor: int = 0
var _rods_active: int = 0
var _unit_box: BoxMesh
var _last_burst_s: Dictionary = {}   # ship_id -> wall-clock of last burst

func _ready() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE
	for i in range(rod_pool_size):
		var node := MeshInstance3D.new()
		node.mesh = _unit_box
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
		add_child(node)
		_rod_pool.append({"node": node, "material": mat, "t0": 0.0, "life": 0.0, "base": Color.WHITE, "active": false})

func register_view(ship_id: String, view: ShipView) -> void:
	_views[ship_id] = view
	view.set_wedge_fresnel(wedge_fresnel)

func clear_views() -> void:
	_views.clear()
	_last_burst_s.clear()

func set_wedge_fresnel(on: bool) -> void:
	wedge_fresnel = on
	for view in _views.values():
		if is_instance_valid(view):
			view.set_wedge_fresnel(on)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F9:
		set_wedge_fresnel(not wedge_fresnel)

## Call once per simulation tick, after SimulationWorld.tick_simulation().
func update(world: SimulationWorld) -> void:
	if world.last_tick_impacts.is_empty():
		return
	var now_s: float = ShipView.fx_clock_s()
	var records: Array = world.last_tick_impacts
	var rods_per_record: int = maxi(1, max_rod_lines_per_update / records.size())
	var pending: Dictionary = {}   # ship_id -> {ripples: [], crackles: {sector: []}, bursts: []}
	var player_struck: bool = false

	for rec in records:
		var target_id: String = rec["target_ship_id"]
		var view: ShipView = _views.get(target_id)
		if view != null and not is_instance_valid(view):
			view = null
		if rec["kind"] == "missile":
			_spawn_rod_lines(rec, now_s, rods_per_record, view)
		badge_model.add(target_id, 1, rec["total_incoming"], rec["total_damage"], rec["overall_outcome"], now_s)
		if view != null:
			if float(rec["hull_max"]) > 0.0:
				view.set_hull_damage(1.0 - float(rec["hull_after"]) / float(rec["hull_max"]))
			if not pending.has(target_id):
				pending[target_id] = {"ripples": [], "crackles": {}, "bursts": []}
			_collect_effects(rec, view, pending[target_id])
		if player_team != "" and String(world.teams.get(target_id, "")) == player_team:
			player_struck = true

	for ship_id in pending.keys():
		_flush_effects(ship_id, _views[ship_id], pending[ship_id], now_s)

	if impact_cam_enabled and player_struck:
		impact_cam_requested.emit(impact_cam_hold_s)

## Where in this ship's local frame a given rod of `rec` strikes.
static func strike_local(rec: Dictionary, rod: Dictionary, dims: Dictionary) -> Vector3:
	var inverse: Quaternion = (rec["target_orientation"] as Quaternion).inverse()
	var rod_local: Vector3 = inverse * ((rod["position"] as Vector3) - (rec["target_position"] as Vector3))
	return ImpactGeometry.strike_point_local(int(rod["outcome"]), int(rod["sector"]), rod_local, dims)

## Render-space end point of a record's (first) rod: the beam renderer ends its
## beam here instead of at the target's centre.
func strike_point_render(rec: Dictionary) -> Vector3:
	var target_render: Vector3 = RenderOrigin.to_render(rec["target_position"])
	var view: ShipView = _views.get(rec["target_ship_id"])
	var rods: Array = rec["rods"]
	if view == null or not is_instance_valid(view) or view.sim_state == null or rods.is_empty():
		return target_render
	return target_render + (rec["target_orientation"] as Quaternion) * strike_local(rec, rods[0], view.ship_geometry())

## Ripple energy 0..1 for `absorbed` yield against a hull of `hull_max`.
static func ripple_energy(absorbed: float, hull_max: float, min_energy: float, per_hull_fraction: float) -> float:
	var fraction: float = absorbed / maxf(hull_max, 1.0)
	return clampf(min_energy + fraction * per_hull_fraction, min_energy, 1.0)

## Groups one record's rods by outcome into render jobs for its target ship.
func _collect_effects(rec: Dictionary, view: ShipView, job: Dictionary) -> void:
	var dims: Dictionary = view.ship_geometry()
	var hull_max: float = rec["hull_max"]
	var wedge_sum: Vector3 = Vector3.ZERO
	var wedge_incoming: float = 0.0
	var wedge_n: int = 0
	var side: Dictionary = {}   # sector -> {sum, n, incoming}
	var hull_sum: Vector3 = Vector3.ZERO
	var hull_incoming: float = 0.0
	var hull_n: int = 0
	for rod in rec["rods"]:
		var point: Vector3 = strike_local(rec, rod, dims)
		match int(rod["outcome"]):
			MissileResolution.Outcome.WEDGE_BLOCKED:
				wedge_sum += point
				wedge_incoming += rod["incoming"]
				wedge_n += 1
			MissileResolution.Outcome.SIDEWALL_ATTENUATED:
				var sector: int = int(rod["sector"])
				var entry: Dictionary = side.get(sector, {"sum": Vector3.ZERO, "n": 0, "incoming": 0.0})
				entry["sum"] += point
				entry["n"] += 1
				entry["incoming"] += rod["incoming"]
				side[sector] = entry
			MissileResolution.Outcome.HIT_UNPROTECTED:
				hull_sum += point
				hull_incoming += rod["incoming"]
				hull_n += 1
	if wedge_n > 0:
		job["ripples"].append({"center": wedge_sum / float(wedge_n), "energy": ripple_energy(wedge_incoming, hull_max, ripple_min_energy, energy_per_hull_fraction)})
	for sector in side.keys():
		var entry2: Dictionary = side[sector]
		if not job["crackles"].has(sector):
			job["crackles"][sector] = []
		job["crackles"][sector].append({"center": entry2["sum"] / float(entry2["n"]), "energy": ripple_energy(entry2["incoming"], hull_max, ripple_min_energy, energy_per_hull_fraction)})
	if hull_n > 0:
		var point2: Vector3 = ImpactGeometry.hull_surface_point_local(hull_sum / float(hull_n), dims)
		job["bursts"].append({"point": point2, "normal": ImpactGeometry.hull_normal_local(point2, dims), "strength": ripple_energy(hull_incoming, hull_max, ripple_min_energy, energy_per_hull_fraction)})

func _flush_effects(ship_id: String, view: ShipView, job: Dictionary, now_s: float) -> void:
	var ripples: Array = job["ripples"]
	ripples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["energy"] > b["energy"])
	for i in range(mini(ripples.size(), max_ripples_per_ship_per_update)):
		view.add_wedge_impact(ripples[i]["center"], ripples[i]["energy"], now_s, ripple_life_s)

	for sector in job["crackles"].keys():
		var list: Array = job["crackles"][sector]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["energy"] > b["energy"])
		for i in range(mini(list.size(), max_crackles_per_panel_per_update)):
			view.add_sidewall_impact(sector, list[i]["center"], list[i]["energy"], now_s, crackle_life_s)

	var bursts: Array = job["bursts"]
	if not bursts.is_empty() and view.damage_fx != null:
		if now_s - float(_last_burst_s.get(ship_id, -100.0)) >= min_burst_interval_s:
			_last_burst_s[ship_id] = now_s
			bursts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["strength"] > b["strength"])
			for i in range(mini(bursts.size(), max_bursts_per_ship_per_update)):
				var b: Dictionary = bursts[i]
				view.damage_fx.spawn_burst(b["point"], b["normal"], b["strength"], now_s)
				view.damage_fx.add_scorch(b["point"], b["normal"], b["strength"], now_s)
				view.damage_fx.add_vent_point(b["point"], b["normal"])

func _spawn_rod_lines(rec: Dictionary, now_s: float, budget: int, view: ShipView) -> void:
	var rods: Array = rec["rods"]
	if rods.is_empty():
		return
	var target_render: Vector3 = RenderOrigin.to_render(rec["target_position"])
	var orientation: Quaternion = rec["target_orientation"]
	var dims: Dictionary = {}
	if view != null and view.sim_state != null:
		dims = view.ship_geometry()
	var step: float = maxf(1.0, float(rods.size()) / float(budget))
	var i: float = 0.0
	while int(i) < rods.size():
		var rod: Dictionary = rods[int(i)]
		i += step
		var end: Vector3 = target_render
		if not dims.is_empty():
			end = target_render + orientation * strike_local(rec, rod, dims)
		_start_rod_line(RenderOrigin.to_render(rod["position"]), end, rod["outcome"], now_s)

func _start_rod_line(from: Vector3, to: Vector3, outcome: int, now_s: float) -> void:
	var length: float = from.distance_to(to)
	if length <= 0.001:
		return
	var entry: Dictionary = _rod_pool[_rod_cursor]
	_rod_cursor = (_rod_cursor + 1) % _rod_pool.size()
	if not entry["active"]:
		_rods_active += 1
	var dir: Vector3 = (to - from) / length
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var basis: Basis = Basis.looking_at(dir, up)
	var mid: Vector3 = (from + to) * 0.5
	var width: float = ImpactGeometry.world_size_for_pixels(get_viewport(), mid, rod_line_pixels)
	var node: MeshInstance3D = entry["node"]
	node.global_transform = Transform3D(Basis(basis.x * width, basis.y * width, basis.z * length), mid)
	node.visible = true
	entry["t0"] = now_s
	entry["life"] = rod_line_life_s
	entry["base"] = _rod_color(outcome)
	entry["active"] = true
	(entry["material"] as StandardMaterial3D).albedo_color = entry["base"]

static func _rod_color(outcome: int) -> Color:
	match outcome:
		MissileResolution.Outcome.WEDGE_BLOCKED:
			return Color(0.65, 0.88, 1.0, 0.95)
		MissileResolution.Outcome.SIDEWALL_ATTENUATED:
			return Color(0.95, 0.75, 0.15, 0.9)
		MissileResolution.Outcome.HIT_UNPROTECTED:
			return Color(1.0, 0.3, 0.15, 0.95)
		MissileResolution.Outcome.FORMATION_COVERED:
			return Color(0.6, 0.6, 0.7, 0.6)
		_:
			return Color(1.0, 1.0, 1.0, 0.7)

func _process(_delta: float) -> void:
	var now_s: float = ShipView.fx_clock_s()
	badge_model.prune(now_s)
	if _rods_active <= 0:
		return
	for entry in _rod_pool:
		if not entry["active"]:
			continue
		var k: float = (now_s - float(entry["t0"])) / maxf(float(entry["life"]), 0.001)
		if k >= 1.0:
			(entry["node"] as MeshInstance3D).visible = false
			entry["active"] = false
			_rods_active -= 1
			continue
		var color: Color = entry["base"]
		color.a *= (1.0 - k) * (1.0 - k)
		(entry["material"] as StandardMaterial3D).albedo_color = color
