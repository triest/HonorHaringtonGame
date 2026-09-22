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
class_name ShipView

const HullMeshBuilder = preload("res://scripts/hull_mesh_builder.gd")
const WedgeMeshBuilder = preload("res://scripts/wedge_mesh_builder.gd")
const SidewallMeshBuilder = preload("res://scripts/sidewall_mesh_builder.gd")

var sim_state: ShipPhysicsState
var hull_mesh_instance: MeshInstance3D
var wedge_top: MeshInstance3D
var wedge_bottom: MeshInstance3D
var sidewall_port: MeshInstance3D
var sidewall_starboard: MeshInstance3D
var sidewall_bow: MeshInstance3D
var sidewall_stern: MeshInstance3D

func bind(state: ShipPhysicsState) -> void:
	sim_state = state
	_build_hull()
	_build_wedge_planes()
	_build_sidewall_panels()

func _build_hull() -> void:
	if hull_mesh_instance != null:
		hull_mesh_instance.queue_free()

	hull_mesh_instance = MeshInstance3D.new()
	hull_mesh_instance.mesh = HullMeshBuilder.build(sim_state.length_m, sim_state.max_width_m, sim_state.max_height_m)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.58, 0.62)  # dull hull-plate grey; no branding/IP-derived livery
	material.metallic = 0.3
	material.roughness = 0.6
	hull_mesh_instance.material_override = material

	add_child(hull_mesh_instance)

func _build_wedge_planes() -> void:
	# Procedural V-cross-section "tent" wedge (WedgeMeshBuilder), flaring
	# toward bow/stern, instead of a flat rectangle -- see that file's
	# header for the reasoning and CANON/ASSUMPTION basis.
	var hull_half_width: float = sim_state.max_width_m * 1.1  # slightly proud of the hull envelope
	var ridge_height: float = sim_state.max_height_m * 0.9

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.6, 1.0, 0.28)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	global_position = sim_state.position
	global_basis = Basis(sim_state.orientation)

	var defense: ShipDefenseState = sim_state.defense
	var wedge_visible: bool = defense != null and defense.wedge_up
	if wedge_top != null:
		wedge_top.visible = wedge_visible
		wedge_bottom.visible = wedge_visible

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
