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
const FormationOrder = preload("res://simulation/formation_order.gd")
const CommandEchelon = preload("res://simulation/command_echelon.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")
const IndividualCommandState = preload("res://simulation/individual_command_state.gd")
const ShipCombatDirective = preload("res://simulation/ship_combat_directive.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const ReplayLog = preload("res://simulation/replay_log.gd")
const KinematicsUtils = preload("res://simulation/kinematics_utils.gd")

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
## §28 Command Hierarchy (this pass, first slice): echelon_id -> CommandEchelon,
## an optional tree ABOVE `formations` (Fleet/Task Force/Squadron/Division/
## Element by default, but configurable -- see CommandEchelon class doc).
## Entirely unused by any pre-existing formation/ship code -- a scenario
## that never calls add_command_echelon behaves identically to before this
## pass.
var command_echelons: Dictionary = {}
var individual_orders: Dictionary = {}  # ship_id -> IndividualCommandState (§30/§31, Milestone 11 first slice)
var ship_combat_directives: Dictionary = {}  # ship_id -> ShipCombatDirective (§30 target/weapon mode, Milestone 11 second slice)
var _formation_assigned_targets: Dictionary = {}  # ship_id -> target_ship_id (§34.1 Doubling, rebuilt every tick by _resolve_formation_target_assignment, empty for ships with no governed formation)
## §34.2 Missile Time-on-Target coordination: ship_id -> {"fire_at":
## float world_sim_time, "target_ship_id": String}. UNLIKE
## `_formation_assigned_targets`, this is deliberately NOT cleared and
## rebuilt every tick -- a scheduled hold has to survive from the tick it
## is decided until the (possibly much later) tick it actually fires,
## the same "survives across ticks until consumed" convention already
## used by `_pending_command_transmissions` below. An entry is removed
## the instant it fires, or when `_resolve_missile_tot_coordination`
## finds it stale (ship gone/wrecked, or its §34.1 assigned target moved
## away from the one this schedule was built for). See
## `_resolve_missile_tot_coordination` / `_resolve_missile_launch_ai`.
var _missile_salvo_fire_at: Dictionary = {}
var _pending_command_transmissions: Array = []  # Array[Dictionary{ready_at:float, ship_id:String, callable:Callable}] -- §25/§31 communication-delayed individual orders, see transmit_individual_order_now/transmit_ship_target/etc. below

## ТЗ §45 Replay (Milestone 12): null (default) means recording is OFF,
## identical to every pre-existing test/scenario -- _record_command/
## _record_event below are no-ops until start_recording() is called.
var replay_log: ReplayLog = null

## ТЗ §56.1 item 3 (weapon-fire visualization): every energy-weapon shot
## actually fired THIS tick, for a renderer to poll after tick_simulation()
## -- pure already-resolved facts (attacker/target ids+positions, outcome,
## damage), per §42 "rendering only displays already-resolved simulation
## state". Cleared and rebuilt every tick_simulation() call.
## Deliberately SEPARATE from `_record_event`/`replay_log`: that log is a
## no-op unless start_recording() was called (Milestone 12 Replay,
## deprioritized -- see §56.1's OUT OF SCOPE list), but a live renderer
## needs this every tick regardless of whether replay recording is on.
## "Fired" means the mount actually consumed its recharge cycle (i.e. got
## past the NOT_READY/OUT_OF_RANGE/NO_ARC checks in WeaponResolution.fire),
## not just that it hit -- a blocked/attenuated shot still gets a visible
## beam, it just did not penetrate.
var last_tick_weapon_shots: Array = []  # Array[Dictionary]: {attacker_ship_id, target_ship_id, attacker_position: Vector3, target_position: Vector3, outcome: int, damage_dealt: float}

## Local tick counter, independent of SimClock.tick_count (most
## existing tests drive tick_simulation() directly without ever going
## through a SimClock), used only to timestamp replay commands/events.
var _tick_index: int = 0

## ASSUMPTION (§26 "retreat"/"disengage", no canonical figure found): a
## ship whose HullState integrity fraction drops to or below this stops
## firing offensively and instead thrusts away from its known hostile
## contacts. See TacticalAI.is_critically_damaged / select_retreat_vector_world.
const CRITICAL_HULL_FRACTION: float = 0.3
const MAX_USEFUL_ATTACKERS_PER_TARGET: int = 2  # §34.1 Doubling -- ASSUMPTION, see TacticalAI.select_formation_target_for_member doc comment

## §22.1 Formation mutual defensive coverage -- ASSUMPTION (no canonical
## figures for either; see _formation_bow_stern_coverage doc comment and
## ASSUMPTIONS.md for the full reasoning). A formation neighbor further
## than this from the ship being screened is not considered close enough
## to plausibly interpose its own defensive envelope -- station spacing
## used elsewhere in this codebase's own tests/scenarios is on the order
## of hundreds of meters (a tight "wall of battle"), so a multi-kilometer
## cap is deliberately generous rather than tuned tight. The cone half-
## width is independent of, and wider than,
## ShipDefenseState.BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD (15 deg) -- that
## constant is about how narrow an attack angle bypasses ONE ship's own
## raised sidewall; this one is about how far off-axis a COVERING
## NEIGHBOR can sit and still plausibly screen the gap, a geometrically
## distinct and looser question.
const FORMATION_COVERAGE_MAX_DISTANCE_M: float = 5000.0
const FORMATION_COVERAGE_CONE_HALF_WIDTH_RAD: float = deg_to_rad(30.0)

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

## §25 Damage "communications damage -> degraded command/reporting" +
## §31 "account for communication limitations" (both honestly-logged
## gaps from previous passes -- see ASSUMPTIONS.md -- closed together
## here, since they are the same underlying mechanic: a routine
## individual order/designation takes real time to reach the ship that
## must carry it out, and that time grows as the receiving ship's own
## COMMUNICATIONS subsystem degrades). Baseline seconds a routine order
## takes to reach a ship with FULLY INTACT communications, before
## `_resolve_individual_orders`/`_resolve_weapon_target` ever sees it.
## Deliberately much smaller than COMMAND_TRANSFER_DELAY_S (3.0s) --
## that constant models crews RECOGNIZING a major, uncertain event
## (their guide going silent) and working out succession doctrine; this
## constant models the mechanical/procedural latency of relaying a
## routine order within the same tactical formation while
## communications are healthy (bridge-to-bridge transmission, watch
## officer relay, helm/weapons acknowledgment) -- a smaller, different
## kind of delay. No canonical Honorverse figure exists for either;
## both are ASSUMPTIONs, not canon.
const INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S: float = 1.0

## Same floor-of-condition convention as PointDefenseMount/MissileTube's
## `_MIN_CONDITION_FOR_TIMING` (see those files): keeps the delay finite
## as COMMUNICATIONS condition approaches zero, while still letting it
## grow large well before that floor is reached.
const _MIN_CONDITION_FOR_COMMS_TIMING: float = 0.05

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
	individual_orders.erase(ship_id)
	ship_combat_directives.erase(ship_id)
	if not _pending_command_transmissions.is_empty():
		var kept: Array = []
		for entry in _pending_command_transmissions:
			if entry["ship_id"] != ship_id:
				kept.append(entry)
		_pending_command_transmissions = kept

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

## §29 Formation Orders via SimulationWorld (ТЗ §45 Replay, Milestone
## 12 slice): thin, ADDITIONAL wrappers around FormationState's own
## issue_order/issue_order_now/clear_orders. Calling FormationState
## directly (as every existing test/scenario still does) remains fully
## supported and unaffected -- these wrappers exist ONLY so formation
## orders funnel through a SimulationWorld-level choke point that CAN
## be recorded for replay (see _record_command below), the same reason
## transmit_individual_order_now funnels individual orders through
## this file instead of touching IndividualCommandState directly. A
## formation_id that does not exist is a safe no-op (nothing to record
## either -- there is no order to have taken effect).
func issue_formation_order(formation_id: String, order) -> void:
	var formation: FormationState = formations.get(formation_id)
	if formation == null:
		return
	_record_command("issue_formation_order", {"formation_id": formation_id, "order": order.to_dict()})
	formation.issue_order(order)

func issue_formation_orders(formation_id: String, orders: Array) -> void:
	var formation: FormationState = formations.get(formation_id)
	if formation == null:
		return
	for order in orders:
		_record_command("issue_formation_order", {"formation_id": formation_id, "order": order.to_dict()})
	formation.issue_orders(orders)

## Interrupt whatever `formation_id` is currently doing (or has
## queued) and start `order` immediately -- the SimulationWorld-level,
## recordable equivalent of FormationState.issue_order_now.
func issue_formation_order_now(formation_id: String, order) -> void:
	var formation: FormationState = formations.get(formation_id)
	if formation == null:
		return
	_record_command("issue_formation_order_now", {"formation_id": formation_id, "order": order.to_dict()})
	formation.issue_order_now(order)

func clear_formation_orders(formation_id: String) -> void:
	var formation: FormationState = formations.get(formation_id)
	if formation == null:
		return
	_record_command("clear_formation_orders", {"formation_id": formation_id})
	formation.clear_orders()

## §28 Command Hierarchy (this pass, first slice): register a
## CommandEchelon node. `parent_id`, if given, must already be a
## registered, non-leaf echelon (see CommandEchelon class doc) --
## otherwise this call push_errors and still registers `echelon_id`,
## but as a ROOT (empty parent_id), so a config mistake never silently
## drops the echelon itself, only its intended place in the tree.
## Self-parenting (`parent_id == echelon_id`) is refused the same way.
func add_command_echelon(echelon_id: String, kind: String, parent_id: String = "") -> CommandEchelon:
	var echelon := CommandEchelon.new()
	echelon.echelon_id = echelon_id
	echelon.kind = kind
	if parent_id != "":
		if parent_id == echelon_id:
			push_error("SimulationWorld.add_command_echelon: echelon '%s' cannot be its own parent" % echelon_id)
		else:
			var parent: CommandEchelon = command_echelons.get(parent_id)
			if parent == null:
				push_error("SimulationWorld.add_command_echelon: parent echelon '%s' not found for '%s'" % [parent_id, echelon_id])
			elif parent.is_leaf():
				push_error("SimulationWorld.add_command_echelon: parent echelon '%s' is a leaf (commands formation '%s'), cannot also have child echelons" % [parent_id, parent.commanded_formation_id])
			else:
				echelon.parent_id = parent_id
				parent.child_echelon_ids.append(echelon_id)
	command_echelons[echelon_id] = echelon
	return echelon

func get_command_echelon(echelon_id: String) -> CommandEchelon:
	return command_echelons.get(echelon_id)

## Make `echelon_id` a LEAF node directly commanding `formation_id` (see
## CommandEchelon class doc). Refused (push_error, no-op) if the echelon
## already has child echelons -- an echelon is either internal OR a
## leaf, never both. `formation_id` need not already exist in
## `formations` (consistent with add_formation's own "guide need not
## exist yet" flexibility) -- checked live by
## _collect_formation_ids_under_echelon/issue_echelon_order.
func attach_formation_to_echelon(echelon_id: String, formation_id: String) -> void:
	var echelon: CommandEchelon = command_echelons.get(echelon_id)
	if echelon == null:
		push_error("SimulationWorld.attach_formation_to_echelon: echelon '%s' not found" % echelon_id)
		return
	if not echelon.child_echelon_ids.is_empty():
		push_error("SimulationWorld.attach_formation_to_echelon: echelon '%s' has child echelons, cannot also command a formation directly" % echelon_id)
		return
	echelon.commanded_formation_id = formation_id

## Recursive, cycle-safe walk of `echelon_id`'s subtree collecting every
## LEAF's `commanded_formation_id` (deduplicated, insertion order --
## deterministic, ТЗ §43). An echelon that does not exist, or a subtree
## with no leaves yet (e.g. freshly created internal echelons with no
## children attached), safely yields an empty Array rather than an
## error -- issue_echelon_order then simply cascades to nobody.
func _collect_formation_ids_under_echelon(echelon_id: String) -> Array:
	var visited: Dictionary = {}
	var result: Array = []
	_collect_formation_ids_recursive(echelon_id, visited, result)
	return result

func _collect_formation_ids_recursive(echelon_id: String, visited: Dictionary, result: Array) -> void:
	if visited.has(echelon_id):
		return
	visited[echelon_id] = true
	var echelon: CommandEchelon = command_echelons.get(echelon_id)
	if echelon == null:
		return
	if echelon.is_leaf():
		if not result.has(echelon.commanded_formation_id):
			result.append(echelon.commanded_formation_id)
		return
	for child_id in echelon.child_echelon_ids:
		_collect_formation_ids_recursive(child_id, visited, result)

## §28 Command Hierarchy (this pass, first slice): cascade `order` down
## to every formation subordinate to `echelon_id`'s subtree, via the
## same per-formation `issue_order` FormationState already exposes -- an
## echelon-level order is exactly "issue this same intention to every
## formation under my command", nothing more. INTERPRETATION, not
## canon: no Honorverse source specifies the exact mechanics of how a
## fleet-level order propagates to individual formations; "identical
## order, fanned out to every subordinate formation" is the most direct
## reading of §29's order list applying at any echelon, not a numeric
## assumption -- see ASSUMPTIONS.md.
##
## Recorded ONCE at the echelon level for replay (see
## apply_recorded_command below) rather than once per formation, so
## replay re-derives the recipient set from whatever the command
## hierarchy looks like AT REPLAY TIME -- consistent with how
## issue_formation_order already re-looks-up its formation_id live
## rather than baking in a snapshot.
##
## Each recipient formation gets its OWN independent clone of `order`
## (via FormationOrder.to_dict()/from_dict() round-trip -- already
## tested, see test_replay_log.gd), never the same shared object
## instance -- required because some order kinds mutate themselves
## per-tick against ONE specific guide (APPROACH recomputes
## target_velocity_mps from the guide's live position every tick, see
## _resolve_formation_orders) or carry formation-specific data
## (CHANGE_FORMATION's new_offsets_local); sharing one instance across
## formations with different guides/rosters would corrupt whichever
## formation's tick happened to run last.
func issue_echelon_order(echelon_id: String, order) -> void:
	if not command_echelons.has(echelon_id):
		return
	_record_command("issue_echelon_order", {"echelon_id": echelon_id, "order": order.to_dict()})
	var formation_ids: Array = _collect_formation_ids_under_echelon(echelon_id)
	for formation_id in formation_ids:
		var formation: FormationState = formations.get(formation_id)
		if formation == null:
			continue
		formation.issue_order(FormationOrder.from_dict(order.to_dict()))

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

## ТЗ §63.1 INTERPRETATION: a wreck is excluded here, so it is never
## selected as a weapon/PD/missile/retreat-threat target by anyone --
## §63.1 says a wreck "is no longer a ship for any combat... purpose",
## which this codebase reads as including "worth shooting at", not
## just "able to shoot back". It remains a normal SENSOR contact
## (still tracked by _update_sensors) -- only its combat-targeting
## eligibility changes here.
func _hostile_ship_ids(ship_id: String) -> Array:
	var result: Array = []
	for other_id in ships.keys():
		if other_id == ship_id:
			continue
		if ships[other_id].is_wreck:
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

## ТЗ §45 Replay (Milestone 12): begin recording every command issued
## through this world's public order-issuing API and every event
## recorded via _record_event, from this tick onward. `seed` is stored
## on the log for forward compatibility (see ReplayLog class doc) --
## nothing in this simulation currently reads it back, since there is
## no unseeded randomness anywhere to seed. Calling this again simply
## replaces any log already being recorded (starts fresh).
func start_recording(seed: int = 0) -> void:
	replay_log = ReplayLog.new()
	replay_log.random_seed = seed

## Stops recording (if any) and returns the completed log, or null if
## recording was never started. Safe to call unconditionally.
func stop_recording() -> ReplayLog:
	var finished := replay_log
	replay_log = null
	return finished

func _record_command(command_name: String, args: Dictionary) -> void:
	if replay_log == null:
		return
	replay_log.record_command(_tick_index, world_sim_time, command_name, args)

func _record_event(event_type: String, data: Dictionary) -> void:
	if replay_log == null:
		return
	replay_log.record_event(_tick_index, world_sim_time, event_type, data)

## ТЗ §45 Replay: replays one entry from a ReplayLog.commands array
## (as produced by _record_command) by dispatching it back to the
## matching public SimulationWorld API, reconstructing any order
## object from its to_dict() form via IndividualOrder.from_dict/
## FormationOrder.from_dict. Intended use: rebuild a fresh
## SimulationWorld with the SAME initial ship/formation/mount setup a
## scenario script already constructs (recording is deterministic,
## not a snapshot of setup -- see ReplayLog class doc), then call this
## once per recorded command, interleaved with tick_simulation() calls
## so each command lands on its own recorded tick. Does NOT replay
## `events` (those are a RECORD of what happened, produced by the
## simulation itself, not inputs to replay). An unrecognized command
## name is skipped with a warning rather than crashing (e.g. a log
## written by a future version with a command this version does not
## know).
func apply_recorded_command(entry: Dictionary) -> void:
	var command_name: String = entry.get("name", "")
	var args: Dictionary = entry.get("args", {})
	match command_name:
		"issue_individual_order_now":
			issue_individual_order_now(args["ship_id"], IndividualOrder.from_dict(args["order"]))
		"return_ship_to_formation":
			return_ship_to_formation(args["ship_id"])
		"transmit_individual_order_now":
			transmit_individual_order_now(args["ship_id"], IndividualOrder.from_dict(args["order"]))
		"transmit_ship_target":
			transmit_ship_target(args["ship_id"], args["target_ship_id"])
		"transmit_clear_ship_target":
			transmit_clear_ship_target(args["ship_id"])
		"transmit_ship_weapons_free":
			transmit_ship_weapons_free(args["ship_id"], args["is_free"])
		"transmit_return_ship_to_formation":
			transmit_return_ship_to_formation(args["ship_id"])
		"set_ship_target":
			set_ship_target(args["ship_id"], args["target_ship_id"])
		"clear_ship_target":
			clear_ship_target(args["ship_id"])
		"set_ship_weapons_free":
			set_ship_weapons_free(args["ship_id"], args["is_free"])
		"order_missile_launch":
			order_missile_launch(args["ship_id"], args.get("target_ship_id", ""))
		"issue_formation_order":
			issue_formation_order(args["formation_id"], FormationOrder.from_dict(args["order"]))
		"issue_formation_order_now":
			issue_formation_order_now(args["formation_id"], FormationOrder.from_dict(args["order"]))
		"clear_formation_orders":
			clear_formation_orders(args["formation_id"])
		"issue_echelon_order":
			issue_echelon_order(args["echelon_id"], FormationOrder.from_dict(args["order"]))
		_:
			push_warning("SimulationWorld.apply_recorded_command: unknown command '%s', skipped" % command_name)

## ТЗ §25/§37 "ship lost"/"target destroyed" (Milestone 12): a ship
## whose HullState (still the single-scalar §58 placeholder pool)
## reached zero integrity by the END of the previous tick is removed
## from the world at the START of this one -- the same "cleanup lags
## by one tick, applied before anything this tick reads world state"
## convention `_cleanup_inactive_missiles` already uses for missiles,
## so damage that kills a ship is still fully visible (sensors,
## targeting, this replay event) for the tick it lands on, and
## removal never races a same-tick kill shot. This closes a
## previously-honest gap: `HullState.is_destroyed()` existed and was
## already READ by formation-leader-loss logic, but nothing in the
## tick loop ever actually removed a destroyed ship from `ships` --
## it would keep being sensed, targeted, and integrated forever. A
## ship with no HullState at all (most existing tests/scenarios never
## attach one) is never auto-destroyed, identical to before this pass.
## ТЗ §63.1 (AGENTS.md, added after this mechanic's first slice):
## "a destroyed ship must NOT be deleted or vanish from the simulated
## world -- it becomes a wreck". This SUPERSEDES this function's
## original implementation, which called `remove_ship()` (full
## deletion) -- that was flagged as a documented spec violation in
## ASSUMPTIONS.md and is fixed here. A newly-destroyed ship instead:
##   * gets `ship.is_wreck = true` (checked -- not re-checked, see the
##     `not ship.is_wreck` guard below -- by every combat/command/AI
##     resolver in this file, so a wreck is permanently excluded from
##     firing, launching, defending, maneuvering-on-command, and
##     being selected as a hostile target/formation guide);
##   * has `commanded_thrust_local` zeroed ONCE, here -- no crew left
##     to hold a heading, but existing `velocity`/`angular_velocity`
##     are left completely untouched, so `_integrate_ships` keeps
##     carrying it forward under pure momentum (ТЗ §12), exactly like
##     a live ship that stopped thrusting;
##   * is dropped from every formation's membership (pre-existing
##     `FormationState.remove_member`, as before this pass) and from
##     `individual_orders`/`ship_combat_directives` ("cannot be given
##     orders", §63.1) and `ecm_states` (no crew left to run a
##     jammer) -- but STAYS in `ships`/`hulls`/`sensor_contacts`/
##     `teams`, since §63.1 explicitly requires it to remain a valid
##     sensor contact and a persistent, identifiable object.
## Retention/pruning policy (§63.2 -- how long a wreck should
## eventually be removed, if ever) is explicitly UNKNOWN/deferred,
## see ASSUMPTIONS.md -- this function never prunes a wreck itself.
func _resolve_ship_destruction() -> void:
	var destroyed_ids: Array = []
	for ship_id in ships.keys():
		var ship: ShipPhysicsState = ships[ship_id]
		if ship.is_wreck:
			continue  # already processed -- hull stays destroyed forever, never re-trigger
		var hull = hulls.get(ship_id)
		if hull != null and hull.is_destroyed():
			destroyed_ids.append(ship_id)
	for ship_id in destroyed_ids:
		_record_event("ship_destroyed", {"ship_id": ship_id})
		var ship: ShipPhysicsState = ships[ship_id]
		ship.is_wreck = true
		ship.commanded_thrust_local = Vector3.ZERO
		for formation_id in formations.keys():
			formations[formation_id].remove_member(ship_id)
		individual_orders.erase(ship_id)
		ship_combat_directives.erase(ship_id)
		ecm_states.erase(ship_id)

## Explicit shot trigger. Still callable directly (e.g. by a scenario
## script that wants to override AI target selection for one shot);
## `_resolve_weapons_ai` now also calls this automatically once a target
## has been AI-selected (see below).
func fire_weapon(attacker_ship_id: String, mount, target_ship_id: String):
	var attacker = ships.get(attacker_ship_id)
	var target = ships.get(target_ship_id)
	if attacker == null or target == null:
		return null
	var formation_coverage: Dictionary = _formation_bow_stern_coverage(target_ship_id)
	var result = WeaponResolution.fire(attacker, mount, target, hulls.get(target_ship_id), target.subsystems, formation_coverage)
	if result != null and result.outcome == WeaponResolution.Outcome.HIT_UNPROTECTED and result.damage_dealt > 0.0:
		_record_event("weapon_hit", {"attacker_ship_id": attacker_ship_id, "target_ship_id": target_ship_id, "damage_dealt": result.damage_dealt})
	if result != null and result.outcome != WeaponResolution.Outcome.NOT_READY and result.outcome != WeaponResolution.Outcome.OUT_OF_RANGE and result.outcome != WeaponResolution.Outcome.NO_ARC:
		# §56.1 item 3: the mount actually fired this tick (recharge cycle
		# consumed) -- record it for the renderer regardless of whether it
		# penetrated, mirrors WeaponResolution.fire's own "shot is fired"
		# comment just above `mount.trigger_cooldown()`.
		last_tick_weapon_shots.append({
			"attacker_ship_id": attacker_ship_id,
			"target_ship_id": target_ship_id,
			"attacker_position": attacker.position,
			"target_position": target.position,
			"outcome": result.outcome,
			"damage_dealt": result.damage_dealt,
		})
	return result

func _on_simulation_tick(dt: float, _tick: int, _sim_time: float) -> void:
	tick_simulation(dt)

## The actual per-tick integration of every module, exposed as a plain
## method (not gated behind the SimClock/Node signal) so tests -- and any
## future scenario runner -- can drive it directly without a SceneTree.
func tick_simulation(dt: float) -> void:
	_tick_index += 1
	world_sim_time += dt
	last_tick_weapon_shots.clear()
	_resolve_pending_command_transmissions()
	_sync_subsystem_driven_conditions()
	_cleanup_inactive_missiles()
	_resolve_ship_destruction()
	_update_sensors(dt)
	_update_missiles(dt)
	_resolve_counter_missile_intercepts()
	_resolve_point_defense(dt)
	_resolve_formation_orders(dt)
	_resolve_formation_keeping(dt)
	_resolve_individual_orders(dt)
	_resolve_damage_response(dt)
	_resolve_formation_target_assignment(dt)
	_resolve_missile_tot_coordination(dt)
	_resolve_weapons_ai(dt)
	_resolve_missile_launch_ai(dt)
	_resolve_crossing_t_maneuver(dt)
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
		if observer.is_wreck:
			continue  # §63.1: a wreck has no crew/power to operate sensors -- it can still be SENSED by others (see the inner loop below), just cannot sense anything itself
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
			var target_formation_coverage: Dictionary = {}
			for ship_id in ships.keys():
				if ships[ship_id] == target:
					target_hull = hulls.get(ship_id)
					target_subsystems = ships[ship_id].subsystems
					target_formation_coverage = _formation_bow_stern_coverage(ship_id)
					break
			MissileResolution.resolve_detonation(missile, target_hull, target_subsystems, target_formation_coverage.get("bow", false), target_formation_coverage.get("stern", false))

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
		if ships[ship_id].is_wreck:
			continue  # §63.1: a wreck has no crew/power to operate point defense
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

## §29 Formation Orders / §35 Command Queue (Milestone 10, this pass):
## translates a formation's active FormationOrder into the GUIDE ship's
## own `commanded_thrust_local`, before ordinary station-keeping (below)
## makes every member chase wherever the guide ends up. A formation with
## no current/queued order is a complete no-op here -- the guide's thrust
## is left exactly as whatever set it before (scenario setup, or nothing
## at all), identical to every prior pass's behavior.
##
## Execution law: rather than bang-bang-always-full-thrust (which, given
## this codebase's existing ship accelerations -- often hundreds of g --
## would overshoot a modest target velocity change wildly in a single
## tick and then oscillate forever chasing the flipped error) or a
## PD-with-tuned-gains controller (which needs per-scenario tuning, see
## the station-keeping K_P_STATION/K_D_STATION above), this uses an
## EXACT-STOP clamp: accelerate at full available thrust MAGNITUDE only
## up to whatever this tick's `dt` can deliver without passing the
## target velocity (`error.length() / dt`), so the guide always reaches
## (never overshoots) its ordered course/speed, converging in a bounded
## number of ticks with no oscillation and no tuning constants. This is
## an ENGINEERING CHOICE (ASSUMPTION), not itself Honorverse canon -- no
## source specifies how helm crews execute a course/speed order; see
## ASSUMPTIONS.md.
func _resolve_formation_orders(dt: float) -> void:
	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]
		var guide: ShipPhysicsState = ships.get(formation.guide_ship_id)
		if guide == null:
			continue

		if formation.current_order == null:
			if formation.order_queue.is_empty():
				continue
			formation.current_order = formation.order_queue.pop_front()

		var order: FormationOrder = formation.current_order

		# HOLD_FORMATION is a standing order (§29 "hold formation"): it
		# never auto-completes/dequeues on its own -- it stays active,
		# actively zeroing the guide's own maneuver thrust every tick,
		# until something else explicitly replaces it (issue_order_now)
		# or a NEW order is queued behind it.
		if order.kind == FormationOrder.Kind.HOLD_FORMATION:
			guide.commanded_thrust_local = Vector3.ZERO
			continue

		# §29 "change formation": a re-tasking order, not a guide maneuver --
		# it does not touch commanded_thrust_local at all (the guide's course
		# continues whatever it was already doing). Applied once, then
		# immediately dequeued; see _apply_change_formation's doc comment for
		# why the actual flying-into-station is left to the pre-existing
		# station-keeping PD controller rather than a new maneuver mechanic.
		if order.kind == FormationOrder.Kind.CHANGE_FORMATION:
			_apply_change_formation(formation, order)
			formation.current_order = null
			continue

		# §29 "approach" (this pass): unlike CHANGE_COURSE/CHANGE_SPEED,
		# whose target_velocity_mps is frozen once at issue time, APPROACH
		# tracks a fixed world-space POINT -- the correct heading to that
		# point changes every tick as the guide's own position changes, so
		# target_velocity_mps must be refreshed here BEFORE the generic
		# is_complete()/thrust-error code below (which is otherwise
		# unmodified and shared with every other kind). is_complete() for
		# APPROACH does not depend on target_velocity_mps at all (it checks
		# arrival distance, not velocity), so recomputing first is safe.
		if order.kind == FormationOrder.Kind.APPROACH:
			order.target_velocity_mps = _approach_target_velocity(guide, order)

		if order.is_complete(guide):
			formation.current_order = null
			guide.commanded_thrust_local = Vector3.ZERO
			continue

		var max_accel: float = guide.effective_max_acceleration()
		if max_accel <= 0.0:
			continue

		var velocity_error: Vector3 = order.target_velocity_mps - guide.velocity
		var error_mag: float = velocity_error.length()
		if error_mag <= 0.0001:
			continue
		var desired_accel_mag: float = min(max_accel, error_mag / dt)
		var desired_accel: Vector3 = velocity_error.normalized() * desired_accel_mag
		guide.commanded_thrust_local = guide.orientation.inverse() * (desired_accel / max_accel)

