extends SceneTree
## Headless probe of DemoScenario: runs the canon-shaped engagement for a
## while and prints a timeline. Not an assert test -- a diagnostic run.
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	DemoScenario.build(world)
	var shift: float = float(OS.get_environment("PROBE_SHIFT_KM")) * 1000.0 if OS.get_environment("PROBE_SHIFT_KM") != "" else 0.0
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += shift
	var dt: float = (1.0 / 60.0) * (float(OS.get_environment("PROBE_M")) if OS.get_environment("PROBE_M") != "" else 1.0)
	var launched: Dictionary = {}
	var first_launch_t: float = -1.0
	var intercepted := 0
	var detonated := 0
	var seen_state: Dictionary = {}
	var final_counts: Dictionary = {}
	var total_s: float = float(OS.get_environment("PROBE_S")) if OS.get_environment("PROBE_S") != "" else 900.0
	var steps: int = int(total_s / dt)
	for i in range(steps):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
		var t: float = (i + 1) * dt
		for mid in world.missiles.keys():
			var ms = world.missiles[mid]
			if not launched.has(mid):
				launched[mid] = true
				if first_launch_t < 0.0:
					first_launch_t = t
					print("t=%.1f first missile launch, separation %.0f km" % [t, world.ships["alpha"].position.distance_to(world.ships["beta"].position) / 1000.0])
			var st: int = ms.guidance_state
			if seen_state.get(mid, -1) != st:
				seen_state[mid] = st
				var owner_team: String = world.teams.get(world.missile_owners.get(mid, ""), "?")
				var key: String = "%s:%s" % [owner_team, MissileState.GuidanceState.keys()[st]]
				final_counts[key] = final_counts.get(key, 0) + 1
				if st == MissileState.GuidanceState.INTERCEPTED:
					intercepted += 1
				elif st == MissileState.GuidanceState.DETONATED:
					detonated += 1
		if i % int(15.0 / dt) == 0 or i == steps - 1:
			var line := "t=%4.0f sep=%9.0f km msl_total=%d active=%d intercepted=%d detonated=%d |" % [t, world.ships["alpha"].position.distance_to(world.ships["beta"].position) / 1000.0, launched.size(), _active(world), intercepted, detonated]
			for sid in ["alpha","alpha_2","alpha_3","alpha_4","beta","beta_2","beta_3","beta_4"]:
				if world.ships.has(sid):
					var sub = world.ships[sid].subsystems
					var dead: int = 0
					for tv in range(11):
						if sub.is_disabled(tv):
							dead += 1
					line += " %s:S%d/off%d%s" % [sid, int(100 * sub.get_condition(9)), dead, "W" if world.ships[sid].is_wreck else ""]
			print(line)
	print("missile state transitions by owner team: ", final_counts)
	print("guide orientation ", world.ships["alpha"].orientation, " beta ", world.ships["beta"].orientation)
	# formation keeping check
	var g = world.ships["alpha"]
	for sid in ["alpha_2","alpha_3","alpha_4"]:
		print("%s offset from guide: %s km" % [sid, (world.ships[sid].position - g.position) / 1000.0])
	quit(0)

func _active(world) -> int:
	var n := 0
	for mid in world.missiles.keys():
		if world.missiles[mid].is_active():
			n += 1
	return n
