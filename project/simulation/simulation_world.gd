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
const SubsystemType = preload("res://simulation/subsystem_type.gd")

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

## ASSUMPTION (§33 Formation Leader, step 4 "account for communication
## limitations" -- see FormationState.guide_lost_since for why this is
## deliberately NOT a light-speed command-lag figure per CANON_RULES.md
## §7). Seconds a formation waits, after its guide is first observed
## lost/incapacitated, before formally transferring command to a
## successor. Represents subordinate crews recognizing the loss and
## executing succession doctrine, not instant telepathic reorganization.
## No canonical Honorverse figure exists for this -- chosen as a small,
## game-feel value (a few seconds at 1x time scale) rather than tuned
## against any source.
const COMMAND_TRANSFER_DELAY_S: float = 3.0

var missiles: Dictionary = {}         # missile_id -> MissileState
var missile_owners: Dictionary = {}   # missile_id -> owning ship_id (String, may be "")
var _next_ai_missile_id: int = 0      # counter for AI-launched missile ids (see _resolve_missile_launch_ai)

## Total simulated time accumulated purely by successive `tick_simulation(dt)`
## calls (§43 Deterministic Simulation). Deliberately independent of
## `clock.sim_time` / the SceneTree, because tests (and any future
## scenario runner) call `tick_simulation` directly without a running
## Node tree, where `clock` is never initialized (`_ready()` never
## fires). Used by `_resolve_formation_keeping` to time
## COMMAND_TRANSFER_DELAY_S.
var world_sim_time: float = 0.0

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
	world_sim_time += dt
	_sync_subsystem_driven_conditions()
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

## ТЗ §25 Subsystem Damage: run once at the START of every tick, before
## any consumer (weapons fire, PD engagement, missile launch AI) reads a
## mount/tube's `condition` this tick, to sync WeaponMount.condition,
## PointDefenseMount.condition, and MissileTube.condition from their
## owning ship's own ShipSubsystems container (WEAPONS, POINT_DEFENSE,
## and MISSILE_SYSTEMS respectively). This is the direct implementation
## of what those fields' own doc comments already anticipated ("damaged
## by §25 later" / "not yet modeled here") -- closing 3 of the 8
## previously-honest "no consumer wired" subsystem-damage gaps recorded
## in ASSUMPTIONS.md/ship_subsystems.gd (COUNTER_MISSILE_SYSTEMS is the
## 4th, wired separately in `_resolve_counter_missile_intercepts()`,
## since a counter-missile's kill check has no per-tick "mount" of its
## own to hold a synced condition field on). A ship with no
## ShipSubsystems (`subsystems == null`, e.g. a test/scenario that never
## opted into §25) is left untouched -- its mounts/tubes keep whatever
## `condition` they were constructed or set with, identical to
## pre-this-change behavior. Deliberately a per-tick SNAPSHOT taken
## before this tick's own damage is applied (e.g. a weapon hit landing
## later in this same tick, during `_resolve_weapons_ai`) rather than
## reactive mid-tick coupling -- damage applied this tick is reflected
## starting NEXT tick, which keeps tick ordering simple and deterministic
## (ТЗ §43).
func _sync_subsystem_driven_conditions() -> void:
	for ship_id in ships.keys():
		var ship: ShipPhysicsState = ships[ship_id]
		if ship.subsystems == null:
			continue
		for mount in weapon_mounts.get(ship_id, []):
			mount.condition = ship.subsystems.get_condition(SubsystemType.Type.WEAPONS)
		for mount in pd_mounts.get(ship_id, []):
			mount.condition = ship.subsystems.get_condition(SubsystemType.Type.POINT_DEFENSE)
		for tube in missile_tubes.get(ship_id, []):
			tube.condition = ship.subsystems.get_condition(SubsystemType.Type.MISSILE_SYSTEMS)

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
##
## BUG FOUND AND FIXED THIS PASS: a counter-missile (missile.target is
## itself another MissileState, ТЗ §20) arms its warhead via the exact
## same generic distance-to-target check as an offensive missile
## (MissileState.integrate()'s arm-at-10%-of-terminal-range logic does
## not care what kind of object `target` is). Before this fix, once armed
## it fell into MissileResolution.resolve_detonation(), which
## unconditionally reads `target.defense` -- a property that exists on
## ShipPhysicsState but NOT on MissileState -- crashing with "Invalid
## access to property or key 'defense'" the first time a counter-missile
## closed within its own arm radius of an incoming missile inside the
## live per-tick loop. This was previously latent/undiscovered because
## every existing counter-missile test (test_counter_missile.gd) drives
## `integrate()`/`check_intercept()` directly, bypassing
## `SimulationWorld.tick_simulation()` entirely -- it only surfaced once
## this pass's new test exercised a counter-missile through the full
## world loop (test_subsystem_damage_consumers.gd). Counter-missiles
## never use laserhead/rod detonation (§21) against another missile --
## per CounterMissileResolution's class doc, a counter-missile kill is a
## wedge-vs-wedge overlap, resolved exclusively by
## `_resolve_counter_missile_intercepts()` -- so a missile whose target is
## another MissileState is now explicitly excluded from this laserhead
## detonation path, regardless of its own warhead_armed flag.
func _update_missiles(dt: float) -> void:
	for missile_id in missiles.keys():
		var missile = missiles[missile_id]
		if not missile.is_active():
			continue

		var thrust_dir: Vector3 = MissileGuidance.resolve_thrust_direction(missile, dt)
		missile.integrate(dt, thrust_dir)

		var is_counter_missile: bool = missile.target is MissileState
		if missile.warhead_armed and not missile.has_detonated and not is_counter_missile:
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
## ТЗ §25: the effective kill radius is scaled by the counter-missile's
## OWN LAUNCHING ship's COUNTER_MISSILE_SYSTEMS subsystem condition (via
## `missile_owners`, recorded at `add_missile()` time) -- see
## CounterMissileResolution's class doc for the INTERPRETATION this
## represents. An unowned counter-missile (owner_id == "", e.g. a test
## that never registered ownership) or one whose owner ship no longer
## exists defaults to condition 1.0, identical to pre-§25 behavior.
func _resolve_counter_missile_intercepts() -> void:
	for missile_id in missiles.keys():
		var missile = missiles[missile_id]
		if not missile.is_active():
			continue
		if missile.target is MissileState:
			var owner_ship: ShipPhysicsState = ships.get(missile_owners.get(missile_id, ""))
			var cm_condition: float = 1.0
			if owner_ship != null and owner_ship.subsystems != null:
				cm_condition = owner_ship.subsystems.get_condition(SubsystemType.Type.COUNTER_MISSILE_SYSTEMS)
			CounterMissileResolution.check_intercept(missile, missile.target, cm_condition)

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

