extends Node
## SimulationWorld
##
## ТЗ §42 Simulation Architecture / Milestone 1 ("Engine skeleton + 3D
## world + simulation loop"): the root of "Simulation". Owns all ships and
## missiles and, each fixed SimClock tick, drives EVERY previously-built
## module together in one deterministic pass -- sensors, tactical AI
## target selection, missile guidance/flight/detonation, counter-missiles,
## point defense, ship-to-ship weapons fire, and ship physics. Has no
## knowledge of rendering.
##
## HONEST STATUS: this is the first place all of the following actually
## run together tick-by-tick, instead of existing only as isolated,
## individually-tested modules:
##   SensorResolution (§23), ECMState (§24, read-only here -- nothing yet
##   calls a ship's own jammer on/off), ShipSubsystems (§25, read via
##   ShipPhysicsState.subsystems), MissileGuidance/MissileState (§18/§19),
##   MissileResolution (§21), CounterMissileResolution (§20),
##   PointDefenseResolution (§22), TacticalAI (§26, target selection only),
##   WeaponResolution (§17, now fired automatically per §26 "use
##   weapons"), ShipPhysicsState.integrate (§12).
##
## §26 Tactical AI status: target SELECTION for point defense AND for
## ship-to-ship weapons now goes through `TacticalAI`, which reads ONLY
## sensor contacts (never true position/identity) -- this also FIXES an
## earlier bug in this file's own point-defense placeholder, which used
## to scan `missiles` by true position/identity, itself a "no cheat
## vision" violation of §26. What is still NOT here: threat WEIGHTING
## beyond nearest-contact, formation management, maneuvering/distance
## selection, missile launch decisions, damage/loss response, retreat/
## disengage. `teams` is a minimal hostility model (different, non-empty
## team = hostile) so target selection has something to select AGAINST;
## it is not itself part of §26, just the bookkeeping §26 needs.
class_name SimulationWorld

