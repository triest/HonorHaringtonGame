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

func bind(state: ShipPhysicsState) -> void:
	sim_state = state
	_build_hull()
	_build_wedge_planes()
	_build_sidewall_panels()
	_build_greebles()
	_build_impeller_rings()

func _build_hull() -> void:
	if hull_mesh_instance != null:
		hull_mesh_instance.queue_free()

	hull_mesh_instance = MeshInstance3D.new()
	hull_mesh_instance.mesh = HullMeshBuilder.build(sim_state.length_m, sim_state.max_width_m, sim_state.max_height_m)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.58, 0.62)  # dull hull-plate grey; no branding/IP-derived livery
	material.vertex_color_use_as_albedo = true  # picks up HullMeshBuilder's baked shading/seam gradient
	material.metallic = 0.35
	material.roughness = 0.45
	# Cheap fresnel edge highlight -- makes a low-poly procedural hull
	# read as a lit solid instead of a flat-shaded blob from most angles.
	material.rim_enabled = true
	material.rim = 0.35
	material.rim_tint = 0.5
	hull_mesh_instance.material_override = material

	add_child(hull_mesh_instance)

func _build_wedge_planes() -> void:
	# Procedural V-cross-section "tent" wedge (WedgeMeshBuilder), flaring
	# toward bow/stern, instead of a flat rectangle -- see that file's
	# header for the reasoning and CANON/ASSUMPTION basis.
	var hull_half_width: float = sim_state.max_width_m * 1.1  # slightly proud of the hull envelope
	var ridge_height: float = sim_state.max_height_m * 0.9

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.65, 1.0, 1.0)
	material.vertex_color_use_as_albedo = true  # WedgeMeshBuilder's ridge->edge + lengthwise glow gradient
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # reads as a glowing field, not a flat translucent card
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	wedge_top = _make_flat_wedge_mesh(hull_half_width, ridge_height, 1.0, material)
	wedge_bottom = _make_flat_wedge_mesh(hull_half_width, ridge_height, -1.0, material)
	add_child(wedge_top)
	add_child(wedge_bottom)

func _make_flat_wedge_mesh(hull_half_width: float, ridge_height: float, sign: float, material: StandardMaterial3D) -> MeshInstance3D:
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

	var broadside_material := StandardMaterial3D.new()
	broadside_material.albedo_color = Color(0.95, 0.75, 0.15, 0.22)
	broadside_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	broadside_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	broadside_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	sidewall_port = MeshInstance3D.new()
	sidewall_port.mesh = SidewallMeshBuilder.build_broadside(sim_state.length_m, sim_state.max_height_m)
	sidewall_port.material_override = broadside_material
	sidewall_port.position = Vector3(-broadside_half_width, 0.0, 0.0)
	add_child(sidewall_port)

	var starboard_material := broadside_material.duplicate()
	sidewall_starboard = MeshInstance3D.new()
	sidewall_starboard.mesh = SidewallMeshBuilder.build_broadside(sim_state.length_m, sim_state.max_height_m)
	sidewall_starboard.material_override = starboard_material
	sidewall_starboard.position = Vector3(broadside_half_width, 0.0, 0.0)
	add_child(sidewall_starboard)

	var bow_stern_material := StandardMaterial3D.new()
	bow_stern_material.albedo_color = Color(0.95, 0.35, 0.15, 0.22)
	bow_stern_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bow_stern_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bow_stern_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# -Z = bow (attack_geometry.gd convention).
	sidewall_bow = MeshInstance3D.new()
	sidewall_bow.mesh = SidewallMeshBuilder.build_bow_stern(sim_state.max_width_m, sim_state.max_height_m)
	sidewall_bow.material_override = bow_stern_material
	sidewall_bow.position = Vector3(0.0, 0.0, -bow_stern_half_length)
	add_child(sidewall_bow)

	var stern_material := bow_stern_material.duplicate()
	sidewall_stern = MeshInstance3D.new()
	sidewall_stern.mesh = SidewallMeshBuilder.build_bow_stern(sim_state.max_width_m, sim_state.max_height_m)
	sidewall_stern.material_override = stern_material
	sidewall_stern.position = Vector3(0.0, 0.0, bow_stern_half_length)
	add_child(sidewall_stern)

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

	if sidewall_port != null:
		sidewall_port.visible = _broadside_sidewall_visible(defense.port_sidewall_condition)
	if sidewall_starboard != null:
		sidewall_starboard.visible = _broadside_sidewall_visible(defense.starboard_sidewall_condition)
	if sidewall_bow != null:
		sidewall_bow.visible = _bow_stern_sidewall_visible(defense.bow_sidewall_raised, defense.bow_sidewall_condition)
	if sidewall_stern != null:
		sidewall_stern.visible = _bow_stern_sidewall_visible(defense.stern_sidewall_raised, defense.stern_sidewall_condition)