## §29 "approach" (this pass): the guide's desired velocity for an
## APPROACH order, recomputed fresh every tick from the guide's CURRENT
## position -- pure pursuit of a fixed point, at the order's fixed
## `approach_speed_mps`. Guards against normalizing a zero-length
## direction (guide sitting exactly on the target point) by returning
## Vector3.ZERO instead -- harmless even though this can only actually
## arise well inside is_complete()'s much larger arrival_tolerance_m, at
## which point the caller dequeues the order right after this call
## anyway without ever acting on the zero velocity. ENGINEERING CHOICE
## (ASSUMPTION), not canon: no Honorverse source describes how a
## formation "approach" order is flown; pure pursuit (aim directly at the
## current target point, not a lead/intercept solution) matches how
## CHANGE_COURSE already treats a one-shot heading order, and reuses the
## same exact-stop thrust law as every other kinematic order kind rather
## than inventing a bespoke navigation law -- see ASSUMPTIONS.md.
func _approach_target_velocity(guide: ShipPhysicsState, order: FormationOrder) -> Vector3:
	var to_target: Vector3 = order.target_point_world - guide.position
	if to_target.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_target.normalized() * order.approach_speed_mps

## §29 "change formation" (this pass): applies a CHANGE_FORMATION order's
## `new_offsets_local` to `formation.member_offsets` (only the ships
## named as keys are reassigned -- see FormationOrder.new_offsets_local's
## doc comment; anyone else already in the formation keeps their current
## station untouched), then captures the RESULTING full shape as the
## formation's new `design_offsets` baseline.
##
## Deliberately does NOT teleport any ship or touch anyone's
## commanded_thrust_local -- retargeting `member_offsets` is the entire
## effect. The existing station-keeping PD controller in
## `_resolve_formation_keeping` (unchanged by this pass) picks up the new
## target next tick and flies each member there exactly as it already
## flies members onto their design stations after a leader transfer --
## this order is "what the new shape is", not "how to get there".
## ENGINEERING CHOICE (ASSUMPTION), not canon: no Honorverse source
## describes the mechanics of a "reform formation" order; reusing the
## same convergence law formation-keeping already uses (rather than a
## bespoke maneuver/timeline for reshaping) is simplicity/consistency
## (§43), not a numeric claim -- see ASSUMPTIONS.md.
##
## Overwriting `design_offsets` with the POST-order shape (not just
## leaving the old design in place) is deliberate: a deliberate reshape
## is itself a new "plan" for the formation, so a LATER leader transfer
## should re-plan survivors around the shape just ordered, not silently
## revert to whatever shape predates this order.
func _apply_change_formation(formation: FormationState, order: FormationOrder) -> void:
	for ship_id in order.new_offsets_local.keys():
		formation.member_offsets[ship_id] = order.new_offsets_local[ship_id]

	var refreshed_design: Dictionary = {formation.guide_ship_id: Vector3.ZERO}
	for ship_id in formation.member_offsets.keys():
		refreshed_design[ship_id] = formation.member_offsets[ship_id]
	formation.design_offsets = refreshed_design

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
## Milestone 10 (this pass): the guide's own ANGULAR velocity is now
## accounted for too -- a station point at a nonzero offset from a
## rotating guide is itself moving (rigid-body kinematics,
## v_station = v_guide + omega x r), so the previous linear-velocity-only
## matching term made a member at a wide offset perpetually "chase" a
## guide that was simply turning, thrusting against its own turn-rate
## instead of tracking the swept slot. This closes that previously-open
## gap; see the offset_world/station_point_velocity computation below and
## ASSUMPTIONS.md for the rigid-body-kinematics framing (not itself new
## Honorverse canon, just applying the same v = v_cg + omega x r identity
## KinematicsUtils/ShipPhysicsState already use elsewhere).
##
## §33 Formation Leader: a lost guide (destroyed/removed OR incapacitated
## -- see TacticalAI.is_guide_lost) triggers a real succession sequence
## after a short recognition delay (COMMAND_TRANSFER_DELAY_S) instead of
## being silently skipped forever -- see the guide-lost branch below and
## `_transfer_formation_command`. §29 Formation Orders (this pass):
## `_transfer_formation_command` now RE-PLANS surviving members into the
## formation's originally-designed relative geometry around the new
## guide (closing the wall), instead of freezing each member wherever it
## physically happened to be at the moment of transfer -- see
## FormationState.design_offsets and `_transfer_formation_command`'s doc
## comment for the mechanism and its honest fallback case.
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
		#
		# §33.1 Autonomous behavior during the succession window: for
		# EVERY member of this formation, for every tick from the very
		# first tick the guide is found lost (even before
		# `guide_lost_since` is set, below) through the end of
		# `COMMAND_TRANSFER_DELAY_S`, this loop deliberately issues them
		# NO new station-keeping command at all (the `continue` below
		# skips the member loop that would otherwise run further down
		# this function) rather than zeroing their thrust or driving them
		# toward a now-meaningless station relative to a lost guide. This
		# is a deliberate implementation of §33.1's three requirements,
		# not an accidental side effect of the early `continue`:
		#   * "hold its current tactical vector" -- `commanded_thrust_
		#     local` is a per-tick command, never reset to zero by
		#     default (see ShipPhysicsState), so a member that receives
		#     no new command here simply keeps flying on whatever thrust
		#     vector this same function last gave it the tick before the
		#     guide was lost (or whatever an active IndividualOrder/
		#     damage-response retreat is separately commanding it --
		#     both `_resolve_individual_orders` and
		#     `_resolve_damage_response` run AFTER this function every
		#     tick regardless of formation/guide state and are free to
		#     override, exactly as they already do outside this window);
		#   * "keep engaging its last AI-assigned target" -- weapons/
		#     missile-launch AI (`_resolve_weapons_ai`/
		#     `_resolve_missile_launch_ai`) and `ship_combat_directives`
		#     manual target designations have no coupling to formation
		#     guide status anywhere in this file, so target engagement
		#     genuinely continues unaffected through the whole window;
		#   * "keep covering/screening a neighboring ship" -- since this
		#     member's velocity/thrust are not perturbed, its position
		#     relative to its neighbors does not suddenly jump during the
		#     (short, engineering-tuned) recognition delay either.
		# See test_formation.gd's
		# `_test_succession_window_member_holds_last_commanded_thrust`
		# and `_test_succession_window_manual_target_designation_
		# survives_guide_loss` for tests that lock this behavior in.
		if TacticalAI.is_guide_lost(formation.guide_ship_id, ships, hulls, CRITICAL_HULL_FRACTION):
			if formation.guide_lost_since < 0.0:
				formation.guide_lost_since = world_sim_time
			elif world_sim_time - formation.guide_lost_since >= COMMAND_TRANSFER_DELAY_S:
				var successor_id: String = TacticalAI.select_formation_successor(formation, ships, hulls, CRITICAL_HULL_FRACTION)
				if successor_id != "":
					_transfer_formation_command(formation_id, formation, successor_id)
				# else: nobody left fit to lead -- §33 "do not magically
				# transfer information unavailable to subordinate ships"
				# means there is honestly nobody to hand command to; the
				# formation holds silently (no station-keeping thrust)
				# rather than inventing a successor.
			# Either way (still within the recognition delay, or just
			# transferred/failed to transfer this tick), skip ordinary
			# station-keeping for this formation this tick -- see the
			# §33.1 block comment above for why this IS the succession-
			# window behavior, not a placeholder.
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
			var offset_world: Vector3 = guide.orientation * offset_local
			var desired_world_position: Vector3 = guide.position + offset_world
			var to_station: Vector3 = desired_world_position - member.position
			# Rigid-body kinematics: a point at `offset_world` from the
			# guide's center of mass is itself moving at
			# guide.velocity + guide.angular_velocity x offset_world when
			# the guide is turning, not just guide.velocity. Matching only
			# the guide's linear velocity (the old formula) made a member
			# at a wide offset see a constant, spurious velocity error
			# while the guide simply rotated in place -- this feedforward
			# term cancels that out so the member tracks the swept slot
			# instead of fighting the guide's turn.
			var station_point_velocity: Vector3 = guide.velocity + guide.angular_velocity.cross(offset_world)
			var velocity_error: Vector3 = station_point_velocity - member.velocity

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
## formation state") + §29 Formation Orders ("re-plan the wall" after a
## leader change). Makes `new_guide_id` the formation's guide.
##
## The first time ANY transfer happens on a formation, its pre-transfer
## `member_offsets` (plus the old guide at an implicit ZERO offset) are
## captured once into `FormationState.design_offsets` -- the formation's
## ORIGINALLY PLANNED relative geometry, e.g. the spacing of a "wall of
## battle" -- and never overwritten again by later transfers. Every
## surviving ship that has a design entry then gets a REPLANNED offset
## around the new guide: `design_offsets[ship] - design_offsets[new_guide]`,
## i.e. the same relative geometry the formation was always flying,
## simply re-centered on whoever is now in the lead (a 3-ship line losing
## its lead ship closes up into a 2-ship line at the original spacing,
## rather than snapping to wherever the survivors physically drifted
## during the recognition delay).
##
## Honest fallback: a ship with NO design entry (it joined the formation
## AFTER a design was already captured, e.g. reinforcements) has no
## planned geometry to preserve, so it keeps the previous behavior --
## freeze its actual current position relative to the new guide. When
## that fallback is used for anyone this call, the resulting offsets are
## captured as a FRESH design baseline so the NEXT transfer has real
## geometry to replan from instead of repeating the freeze forever.
##
## The old guide, if it still physically exists (e.g. incapacitated but
## not destroyed) and is not the new guide, is folded in as an ordinary
## member under the same replan-or-freeze rule -- it keeps flying, just
## no longer in charge. A former member that no longer exists in `ships`
## (destroyed) is silently dropped rather than carried forward as a
## dangling station.
func _transfer_formation_command(formation_id: String, formation: FormationState, new_guide_id: String) -> void:
	var new_guide: ShipPhysicsState = ships.get(new_guide_id)
	if new_guide == null:
		return  # should not happen (caller already validated), safe no-op

	var old_guide_id: String = formation.guide_ship_id
	_record_event("formation_leader_lost", {"formation_id": formation_id, "old_guide_id": old_guide_id, "new_guide_id": new_guide_id})
	var old_member_ids: Array = formation.member_ids()
	var inverse_orientation: Quaternion = new_guide.orientation.inverse()

	# §29: lazily capture the pre-transfer shape as the formation's
	# permanent "design" the first time a transfer ever happens, so it
	# survives this and future transfers overwriting `member_offsets`.
	if formation.design_offsets.is_empty():
		var design: Dictionary = {old_guide_id: Vector3.ZERO}
		for member_id in old_member_ids:
			design[member_id] = formation.member_offsets[member_id]
		formation.design_offsets = design

	var can_replan: bool = formation.design_offsets.has(new_guide_id)
	var new_guide_design: Vector3 = formation.design_offsets.get(new_guide_id, Vector3.ZERO)

	var carried_ids: Array = old_member_ids.duplicate()
	if old_guide_id != new_guide_id and old_guide_id != "" and ships.has(old_guide_id):
		carried_ids.append(old_guide_id)

	var new_offsets: Dictionary = {}
	var fully_replanned: bool = can_replan
	for ship_id in carried_ids:
		if ship_id == new_guide_id:
			continue
		var ship: ShipPhysicsState = ships.get(ship_id)
		if ship == null:
			continue
		if can_replan and formation.design_offsets.has(ship_id):
			new_offsets[ship_id] = formation.design_offsets[ship_id] - new_guide_design
		else:
			fully_replanned = false
			new_offsets[ship_id] = inverse_orientation * (ship.position - new_guide.position)

	formation.member_offsets = new_offsets
	formation.guide_ship_id = new_guide_id
	formation.guide_lost_since = -1.0

	# Honest fallback follow-up: if this transfer couldn't fully replan
	# from the existing design (some carried ship had no design entry),
	# the freeze-in-place result becomes the new design baseline so a
	# FUTURE transfer has real geometry to preserve instead of repeating
	# the freeze fallback on every single leader change.
	if not fully_replanned:
		var refreshed_design: Dictionary = {new_guide_id: Vector3.ZERO}
		for ship_id in new_offsets.keys():
			refreshed_design[ship_id] = new_offsets[ship_id]
		formation.design_offsets = refreshed_design

