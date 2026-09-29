extends SceneTree
## Diagnostic: per-counter-missile trace (min distance to its target, fate).
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	DemoScenario.set_cm_stock_mult(1.0)
	var scen: String = OS.get_environment("CM_SCENARIO")
	DemoScenario.build(world, {"scenario": scen} if scen != "" else {})
	if scen == "" or scen == "intercept":
		for sid0 in world.ships.keys():
			if world.teams[sid0] == "blue":
				world.ships[sid0].position.z += 3.1e8
	var dt := 0.1
	var info: Dictionary = {}  # cm_id -> {min, owner_team, t0, fate, launch_dist}
	var printed := 0
	for i in range(int(float(OS.get_environment("CM_SECONDS") if OS.get_environment("CM_SECONDS") != "" else "420") / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		for cid in world.counter_missile_ids.keys():
			var cm = world.missiles.get(cid)
			if cm == null:
				continue
			if not info.has(cid):
				var own = String(world.teams.get(world.missile_owners.get(cid, ""), "?"))
				info[cid] = {"min": INF, "team": own, "t0": world.world_sim_time, "d0": cm.position.distance_to(cm.target.position), "spd_t": cm.target.velocity.length(), "spd_c": cm.velocity.length()}
			var d: float = cm.position.distance_to(cm.target.position)
			info[cid]["min"] = minf(info[cid]["min"], d)
			if info[cid].has("pc"):
				var rs: Vector3 = info[cid]["pt"] - info[cid]["pc"]
				var re: Vector3 = cm.target.position - cm.position
				var sg: Vector3 = re - rs
				var tt: float = clampf(-rs.dot(sg) / maxf(sg.length_squared(), 1e-9), 0.0, 1.0)
				info[cid]["swept"] = minf(info[cid].get("swept", INF), (rs + sg * tt).length())
			info[cid]["pc"] = cm.position
			info[cid]["pt"] = cm.target.position
			info[cid]["last_state"] = cm.guidance_state
			info[cid]["life"] = cm.lifetime_s
	var n := {"red": 0, "blue": 0}
	for cid in info.keys():
		var r: Dictionary = info[cid]
		if n[r["team"]] < 8:
			n[r["team"]] += 1
			print("%s %s t0=%.0f d0=%dkm vt=%dkm/s vc=%dkm/s min=%dkm swept=%.1fkm life=%.1f state=%s" % [cid, r["team"], r["t0"], int(r["d0"] / 1000.0), int(r["spd_t"] / 1000.0), int(r["spd_c"] / 1000.0), int(r["min"] / 1000.0), r.get("swept", INF) / 1000.0, r.get("life", 0), r.get("last_state", -1)])
	quit(0)