const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const MissileGuidance = preload("res://simulation/missile_guidance.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const CounterMissileResolution = preload("res://simulation/counter_missile_resolution.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")
const TacticalAI = preload("res://simulation/tactical_ai.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const FormationState = preload("res://simulation/formation_state.gd")

var clock: SimClock

var ships: Dictionary = {}            # ship_id -> ShipPhysicsState
var hulls: Dictionary = {}            # ship_id -> HullState (optional)
var weapon_mounts: Dictionary = {}    # ship_id -> Array[WeaponMount]
var missile_tubes: Dictionary = {}    # ship_id -> Array[MissileTube] (§26 "launch missiles")
var pd_mounts: Dictionary = {}        # ship_id -> Array[PointDefenseMount]
var ecm_states: Dictionary = {}       # ship_id -> ECMState (optional)
var sensor_contacts: Dictionary = {}  # ship_id -> Dictionary[contact_key -> SensorContact]
var teams: Dictionary = {}            # ship_id -> String team id (ASSUMPTION: minimal hostility model, see class doc)
var formations: Dictionary = {}       # formation_id -> FormationState (§27/§28/§29, Milestone 10 first slice)

## ASSUMPTION (§26 "retreat"/"disengage", no canonical figure found): a
## ship whose HullState integrity fraction drops to or below this stops
## firing offensively and instead thrusts away from its known hostile
## contacts. See TacticalAI.is_critically_damaged / select_retreat_vector_world.
const CRITICAL_HULL_FRACTION: float = 0.3

var missiles: Dictionary = {}         # missile_id -> MissileState
var missile_owners: Dictionary = {}   # missile_id -> owning ship_id (String, may be "")
var _next_ai_missile_id: int = 0      # counter for AI-launched missile ids (see _resolve_missile_launch_ai)

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
	if not missile_tubes.has(ship_id):
		missile_tubes[ship_id] = []
	if not pd_mounts.has(ship_id):
		pd_mounts[ship_id] = []
	if not sensor_contacts.has(ship_id):
		sensor_contacts[ship_id] = {}

func remove_ship(ship_id: String) -> void:
	ships.erase(ship_id)
	hulls.erase(ship_id)
	weapon_mounts.erase(ship_id)
	missile_tubes.erase(ship_id)
	pd_mounts.erase(ship_id)
	ecm_states.erase(ship_id)
	sensor_contacts.erase(ship_id)
	teams.erase(ship_id)

func get_ship(ship_id: String) -> ShipPhysicsState:
	return ships.get(ship_id)

func get_hull(ship_id: String):
	return hulls.get(ship_id)

func add_weapon_mount(ship_id: String, mount) -> void:
	weapon_mounts[ship_id].append(mount)

func add_missile_tube(ship_id: String, tube) -> void:
	missile_tubes[ship_id].append(tube)

func add_pd_mount(ship_id: String, mount) -> void:
	pd_mounts[ship_id].append(mount)

func set_ecm(ship_id: String, ecm_state) -> void:
	ecm_states[ship_id] = ecm_state

## Milestone 10 first slice: register a formation. `guide_ship_id` need
## not exist yet at call time (checked live each tick by
## `_resolve_formation_keeping`), so scenario setup order is flexible.
func add_formation(formation_id: String, guide_ship_id: String) -> FormationState:
	var formation := FormationState.new()
	formation.guide_ship_id = guide_ship_id
	formations[formation_id] = formation
	return formation

func get_formation(formation_id: String) -> FormationState:
	return formations.get(formation_id)

## ТЗ §26: minimal hostility bookkeeping. Two ships are hostile to each
## other only if BOTH have a non-empty team assigned AND the teams
## differ -- a ship with no team set is neutral (never selected as a
## weapon/PD target), not an accidental default-hostile.
func set_team(ship_id: String, team: String) -> void:
	teams[ship_id] = team

func is_hostile(ship_id_a: String, ship_id_b: String) -> bool:
	var team_a = teams.get(ship_id_a, "")
	var team_b = teams.get(ship_id_b, "")
	return team_a != "" and team_b != "" and team_a != team_b

func _hostile_ship_ids(ship_id: String) -> Array:
	var result: Array = []
	for other_id in ships.keys():
		if other_id == ship_id:
			continue
		if is_hostile(ship_id, other_id):
			result.append(other_id)
	return result

func add_missile(missile_id: String, missile, owner_ship_id: String = "") -> void:
	missiles[missile_id] = missile
	missile_owners[missile_id] = owner_ship_id

func remove_missile(missile_id: String) -> void:
	missiles.erase(missile_id)
	missile_owners.erase(missile_id)

## Explicit shot trigger. Still callable directly (e.g. by a scenario
## script that wants to override AI target selection for one shot);
## `_resolve_weapons_ai` now also calls this automatically once a target
## has been AI-selected (see below).
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
	_resolve_formation_keeping(dt)
	_resolve_damage_response(dt)
	_resolve_weapons_ai(dt)
	_resolve_missile_launch_ai(dt)
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

## ТЗ §22 Point Defense + §26 Tactical AI. Target selection now goes
## through `TacticalAI.select_pd_target()`, which reads ONLY this ship's
## own sensor contacts (never a missile's true position/identity
## directly) -- fixing the earlier ground-truth-scanning placeholder.
## Prioritization beyond "nearest usable contact" (salvo size,
## time-to-impact, etc.) is still not implemented -- see tactical_ai.gd.
func _resolve_point_defense(dt: float) -> void:
	for ship_id in ships.keys():
		var mounts: Array = pd_mounts.get(ship_id, [])
		if mounts.is_empty():
			continue

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var selection: Dictionary = TacticalAI.select_pd_target(ship, contacts)
		var target_missile = selection.get("missile")
		var target_contact = selection.get("contact")

		for mount in mounts:
			PointDefenseResolution.engage(mount, ship, target_missile, dt, target_contact)

## Milestone 10 (Formation Command) first slice, AGENTS.md §61 "wall of
## battle / formation fighting": every non-guide member of a formation
## thrusts to hold a fixed station (offset in the GUIDE's own local
## frame, so the formation rotates with the guide rather than staying
## fixed to world axes) relative to its guide ship. Deliberately simple:
## thrust direction only (toward the desired world station), no separate
## velocity-matching/damping term yet, so a member can overshoot and
## oscillate around station rather than settling smoothly -- an honest
## gap, not hidden. A formation whose guide ship no longer exists (e.g.
## destroyed) is simply skipped this tick -- there is no fallback
## guide/reform logic yet (§29 "reform formations" remains open).
##
## Runs BEFORE `_resolve_damage_response` so a critically damaged member
## retreating overrides its formation station-keeping thrust for that
## tick (disengaging takes priority over holding the wall).
func _resolve_formation_keeping(dt: float) -> void:
	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]
		var guide: ShipPhysicsState = ships.get(formation.guide_ship_id)
		if guide == null:
			continue

		for member_id in formation.member_ids():
			if member_id == formation.guide_ship_id:
				continue
			var member: ShipPhysicsState = ships.get(member_id)
			if member == null:
				continue

			var offset_local: Vector3 = formation.member_offsets[member_id]
			var desired_world_position: Vector3 = guide.position + (guide.orientation * offset_local)
			var to_station: Vector3 = desired_world_position - member.position

			# ASSUMPTION: a small dead zone avoids thrust jitter once a
			# member is essentially on station -- no canonical figure,
			# chosen as a small fraction of a typical formation spacing.
			if to_station.length_squared() <= 1.0:
				member.commanded_thrust_local = Vector3.ZERO
				continue

			var to_station_world: Vector3 = to_station.normalized()
			member.commanded_thrust_local = member.orientation.inverse() * to_station_world

## §26 "respond to damage" / "retreat" / "disengage" -- first slice. A
## critically damaged ship (see CRITICAL_HULL_FRACTION) stops thrusting
## toward the fight and instead thrusts directly away from its own known
## (sensor-contact-based, no cheat vision) hostile contacts. If it has no
## usable hostile contact to retreat from, its commanded thrust is left
## untouched (there is nothing sensor-honest to retreat FROM yet).
## Firing is suppressed for a disengaging ship in `_resolve_weapons_ai`
## (checked there via the same `is_critically_damaged` call), not here --
## this function only handles movement.
func _resolve_damage_response(dt: float) -> void:
	for ship_id in ships.keys():
		var hull = hulls.get(ship_id)
		if not TacticalAI.is_critically_damaged(hull, CRITICAL_HULL_FRACTION):
			continue

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		var away_world: Vector3 = TacticalAI.select_retreat_vector_world(ship, contacts, hostile_ids)
		if away_world == Vector3.ZERO:
			continue
		ship.commanded_thrust_local = ship.orientation.inverse() * away_world

## ТЗ §17 Weapons + §26 Tactical AI ("select targets" / "use weapons").
## Each ship with at least one weapon mount and a team assigned picks the
## nearest usable hostile contact (via `TacticalAI.select_weapon_target`,
## sensor-limited) and fires every ready, arc-capable mount at it. A ship
## with no team, or no hostile contacts, does not fire -- there is no
## default-hostile fallback (see `is_hostile`).
func _resolve_weapons_ai(dt: float) -> void:
	for ship_id in ships.keys():
		var mounts: Array = weapon_mounts.get(ship_id, [])
		if mounts.is_empty():
			continue
		if not teams.has(ship_id) or teams[ship_id] == "":
			continue
		if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
			continue  # disengaging -- see _resolve_damage_response

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		if hostile_ids.is_empty():
			continue

		var selection: Dictionary = TacticalAI.select_weapon_target(ship, contacts, hostile_ids)
		var target_ship_id = selection.get("ship_id")
		if target_ship_id == null:
			continue

		for mount in mounts:
			fire_weapon(ship_id, mount, target_ship_id)

## §26 "launch missiles" -- first real launch DECISION (not just firing
## already-mounted weapons). Every tube always advances its own cooldown
## (`tube.advance(dt)`), even for a ship with no team/hostiles/that is
## disengaging, so ammo/cooldown bookkeeping stays correct regardless of
## whether the AI is currently choosing to shoot. Target selection reuses
## `TacticalAI.select_weapon_target` (same nearest-usable-hostile-contact
## rule, same "no cheat vision" -- distance is measured to the CONTACT's
## estimated position, not the target's true position) rather than a
## separate missile-specific selector, since there is no missile-specific
## targeting criterion implemented yet (see tactical_ai.gd HONEST SCOPE).
## A critically damaged/disengaging ship (see _resolve_damage_response)
## does not launch new missiles, same as it does not fire weapons.
func _resolve_missile_launch_ai(dt: float) -> void:
	for ship_id in ships.keys():
		var tubes: Array = missile_tubes.get(ship_id, [])
		if tubes.is_empty():
			continue
		for tube in tubes:
			tube.advance(dt)

		if not teams.has(ship_id) or teams[ship_id] == "":
			continue
		if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
			continue  # disengaging -- see _resolve_damage_response

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		if hostile_ids.is_empty():
			continue

		var selection: Dictionary = TacticalAI.select_weapon_target(ship, contacts, hostile_ids)
		var target_ship = selection.get("ship")
		var target_contact = selection.get("contact")
		if target_ship == null or target_contact == null:
			continue

		var distance: float = ship.position.distance_to(target_contact.estimated_position)
		for tube in tubes:
			if not tube.is_ready():
				continue
			if distance > tube.max_range_m:
				continue
			_launch_missile_from_tube(ship_id, ship, target_ship, tube)

## Constructs and registers a new offensive MissileState launched by
## `attacker` at `target`, then marks the launching tube as spent.
## Inherits the launching ship's velocity (a missile does not start from
## rest relative to the galaxy, only relative to its launch platform) --
## everything else uses MissileState's own defaults (drive/warhead/rod
## configuration), same as every other missile created in this codebase
## via `MissileState.new()`.
func _launch_missile_from_tube(attacker_ship_id: String, attacker: ShipPhysicsState, target, tube) -> void:
	var missile := MissileState.new()
	missile.position = attacker.position
	missile.velocity = attacker.velocity
	missile.target = target

	_next_ai_missile_id += 1
	var missile_id: String = "ai_missile_%d" % _next_ai_missile_id
	add_missile(missile_id, missile, attacker_ship_id)
	tube.mark_launched()

func _integrate_ships(dt: float) -> void:
	for ship_id in ships.keys():
		ships[ship_id].integrate(dt)

