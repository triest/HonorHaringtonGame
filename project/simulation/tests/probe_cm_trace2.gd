extends SceneTree
## Diagnostic: tick-by-tick approach of the first red and first blue counter-missile.
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
	var follow: Dictionary = {}
	var log_lines: Dictionary = {"red": [], "blue": []}
	for i in range(int(200.0 / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		for cid in world.counter_missile_ids.keys():
			var team: String = String(world.teams.get(world.missile_owners.get(cid, ""), "?"))
			if not follow.has(team):
				follow[team] = cid
		for team in follow.keys():
			var cid: String = follow[team]
			var cm = world.missiles.get(cid)
			if cm == null:
				continue
			var tgt = cm.target
			var rel: Vector3 = tgt.position - cm.position
			var relv: Vector3 = tgt.velocity - cm.velocity
			log_lines[team].append("t=%.1f d=%dkm closing=%dkm/s sens=%d cm_burn=%.1f tgt_burn=%.1f lat_vel=%dkm/s cmv=(%d,%d,%d) tv=(%d,%d,%d)" % [world.world_sim_time, int(rel.length() / 1000.0), int(-rel.dot(relv) / maxf(rel.length(), 1.0) / 1000.0), cm.sensor_state, cm.drive_burn_remaining_s, tgt.drive_burn_remaining_s, int((relv - rel.normalized() * relv.dot(rel.normalized())).length() / 1000.0), int(cm.velocity.x / 1000.0), int(cm.velocity.y / 1000.0), int(cm.velocity.z / 1000.0), int(tgt.velocity.x / 1000.0), int(tgt.velocity.y / 1000.0), int(tgt.velocity.z / 1000.0)])
	for team in ["red", "blue"]:
		print("==== %s (first CM %s) first 14 samples (every 5th) ====" % [team, follow.get(team, "-")])
		var arr: Array = log_lines[team]
		var mi := 0
		var md := INF
		for k in range(arr.size()):
			var parts = String(arr[k]).split(" ")
			var dv := float(String(parts[1]).replace("d=", "").replace("km", ""))
			if dv < md:
				md = dv
				mi = k
		for l in arr.slice(maxi(0, mi - 6), mini(arr.size(), mi + 3)):
			print(l)
		for k in range(0, mini(arr.size(), 400), 40):
			print("EARLY ", arr[k])
	quit(0)
