extends SceneTree
## Headless test runner for ТЗ §45 Replay (Milestone 12 first slice):
## ReplayLog command/event recording, JSON round-trip serialization, the
## new automatic ship-destruction resolution (§25/§37 "ship lost"), and
## the actual PROOF this is all worth having -- that a fresh
## SimulationWorld built from the same initial setup and fed the
## recorded commands via SimulationWorld.apply_recorded_command()
## reproduces the original run's outcome, since this simulation has no
## unseeded randomness anywhere (ТЗ §43).
## Run via: godot --headless --path . --script res://simulation/tests/test_replay_log.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ReplayLog = preload("res://simulation/replay_log.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")
const FormationOrder = preload("res://simulation/formation_order.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(pos: Vector3) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.defense = ShipDefenseState.new()
	return s

func _make_hull(integrity: float = 1000.0, max_integrity: float = 1000.0) -> HullState:
	var h := HullState.new()
	h.max_integrity = max_integrity
	h.integrity = integrity
	return h

func _make_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.id = "test_laser"
	w.max_range_m = 5_000_000.0
	w.damage_per_hit = 100.0
	w.recharge_time_s = 4.0
	return w

func _make_tube() -> MissileTube:
	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0
	tube.max_range_m = 5_000_000.0
	return tube

# ---------------------------------------------------------------------
# Command recording
# ---------------------------------------------------------------------

func _test_recording_off_by_default_records_nothing() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.set_ship_weapons_free("alpha", false)
	world.tick_simulation(1.0 / 60.0)
	_assert(world.replay_log == null, "a SimulationWorld that never called start_recording() should never allocate a ReplayLog (zero overhead, identical to every pre-existing test)")

func _test_start_recording_captures_a_direct_command() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.start_recording(42)
	world.tick_simulation(1.0 / 60.0)
	world.set_ship_target("alpha", "beta")

	_assert(world.replay_log != null, "start_recording() should allocate a ReplayLog")
	_assert(world.replay_log.random_seed == 42, "the seed passed to start_recording should be stored on the log")
	_assert(world.replay_log.commands.size() == 1, "set_ship_target should have recorded exactly one command")
	var entry: Dictionary = world.replay_log.commands[0]
	_assert(entry["name"] == "set_ship_target", "the recorded command name should match the API called")
	_assert(entry["args"]["ship_id"] == "alpha" and entry["args"]["target_ship_id"] == "beta", "the recorded command args should match what was passed")
	_assert(entry["tick"] == 1, "the command issued after exactly one tick_simulation call should be timestamped at tick 1")

	var finished := world.stop_recording()
	_assert(finished == world.replay_log or world.replay_log == null, "stop_recording should clear replay_log")
	_assert(world.replay_log == null, "after stop_recording, recording should be off again")

func _test_transmit_and_formation_and_missile_launch_commands_are_recorded() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	world.add_formation("wall", "alpha")
	world.start_recording()

	world.transmit_ship_weapons_free("alpha", false)
	world.issue_individual_order_now("alpha", IndividualOrder.hold())
	world.issue_formation_order_now("wall", FormationOrder.hold_formation())
	world.order_missile_launch("alpha", "beta")  # no valid target -- still an issued command, 0 missiles launched

	var names: Array = []
	for entry in world.replay_log.commands:
		names.append(entry["name"])
	_assert(names.has("transmit_ship_weapons_free"), "transmit_ship_weapons_free should be recorded")
	_assert(names.has("issue_individual_order_now"), "issue_individual_order_now should be recorded")
	_assert(names.has("issue_formation_order_now"), "issue_formation_order_now should be recorded")
	_assert(names.has("order_missile_launch"), "order_missile_launch should be recorded even when it launches nothing")

# ---------------------------------------------------------------------
# Event recording + the new ship-destruction mechanic
# ---------------------------------------------------------------------

func _test_weapon_hit_event_is_recorded() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	var beta_hull := _make_hull()
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta, beta_hull)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))
	world.start_recording()

	world.tick_simulation(1.0 / 60.0)

	_assert(beta_hull.integrity < 1000.0, "sanity check: the shot should have actually landed")
	var hit_events: Array = []
	for entry in world.replay_log.events:
		if entry["type"] == "weapon_hit":
			hit_events.append(entry)
	_assert(hit_events.size() == 1, "exactly one weapon_hit event should be recorded for the one shot that landed")
	if hit_events.size() == 1:
		_assert(hit_events[0]["data"]["attacker_ship_id"] == "alpha" and hit_events[0]["data"]["target_ship_id"] == "beta", "the weapon_hit event should name attacker and target correctly")
		_assert(hit_events[0]["data"]["damage_dealt"] > 0.0, "the weapon_hit event should carry the damage actually dealt")