## §30 Individual Ship Orders / §31 Individual Override (Milestone 11,
## first slice). Returns this ship's IndividualCommandState, creating an
## empty (inactive) one on first use so callers don't need to special-case
## "this ship has never been individually ordered before".
func _get_or_create_individual_command_state(ship_id: String) -> IndividualCommandState:
	if not individual_orders.has(ship_id):
		individual_orders[ship_id] = IndividualCommandState.new()
	return individual_orders[ship_id]

## §35 Command Queue at the single-ship level: queue an order to run once
## this ship's current order (and anything already queued) completes.
func issue_individual_order(ship_id: String, order: IndividualOrder) -> void:
	_get_or_create_individual_command_state(ship_id).issue_order(order)

func issue_individual_orders(ship_id: String, orders: Array) -> void:
	_get_or_create_individual_command_state(ship_id).issue_orders(orders)

## Interrupt whatever this ship is currently doing (individually) and
## start `order` immediately -- e.g. an urgent "intercept incoming
## missile" that shouldn't wait for an in-progress course change to
## finish first.
func issue_individual_order_now(ship_id: String, order: IndividualOrder) -> void:
	_record_command("issue_individual_order_now", {"ship_id": ship_id, "order": order.to_dict()})
	_get_or_create_individual_command_state(ship_id).issue_order_now(order)

