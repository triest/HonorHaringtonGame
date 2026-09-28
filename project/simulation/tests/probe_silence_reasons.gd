extends SceneTree
## Diagnostic: classifies, for every alive ship at intervals through a full
## battle, WHY it isn't firing this tick (if it isn't) -- answers "why do
## ships sometimes stop shooting" empirically instead of just by code
## review. Run: godot4 --headless --path . --script res://simulation/tests/probe_silence_reasons.gd
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const TacticalAI = preload("res://simulation/tactical_ai.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

func _classify(world: SimulationWorld, sid: String) -> String:
	var ship = world.ships[sid]
	if ship.is_wreck:
		return "wreck"
	var mounts: Array = world.weapon_mounts.get(sid, [])
	var tubes: Array = world.missile_tubes.get(sid, [])
	if TacticalAI.is_critically_damaged(world.hulls.get(sid), world.CRITICAL_HULL_FRACTION):
		return "DISENGAGING (hull<=%.0f%%)" % (world.CRITICAL_HULL_FRACTION * 100.0)
	var directive = world.ship_combat_directives.get(sid)
	if directive != null and not directive.weapons_free:
		return "hold_fire_order"
	if String(world.ship_effective_attitude.get(sid, "")) == "wedge":
		return "wedge_attitude"
	var hostile_ids: Array = world._hostile_ship_ids(sid)
	if hostile_ids.is_empty():
		return "no_hostiles_left"
	var contacts: Dictionary = world.sensor_contacts.get(sid, {})
	var sel: Dictionary = world._resolve_weapon_target(sid, ship, contacts, hostile_ids)
	if sel.get("ship_id") == null:
		return "no_sensor_track_on_any_hostile"
	var subs = ship.subsystems
	var ammo: int = 0
	for t in tubes:
		ammo += t.ammo_count
	var weapons_disabled: bool = subs != null and subs.is_disabled(SubsystemType.Type.WEAPONS)
	if mounts.is_empty() and ammo == 0:
		return "no_weapons_fitted_or_all_ammo_spent"
	if weapons_disabled and ammo == 0:
		return "WEAPONS module knocked out AND out of missiles"
	return "should_be_firing"

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	var ids: Dictionary = DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	var dt := (1.0 / 60.0) * 6.0
	var reason_counts: Dictionary = {}
	var per_ship_last_reason: Dictionary = {}
	var transitions: Array = []
	for i in range(int(1400.0 / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		if i % 30 != 0:
			continue
		for sid in world.ships.keys():
			var r: String = _classify(world, sid)
			reason_counts[r] = reason_counts.get(r, 0) + 1
			if per_ship_last_reason.get(sid, "") != r:
				transitions.append("t=%.0f %s -> %s" % [world.world_sim_time, sid, r])
				per_ship_last_reason[sid] = r
	print("=== reason sample-counts across the whole battle ===")
	for k in reason_counts.keys():
		print("  %s: %d" % [k, reason_counts[k]])
	print("=== first 40 state transitions per ship ===")
	for line in transitions.slice(0, 40):
		print(line)
	quit(0)