func _test_missile_launched_event_is_recorded() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta, _make_hull())
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.add_missile_tube("alpha", _make_tube())
	world.tick_simulation(1.0 / 60.0)  # populate sensor contacts before issuing the order
	world.start_recording()

	var launched: int = world.order_missile_launch("alpha", "beta")

	_assert(launched == 1, "sanity check: the order should have actually launched one missile")
	var launch_events: Array = []
	for entry in world.replay_log.events:
		if entry["type"] == "missile_launched":
			launch_events.append(entry)
	_assert(launch_events.size() == 1, "exactly one missile_launched event should be recorded")
	if launch_events.size() == 1:
		_assert(launch_events[0]["data"]["attacker_ship_id"] == "alpha", "the missile_launched event should name the launching ship")
		_assert(world.missiles.has(launch_events[0]["data"]["missile_id"]), "the missile_id in the event should refer to a real missile in the world")

func _test_ship_destruction_becomes_a_wreck_and_records_event() -> void:
	# ТЗ §63.1: a destroyed ship must NOT disappear -- it becomes an inert
	# wreck, still present in the world, still obeying inertia.
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	alpha.velocity = Vector3(0, 0, 100.0)  # coasting -- should be UNCHANGED by destruction
	alpha.commanded_thrust_local = Vector3.FORWARD  # should be ZEROED by destruction (no crew left to hold it)
	var alpha_hull := _make_hull(0.0)  # already at zero integrity
	world.add_ship("alpha", alpha, alpha_hull)
	world.start_recording()

	_assert(world.ships.has("alpha"), "sanity check: the ship should exist before the first tick")
	world.tick_simulation(1.0 / 60.0)

	_assert(world.ships.has("alpha"), "§63.1: a destroyed ship must NOT be removed from the world -- it becomes a wreck")
	_assert(world.hulls.has("alpha"), "the destroyed ship's hull entry should be kept (its is_destroyed()==true is what keeps it a wreck)")
	_assert(alpha.is_wreck, "the destroyed ship should be flagged as a wreck")
	_assert(alpha.commanded_thrust_local == Vector3.ZERO, "a wreck should have its thrust zeroed -- no crew left to hold a heading")
	_assert(alpha.velocity.is_equal_approx(Vector3(0, 0, 100.0)), "§63.1: a wreck must keep obeying inertia -- its pre-destruction velocity must be left completely untouched")
	var destroy_events: Array = []
	for entry in world.replay_log.events:
		if entry["type"] == "ship_destroyed":
			destroy_events.append(entry)
	_assert(destroy_events.size() == 1, "exactly one ship_destroyed event should be recorded, even though the ship is not removed")
	if destroy_events.size() == 1:
		_assert(destroy_events[0]["data"]["ship_id"] == "alpha", "the ship_destroyed event should name the destroyed ship")

	# The event/wreck-flip should happen exactly once, not every tick.
	for i in range(5):
		world.tick_simulation(1.0 / 60.0)
	var destroy_events_after: Array = []
	for entry in world.replay_log.events:
		if entry["type"] == "ship_destroyed":
			destroy_events_after.append(entry)
	_assert(destroy_events_after.size() == 1, "a wreck must not be re-processed as newly destroyed on later ticks")