## §30 "return to formation" / §31's worked example's second half. Drops
## any individual order/queue for this ship -- NOT a maneuver, just a
## command-authority change: once this returns, `_resolve_individual_orders`
## stops touching this ship, so its formation's own station-keeping
## (`_resolve_formation_keeping`, which runs every tick regardless of
## individual-order state) simply takes back effect starting next tick. A
## ship with no formation at all just keeps whatever thrust its last
## individual order left it at.
func return_ship_to_formation(ship_id: String) -> void:
	_record_command("return_ship_to_formation", {"ship_id": ship_id})
	if individual_orders.has(ship_id):
		individual_orders[ship_id].clear_orders()

## §31 ("The override must be represented in simulation state"): true
## while `ship_id` has an active or queued individual order, i.e. is
## currently under individual command rather than left entirely to its
## formation (or to nothing, for a ship with no formation).
func is_ship_overriding_formation(ship_id: String) -> bool:
	var state = individual_orders.get(ship_id)
	return state != null and state.is_active()

## Seconds a routine individual order/designation takes to reach
## `ship_id`, given that ship's own COMMUNICATIONS subsystem condition
## (§25 "communications damage -> degraded command/reporting"). A ship
## with no ShipSubsystems (§25 opted out entirely -- true of most
## existing tests/scenarios) or not yet known to this world is treated
## as condition == 1.0, i.e. the smallest ("healthy comms") baseline
## delay, never an unexplained worst case.
func _individual_order_transmission_delay_s(ship_id: String) -> float:
	var ship: ShipPhysicsState = ships.get(ship_id)
	var condition: float = 1.0
	if ship != null and ship.subsystems != null:
		condition = ship.subsystems.get_condition(SubsystemType.Type.COMMUNICATIONS)
	return INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S / maxf(condition, _MIN_CONDITION_FOR_COMMS_TIMING)

