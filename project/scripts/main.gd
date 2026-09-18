extends Node3D
## Main
##
## Visual prototype bring-up scene: creates a SimulationWorld with two
## ships on an inertial thrust course, each with a procedural hull mesh
## (scripts/hull_mesh_builder.gd) and a live wedge visualization driven by
## ship_defense_state.gd -- the first actually-visible prototype of the
## simulation, not just headless unit tests (ТЗ §56 Milestone 1-3 bring-up).
##
## Still explicitly NOT done here: weapons firing automatically, missiles,
## AI, tactical UI, camera controls beyond a fixed framing shot. See
## CHANGELOG.md for the authoritative "done vs not done" list.

var world: SimulationWorld
var hulls: Dictionary = {}  # String ship_id -> HullState
var mounts: Dictionary = {}  # String ship_id -> Array[WeaponMount]

func _ready() -> void:
	world = SimulationWorld.new()
	add_child(world)

	var alpha := ShipPhysicsState.new()
	alpha.position = Vector3(-5000.0, 0.0, 0.0)
	alpha.commanded_thrust_local = Vector3(0.0, 0.0, -1.0)
	alpha.defense = ShipDefenseState.new()
	world.add_ship("alpha", alpha)

	var beta := ShipPhysicsState.new()
	beta.position = Vector3(5000.0, 0.0, 0.0)
	beta.orientation = Quaternion(Vector3.UP, PI)
	beta.commanded_thrust_local = Vector3(0.0, 0.0, -1.0)
	beta.defense = ShipDefenseState.new()
	world.add_ship("beta", beta)

	for ship_id in world.ships.keys():
		var view := ShipView.new()
		view.bind(world.ships[ship_id])  # builds its own procedural hull + wedge planes
		add_child(view)

		hulls[ship_id] = HullState.new()
		var laser := WeaponData.new()
		laser.id = "demo_laser"
		laser.max_range_m = 500_000.0
		laser.damage_per_hit = 100.0
		laser.recharge_time_s = 4.0
		mounts[ship_id] = [WeaponMount.new(laser, WeaponMount.bow_chaser_arc())]

	world.clock.simulation_tick.connect(_on_tick)
	_frame_camera_on_ships()

func _on_tick(dt: float, _tick: int, _sim_time: float) -> void:
	for ship_id in mounts.keys():
		for mount in mounts[ship_id]:
			mount.tick(dt)

## Points the scene's Camera3D at the midpoint between the two demo ships
## from a distance proportional to their separation, computed from actual
## ship positions rather than a hand-tuned fixed transform in the .tscn
## (which, on inspection, was aimed along -Z without ever pointing at the
## ships -- a Milestone 1 oversight since headless test runs cannot verify
## framing visually; fixed now that this is meant to actually be looked at).
func _frame_camera_on_ships() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return

	var positions: Array = []
	for ship_id in world.ships.keys():
		positions.append(world.ships[ship_id].position)
	if positions.is_empty():
		return

	var midpoint: Vector3 = Vector3.ZERO
	for p in positions:
		midpoint += p
	midpoint /= positions.size()

	var spread: float = 1.0
	for p in positions:
		spread = maxf(spread, midpoint.distance_to(p))

	# Distance derived from the camera's own FOV so the full spread
	# actually fits in frame (a fixed offset multiplier either left ships
	# outside the frustum when too close, or too small to read when too
	# far -- both happened during this pass; deriving it from trig avoids
	# re-tuning a magic number by hand every time ship separation changes).
	camera.fov = 60.0
	var half_fov_rad: float = deg_to_rad(camera.fov * 0.5)
	var required_distance: float = (spread / tan(half_fov_rad)) * 1.6
	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	camera.global_position = midpoint + view_dir * required_distance
	camera.look_at(midpoint, Vector3.UP)
	camera.far = required_distance * 3.0 + 10000.0
