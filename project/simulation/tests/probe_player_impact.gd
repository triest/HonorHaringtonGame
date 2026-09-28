extends SceneTree
## Empirical check: does a player who actively concentrates fire on the
## weakest enemy ship (a classic naval tactic -- kill one ship fast to
## reduce incoming fire sooner) noticeably outperform hands-off play
## where every ship just picks its own nearest target (today's AI
## default)? Same seed both runs (SubsystemDamageResolution.spread_rng is
## reseeded identically) so any difference is the TACTIC, not luck.
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const SubsystemDamageResolution = preload("res://simulation/subsystem_damage_resolution.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

func _run(focus_fire: bool, duration_s: float) -> Dictionary:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	var ids: Dictionary = DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var dt := (1.0 / 60.0) * 6.0
	var steps: int = int(duration_s / dt)
	var retarget_every: int = int(5.0 / dt)  # an attentive admiral re-checks "who's weakest" every 5 sim-seconds
	for i in range(steps):
		if focus_fire and i % retarget_every == 0:
			# Find the weakest (lowest structural condition) currently-detected enemy, order the whole red squadron onto it.
			var pov := "alpha"
			if not world.ships.has(pov) or world.ships[pov].is_wreck:
				for sid in ids["red_ids"]:
					if world.ships.has(sid) and not world.ships[sid].is_wreck:
						pov = sid
						break
			var contacts: Dictionary = world.sensor_contacts.get(pov, {})
			var weakest_id := ""
			var weakest_cond := INF
			for bid in ids["blue_ids"]:
				if not world.ships.has(bid) or world.ships[bid].is_wreck:
					continue
				var c = contacts.get(bid)
				if c == null or c.state == 0:
					continue
				var cond: float = world.ships[bid].subsystems.get_condition(SubsystemType.Type.STRUCTURAL_INTEGRITY)
				if cond < weakest_cond:
					weakest_cond = cond
					weakest_id = bid
			if weakest_id != "":
				for sid in ids["red_ids"]:
					if world.ships.has(sid) and not world.ships[sid].is_wreck:
						world.transmit_ship_target(sid, weakest_id)
						world.transmit_ship_weapons_free(sid, true)
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
	var red_alive := 0
	var blue_alive := 0
	var blue_dead_at: Array = []
	for sid in ids["red_ids"]:
		if world.ships.has(sid) and not world.ships[sid].is_wreck:
			red_alive += 1
	for sid in ids["blue_ids"]:
		if world.ships.has(sid) and not world.ships[sid].is_wreck:
			blue_alive += 1
	var red_ammo := 0
	for sid in ids["red_ids"]:
		for t in world.missile_tubes.get(sid, []):
			red_ammo += t.ammo_count
	return {"red_alive": red_alive, "blue_alive": blue_alive, "red_ammo_left": red_ammo, "t": world.world_sim_time}

func _init() -> void:
	# 2026-09-28: a SINGLE shared-seed A/B run is NOT a valid comparison --
	# the instant the two conditions' behavior diverges (almost
	# immediately -- different launch timing/order alone shifts which RNG
	# draw lands on which hit), SubsystemDamageResolution.spread_rng's
	# draw SEQUENCE desyncs between the two runs, so "who wins" past that
	# point is dominated by which random draws each run happened to
	# consume, not by the tactic. Averaging several INDEPENDENT seeds per
	# condition is the only way to actually isolate the tactic's effect
	# from luck.
	var seeds: Array = [1904, 1905, 1906]
	var duration: float = 500.0
	var ho_red_alive := 0.0
	var ho_blue_alive := 0.0
	var ff_red_alive := 0.0
	var ff_blue_alive := 0.0
	for seed in seeds:
		var rng1 := RandomNumberGenerator.new()
		rng1.seed = seed
		SubsystemDamageResolution.spread_rng = rng1
		var ho := _run(false, duration)
		ho_red_alive += ho["red_alive"]
		ho_blue_alive += ho["blue_alive"]
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = seed
		SubsystemDamageResolution.spread_rng = rng2
		var ff := _run(true, duration)
		ff_red_alive += ff["red_alive"]
		ff_blue_alive += ff["blue_alive"]
		print("seed=%d  hands-off red=%d blue=%d  |  focus-fire red=%d blue=%d" % [seed, ho["red_alive"], ho["blue_alive"], ff["red_alive"], ff["blue_alive"]])
	var n: float = float(seeds.size())
	print("AVERAGE over %d seeds -- hands-off: red_alive=%.2f blue_alive=%.2f" % [seeds.size(), ho_red_alive / n, ho_blue_alive / n])
	print("AVERAGE over %d seeds -- focus-fire: red_alive=%.2f blue_alive=%.2f" % [seeds.size(), ff_red_alive / n, ff_blue_alive / n])
	quit(0)
