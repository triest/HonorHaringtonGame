extends SceneTree
## 2026-09-29 (user: "давай сценарии и контрракеты. И их запас"): headless
## tests for the counter-missile LAUNCH decision, finite stock, player
## policy (auto/flagship/salvo/hold) and the swept high-speed intercept.
## Run: godot --headless --script res://simulation/tests/test_counter_missile_launch.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const CounterMissileResolution = preload("res://simulation/counter_missile_resolution.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		printerr("FAIL: ", message)

func _ship(pos: Vector3) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.defense = ShipDefenseState.new()
	return s

## Two friendly ships (alpha = flagship/guide, alpha_2) at the origin with
## CM tubes, one hostile ship far away. `threats` hostile missiles are
## launched at `victim` from ~800,000 km out, closing at 50,000 km/s.
func _world(threats: int, victim: String, ammo: int = 6) -> SimulationWorld:
	var w := SimulationWorld.new()
	get_root().add_child(w)
	w.add_ship("alpha", _ship(Vector3.ZERO))
	w.set_team("alpha", "red")
	w.add_ship("alpha_2", _ship(Vector3(20_000.0, 0.0, 0.0)))
	w.set_team("alpha_2", "red")
	w.add_ship("beta", _ship(Vector3(0.0, 0.0, -3.0e9)))
	w.set_team("beta", "blue")
	w.add_formation("f", "alpha")
	for sid in ["alpha", "alpha_2"]:
		var t := MissileTube.new()
		t.ammo_count = ammo
		t.reload_time_s = 1.0
		t.max_range_m = 1.6e9
		w.add_cm_tube(sid, t)
	for i in range(threats):
		var m := MissileState.new()
		m.position = Vector3(float(i) * 100.0, 0.0, -8.0e8)
		m.velocity = Vector3(0.0, 0.0, 5.0e7)
		m.target = w.ships[victim]
		w.add_missile("in_%d" % i, m, "beta")
	return w

func _run(w: SimulationWorld, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		w.tick_simulation(0.1)
		t += 0.1

func _cm_launched(w: SimulationWorld) -> int:
	var n := 0
	for e in w.battle_events:
		if e["type"] == "cm_launched":
			n += 1
	return n

func _init() -> void:
	_test_launches_and_spends_stock()
	_test_hold_never_launches()
	_test_flagship_policy_filters_by_victim()
	_test_salvo_policy_needs_big_salvo()
	_test_empty_magazine_fires_nothing()
	_test_counter_missile_kills_inbound_in_world_loop()
	_test_swept_intercept_catches_tunnelling_pair()
	print("counter-missile launch tests: passed=%d failed=%d" % [_passed, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
	quit(_failures)

func _test_launches_and_spends_stock() -> void:
	var w := _world(1, "alpha")
	var before: int = w.cm_ammo_remaining("alpha") + w.cm_ammo_remaining("alpha_2")
	_run(w, 3.0)
	var after: int = w.cm_ammo_remaining("alpha") + w.cm_ammo_remaining("alpha_2")
	_assert(before == 12, "starting stock is the sum of tube ammo")
	_assert(before - after == 1, "one inbound missile costs exactly one counter-missile (before=%d after=%d)" % [before, after])
	_assert(_cm_launched(w) == 1, "a cm_launched battle event is emitted once")
	_assert(w.cm_start_ammo["alpha"] == 6, "cm_start_ammo remembers the initial magazine for the n/N readout")

func _test_hold_never_launches() -> void:
	var w := _world(3, "alpha")
	w.set_ship_cm_policy("alpha", "hold")
	w.set_ship_cm_policy("alpha_2", "hold")
	_run(w, 3.0)
	_assert(_cm_launched(w) == 0, "hold policy: no counter-missile is ever launched")

func _test_flagship_policy_filters_by_victim() -> void:
	var w := _world(2, "alpha_2")  # aimed at the NON-guide
	w.set_ship_cm_policy("alpha", "flagship")
	w.set_ship_cm_policy("alpha_2", "flagship")
	_run(w, 3.0)
	_assert(_cm_launched(w) == 0, "flagship policy: threats aimed at a non-guide are left to point defence")
	var w2 := _world(2, "alpha")  # aimed at the guide
	w2.set_ship_cm_policy("alpha", "flagship")
	w2.set_ship_cm_policy("alpha_2", "flagship")
	_run(w2, 3.0)
	_assert(_cm_launched(w2) >= 1, "flagship policy: threats aimed at the guide are engaged")

func _test_salvo_policy_needs_big_salvo() -> void:
	var w := _world(3, "alpha")
	w.set_ship_cm_policy("alpha", "salvo")
	w.set_ship_cm_policy("alpha_2", "salvo")
	_run(w, 3.0)
	_assert(_cm_launched(w) == 0, "salvo policy: 3 inbound is below the threshold, stock is kept")
	var w2 := _world(SimulationWorld.CM_SALVO_MIN_INBOUND + 2, "alpha")
	w2.set_ship_cm_policy("alpha", "salvo")
	w2.set_ship_cm_policy("alpha_2", "salvo")
	_run(w2, 3.0)
	_assert(_cm_launched(w2) >= 1, "salvo policy: a big salvo triggers launches")

func _test_empty_magazine_fires_nothing() -> void:
	var w := _world(4, "alpha", 0)
	_run(w, 3.0)
	_assert(_cm_launched(w) == 0, "an empty counter-missile magazine launches nothing")

func _test_counter_missile_kills_inbound_in_world_loop() -> void:
	var w := _world(1, "alpha")
	var inbound = w.missiles["in_0"]
	_run(w, 40.0)
	_assert(not inbound.is_active(), "the inbound missile is no longer active after the engagement")
	_assert(inbound.is_intercepted(), "...and it was INTERCEPTED (killed by a counter-missile), not just expired")
	var had_intercept_event := false
	for e in w.battle_events:
		if e["type"] == "cm_intercept":
			had_intercept_event = true
	_assert(had_intercept_event, "a cm_intercept battle event is emitted")

func _test_swept_intercept_catches_tunnelling_pair() -> void:
	# 90,000 km/s closing, one 0.1 s tick = 9,000 km: the pair ends the tick
	# far apart on OPPOSITE sides of each other, but passes within 1 km.
	var inc := MissileState.new()
	var cm := MissileState.new()
	cm.target = inc
	var cm_prev := Vector3(0.0, 0.0, 0.0)
	var inc_prev := Vector3(0.0, 1000.0, -4.5e6)  # 1 km lateral, 4,500 km ahead
	cm.position = Vector3(0.0, 0.0, -4.5e6)
	inc.position = Vector3(0.0, 1000.0, 0.0)  # swapped ends: passed each other mid-tick
	var end_only := CounterMissileResolution.check_intercept(cm, inc)
	_assert(end_only.outcome == CounterMissileResolution.Outcome.TOO_FAR, "the old end-of-tick test misses a tunnelling pair (documents why swept exists)")
	var swept := CounterMissileResolution.check_intercept_swept(cm, inc, cm_prev, inc_prev)
	_assert(swept.outcome == CounterMissileResolution.Outcome.INTERCEPTED, "the swept test catches the pair that passed within the kill radius")
