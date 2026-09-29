extends RefCounted
## CounterMissileResolution
##
## ТЗ §20 Counter-Missiles: "launch from ships; receive target information;
## track incoming missiles; calculate interception; maneuver; account for
## sensor information; interact with ECM; produce a real intercept result."
##
## CANON kill mechanism (Honorverse Wiki "Missile", verified this session):
## countermissiles attempt to "overlap their over-powered, out-sized
## impeller wedges with the wedges of the attacking missiles" -- this is
## NOT a direct kinetic collision and NOT a simple proximity warhead blast;
## it is a wedge-vs-wedge interaction. Per the already-established wedge
## canon (CANON_RULES.md: "any object entering the [wedge] is
## instantaneously destroyed by tidal gravitational forces"), a successful
## overlap is mutually destructive -- both the incoming missile and the
## counter-missile are spent in the intercept, which matches Honorverse
## being a "trade munitions for munitions" defense-in-depth setting rather
## than counter-missiles surviving to re-engage.
##
## INTERPRETATION / ASSUMPTION (no canonical number found for the exact
## effective wedge-overlap radius): `INTERCEPT_KILL_RADIUS_M` below is a
## documented placeholder, not a canonical figure. See ASSUMPTIONS.md.
##
## ТЗ §25 Subsystem Damage / COUNTER_MISSILE_SYSTEMS: INTERPRETATION (no
## canonical source distinguishes a hull "counter-missile systems"
## subsystem from the counter-missile's own onboard guidance) --
## `check_intercept()`'s optional `counter_missile_system_condition`
## represents the LAUNCHING SHIP's fire-control uplink that feeds terminal
## targeting corrections to its own already-launched counter-missile
## (the counter-missile's flight itself is guided independently by
## MissileGuidance, unaffected). A degraded condition shrinks the
## effective wedge-overlap kill radius achievable via that uplink --
## same "deeper simulation model, not a flat modifier" pattern already
## used by ECMState.jamming_range_multiplier -- rather than gating
## intercept as a binary on/off. Wired by SimulationWorld
## (_resolve_counter_missile_intercepts), which looks up the
## counter-missile's OWN launching ship (via `missile_owners`, not the
## incoming missile's) each tick.
class_name CounterMissileResolution

const MissileState = preload("res://simulation/missile_state.gd")

## ASSUMPTION placeholder: distance at which a counter-missile's oversized
## wedge is considered to have overlapped the incoming missile's wedge
## closely enough to guarantee mutual destruction. A finer model would
## make this probabilistic based on relative closing geometry/wedge
## strength rather than a hard radius -- left as a documented TODO.
##
## 2026-09-29: raised 5 km -> 40 km after tracing live counter-missiles in
## the canon-scale demo (probe_cm_trace2.gd): closing speeds are ~90,000
## km/s, and the residual ZEM-guidance miss against a target that is itself
## accelerating is ~1-10 km, so a 5 km radius made counter-missiles fail
## on geometry alone (crossing shots miss by 20-35 km per tick-swept
## closest approach). Still a placeholder for "oversized wedge overlap",
## not a canon figure (ASSUMPTIONS.md "контрракеты").
const INTERCEPT_KILL_RADIUS_M: float = 40_000.0

enum Outcome { NOT_TRACKING, ALREADY_RESOLVED, TOO_FAR, INTERCEPTED }

class InterceptResult:
	var outcome: int
	func _init(p_outcome: int) -> void:
		outcome = p_outcome

## Call once per tick per (counter_missile, incoming_missile) pair that is
## still mutually active, to check whether this tick's closing has
## achieved a wedge-overlap kill.
static func check_intercept(counter_missile, incoming_missile, counter_missile_system_condition: float = 1.0) -> InterceptResult:
	if counter_missile.target != incoming_missile:
		return InterceptResult.new(Outcome.NOT_TRACKING)

	if not counter_missile.is_active() or not incoming_missile.is_active():
		return InterceptResult.new(Outcome.ALREADY_RESOLVED)

	var distance: float = counter_missile.position.distance_to(incoming_missile.position)
	var effective_kill_radius: float = INTERCEPT_KILL_RADIUS_M * clampf(counter_missile_system_condition, 0.0, 1.0)
	if distance > effective_kill_radius:
		return InterceptResult.new(Outcome.TOO_FAR)

	counter_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	incoming_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	return InterceptResult.new(Outcome.INTERCEPTED)

## 2026-09-29: SWEPT variant used by the live world loop. At canon closing
## speeds (tens of thousands of km/s) a counter-missile and its target
## cross ~10,000 km per 0.1 s tick, so the end-of-tick distance test in
## check_intercept() essentially never fires (same tunnelling problem
## MissileState.integrate() already solves for laserhead arming). Here the
## RELATIVE motion over the tick is taken as linear between the start-of-
## tick positions (`cm_prev`, `incoming_prev`) and the end-of-tick ones,
## and the closest approach over that segment is compared to the kill
## radius. Same outcomes/side effects as check_intercept().
static func check_intercept_swept(counter_missile, incoming_missile, cm_prev: Vector3, incoming_prev: Vector3, counter_missile_system_condition: float = 1.0) -> InterceptResult:
	if counter_missile.target != incoming_missile:
		return InterceptResult.new(Outcome.NOT_TRACKING)
	if not counter_missile.is_active() or not incoming_missile.is_active():
		return InterceptResult.new(Outcome.ALREADY_RESOLVED)

	var rel_start: Vector3 = incoming_prev - cm_prev
	var rel_end: Vector3 = incoming_missile.position - counter_missile.position
	var seg: Vector3 = rel_end - rel_start
	var seg_len_sq: float = seg.length_squared()
	var closest: float = rel_end.length()
	if seg_len_sq > 0.0:
		var t: float = clampf(-rel_start.dot(seg) / seg_len_sq, 0.0, 1.0)
		closest = minf(closest, (rel_start + seg * t).length())
	var effective_kill_radius: float = INTERCEPT_KILL_RADIUS_M * clampf(counter_missile_system_condition, 0.0, 1.0)
	if closest > effective_kill_radius:
		return InterceptResult.new(Outcome.TOO_FAR)

	counter_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	incoming_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	return InterceptResult.new(Outcome.INTERCEPTED)
