extends Node3D
## ShipDamageFx
##
## Rendering-only child of a ShipView (ТЗ §42): everything it shows comes from
## ImpactRecord snapshots routed in by ImpactFxDirector, never from live
## simulation objects. Three jobs for HIT_UNPROTECTED strikes:
##   1. BURST   -- a bright flash plus spark/debris particles at the strike.
##   2. SCORCH  -- a persistent burn mark on the hull (ragged soot disc with a
##                 cooling ember core, hull_scorch.gdshader); newest N kept.
##   3. VENTING -- up to two vents at the most recent strike points leak gas and
##                 smoke; emission scales with the hull fraction LOST so a
##                 battered ship visibly bleeds while a scratched one barely does.
## All timing is wall-clock (ShipView.fx_clock_s). Sizes scale with ship length
## and are floored to a few screen pixels so effects stay visible at distance.
## Pools are pre-allocated in setup(): no per-hit node/material allocation
## except the (capped) scorch mark materials.
class_name ShipDamageFx

const SCORCH_SHADER = preload("res://scripts/hull_scorch.gdshader")
const ImpactGeometry = preload("res://scripts/impact_geometry.gd")

const MAX_SCORCH: int = 12
const MAX_BURSTS: int = 4
const MAX_VENTS: int = 2
const FLASH_LIFE_S: float = 0.3
const RING_LIFE_S: float = 0.9
const BURST_LIFE_S: float = 1.6
const EMBER_LIFE_S: float = 14.0
## Hull fraction lost below which a ship does not vent at all.
const VENT_MIN_FRACTION: float = 0.04
## Hull fraction lost at which venting reaches full strength.
const VENT_FULL_FRACTION: float = 0.6

static var _soft_texture: GradientTexture2D
static var _ring_texture: GradientTexture2D

var _length_m: float = 500.0
var _min_px: float = 4.0
var _bursts: Array = []     # Array[Dictionary]: {particles, material, flash, flash_mat, t0, active}
var _burst_cursor: int = 0
var _scorches: Array = []   # Array[Dictionary]: {node, material, t0}
var _scorch_cursor: int = 0
var _scorch_serial: int = 0
var _vents: Array = []      # Array[Dictionary]: {gas, gas_mat, smoke, smoke_mat, placed}
var _vent_cursor: int = 0
var _damage_fraction: float = 0.0
var _size_refresh_s: float = 0.0
var _flashes_active: int = 0

static func soft_texture() -> GradientTexture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_soft_texture = GradientTexture2D.new()
		_soft_texture.gradient = gradient
		_soft_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_texture.fill_from = Vector2(0.5, 0.5)
		_soft_texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture.width = 64
		_soft_texture.height = 64
	return _soft_texture

## Hollow ring profile for the expanding plasma ring (transparent core, bright
## band at ~0.7 of the radius, transparent rim).
static func ring_texture() -> GradientTexture2D:
	if _ring_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 0.72, 0.9, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0)])
		_ring_texture = GradientTexture2D.new()
		_ring_texture.gradient = gradient
		_ring_texture.fill = GradientTexture2D.FILL_RADIAL
		_ring_texture.fill_from = Vector2(0.5, 0.5)
		_ring_texture.fill_to = Vector2(1.0, 0.5)
		_ring_texture.width = 128
		_ring_texture.height = 128
	return _ring_texture

func setup(length_m: float) -> void:
	_length_m = maxf(length_m, 1.0)
	for i in range(MAX_BURSTS):
		_bursts.append(_make_burst())
	for i in range(MAX_VENTS):
		_vents.append(_make_vent())

## Strike on the bare hull. `strength` 0..1 (yield vs hull size).
func spawn_burst(local_point: Vector3, normal: Vector3, strength: float, now_s: float) -> void:
	if _bursts.is_empty():
		return
	var entry: Dictionary = _bursts[_burst_cursor]
	_burst_cursor = (_burst_cursor + 1) % _bursts.size()
	strength = clampf(strength, 0.1, 1.0)
	var particles: GPUParticles3D = entry["particles"]
	var material: ParticleProcessMaterial = entry["material"]
	particles.position = local_point
	material.direction = normal
	material.initial_velocity_min = _length_m * 0.12 * (0.5 + strength)
	material.initial_velocity_max = _length_m * 0.55 * (0.5 + strength)
	entry["strength"] = strength
	_apply_burst_size(entry)
	particles.restart()
	particles.emitting = true

	var flash: MeshInstance3D = entry["flash"]
	flash.position = local_point + normal * (_length_m * 0.01)
	flash.visible = true
	var ring: MeshInstance3D = entry["ring"]
	ring.position = flash.position
	ring.visible = true
	entry["t0"] = now_s
	if not entry["active"]:
		_flashes_active += 1
	entry["active"] = true
	_apply_flash(entry, 0.0)