func _queue_command_transmission(ship_id: String, callable: Callable) -> void:
	var ready_at: float = world_sim_time + _individual_order_transmission_delay_s(ship_id)
	_pending_command_transmissions.append({"ready_at": ready_at, "ship_id": ship_id, "callable": callable})

## §25/§31: applied once per tick, BEFORE `_sync_subsystem_driven_conditions`
## and every order-consuming resolver runs, so an order that finishes
## transmitting THIS tick is already visible to
## `_resolve_individual_orders`/`_resolve_weapon_target` this same tick --
## no extra tick of lag beyond the modeled delay itself (same convention
## `_sync_subsystem_driven_conditions` already uses for its own snapshot
## timing). Applies every pending transmission whose `ready_at` has
## arrived, in the order they were queued (oldest-issued order lands
## first if two land the same tick), then drops it from the pending list.
func _resolve_pending_command_transmissions() -> void:
	if _pending_command_transmissions.is_empty():
		return
	var still_pending: Array = []
	for entry in _pending_command_transmissions:
		if world_sim_time >= entry["ready_at"]:
			entry["callable"].call()
		else:
			still_pending.append(entry)
	_pending_command_transmissions = still_pending

## §25/§31 communication-delayed variants of the immediate APIs above.
## Use these to represent a commander issuing an order through the normal
## chain of command (the realistic case, now that it has a real seam to
## hook into). The immediate `issue_individual_order`/
## `issue_individual_order_now`/`set_ship_target`/`clear_ship_target`/
## `set_ship_weapons_free`/`return_ship_to_formation` above remain
## available UNCHANGED -- every existing caller/test that assumes
## instantaneous effect (e.g. a scenario script directly puppeteering a
## ship, or the many pre-existing tests written against the instant
## behavior) keeps working exactly as before; nothing about this pass
## touches their signatures or semantics. `order_missile_launch` (§30
## "missile launch") deliberately has no transmit_* wrapper -- it is
## already documented as an immediate "explicit shot trigger" by its own
## convention, matching `fire_weapon()`, and reconsidering that is out of
## scope for this pass.
func transmit_individual_order_now(ship_id: String, order: IndividualOrder) -> void:
	_record_command("transmit_individual_order_now", {"ship_id": ship_id, "order": order.to_dict()})
	_queue_command_transmission(ship_id, Callable(self, "issue_individual_order_now").bind(ship_id, order))

func transmit_ship_target(ship_id: String, target_ship_id: String) -> void:
	_record_command("transmit_ship_target", {"ship_id": ship_id, "target_ship_id": target_ship_id})
	_queue_command_transmission(ship_id, Callable(self, "set_ship_target").bind(ship_id, target_ship_id))

func transmit_clear_ship_target(ship_id: String) -> void:
	_record_command("transmit_clear_ship_target", {"ship_id": ship_id})
	_queue_command_transmission(ship_id, Callable(self, "clear_ship_target").bind(ship_id))

func transmit_ship_weapons_free(ship_id: String, is_free: bool) -> void:
	_record_command("transmit_ship_weapons_free", {"ship_id": ship_id, "is_free": is_free})
	_queue_command_transmission(ship_id, Callable(self, "set_ship_weapons_free").bind(ship_id, is_free))

func transmit_return_ship_to_formation(ship_id: String) -> void:
	_record_command("transmit_return_ship_to_formation", {"ship_id": ship_id})
	_queue_command_transmission(ship_id, Callable(self, "return_ship_to_formation").bind(ship_id))

## §30 "target"/"target priority"/"weapon mode" (Milestone 11, second
## slice). Returns this ship's ShipCombatDirective, creating a default
## (no manual target, weapons free -- i.e. behaviorally identical to
## before this pass) one on first use, exactly the same lazy-creation
## convention as _get_or_create_individual_command_state.
func _get_or_create_combat_directive(ship_id: String) -> ShipCombatDirective:
	if not ship_combat_directives.has(ship_id):
		ship_combat_directives[ship_id] = ShipCombatDirective.new()
	return ship_combat_directives[ship_id]

## §30 "target"/"target priority": designate `ship_id`'s weapon target.
## Applies to both ship-to-ship energy weapons and missile launches (see
## _resolve_weapon_target). Does not itself validate `target_ship_id` --
## an invalid/non-hostile/undetected designation simply fails to select
## in _resolve_weapon_target every tick until it becomes valid or is
## cleared (see ShipCombatDirective doc comment).
func set_ship_target(ship_id: String, target_ship_id: String) -> void:
	_record_command("set_ship_target", {"ship_id": ship_id, "target_ship_id": target_ship_id})
	_get_or_create_combat_directive(ship_id).set_manual_target(target_ship_id)

## Reverts `ship_id` to automatic (TacticalAI) nearest-hostile target
## selection.
func clear_ship_target(ship_id: String) -> void:
	_record_command("clear_ship_target", {"ship_id": ship_id})
	if ship_combat_directives.has(ship_id):
		ship_combat_directives[ship_id].clear_manual_target()

## §30 "weapon mode": true = free to fire (default, pre-existing
## behavior), false = hold fire -- see ShipCombatDirective.weapons_free.
func set_ship_weapons_free(ship_id: String, is_free: bool) -> void:
	_record_command("set_ship_weapons_free", {"ship_id": ship_id, "is_free": is_free})
	_get_or_create_combat_directive(ship_id).set_weapons_free(is_free)

## §30 "missile launch" (Milestone 11) -- a discrete, one-time "fire a
## salvo now" ORDER, deliberately distinct from BOTH `weapons_free`
## ("weapon mode", a standing posture) and the continuous automatic
## missile-launch AI (`_resolve_missile_launch_ai`, which fires every
## ready in-range tube every tick using this ship's STANDING target
## selection). This was an honestly-logged gap since §30/§31's first
## slice (see ASSUMPTIONS.md/CHANGELOG.md history): nothing let a
## commander say "loose a salvo at THIS target, right now" as a single
## action independent of the ship's ongoing posture -- e.g. coordinating
## a simultaneous alpha-strike salvo timing across several ships without
## touching any ship's standing `manual_target_ship_id`/`weapons_free`.
##
## Calling this does NOT modify `ship_combat_directives[ship_id]` at
## all -- the standing directive (if any) is left completely untouched,
## and `_resolve_missile_launch_ai` resumes using it, unaffected, on the
## very next tick. If `target_ship_id` is empty, this call falls back to
## the SAME standing-target resolution the automatic AI already uses
## (`_resolve_weapon_target`) -- "fire right now at whoever I'd normally
## be engaging". If `target_ship_id` is given explicitly but is not a
## currently USABLE hostile contact (destroyed, never hostile, or lost
## from this ship's own sensors), this order simply does not fire --
## UNLIKE the standing-directive fallback policy in
## `_resolve_weapon_target`, a one-time explicit "fire at X" order does
## NOT silently redirect to a different target the commander did not
## name for this specific salvo (see ASSUMPTIONS.md for the fallback-
## policy distinction between a standing designation and a one-shot
## order).
##
## INTERPRETATION, not canon: this order respects `weapons_free` exactly
## like the automatic AI does (a ship under an explicit "hold fire"
## directive does not launch even on a direct one-time order) -- kept
## consistent with `weapons_free` having exactly ONE meaning everywhere
## it is checked, rather than adding an unspecified "explicit orders
## bypass hold-fire" exception §30 does not actually call for either
## way. Physical constraints (ammo, cooldown, `condition`, range) are
## NEVER waived by an order, exactly like `fire_weapon()` already never
## waives them for energy weapons -- a tube that isn't ready, or the
## target that isn't in range, simply does not fire, and no missile is
## created for it.
##
## Returns the number of missiles actually launched this call (0 if
## none -- held fire, disengaging, no valid target, or no tube ready/
## in range).
func order_missile_launch(ship_id: String, target_ship_id: String = "") -> int:
	_record_command("order_missile_launch", {"ship_id": ship_id, "target_ship_id": target_ship_id})
	var ship: ShipPhysicsState = ships.get(ship_id)
	if ship == null:
		return 0
	var tubes: Array = missile_tubes.get(ship_id, [])
	if tubes.is_empty():
		return 0
	if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
		return 0  # disengaging -- same gate as the automatic AI
	var directive = ship_combat_directives.get(ship_id)
	if directive != null and not directive.weapons_free:
		return 0  # §30 "weapon mode": hold fire, even for an explicit order

	var contacts: Dictionary = sensor_contacts.get(ship_id, {})
	var hostile_ids: Array = _hostile_ship_ids(ship_id)
	var selection: Dictionary
	if target_ship_id != "":
		selection = TacticalAI.select_directed_weapon_target(ship, contacts, hostile_ids, target_ship_id)
	else:
		selection = _resolve_weapon_target(ship_id, ship, contacts, hostile_ids)
	var target_ship = selection.get("ship")
	var target_contact = selection.get("contact")
	if target_ship == null or target_contact == null:
		return 0

	var distance: float = ship.position.distance_to(target_contact.estimated_position)
	var launched_count: int = 0
	for tube in tubes:
		if not tube.is_ready():
			continue
		if distance > tube.effective_max_range_m():
			continue
		_launch_missile_from_tube(ship_id, ship, target_ship, tube)
		launched_count += 1
	return launched_count