func _test_wreck_is_excluded_from_combat_and_command() -> void:
	# §63.1: "no longer a ship for any combat/command/AI purpose".
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))  # would normally be alpha's nearest hostile target
	var alpha_hull := _make_hull(0.0)  # alpha starts already destroyed
	var beta_hull := _make_hull()
	world.add_ship("alpha", alpha, alpha_hull)
	world.add_ship("beta", beta, beta_hull)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))
	world.add_weapon_mount("beta", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))
	world.issue_individual_order_now("alpha", IndividualOrder.change_speed(alpha, 500.0))

	world.tick_simulation(1.0 / 60.0)

	_assert(alpha.is_wreck, "sanity check: alpha should have become a wreck on this tick")
	_assert(beta_hull.integrity == 1000.0, "beta should never fire at alpha's wreck -- a wreck must never be selectable as anyone's hostile target")
	_assert(alpha.commanded_thrust_local == Vector3.ZERO, "a wreck must never receive individual-order thrust, even with an active order still queued for it")

func _test_ship_destruction_removes_member_from_formation() -> void:
	var world := SimulationWorld.new()
	var guide := _make_ship(Vector3.ZERO)
	var member := _make_ship(Vector3(100, 0, 0))
	var member_hull := _make_hull(0.0)
	world.add_ship("guide", guide)
	world.add_ship("member", member, member_hull)
	var formation := world.add_formation("wall", "guide")
	formation.set_station("member", Vector3(100, 0, 0))

	world.tick_simulation(1.0 / 60.0)

	_assert(not formation.member_ids().has("member"), "a destroyed formation member should be dropped from the formation's own member list, not left as a dangling station")

func _test_a_ship_with_no_hull_state_is_never_auto_destroyed() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)  # no HullState at all
	for i in range(5):
		world.tick_simulation(1.0 / 60.0)
	_assert(world.ships.has("alpha"), "a ship with no HullState should never be auto-destroyed (identical to pre-Milestone-12 behavior)")

# ---------------------------------------------------------------------
# Serialization round-trips
# ---------------------------------------------------------------------

func _test_replay_log_to_dict_from_dict_round_trip() -> void:
	var log := ReplayLog.new()
	log.random_seed = 7
	log.record_command(3, 0.05, "set_ship_target", {"ship_id": "a", "target_ship_id": "b"})
	log.record_command(5, 0.083, "transmit_individual_order_now", {"ship_id": "a", "order": IndividualOrder.hold().to_dict()})
	log.record_event(4, 0.066, "weapon_hit", {"attacker_ship_id": "a", "target_ship_id": "b", "damage_dealt": 100.0})

	var restored := ReplayLog.from_dict(log.to_dict())
	_assert(restored.random_seed == 7, "random_seed should survive a to_dict/from_dict round-trip")
	_assert(restored.commands.size() == 2, "both recorded commands should survive the round-trip")
	_assert(restored.events.size() == 1, "the recorded event should survive the round-trip")
	_assert(restored.commands[0]["name"] == "set_ship_target", "command order/content should be preserved")
	_assert(restored.commands[1]["args"]["order"]["kind"] == IndividualOrder.Kind.HOLD, "a serialized order's kind should survive the round-trip")
	_assert(restored.events[0]["data"]["damage_dealt"] == 100.0, "event data should survive the round-trip")

