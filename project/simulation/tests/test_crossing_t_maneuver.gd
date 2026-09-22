extends SceneTree
## Behavioral test for "Crossing the T" maneuver (§41.1).
## Verifies that a ship attempts to maneuver to a broadside aspect rather than
## simply charging straight at the target.

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")

func _init() -> void:
	var failures := 0
	failures += _test_crossing_t_maneuver_produces_perpendicular_thrust()

	if failures == 0:
		print("CROSSING-T BEHAVIOR TEST PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_crossing_t_maneuver_produces_perpendicular_thrust() -> int:
	var world := SimulationWorld.new()

	# Setup: Ship A at origin, Ship B 10km ahead on Z axis
	var ship_a := ShipPhysicsState.new()
	ship_a.position = Vector3.ZERO
	ship_a.orientation = Quaternion.IDENTITY # Facing -Z (Forward)
	world.add_ship("A", ship_a)
	world.set_team("A", "Alpha")

	var ship_b := ShipPhysicsState.new()
	ship_b.position = Vector3(0, 0, -10000)
	ship_b.orientation = Quaternion.IDENTITY # Facing +Z (towards A)
	world.add_ship("B", ship_b)
	world.set_team("B", "Beta")

	# Mock sensor contact for A to see B
	var contact_b := SensorContact.new(ship_b)
	contact_b.state = ContactState.Type.TRACKED
	contact_b.estimated_position = ship_b.position
	world.sensor_contacts["A"] = {"B": contact_b}

	# Tick simulation for a few frames to let AI react
	var dt := 1.0 / 60.0
	for i in range(10):
		world.tick_simulation(dt)

	# ANALYSIS:
	# Line of Sight (LOS) is along Z axis.
	# Target Forward is along +Z.
	# Crossing the T maneuver should produce a velocity/thrust vector
	# perpendicular to BOTH (i.e., along X or Y axis).

	var thrust := ship_a.commanded_thrust_local
	var los := (ship_b.position - ship_a.position).normalized()

	# The thrust should NOT be purely along the LOS (no simple charging)
	var dot_with_los: float = absf(thrust.normalized().dot(los))
	var is_perpendicular: bool = dot_with_los < 0.5 # Significant deviation from straight line

	if not is_perpendicular:
		printerr("FAIL: Ship A is charging straight at target or not moving. Thrust: %s, LOS: %s" % [thrust, los])
		return 1

	print("SUCCESS: Ship A is maneuvering to the flank. Thrust: %s" % thrust)
	return 0
