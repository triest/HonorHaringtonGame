extends RefCounted
## FormationOrder
##
## ТЗ §29 Formation Orders + §35 Command Queue (Milestone 10). Until this
## pass, "formation orders" existed only as the passive default (member
## station-keeping in SimulationWorld._resolve_formation_keeping, plus
## §33's leader-transfer re-plan) -- §29's list itself ("change course;
## change speed; accelerate; decelerate; hold formation; ...") was an
## honestly-logged gap: nothing let a player/AI actually ISSUE an
## intention to a formation's guide ship. This is a first slice of that:
## explicit orders that drive the GUIDE ship's own commanded thrust
## (members keep following the guide exactly as before -- an order
## changes where the wall is going, not how the wall holds together).
##
## Covers the two purely-kinematic order kinds from §29's list
## (CHANGE_COURSE and CHANGE_SPEED, which together also cover
## "accelerate"/"decelerate", both just CHANGE_SPEED with a higher/lower
## target), the explicit "stop maneuvering" order (HOLD_FORMATION), and
## (this pass) §29's "change formation" itself: CHANGE_FORMATION
## re-tasks the formation's STATION GEOMETRY (member_offsets), not the
## guide's course -- e.g. reforming a line-ahead into a line-abreast, or
## opening/closing spacing, without anyone leaving the formation. §29
## items that require target/weapon context (attack, select target,
## target distribution, missile use, counter-missile posture, defensive
## posture, evasive maneuver) or the full command hierarchy (§28) are
## OUT of scope for this slice -- honestly left open, see
## ASSUMPTIONS.md/CHANGELOG.md. "approach" and "withdraw"/"disengage" are
## provided as convenience composites of the two kinematic kinds (see
## `withdraw_orders` below), not new primitive kinds.
##
## INTERPRETATION, not canon: "change course" here retargets the guide's
## VELOCITY VECTOR (flight path), not necessarily its nose orientation --
## consistent with how this codebase already treats
## `commanded_thrust_local` as omnidirectional relative to facing (see
## ShipPhysicsState.integrate; only bow/stern sidewalls being raised
## blocks thrust, not facing). No Honorverse source specifies that a
## "change course" order forces the ship to point its nose along its new
## heading; modeling nose-orientation control is a separate, not-yet-
## built mechanic (no code anywhere currently drives `angular_velocity`
## from an AI/order -- see ASSUMPTIONS.md). See ASSUMPTIONS.md for the
## exact-stop acceleration clamp used to execute CHANGE_COURSE/
## CHANGE_SPEED without oscillation, and for CHANGE_FORMATION's
## "re-task the target, let existing station-keeping fly it" design.
class_name FormationOrder

enum Kind {
	HOLD_FORMATION,
	CHANGE_COURSE,
	CHANGE_SPEED,
	CHANGE_FORMATION,
}

var kind: int = Kind.HOLD_FORMATION

## World-space target velocity for CHANGE_COURSE/CHANGE_SPEED. Unused
## (left at zero) for HOLD_FORMATION/CHANGE_FORMATION.
var target_velocity_mps: Vector3 = Vector3.ZERO

## §29 "change formation": ship_id -> Vector3 NEW desired station offset,
## expressed in the guide's own local/body frame (same convention as
## FormationState.member_offsets/design_offsets). Unused (left empty)
## for the other three Kinds. Only ships present as KEYS here have their
## station reassigned -- a ship already in the formation but not
## mentioned keeps its current offset (a "change formation" order need
## not re-specify every station if only some are moving, e.g. opening
## spacing on one wing). A key not currently in the formation is simply
## added as a new member at that station (§29 does not distinguish
## "reform" from "take station" -- both are just "this ship's assigned
## offset is now X").
var new_offsets_local: Dictionary = {}

## ASSUMPTION: no canonical "order achieved" tolerance exists -- these
## are small, game-feel thresholds (a few degrees / a slow walking pace)
## chosen so floating-point noise near the target doesn't leave an order
## permanently "almost done", not tuned against any source.
var heading_tolerance_rad: float = 0.02
var speed_tolerance_mps: float = 0.5

