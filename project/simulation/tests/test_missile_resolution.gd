extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")
const LasingRod = preload("res://simulation/lasing_rod.gd")

func _init() -> void:
	var failures: int = 0
	failures += _test_not_armed_does_not_detonate()
	failures += _test_armed_hit_unprotected_damages_hull()
	failures += _test_armed_wedge_blocks()
	failures += _test_cannot_detonate_twice()
	failures += _test_rods_eject_at_configured_count_and_offset()
	failures += _test_rod_damage_sums_to_total_laserhead_damage()
	failures += _test_single_rod_fallback_still_works()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_not_armed_does_not_detonate() -> int:
	var target := ShipPhysicsState.new()
	var m := MissileState.new()
	m.target = target
	m.warhead_armed = false
	var result := MissileResolution.resolve_detonation(m, null)
	var ok: bool = result.outcome == MissileResolution.Outcome.NOT_ARMED and not m.has_detonated
	if not ok:
		printerr("FAIL not_armed_does_not_detonate: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_armed_hit_unprotected_damages_hull() -> int:
	var target := ShipPhysicsState.new()
	var m := MissileState.new()
	m.target = target
	m.warhead_armed = true
	m.laserhead_damage = 250.0
	var hull := HullState.new()
	var result := MissileResolution.resolve_detonation(m, hull)
	var ok: bool = result.outcome == MissileResolution.Outcome.HIT_UNPROTECTED and hull.integrity == hull.max_integrity - 250.0 and m.has_detonated and m.guidance_state == MissileState.GuidanceState.DETONATED
	if not ok:
		printerr("FAIL armed_hit_unprotected_damages_hull: outcome=%s hull=%s" % [result.outcome, hull.integrity])
		return 1
	return 0

func _test_armed_wedge_blocks() -> int:
	var target := ShipPhysicsState.new()
	target.defense = ShipDefenseState.new()
	target.defense.wedge_up = true
	var m := MissileState.new()
	m.target = target
	m.position = Vector3(0, 1000.0, 0)  # above target -> TOP sector -> wedge
	m.warhead_armed = true
	var hull := HullState.new()
	var result := MissileResolution.resolve_detonation(m, hull)
	var ok: bool = result.outcome == MissileResolution.Outcome.WEDGE_BLOCKED and hull.integrity == hull.max_integrity
	if not ok:
		printerr("FAIL armed_wedge_blocks: outcome=%s hull=%s" % [result.outcome, hull.integrity])
		return 1
	return 0

func _test_cannot_detonate_twice() -> int:
	var target := ShipPhysicsState.new()
	var m := MissileState.new()
	m.target = target
	m.warhead_armed = true
	var hull := HullState.new()
	MissileResolution.resolve_detonation(m, hull)
	var integrity_after_first: float = hull.integrity
	var result_second := MissileResolution.resolve_detonation(m, hull)
	var ok: bool = result_second.outcome == MissileResolution.Outcome.ALREADY_DETONATED and hull.integrity == integrity_after_first
	if not ok:
		printerr("FAIL cannot_detonate_twice: outcome=%s hull=%s vs %s" % [result_second.outcome, hull.integrity, integrity_after_first])
		return 1
	return 0

func _test_rods_eject_at_configured_count_and_offset() -> int:
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -100000.0)
	var m := MissileState.new()
	m.target = target
	m.position = Vector3.ZERO
	m.rod_count = 6
	m.rod_offset_m = 100.0

	var positions: Array = MissileResolution.compute_rod_positions(m)
	var ok: bool = positions.size() == 6
	for p in positions:
		var dist_from_missile: float = (p as Vector3).distance_to(m.position)
		ok = ok and absf(dist_from_missile - 100.0) < 0.01
	if not ok:
		printerr("FAIL rods_eject_at_configured_count_and_offset: count=%s" % positions.size())
		return 1
	return 0

func _test_rod_damage_sums_to_total_laserhead_damage() -> int:
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -50000.0)
	var m := MissileState.new()
	m.target = target
	m.warhead_armed = true
	m.laserhead_damage = 600.0
	m.rod_count = 6
	var hull := HullState.new()
	var result := MissileResolution.resolve_detonation(m, hull)
	# No defense on target -> every rod fully unprotected -> total damage
	# should equal the full laserhead_damage (split across rods, then summed).
	var ok: bool = result.rod_results.size() == 6 and absf(result.damage_dealt - 600.0) < 0.01 and absf((hull.max_integrity - hull.integrity) - 600.0) < 0.01
	if not ok:
		printerr("FAIL rod_damage_sums_to_total_laserhead_damage: results=%s dealt=%s hull=%s" % [result.rod_results.size(), result.damage_dealt, hull.integrity])
		return 1
	return 0

func _test_single_rod_fallback_still_works() -> int:
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -50000.0)
	var m := MissileState.new()
	m.target = target
	m.warhead_armed = true
	m.laserhead_damage = 300.0
	m.rod_count = 1
	var hull := HullState.new()
	var result := MissileResolution.resolve_detonation(m, hull)
	var ok: bool = result.rod_results.size() == 1 and absf(result.damage_dealt - 300.0) < 0.01
	if not ok:
		printerr("FAIL single_rod_fallback_still_works: results=%s dealt=%s" % [result.rod_results.size(), result.damage_dealt])
		return 1
	return 0
