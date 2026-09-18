extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const MissileGuidance = preload("res://simulation/missile_guidance.gd")
## Milestone 5 headless smoke tests: missile as a real 3D entity + predictive
## guidance (not "direction = target.position - missile.position").
## Run: godot4 --headless --script res://simulation/tests/test_missile.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_intercept_leads_a_moving_target()
	failures += _test_missile_accelerates_during_boost_then_coasts()
	failures += _test_missile_reaches_stationary_target_and_goes_terminal()
	failures += _test_lost_track_holds_heading_instead_of_snapping()
	failures += _test_missile_self_destructs_after_max_lifetime()
	failures += _test_throttle_extends_burn_time_and_preserves_delta_v_budget()
	failures += _test_canon_powered_range_sanity_check()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_intercept_leads_a_moving_target() -> int:
	var missile_pos := Vector3(0, 0, 0)
	var target_pos := Vector3(0, 0, -10000.0)
	var target_vel := Vector3(500.0, 0, 0)  # crossing laterally
	var intercept := MissileGuidance.predict_intercept_point(missile_pos, 2000.0, target_pos, target_vel)

	# A naive "aim at current position" guidance would point straight at
	# target_pos (x=0). Predictive guidance must lead the target: intercept
	# x must be meaningfully greater than 0.
	var ok: bool = intercept.x > 100.0
	if not ok:
		printerr("FAIL intercept_leads_a_moving_target: intercept=%s" % intercept)
		return 1
	return 0

func _test_missile_accelerates_during_boost_then_coasts() -> int:
	var m := MissileState.new()
	m.drive_burn_time_s = 1.0
	m.drive_burn_remaining_s = 1.0
	var dt: float = 1.0 / 60.0
	var forward := Vector3(0, 0, -1)
	for i in range(30):  # 0.5s, still burning
		m.integrate(dt, forward)
	var speed_mid_burn: float = m.velocity.length()

	for i in range(90):  # past burn-out (total 2s simulated)
		m.integrate(dt, forward)
	var speed_after_burnout: float = m.velocity.length()

	var ok: bool = speed_mid_burn > 0.0 and absf(speed_after_burnout - speed_mid_burn) > 0.0 and m.drive_burn_remaining_s == 0.0 and m.acceleration.length() == 0.0
	if not ok:
		printerr("FAIL accelerates_then_coasts: mid=%s after=%s burn_left=%s accel=%s" % [speed_mid_burn, speed_after_burnout, m.drive_burn_remaining_s, m.acceleration])
		return 1
	return 0

func _test_missile_reaches_stationary_target_and_goes_terminal() -> int:
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -20000.0)  # 20 km away, within a few seconds at missile speeds

	var m := MissileState.new()
	m.target = target
	m.terminal_detonation_range_m = 50_000.0
	m.drive_max_acceleration_mps2 = 500.0  # gentle, deterministic for this test
	m.drive_burn_time_s = 60.0
	m.drive_burn_remaining_s = 60.0

	var dt: float = 1.0 / 60.0
	for i in range(600):  # 10 simulated seconds
		var dir := MissileGuidance.compute_thrust_direction(m, target.position, target.velocity, MissileState.SensorState.TRACKED)
		m.integrate(dt, dir)
		if m.guidance_state == MissileState.GuidanceState.TERMINAL:
			break

	var ok: bool = m.guidance_state == MissileState.GuidanceState.TERMINAL
	if not ok:
		printerr("FAIL reaches_stationary_target_and_goes_terminal: state=%s dist=%s" % [m.guidance_state, m.position.distance_to(target.position)])
		return 1
	return 0

func _test_lost_track_holds_heading_instead_of_snapping() -> int:
	var m := MissileState.new()
	m.velocity = Vector3(0, 0, -1000.0)
	var dir := MissileGuidance.compute_thrust_direction(m, Vector3(99999, 99999, 99999), Vector3.ZERO, MissileState.SensorState.LOST)
	var ok: bool = dir.is_equal_approx(Vector3(0, 0, -1.0))
	if not ok:
		printerr("FAIL lost_track_holds_heading: dir=%s" % dir)
		return 1
	return 0

func _test_missile_self_destructs_after_max_lifetime() -> int:
	var m := MissileState.new()
	m.max_lifetime_s = 0.1
	var dt: float = 1.0 / 60.0
	for i in range(20):  # ~0.33s
		m.integrate(dt, Vector3(0, 0, -1))
	var ok: bool = m.guidance_state == MissileState.GuidanceState.SELF_DESTRUCTED and not m.is_active()
	if not ok:
		printerr("FAIL self_destructs_after_max_lifetime: state=%s" % m.guidance_state)
		return 1
	return 0

func _test_throttle_extends_burn_time_and_preserves_delta_v_budget() -> int:
	var m := MissileState.new()
	m.drive_max_acceleration_mps2 = 46_000.0 * 9.80665
	m.drive_burn_time_s = 180.0
	m.drive_burn_remaining_s = 180.0
	var base_budget: float = m.drive_max_acceleration_mps2 * m.drive_burn_time_s

	m.set_throttle(0.5)
	var throttled_budget: float = m.drive_max_acceleration_mps2 * m.drive_burn_time_s

	var ok: bool = absf(m.drive_max_acceleration_mps2 - (46_000.0 * 9.80665 * 0.5)) < 1.0
	ok = ok and absf(m.drive_burn_time_s - 360.0) < 0.01  # half accel -> double burn time
	ok = ok and m.drive_burn_remaining_s == m.drive_burn_time_s
	ok = ok and absf(throttled_budget - base_budget) < 1.0  # delta-v budget preserved
	if not ok:
		printerr("FAIL throttle_extends_burn_time: accel=%s burn=%s budget=%s vs %s" % [m.drive_max_acceleration_mps2, m.drive_burn_time_s, throttled_budget, base_budget])
		return 1
	return 0

func _test_canon_powered_range_sanity_check() -> int:
	# CANON (AGENTS.md §18.1): 46,000 G for ~180s gives "over six million
	# kilometers" of powered range. Our own estimator should land in the
	# same ballpark, as a sanity check that the formula/units are right.
	var m := MissileState.new()
	m.drive_max_acceleration_mps2 = 46_000.0 * 9.80665
	m.drive_burn_time_s = 180.0
	var range_m: float = m.estimated_powered_range_m()
	var range_km: float = range_m / 1000.0
	var ok: bool = range_km > 6_000_000.0 and range_km < 9_000_000.0
	if not ok:
		printerr("FAIL canon_powered_range_sanity_check: range_km=%s" % range_km)
		return 1
	return 0