## §29 "change course": hold the guide's CURRENT speed (read from `guide`
## at issue time -- frozen, does not track later speed changes from other
## causes) and retarget its direction to `new_heading_world`.
static func change_course(guide, new_heading_world: Vector3) -> FormationOrder:
	var order := FormationOrder.new()
	order.kind = Kind.CHANGE_COURSE
	var heading: Vector3 = new_heading_world.normalized()
	var speed: float = guide.velocity.length()
	order.target_velocity_mps = heading * speed
	return order

## §29 "change speed"/"accelerate"/"decelerate": retarget the guide's
## speed to `new_speed_mps` while holding a heading. If `heading_world`
## is given (nonzero), that EXPLICIT heading is used (needed when this
## order is queued to run after an earlier CHANGE_COURSE that hasn't
## executed yet -- at queue-build time the guide's actual velocity
## direction is still the OLD heading, so `withdraw_orders` below passes
## the intended new heading explicitly rather than relying on the
## guide's current velocity direction). Otherwise defaults to the
## guide's current velocity direction, or its nose orientation if it is
## presently stationary.
static func change_speed(guide, new_speed_mps: float, heading_world: Vector3 = Vector3.ZERO) -> FormationOrder:
	var order := FormationOrder.new()
	order.kind = Kind.CHANGE_SPEED
	var heading: Vector3
	if heading_world.length_squared() > 0.0001:
		heading = heading_world.normalized()
	elif guide.velocity.length_squared() > 0.0001:
		heading = guide.velocity.normalized()
	else:
		heading = guide.orientation * Vector3.FORWARD
	order.target_velocity_mps = heading * new_speed_mps
	return order

## §29 "withdraw"/"disengage" -- a composite, not a new primitive kind:
## turn to point directly away from the threat, THEN accelerate to
## `withdrawal_speed_mps` along that same heading. Both component orders
## are built against the EXPLICIT `away_direction_world` (not the
## guide's state at the time the second order actually starts executing,
## which by queue-order comes after the first has already turned the
## ship) -- see `change_speed`'s `heading_world` parameter doc above.
## Returns an Array[FormationOrder] meant for FormationState.issue_orders.
static func withdraw_orders(guide, away_direction_world: Vector3, withdrawal_speed_mps: float) -> Array:
	var away: Vector3 = away_direction_world.normalized()
	return [
		FormationOrder.change_course(guide, away),
		FormationOrder.change_speed(guide, withdrawal_speed_mps, away),
	]

static func hold_formation() -> FormationOrder:
	var order := FormationOrder.new()
	order.kind = Kind.HOLD_FORMATION
	return order

## §29 "change formation": reassign station offsets (guide's local/body
## frame) for the ships named as keys in `offsets_local`. Duplicated
## defensively so later mutation of the caller's Dictionary doesn't
## silently change an already-issued order behind its back.
static func change_formation(offsets_local: Dictionary) -> FormationOrder:
	var order := FormationOrder.new()
	order.kind = Kind.CHANGE_FORMATION
	order.new_offsets_local = offsets_local.duplicate()
	return order

## True once `guide`'s actual velocity is within tolerance of this
## order's target. HOLD_FORMATION never completes on its own (it is a
## standing order, replaced only by issuing something else) -- callers
## must not call this for HOLD_FORMATION expecting auto-dequeue.
## CHANGE_FORMATION is a re-tasking order, not a maneuver the GUIDE
## flies -- it is considered complete the instant it is applied (see
## SimulationWorld._resolve_formation_orders/_apply_change_formation);
## the actual flying of members into their newly-assigned stations is
## left entirely to the pre-existing station-keeping PD controller in
## `_resolve_formation_keeping`, exactly as it already flies members to
## their design stations after a leader transfer -- reusing that mature,
## already-tested convergence code rather than inventing a second one.
func is_complete(guide) -> bool:
	match kind:
		Kind.HOLD_FORMATION:
			return false
		Kind.CHANGE_COURSE:
			if target_velocity_mps.length_squared() <= 0.0001:
				return guide.velocity.length_squared() <= 0.0001
			if guide.velocity.length_squared() <= 0.0001:
				return false
			var angle: float = guide.velocity.normalized().angle_to(target_velocity_mps.normalized())
			return angle <= heading_tolerance_rad
		Kind.CHANGE_SPEED:
			return abs(guide.velocity.length() - target_velocity_mps.length()) <= speed_tolerance_mps
		_:
			return true
