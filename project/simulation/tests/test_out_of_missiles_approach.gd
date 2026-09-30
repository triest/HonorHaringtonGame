extends SceneTree
## TODO.md "Сближение при пустых ракетных трубах": a team whose tubes are all
## empty (and with no missiles in flight) closes on the enemy; a team with ammo
## keeps the crossing-the-T behaviour; energy-only teams are unaffected.

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")

func _init() -> void:
	var failures := 0
	failures += _case(0, true, "empty tubes -> closes")
	failures += _case(5, false, "ammo left -> no auto-approach")
	failures += _case(-1, false, "no tubes at all -> unaffected")
	if failures == 0:
		print("OUT-OF-MISSILES APPROACH TEST PASSED")
	quit(failures)

func _case(ammo: int, expect_close: bool, label: String) -> int:
	var world := SimulationWorld.new()
	var a := ShipPhysicsState.new()
	a.position = Vector3.ZERO
	world.add_ship("A", a)
	world.set_team("A", "Alpha")
	var b := ShipPhysicsState.new()
	b.position = Vector3(0, 0, -5_000_000)
	world.add_ship("B", b)
	world.set_team("B", "Beta")
	if ammo >= 0:
		var tube := MissileTube.new()
		tube.ammo_count = ammo
		world.add_missile_tube("A", tube)
	var c := SensorContact.new(b)
	c.state = ContactState.Type.TRACKED
	c.estimated_position = b.position
	world.sensor_contacts["A"] = {"B": c}
	for i in range(10):
		world.tick_simulation(1.0 / 60.0)
	var los := (b.position - a.position).normalized()
	var along: bool = a.commanded_thrust_local.length() > 0.0 and (a.orientation * a.commanded_thrust_local).normalized().dot(los) > 0.8
	if along != expect_close:
		printerr("FAIL: %s (thrust=%s)" % [label, a.commanded_thrust_local])
		return 1
	print("ok: ", label)
	return 0
