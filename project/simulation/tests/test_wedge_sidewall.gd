extends SceneTree
const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
## Headless smoke tests for Milestone 3 (wedge, sidewalls, attack direction).
## Run: godot4 --headless --script res://simulation/tests/test_wedge_sidewall.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_classify_top_bottom()
	failures += _test_classify_bow_stern()
	failures += _test_classify_port_starboard()
	failures += _test_wedge_blocks_top_bottom()
	failures += _test_wedge_down_leaves_top_bottom_unprotected()
	failures += _test_broadside_sidewall_attenuates()
	failures += _test_bow_unprotected_when_not_raised()
	failures += _test_bow_sidewall_blocks_thrust()
	failures += _test_laserhead_penetrates_sidewall_more_than_energy()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_classify_top_bottom() -> int:
	var target_pos := Vector3.ZERO
	var ori := Quaternion.IDENTITY
	var from_above := Vector3(0, 1000, 0)
	var from_below := Vector3(0, -1000, 0)
	var ok: bool = AttackGeometry.classify(from_above, target_pos, ori) == AttackGeometry.Sector.TOP
	ok = ok and AttackGeometry.classify(from_below, target_pos, ori) == AttackGeometry.Sector.BOTTOM
	if not ok:
		printerr("FAIL classify_top_bottom")
		return 1
	return 0

func _test_classify_bow_stern() -> int:
	var target_pos := Vector3.ZERO
	var ori := Quaternion.IDENTITY
	# Local -Z is bow. Attacker ahead of the ship (world -Z, identity orientation).
	var ahead := Vector3(0, 0, -1000)
	var behind := Vector3(0, 0, 1000)
	var ok: bool = AttackGeometry.classify(ahead, target_pos, ori) == AttackGeometry.Sector.BOW
	ok = ok and AttackGeometry.classify(behind, target_pos, ori) == AttackGeometry.Sector.STERN
	if not ok:
		printerr("FAIL classify_bow_stern")
		return 1
	return 0

func _test_classify_port_starboard() -> int:
	var target_pos := Vector3.ZERO
	var ori := Quaternion.IDENTITY
	var to_starboard := Vector3(1000, 0, 0)
	var to_port := Vector3(-1000, 0, 0)
	var ok: bool = AttackGeometry.classify(to_starboard, target_pos, ori) == AttackGeometry.Sector.STARBOARD
	ok = ok and AttackGeometry.classify(to_port, target_pos, ori) == AttackGeometry.Sector.PORT
	if not ok:
		printerr("FAIL classify_port_starboard")
		return 1
	return 0

func _test_wedge_blocks_top_bottom() -> int:
	var defense := ShipDefenseState.new()
	defense.wedge_up = true
	var res := defense.resolve_attack(Vector3(0, 1000, 0), Vector3.ZERO, Quaternion.IDENTITY)
	var ok: bool = res.kind == ShipDefenseState.ResolutionKind.WEDGE_BLOCKED and res.transmitted_fraction == 0.0
	if not ok:
		printerr("FAIL wedge_blocks_top_bottom: kind=%s frac=%s" % [res.kind, res.transmitted_fraction])
		return 1
	return 0

func _test_wedge_down_leaves_top_bottom_unprotected() -> int:
	var defense := ShipDefenseState.new()
	defense.wedge_up = false
	var res := defense.resolve_attack(Vector3(0, 1000, 0), Vector3.ZERO, Quaternion.IDENTITY)
	var ok: bool = res.kind == ShipDefenseState.ResolutionKind.UNPROTECTED and res.transmitted_fraction == 1.0
	if not ok:
		printerr("FAIL wedge_down_leaves_top_bottom_unprotected")
		return 1
	return 0

func _test_broadside_sidewall_attenuates() -> int:
	var defense := ShipDefenseState.new()
	defense.starboard_sidewall_condition = 1.0
	var res_full := defense.resolve_attack(Vector3(1000, 0, 0), Vector3.ZERO, Quaternion.IDENTITY)
	defense.starboard_sidewall_condition = 0.0
	var res_burned := defense.resolve_attack(Vector3(1000, 0, 0), Vector3.ZERO, Quaternion.IDENTITY)
	var ok: bool = res_full.kind == ShipDefenseState.ResolutionKind.SIDEWALL_ATTENUATED and res_full.transmitted_fraction < res_burned.transmitted_fraction
	ok = ok and res_burned.kind == ShipDefenseState.ResolutionKind.UNPROTECTED
	if not ok:
		printerr("FAIL broadside_sidewall_attenuates: full=%s burned=%s" % [res_full.transmitted_fraction, res_burned.transmitted_fraction])
		return 1
	return 0

func _test_bow_unprotected_when_not_raised() -> int:
	var defense := ShipDefenseState.new()
	defense.bow_sidewall_raised = false
	var res := defense.resolve_attack(Vector3(0, 0, -1000), Vector3.ZERO, Quaternion.IDENTITY)
	var ok: bool = res.kind == ShipDefenseState.ResolutionKind.UNPROTECTED
	if not ok:
		printerr("FAIL bow_unprotected_when_not_raised")
		return 1
	return 0

func _test_bow_sidewall_blocks_thrust() -> int:
	var s := ShipPhysicsState.new()
	s.commanded_thrust_local = Vector3(0, 0, -1)
	s.defense = ShipDefenseState.new()
	s.defense.bow_sidewall_raised = true
	var dt: float = 1.0 / 60.0
	for i in range(60):
		s.integrate(dt)
	var ok: bool = s.velocity.length() < 0.001 and s.position.length() < 0.001
	if not ok:
		printerr("FAIL bow_sidewall_blocks_thrust: vel=%s pos=%s" % [s.velocity, s.position])
		return 1
	return 0

func _test_laserhead_penetrates_sidewall_more_than_energy() -> int:
	var defense_energy := ShipDefenseState.new()
	defense_energy.starboard_sidewall_condition = 0.7
	var res_energy := defense_energy.resolve_attack(Vector3(1000, 0, 0), Vector3.ZERO, Quaternion.IDENTITY, ShipDefenseState.DamageType.Type.ENERGY)

	var defense_laser := ShipDefenseState.new()
	defense_laser.starboard_sidewall_condition = 0.7
	var res_laser := defense_laser.resolve_attack(Vector3(1000, 0, 0), Vector3.ZERO, Quaternion.IDENTITY, ShipDefenseState.DamageType.Type.LASERHEAD)

	var ok: bool = res_laser.transmitted_fraction > res_energy.transmitted_fraction
	if not ok:
		printerr("FAIL laserhead_penetrates_sidewall_more_than_energy: energy=%s laser=%s" % [res_energy.transmitted_fraction, res_laser.transmitted_fraction])
		return 1
	return 0