## Persistent burn mark; the oldest of MAX_SCORCH is recycled.
func add_scorch(local_point: Vector3, normal: Vector3, strength: float, now_s: float) -> void:
	strength = clampf(strength, 0.1, 1.0)
	var entry: Dictionary
	if _scorches.size() < MAX_SCORCH:
		var node := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		node.mesh = quad
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = SCORCH_SHADER
		mat.set_shader_parameter("ember_life", EMBER_LIFE_S)
		node.material_override = mat
		add_child(node)
		entry = {"node": node, "material": mat, "t0": 0.0}
		_scorches.append(entry)
	else:
		entry = _scorches[_scorch_cursor]
		_scorch_cursor = (_scorch_cursor + 1) % MAX_SCORCH
	_scorch_serial += 1
	var radius: float = _length_m * (0.025 + 0.06 * strength)
	var z_axis: Vector3 = normal.normalized()
	var ref: Vector3 = Vector3.UP if absf(z_axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis)
	var node2: MeshInstance3D = entry["node"]
	node2.transform = Transform3D(Basis(x_axis * radius * 2.0, y_axis * radius * 2.0, z_axis), local_point + z_axis * (_length_m * 0.002))
	var mat2: ShaderMaterial = entry["material"]
	mat2.set_shader_parameter("start_time", now_s)
	mat2.set_shader_parameter("fx_time", now_s)
	mat2.set_shader_parameter("seed", float(_scorch_serial))
	mat2.set_shader_parameter("strength", strength)
	entry["t0"] = now_s

## Moves a vent (alternating between the two) to a fresh strike point.
func add_vent_point(local_point: Vector3, normal: Vector3) -> void:
	if _vents.is_empty():
		return
	var vent: Dictionary = _vents[_vent_cursor]
	_vent_cursor = (_vent_cursor + 1) % _vents.size()
	for key in ["gas", "smoke"]:
		var particles: GPUParticles3D = vent[key]
		particles.position = local_point
		(vent[key + "_mat"] as ParticleProcessMaterial).direction = normal
	vent["placed"] = true
	_apply_vent_rates()

## Cumulative hull fraction lost (0..1), from ImpactRecord hull_after/hull_max.
func set_damage_fraction(fraction: float) -> void:
	_damage_fraction = clampf(fraction, 0.0, 1.0)
	_apply_vent_rates()

func damage_fraction() -> float:
	return _damage_fraction

## 0..1 vent intensity for a hull fraction lost (pure, testable).
static func vent_intensity(fraction_lost: float) -> float:
	if fraction_lost < VENT_MIN_FRACTION:
		return 0.0
	return clampf((fraction_lost - VENT_MIN_FRACTION) / (VENT_FULL_FRACTION - VENT_MIN_FRACTION), 0.12, 1.0)

func _apply_vent_rates() -> void:
	var intensity: float = vent_intensity(_damage_fraction)
	for vent in _vents:
		var on: bool = vent["placed"] and intensity > 0.0
		var gas: GPUParticles3D = vent["gas"]
		var smoke: GPUParticles3D = vent["smoke"]
		gas.emitting = on
		smoke.emitting = on
		gas.amount_ratio = clampf(intensity, 0.05, 1.0)
		smoke.amount_ratio = clampf(intensity * 1.0, 0.05, 1.0)
		_apply_vent_size(vent, intensity)

func _make_burst() -> Dictionary:
	var particles := GPUParticles3D.new()
	particles.amount = 40
	particles.lifetime = BURST_LIFE_S
	particles.one_shot = true
	particles.explosiveness = 0.96
	particles.emitting = false
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1.0e7, -1.0e7, -1.0e7), Vector3(2.0e7, 2.0e7, 2.0e7))
	var material := ParticleProcessMaterial.new()
	material.spread = 70.0
	material.gravity = Vector3.ZERO
	material.damping_min = 0.2
	material.damping_max = 0.6
	material.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.25, Color(1.0, 0.5, 0.12, 0.9)], [1.0, Color(0.3, 0.05, 0.0, 0.0)]])
	particles.process_material = material
	particles.draw_pass_1 = _billboard_quad(true)
	add_child(particles)

	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	flash.mesh = quad
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.albedo_texture = soft_texture()
	flash_mat.albedo_color = Color(1.0, 0.9, 0.65, 1.0)
	flash_mat.no_depth_test = true
	flash.material_override = flash_mat
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)

	# Expanding plasma ring: a billboarded hollow ring that grows and fades.
	var ring := MeshInstance3D.new()
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2.ONE
	ring.mesh = ring_quad
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ring_mat.albedo_texture = ring_texture()
	ring_mat.albedo_color = Color(1.0, 0.55, 0.2, 1.0)
	ring_mat.no_depth_test = true
	ring.material_override = ring_mat
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	return {"particles": particles, "material": material, "flash": flash, "flash_mat": flash_mat, "ring": ring, "ring_mat": ring_mat, "t0": 0.0, "active": false, "strength": 0.5}

func _make_vent() -> Dictionary:
	var gas := _make_vent_system(24, 1.8, Color(0.85, 0.95, 1.0, 0.0), true)
	var smoke := _make_vent_system(24, 3.2, Color(0.12, 0.11, 0.1, 0.0), false)
	return {"gas": gas[0], "gas_mat": gas[1], "smoke": smoke[0], "smoke_mat": smoke[1], "placed": false}

