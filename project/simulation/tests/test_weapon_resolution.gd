extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const HullState = preload("res://simulation/hull_state.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")
## Milestone 4 headless smoke tests.
## Run: godot4 --headless --script res://simulation/tests/test_weapon_resolution.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_out_of_range()
	failures += _test_not_ready_during_cooldown()
	failures += _test_no_arc_broadside_cannot_hit_bow_target()
	failures += _test_wedge_blocks_top_shot()
	failures += _test_broadside_hits_and_damages_hull()
	failures += _test_cooldown_consumed_on_fire()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _make_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.id = "test_laser"
	w.max_range_m = 500_000.0
	w.damage_per_hit = 100.0
	w.recharge_time_s = 4.0
	return w

func _test_out_of_range() -> int:
	var attacker := ShipPhysicsState.new()
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -1_000_000.0)  # 1000 km, weapon range 500 km
	var mount := WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc())
	var result := WeaponResolution.fire(attacker, mount, target, null)
	var ok: bool = result.outcome == WeaponResolution.Outcome.OUT_OF_RANGE
	if not ok:
		printerr("FAIL out_of_range: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_not_ready_during_cooldown() -> int:
	var attacker := ShipPhysicsState.new()
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -1000.0)
	var mount := WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc())
	mount.cooldown_remaining_s = 2.0
	var result := WeaponResolution.fire(attacker, mount, target, null)
	var ok: bool = result.outcome == WeaponResolution.Outcome.NOT_READY
	if not ok:
		printerr("FAIL not_ready_during_cooldown: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_no_arc_broadside_cannot_hit_bow_target() -> int:
	var attacker := ShipPhysicsState.new()
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -1000.0)  # dead ahead of attacker (bow arc)
	var mount := WeaponMount.new(_make_weapon(), WeaponMount.broadside_arc())  # only PORT/STARBOARD
	var result := WeaponResolution.fire(attacker, mount, target, null)
	var ok: bool = result.outcome == WeaponResolution.Outcome.NO_ARC
	if not ok:
		printerr("FAIL no_arc_broadside_cannot_hit_bow_target: outcome=%s" % result.outcome)
		return 1
	return 0

func _test_wedge_blocks_top_shot() -> int:
	var attacker := ShipPhysicsState.new()
	attacker.position = Vector3(0, 1000.0, 0)  # above the target: attacker's own arc doesn't matter here since attacker fires "down" at own BOTTOM-relative... use omni arc for this test
	var target := ShipPhysicsState.new()
	target.defense = ShipDefenseState.new()
	target.defense.wedge_up = true

	var mount := WeaponMount.new(_make_weapon(), [0, 1, 2, 3, 4, 5])  # all sectors: isolate wedge behavior, not arc behavior
	var hull := HullState.new()
	var result := WeaponResolution.fire(attacker, mount, target, hull)
	var ok: bool = result.outcome == WeaponResolution.Outcome.WEDGE_BLOCKED and hull.integrity == hull.max_integrity
	if not ok:
		printerr("FAIL wedge_blocks_top_shot: outcome=%s hull=%s" % [result.outcome, hull.integrity])
		return 1
	return 0

func _test_broadside_hits_and_damages_hull() -> int:
	var attacker := ShipPhysicsState.new()
	attacker.position = Vector3(1000.0, 0, 0)  # to starboard of target's frame, and target is to starboard of attacker's frame (symmetric on X axis)
	var target := ShipPhysicsState.new()
	target.defense = ShipDefenseState.new()
	# Partial (not full) sidewall condition: a fully healthy sidewall (1.0)
	# fully attenuates per ship_defense_state.gd's linear model, so use a
	# degraded value to prove damage actually gets through and scales with
	# condition, per ТЗ §16 ("must interact with... geometry", not shieldHP).
	target.defense.port_sidewall_condition = 0.4
	target.defense.starboard_sidewall_condition = 0.4

	var mount := WeaponMount.new(_make_weapon(), WeaponMount.broadside_arc())
	var hull := HullState.new()
	var result := WeaponResolution.fire(attacker, mount, target, hull)
	var ok: bool = result.outcome == WeaponResolution.Outcome.SIDEWALL_ATTENUATED and hull.integrity < hull.max_integrity
	if not ok:
		printerr("FAIL broadside_hits_and_damages_hull: outcome=%s hull=%s" % [result.outcome, hull.integrity])
		return 1
	return 0

func _test_cooldown_consumed_on_fire() -> int:
	var attacker := ShipPhysicsState.new()
	var target := ShipPhysicsState.new()
	target.position = Vector3(0, 0, -1000.0)
	var mount := WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc())
	WeaponResolution.fire(attacker, mount, target, null)
	var ok: bool = mount.cooldown_remaining_s == mount.weapon.recharge_time_s and not mount.is_ready()
	if not ok:
		printerr("FAIL cooldown_consumed_on_fire: cooldown=%s" % mount.cooldown_remaining_s)
		return 1
	return 0