## Milestone 10 (Formation Command) -- velocity-matching pass, ТЗ §29/
## §32 "maintain... relative position; velocity matching". Builds on the
## first slice (see CHANGELOG.md): every non-guide member of a formation
## now thrusts using a proportional-derivative law (position error AND
## velocity error towards the guide), replacing the earlier direction-
## only bang-bang thrust -- this closes the first slice's documented
## honest gap ("no separate velocity-matching/damping term yet, so a
## member can overshoot and oscillate around station"). ASSUMPTION:
## K_P_STATION/K_D_STATION are an engineering PD-controller tuning
## choice (heavily overdamped -- no canonical Honorverse station-keeping
## formula exists), not itself Honorverse canon -- see ASSUMPTIONS.md.
## Still NOT modeled (open item, unchanged from the first slice): the
## guide's own ANGULAR velocity sweeping a nonzero-offset slot through an
## arc (this only matches the guide's LINEAR velocity).
##
## §33 Formation Leader (this pass): a lost guide (destroyed/removed OR
## incapacitated -- see TacticalAI.is_guide_lost) now triggers a real
## succession sequence after a short recognition delay
## (COMMAND_TRANSFER_DELAY_S) instead of being silently skipped forever
## -- see the guide-lost branch below and `_transfer_formation_command`.
## Still NOT modeled: re-issuing/reshaping formation ORDERS (§29) after a
## leader change (member stations are frozen in place relative to the
## new guide, not replanned into a fresh geometric wall).
##
## Runs BEFORE `_resolve_damage_response` so a critically damaged member
## retreating overrides its formation station-keeping thrust for that
## tick (disengaging takes priority over holding the wall).
func _resolve_formation_keeping(dt: float) -> void:
	const K_P_STATION: float = 0.02
	const K_D_STATION: float = 0.9

	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]

		# §33 Formation Leader: guide destroyed/incapacitated handling
		# comes BEFORE ordinary station-keeping below, since a lost guide
		# means there is (for now) nobody to keep station on at all.
		if TacticalAI.is_guide_lost(formation.guide_ship_id, ships, hulls, CRITICAL_HULL_FRACTION):
			if formation.guide_lost_since < 0.0:
				formation.guide_lost_since = world_sim_time
			elif world_sim_time - formation.guide_lost_since >= COMMAND_TRANSFER_DELAY_S:
				var successor_id: String = TacticalAI.select_formation_successor(formation, ships, hulls, CRITICAL_HULL_FRACTION)
				if successor_id != "":
					_transfer_formation_command(formation, successor_id)
				# else: nobody left fit to lead -- §33 "do not magically
				# transfer information unavailable to subordinate ships"
				# means there is honestly nobody to hand command to; the
				# formation holds silently (no station-keeping thrust)
				# rather than inventing a successor.
			# Either way (still within the recognition delay, or just
			# transferred/failed to transfer this tick), skip ordinary
			# station-keeping for this formation this tick.
			continue
		else:
			formation.guide_lost_since = -1.0

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
			var velocity_error: Vector3 = guide.velocity - member.velocity

			# ASSUMPTION: a small dead zone avoids thrust jitter once a
			# member is essentially on station AND already velocity-
			# matched with the guide -- no canonical figure, chosen as a
			# small fraction of a typical formation spacing / a barely-
			# measurable speed difference.
			if to_station.length_squared() <= 1.0 and velocity_error.length_squared() <= 0.0001:
				member.commanded_thrust_local = Vector3.ZERO
				continue

			var max_accel: float = member.effective_max_acceleration()
			if max_accel <= 0.0:
				continue

			var desired_accel: Vector3 = to_station * K_P_STATION + velocity_error * K_D_STATION
			if desired_accel.length() > max_accel:
				desired_accel = desired_accel.normalized() * max_accel

			member.commanded_thrust_local = member.orientation.inverse() * (desired_accel / max_accel)

