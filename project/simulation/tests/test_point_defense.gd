extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
## Milestone: Point Defense headless smoke tests (ТЗ §22).
## Run: godot4 --headless --script res://simulation/tests/test_point_defense.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_no_target_resets()
	failures += _test_out_of_range()
	failures += _test_acquiring_before_reaction_time_elapses()
	failures += _test_full_engagement_kills_after_required_hits()
	failures += _test_switching_targets_resets_progress()
	failures += _test_missile_leaving_range_resets_progress()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _make_ship() -> ShipPhysicsState:
	return ShipPhysicsState.new()

func _make_missile_at(distance: float) -> MissileState:
	var m := MissileState.new()
	m.position = Vector3(0, 0, -distance)
	return m

func _test_no_target_resets() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	var result := PointDefenseResolution.engage(mount, ship, null, 1.0 / 60.0)
	var ok: bool = result.outcome == PointDefenseResolution.Outcome.NO_TARGET
	if not ok:
		printerr("FAIL no_target_resets: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_out_of_range() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.max_engagement_range_m = 20_000.0
	var missile := _make_missile_at(50_000.0)
	var result := PointDefenseResolution.engage(mount, ship, missile, 1.0 / 60.0)
	var ok: bool = result.outcome == PointDefenseResolution.Outcome.OUT_OF_RANGE
	if not ok:
		printerr("FAIL out_of_range: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_acquiring_before_reaction_time_elapses() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 1.0
	var missile := _make_missile_at(5000.0)
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	var ok: bool = result.outcome == PointDefenseResolution.Outcome.ACQUIRING
	if not ok:
		printerr("FAIL acquiring_before_reaction_time_elapses: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_full_engagement_kills_after_required_hits() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.5
	mount.recharge_time_s = 0.2
	mount.hits_required_to_kill = 3
	var missile := _make_missile_at(5000.0)

	var dt: float = 1.0 / 60.0
	var last_result
	var intercepted: bool = false
	for i in range(600):  # up to 10 simulated seconds
		last_result = PointDefenseResolution.engage(mount, ship, missile, dt)
		if last_result.outcome == PointDefenseResolution.Outcome.INTERCEPTED:
			intercepted = true
			break

	var ok: bool = intercepted and missile.is_intercepted() and last_result.hits_scored == 3
	if not ok:
		printerr("FAIL full_engagement_kills_after_required_hits: intercepted=%s missile_state=%s hits=%s" % [intercepted, missile.guidance_state, last_result.hits_scored if last_result else -1])
		return 1
	return 0

func _test_switching_targets_resets_progress() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.1
	mount.recharge_time_s = 0.05
	mount.hits_required_to_kill = 5

	var missile_a := _make_missile_at(5000.0)
	var missile_b := _make_missile_at(5000.0)
	var dt: float = 1.0 / 60.0

	# Engage A for a while (score some hits, but not enough to kill --
	# 15 ticks at dt=1/60 = 0.25s total: 0.1s reaction + up to 3 shots at
	# 0.05s recharge, well under hits_required_to_kill=5).
	for i in range(15):
		PointDefenseResolution.engage(mount, ship, missile_a, dt)
	var hits_on_a_before_switch: int = mount._hits_scored

	# Switch to B -- progress against A must not carry over.
	var result := PointDefenseResolution.engage(mount, ship, missile_b, dt)

	var ok: bool = hits_on_a_before_switch > 0 and result.outcome == PointDefenseResolution.Outcome.ACQUIRING and mount._hits_scored == 0
	if not ok:
		printerr("FAIL switching_targets_resets_progress: hits_before=%s outcome=%s hits_after=%s" % [hits_on_a_before_switch, result.outcome, mount._hits_scored])
		return 1
	return 0

func _test_missile_leaving_range_resets_progress() -> int:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.1
	mount.recharge_time_s = 0.05
	mount.max_engagement_range_m = 20_000.0
	mount.hits_required_to_kill = 5

	var missile := _make_missile_at(5000.0)
	var dt: float = 1.0 / 60.0
	for i in range(20):
		PointDefenseResolution.engage(mount, ship, missile, dt)
	var hits_before: int = mount._hits_scored

	missile.position = Vector3(0, 0, -50_000.0)  # jumps out of range
	var result := PointDefenseResolution.engage(mount, ship, missile, dt)

	var ok: bool = hits_before > 0 and result.outcome == PointDefenseResolution.Outcome.OUT_OF_RANGE and mount._hits_scored == 0
	if not ok:
		printerr("FAIL missile_leaving_range_resets_progress: hits_before=%s outcome=%s hits_after=%s" % [hits_before, result.outcome, mount._hits_scored])
		return 1
	return 0
