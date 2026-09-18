extends Node3D
## ShipView
##
## Rendering-only node. Reads a ShipPhysicsState (and its optional
## ShipDefenseState) each frame and updates the visual transform + hull
## mesh + wedge visualization. Must NEVER write back into simulation state
## or make combat/physics decisions (ТЗ §42).
##
## Hull mesh: a procedural "flattened spindle" placeholder built from the
## CANON silhouette description (see scripts/hull_mesh_builder.gd), sized
## from the bound ShipPhysicsState's length_m/max_width_m/max_height_m.
##
## Wedge visualization: two translucent planes above/below the hull,
## shown only while sim_state.defense.wedge_up is true -- a direct visual
## readout of the already-implemented wedge logic (ship_defense_state.gd),
## not a separate source of truth.
class_name ShipView

const HullMeshBuilder = preload("res://scripts/hull_mesh_builder.gd")
const WedgeMeshBuilder = preload("res://scripts/wedge_mesh_builder.gd")

var sim_state: ShipPhysicsState
var hull_mesh_instance: MeshInstance3D
var wedge_top: MeshInstance3D
var wedge_bottom: MeshInstance3D

func bind(state: ShipPhysicsState) -> void:
	sim_state = state
	_build_hull()
	_build_wedge_planes()

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

	wedge_top = _make_wedge_mesh(hull_half_width, ridge_height, 1.0, material)
	wedge_bottom = _make_wedge_mesh(hull_half_width, ridge_height, -1.0, material)
	add_child(wedge_top)
	add_child(wedge_bottom)

func _make_wedge_mesh(hull_half_width: float, ridge_height: float, sign: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = WedgeMeshBuilder.build(sim_state.length_m, hull_half_width, ridge_height, sign)
	mesh_instance.material_override = material
	return mesh_instance

func _process(_delta: float) -> void:
	if sim_state == null:
		return
	global_position = sim_state.position
	global_basis = Basis(sim_state.orientation)

	var wedge_visible: bool = sim_state.defense != null and sim_state.defense.wedge_up
	if wedge_top != null:
		wedge_top.visible = wedge_visible
		wedge_bottom.visible = wedge_visible
