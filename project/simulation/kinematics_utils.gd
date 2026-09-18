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
