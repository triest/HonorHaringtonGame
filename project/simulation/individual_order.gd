extends RefCounted
## IndividualOrder
##
## ТЗ §30 Individual Ship Orders + §31 Individual Override (Milestone 11,
## first slice). Until this pass, EVERY ship's `commanded_thrust_local`
## was set only by whichever automatic system happened to run last each
## tick (formation station-keeping, critical-damage retreat) -- there was
## no way to give a SINGLE ship an explicit intention independent of its
## formation, and no representation at all of §31's "an individual ship
## can temporarily override its formation's order" (the worked example:
## "Ship A: Intercept Incoming Missile" while the formation still says
## "Hold Formation", then "Ship A: Return To Formation Control").
##
## This covers the purely-kinematic subset of §30's list that this
## codebase can already execute honestly without inventing new weapon/
## targeting context: course, acceleration/speed, and (new in this pass)
## orientation. §30 items that need target/weapon context (target,
## target priority, weapon mode, missile launch, counter-missile policy,
## point-defense policy, sensor mode, ECM mode, defensive posture) are
## OUT of scope for this slice -- honestly left open, see ASSUMPTIONS.md.
## "retreat"/"disengage" are provided as convenience composites of
## course+speed (see `withdraw_orders`), exactly mirroring
## FormationOrder's own withdraw_orders and, like that one, a DIFFERENT
## mechanism from SimulationWorld._resolve_damage_response's automatic
## health-triggered retreat -- this is an explicitly ISSUED order for one
## ship, not a sensor-honest automatic reaction. "return to formation" is
## not a Kind here at all -- it is simply clearing this ship's order/queue
## (see SimulationWorld.return_ship_to_formation); there is no maneuver to
## execute, only a command-authority change.
##
## Deliberately NOT a generalization/merge with FormationOrder despite the
## obvious overlap for CHANGE_COURSE/CHANGE_SPEED (duplicated here, not
## factored into a shared base class): FormationOrder is guide-of-a-
## formation-specific, already fully tested, and used in a hot path
## (`_resolve_formation_orders`) -- risking a refactor of that tested code
## in the same pass that introduces a NEW, still-shaky concept (per-ship
## override state) is not worth it for two short kinematic blocks. See
## ASSUMPTIONS.md.
##
## INTERPRETATION, not canon: "orientation" here means the ship's NOSE
## direction (`Vector3.FORWARD` in the ship's own body frame, transformed
## by `orientation`), independent of its velocity vector -- this is the
## first code anywhere in this project to actually drive `angular_velocity`
## from an order (previously an honestly-logged gap, see CHANGELOG.md/
## ASSUMPTIONS.md history). No Honorverse source specifies attitude-control
## authority/rates; `ShipPhysicsState.max_angular_speed_rad_s` (an existing
## but previously-unused field) is used as the turn-rate limit, and the
## exact-stop clamp technique already used for CHANGE_COURSE/CHANGE_SPEED
## is reused for rotation so a ship reaches (never overshoots/oscillates
## past) its ordered facing. See ASSUMPTIONS.md for the body-frame vs.
## world-frame reasoning (`KinematicsUtils.integrate_orientation` composes
## `orientation * delta_rotation`, i.e. a BODY-frame angular velocity, not
## world-frame -- this order's axis/angle math is done entirely in the
## ship's own local frame to stay consistent with that).
class_name IndividualOrder

enum Kind {
	HOLD,
	CHANGE_COURSE,
	CHANGE_SPEED,
	CHANGE_ORIENTATION,
}

var kind: int = Kind.HOLD

## World-space target velocity for CHANGE_COURSE/CHANGE_SPEED. Unused for
## HOLD/CHANGE_ORIENTATION.
var target_velocity_mps: Vector3 = Vector3.ZERO

## World-space target NOSE direction for CHANGE_ORIENTATION. Unused for
## the other three Kinds. Need not be a unit vector (normalized on use).
var target_facing_world: Vector3 = Vector3.ZERO