## Shared target-selection policy for BOTH _resolve_weapons_ai and
## _resolve_missile_launch_ai (§30 "target"/"target priority", Milestone
## 11 second slice, extended by §34.1 Doubling this pass): priority order
## is (1) a manually designated target (§30), if `ship_id` has one AND it
## is still a valid usable hostile contact; else (2) this tick's
## formation-coordinated assignment (§34.1,
## `_resolve_formation_target_assignment`), if this ship belongs to a
## governed formation that computed one AND it is still a valid usable
## hostile contact; else (3) TacticalAI's pre-existing automatic nearest-
## hostile-contact selection. A stale/no-longer-valid entry at any
## priority level falls through to the next, exactly like the pre-
## existing manual-designation fallback -- never "no target" purely
## because a stale designation/assignment exists (see
## ShipCombatDirective doc comment for the original reasoning, which
## applies identically here).
func _resolve_weapon_target(ship_id: String, ship, contacts: Dictionary, hostile_ids: Array) -> Dictionary:
	var directive = ship_combat_directives.get(ship_id)
	if directive != null and directive.manual_target_ship_id != "":
		var directed: Dictionary = TacticalAI.select_directed_weapon_target(ship, contacts, hostile_ids, directive.manual_target_ship_id)
		if directed.get("ship_id") != null:
			return directed
	var formation_assigned_id = _formation_assigned_targets.get(ship_id, "")
	if formation_assigned_id != "":
		var assigned: Dictionary = TacticalAI.select_directed_weapon_target(ship, contacts, hostile_ids, formation_assigned_id)
		if assigned.get("ship_id") != null:
			return assigned
	return TacticalAI.select_weapon_target(ship, contacts, hostile_ids)

## §30/§31 (Milestone 11, this pass): executes each ship's active
## individual order, OVERWRITING whatever `_resolve_formation_keeping`
## (which ran just before this, unconditionally, for every formation
## member) computed for that ship this tick -- this is the entire
## mechanism of "an individual ship can temporarily override its
## formation's order" (§31): no special "override mode" flag on the
## formation or the ship is needed, an active IndividualCommandState is
## itself sufficient representation (see `is_ship_overriding_formation`),
## and simply STOPPING here (queue drained, `clear_orders`/§30 "return to
## formation") is sufficient to hand control back, since nothing then
## overwrites `_resolve_formation_keeping`'s output again until this
## function runs again next tick and finds nothing active.
##
## A ship with no formation at all is handled identically -- this
## function has no notion of "formation member" at all, only "ship_id
## with an active individual order", so Milestone 11's actual target
## (independent single-ship command, not just formation overrides) works
## via the exact same code path.
##
## CHANGE_COURSE/CHANGE_SPEED reuse the same EXACT-STOP acceleration
## clamp as `_resolve_formation_orders` (see that function's doc comment
## for the full rationale) so an individually-ordered ship converges on
## its target course/speed without overshoot or oscillation, with no
## tuned gains. CHANGE_ORIENTATION is new: see
## `_resolve_individual_orientation_order`.
func _resolve_individual_orders(dt: float) -> void:
	for ship_id in individual_orders.keys():
		var state: IndividualCommandState = individual_orders[ship_id]
		if not state.is_active():
			continue
		var ship: ShipPhysicsState = ships.get(ship_id)
		if ship == null:
			continue
		if ship.is_wreck:
			continue  # §63.1: a wreck cannot be given orders (_resolve_ship_destruction already clears individual_orders for it, but guard here too in case a stale/replayed order lands afterward)

		if state.current_order == null:
			state.current_order = state.order_queue.pop_front()

		var order: IndividualOrder = state.current_order

		# HOLD is a standing order (§30's implicit "stop maneuvering"):
		# it never auto-completes -- it actively zeroes both this ship's
		# maneuver thrust AND its turn rate every tick until something
		# else explicitly replaces it.
		if order.kind == IndividualOrder.Kind.HOLD:
			ship.commanded_thrust_local = Vector3.ZERO
			ship.angular_velocity = Vector3.ZERO
			continue

		if order.kind == IndividualOrder.Kind.CHANGE_ORIENTATION:
			_resolve_individual_orientation_order(ship, order, dt)
			if order.is_complete(ship):
				state.current_order = null
			continue

		# CHANGE_COURSE / CHANGE_SPEED.
		if order.is_complete(ship):
			state.current_order = null
			# Zeroed on the exact tick of completion, mirroring
			# FormationOrder's identical convention for its guide -- for
			# a ship that also happens to be a formation member, this
			# means one tick of zero thrust before station-keeping
			# recomputes a fresh value next tick (negligible at this
			# project's tick rates; see ASSUMPTIONS.md), rather than
			# adding coupling here to know whether a formation would
			# otherwise be driving this ship's thrust.
			ship.commanded_thrust_local = Vector3.ZERO
			continue

		var max_accel: float = ship.effective_max_acceleration()
		if max_accel <= 0.0:
			continue
		var velocity_error: Vector3 = order.target_velocity_mps - ship.velocity
		var error_mag: float = velocity_error.length()
		if error_mag <= 0.0001:
			continue
		var desired_accel_mag: float = min(max_accel, error_mag / dt)
		var desired_accel: Vector3 = velocity_error.normalized() * desired_accel_mag
		ship.commanded_thrust_local = ship.orientation.inverse() * (desired_accel / max_accel)

## §30 "orientation" (Milestone 11, this pass): the first code anywhere
## in this project to actually drive `angular_velocity` from an order
## (previously an honestly-logged gap -- see CHANGELOG.md/ASSUMPTIONS.md
## history). Turns `ship`'s nose to point along `order.target_facing_world`
## using the same EXACT-STOP clamp philosophy as the kinematic orders
## (accelerate the turn rate up to `max_angular_speed_rad_s`, but never so
## fast that this tick's rotation would overshoot the remaining angle),
## so a ship reaches its ordered facing and stops -- no oscillation, no
## tuned gains.
##
## Works entirely in the ship's own BODY/local frame, not world frame:
## `KinematicsUtils.integrate_orientation` composes
## `orientation * delta_rotation`, which is the standard rigid-body
## convention for a BODY-frame angular velocity (rotating about a body
## axis leaves that axis's own world direction unchanged, exactly like a
## real ship's own rate gyros/thrusters would command a turn rate in its
## own frame, not in some external world frame). Transforming the world-
## space target facing into the ship's local frame first
## (`orientation.inverse() * target_facing_world`) and computing the
## rotation axis/angle there keeps this consistent with that convention
## -- see ASSUMPTIONS.md for the full derivation and why getting this
## backwards would only be caught by a test that starts from a NON-
## identity initial orientation (which test_individual_orders.gd
## deliberately includes).
func _resolve_individual_orientation_order(ship: ShipPhysicsState, order: IndividualOrder, dt: float) -> void:
	_steer_toward_world_facing(ship, order.target_facing_world, dt)
	var remaining: Vector3 = ship.orientation.inverse() * order.target_facing_world
	if Vector3.FORWARD.angle_to(remaining) <= order.orientation_tolerance_rad:
		ship.angular_velocity = Vector3.ZERO

## Shared BODY-frame "turn toward a world-space facing" helper. Extracted
## from what used to be `_resolve_individual_orientation_order`'s own
## inline logic (see CHANGELOG.md/git history for that original single-
## caller version) so `_resolve_crossing_t_maneuver` below can reuse the
## exact same EXACT-STOP turn-rate clamp for §41.1, instead of a second,
## possibly-drifting copy of the same math.
##
## Turns `ship`'s nose toward `target_facing_world` at up to
## `ship.max_angular_speed_rad_s`, clamped so this tick's rotation never
## overshoots the remaining angle (no tuned gains, no oscillation).
## Always WRITES `ship.angular_velocity` (including the zero-angle-error
## case, where it writes a zero vector) -- callers that need a tolerance-
## band "stop turning and hold" behavior (e.g. §30's CHANGE_ORIENTATION)
## apply that themselves AFTER calling this, exactly as
## `_resolve_individual_orientation_order` does above. Does nothing if
## `target_facing_world` is the zero vector (nothing to turn toward).
func _steer_toward_world_facing(ship: ShipPhysicsState, target_facing_world: Vector3, dt: float) -> void:
	if target_facing_world == Vector3.ZERO:
		return
	if dt <= 0.0:
		return

	var target_facing_local: Vector3 = ship.orientation.inverse() * target_facing_world
	var forward_local: Vector3 = Vector3.FORWARD
	var angle_err: float = forward_local.angle_to(target_facing_local)

	if angle_err <= 0.000001:
		ship.angular_velocity = Vector3.ZERO
		return

	var axis_local: Vector3 = forward_local.cross(target_facing_local)
	if axis_local.length_squared() <= 0.000001:
		# forward_local and target_facing_local are (anti)parallel --
		# ASSUMPTION: no canonically "correct" roll-free axis exists for
		# a pure 180-degree reversal, so an arbitrary perpendicular axis
		# is picked (this codebase never models roll/bank around the
		# forward axis at all).
		axis_local = forward_local.cross(Vector3.UP)
		if axis_local.length_squared() <= 0.000001:
			axis_local = forward_local.cross(Vector3.RIGHT)
	axis_local = axis_local.normalized()

	var max_turn_rate: float = ship.max_angular_speed_rad_s
	if max_turn_rate <= 0.0:
		return
	var turn_rate: float = min(max_turn_rate, angle_err / dt)
	ship.angular_velocity = axis_local * turn_rate

## §41.1 Crossing the T -- default combat maneuvering AI for a ship with
## NO more specific command claiming its movement this tick. Deliberately
## runs LAST among the per-tick AI passes (see `tick_simulation`, right
## before `_integrate_ships`) so it only fills in movement for ships
## nothing else already claimed this tick:
##   * a wreck (§63.1) never maneuvers;
##   * a ship with an ACTIVE `IndividualCommandState` (§30) is under
##     explicit single-ship command -- `_resolve_individual_orders`
##     already drove its thrust/orientation this tick, and this pass
##     must not fight that order;
##   * a ship that is a MEMBER (not guide) of a formation with a valid
##     (not lost, see TacticalAI.is_guide_lost) guide is being driven by
##     `_resolve_formation_keeping`'s station-keeping controller --
##     formation-level ("wall") crossing-the-T is explicitly NOT
##     implemented yet (see TacticalAI.compute_crossing_t_maneuver's own
##     doc comment), so an individual member is honestly left under
##     station-keeping rather than having this pass fight it every tick.
##     The formation GUIDE itself is not station-kept by anything, so it
##     IS eligible here -- members simply follow its offset as always;
##   * a critically damaged/disengaging ship (§26) is already retreating
##     via `_resolve_damage_response`, which runs earlier this same
##     tick -- this pass must not override that with an "engage" thrust.
## Every remaining ship with a team and at least one usable hostile
## sensor contact gets `TacticalAI.compute_crossing_t_maneuver`'s result
## applied: thrust toward `desired_velocity_world` using the exact same
## velocity-error-to-thrust conversion `_resolve_individual_orders` uses
## for CHANGE_COURSE/CHANGE_SPEED (kept consistent rather than inventing
## a second formula), and a turn toward `desired_facing_world` via the
## shared `_steer_toward_world_facing` helper above. A ship with no
## usable hostile contact is left completely untouched -- nothing
## sensor-honest to maneuver against yet, same philosophy already used
## by `_resolve_damage_response` for the no-contact retreat case.
func _resolve_crossing_t_maneuver(dt: float) -> void:
	for ship_id in ships.keys():
		var ship: ShipPhysicsState = ships[ship_id]
		if ship.is_wreck:
			continue
		if not teams.has(ship_id):
			continue

		var order_state: IndividualCommandState = individual_orders.get(ship_id)
		if order_state != null and order_state.is_active():
			continue

		if _is_station_kept_formation_member(ship_id):
			continue

		var hull = hulls.get(ship_id)
		if TacticalAI.is_critically_damaged(hull, CRITICAL_HULL_FRACTION):
			continue

		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		var maneuver: Dictionary = TacticalAI.compute_crossing_t_maneuver(ship, contacts, hostile_ids)
		var desired_velocity_world: Vector3 = maneuver["desired_velocity_world"]
		var desired_facing_world: Vector3 = maneuver["desired_facing_world"]
		if desired_velocity_world == Vector3.ZERO and desired_facing_world == Vector3.ZERO:
			continue  # no usable hostile contact -- nothing sensor-honest to maneuver against

		var max_accel: float = ship.effective_max_acceleration()
		if max_accel > 0.0:
			var velocity_error: Vector3 = desired_velocity_world - ship.velocity
			var error_mag: float = velocity_error.length()
			if error_mag > 0.0001:
				var desired_accel_mag: float = min(max_accel, error_mag / dt)
				var desired_accel: Vector3 = velocity_error.normalized() * desired_accel_mag
				ship.commanded_thrust_local = ship.orientation.inverse() * (desired_accel / max_accel)

		_steer_toward_world_facing(ship, desired_facing_world, dt)

