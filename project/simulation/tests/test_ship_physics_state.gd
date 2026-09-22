extends SceneTree
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
## Minimal headless self-test, runnable without a full Godot editor project
## via: godot4 --headless --script res://simulation/tests/test_ship_physics_state.gd
##
## This is a smoke test for Milestone 1 physics (ТЗ §52 Testing:
## "vector math; physics; inertial movement; high acceleration").
## It is deliberately dependency-free (no test framework) so it can run in
## any environment that has the Godot 4 binary, including CI without
## internet access.

func _init() -> void:
	var failures := 0
	failures += _test_thrust_produces_velocity_and_position_change()
	failures += _test_zero_thrust_preserves_velocity_inertially()
	failures += _test_velocity_never_exceeds_c()
	failures += _test_relative_velocity_and_closure()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_thrust_produces_velocity_and_position_change() -> int:
	var s := ShipPhysicsState.new()
	s.commanded_thrust_local = Vector3(0, 0, -1)
	s.max_thrust_n = 1.0e11 # Approx 100 m/s^2 for 1e9 kg
	var dt := 1.0 / 60.0
	for i in range(60):  # 1 simulated second
		s.integrate(dt)
	var ok: bool = s.velocity.z < 0.0 and s.position.z < 0.0
	if not ok:
		printerr("FAIL thrust_produces_velocity_and_position_change: vel=%s pos=%s" % [s.velocity, s.position])
		return 1
	return 0

func _test_zero_thrust_preserves_velocity_inertially() -> int:
	var s := ShipPhysicsState.new()
	s.velocity = Vector3(100, 0, 0)
	var dt := 1.0 / 60.0
	for i in range(600):  # 10 simulated seconds, no thrust commanded
		s.integrate(dt)
	var ok: bool = abs(s.velocity.x - 100.0) < 0.001
	if not ok:
		printerr("FAIL zero_thrust_preserves_velocity_inertially: vel=%s" % s.velocity)
		return 1
	return 0

func _test_velocity_never_exceeds_c() -> int:
	var s := ShipPhysicsState.new()
	s.commanded_thrust_local = Vector3(0, 0, -1)
	s.max_thrust_n = 1.0e14 # Unrealistically high, to stress the clamp
	var dt := 1.0 / 60.0
	for i in range(60 * 60 * 5):  # 5 simulated hours
		s.integrate(dt)
	var ok: bool = s.velocity.length() < ShipPhysicsState.SPEED_OF_LIGHT_MPS
	if not ok:
		printerr("FAIL velocity_never_exceeds_c: speed=%s" % s.velocity.length())
		return 1
	return 0

func _test_relative_velocity_and_closure() -> int:
	var a := ShipPhysicsState.new()
	a.position = Vector3(-1000, 0, 0)
	a.velocity = Vector3(50, 0, 0)
	var b := ShipPhysicsState.new()
	b.position = Vector3(1000, 0, 0)
	b.velocity = Vector3(-50, 0, 0)
	var rel: Vector3 = a.relative_velocity(b)
	var expected: Vector3 = b.velocity - a.velocity
	var ok: bool = rel.is_equal_approx(expected)
	var closure: float = a.closure_velocity_towards(b)
	ok = ok and closure > 0.0  # ships closing on each other
	if not ok:
		printerr("FAIL relative_velocity_and_closure: rel=%s closure=%s" % [rel, closure])
		return 1
	return 0