func _make_vent_system(amount: int, life_s: float, tint: Color, additive: bool) -> Array:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = life_s
	particles.emitting = false
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1.0e7, -1.0e7, -1.0e7), Vector3(2.0e7, 2.0e7, 2.0e7))
	var material := ParticleProcessMaterial.new()
	material.spread = 28.0 if additive else 40.0
	material.gravity = Vector3.ZERO
	material.initial_velocity_min = _length_m * (0.10 if additive else 0.03)
	material.initial_velocity_max = _length_m * (0.30 if additive else 0.09)
	material.damping_min = 0.1
	material.damping_max = 0.3
	var peak: float = 0.55 if additive else 0.5
	material.color_ramp = _ramp([[0.0, Color(tint.r, tint.g, tint.b, 0.0)], [0.15, Color(tint.r, tint.g, tint.b, peak)], [1.0, Color(tint.r, tint.g, tint.b, 0.0)]])
	particles.process_material = material
	particles.draw_pass_1 = _billboard_quad(additive)
	add_child(particles)
	return [particles, material]

func _billboard_quad(additive: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	return quad

static func _ramp(stops: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1])
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

func _world_px(world_local: Vector3, pixels: float) -> float:
	return ImpactGeometry.world_size_for_pixels(get_viewport(), to_global(world_local), pixels, 0.0)

func _apply_burst_size(entry: Dictionary) -> void:
	var particles: GPUParticles3D = entry["particles"]
	var material: ParticleProcessMaterial = entry["material"]
	var strength: float = entry["strength"]
	var base: float = _length_m * 0.012 * (0.6 + strength)
	var floor_size: float = _world_px(particles.position, _min_px)
	material.scale_min = maxf(base * 0.6, floor_size)
	material.scale_max = maxf(base * 1.6, floor_size * 1.8)

func _apply_vent_size(vent: Dictionary, intensity: float) -> void:
	var gas: GPUParticles3D = vent["gas"]
	var smoke: GPUParticles3D = vent["smoke"]
	var gas_floor: float = _world_px(gas.position, _min_px)
	var smoke_floor: float = _world_px(smoke.position, _min_px * 1.5)
	(vent["gas_mat"] as ParticleProcessMaterial).scale_min = maxf(_length_m * 0.015 * (0.5 + intensity), gas_floor)
	(vent["gas_mat"] as ParticleProcessMaterial).scale_max = maxf(_length_m * 0.04 * (0.5 + intensity), gas_floor * 1.6)
	(vent["smoke_mat"] as ParticleProcessMaterial).scale_min = maxf(_length_m * 0.04 * (0.5 + intensity), smoke_floor)
	(vent["smoke_mat"] as ParticleProcessMaterial).scale_max = maxf(_length_m * 0.11 * (0.5 + intensity), smoke_floor * 1.6)

func _apply_flash(entry: Dictionary, k: float) -> void:
	var flash: MeshInstance3D = entry["flash"]
	var strength: float = entry["strength"]
	var size: float = maxf(_length_m * (0.12 + 0.3 * strength) * (0.6 + 0.8 * k), _world_px(flash.position, _min_px * 3.0))
	flash.scale = Vector3(size, size, size)
	var mat: StandardMaterial3D = entry["flash_mat"]
	var c: Color = mat.albedo_color
	c.a = (1.0 - k) * (1.0 - k)
	mat.albedo_color = c
	# Plasma ring outlives the flash: it expands over the full burst window.
	var ring: MeshInstance3D = entry["ring"]
	var rk: float = clampf(k * FLASH_LIFE_S / RING_LIFE_S, 0.0, 1.0)
	var ring_size: float = maxf(_length_m * (0.15 + 0.7 * strength) * (0.2 + 1.2 * rk), _world_px(ring.position, _min_px * 4.0))
	ring.scale = Vector3(ring_size, ring_size, ring_size)
	var rmat: StandardMaterial3D = entry["ring_mat"]
	var rc: Color = rmat.albedo_color
	rc.a = (1.0 - rk) * (1.0 - rk) * 0.9
	rmat.albedo_color = rc

func _process(delta: float) -> void:
	var now_s: float = ShipView.fx_clock_s()
	if _flashes_active > 0:
		for entry in _bursts:
			if not entry["active"]:
				continue
			var k: float = (now_s - float(entry["t0"])) / RING_LIFE_S
			if k >= 1.0:
				(entry["flash"] as MeshInstance3D).visible = false
				(entry["ring"] as MeshInstance3D).visible = false
				entry["active"] = false
				_flashes_active -= 1
			else:
				_apply_flash(entry, k)
	for scorch in _scorches:
		if now_s - float(scorch["t0"]) < EMBER_LIFE_S + 0.5:
			(scorch["material"] as ShaderMaterial).set_shader_parameter("fx_time", now_s)
	# Screen-size floors depend on camera distance: refresh a few times a second.
	_size_refresh_s += delta
	if _size_refresh_s >= 0.25:
		_size_refresh_s = 0.0
		var intensity: float = vent_intensity(_damage_fraction)
		for vent in _vents:
			if vent["placed"] and intensity > 0.0:
				_apply_vent_size(vent, intensity)