## Helper for `_resolve_crossing_t_maneuver`: true iff `ship_id` is a
## non-guide member of some formation whose guide is currently valid
## (not lost per TacticalAI.is_guide_lost) -- i.e. a ship whose movement
## `_resolve_formation_keeping` is actively driving this tick, which
## `_resolve_crossing_t_maneuver` must not fight. During a guide-lost
## succession window `_resolve_formation_keeping` itself skips station-
## keeping (see that function's §33.1 doc comment) and instead holds the
## member's LAST commanded thrust -- this helper returns false in that
## window so crossing-the-T is free to take over a member abandoned by
## its lost guide, rather than leaving it frozen on stale thrust forever
## if the succession window never resolves cleanly.
func _is_station_kept_formation_member(ship_id: String) -> bool:
	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]
		if formation.guide_ship_id == ship_id:
			continue
		if not formation.member_ids().has(ship_id):
			continue
		return not TacticalAI.is_guide_lost(formation.guide_ship_id, ships, hulls, CRITICAL_HULL_FRACTION)
	return false

## §22.1 Formation mutual defensive coverage -- first slice. Returns
## {"bow": bool, "stern": bool}: whether `ship_id` currently has a living,
## non-wreck formation neighbor (any OTHER member of the same formation,
## guide included) positioned within FORMATION_COVERAGE_MAX_DISTANCE_M
## and within FORMATION_COVERAGE_CONE_HALF_WIDTH_RAD of its own bow
## (resp. stern) axis -- close enough and nearly enough in line to
## plausibly interpose that neighbor's own wedge/sidewall geometry
## between an attacker and this ship's otherwise-undefended bow/stern
## gap (AGENTS.md §22.1: "keeping close formation station lets a
## neighboring ship's ... wedge/sidewall aspect cover an arc that the
## first ship's own systems cannot reach").
##
## Reuses the SAME "classify the direction to another position in MY
## local frame" idea AttackGeometry.classify already provides for attack
## geometry, rather than inventing a second angle formula -- a neighbor
## is "on my bow" in exactly the sense an attacker would be.
##
## Cohesion gate, same as `_is_station_kept_formation_member` and every
## other §33/§33.1-aware pass in this file: a formation whose guide is
## currently lost (TacticalAI.is_guide_lost) provides NO coverage at all,
## for EITHER its guide or its members -- a broken formation's mutual
## defense is genuinely gone, not just cosmetically (AGENTS.md §22.1:
## "when formation integrity breaks ... the mutual coverage those
## neighbors were providing ... is genuinely lost"). Unlike
## `_is_station_kept_formation_member`, the ship being screened MAY be
## the guide itself here -- coverage is symmetric between guide and
## members (the guide benefits from a covering member exactly as a
## member benefits from a covering guide or another member); only the
## MOVEMENT authority `_is_station_kept_formation_member` answers is
## guide-vs-member-asymmetric, not defensive coverage.
##
## HONEST SCOPE LIMITS (see ASSUMPTIONS.md for the full write-up): only
## mitigates the "no functioning sidewall of this ship's own" bow/stern
## case (ShipDefenseState's FORMATION_COVERED path), not the separate
## raised-sidewall acute-angle-bypass case; no PD firing-arc model exists
## yet (AGENTS.md §22.1's own honest-gap paragraph), so PD engagement
## itself is entirely unaffected by this function -- only wedge/sidewall
## resolution reads it, via `_formation_bow_stern_coverage`'s two callers
## below (`fire_weapon` and `_update_missiles`).
func _formation_bow_stern_coverage(ship_id: String) -> Dictionary:
	var result: Dictionary = {"bow": false, "stern": false}
	var ship: ShipPhysicsState = ships.get(ship_id)
	if ship == null or ship.is_wreck:
		return result

	var formation: FormationState = null
	for formation_id in formations.keys():
		var f: FormationState = formations[formation_id]
		if f.guide_ship_id == ship_id or f.member_ids().has(ship_id):
			formation = f
			break
	if formation == null:
		return result
	if TacticalAI.is_guide_lost(formation.guide_ship_id, ships, hulls, CRITICAL_HULL_FRACTION):
		return result

	var neighbor_ids: Array = formation.member_ids().duplicate()
	if not neighbor_ids.has(formation.guide_ship_id):
		neighbor_ids.append(formation.guide_ship_id)
	neighbor_ids.erase(ship_id)

	for neighbor_id in neighbor_ids:
		if result.bow and result.stern:
			break
		var neighbor: ShipPhysicsState = ships.get(neighbor_id)
		if neighbor == null or neighbor.is_wreck:
			continue
		if ship.position.distance_to(neighbor.position) > FORMATION_COVERAGE_MAX_DISTANCE_M:
			continue

		var world_dir: Vector3 = neighbor.position - ship.position
		if world_dir.length_squared() <= 0.0:
			continue
		world_dir = world_dir.normalized()
		var local_dir: Vector3 = ship.orientation.inverse() * world_dir

		if not result.bow and local_dir.angle_to(Vector3(0, 0, -1)) <= FORMATION_COVERAGE_CONE_HALF_WIDTH_RAD:
			result.bow = true
		if not result.stern and local_dir.angle_to(Vector3(0, 0, 1)) <= FORMATION_COVERAGE_CONE_HALF_WIDTH_RAD:
			result.stern = true

	return result

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
		if ships[ship_id].is_wreck:
			continue  # §63.1: a wreck does not retreat -- no crew left to order it, and it must keep obeying pure inertia, not manufactured "retreat" thrust
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

## §34.1 Doubling -- formation-coordinated target assignment (first
## slice). Runs once per tick, BEFORE `_resolve_weapons_ai`/
## `_resolve_missile_launch_ai`, for every formation that currently has a
## valid (not lost, see TacticalAI.is_guide_lost) guide -- "run by the
## guide ship's side of the command hierarchy" per §34.1's own wording. A
## formation whose guide is lost/mid-transfer (§33) does NOT get
## coordinated assignment this tick -- its members simply fall back to
## each individually running TacticalAI.select_weapon_target via
## _resolve_weapon_target's existing fallback, exactly as before this
## pass, since there is no guide side of the hierarchy to run the pass
## FROM (honest: no phantom coordinator invented for a headless
## formation).
##
## For each governed formation, walks its members in the formation's own
## deterministic order (guide first, then `member_offsets.keys()` in
## their existing Dictionary insertion order -- same convention used
## throughout this codebase, e.g. `_resolve_formation_keeping`) and, for
## each member actually able to independently choose a target this tick
## (has a team, is not critically damaged/disengaging, is NOT holding
## fire under a §30 "weapon mode" directive, and does NOT have an active
## §30 manual target designation -- a commander's explicit single-ship
## override already outranks automatic selection everywhere else in this
## codebase, e.g. `_resolve_individual_orders` overriding
## `_resolve_formation_keeping`, and this pass deliberately keeps that
## same precedence rather than overriding an override), computes a
## coordinated pick via `TacticalAI.select_formation_target_for_member`
## using a running `assigned_counts` tally SHARED across this formation's
## members for this tick only -- so member 2's pick already "sees" member
## 1's pick this same tick, true sequential coordination, not just
## simultaneous independent guesses that happen to look similar.
##
## Stores the result in `_formation_assigned_targets[ship_id]`, which
## `_resolve_weapon_target` consults (after manual designation, before
## the ordinary automatic fallback) for BOTH energy weapons and missile
## launch target selection -- one assignment pass drives both weapon
## types identically, since §34.1 does not distinguish between them.
## §34.2 (missile time-on-target staggering) is a SEPARATE, still-open
## piece of work -- this pass only coordinates WHICH target is chosen,
## not WHEN missiles launched against it arrive (see ASSUMPTIONS.md).
##
## `_formation_assigned_targets` is fully rebuilt (cleared, then
## repopulated) every tick, exactly like every other per-tick AI decision
## in this file -- there is no "sticky" assignment carried across ticks;
## a member is free to be reassigned next tick as the tactical picture
## (damage, new contacts, lost contacts) changes.
func _resolve_formation_target_assignment(dt: float) -> void:
	_formation_assigned_targets.clear()

	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]
		if TacticalAI.is_guide_lost(formation.guide_ship_id, ships, hulls, CRITICAL_HULL_FRACTION):
			continue  # no guide side of the hierarchy to run this pass from this tick -- see doc comment above

		var member_ids: Array = [formation.guide_ship_id]
		for member_id in formation.member_offsets.keys():
			member_ids.append(member_id)

		var assigned_counts: Dictionary = {}

		for ship_id in member_ids:
			var ship: ShipPhysicsState = ships.get(ship_id)
			if ship == null or ship.is_wreck:
				continue
			var has_weapons: bool = not weapon_mounts.get(ship_id, []).is_empty() or not missile_tubes.get(ship_id, []).is_empty()
			if not has_weapons:
				continue
			if not teams.has(ship_id) or teams[ship_id] == "":
				continue
			if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
				continue
			var directive = ship_combat_directives.get(ship_id)
			if directive != null and not directive.weapons_free:
				continue
			if directive != null and directive.manual_target_ship_id != "":
				continue  # §30 commander override outranks automatic coordination, same precedence as everywhere else

			var hostile_ids: Array = _hostile_ship_ids(ship_id)
			if hostile_ids.is_empty():
				continue
			var contacts: Dictionary = sensor_contacts.get(ship_id, {})
			var selection: Dictionary = TacticalAI.select_formation_target_for_member(ship, contacts, hostile_ids, hulls, assigned_counts, MAX_USEFUL_ATTACKERS_PER_TARGET, CRITICAL_HULL_FRACTION)
			var target_id = selection.get("ship_id")
			if target_id == null:
				continue
			_formation_assigned_targets[ship_id] = target_id
			assigned_counts[target_id] = assigned_counts.get(target_id, 0) + 1

