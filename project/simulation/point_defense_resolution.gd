extends RefCounted
## PointDefenseResolution
##
## Advances a PointDefenseMount's engagement against ONE candidate incoming
## missile by one tick (ТЗ §22 Point Defense: "sensor information;
## detection; tracking; weapon availability; geometry; range; reaction
## time; target state; ship damage; ECM/countermeasures where applicable").
##
## Caller contract: the ship/AI layer (not yet implemented -- no Milestone
## wires this into the live simulation loop yet, see ASSUMPTIONS.md) picks
## which single incoming missile a given mount should track this tick
## (e.g. nearest / highest threat) and calls `engage()` once per mount per
## tick with that choice. This module does not do target SELECTION itself
## (that is an AI/tactical concern, §26/§41), only engagement resolution
## for an already-chosen target -- same separation of concerns as
## WeaponResolution (fires at a given target) vs tactical AI (picks it).
##
## ТЗ §23 Sensors wiring: `engage()` now optionally accepts the ship's own
## `SensorContact` on the incoming missile. When one is passed, PD can only
## engage while that contact is DETECTED/TRACKED/ESTIMATED -- an
## `UNKNOWN`/`LOST` contact means the ship's own sensors do not currently
## have this missile, and PD must not fire on data it doesn't have
## (Outcome.NOT_DETECTED). Passing `null` (the default) keeps the old
## "trackable whenever in range" behavior for backward compatibility --
## every existing test/caller that never wires up a SensorContact is
## unaffected.
##
## HONEST GAPS (not implemented, see AGENTS.md §22/§24 for what these
## should eventually do): ECM does not yet degrade PD accuracy/tracking;
## ship subsystem damage does not yet degrade `condition`. These are real,
## named gaps, not silently skipped.
class_name PointDefenseResolution

const MissileState = preload("res://simulation/missile_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")

enum Outcome { NO_TARGET, NOT_DETECTED, OUT_OF_RANGE, ACQUIRING, NOT_READY, SHOT_FIRED, INTERCEPTED }

class EngagementResult:
	var outcome: int
	var hits_scored: int
	var hits_required: int
	func _init(p_outcome: int, p_hits_scored: int = 0, p_hits_required: int = 0) -> void:
		outcome = p_outcome
		hits_scored = p_hits_scored
		hits_required = p_hits_required

## ship: ShipPhysicsState carrying the mount. incoming_missile: the
## MissileState this mount is engaging this tick (or null to disengage).
## sensor_contact: optional SensorContact (already updated THIS tick by
## the caller, e.g. via SensorResolution.update_contacts()) representing
## the ship's own sensor track on incoming_missile. Null means "not
## sensor-gated" (legacy/perfect-detection behavior).
static func engage(mount: PointDefenseMount, ship, incoming_missile, dt: float, sensor_contact = null) -> EngagementResult:
	mount.tick_cooldown(dt)

	if incoming_missile == null or not incoming_missile.is_active():
		mount._reset_tracking()
		return EngagementResult.new(Outcome.NO_TARGET)

	if sensor_contact != null:
		var has_track: bool = (
			sensor_contact.state == ContactState.Type.DETECTED
			or sensor_contact.state == ContactState.Type.TRACKED
			or sensor_contact.state == ContactState.Type.ESTIMATED
		)
		if not has_track:
			mount._reset_tracking()
			return EngagementResult.new(Outcome.NOT_DETECTED)

	# Switching targets (or first acquisition) resets the engagement --
	# reaction time and hit count are PER TARGET, not banked across
	# different incoming missiles (§22: "reaction time" is a real cost).
	if mount._tracking_target != incoming_missile:
		mount._tracking_target = incoming_missile
		mount._tracking_time_s = 0.0
		mount._hits_scored = 0

	var distance: float = ship.position.distance_to(incoming_missile.position)
	if distance > mount.max_engagement_range_m:
		mount._reset_tracking()
		return EngagementResult.new(Outcome.OUT_OF_RANGE)

	mount._tracking_time_s += dt
	if mount._tracking_time_s < mount.reaction_time_s:
		return EngagementResult.new(Outcome.ACQUIRING, mount._hits_scored, mount.hits_required_to_kill)

	if not mount.is_ready():
		return EngagementResult.new(Outcome.NOT_READY, mount._hits_scored, mount.hits_required_to_kill)

	mount.cooldown_remaining_s = mount.recharge_time_s
	mount._hits_scored += 1

	if mount._hits_scored >= mount.hits_required_to_kill:
		incoming_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
		var final_hits: int = mount._hits_scored
		mount._reset_tracking()
		return EngagementResult.new(Outcome.INTERCEPTED, final_hits, mount.hits_required_to_kill)

	return EngagementResult.new(Outcome.SHOT_FIRED, mount._hits_scored, mount.hits_required_to_kill)
