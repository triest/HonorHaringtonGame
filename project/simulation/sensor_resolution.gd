extends RefCounted
## SensorResolution
##
## ТЗ §23 Sensors: detection/tracking update logic. Kept entirely inside
## simulation/ (no rendering knowledge, ТЗ §42) and entirely separate from
## SensorContact (data holder) and from combat resolution (weapon/missile
## resolution do not decide who can be detected).
##
## CANON basis (CANON_RULES.md "Седьмая сверка", primary source "On
## Basilisk Station" ch.3):
##   - Passive gravitic sensors detect a unit's impeller wedge signature.
##   - A unit CAN reduce/hide its detectability by powering impellers down
##     ("shutting down her impellers and dropping off the enemy's passive
##     scanners"). Modeled here as: ships are only detectable while
##     defense.wedge_up == true; missiles are only detectable while their
##     drive is still burning (drive_burn_remaining_s > 0). A ship with its
##     wedge down, or a missile in unpowered coast, presents no signature
##     to THIS model and cannot be freshly detected (existing contacts may
##     still coast on dead reckoning, see ESTIMATED below).
##   - Missiles "produce distinct, easily-detected traces at launch" --
##     consistent with treating active-drive as the detectable state.
##
## ТЗ §24 ECM (CANON basis: Honorverse Wiki "Electronic warfare", secondary
## source -- see ecm_state.gd doc comment): a target with `ECMState.jamming_active`
## shrinks the EFFECTIVE detection range an observer gets against it
## (`_effective_sensor_range_m`) -- jamming makes a firm track physically
## harder to hold at range, rather than subtracting a flat post-hoc hit
## chance (the ТЗ explicitly forbids that shortcut unless it's the
## documented consequence of a deeper model, which this is). A jammed
## target with active decoys can also have its APPARENT position
## substituted for the nearest deployed decoy (`_resolve_apparent_return`)
## -- a deterministic stand-in for "jammers and decoys... confuse incoming
## fire" that does NOT use unseeded randomness (ТЗ §43 forbids that): the
## observer's sensors lock onto whichever return (true target or a decoy)
## is geometrically nearest to the observer, which is what a real
## return-strength-dominated sensor would plausibly resolve first.
##
## ТЗ §25 Damage (example given in the ТЗ itself: "sensor damage ->
## degraded tracking"): an optional `observer_subsystems` (the OBSERVER's
## own ShipSubsystems) scales its effective sensor range by its own
## SENSORS subsystem condition, and a fully-disabled sensors subsystem
## (integrity <= 0) blocks fresh detection entirely -- a damaged ship's
## sensors get physically worse, not a flat "tracking quality -20%" tacked
## on afterward.
##
## All timing thresholds below (detection->tracking time, ESTIMATED grace
## period) are UNVERIFIED ASSUMPTIONS -- no canonical figures were found
## for gravitic sensor discrimination time. See ASSUMPTIONS.md.
class_name SensorResolution

