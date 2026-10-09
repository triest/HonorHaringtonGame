extends Node3D
## MissileTrailFx
##
## Smooth glowing ribbon trails for every live missile, in ONE draw call
## (ТЗ §42: render-only -- it reads `world.missiles` positions/velocities and
## nothing else; it never writes simulation state).
##
## How it stays cheap with hundreds of missiles:
##  - A single MultiMeshInstance3D holds every segment of every trail;
##    missile_trail.gdshader expands each segment into a camera-facing ribbon
##    on the GPU, so no per-frame mesh building and no per-missile nodes.
##  - Trails are SIM-time history (last `trail_sim_s` seconds), so a ribbon is
##    as long as the missile really travelled, at any time scale.
##  - LOD: a trail shorter than `min_pixel_length` on screen is skipped, and at
##    most `max_trails` are drawn. At fleet range almost everything is culled.
##  - The segment buffer is rebuilt at `rebuild_hz`, not every frame.
class_name MissileTrailFx

const TRAIL_SHADER = preload("res://scripts/missile_trail.gdshader")
const MAX_SEGMENTS: int = 4096
const FLOATS_PER_INSTANCE: int = 16   # 12 transform + 4 custom data

@export_group("Trail shape")
## Sim seconds of history drawn behind a missile.
@export_range(0.5, 20.0, 0.5) var trail_sim_s: float = 4.0
## Ribbon points per trail (segments = points - 1).
@export_range(3, 16) var points_per_trail: int = 8
## Ribbon width in screen pixels at the head.
@export_range(0.5, 8.0, 0.5) var width_pixels: float = 2.5
@export_group("Budget / LOD")
@export_range(10, 800) var max_trails: int = 400
@export_range(0.0, 30.0, 0.5) var min_pixel_length: float = 3.0
@export_range(5.0, 60.0, 1.0) var rebuild_hz: float = 30.0

var _world: SimulationWorld
var _history: Dictionary = {}     # missile_id -> {pts: PackedVector3Array, times: PackedFloat64Array}
var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _since_rebuild_s: float = 0.0
var _sample_clock: float = 0.0

func _ready() -> void:
	_buffer.resize(MAX_SEGMENTS * FLOATS_PER_INSTANCE)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = _build_quad()
	_multimesh.instance_count = MAX_SEGMENTS
	_multimesh.visible_instance_count = 0
	_material = ShaderMaterial.new()
	_material.shader = TRAIL_SHADER
	_instance = MultiMeshInstance3D.new()
	_instance.multimesh = _multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Geometry lives in instance data, so the node's own AABB is meaningless:
	# never frustum-cull the whole batch.
	_instance.custom_aabb = AABB(Vector3(-1.0e11, -1.0e11, -1.0e11), Vector3(2.0e11, 2.0e11, 2.0e11))
	add_child(_instance)

## Unit quad: x in [-0.5, 0.5] along the segment, y in [-0.5, 0.5] across.
static func _build_quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0), Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func bind(world: SimulationWorld) -> void:
	_world = world

func _process(delta: float) -> void:
	if _world == null:
		return
	_sample_history()
	_since_rebuild_s += delta
	if _since_rebuild_s < 1.0 / rebuild_hz:
		return
	_since_rebuild_s = 0.0
	_rebuild()

## Appends the current position of every live missile to its history (at most
## about 10 samples per `trail_sim_s`) and forgets missiles that are gone.
func _sample_history() -> void:
	var now: float = _world.world_sim_time
	var interval: float = trail_sim_s / float(maxi(points_per_trail, 2) + 2)
	var live: Dictionary = {}
	for missile_id in _world.missiles.keys():
		var missile = _world.missiles[missile_id]
		if not missile.is_active():
			continue
		live[missile_id] = true
		var h: Dictionary = _history.get(missile_id, {})
		if h.is_empty():
			h = {"pts": PackedVector3Array(), "times": PackedFloat64Array()}
			_history[missile_id] = h
		# PackedArrays come back from a Dictionary by value: edit locals, write back.
		var pts: PackedVector3Array = h["pts"]
		var times: PackedFloat64Array = h["times"]
		if times.is_empty() or now - times[times.size() - 1] >= interval:
			pts.append(missile.position)
			times.append(now)
			# Drop samples older than the trail window (keep one older anchor).
			while times.size() > 2 and now - times[1] > trail_sim_s:
				pts.remove_at(0)
				times.remove_at(0)
			h["pts"] = pts
			h["times"] = times
	for missile_id in _history.keys():
		if not live.has(missile_id):
			_history.erase(missile_id)

