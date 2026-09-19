extends RefCounted
## KinematicsUtils
##
## Shared kinematics helpers used by both ShipPhysicsState and MissileState,
## so the ТЗ §15 "never silently exceed c" rule lives in exactly one place
## instead of being copy-pasted per entity type.
class_name KinematicsUtils

const SPEED_OF_LIGHT_MPS: float = 299_792_458.0

## ТЗ §15: clamp velocity to just under c rather than letting integration
## error push an object to/above light speed. ASSUMPTION: hard clamp, not a
## true relativistic treatment — see ASSUMPTIONS.md.
static func clamp_velocity_below_c(velocity: Vector3) -> Vector3:
	var speed := velocity.length()
	var limit := SPEED_OF_LIGHT_MPS * 0.999999
	if speed > limit:
		return velocity.normalized() * limit
	return velocity

## Semi-implicit Euler step shared by ships and missiles: thrust -> accel
## -> velocity -> position (ТЗ §12), with the c-clamp applied every tick.
## Returns [new_velocity, new_position].
static func integrate_linear(position: Vector3, velocity: Vector3, acceleration: Vector3, dt: float) -> Array:
	var new_velocity: Vector3 = clamp_velocity_below_c(velocity + acceleration * dt)
	var new_position: Vector3 = position + new_velocity * dt
	return [new_velocity, new_position]

## Shared orientation integration from an angular velocity vector
## (ship-independent, so missiles reuse the same turn-rate math).
static func integrate_orientation(orientation: Quaternion, angular_velocity: Vector3, dt: float) -> Quaternion:
	var angle: float = angular_velocity.length() * dt
	if angle <= 0.0:
		return orientation
	var axis: Vector3 = angular_velocity.normalized()
	var delta_rotation := Quaternion(axis, angle)
	return (orientation * delta_rotation).normalized()

## ТЗ §34.2 Missile Time-on-Target coordination: ENGINEERING ESTIMATE of
## how long a missile launched RIGHT NOW would take to cover `distance_m`
## in a straight line, given a constant boost-phase acceleration
## `max_acceleration_mps2` for up to `burn_time_s` before coasting
## ballistically at whatever speed the boost phase reached. This
## deliberately ignores the TARGET's own motion during the flight (a true
## intercept-time solve is a separate, still-open problem -- see
## AGENTS.md §41.1 "Crossing the T", which needs the same missing
## intercept-vector solver) and the missile's real guidance-driven curved
## path (same idealization already used by
## MissileState.estimated_powered_range_m()) -- it is a SCHEDULING
## heuristic for "roughly how far apart should two salvo members launch
## to land together", not a targeting solution. Returns INF if
## `max_acceleration_mps2 <= 0.0` (a missile that cannot accelerate never
## arrives).
static func estimate_boost_coast_time_to_distance_s(distance_m: float, max_acceleration_mps2: float, burn_time_s: float) -> float:
	if distance_m <= 0.0:
		return 0.0
	if max_acceleration_mps2 <= 0.0:
		return INF
	var burnout_distance_m: float = 0.5 * max_acceleration_mps2 * burn_time_s * burn_time_s
	if distance_m <= burnout_distance_m:
		return sqrt(2.0 * distance_m / max_acceleration_mps2)
	var burnout_speed_mps: float = max_acceleration_mps2 * burn_time_s
	var remaining_distance_m: float = distance_m - burnout_distance_m
	return burn_time_s + remaining_distance_m / burnout_speed_mps
