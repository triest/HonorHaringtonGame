extends Node3D
## ShipView
##
## Rendering-only node. Reads a ShipPhysicsState (and its optional
## ShipDefenseState) each frame and updates the visual transform + hull
## mesh + wedge/sidewall visualization. Must NEVER write back into
## simulation state or make combat/physics decisions (ТЗ §42).
##
## Hull mesh: a procedural "flattened spindle" placeholder built from the
## CANON silhouette description (see scripts/hull_mesh_builder.gd), sized
## from the bound ShipPhysicsState's length_m/max_width_m/max_height_m.
##
## Wedge visualization: two translucent planes above/below the hull,
## shown only while sim_state.defense.wedge_up is true -- a direct visual
## readout of the already-implemented wedge logic (ship_defense_state.gd),
## not a separate source of truth.
##
## Sidewall visualization (ТЗ §16, §56.1 item 2): four translucent panels
## -- port/starboard (broadside) and bow/stern -- each independently
## visible per ship_defense_state.gd's own condition/raised fields, NOT a
## single shared flag. Broadside sidewalls show whenever their condition
## is above burnout (no "raised" concept for those, per ship_defense_
## state.gd); bow/stern panels show only while explicitly raised (raising
## them costs impeller acceleration, CONFIRMED CANON) AND above burnout.
## Visibility decisions are pure static functions below so they are
## unit-testable without a scene tree (see
## simulation/tests/test_ship_view_sidewalls.gd), mirroring
## WedgeMeshBuilder._width_profile's testable-pure-helper pattern.
##
## 2026-09-28 (user: "модели кораблей и импеллеров то улучши, а то совсем
## черновик"): three additions on top of the existing geometry, none of
## which change what the hull/wedge/sidewalls represent -- purely making
## them read as more than flat placeholder primitives:
##   1. Hull/wedge materials pick up the vertex colours HullMeshBuilder/
##      WedgeMeshBuilder now bake in (vertex_color_use_as_albedo), plus a
##      cheap rim/fresnel highlight on the hull -- low-poly procedural
##      meshes read far better with SOME edge lighting than none. The
##      wedge additionally blends additively now (a glowing energy band
##      over black space, instead of a flat alpha card).
##   2. A handful of small static "greeble" meshes (bridge/sensor mast,
##      flank blisters) so the hull silhouette isn't perfectly smooth --
##      explicitly illustrative placement (ASSUMPTIONS.md), not derived
##      from this ship's actual weapon-mount count/positions.
##   3. A visible impeller-ring glow at the bow/stern flare positions
##      (CANON_RULES.md: "impeller rings (degrading max acceleration)" is
##      an existing, real damage-model component -- see
##      simulation_world.gd's PROPULSION subsystem) -- colour/brightness
##      driven by the ship's own PROPULSION condition each frame, so a
##      damaged impeller ring visibly dims/reddens in the 3D view, not
##      only in the ShipCardsPanel module grid.
class_name ShipView

