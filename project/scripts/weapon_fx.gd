extends Node3D
## WeaponFx
##
## Rendering-only node (ТЗ §56.1 item 3: "Simple, non-polished
## visualization of weapon fire ... purely so a player can SEE combat
## happening. Per §42, rendering only displays already-resolved
## simulation state -- it must not invent its own hit/damage logic").
##
## Two independent responsibilities, both pure readouts of existing
## SimulationWorld state:
##
## - Energy-weapon beams: each call to update() spawns one short-lived
##   beam effect per entry in SimulationWorld.last_tick_weapon_shots (a
##   transient per-tick list the simulation already populates in
##   fire_weapon() -- see simulation_world.gd). Colour communicates the
##   ALREADY-COMPUTED outcome (penetrated / wedge-blocked / sidewall-
##   attenuated / formation-covered); this node does not decide which of
##   those happened, only how to draw it.
## - Missile markers: a small marker mesh per LIVE entry in
##   SimulationWorld.missiles, created/repositioned/removed by diffing
##   against that dictionary every update() -- missiles are ongoing
##   simulation entities (ТЗ §18), not one-tick events, so unlike beams
##   they are synced continuously rather than spawned from an event list.
class_name WeaponFx

const BeamFxMeshBuilder = preload("res://scripts/beam_fx_mesh_builder.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")

## Placeholder visual thickness for a beam, in meters -- purely a
## legibility choice (demo ships/ranges are on the order of thousands to
## hundreds of thousands of meters), not a canon beam-width citation
## (ASSUMPTIONS.md, same placeholder status as every mesh builder here).
const BEAM_WIDTH_M: float = 60.0
## How long a beam stays visible after firing, in seconds. Energy weapons
## resolve instantly in the simulation (one tick); this is purely a
## render-side "muzzle flash" duration so the shot is visible to a human
## eye at 60 sim ticks/sec, not a simulation timing value.
const BEAM_LIFETIME_S: float = 0.18

## Placeholder missile marker radius, in meters -- same "illustrative,
## not canon" status as BEAM_WIDTH_M above.
const MISSILE_MARKER_RADIUS_M: float = 25.0

var _active_beams: Array = []  # Array[Dictionary]: {node: MeshInstance3D, material: StandardMaterial3D, base_alpha: float, remaining: float}
var _missile_markers: Dictionary = {}  # missile_id -> MeshInstance3D
var _missile_marker_mesh: SphereMesh
var _missile_marker_material: StandardMaterial3D

func _ready() -> void:
	_missile_marker_mesh = SphereMesh.new()
	_missile_marker_mesh.radius = MISSILE_MARKER_RADIUS_M
	_missile_marker_mesh.height = MISSILE_MARKER_RADIUS_M * 2.0

	_missile_marker_material = StandardMaterial3D.new()
	_missile_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_missile_marker_material.albedo_color = Color(1.0, 0.85, 0.2)  # bright yellow -- distinct from beam/wedge/sidewall colours

## Call once per simulation tick (after SimulationWorld.tick_simulation()
## has already run for that tick -- main.gd's connection order guarantees
## this, see main.gd doc comment) with the same `world` main.gd owns.
func update(world: SimulationWorld) -> void:
	for shot in world.last_tick_weapon_shots:
		_spawn_beam(shot["attacker_position"], shot["target_position"], shot["outcome"])
	_sync_missile_markers(world)

func _spawn_beam(from: Vector3, to: Vector3, outcome: int) -> void:
	var length: float = from.distance_to(to)
	if length <= 0.001:
		return  # degenerate (attacker == target position) -- nothing to draw

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BeamFxMeshBuilder.build(length, BEAM_WIDTH_M)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var color: Color = _beam_color(outcome)
	material.albedo_color = color
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.global_position = from
	# look_at requires a direction != Vector3.ZERO and not parallel to `up`;
	# fall back to a fixed up vector if attacker/target happen to be
	# stacked directly along world Y (degenerate for this placeholder
	# effect, not worth failing the shot over).
	var up: Vector3 = Vector3.UP
	if abs((to - from).normalized().dot(up)) > 0.999:
		up = Vector3.RIGHT
	mesh_instance.look_at(to, up)

	_active_beams.append({
		"node": mesh_instance,
		"material": material,
		"base_alpha": color.a,
		"remaining": BEAM_LIFETIME_S,
	})

## Colour communicates the outcome WeaponResolution already computed --
## this function only maps that already-resolved fact to a colour, it
## does not itself judge whether the shot penetrated (§42).
static func _beam_color(outcome: int) -> Color:
	match outcome:
		WeaponResolution.Outcome.HIT_UNPROTECTED:
			return Color(1.0, 0.25, 0.15, 0.9)  # penetrated -- hot red/orange
		WeaponResolution.Outcome.WEDGE_BLOCKED:
			return Color(0.4, 0.7, 1.0, 0.6)  # blocked by wedge -- cool blue, dimmer
		WeaponResolution.Outcome.SIDEWALL_ATTENUATED:
			return Color(0.95, 0.75, 0.15, 0.75)  # attenuated by sidewall -- amber, matches ShipView's sidewall colour
		WeaponResolution.Outcome.FORMATION_COVERED:
			return Color(0.6, 0.6, 0.65, 0.5)  # covered by a formation-mate -- dim grey
		_:
			return Color(1.0, 1.0, 1.0, 0.7)  # unrecognized outcome -- neutral white rather than silently guessing

func _sync_missile_markers(world: SimulationWorld) -> void:
	var live_ids: Dictionary = {}
	for missile_id in world.missiles.keys():
		live_ids[missile_id] = true
		var missile = world.missiles[missile_id]
		var marker: MeshInstance3D = _missile_markers.get(missile_id)
		if marker == null:
			marker = MeshInstance3D.new()
			marker.mesh = _missile_marker_mesh
			marker.material_override = _missile_marker_material
			add_child(marker)
			_missile_markers[missile_id] = marker
		marker.global_position = missile.position

	for missile_id in _missile_markers.keys().duplicate():
		if not live_ids.has(missile_id):
			_missile_markers[missile_id].queue_free()
			_missile_markers.erase(missile_id)

func _process(delta: float) -> void:
	var i: int = _active_beams.size() - 1
	while i >= 0:
		var entry: Dictionary = _active_beams[i]
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			entry["node"].queue_free()
			_active_beams.remove_at(i)
		else:
			var fraction: float = clampf(entry["remaining"] / BEAM_LIFETIME_S, 0.0, 1.0)
			var mat: StandardMaterial3D = entry["material"]
			var color: Color = mat.albedo_color
			color.a = entry["base_alpha"] * fraction
			mat.albedo_color = color
		i -= 1
