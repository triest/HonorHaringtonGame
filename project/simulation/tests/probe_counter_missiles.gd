extends SceneTree
## Diagnostic: full default battle with and without counter-missiles,
## averaged over several RNG seeds (a single shared-seed A/B is NOT valid
## once behavior diverges -- see ASSUMPTIONS.md methodology note).
## Env: CM_SECONDS (default 700), CM_SEEDS ("1904,1905,1906"), CM_MULT
## (stock multiplier for the "with CM" arm, default 1.0), CM_SETUP=mixed.
## Run: godot4 --headless --path . --script res://simulation/tests/probe_counter_missiles.gd
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")

func _run(mult: float, seed_value: int, secs: float, scenario: String) -> Dictionary:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	var setup: Dictionary = {"scenario": scenario} if scenario != "" else {}
	DemoScenario.set_cm_stock_mult(mult)
	var ids: Dictionary = DemoScenario.build(world, setup)
	var shift: float = float(OS.get_environment("CM_SHIFT")) if OS.get_environment("CM_SHIFT") != "" else 3.1e8
	if scenario == "" or scenario == "intercept":
		for sid0 in world.ships.keys():
			if world.teams[sid0] == "blue":
				world.ships[sid0].position.z += shift  # start right at missile range (see probe_demo_scenario)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	SubsystemDamageResolution.spread_rng = rng
	var dt := 0.1
	var counts: Dictionary = {}
	var last_seq: int = 0
	for i in range(int(secs / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		for e in world.battle_events:
			if e["seq"] <= last_seq:
				continue
			last_seq = e["seq"]
			var side: String = ""
			var d: Dictionary = e["data"]
			var who: String = String(d.get("ship_id", d.get("attacker_ship_id", "")))
			side = String(world.teams.get(who, "?"))
			var key: String = "%s:%s" % [e["type"], side]
			counts[key] = counts.get(key, 0) + 1
	var red_alive: int = 0
	var blue_alive: int = 0
	var cm_left_red: int = 0
	var cm_left_blue: int = 0
	for sid in world.ships.keys():
		if not world.ships[sid].is_wreck:
			if world.teams[sid] == "red":
				red_alive += 1
			else:
				blue_alive += 1
		if world.teams[sid] == "red":
			cm_left_red += world.cm_ammo_remaining(sid)
		else:
			cm_left_blue += world.cm_ammo_remaining(sid)
	counts["red_alive"] = red_alive
	counts["blue_alive"] = blue_alive
	counts["cm_left_red"] = cm_left_red
	counts["cm_left_blue"] = cm_left_blue
	world.queue_free()
	return counts

func _init() -> void:
	var secs: float = float(OS.get_environment("CM_SECONDS")) if OS.get_environment("CM_SECONDS") != "" else 700.0
	var seeds_txt: String = OS.get_environment("CM_SEEDS") if OS.get_environment("CM_SEEDS") != "" else "1904,1905,1906"
	var mult: float = float(OS.get_environment("CM_MULT")) if OS.get_environment("CM_MULT") != "" else 1.0
	var scenario: String = OS.get_environment("CM_SCENARIO")
	var arms_txt: String = OS.get_environment("CM_ARMS") if OS.get_environment("CM_ARMS") != "" else "0,1"
	for arm_txt in arms_txt.split(","):
		var arm: float = float(arm_txt) * mult if float(arm_txt) > 0.0 else 0.0
		print("=== stock multiplier %.2f ===" % arm)
		for sd in seeds_txt.split(","):
			var c: Dictionary = _run(arm, int(sd), secs, scenario)
			var keys: Array = c.keys()
			keys.sort()
			var parts: Array = []
			for k in keys:
				parts.append("%s=%d" % [k, c[k]])
			print("seed %s: %s" % [sd, " ".join(parts)])
	quit(0)
