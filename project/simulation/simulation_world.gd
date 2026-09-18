extends Node
## SimulationWorld
##
## ТЗ §42 Simulation Architecture / Milestone 1 ("Engine skeleton + 3D
## world + simulation loop"): the root of "Simulation". Owns all ships and
## missiles and, each fixed SimClock tick, drives EVERY previously-built
## module together in one deterministic pass -- sensors, missile
## guidance/flight/detonation, counter-missiles, point defense, and ship
## physics. Has no knowledge of rendering.
##
## HONEST STATUS: this is the first place all of the following actually
## run together tick-by-tick, instead of existing only as isolated,
## individually-tested modules:
##   SensorResolution (§23), ECMState (§24, read-only here -- nothing yet
##   calls a ship's own jammer on/off), ShipSubsystems (§25, read via
##   ShipPhysicsState.subsystems), MissileGuidance/MissileState (§18/§19),
##   MissileResolution (§21), CounterMissileResolution (§20),
##   PointDefenseResolution (§22), ShipPhysicsState.integrate (§12).
## What this is NOT: Tactical AI (§26). There is no target/weapon
## SELECTION logic here beyond one explicitly-documented placeholder rule
## (point defense picks the nearest active missile CURRENTLY targeting
## that ship -- see `_resolve_point_defense`). Nothing here decides which
## ship a missile should be launched at, or fires ship-to-ship weapons
## automatically; `weapon_mounts`/`fire_weapon` exist so a caller (a
## scenario script, or eventually real AI) can trigger a shot, but this
## class does not choose targets for them itself. That is Milestone 9,
## not this one.
class_name SimulationWorld

