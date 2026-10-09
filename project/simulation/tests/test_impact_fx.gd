extends SceneTree
## Headless tests for the missile-impact feedback data path:
## SimulationWorld.last_tick_impacts / ImpactRecord (sim side) and
## ImpactFxDirector's pure helpers (render side, no scene tree needed).
## Run via: godot --headless --script res://simulation/tests/test_impact_fx.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")
const ImpactFxDirector = preload("res://scripts/impact_fx_director.gd")
const ImpactGeometry = preload("res://scripts/impact_geometry.gd")
const ImpactBadgeModel = preload("res://scripts/impact_badge_model.gd")
const ImpactBadgeOverlay = preload("res://scripts/impact_badge_overlay.gd")
const CameraFxController = preload("res://scripts/camera_fx_controller.gd")
const ShipDamageFx = preload("res://scripts/ship_damage_fx.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const ImpactRecord = preload("res://simulation/impact_record.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _init() -> void:
	_test_wedge_blocked_record()
	_test_unprotected_record_reports_hull_loss()
	_test_records_cleared_each_tick()
	_test_record_is_isolated_snapshot()
	_test_records_deterministic()
	_test_wedge_hit_center_local()
	_test_ripple_energy_bounds()
	_test_record_kind_and_geometry_fields()
	_test_beam_record_routed_into_impacts()
	_test_beam_miss_has_no_record()
	_test_sidewall_and_hull_strike_points()
	_test_strike_point_dispatch()
	_test_badge_model_merges_salvo()
	_test_badge_text()
	_test_camera_trauma()
	_test_vent_intensity()
	print("Passed: %d Failed: %d" % [_passed, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
	quit(_failures)

func _make_ship(wedge: bool) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = Vector3.ZERO
	if wedge:
		s.defense = ShipDefenseState.new()
		s.defense.wedge_up = true
	return s

## One armed missile sitting on top of (or above) a ship, detonating on tick 1.
func _world_with_missile(wedge: bool, missile_pos: Vector3) -> Array:
	var world := SimulationWorld.new()
	world.accuracy_enabled = false
	var target := _make_ship(wedge)
	var hull := HullState.new()
	world.add_ship("target", target, hull)
	var missile := MissileState.new()
	missile.position = missile_pos
	missile.velocity = Vector3(0, 0, 0)
	missile.target = target
	missile.terminal_detonation_range_m = 5000.0
	world.add_missile("m1", missile, "attacker")
	return [world, hull]

func _test_wedge_blocked_record() -> void:
	var w: Array = _world_with_missile(true, Vector3(0, 100.0, 0))  # above -> TOP sector
	var world: SimulationWorld = w[0]
	world.tick_simulation(1.0 / 60.0)
	_assert(world.last_tick_impacts.size() == 1, "one detonation should produce exactly one impact record")
	if world.last_tick_impacts.is_empty():
		return
	var rec: Dictionary = world.last_tick_impacts[0]
	_assert(rec["target_ship_id"] == "target" and rec["attacker_ship_id"] == "attacker", "record should carry attacker/target ids")
	_assert(rec["overall_outcome"] == MissileResolution.Outcome.WEDGE_BLOCKED, "TOP-sector strike on a raised wedge should be WEDGE_BLOCKED")
	_assert(rec["rods"].size() == 6, "default warhead has 6 lasing rods")
	_assert(is_equal_approx(rec["total_incoming"], 400.0), "total_incoming should equal the laserhead yield")
	_assert(rec["total_damage"] == 0.0 and is_equal_approx(rec["hull_before"], rec["hull_after"]), "a blocked strike must not hurt the hull")
	_assert(rec["wedge_up"], "record should snapshot wedge_up")
	for rod in rec["rods"]:
		_assert(rod["outcome"] == MissileResolution.Outcome.WEDGE_BLOCKED and is_equal_approx(rod["incoming"], 400.0 / 6.0), "each blocked rod keeps its incoming yield")

func _test_unprotected_record_reports_hull_loss() -> void:
	var w: Array = _world_with_missile(false, Vector3(0, 0, -100.0))
	var world: SimulationWorld = w[0]
	var hull: HullState = w[1]
	world.tick_simulation(1.0 / 60.0)
	_assert(world.last_tick_impacts.size() == 1, "unprotected strike should also be recorded")
	if world.last_tick_impacts.is_empty():
		return
	var rec: Dictionary = world.last_tick_impacts[0]
	_assert(rec["overall_outcome"] == MissileResolution.Outcome.HIT_UNPROTECTED, "no defence -> HIT_UNPROTECTED")
	_assert(is_equal_approx(rec["hull_before"] - rec["hull_after"], 400.0), "hull_before - hull_after should equal damage dealt")
	_assert(is_equal_approx(rec["hull_after"], hull.integrity) and rec["hull_max"] == hull.max_integrity, "hull_after/hull_max should match the live hull")

func _test_records_cleared_each_tick() -> void:
	var w: Array = _world_with_missile(true, Vector3(0, 100.0, 0))
	var world: SimulationWorld = w[0]
	world.tick_simulation(1.0 / 60.0)
	world.tick_simulation(1.0 / 60.0)
	_assert(world.last_tick_impacts.is_empty(), "last_tick_impacts is per-tick: empty once nothing detonates")

func _test_record_is_isolated_snapshot() -> void:
	var w: Array = _world_with_missile(false, Vector3(0, 0, -100.0))
	var world: SimulationWorld = w[0]
	var hull: HullState = w[1]
	world.tick_simulation(1.0 / 60.0)
	var integrity_before: float = hull.integrity
	var pos_before: Vector3 = world.ships["target"].position
	var rec: Dictionary = world.last_tick_impacts[0]
	rec["rods"].clear()
	rec["target_position"] = Vector3(9, 9, 9)
	rec["hull_after"] = 12345.0
	_assert(hull.integrity == integrity_before and world.ships["target"].position == pos_before, "mutating a record must not change simulation state")

func _test_records_deterministic() -> void:
	var a: Array = _world_with_missile(true, Vector3(0, 100.0, 0))
	var b: Array = _world_with_missile(true, Vector3(0, 100.0, 0))
	(a[0] as SimulationWorld).tick_simulation(1.0 / 60.0)
	(b[0] as SimulationWorld).tick_simulation(1.0 / 60.0)
	_assert(str((a[0] as SimulationWorld).last_tick_impacts) == str((b[0] as SimulationWorld).last_tick_impacts), "identical worlds must publish identical impact records")

func _test_wedge_hit_center_local() -> void:
	var half_len: float = 287.5
	var half_w: float = 99.0
	var ridge: float = 40.0
	var top: Vector3 = ImpactGeometry.wedge_hit_center_local(Vector3(0, 1000, 0), half_len, half_w, ridge)
	_assert(absf(top.x) < 0.01 and absf(top.z) < 0.01 and is_equal_approx(top.y, ridge), "strike from straight above hits the top ridge centre")
	var bottom: Vector3 = ImpactGeometry.wedge_hit_center_local(Vector3(0, -1000, 0), half_len, half_w, ridge)
	_assert(is_equal_approx(bottom.y, -ridge), "strike from below lands on the bottom wedge (negative y)")
	var bow: Vector3 = ImpactGeometry.wedge_hit_center_local(Vector3(0, 300, -5000), half_len, half_w, ridge)
	_assert(bow.z >= -half_len - 0.001 and bow.z <= 0.0 and bow.y > 0.0, "near-axial strike is clamped to the wedge footprint")
	var side: Vector3 = ImpactGeometry.wedge_hit_center_local(Vector3(5000, 300, 0), half_len, half_w, ridge)
	_assert(absf(side.x) <= half_w + 0.001 and side.y > 0.0 and side.y < ridge, "grazing broadside strike is clamped to the flank")
	var degenerate: Vector3 = ImpactGeometry.wedge_hit_center_local(Vector3.ZERO, half_len, half_w, ridge)
	_assert(is_finite(degenerate.x) and is_finite(degenerate.y) and is_finite(degenerate.z), "zero offset must not produce NaN")

func _test_ripple_energy_bounds() -> void:
	_assert(is_equal_approx(ImpactFxDirector.ripple_energy(0.0, 10000.0, 0.3, 14.0), 0.3), "no absorbed yield -> minimum visible energy")
	_assert(ImpactFxDirector.ripple_energy(400.0, 10000.0, 0.3, 14.0) > 0.8, "one default missile reads as a strong ripple")
	_assert(ImpactFxDirector.ripple_energy(1e9, 10000.0, 0.3, 14.0) == 1.0, "energy saturates at 1.0")
	_assert(ImpactFxDirector.ripple_energy(400.0, 0.0, 0.3, 14.0) <= 1.0, "hull_max of 0 must not divide by zero")


func _test_record_kind_and_geometry_fields() -> void:
	var w: Array = _world_with_missile(true, Vector3(0, 100.0, 0))
	var world: SimulationWorld = w[0]
	world.tick_simulation(1.0 / 60.0)
	var rec: Dictionary = world.last_tick_impacts[0]
	_assert(rec["kind"] == "missile", "missile detonation records are kind 'missile'")
	_assert(rec["target_orientation"] is Quaternion and rec["rods"][0]["position"] is Vector3, "records carry orientation and rod positions as plain values")

## Two ships, one beam mount, one tick of fire_weapon.
func _beam_world(target_has_defense: bool, attacker_pos: Vector3) -> Array:
	var world := SimulationWorld.new()
	world.accuracy_enabled = false
	var attacker := ShipPhysicsState.new()
	attacker.position = attacker_pos
	var target := _make_ship(target_has_defense)
	var hull := HullState.new()
	world.add_ship("attacker", attacker)
	world.add_ship("target", target, hull)
	var mount := WeaponMount.new()
	mount.weapon = WeaponData.new()
	mount.weapon.max_range_m = 1.0e9
	mount.weapon.damage_per_hit = 120.0
	mount.arc_sectors = [AttackGeometry.Sector.TOP, AttackGeometry.Sector.BOTTOM, AttackGeometry.Sector.BOW, AttackGeometry.Sector.STERN, AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD]
	world.add_weapon_mount("attacker", mount)
	return [world, mount, hull]

func _test_beam_record_routed_into_impacts() -> void:
	var b: Array = _beam_world(false, Vector3(0, 0, -50000.0))
	var world: SimulationWorld = b[0]
	var result = world.fire_weapon("attacker", b[1], "target")
	_assert(result != null and result.outcome == WeaponResolution.Outcome.HIT_UNPROTECTED, "an undefended target is hit by the beam")
	_assert(world.last_tick_impacts.size() == 1, "a beam strike is published in last_tick_impacts")
	if world.last_tick_impacts.is_empty():
		return
	var rec: Dictionary = world.last_tick_impacts[0]
	_assert(rec["kind"] == "beam" and rec["rods"].size() == 1, "beam record: kind 'beam' with exactly one rod")
	_assert(rec["rods"][0]["position"] == Vector3(0, 0, -50000.0), "the beam 'rod' sits at the attacker")
	_assert(is_equal_approx(rec["total_incoming"], 120.0) and rec["total_damage"] > 0.0, "beam record carries incoming yield and damage")
	_assert(world.last_tick_weapon_shots.size() == 1 and world.last_tick_weapon_shots[0]["impact_index"] == 0, "the weapon shot points at its impact record")
	_assert(rec["hull_before"] > rec["hull_after"], "beam record snapshots hull before/after")

func _test_beam_miss_has_no_record() -> void:
	_assert(ImpactRecord.beam_outcome_to_rod_outcome(WeaponResolution.Outcome.MISS) == -1, "a miss maps to no record")
	_assert(ImpactRecord.beam_outcome_to_rod_outcome(WeaponResolution.Outcome.OUT_OF_RANGE) == -1, "out of range maps to no record")
	_assert(ImpactRecord.beam_outcome_to_rod_outcome(WeaponResolution.Outcome.WEDGE_BLOCKED) == MissileResolution.Outcome.WEDGE_BLOCKED, "wedge-blocked beams map to the matching rod outcome")

func _test_sidewall_and_hull_strike_points() -> void:
	var dims: Dictionary = ImpactGeometry.dims_for(500.0, 90.0, 50.0)
	var port: Vector3 = ImpactGeometry.sidewall_hit_center_local(Vector3(-5000, 10, 100), AttackGeometry.Sector.PORT, dims)
	_assert(is_equal_approx(port.x, -49.5) and absf(port.z) <= 262.6, "a port strike lands on the port panel plane")
	var stbd: Vector3 = ImpactGeometry.sidewall_hit_center_local(Vector3(5000, 0, 0), AttackGeometry.Sector.STARBOARD, dims)
	_assert(is_equal_approx(stbd.x, 49.5) and is_equal_approx(stbd.z, 0.0), "a starboard strike lands on the starboard panel plane")
	var bow: Vector3 = ImpactGeometry.sidewall_hit_center_local(Vector3(0, 0, -5000), AttackGeometry.Sector.BOW, dims)
	_assert(is_equal_approx(bow.z, -250.0), "a bow strike lands on the bow panel plane")
	var hull: Vector3 = ImpactGeometry.hull_surface_point_local(Vector3(1, 0, 0), dims)
	_assert(is_equal_approx(hull.x, 45.0) and absf(hull.y) < 0.001, "hull surface point along +X is the half width")
	var on_surface: float = pow(hull.x / 45.0, 2.0) + pow(hull.y / 25.0, 2.0) + pow(hull.z / 250.0, 2.0)
	_assert(is_equal_approx(on_surface, 1.0), "hull surface points satisfy the ellipsoid equation")
	var n: Vector3 = ImpactGeometry.hull_normal_local(hull, dims)
	_assert(n.is_normalized() and n.x > 0.99, "hull normal at +X points outward")
	_assert(is_finite(ImpactGeometry.hull_surface_point_local(Vector3.ZERO, dims).x), "zero bearing must not produce NaN")

func _test_strike_point_dispatch() -> void:
	var dims: Dictionary = ImpactGeometry.dims_for(500.0, 90.0, 50.0)
	var rod_local := Vector3(2000, 300, -100)
	var wedge: Vector3 = ImpactGeometry.strike_point_local(MissileResolution.Outcome.WEDGE_BLOCKED, AttackGeometry.Sector.TOP, rod_local, dims)
	var side: Vector3 = ImpactGeometry.strike_point_local(MissileResolution.Outcome.SIDEWALL_ATTENUATED, AttackGeometry.Sector.STARBOARD, rod_local, dims)
	var hull: Vector3 = ImpactGeometry.strike_point_local(MissileResolution.Outcome.HIT_UNPROTECTED, AttackGeometry.Sector.STARBOARD, rod_local, dims)
	_assert(wedge.y > 0.0 and is_equal_approx(side.x, 49.5) and absf(hull.x) <= 45.001, "outcomes dispatch to wedge / sidewall / hull geometry")
	_assert(side.x > hull.x, "a sidewall strike point lies outside the hull surface point")

func _test_badge_model_merges_salvo() -> void:
	var m := ImpactBadgeModel.new()
	for i in range(20):
		m.add("dread", 1, 400.0, 0.0, MissileResolution.Outcome.WEDGE_BLOCKED, 10.0 + float(i) * 0.01)
	_assert(m.badges.size() == 1 and m.badges["dread"]["hits"] == 20, "20 near-simultaneous strikes merge into one badge (x20)")
	_assert(is_equal_approx(m.badges["dread"]["absorbed"], 8000.0), "absorbed yield sums across the salvo")
	m.add("dread", 1, 400.0, 400.0, MissileResolution.Outcome.HIT_UNPROTECTED, 12.0)
	_assert(m.badges["dread"]["hits"] == 1, "a strike after the merge window starts a fresh badge")
	m.add("escort", 1, 100.0, 0.0, MissileResolution.Outcome.SIDEWALL_ATTENUATED, 12.0)
	_assert(m.badges.size() == 2, "different ships get different badges")
	m.prune(12.0 + ImpactBadgeModel.LIFE_S + 0.1)
	_assert(m.badges.is_empty(), "badges expire")
	_assert(ImpactBadgeModel.dominant_outcome({"by_outcome": {1: 5.0, 3: 9.0}}) == 3, "dominant outcome is the one with the most yield")

func _test_badge_text() -> void:
	var lines: PackedStringArray = ImpactBadgeOverlay.badge_lines({"hits": 12, "damage": 0.0, "absorbed": 4800.0})
	_assert(lines[0] == "×12" and lines.size() == 2, "badge shows x N and absorbed yield")
	_assert(ImpactBadgeOverlay.badge_lines({"hits": 1, "damage": 40.0, "absorbed": 0.0})[0] == "УДАР", "a single strike is labelled УДАР, not x1")

func _test_camera_trauma() -> void:
	var w: Array = _world_with_missile(false, Vector3(0, 0, -100.0))
	var world: SimulationWorld = w[0]
	world.tick_simulation(1.0 / 60.0)
	var rec: Dictionary = world.last_tick_impacts[0]
	var plain: float = CameraFxController.trauma_for_record(rec, false, 3.0, 0.12, 0.2, 1.8, 1.0)
	var flag: float = CameraFxController.trauma_for_record(rec, true, 3.0, 0.12, 0.2, 1.8, 1.0)
	var far: float = CameraFxController.trauma_for_record(rec, false, 3.0, 0.12, 0.2, 1.8, 0.2)
	_assert(plain > 0.0 and flag > plain and far < plain, "trauma grows with yield, flagship status, and falls with distance")
	_assert(CameraFxController.trauma_for_record(rec, true, 1000.0, 1.0, 1.0, 3.0, 1.0) <= 1.0, "trauma is clamped to 1")
	_assert(CameraFxController.attenuation_for(0.0, 1000.0) == 1.0 and CameraFxController.attenuation_for(1.0e12, 1000.0) == 0.2, "attenuation spans 1.0 .. 0.2")

func _test_vent_intensity() -> void:
	_assert(ShipDamageFx.vent_intensity(0.0) == 0.0 and ShipDamageFx.vent_intensity(0.03) == 0.0, "an undamaged ship does not vent")
	_assert(ShipDamageFx.vent_intensity(0.1) > 0.0 and ShipDamageFx.vent_intensity(0.3) > ShipDamageFx.vent_intensity(0.1), "venting grows with hull fraction lost")
	_assert(ShipDamageFx.vent_intensity(0.9) == 1.0, "venting saturates")