## ASSUMPTION: same as FormationOrder -- small, game-feel tolerances, not
## tuned against any canonical source.
var heading_tolerance_rad: float = 0.02
var speed_tolerance_mps: float = 0.5
var orientation_tolerance_rad: float = 0.02

## §30 "course": hold the ship's CURRENT speed and retarget its velocity
## direction to `new_heading_world`.
static func change_course(ship, new_heading_world: Vector3) -> IndividualOrder:
	var order := IndividualOrder.new()
	order.kind = Kind.CHANGE_COURSE
	var heading: Vector3 = new_heading_world.normalized()
	var speed: float = ship.velocity.length()
	order.target_velocity_mps = heading * speed
	return order

## §30 "speed"/"acceleration": retarget the ship's speed to `new_speed_mps`
## while holding a heading. `heading_world`, if given, is used explicitly
## (needed for a queued order built before an earlier CHANGE_COURSE has
## actually executed -- see FormationOrder.change_speed's identical
## reasoning). Otherwise defaults to the ship's current velocity
## direction, or its nose orientation if presently stationary.
static func change_speed(ship, new_speed_mps: float, heading_world: Vector3 = Vector3.ZERO) -> IndividualOrder:
	var order := IndividualOrder.new()
	order.kind = Kind.CHANGE_SPEED
	var heading: Vector3
	if heading_world.length_squared() > 0.0001:
		heading = heading_world.normalized()
	elif ship.velocity.length_squared() > 0.0001:
		heading = ship.velocity.normalized()
	else:
		heading = ship.orientation * Vector3.FORWARD
	order.target_velocity_mps = heading * new_speed_mps
	return order

## §30 "orientation": turn the ship's nose to point along `facing_world`,
## independent of its velocity vector (a ship can face one way while
## still coasting/thrusting another, exactly as the rest of this codebase
## already treats impeller thrust as omnidirectional relative to facing).
static func change_orientation(facing_world: Vector3) -> IndividualOrder:
	var order := IndividualOrder.new()
	order.kind = Kind.CHANGE_ORIENTATION
	order.target_facing_world = facing_world.normalized()
	return order

## §30 "retreat"/"disengage" -- a composite, not a new primitive Kind,
## exactly mirroring FormationOrder.withdraw_orders: turn to point away
## from the threat, then accelerate to `withdrawal_speed_mps` along that
## same heading. Both legs are built against the EXPLICIT
## `away_direction_world` so the second order doesn't depend on the
## ship's actual heading at the moment it starts executing (which, by
## queue order, is AFTER the turn has already happened).
static func withdraw_orders(ship, away_direction_world: Vector3, withdrawal_speed_mps: float) -> Array:
	var away: Vector3 = away_direction_world.normalized()
	return [
		IndividualOrder.change_course(ship, away),
		IndividualOrder.change_speed(ship, withdrawal_speed_mps, away),
	]

static func hold() -> IndividualOrder:
	var order := IndividualOrder.new()
	order.kind = Kind.HOLD
	return order

## True once `ship`'s actual state is within tolerance of this order's
## target. HOLD never completes on its own (a standing order, replaced
## only by issuing something else or by return-to-formation clearing it).
func is_complete(ship) -> bool:
	match kind:
		Kind.HOLD:
			return false
		Kind.CHANGE_COURSE:
			if target_velocity_mps.length_squared() <= 0.0001:
				return ship.velocity.length_squared() <= 0.0001
			if ship.velocity.length_squared() <= 0.0001:
				return false
			var angle: float = ship.velocity.normalized().angle_to(target_velocity_mps.normalized())
			return angle <= heading_tolerance_rad
		Kind.CHANGE_SPEED:
			return abs(ship.velocity.length() - target_velocity_mps.length()) <= speed_tolerance_mps
		Kind.CHANGE_ORIENTATION:
			var world_forward: Vector3 = ship.orientation * Vector3.FORWARD
			var angle_err: float = world_forward.angle_to(target_facing_world)
			return angle_err <= orientation_tolerance_rad
		_:
			return true