func _rebuild() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		_multimesh.visible_instance_count = 0
		return
	var cam_pos: Vector3 = cam.global_position
	var vp_h: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var px_k: float = 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / vp_h
	_material.set_shader_parameter("px_k", px_k)

	var now: float = _world.world_sim_time
	var segments: int = 0
	var trails: int = 0
	var points: PackedVector3Array = PackedVector3Array()
	for missile_id in _history.keys():
		if trails >= max_trails or segments + points_per_trail > MAX_SEGMENTS:
			break
		var missile = _world.missiles.get(missile_id)
		if missile == null:
			continue
		var head_render: Vector3 = RenderOrigin.to_render(missile.position)
		points = _trail_points(_history[missile_id], missile, now)
		if points.size() < 2:
			continue
		# LOD: projected trail length in pixels.
		var tail_render: Vector3 = RenderOrigin.to_render(points[points.size() - 1])
		var dist: float = maxf(cam_pos.distance_to(head_render), 1.0)
		var pixels: float = head_render.distance_to(tail_render) / (dist * px_k)
		if pixels < min_pixel_length:
			continue
		trails += 1
		var kind: float = 1.0 if _world.counter_missile_ids.has(missile_id) else 0.0
		var last_index: float = float(points.size() - 1)
		var prev: Vector3 = head_render
		for i in range(1, points.size()):
			var cur: Vector3 = RenderOrigin.to_render(points[i])
			var d: Vector3 = cur - prev
			var o: int = segments * FLOATS_PER_INSTANCE
			# Row-major 3x4: basis.x = D, basis.y = basis.z = 0, origin = A.
			_buffer[o] = d.x; _buffer[o + 1] = 0.0; _buffer[o + 2] = 0.0; _buffer[o + 3] = prev.x
			_buffer[o + 4] = d.y; _buffer[o + 5] = 0.0; _buffer[o + 6] = 0.0; _buffer[o + 7] = prev.y
			_buffer[o + 8] = d.z; _buffer[o + 9] = 0.0; _buffer[o + 10] = 0.0; _buffer[o + 11] = prev.z
			_buffer[o + 12] = width_pixels
			_buffer[o + 13] = float(i - 1) / last_index
			_buffer[o + 14] = float(i) / last_index
			_buffer[o + 15] = kind
			prev = cur
			segments += 1
	_multimesh.visible_instance_count = segments
	if segments > 0:
		_multimesh.buffer = _buffer

## Newest-first polyline for one missile: live head, then recorded samples no
## older than `trail_sim_s` (the last kept span is interpolated to the exact
## cut-off, so the trail length is independent of the time scale). A missile
## with no usable history gets a straight tail along -velocity.
func _trail_points(h: Dictionary, missile, now: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(missile.position)
	var pts: PackedVector3Array = h["pts"]
	var times: PackedFloat64Array = h["times"]
	var previous: Vector3 = missile.position
	var previous_t: float = now
	for i in range(pts.size() - 1, -1, -1):
		if out.size() >= points_per_trail:
			break
		var t: float = times[i]
		if now - t > trail_sim_s:
			var span: float = previous_t - t
			if span > 0.0:
				var f: float = clampf((previous_t - (now - trail_sim_s)) / span, 0.0, 1.0)
				out.append(previous.lerp(pts[i], f))
			break
		out.append(pts[i])
		previous = pts[i]
		previous_t = t
	if out.size() < 2:
		out.append(missile.position - missile.velocity * trail_sim_s * 0.3)
	return out
