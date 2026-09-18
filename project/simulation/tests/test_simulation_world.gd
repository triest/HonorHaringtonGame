extends SceneTree
## Headless test runner for SimulationWorld's first end-to-end tick loop
## (Milestone 1 completion / ТЗ §42): sensors + missile guidance/flight/
## detonation + counter-missiles + point defense + ship physics all
## driven together deterministically, tick by tick.
## Run via: godot --headless --script res://simulation/tests/test_simulation_world.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const ContactState = preload("res://simulation/contact_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(pos: Vector3) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.defense = ShipDefenseState.new()
	return s

func _test_ships_integrate_through_the_world() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	ship.commanded_thrust_local = Vector3.FORWARD
	ship.max_acceleration_mps2 = 100.0
	world.add_ship("alpha", ship)

	for i in range(10):
		world.tick_simulation(1.0 / 60.0)

	_assert(ship.velocity.length() > 0.0, "a ship with commanded thrust should gain velocity through world.tick_simulation")

func _test_missile_flies_and_gets_a_sensor_contact() -> void:
	var world := SimulationWorld.new()
	var attacker := _make_ship(Vector3(0, 0, -50_000.0))
	var target := _make_ship(Vector3.ZERO)
	world.add_ship("attacker", attacker)
	world.add_ship("target", target)

	var missile := MissileState.new()
	missile.position = attacker.position
	missile.velocity = Vector3(0, 0, 1000.0)
	missile.target = target
	missile.terminal_detonation_range_m = 5000.0
	world.add_missile("m1", missile, "attacker")

	for i in range(30):
		world.tick_simulation(1.0 / 60.0)

	_assert(missile.position.z > attacker.position.z, "missile should have moved toward the target over 30 ticks")
	var contacts: Dictionary = world.sensor_contacts.get("target", {})
	_assert(contacts.has("m1"), "target ship should have opened a sensor contact on the missile via the world loop")

func _test_missile_detonates_on_target_and_damages_hull() -> void:
	var world := SimulationWorld.new()
	var target := _make_ship(Vector3.ZERO)
	var hull := HullState.new()
	world.add_ship("target", target, hull)

	var missile := MissileState.new()
	missile.position = Vector3(0, 0, -100.0)  # already essentially on top of the target
	missile.velocity = Vector3(0, 0, 50.0)
	missile.target = target
	missile.terminal_detonation_range_m = 5000.0  # arm threshold = 10% of this = 500m, already inside
	world.add_missile("m1", missile, "")

	var starting_integrity: float = hull.integrity
	for i in range(5):
		world.tick_simulation(1.0 / 60.0)

	_assert(hull.integrity < starting_integrity, "missile should have detonated and damaged the undefended target's hull within a few ticks")
	_assert(not world.missiles.has("m1"), "detonated missile should be cleaned up from world.missiles by the following tick")

func _test_point_defense_engages_and_can_intercept() -> void:
	var world := SimulationWorld.new()
	var target := _make_ship(Vector3.ZERO)
	world.add_ship("target", target)

	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0
	mount.recharge_time_s = 0.0
	mount.hits_required_to_kill = 1
	mount.max_engagement_range_m = 100_000.0
	world.add_pd_mount("target", mount)

	var missile := MissileState.new()
	missile.position = Vector3(0, 0, -5000.0)
	missile.velocity = Vector3.ZERO  # stationary -- isolates the PD-intercept assertion from flight/guidance
	missile.drive_max_acceleration_mps2 = 0.0  # no thrust force -- stays put, but drive_burn_remaining_s stays > 0 so it still emits a detectable signature (§23) and PD's sensor gate does not block it
	missile.terminal_detonation_range_m = 100.0  # keep well below the 5000m starting distance so it never self-arms/detonates during this test
	missile.target = target
	world.add_missile("incoming", missile, "")

	for i in range(10):
		world.tick_simulation(1.0 / 60.0)
		if missile.is_intercepted():
			break

	_assert(missile.is_intercepted(), "point defense should be able to detect (nearest-missile placeholder selection) and intercept an incoming missile through the world loop")

func _test_remove_ship_and_missile() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", ship)
	var missile := MissileState.new()
	world.add_missile("m1", missile, "alpha")

	world.remove_ship("alpha")
	world.remove_missile("m1")

	_assert(world.get_ship("alpha") == null, "remove_ship should remove the ship")
	_assert(not world.missiles.has("m1"), "remove_missile should remove the missile")

func _init() -> void:
	_test_ships_integrate_through_the_world()
	_test_missile_flies_and_gets_a_sensor_contact()
	_test_missile_detonates_on_target_and_damages_hull()
	_test_point_defense_engages_and_can_intercept()
	_test_remove_ship_and_missile()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