const HullMeshBuilder = preload("res://scripts/hull_mesh_builder.gd")
const WedgeMeshBuilder = preload("res://scripts/wedge_mesh_builder.gd")
const SidewallMeshBuilder = preload("res://scripts/sidewall_mesh_builder.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const WEDGE_SHADER = preload("res://scripts/wedge_impact.gdshader")
const SIDEWALL_SHADER = preload("res://scripts/sidewall_crackle.gdshader")
const HULL_SHADER = preload("res://scripts/capital_hull.gdshader")
const ImpactGeometry = preload("res://scripts/impact_geometry.gd")
const ShipDamageFx = preload("res://scripts/ship_damage_fx.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")

## Concurrent crackle sources per sidewall panel (matches sidewall_crackle.gdshader).
const MAX_SIDEWALL_HITS: int = 6

## Concurrent strike ripples the wedge shader can show (must match the
## uniform array size in wedge_impact.gdshader). Oldest is overwritten.
const MAX_WEDGE_HITS: int = 8
## Wall-clock epoch for effect timing (see fx_clock_s). A recent epoch keeps
## the float32 shader uniforms precise during long sessions.
static var _fx_epoch_msec: int = Time.get_ticks_msec()

var sim_state: ShipPhysicsState
var hull_mesh_instance: MeshInstance3D
var wedge_top: MeshInstance3D
var wedge_bottom: MeshInstance3D
var sidewall_port: MeshInstance3D
var sidewall_starboard: MeshInstance3D
var sidewall_bow: MeshInstance3D
var sidewall_stern: MeshInstance3D
var impeller_ring_bow: MeshInstance3D
var impeller_ring_stern: MeshInstance3D
var _greebles: Array = []
var wedge_material: ShaderMaterial
var _wedge_hits: Array = []        # Array[Vector4]: xyz local centre, w wall-clock start
var _wedge_hit_params: Array = []  # Array[Vector4]: x energy (0 = unused)
var _wedge_hit_cursor: int = 0
var _wedge_fx_until_s: float = 0.0
var damage_fx: ShipDamageFx
var hull_material: ShaderMaterial
var _hull_damage: float = 0.0
var _wedge_fresnel: bool = false
## sector (AttackGeometry.Sector) -> {mesh, material, hits, params, cursor, until_s, last_condition}
var _sidewall_fx: Dictionary = {}

func bind(state: ShipPhysicsState) -> void:
	sim_state = state
	_build_hull()
	_build_wedge_planes()
	_build_sidewall_panels()
	_build_greebles()
	_build_impeller_rings()
	_build_damage_fx()

func _build_damage_fx() -> void:
	if damage_fx != null and is_instance_valid(damage_fx):
		damage_fx.queue_free()
	damage_fx = ShipDamageFx.new()
	add_child(damage_fx)
	damage_fx.setup(sim_state.length_m)

func _build_hull() -> void:
	if hull_mesh_instance != null:
		hull_mesh_instance.queue_free()

	hull_mesh_instance = MeshInstance3D.new()
	hull_mesh_instance.mesh = HullMeshBuilder.build(sim_state.length_m, sim_state.max_width_m, sim_state.max_height_m)

	# 2026-10-09: capital_hull.gdshader -- procedural plating, emissive strips /
	# windows / thrusters and a damage mask, on top of the same baked vertex
	# colours (HullMeshBuilder light-from-above gradient) as before.
	var material := ShaderMaterial.new()
	material.shader = HULL_SHADER
	material.set_shader_parameter("half_extents", Vector3(sim_state.max_width_m * 0.5, sim_state.max_height_m * 0.5, sim_state.length_m * 0.5))
	material.set_shader_parameter("plate_color", Color(0.55, 0.58, 0.62))  # dull hull-plate grey; no branding/IP-derived livery
	hull_material = material
	hull_mesh_instance.material_override = material

	add_child(hull_mesh_instance)

func _build_wedge_planes() -> void:
	# Procedural V-cross-section "tent" wedge (WedgeMeshBuilder), flaring
	# toward bow/stern, instead of a flat rectangle -- see that file's
	# header for the reasoning and CANON/ASSUMPTION basis.
	var hull_half_width: float = sim_state.max_width_m * 1.1  # slightly proud of the hull envelope
	var ridge_height: float = sim_state.max_height_m * 0.9

	# 2026-10-09: the wedge material is now wedge_impact.gdshader (same
	# additive/unshaded look, plus strike ripples driven by add_wedge_impact).
	wedge_material = ShaderMaterial.new()
	wedge_material.shader = WEDGE_SHADER
	wedge_material.set_shader_parameter("ship_size", sim_state.length_m)
	_wedge_hits.clear()
	_wedge_hit_params.clear()
	for i in range(MAX_WEDGE_HITS):
		_wedge_hits.append(Vector4.ZERO)
		_wedge_hit_params.append(Vector4.ZERO)
	wedge_material.set_shader_parameter("hits", _wedge_hits)
	wedge_material.set_shader_parameter("hit_params", _wedge_hit_params)
	var material: ShaderMaterial = wedge_material

	wedge_top = _make_flat_wedge_mesh(hull_half_width, ridge_height, 1.0, material)
	wedge_bottom = _make_flat_wedge_mesh(hull_half_width, ridge_height, -1.0, material)
	add_child(wedge_top)
	add_child(wedge_bottom)

## Wall-clock seconds used by every impact effect (never sim time: at x2000
## a detonation lasts one tick, the player still needs ~1 s to read it).
static func fx_clock_s() -> float:
	return float(Time.get_ticks_msec() - _fx_epoch_msec) * 0.001

## Wedge geometry the strike-centre maths needs, mirroring
## _build_wedge_planes()/WedgeMeshBuilder (hull_half_width, ridge_height,
## wedge_half_length). Read-only convenience for ImpactFxDirector.
func wedge_geometry() -> Dictionary:
	return {
		"half_length": sim_state.length_m * 0.5 * 1.15,
		"half_width": sim_state.max_width_m * 1.1,
		"ridge_height": sim_state.max_height_m * 0.9,
	}

## Starts one strike ripple on the wedge. `local_center` is in this ship's
## local frame; `energy` 0..1 (>0); `start_s`/`life_s` on fx_clock_s().
## Purely visual state -- writes shader uniforms only, nothing in the sim.
func add_wedge_impact(local_center: Vector3, energy: float, start_s: float, life_s: float) -> void:
	if wedge_material == null or energy <= 0.0:
		return
	_wedge_hits[_wedge_hit_cursor] = Vector4(local_center.x, local_center.y, local_center.z, start_s)
	_wedge_hit_params[_wedge_hit_cursor] = Vector4(clampf(energy, 0.0, 1.0), 0.0, 0.0, 0.0)
	_wedge_hit_cursor = (_wedge_hit_cursor + 1) % MAX_WEDGE_HITS
	wedge_material.set_shader_parameter("hits", _wedge_hits)
	wedge_material.set_shader_parameter("hit_params", _wedge_hit_params)
	wedge_material.set_shader_parameter("ripple_life", life_s)
	_wedge_fx_until_s = maxf(_wedge_fx_until_s, start_s + life_s)

## Full dimension bundle for ImpactGeometry (hull ellipsoid, wedge, panels).
func ship_geometry() -> Dictionary:
	return ImpactGeometry.dims_for(sim_state.length_m, sim_state.max_width_m, sim_state.max_height_m)

## Cumulative hull fraction lost (0..1) from ImpactRecord snapshots: darkens
## the hull plating and drives venting. Visual state only.
func set_hull_damage(fraction: float) -> void:
	_hull_damage = clampf(fraction, 0.0, 1.0)
	if hull_material != null:
		hull_material.set_shader_parameter("damage", _hull_damage)
	if damage_fx != null:
		damage_fx.set_damage_fraction(_hull_damage)

func hull_damage() -> float:
	return _hull_damage

## BRIGHT (false, default) or FRESNEL "almost invisible until hit" (true).
func set_wedge_fresnel(on: bool) -> void:
	_wedge_fresnel = on
	if wedge_material != null:
		wedge_material.set_shader_parameter("fresnel_mode", 1.0 if on else 0.0)

func is_wedge_fresnel() -> bool:
	return _wedge_fresnel

## Starts a crackle burst on one sidewall panel. `ship_center` is in the SHIP's
## local frame (converted to the panel's frame here). Visual state only.
func add_sidewall_impact(sector: int, ship_center: Vector3, energy: float, start_s: float, life_s: float) -> void:
	var fx: Dictionary = _sidewall_fx.get(sector, {})
	if fx.is_empty() or energy <= 0.0:
		return
	var panel: MeshInstance3D = fx["mesh"]
	var local: Vector3 = ship_center - panel.position
	var hits: Array = fx["hits"]
	var params: Array = fx["params"]
	var cursor: int = fx["cursor"]
	hits[cursor] = Vector4(local.x, local.y, local.z, start_s)
	params[cursor] = Vector4(clampf(energy, 0.0, 1.0), 0.0, 0.0, 0.0)
	fx["cursor"] = (cursor + 1) % MAX_SIDEWALL_HITS
	var material: ShaderMaterial = fx["material"]
	material.set_shader_parameter("hits", hits)
	material.set_shader_parameter("hit_params", params)
	material.set_shader_parameter("crackle_life", life_s)
	fx["until_s"] = maxf(float(fx["until_s"]), start_s + life_s)

func _make_flat_wedge_mesh(hull_half_width: float, ridge_height: float, sign: float, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = WedgeMeshBuilder.build(sim_state.length_m, hull_half_width, ridge_height, sign)
	mesh_instance.material_override = material
	return mesh_instance

## Sidewall colour is deliberately distinct from the wedge's blue (amber
## for the always-potentially-up broadside pair, orange-red for the
## situational bow/stern pair) so a player can visually tell wedge and
## sidewalls apart, and tell the two sidewall kinds apart, at a glance --
## purely a rendering distinction, not a new simulation concept.
func _build_sidewall_panels() -> void:
	var broadside_half_width: float = sim_state.max_width_m * 0.55  # sits just outside the hull flank
	var bow_stern_half_length: float = sim_state.length_m * 0.5
	var broadside_color := Color(0.95, 0.75, 0.15, 0.22)
	var bow_stern_color := Color(0.95, 0.35, 0.15, 0.22)

	sidewall_port = _make_sidewall_panel(SidewallMeshBuilder.build_broadside(sim_state.length_m, sim_state.max_height_m), Vector3(-broadside_half_width, 0.0, 0.0), broadside_color, AttackGeometry.Sector.PORT)
	sidewall_starboard = _make_sidewall_panel(SidewallMeshBuilder.build_broadside(sim_state.length_m, sim_state.max_height_m), Vector3(broadside_half_width, 0.0, 0.0), broadside_color, AttackGeometry.Sector.STARBOARD)
	# -Z = bow (attack_geometry.gd convention).
	sidewall_bow = _make_sidewall_panel(SidewallMeshBuilder.build_bow_stern(sim_state.max_width_m, sim_state.max_height_m), Vector3(0.0, 0.0, -bow_stern_half_length), bow_stern_color, AttackGeometry.Sector.BOW)
	sidewall_stern = _make_sidewall_panel(SidewallMeshBuilder.build_bow_stern(sim_state.max_width_m, sim_state.max_height_m), Vector3(0.0, 0.0, bow_stern_half_length), bow_stern_color, AttackGeometry.Sector.STERN)

## One sidewall panel with its own sidewall_crackle.gdshader material (own
## condition + strike ring buffer), registered under its AttackGeometry sector.
func _make_sidewall_panel(mesh: Mesh, panel_position: Vector3, color: Color, sector: int) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.mesh = mesh
	panel.position = panel_position
	var material := ShaderMaterial.new()
	material.shader = SIDEWALL_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("ship_size", sim_state.length_m)
	var hits: Array = []
	var params: Array = []
	for i in range(MAX_SIDEWALL_HITS):
		hits.append(Vector4.ZERO)
		params.append(Vector4.ZERO)
	material.set_shader_parameter("hits", hits)
	material.set_shader_parameter("hit_params", params)
	panel.material_override = material
	add_child(panel)
	_sidewall_fx[sector] = {"mesh": panel, "material": material, "hits": hits, "params": params, "cursor": 0, "until_s": 0.0, "last_condition": 1.0}
	return panel

## Small static "greeble" meshes (bridge/sensor mast, flank blisters) so
## the hull silhouette isn't a perfectly smooth surface of revolution.
## Explicitly illustrative placement/count (ASSUMPTIONS.md, same status
## as the hull/wedge/sidewall shapes) -- NOT derived from this ship's
## actual weapon-mount positions or count (weapon_fx.gd owns that, for
## the actual fire-effect origins; this is pure silhouette dressing).
func _build_greebles() -> void:
	for g in _greebles:
		if is_instance_valid(g):
			g.queue_free()
	_greebles.clear()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.44, 0.48)
	material.metallic = 0.4
	material.roughness = 0.4
	material.rim_enabled = true
	material.rim = 0.3
	material.rim_tint = 0.5

	# Bridge/sensor mast: a small raised block set dorsally, offset
	# toward the stern third of the hull for an asymmetric silhouette
	# (common capital-ship layout; not a citation of a specific class).
	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = Vector3(sim_state.max_width_m * 0.16, sim_state.max_height_m * 0.30, sim_state.length_m * 0.09)
	bridge.mesh = bridge_mesh
	bridge.material_override = material
	bridge.position = Vector3(0.0, sim_state.max_height_m * 0.40, sim_state.length_m * 0.14)
	add_child(bridge)
	_greebles.append(bridge)

	# Flank blisters (sensor/PD clusters): a fixed small count along both
	# sides, purely for silhouette breakup -- not tied to this ship's
	# actual PD-mount count.
	var blister_count: int = 3
	for i in range(blister_count):
		var frac: float = lerp(-0.55, 0.15, float(i) / float(maxi(blister_count - 1, 1)))
		for side in [-1.0, 1.0]:
			var blister := MeshInstance3D.new()
			var blister_mesh := CapsuleMesh.new()
			blister_mesh.radius = sim_state.max_height_m * 0.055
			blister_mesh.height = sim_state.max_height_m * 0.14
			blister.mesh = blister_mesh
			blister.material_override = material
			blister.position = Vector3(side * sim_state.max_width_m * 0.46, 0.0, sim_state.length_m * frac)
			add_child(blister)
			_greebles.append(blister)

## Impeller-ring glow at the bow/stern flare positions (matching
## HullMeshBuilder._radius_profile's own flare_center=0.82, so the ring
## sits right where the hull's hammerhead flare already visually reads as
## "this is the generator location"). Colour/brightness is set every
## frame from the ship's own PROPULSION subsystem condition (see
## _process) -- CANON_RULES.md lists "impeller rings (degrading max
## acceleration)" as a real, already-modelled damage-model component
## (simulation_world.gd's PROPULSION subsystem); this only makes that
## existing state visible in the 3D view instead of only in
## ShipCardsPanel's module grid.
func _build_impeller_rings() -> void:
	if impeller_ring_bow != null:
		impeller_ring_bow.queue_free()
	if impeller_ring_stern != null:
		impeller_ring_stern.queue_free()

	var half_length: float = sim_state.length_m * 0.5
	var ring_z: float = half_length * 0.82
	var ring_radius: float = (sim_state.max_width_m + sim_state.max_height_m) * 0.25 * 0.7

	impeller_ring_bow = _make_impeller_ring(ring_radius, -ring_z)
	impeller_ring_stern = _make_impeller_ring(ring_radius, ring_z)
	add_child(impeller_ring_bow)
	add_child(impeller_ring_stern)

func _make_impeller_ring(radius: float, z: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = radius
	torus.inner_radius = radius * 0.78
	mesh_instance.mesh = torus
	# TorusMesh's hole axis defaults to Y (ring lies flat in the XZ
	# plane); rotate 90 deg about X so the hole axis becomes Z -- the
	# ring then encircles the hull's cross-section at this Z position,
	# matching -Z=bow/+Z=stern (attack_geometry.gd convention).
	mesh_instance.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mesh_instance.position = Vector3(0.0, 0.0, z)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	mesh_instance.material_override = material
	return mesh_instance

## PROPULSION condition -> impeller-ring glow colour. Healthy: a bright
## cyan-white matching the wedge's own hue family (same field, same
## generator). Damaged: dims and shifts toward a dull red warning glow,
## going nearly dark once PROPULSION is disabled -- a direct visual echo
## of CANON_RULES.md's "impeller rings (degrading max acceleration)".
## Pure function, unit-testable without a scene tree (see
## test_ship_view_sidewalls.gd, which already covers ShipView's other
## static readout helpers).
static func _impeller_glow_color(condition: float) -> Color:
	var c: float = clampf(condition, 0.0, 1.0)
	var healthy := Color(0.55, 0.85, 1.0)
	var damaged := Color(0.9, 0.25, 0.15)
	var hue: Color = healthy.lerp(damaged, 1.0 - c)
	var brightness: float = lerp(0.12, 1.0, c)
	return Color(hue.r * brightness, hue.g * brightness, hue.b * brightness, 1.0)

## Broadside sidewalls have no "raised" flag in ship_defense_state.gd --
## they are potentially up whenever not burned out. Pure function,
## unit-testable without a scene tree.
static func _broadside_sidewall_visible(condition: float) -> bool:
	return condition > ShipDefenseState.SIDEWALL_BURNOUT_THRESHOLD

## Bow/stern sidewalls additionally require the explicit raised flag
## (default false -- raising costs impeller acceleration, CONFIRMED
## CANON). Pure function, unit-testable without a scene tree.
static func _bow_stern_sidewall_visible(raised: bool, condition: float) -> bool:
	return raised and condition > ShipDefenseState.SIDEWALL_BURNOUT_THRESHOLD

func _process(_delta: float) -> void:
	if sim_state == null:
		return
	global_position = RenderOrigin.to_render(sim_state.position)
	global_basis = Basis(sim_state.orientation)

	if wedge_material != null:
		var now_s: float = fx_clock_s()
		if now_s <= _wedge_fx_until_s:
			wedge_material.set_shader_parameter("fx_time", now_s)

	var defense: ShipDefenseState = sim_state.defense
	var wedge_visible: bool = defense != null and defense.wedge_up
	if wedge_top != null:
		wedge_top.visible = wedge_visible
		wedge_bottom.visible = wedge_visible

	if impeller_ring_bow != null:
		var propulsion_condition: float = 1.0
		if sim_state.subsystems != null:
			propulsion_condition = sim_state.subsystems.get_condition(SubsystemType.Type.PROPULSION)
		var glow: Color = _impeller_glow_color(propulsion_condition)
		if hull_material != null:
			hull_material.set_shader_parameter("engine_glow", propulsion_condition)
			hull_material.set_shader_parameter("fx_time", fx_clock_s())
		for ring in [impeller_ring_bow, impeller_ring_stern]:
			var mat: StandardMaterial3D = ring.material_override
			mat.emission = glow
			mat.emission_energy_multiplier = lerp(0.7, 3.0, propulsion_condition)
			mat.albedo_color = Color(glow.r * 0.6, glow.g * 0.6, glow.b * 0.6, 1.0)

	if defense == null:
		if sidewall_port != null:
			sidewall_port.visible = false
			sidewall_starboard.visible = false
			sidewall_bow.visible = false
			sidewall_stern.visible = false
		return

	_update_sidewall_fx(defense)

	if sidewall_port != null:
		sidewall_port.visible = _broadside_sidewall_visible(defense.port_sidewall_condition)
	if sidewall_starboard != null:
		sidewall_starboard.visible = _broadside_sidewall_visible(defense.starboard_sidewall_condition)
	if sidewall_bow != null:
		sidewall_bow.visible = _bow_stern_sidewall_visible(defense.bow_sidewall_raised, defense.bow_sidewall_condition)
	if sidewall_stern != null:
		sidewall_stern.visible = _bow_stern_sidewall_visible(defense.stern_sidewall_raised, defense.stern_sidewall_condition)

## Pushes each panel's live condition (read-only from the sim) and the wall
## clock into its shader, so a failing panel flickers on its own and a struck
## one crackles. fx_time is only written while something needs animating.
func _update_sidewall_fx(defense: ShipDefenseState) -> void:
	var now_s: float = fx_clock_s()
	var conditions: Dictionary = {
		AttackGeometry.Sector.PORT: defense.port_sidewall_condition,
		AttackGeometry.Sector.STARBOARD: defense.starboard_sidewall_condition,
		AttackGeometry.Sector.BOW: defense.bow_sidewall_condition,
		AttackGeometry.Sector.STERN: defense.stern_sidewall_condition,
	}
	for sector in _sidewall_fx.keys():
		var fx: Dictionary = _sidewall_fx[sector]
		var material: ShaderMaterial = fx["material"]
		var condition: float = conditions[sector]
		if not is_equal_approx(condition, float(fx["last_condition"])):
			material.set_shader_parameter("condition", condition)
			fx["last_condition"] = condition
		if condition < 0.999 or now_s <= float(fx["until_s"]):
			material.set_shader_parameter("fx_time", now_s)
