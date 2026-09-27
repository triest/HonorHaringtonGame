extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var dt := 1.0/60.0
	for i in range(int(100.0/dt)):
		world.tick_simulation(dt)
	print("missiles ", world.missiles.size())
	var fns = ["_resolve_pending_command_transmissions","_sync_subsystem_driven_conditions","_cleanup_inactive_missiles","_resolve_ship_destruction"]
	var fdt = ["_update_sensors","_update_missiles","_resolve_point_defense","_resolve_formation_orders","_resolve_formation_keeping","_resolve_individual_orders","_resolve_damage_response","_resolve_formation_target_assignment","_resolve_missile_tot_coordination","_resolve_weapons_ai","_resolve_missile_launch_ai","_resolve_crossing_t_maneuver","_integrate_ships"]
	for f in fns:
		var t0 = Time.get_ticks_usec()
		for k in range(30): world.call(f)
		print(f, " ", (Time.get_ticks_usec()-t0)/30, " us")
	for f in fdt:
		var t0 = Time.get_ticks_usec()
		for k in range(30): world.call(f, dt)
		print(f, " ", (Time.get_ticks_usec()-t0)/30, " us")
	var t1 = Time.get_ticks_usec()
	for k in range(30): world.tick_simulation(dt)
	print("TOTAL tick ", (Time.get_ticks_usec()-t1)/30, " us")
	quit(0)