## ТЗ §34.2 Missile Time-on-Target -- coordinate WHEN formation-mates
## launch missiles at a shared §34.1-assigned target so that missiles
## fired from different ranges (and therefore with different flight
## times) arrive TOGETHER instead of strung out one at a time, each
## individually easy for point defense to intercept. Runs once per tick,
## AFTER `_resolve_formation_target_assignment` (needs this tick's
## `_formation_assigned_targets` to know who is even shooting at the same
## contact) and BEFORE `_resolve_missile_launch_ai` (the only consumer of
## the schedule this pass produces).
##
## HONEST SCOPE: this coordinates ONLY members of the SAME formation
## whose target this tick came from §34.1's coordinated assignment (not
## a manual §30 designation, and not two different formations that
## happen to have picked the same hostile independently -- both real,
## narrower-than-ideal limits of this first slice, see ASSUMPTIONS.md).
## For each formation, ships with a ready, in-range tube on their
## assigned target and NOT already holding an earlier schedule are
## grouped by target. A lone shooter (group size < 2) gets no entry in
## `_missile_salvo_fire_at` at all, so `_resolve_missile_launch_ai` fires
## it the instant it is ready -- EXACTLY the pre-§34.2 behavior (same
## "degenerates to the old behavior" pattern §34.1 itself already uses).
##
## For an actual group (>= 2 candidates), each candidate's flight time to
## the target is estimated by
## `KinematicsUtils.estimate_boost_coast_time_to_distance_s` from the
## CURRENT distance (this ship's real `position`, the target's
## `SensorContact.estimated_position` -- same "no cheat vision"
## measurement `TacticalAI` uses everywhere else), using the shared
## DEFAULT drive constants every AI-launched missile actually gets (see
## `_launch_missile_from_tube` -- no per-class missile drive data exists
## yet, see ASSUMPTIONS.md §8). The slowest (longest-flight-time) member
## fires immediately (no schedule entry -- it IS the pacing shot); every
## faster member is given `fire_at = now + (max_flight_time -
## its_own_flight_time)`, so that firing exactly then instead of right
## now puts both missiles' estimated arrival at the same instant.
##
## A ship already holding a schedule from an earlier tick is skipped by
## the GROUPING step below (its wait must not be re-timed mid-flight
## using a fresh, unrelated snapshot of who else happens to be ready this
## exact tick) but IS checked for staleness first, at the top of this
## function: if it no longer exists, is a wreck, or its §34.1 assignment
## has moved to a different target than the schedule was built for, the
## stale entry is dropped so the ship is free to be re-grouped (or fire
## immediately) on a later tick. A schedule is never re-validated here
## against "is the tube still ready/in-range" -- `_resolve_missile_launch_ai`
## already handles a not-yet-ready or now-out-of-range tube by simply not
## firing that tick, schedule or not, and will fire (schedule permitting)
## the moment it can.
func _resolve_missile_tot_coordination(dt: float) -> void:
	for ship_id in _missile_salvo_fire_at.keys().duplicate():
		var schedule: Dictionary = _missile_salvo_fire_at[ship_id]
		var scheduled_ship: ShipPhysicsState = ships.get(ship_id)
		if scheduled_ship == null or scheduled_ship.is_wreck or _formation_assigned_targets.get(ship_id, "") != schedule.get("target_ship_id", ""):
			_missile_salvo_fire_at.erase(ship_id)

	for formation_id in formations.keys():
		var formation: FormationState = formations[formation_id]
		var member_ids: Array = [formation.guide_ship_id]
		for member_id in formation.member_offsets.keys():
			member_ids.append(member_id)

		var groups: Dictionary = {}  # target_ship_id -> Array[{"ship_id": String, "flight_time_s": float}]
		for ship_id in member_ids:
			if _missile_salvo_fire_at.has(ship_id):
				continue  # already scheduled from an earlier tick -- don't re-time mid-wait
			var target_id = _formation_assigned_targets.get(ship_id, "")
			if target_id == "":
				continue
			var ship: ShipPhysicsState = ships.get(ship_id)
			if ship == null or ship.is_wreck:
				continue
			var tubes: Array = missile_tubes.get(ship_id, [])
			if tubes.is_empty():
				continue
			var contacts: Dictionary = sensor_contacts.get(ship_id, {})
			var contact = contacts.get(target_id)
			if contact == null:
				continue
			var distance: float = ship.position.distance_to(contact.estimated_position)
			var ready_and_in_range := false
			for tube in tubes:
				if tube.is_ready() and distance <= tube.effective_max_range_m():
					ready_and_in_range = true
					break
			if not ready_and_in_range:
				continue
			var flight_time_s: float = KinematicsUtils.estimate_boost_coast_time_to_distance_s(distance, MissileState.DEFAULT_DRIVE_MAX_ACCELERATION_MPS2, MissileState.DEFAULT_DRIVE_BURN_TIME_S)
			if not groups.has(target_id):
				groups[target_id] = []
			groups[target_id].append({"ship_id": ship_id, "flight_time_s": flight_time_s})

		for target_id in groups.keys():
			var entries: Array = groups[target_id]
			if entries.size() < 2:
				continue  # a lone shooter needs no coordination -- fires the instant it is ready, unchanged from before §34.2
			var max_flight_time_s: float = 0.0
			for entry in entries:
				max_flight_time_s = maxf(max_flight_time_s, entry["flight_time_s"])
			for entry in entries:
				var hold_s: float = max_flight_time_s - entry["flight_time_s"]
				if hold_s <= dt * 0.5:
					continue  # already the pacing shot (or close enough that holding costs a tick for nothing) -- fires immediately, no schedule needed
				_missile_salvo_fire_at[entry["ship_id"]] = {"fire_at": world_sim_time + hold_s, "target_ship_id": target_id}

## ТЗ §17 Weapons + §26 Tactical AI ("select targets" / "use weapons") +
## §30 "target"/"target priority"/"weapon mode" (Milestone 11, second
## slice). Each ship with at least one weapon mount and a team assigned
## picks its target via `_resolve_weapon_target` (a commander's manual
## designation if one is active and still valid, else the pre-existing
## automatic nearest-usable-hostile-contact selection) and fires every
## ready, arc-capable mount at it. A ship with no team, no hostile
## contacts, or an explicit "hold fire" combat directive does not fire --
## there is no default-hostile fallback (see `is_hostile`).
func _resolve_weapons_ai(dt: float) -> void:
	for ship_id in ships.keys():
		if ships[ship_id].is_wreck:
			continue  # §63.1: a wreck has no crew/power to fire weapons
		var mounts: Array = weapon_mounts.get(ship_id, [])
		if mounts.is_empty():
			continue
		if not teams.has(ship_id) or teams[ship_id] == "":
			continue
		if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
			continue  # disengaging -- see _resolve_damage_response
		var directive = ship_combat_directives.get(ship_id)
		if directive != null and not directive.weapons_free:
			continue  # §30 "weapon mode": hold fire

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		if hostile_ids.is_empty():
			continue

		var selection: Dictionary = _resolve_weapon_target(ship_id, ship, contacts, hostile_ids)
		var target_ship_id = selection.get("ship_id")
		if target_ship_id == null:
			continue

		for mount in mounts:
			fire_weapon(ship_id, mount, target_ship_id)

## §26 "launch missiles" + §30 "target"/"target priority"/"weapon mode"
## (Milestone 11, second slice) -- first real launch DECISION (not just
## firing already-mounted weapons). Every tube always advances its own
## cooldown (`tube.advance(dt)`), even for a ship with no team/hostiles/
## that is disengaging/holding fire, so ammo/cooldown bookkeeping stays
## correct regardless of whether the AI is currently choosing to shoot --
## an explicit "hold fire" directive is a fire-control decision, not
## equipment damage or a jammed tube. Target selection goes through
## `_resolve_weapon_target` (manual designation if active and valid, else
## the pre-existing automatic nearest-usable-hostile-contact rule -- same
## "no cheat vision": distance is measured to the CONTACT's estimated
## position, not the target's true position). A critically damaged/
## disengaging ship, or one under a "hold fire" combat directive, does
## not launch new missiles, same as it does not fire energy weapons.
func _resolve_missile_launch_ai(dt: float) -> void:
	for ship_id in ships.keys():
		if ships[ship_id].is_wreck:
			continue  # §63.1: a wreck has no crew/power to launch missiles
		var tubes: Array = missile_tubes.get(ship_id, [])
		if tubes.is_empty():
			continue
		for tube in tubes:
			tube.advance(dt)

		if not teams.has(ship_id) or teams[ship_id] == "":
			continue
		if TacticalAI.is_critically_damaged(hulls.get(ship_id), CRITICAL_HULL_FRACTION):
			continue  # disengaging -- see _resolve_damage_response
		var directive = ship_combat_directives.get(ship_id)
		if directive != null and not directive.weapons_free:
			continue  # §30 "weapon mode": hold fire

		var ship: ShipPhysicsState = ships[ship_id]
		var contacts: Dictionary = sensor_contacts.get(ship_id, {})
		var hostile_ids: Array = _hostile_ship_ids(ship_id)
		if hostile_ids.is_empty():
			continue

		var selection: Dictionary = _resolve_weapon_target(ship_id, ship, contacts, hostile_ids)
		var target_ship = selection.get("ship")
		var target_contact = selection.get("contact")
		if target_ship == null or target_contact == null:
			continue

		var distance: float = ship.position.distance_to(target_contact.estimated_position)
		# §34.2 Missile Time-on-Target: a schedule here means
		# _resolve_missile_tot_coordination decided this ship should hold this
		# shot so it lands together with a formation-mate's longer-flight-time
		# missile -- see that function's doc comment. No schedule (the common
		# case) means fire the instant ready+in-range, exactly as before §34.2.
		var salvo_schedule = _missile_salvo_fire_at.get(ship_id)
		if salvo_schedule != null and salvo_schedule["target_ship_id"] != selection.get("ship_id"):
			# §34.2: this tick's ACTUAL target (e.g. a §30 manual override issued
			# after the hold was scheduled) no longer matches the target the
			# hold was timed for -- honor the override immediately rather than
			# delaying a shot at a DIFFERENT ship for a synchronization that no
			# longer applies to it.
			_missile_salvo_fire_at.erase(ship_id)
			salvo_schedule = null
		for tube in tubes:
			if not tube.is_ready():
				continue
			if distance > tube.effective_max_range_m():
				continue
			if salvo_schedule != null and world_sim_time < salvo_schedule["fire_at"]:
				continue  # still holding for the coordinated arrival time
			if salvo_schedule != null:
				_missile_salvo_fire_at.erase(ship_id)
				salvo_schedule = null
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
	_record_event("missile_launched", {"attacker_ship_id": attacker_ship_id, "missile_id": missile_id})

func _integrate_ships(dt: float) -> void:
	for ship_id in ships.keys():
		ships[ship_id].integrate(dt)

