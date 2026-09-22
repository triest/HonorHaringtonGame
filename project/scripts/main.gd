extends Node3D
## Main
##
## Visual prototype bring-up scene: creates a SimulationWorld with two
## ships on an inertial thrust course, each with a procedural hull mesh
## (scripts/hull_mesh_builder.gd) and a live wedge visualization driven by
## ship_defense_state.gd -- the first actually-visible prototype of the
## simulation, not just headless unit tests (ТЗ §56 Milestone 1-3 bring-up).
##
## Still explicitly NOT done here: weapons firing automatically (no team
## is assigned to either demo ship, so SimulationWorld's weapons/missile
## AI never selects a target -- see AGENTS.md §56.1 item 6, "Hardcoded
## 1v1/2v2 scenario vs TacticalAI", which is where that gets wired up),
## AI, tactical UI, camera controls beyond a fixed framing shot. See
## CHANGELOG.md for the authoritative "done vs not done" list.
##
## WeaponFx (scripts/weapon_fx.gd, ТЗ §56.1 item 3) IS wired into the
## per-tick loop below, purely so item 6 has nothing left to connect
## later -- with no team assigned yet, SimulationWorld.last_tick_weapon_
## shots/missiles are always empty here, so nothing visibly fires until
## item 6 sets teams and gives ships something to shoot at.

var world: SimulationWorld
var hulls: Dictionary = {}  # String ship_id -> HullState
var mounts: Dictionary = {}  # String ship_id -> Array[WeaponMount]
var weapon_fx: WeaponFx

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

	weapon_fx = WeaponFx.new()
	add_child(weapon_fx)

	world.clock.simulation_tick.connect(_on_tick)
	_frame_camera_on_ships()

## NOTE on ordering: SimulationWorld itself connects to `world.clock.
## simulation_tick` in ITS OWN _ready() (simulation_world.gd), which runs
## synchronously during `add_child(world)` above -- BEFORE this method's
## own connect() call a few lines later in this file's _ready(). Godot
## calls a signal's listeners in connection order, so world.tick_
## simulation() (which rebuilds last_tick_weapon_shots for this tick) has
## already run by the time this handler fires, and weapon_fx.update()
## below is reading this tick's fresh data, not last tick's.
func _on_tick(dt: float, _tick: int, _sim_time: float) -> void:
	for ship_id in mounts.keys():
		for mount in mounts[ship_id]:
			mount.tick(dt)
	weapon_fx.update(world)

## Points the scene's OrbitCamera at the midpoint between the two demo
## ships from a distance proportional to their separation, computed from
## actual ship positions rather than a hand-tuned fixed transform in the
## .tscn (which, on inspection, was aimed along -Z without ever pointing
## at the ships -- a Milestone 1 oversight since headless test runs
## cannot verify framing visually; fixed now that this is meant to
## actually be looked at).
##
## ТЗ §56.1 item 1: the camera used to be fixed after this initial framing
## shot; OrbitCamera (scripts/orbit_camera.gd) now lets the player orbit/
## zoom from here. This function only sets the STARTING pivot/framing --
## all player-driven movement lives in OrbitCamera itself, so main.gd
## still never touches per-frame camera transforms.
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

	if camera.has_method("frame_on"):
		camera.frame_on(midpoint, spread)
		return

	# Fallback for a plain Camera3D with no OrbitCamera script attached
	# (e.g. a dev/test scene that reuses this function) -- reproduces the
	# pre-OrbitCamera fixed-framing behavior exactly.
	camera.fov = 60.0
	var half_fov_rad: float = deg_to_rad(camera.fov * 0.5)
	var required_distance: float = (spread / tan(half_fov_rad)) * 1.6
	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	camera.global_position = midpoint + view_dir * required_distance
	camera.look_at(midpoint, Vector3.UP)
	camera.far = required_distance * 3.0 + 10000.0