## §33 Formation Leader, steps 2-3 ("transfer command" / "update
## formation state"). Makes `new_guide_id` the formation's guide. Every
## remaining member's station offset is recomputed to FREEZE its current
## relative position to the new guide, expressed in the new guide's
## local/body frame, at the moment of transfer -- rather than reusing
## offsets that were only ever meaningful relative to the OLD guide's
## station plan. This avoids the "wall" snapping every member toward a
## nonsensical position built around the new leader; formation SHAPE as
## planned (§29 Formation Orders) is not preserved automatically, honestly
## left as a follow-up (re-issuing formation orders after a leader change
## is a player/AI decision, not something this transfer invents on its
## own). The old guide, if it still physically exists (e.g. incapacitated
## but not destroyed) and is not the new guide, is folded in as an
## ordinary member under the same freeze-in-place rule -- it keeps
## flying, just no longer in charge. A former member that no longer
## exists in `ships` (destroyed) is silently dropped rather than carried
## forward as a dangling station.
func _transfer_formation_command(formation: FormationState, new_guide_id: String) -> void:
	var new_guide: ShipPhysicsState = ships.get(new_guide_id)
	if new_guide == null:
		return  # should not happen (caller already validated), safe no-op

	var old_guide_id: String = formation.guide_ship_id
	var old_member_ids: Array = formation.member_ids()
	var inverse_orientation: Quaternion = new_guide.orientation.inverse()

	var new_offsets: Dictionary = {}
	for member_id in old_member_ids:
		if member_id == new_guide_id:
			continue
		var member: ShipPhysicsState = ships.get(member_id)
		if member == null:
			continue
		new_offsets[member_id] = inverse_orientation * (member.position - new_guide.position)

	if old_guide_id != new_guide_id and old_guide_id != "" and ships.has(old_guide_id):
		var old_guide: ShipPhysicsState = ships[old_guide_id]
		new_offsets[old_guide_id] = inverse_orientation * (old_guide.position - new_guide.position)

	formation.member_offsets = new_offsets
	formation.guide_ship_id = new_guide_id
	formation.guide_lost_since = -1.0

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

