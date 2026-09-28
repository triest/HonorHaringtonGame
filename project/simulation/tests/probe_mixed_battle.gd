extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	var setup := {
		"red": [{"class_id": "destroyer", "count": 3}],
		"blue": [{"class_id": "battlecruiser", "count": 2}],
	}
	var ids: Dictionary = DemoScenario.build(world, setup)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var dt := (1.0 / 60.0) * 6.0
	for i in range(int(900.0 / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
	var line := "t=%.0f " % world.world_sim_time
	for sid in ids["red_ids"] + ids["blue_ids"]:
		var s = world.subsystems_condition_for_probe(sid) if world.has_method("subsystems_condition_for_probe") else -1.0
		var wrecked = world.ships[sid].is_wreck
		line += "%s:%s " % [sid, "WRECK" if wrecked else "alive"]
	print(line)
	print("outnumbered destroyers (3 light) vs battlecruisers (2 heavy) -- outcome above, no crash, no stall")
	quit(0)
