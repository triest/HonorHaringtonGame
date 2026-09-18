extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const MissileGuidance = preload("res://simulation/missile_guidance.gd")
const CounterMissileResolution = preload("res://simulation/counter_missile_resolution.gd")
## Milestone 6a headless smoke tests: counter-missiles as real 3D entities
## targeting an incoming missile, using the same guidance code as an
## offensive missile (ТЗ §20).
## Run: godot4 --headless --script res://simulation/tests/test_counter_missile.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_counter_missile_guidance_targets_a_missile_not_a_ship()
	failures += _test_too_far_no_intercept()
	failures += _test_close_range_produces_intercept_and_kills_both()
	failures += _test_wrong_target_pair_not_tracking()
	failures += _test_full_engagement_counter_missile_closes_and_kills_incoming()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_counter_missile_guidance_targets_a_missile_not_a_ship() -> int:
	# Proves MissileGuidance works via duck typing against a MissileState
	# target, not just ShipPhysicsState (ТЗ §20: counter-missiles track
	# incoming missiles, reusing the same guidance math).
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -20000.0)
	incoming.velocity = Vector3(200.0, 0, 0)

	var cm := MissileState.new()
	cm.target = incoming
	var dir := MissileGuidance.compute_thrust_direction(cm, incoming.position, incoming.velocity, MissileState.SensorState.TRACKED)
	var ok: bool = dir.length_squared() > 0.0 and dir.x > 0.0  # leads the crossing target, same as vs-ship test
	if not ok:
		printerr("FAIL counter_missile_guidance_targets_a_missile_not_a_ship: dir=%s" % dir)
		return 1
	return 0

func _test_too_far_no_intercept() -> int:
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -50000.0)
	var cm := MissileState.new()
	cm.target = incoming
	cm.position = Vector3.ZERO
	var result := CounterMissileResolution.check_intercept(cm, incoming)
	var ok: bool = result.outcome == CounterMissileResolution.Outcome.TOO_FAR and cm.is_active() and incoming.is_active()
	if not ok:
		printerr("FAIL too_far_no_intercept: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_close_range_produces_intercept_and_kills_both() -> int:
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -1000.0)
	var cm := MissileState.new()
	cm.target = incoming
	cm.position = Vector3.ZERO
	var result := CounterMissileResolution.check_intercept(cm, incoming)
	var ok: bool = result.outcome == CounterMissileResolution.Outcome.INTERCEPTED
	ok = ok and cm.is_intercepted() and incoming.is_intercepted()
	ok = ok and not cm.is_active() and not incoming.is_active()
	if not ok:
		printerr("FAIL close_range_produces_intercept_and_kills_both: outcome=%s cm=%s incoming=%s" % [result.outcome, cm.guidance_state, incoming.guidance_state])
		return 1
	return 0

func _test_wrong_target_pair_not_tracking() -> int:
	var incoming_a := MissileState.new()
	var incoming_b := MissileState.new()
	var cm := MissileState.new()
	cm.target = incoming_a
	var result := CounterMissileResolution.check_intercept(cm, incoming_b)
	var ok: bool = result.outcome == CounterMissileResolution.Outcome.NOT_TRACKING
	if not ok:
		printerr("FAIL wrong_target_pair_not_tracking: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_full_engagement_counter_missile_closes_and_kills_incoming() -> int:
	# End-to-end: a counter-missile launched behind an inbound missile,
	# guided every tick via MissileGuidance, should close the gap and
	# eventually produce an INTERCEPTED result within a bounded number of
	# ticks -- proving guidance + intercept resolution work together, not
	# just in isolation.
	var incoming := MissileState.new()
	incoming.position = Vector3(0, 0, -300000.0)  # 300 km out, closing on a notional ship at origin
	incoming.velocity = Vector3(0, 0, 3000.0)      # already closing toward +Z (toward origin)
	incoming.drive_burn_remaining_s = 0.0          # ballistic incoming missile: simpler, deterministic test

	var cm := MissileState.new()
	cm.position = Vector3(0, 0, -250000.0)  # launched from a point defense ship further out
	cm.target = incoming
	cm.drive_max_acceleration_mps2 = 130_000.0 * 9.80665  # CANON: Mark 31 ~130,000G
	cm.drive_burn_time_s = 75.0
	cm.drive_burn_remaining_s = 75.0

	var dt: float = 1.0 / 60.0
	var intercepted: bool = false
	for i in range(3600):  # up to 60 simulated seconds
		var dir := MissileGuidance.compute_thrust_direction(cm, incoming.position, incoming.velocity, MissileState.SensorState.TRACKED)
		cm.integrate(dt, dir)
		incoming.integrate(dt, Vector3.ZERO)  # ballistic, no course changes
		var result := CounterMissileResolution.check_intercept(cm, incoming)
		if result.outcome == CounterMissileResolution.Outcome.INTERCEPTED:
			intercepted = true
			break

	if not intercepted:
		printerr("FAIL full_engagement: never intercepted, final distance=%s" % cm.position.distance_to(incoming.position))
		return 1
	return 0
