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
class_name CounterMissileResolution

const MissileState = preload("res://simulation/missile_state.gd")

## ASSUMPTION placeholder: distance at which a counter-missile's oversized
## wedge is considered to have overlapped the incoming missile's wedge
## closely enough to guarantee mutual destruction. A finer model would
## make this probabilistic based on relative closing geometry/wedge
## strength rather than a hard radius -- left as a documented TODO.
const INTERCEPT_KILL_RADIUS_M: float = 5_000.0

enum Outcome { NOT_TRACKING, ALREADY_RESOLVED, TOO_FAR, INTERCEPTED }

class InterceptResult:
	var outcome: int
	func _init(p_outcome: int) -> void:
		outcome = p_outcome

## Call once per tick per (counter_missile, incoming_missile) pair that is
## still mutually active, to check whether this tick's closing has
## achieved a wedge-overlap kill.
static func check_intercept(counter_missile, incoming_missile) -> InterceptResult:
	if counter_missile.target != incoming_missile:
		return InterceptResult.new(Outcome.NOT_TRACKING)

	if not counter_missile.is_active() or not incoming_missile.is_active():
		return InterceptResult.new(Outcome.ALREADY_RESOLVED)

	var distance: float = counter_missile.position.distance_to(incoming_missile.position)
	if distance > INTERCEPT_KILL_RADIUS_M:
		return InterceptResult.new(Outcome.TOO_FAR)

	counter_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	incoming_missile.guidance_state = MissileState.GuidanceState.INTERCEPTED
	return InterceptResult.new(Outcome.INTERCEPTED)