const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const MissileGuidance = preload("res://simulation/missile_guidance.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const CounterMissileResolution = preload("res://simulation/counter_missile_resolution.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")

var clock: SimClock

var ships: Dictionary = {}            # ship_id -> ShipPhysicsState
var hulls: Dictionary = {}            # ship_id -> HullState (optional)
var weapon_mounts: Dictionary = {}    # ship_id -> Array[WeaponMount]
var pd_mounts: Dictionary = {}        # ship_id -> Array[PointDefenseMount]
var ecm_states: Dictionary = {}       # ship_id -> ECMState (optional)
var sensor_contacts: Dictionary = {}  # ship_id -> Dictionary[contact_key -> SensorContact]

var missiles: Dictionary = {}         # missile_id -> MissileState
var missile_owners: Dictionary = {}   # missile_id -> owning ship_id (String, may be "")

func _ready() -> void:
	clock = SimClock.new()
	add_child(clock)
	clock.simulation_tick.connect(_on_simulation_tick)

func _process(delta: float) -> void:
	clock.advance(delta)

func add_ship(ship_id: String, state: ShipPhysicsState, hull = null) -> void:
	ships[ship_id] = state
	if hull != null:
		hulls[ship_id] = hull
	if not weapon_mounts.has(ship_id):
		weapon_mounts[ship_id] = []
	if not pd_mounts.has(ship_id):
		pd_mounts[ship_id] = []
	if not sensor_contacts.has(ship_id):
		sensor_contacts[ship_id] = {}

func remove_ship(ship_id: String) -> void:
	ships.erase(ship_id)
	hulls.erase(ship_id)
	weapon_mounts.erase(ship_id)
	pd_mounts.erase(ship_id)
	ecm_states.erase(ship_id)
	sensor_contacts.erase(ship_id)

func get_ship(ship_id: String) -> ShipPhysicsState:
	return ships.get(ship_id)

func get_hull(ship_id: String):
	return hulls.get(ship_id)

func add_weapon_mount(ship_id: String, mount) -> void:
	weapon_mounts[ship_id].append(mount)

func add_pd_mount(ship_id: String, mount) -> void:
	pd_mounts[ship_id].append(mount)

func set_ecm(ship_id: String, ecm_state) -> void:
	ecm_states[ship_id] = ecm_state

func add_missile(missile_id: String, missile, owner_ship_id: String = "") -> void:
	missiles[missile_id] = missile
	missile_owners[missile_id] = owner_ship_id

func remove_missile(missile_id: String) -> void:
	missiles.erase(missile_id)
	missile_owners.erase(missile_id)

## Explicit shot trigger -- NOT automatic target selection (see class doc).
## A caller (scenario script / future AI) decides attacker/target/mount.
func fire_weapon(attacker_ship_id: String, mount, target_ship_id: String):
	var attacker = ships.get(attacker_ship_id)
	var target = ships.get(target_ship_id)
	if attacker == null or target == null:
		return null
	return WeaponResolution.fire(attacker, mount, target, hulls.get(target_ship_id), target.subsystems)

func _on_simulation_tick(dt: float, _tick: int, _sim_time: float) -> void:
	tick_simulation(dt)

## The actual per-tick integration of every module, exposed as a plain
## method (not gated behind the SimClock/Node signal) so tests -- and any
## future scenario runner -- can drive it directly without a SceneTree.
func tick_simulation(dt: float) -> void:
	_cleanup_inactive_missiles()
	_update_sensors(dt)
	_update_missiles(dt)
	_resolve_counter_missile_intercepts()
	_resolve_point_defense(dt)
	_integrate_ships(dt)

func _cleanup_inactive_missiles() -> void:
	for missile_id in missiles.keys():
		var missile = missiles[missile_id]
		if not missile.is_active():
			missiles.erase(missile_id)
			missile_owners.erase(missile_id)

## ТЗ §23: every ship updates its own sensor picture of every OTHER ship
## and every active missile, reading its own SENSORS subsystem condition
## (§25) and each target's ECM (§24) if present.
func _update_sensors(dt: float) -> void:
	for observer_id in ships.keys():
		var observer: ShipPhysicsState = ships[observer_id]
		var contacts: Dictionary = sensor_contacts.get(observer_id)
		if contacts == null:
			contacts = {}
			sensor_contacts[observer_id] = contacts

		for other_id in ships.keys():
			if other_id == observer_id:
				continue
			var target = ships[other_id]
			var target_ecm = ecm_states.get(other_id)
			SensorResolution.update_contacts(contacts, other_id, target, observer.position, dt, SensorResolution.DEFAULT_SENSOR_RANGE_M, target_ecm, observer.subsystems)

		for missile_id in missiles.keys():
			var missile = missiles[missile_id]
			SensorResolution.update_contacts(contacts, missile_id, missile, observer.position, dt, SensorResolution.DEFAULT_SENSOR_RANGE_M, null, observer.subsystems)

## ТЗ §18/§19/§21: guide, fly, and (if armed) detonate every active missile.
func _update_missiles(dt: float) -> void:
	for missile_id in missiles.keys():
		var missile = missiles[missile_id]
		if not missile.is_active():
			continue

		var thrust_dir: Vector3 = MissileGuidance.resolve_thrust_direction(missile, dt)
		missile.integrate(dt, thrust_dir)

		if missile.warhead_armed and not missile.has_detonated:
			var target = missile.target
			var target_hull = null
			var target_subsystems = null
			for ship_id in ships.keys():
				if ships[ship_id] == target:
					target_hull = hulls.get(ship_id)
					target_subsystems = ships[ship_id].subsystems
					break
			MissileResolution.resolve_detonation(missile, target_hull, target_subsystems)

## ТЗ §20: any missile whose target is itself another (incoming) missile
## is a counter-missile -- check whether it has closed to kill radius.
func _resolve_counter_missile_intercepts() -> void:
	for missile_id in missiles.keys():
		var missile = missiles[missile_id]
		if not missile.is_active():
			continue
		if missile.target is MissileState:
			CounterMissileResolution.check_intercept(missile, missile.target)

## ТЗ §22 Point Defense. Target SELECTION here is a documented PLACEHOLDER
## (not tactical AI, §26): each ship's PD mounts all engage the single
## nearest currently-active missile whose `.target` is that ship. A real
## AI would prioritize by time-to-impact, salvo size, ship value, etc. --
## none of that exists yet.
func _resolve_point_defense(dt: float) -> void:
	for ship_id in ships.keys():
		var mounts: Array = pd_mounts.get(ship_id, [])
		if mounts.is_empty():
			continue

		var ship: ShipPhysicsState = ships[ship_id]
		var nearest_missile = null
		var nearest_missile_id = null
		var nearest_distance: float = INF
		for missile_id in missiles.keys():
			var missile = missiles[missile_id]
			if not missile.is_active():
				continue
			if missile.target != ship:
				continue
			var d: float = ship.position.distance_to(missile.position)
			if d < nearest_distance:
				nearest_distance = d
				nearest_missile = missile
				nearest_missile_id = missile_id

		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var sensor_contact = contacts.get(nearest_missile_id) if nearest_missile_id != null else null

		for mount in mounts:
			PointDefenseResolution.engage(mount, ship, nearest_missile, dt, sensor_contact)

func _integrate_ships(dt: float) -> void:
	for ship_id in ships.keys():
		ships[ship_id].integrate(dt)