const ContactState = preload("res://simulation/contact_state.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

## ASSUMPTION: default passive detection range. No canonical figure found;
## chosen to comfortably exceed the missile terminal_detonation_range_m
## default (50,000 km) so contacts are not created mid-engagement only.
const DEFAULT_SENSOR_RANGE_M: float = 2_000_000_000.0 # 2,000,000 km

## ASSUMPTION: continuous detection time required before DETECTED upgrades
## to TRACKED (a firm, weapons-quality lock vs. a fleeting return).
const DETECTED_TO_TRACKED_TIME_S: float = 6.0

## ASSUMPTION: how long a lost contact is held as ESTIMATED (dead-reckoned
## from last known position/velocity) before decaying to LOST.
const ESTIMATED_GRACE_PERIOD_S: float = 30.0


## Returns true if `entity` currently presents a detectable signature
## under this model. Duck-typed: ships expose `.defense.wedge_up`,
## missiles expose `.drive_burn_remaining_s`.
static func _is_emitting_signature(entity) -> bool:
	if entity == null:
		return false
	if "defense" in entity and entity.defense != null:
		return entity.defense.wedge_up
	if "drive_burn_remaining_s" in entity:
		return entity.drive_burn_remaining_s > 0.0
	# Unknown entity shape: fail open (treat as detectable) rather than
	# silently hiding an entity type nobody accounted for.
	return true


## ТЗ §24: jamming shrinks the effective range at which a lock can be
## held. `target_ecm` is the TARGET's own ECMState (its jammers work
## against whoever is trying to detect IT), or null for no ECM effect.
##
## ТЗ §25: `observer_subsystems` is the OBSERVER's own ShipSubsystems --
## its SENSORS condition further scales the range it can achieve, on top
## of (not instead of) any jamming penalty against the target.
static func _effective_sensor_range_m(base_range_m: float, target_ecm, observer_subsystems) -> float:
	var range_m: float = base_range_m
	if target_ecm != null and target_ecm.jamming_active:
		range_m *= target_ecm.jamming_range_multiplier
	if observer_subsystems != null:
		range_m *= observer_subsystems.get_condition(SubsystemType.Type.SENSORS)
	return range_m


## ТЗ §24: when the target is jamming and has decoys deployed, the
## observer's sensor may resolve onto whichever return (true target or a
## decoy) is nearest to the observer -- deterministic, no RNG (§43).
## Returns [apparent_position, apparent_velocity]; velocity is ZERO for a
## decoy stand-in (decoys are treated as station-keeping relative to the
## ship they escort -- ASSUMPTION, see ecm_state.gd/ASSUMPTIONS.md).
static func _resolve_apparent_return(true_position: Vector3, true_velocity: Vector3, observer_position: Vector3, target_ecm) -> Array:
	if target_ecm == null or not target_ecm.jamming_active or target_ecm.decoy_positions.is_empty():
		return [true_position, true_velocity]

	var best_position: Vector3 = true_position
	var best_velocity: Vector3 = true_velocity
	var best_distance: float = observer_position.distance_to(true_position)
	for decoy_position in target_ecm.decoy_positions:
		var d: float = observer_position.distance_to(decoy_position)
		if d < best_distance:
			best_distance = d
			best_position = decoy_position
			best_velocity = Vector3.ZERO
	return [best_position, best_velocity]


## Advances one SensorContact by dt sim-seconds given the observer's
## position and the target's current true position/velocity (the
## simulation always has ground truth available; SensorResolution is what
## limits what the OBSERVER is allowed to believe/use downstream).
##
## `target_ecm` (optional, default null): the TARGET's ECMState. Passing
## it applies §24 jamming/decoy effects; omitting it keeps the pre-ECM
## behavior exactly as before.
##
## `observer_subsystems` (optional, default null): the OBSERVER's own
## ShipSubsystems (ТЗ §25). A disabled SENSORS subsystem
## (`is_disabled(SubsystemType.Type.SENSORS)`) blocks any fresh detection
## outright, regardless of range; otherwise its condition scales the
## effective range continuously. Omitting it keeps pre-§25 behavior
## (perfect, undamaged sensors) -- every existing caller/test is
## unaffected.
static func update_contact(contact: SensorContact, observer_position: Vector3, dt: float, sensor_range_m: float = DEFAULT_SENSOR_RANGE_M, target_ecm = null, observer_subsystems = null) -> void:
	var target = contact.target
	if target == null:
		return

	var true_position: Vector3 = target.position
	var true_velocity: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO

	var sensors_disabled: bool = observer_subsystems != null and observer_subsystems.is_disabled(SubsystemType.Type.SENSORS)
	var effective_range_m: float = _effective_sensor_range_m(sensor_range_m, target_ecm, observer_subsystems)
	var in_range: bool = (not sensors_disabled) and observer_position.distance_to(true_position) <= effective_range_m
	var emitting: bool = _is_emitting_signature(target)
	var detected_this_tick: bool = in_range and emitting

	if detected_this_tick:
		var apparent: Array = _resolve_apparent_return(true_position, true_velocity, observer_position, target_ecm)
		contact.estimated_position = apparent[0]
		contact.estimated_velocity = apparent[1]
		contact.last_detection_sim_time = contact.continuous_detection_s
		contact.time_since_lost_s = 0.0
		contact.continuous_detection_s += dt

		match contact.state:
			ContactState.Type.UNKNOWN, ContactState.Type.LOST:
				contact.state = ContactState.Type.DETECTED
				contact.continuous_detection_s = dt
			ContactState.Type.DETECTED:
				if contact.continuous_detection_s >= DETECTED_TO_TRACKED_TIME_S:
					contact.state = ContactState.Type.TRACKED
			ContactState.Type.ESTIMATED, ContactState.Type.UNCERTAIN:
				contact.state = ContactState.Type.DETECTED
				contact.continuous_detection_s = dt
			ContactState.Type.TRACKED:
				pass
	else:
		contact.continuous_detection_s = 0.0

		match contact.state:
			ContactState.Type.UNKNOWN:
				pass
			ContactState.Type.DETECTED, ContactState.Type.TRACKED:
				contact.state = ContactState.Type.ESTIMATED
				contact.time_since_lost_s = 0.0
				# Dead-reckon forward from the last known state.
				contact.estimated_position += contact.estimated_velocity * dt
			ContactState.Type.ESTIMATED:
				contact.time_since_lost_s += dt
				contact.estimated_position += contact.estimated_velocity * dt
				if contact.time_since_lost_s >= ESTIMATED_GRACE_PERIOD_S:
					contact.state = ContactState.Type.LOST
			ContactState.Type.UNCERTAIN, ContactState.Type.LOST:
				contact.time_since_lost_s += dt


## Convenience: create-or-update a contact for `target` inside a
## Dictionary keyed by an arbitrary contact id (caller-chosen, e.g. the
## target ship's id string). Returns the contact.
static func update_contacts(contacts: Dictionary, contact_id, target, observer_position: Vector3, dt: float, sensor_range_m: float = DEFAULT_SENSOR_RANGE_M, target_ecm = null, observer_subsystems = null) -> SensorContact:
	var contact: SensorContact = contacts.get(contact_id)
	if contact == null:
		contact = SensorContact.new(target)
		contacts[contact_id] = contact
	update_contact(contact, observer_position, dt, sensor_range_m, target_ecm, observer_subsystems)
	return contact
