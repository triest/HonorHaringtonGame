extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const BattleLogPanel = preload("res://scripts/battle_log_panel.gd")

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var log := BattleLogPanel.new()
	log.world = world
	log.player_team = "red"
	# NOT added to the tree -- avoids needing a real viewport for layout;
	# we only care about _ingest()'s pure text-building logic here.
	var last_seq := 0
	var dt := (1.0 / 60.0) * 6.0
	for i in range(int(1400.0 / dt)):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
		for e in world.battle_events:
			if e["seq"] > last_seq:
				last_seq = e["seq"]
				log._ingest(e)
	var voices := 0
	for l in log._lines:
		if String(l["key"]).begins_with("voice:"):
			voices += 1
			print(l["bb"])
	print("voice lines currently kept: ", voices, " total lines: ", log._lines.size(), " distinct voice triggers fired: ", log._voice_seen.size(), " keys: ", log._voice_seen.keys())
	quit(0)
