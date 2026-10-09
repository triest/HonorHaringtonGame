extends Node
## CameraFxController
##
## Contextual screen shake and a faint organic drift for the OrbitCamera
## (ТЗ §42: render-only; it reads ImpactRecord snapshots and missile positions
## and never writes simulation state). It does NOT move the camera: it adds
## Camera3D.h_offset / v_offset (frustum shift) plus a tiny fov punch, so the
## OrbitCamera's own transform, floating origin and flights are untouched.
##
## Trauma model (the usual "squared trauma" shake): events add trauma 0..1, it
## decays linearly with WALL-CLOCK time, shake = trauma^2 * smooth noise. All
## offsets scale with the camera's distance so a strike looks the same whether
## you are 2 km or 2 million km out. Shake is attenuated for strikes far from
## where the camera is looking.
class_name CameraFxController

const MR = preload("res://simulation/missile_resolution.gd")

@export_group("Shake")
@export var shake_enabled: bool = true
## Peak frustum shift as a fraction of camera distance at trauma 1.
@export_range(0.0, 0.2, 0.001) var max_offset_fraction: float = 0.03
## Peak fov punch (degrees) at trauma 1.
@export_range(0.0, 10.0, 0.1) var max_fov_punch_deg: float = 1.5
@export_range(0.2, 6.0, 0.1) var decay_per_second: float = 1.4
@export_range(1.0, 40.0, 0.5) var shake_frequency: float = 18.0
@export_group("Trauma per event")
## Trauma added per unit of (yield / target hull max) for a bare-hull hit.
@export_range(0.0, 80.0, 0.5) var hull_hit_gain: float = 30.0
@export_range(0.0, 2.0, 0.05) var wedge_hit_trauma: float = 0.12
@export_range(0.0, 2.0, 0.05) var sidewall_hit_trauma: float = 0.2
@export_range(1.0, 3.0, 0.1) var flagship_multiplier: float = 1.8
@export_range(0.0, 1.0, 0.01) var pass_by_trauma_per_s: float = 0.35
@export_group("Drift")
@export var drift_enabled: bool = true
@export_range(0.0, 0.01, 0.0001) var drift_fraction: float = 0.0015
@export_range(0.01, 1.0, 0.01) var drift_speed: float = 0.07

var camera: Camera3D
var world: SimulationWorld
## Ship whose hits shake harder (set by main.gd: the player's biggest hull).
var flagship_id: String = ""
var player_team: String = ""

var _trauma: float = 0.0
var _noise: FastNoiseLite
var _base_fov: float = -1.0
var _last_applied_fov_punch: float = 0.0

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1337

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func trauma() -> float:
	return _trauma

## Trauma for one impact record (pure, testable): yield-proportional on bare
## hull, flat for wedge/sidewall absorption, boosted for the flagship and
## attenuated with angular distance from the camera's look point.
static func trauma_for_record(rec: Dictionary, is_flagship: bool, hull_gain: float, wedge_t: float, sidewall_t: float, flagship_mult: float, attenuation: float) -> float:
	var hull_max: float = maxf(float(rec["hull_max"]), 1.0)
	# Bare-hull damage is yield-proportional; absorbed strikes add a flat rumble.
	var t: float = float(rec["total_damage"]) / hull_max * hull_gain
	t += _absorption_trauma(rec, wedge_t, sidewall_t)
	if is_flagship:
		t *= flagship_mult
	return clampf(t * attenuation, 0.0, 1.0)

static func _absorption_trauma(rec: Dictionary, wedge_t: float, sidewall_t: float) -> float:
	var t: float = 0.0
	var rods: Array = rec["rods"]
	if rods.is_empty():
		return 0.0
	var share: float = 1.0 / float(rods.size())
	for rod in rods:
		match int(rod["outcome"]):
			MR.Outcome.WEDGE_BLOCKED:
				t += wedge_t * share
			MR.Outcome.SIDEWALL_ATTENUATED:
				t += sidewall_t * share
	return t

## Attenuation 1.0 at the camera's look point falling to 0.2 at 3 camera
## distances away.
static func attenuation_for(strike_to_look_m: float, camera_distance_m: float) -> float:
	return clampf(1.0 - strike_to_look_m / maxf(camera_distance_m * 3.0, 1.0), 0.2, 1.0)

## Called once per sim tick with the same world main.gd owns.
func update(sim_world: SimulationWorld) -> void:
	if not shake_enabled or camera == null or sim_world.last_tick_impacts.is_empty():
		return
	var look: Vector3 = RenderOrigin.to_world(Vector3.ZERO)
	if camera.has_method("look_point"):
		look = camera.call("look_point")
	var cam_distance: float = camera.global_position.length()
	for rec in sim_world.last_tick_impacts:
		var target_id: String = rec["target_ship_id"]
		# Only strikes on the player's side shake the camera (the enemy being hit
		# is a pleasure, not a jolt) -- but those still get a milder rumble.
		var own: bool = player_team == "" or String(sim_world.teams.get(target_id, "")) == player_team
		var att: float = attenuation_for((rec["target_position"] as Vector3).distance_to(look), cam_distance)
		var t: float = trauma_for_record(rec, target_id == flagship_id, hull_hit_gain, wedge_hit_trauma, sidewall_hit_trauma, flagship_multiplier, att)
		add_trauma(t if own else t * 0.4)

## Close-quarters missile passes: any missile within 15% of the camera distance
## of the look point adds a little trauma while it screams past. Call once per
## rendered frame (cheap: one distance test per live missile).
func update_pass_bys(sim_world: SimulationWorld, delta: float) -> void:
	if not shake_enabled or camera == null or pass_by_trauma_per_s <= 0.0:
		return
	var look: Vector3 = RenderOrigin.to_world(Vector3.ZERO)
	if camera.has_method("look_point"):
		look = camera.call("look_point")
	var radius: float = maxf(camera.global_position.length() * 0.15, 1.0)
	var close: int = 0
	for missile_id in sim_world.missiles.keys():
		var missile = sim_world.missiles[missile_id]
		if missile.is_active() and (missile.position as Vector3).distance_to(look) < radius:
			close += 1
			if close >= 6:
				break
	if close > 0:
		add_trauma(pass_by_trauma_per_s * delta * minf(float(close), 3.0) / 3.0)

func _process(delta: float) -> void:
	if camera == null:
		return
	if _base_fov < 0.0:
		_base_fov = camera.fov
	# Undo last frame's fov punch before anything else changes fov.
	camera.fov -= _last_applied_fov_punch
	_last_applied_fov_punch = 0.0

	var t: float = Time.get_ticks_msec() * 0.001
	var dist: float = maxf(camera.global_position.length(), 1.0)
	var h: float = 0.0
	var v: float = 0.0
	if drift_enabled:
		h += _noise.get_noise_2d(t * drift_speed, 11.0) * drift_fraction * dist
		v += _noise.get_noise_2d(t * drift_speed, 57.0) * drift_fraction * dist
	if _trauma > 0.0:
		var shake: float = _trauma * _trauma
		h += _noise.get_noise_2d(t * shake_frequency, 0.0) * shake * max_offset_fraction * dist
		v += _noise.get_noise_2d(t * shake_frequency, 100.0) * shake * max_offset_fraction * dist
		_last_applied_fov_punch = _noise.get_noise_2d(t * shake_frequency, 200.0) * shake * max_fov_punch_deg
		camera.fov += _last_applied_fov_punch
		_trauma = maxf(_trauma - decay_per_second * delta, 0.0)
	camera.h_offset = h
	camera.v_offset = v
