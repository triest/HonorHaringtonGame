extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const TacticalAI = preload("res://simulation/tactical_ai.gd")

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	var ids: Dictionary = DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var dt := (1.0 / 60.0) * 6.0
	var seen: Dictionary = {}
	for i in range(int(1400.0 / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		for sid in world.ships.keys():
			var ship = world.ships[sid]
			if ship.is_wreck or seen.has(sid):
				continue
			if TacticalAI.is_critically_damaged(world.hulls.get(sid), world.CRITICAL_HULL_FRACTION):
				var ammo: int = 0
				for t in world.missile_tubes.get(sid, []):
					ammo += t.ammo_count
				var hull_frac: float = world.hulls[sid].integrity / world.hulls[sid].max_integrity
				print("%s went DISENGAGING at t=%.0f with hull=%.2f, remaining missile ammo=%d, mounts=%d" % [sid, world.world_sim_time, hull_frac, ammo, world.weapon_mounts.get(sid, []).size()])
				seen[sid] = true
	quit(0)