func _test_replay_log_save_and_load_file_round_trip() -> void:
	var log := ReplayLog.new()
	log.random_seed = 99
	log.record_command(1, 0.0166, "order_missile_launch", {"ship_id": "a", "target_ship_id": "b"})
	log.record_event(1, 0.0166, "missile_launched", {"attacker_ship_id": "a", "missile_id": "ai_missile_1"})

	var path := "user://test_replay_log_roundtrip.json"
	var saved: bool = log.save_to_file(path)
	_assert(saved, "save_to_file should succeed writing to the user:// data directory")

	var loaded := ReplayLog.load_from_file(path)
	_assert(loaded != null, "load_from_file should successfully read back a file just saved")
	if loaded != null:
		_assert(loaded.random_seed == 99, "random_seed should survive a save/load file round-trip")
		_assert(loaded.commands.size() == 1 and loaded.commands[0]["name"] == "order_missile_launch", "commands should survive a save/load file round-trip")
		_assert(loaded.events.size() == 1 and loaded.events[0]["type"] == "missile_launched", "events should survive a save/load file round-trip")

	_assert(ReplayLog.load_from_file("user://this_file_does_not_exist.json") == null, "load_from_file should return null (not crash) for a missing file")

func _test_individual_order_to_dict_from_dict_round_trip() -> void:
	var order := IndividualOrder.change_orientation(Vector3(0, 1, 0))
	var restored := IndividualOrder.from_dict(order.to_dict())
	_assert(restored.kind == IndividualOrder.Kind.CHANGE_ORIENTATION, "kind should survive round-trip")
	_assert(restored.target_facing_world.is_equal_approx(Vector3(0, 1, 0)), "target_facing_world should survive round-trip")

func _test_formation_order_to_dict_from_dict_round_trip() -> void:
	var order := FormationOrder.change_formation({"wing1": Vector3(10, 0, -10), "wing2": Vector3(-10, 0, -10)})
	var restored := FormationOrder.from_dict(order.to_dict())
	_assert(restored.kind == FormationOrder.Kind.CHANGE_FORMATION, "kind should survive round-trip")
	_assert(restored.new_offsets_local["wing1"].is_equal_approx(Vector3(10, 0, -10)), "new_offsets_local entries should survive round-trip")
	_assert(restored.new_offsets_local["wing2"].is_equal_approx(Vector3(-10, 0, -10)), "new_offsets_local entries should survive round-trip")

func _test_approach_formation_order_to_dict_from_dict_round_trip() -> void:
	var order := FormationOrder.approach(Vector3(3000, 0, -500), 175.0)
	var restored := FormationOrder.from_dict(order.to_dict())
	_assert(restored.kind == FormationOrder.Kind.APPROACH, "kind should survive round-trip")
	_assert(restored.target_point_world.is_equal_approx(Vector3(3000, 0, -500)), "target_point_world should survive round-trip")
	_assert(is_equal_approx(restored.approach_speed_mps, 175.0), "approach_speed_mps should survive round-trip")
	_assert(is_equal_approx(restored.arrival_tolerance_m, order.arrival_tolerance_m), "arrival_tolerance_m should survive round-trip")

# ---------------------------------------------------------------------
# The actual point of Replay: reproduce a run from its recorded commands
# ---------------------------------------------------------------------

func _build_duel(alpha_pos: Vector3, beta_pos: Vector3) -> Dictionary:
	var world := SimulationWorld.new()
	var alpha := _make_ship(alpha_pos)
	var beta := _make_ship(beta_pos)
	var alpha_hull := _make_hull(2000.0, 2000.0)
	var beta_hull := _make_hull(2000.0, 2000.0)
	world.add_ship("alpha", alpha, alpha_hull)
	world.add_ship("beta", beta, beta_hull)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.add_weapon_mount("alpha", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))
	world.add_weapon_mount("beta", WeaponMount.new(_make_weapon(), WeaponMount.bow_chaser_arc()))
	world.add_missile_tube("alpha", _make_tube())
	return {"world": world, "alpha": alpha, "beta": beta, "alpha_hull": alpha_hull, "beta_hull": beta_hull}

