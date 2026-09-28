extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const ShipStatus = preload("res://scripts/ship_status.gd")
const BattleLogPanel = preload("res://scripts/battle_log_panel.gd")

var passed := 0
var failures := 0
func _check(c: bool, m: String) -> void:
	if c: passed += 1
	else:
		failures += 1
		print("FAIL: ", m)

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
	var last_seq := 0
	var dt := (1.0 / 60.0) * 6.0
	var saw_event := false
	var disengaged_id := ""
	for i in range(int(700.0 / dt)):
		for sid2 in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid2]:
				m.tick(dt)
		world.tick_simulation(dt)
		for e in world.battle_events:
			if e["seq"] <= last_seq:
				continue
			last_seq = e["seq"]
			log._ingest(e)
			if e["type"] == "ship_disengaging" and not saw_event:
				saw_event = true
				disengaged_id = e["data"]["ship_id"]
				# Check the log line right when it's fresh (still in the
				# 60-line rolling window) -- not at the end of a long
				# battle, where it would long since have scrolled off.
				var found_now := false
				for l in log._lines:
					if String(l["bb"]).find(ShipNames.of(disengaged_id)) >= 0 and String(l["bb"]).find("ыходит из боя") >= 0:
						found_now = true
				_check(found_now, "battle log should contain a 'выходит из боя' line right when the event fires")
	_check(saw_event, "at least one ship_disengaging battle_event should fire in a full battle")
	if saw_event:
		var vd: Dictionary = ShipStatus.verdict(world, disengaged_id) if world.teams[disengaged_id] == "red" else ShipStatus.verdict_observed(world, disengaged_id)
		_check(vd["text"].find("ыход") >= 0 or vd["text"].find("СТУПА") >= 0, "verdict for the disengaged ship should say so, got '%s'" % vd["text"])
		_check(log._voice_seen.has("disengage_" + disengaged_id), "a disengage voice line should have fired for %s" % disengaged_id)
	print("Passed: ", passed, " Failed: ", failures)
	print("ALL TESTS PASSED" if failures == 0 else "SOME TESTS FAILED")
	quit(1 if failures > 0 else 0)
