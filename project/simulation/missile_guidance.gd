extends RefCounted
## MissileGuidance
##
## ТЗ §19 Missile Guidance: "Do not implement guidance as merely:
## direction = target.position - missile.position". Must account for
## target position, estimated target position, target velocity, relative
## velocity, sensor update interval/tracking quality, terminal phase.
##
## This module implements PREDICTED INTERCEPT (lead pursuit): it solves for
## where the target will be when the missile arrives, given the target's
## current position/velocity, rather than chasing the target's current
## position. This is a standard, real guidance technique (true proportional
## navigation is a documented future refinement — see ASSUMPTIONS.md) and
## is enough to satisfy §19's requirement that velocity/prediction matter.
##
## ТЗ §23 Sensors wiring: `update_target_tracking()` / `resolve_thrust_direction()`
## connect this module to SensorResolution/SensorContact so a missile's own
## aim point is the OBSERVER'S ESTIMATE of the target (subject to detection
## range, signature, and dead-reckoning during ESTIMATED coast), never raw
## ground truth. A caller that skips these two functions and calls
## compute_thrust_direction() directly with ground-truth position/velocity
## and SensorState.TRACKED keeps the old "perfect information" behavior —
## this is what all existing tests still do, so nothing already-tested
## regresses; only a caller that opts into live tracking gets imperfect
## sensors.
class_name MissileGuidance

const SensorContact = preload("res://simulation/sensor_contact.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")

## Solves for an approximate time-to-intercept assuming the target moves at
## constant velocity and the missile closes at (roughly) its current speed.
## This is an approximation, not exact target-motion-analysis math — it
## iterates a few times to converge, which is sufficient for a fixed
## 60 Hz guidance update and avoids the complexity of solving the exact
## quadratic for a maneuvering, accelerating target (missiles re-solve
## every tick anyway, so a converged-enough estimate each tick is fine).
static func predict_intercept_point(missile_position: Vector3, missile_speed: float, target_position: Vector3, target_velocity: Vector3) -> Vector3:
	if missile_speed <= 0.0:
		return target_position

	var time_estimate: float = target_position.distance_to(missile_position) / missile_speed
	for i in range(4):
		var predicted_target_pos: Vector3 = target_position + target_velocity * time_estimate
		var new_time_estimate: float = predicted_target_pos.distance_to(missile_position) / missile_speed
		time_estimate = new_time_estimate

	return target_position + target_velocity * time_estimate

## Returns a unit thrust direction, in WORLD space, for the missile to
## apply this tick. sensor_state gates how good the target estimate is
## (ТЗ §19: "sensor update interval; tracking quality... loss of contact").
##
## Any state OTHER than DETECTED/TRACKED/ESTIMATED means "no usable current
## estimate" (UNKNOWN: never yet acquired; LOST: contact expired past the
## ESTIMATED grace period; UNCERTAIN: reserved, not currently produced by
## SensorResolution) -- in all of those the missile holds its current
## heading rather than steering toward an undefined/stale aim point.
static func compute_thrust_direction(missile, target_position_estimate: Vector3, target_velocity_estimate: Vector3, sensor_state: int) -> Vector3:
	const MissileStateRef = preload("res://simulation/missile_state.gd")

	var has_usable_track: bool = (
		sensor_state == MissileStateRef.SensorState.DETECTED
		or sensor_state == MissileStateRef.SensorState.TRACKED
		or sensor_state == MissileStateRef.SensorState.ESTIMATED
	)
	if not has_usable_track:
		# No usable track: hold current heading rather than snapping to a
		# stale/undefined aim point (§19: loss of contact must be handled,
		# not silently treated as perfect information).
		if missile.velocity.length_squared() > 0.0:
			return missile.velocity.normalized()
		return Vector3.FORWARD

	var current_speed: float = maxf(missile.velocity.length(), 1.0)  # avoid div-by-zero at launch
	var intercept_point: Vector3 = predict_intercept_point(
		missile.position, current_speed, target_position_estimate, target_velocity_estimate
	)

	var to_intercept: Vector3 = intercept_point - missile.position
	if to_intercept.length_squared() <= 0.0:
		return Vector3.FORWARD
	return to_intercept.normalized()

## ТЗ §23 Sensors wiring, step 1: advances (creating on first call) the
## missile's own SensorContact on its target by one tick, and syncs
## missile.sensor_state from the resulting contact state. Safe to call
## every simulation tick; a null target is a no-op (nothing to track).
static func update_target_tracking(missile, dt: float, sensor_range_m: float = SensorResolution.DEFAULT_SENSOR_RANGE_M) -> void:
	if missile.target == null:
		return
	if missile.sensor_contact == null:
		missile.sensor_contact = SensorContact.new(missile.target)
	SensorResolution.update_contact(missile.sensor_contact, missile.position, dt, sensor_range_m)
	missile.sensor_state = missile.sensor_contact.state

## ТЗ §23 Sensors wiring, step 2: the sensor-aware counterpart to calling
## compute_thrust_direction() directly with ground truth. Updates tracking
## for this tick, then computes thrust from the OBSERVER'S ESTIMATE (which
## may be dead-reckoned/stale during ESTIMATED, or absent during
## UNKNOWN/LOST) rather than missile.target's true position/velocity.
## This is what a live simulation loop should call each tick once it wants
## missiles to stop having perfect target knowledge; existing tests that
## call compute_thrust_direction() directly are unaffected.
static func resolve_thrust_direction(missile, dt: float, sensor_range_m: float = SensorResolution.DEFAULT_SENSOR_RANGE_M) -> Vector3:
	update_target_tracking(missile, dt, sensor_range_m)

	if missile.target == null:
		if missile.velocity.length_squared() > 0.0:
			return missile.velocity.normalized()
		return Vector3.FORWARD

	var contact = missile.sensor_contact
	return compute_thrust_direction(missile, contact.estimated_position, contact.estimated_velocity, missile.sensor_state)