func _test_replay_reproduces_the_original_run() -> void:
	const DT: float = 1.0 / 60.0
	const TOTAL_TICKS: int = 40

	var a := _build_duel(Vector3.ZERO, Vector3(0, 0, -500_000.0))
	var world_a: SimulationWorld = a["world"]
	world_a.start_recording(123)

	for i in range(TOTAL_TICKS):
		world_a.tick_simulation(DT)
		var t: int = i + 1
		if t == 5:
			world_a.order_missile_launch("alpha", "beta")
		elif t == 10:
			world_a.set_ship_weapons_free("alpha", false)
		elif t == 20:
			world_a.set_ship_weapons_free("alpha", true)

	var log: ReplayLog = world_a.stop_recording()
	_assert(log.commands.size() == 3, "the three commands issued during the run should all be recorded")
	_assert(log.events.size() > 0, "at least one combat event (weapon_hit and/or missile_launched) should have been recorded during the run")

	# Round-trip the log through JSON before replaying, so this test also
	# proves the SAVED/LOADED form (not just the in-memory objects) is
	# enough to reproduce the run.
	var path := "user://test_replay_determinism.json"
	_assert(log.save_to_file(path), "saving the recorded run's log should succeed")
	var loaded_log: ReplayLog = ReplayLog.load_from_file(path)
	_assert(loaded_log != null, "loading the saved run's log should succeed")

	var commands_by_tick: Dictionary = {}
	for entry in loaded_log.commands:
		var t: int = entry["tick"]
		if not commands_by_tick.has(t):
			commands_by_tick[t] = []
		commands_by_tick[t].append(entry)

	var b := _build_duel(Vector3.ZERO, Vector3(0, 0, -500_000.0))
	var world_b: SimulationWorld = b["world"]

	for i in range(TOTAL_TICKS):
		world_b.tick_simulation(DT)
		var t: int = i + 1
		if commands_by_tick.has(t):
			for entry in commands_by_tick[t]:
				world_b.apply_recorded_command(entry)

	var alpha_a: ShipPhysicsState = a["alpha"]
	var alpha_b: ShipPhysicsState = b["alpha"]
	var beta_a_ship: ShipPhysicsState = a["beta"]
	var beta_b_ship: ShipPhysicsState = b["beta"]

	_assert(alpha_a.position.is_equal_approx(alpha_b.position), "replayed run should reproduce the original attacker's final position exactly")
	_assert(alpha_a.velocity.is_equal_approx(alpha_b.velocity), "replayed run should reproduce the original attacker's final velocity exactly")
	_assert(beta_a_ship.position.is_equal_approx(beta_b_ship.position), "replayed run should reproduce the original target's final position exactly")

	var beta_hull_a: HullState = a["beta_hull"]
	var beta_hull_b: HullState = b["beta_hull"]
	_assert(is_equal_approx(beta_hull_a.integrity, beta_hull_b.integrity) or beta_hull_a.integrity == beta_hull_b.integrity, "replayed run should reproduce the original target's final hull integrity exactly (damage dealt must match, including the toggled hold-fire window)")
	_assert(beta_hull_a.integrity < 2000.0, "sanity check: the original run should have actually dealt damage")

	_assert(world_a.missiles.size() == world_b.missiles.size(), "replayed run should end with the same number of missiles still in flight as the original")
	_assert(world_a.ships.size() == world_b.ships.size(), "replayed run should end with the same ships alive as the original")

func _init() -> void:
	_test_recording_off_by_default_records_nothing()
	_test_start_recording_captures_a_direct_command()
	_test_transmit_and_formation_and_missile_launch_commands_are_recorded()
	_test_weapon_hit_event_is_recorded()
	_test_missile_launched_event_is_recorded()
	_test_ship_destruction_becomes_a_wreck_and_records_event()
	_test_wreck_is_excluded_from_combat_and_command()
	_test_ship_destruction_removes_member_from_formation()
	_test_a_ship_with_no_hull_state_is_never_auto_destroyed()
	_test_replay_log_to_dict_from_dict_round_trip()
	_test_replay_log_save_and_load_file_round_trip()
	_test_individual_order_to_dict_from_dict_round_trip()
	_test_formation_order_to_dict_from_dict_round_trip()
	_test_approach_formation_order_to_dict_from_dict_round_trip()
	_test_replay_reproduces_the_original_run()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
