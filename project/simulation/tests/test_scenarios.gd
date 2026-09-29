extends SceneTree
## 2026-09-29: every scenario in Scenarios.ORDER builds into a real world
## with the geometry/stock/doctrine its data table promises, and survives a
## short simulation. Run: godot --headless --script res://simulation/tests/test_scenarios.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		printerr("FAIL: ", message)

func _centroid(world: SimulationWorld, ids: Array) -> Vector3:
	var c := Vector3.ZERO
	for id in ids:
		c += world.ships[id].position
	return c / float(ids.size())

func _init() -> void:
	_assert(Scenarios.ORDER.size() >= 5, "there are at least five scenarios")
	for id in Scenarios.ORDER:
		_check_scenario(id)
	_test_default_build_is_intercept()
	_test_cm_stock_multiplier_and_policy()
	print("scenario tests: passed=%d failed=%d" % [_passed, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
	quit(_failures)

func _check_scenario(id: String) -> void:
	var w := SimulationWorld.new()
	get_root().add_child(w)
	var ids: Dictionary = DemoScenario.build(w, {"scenario": id})
	var d: Dictionary = Scenarios.get_data(id)
	var want_red: int = ShipClasses.side_total(d["setup"]["red"])
	var want_blue: int = ShipClasses.side_total(d["setup"]["blue"])
	_assert(ids["red_ids"].size() == want_red and ids["blue_ids"].size() == want_blue, "%s: default force sizes %d v %d" % [id, want_red, want_blue])
	var sep: float = _centroid(w, ids["red_ids"]).distance_to(_centroid(w, ids["blue_ids"]))
	_assert(absf(sep - float(d["sep_m"])) < 1.0e6, "%s: squadron centres start %.0f km apart (got %.0f)" % [id, float(d["sep_m"]) / 1000.0, sep / 1000.0])
	for sid in ids["red_ids"] + ids["blue_ids"]:
		_assert(w.cm_tubes.has(sid) and not w.cm_tubes[sid].is_empty(), "%s: %s carries counter-missiles" % [id, sid])
	# blue heads generally toward red's start point (closing), except pursuit-style
	# scenarios where it is simply aimed at red too -- always true by construction.
	var bf: ShipPhysicsState = w.ships[ids["blue_ids"][0]]
	var to_red: Vector3 = (w.ships[ids["red_ids"][0]].position - bf.position).normalized()
	var flat_vel: Vector3 = Vector3(bf.velocity.x, 0.0, bf.velocity.z).normalized()
	_assert(flat_vel.dot(to_red) > 0.3, "%s: blue starts heading roughly toward red (dot=%.2f)" % [id, flat_vel.dot(to_red)])
	var rf: ShipPhysicsState = w.ships[ids["red_ids"][0]]
	_assert(absf(rf.velocity.length() - float(d["red_speed"])) < 1.0, "%s: red starts at its scenario speed" % id)
	var bf_brief: String = DemoScenario.mission_briefing({"scenario": id, "red": d["setup"]["red"], "blue": d["setup"]["blue"]}, ids["red_ids"], ids["blue_ids"])
	_assert(bf_brief.length() > 400 and bf_brief.find(String(d["place"])) >= 0, "%s: briefing text is scenario-specific" % id)
	for _i in range(60):
		w.tick_simulation(0.1)
	_assert(w.world_sim_time > 5.9, "%s: survives 6 simulated seconds" % id)
	w.queue_free()

func _test_default_build_is_intercept() -> void:
	var w := SimulationWorld.new()
	get_root().add_child(w)
	var ids: Dictionary = DemoScenario.build(w)
	_assert(ids["red_ids"].size() == 4 and ids["blue_ids"].size() == 4, "no-arg build() is still the classic 4v4")
	_assert(w.ships["alpha"].position == Vector3(-30_000.0, 0.0, 0.0), "classic layout: red flagship slot unchanged")
	_assert(absf(w.ships["beta"].position.x + 30_000.0) < 1.0, "classic layout: blue flagship slot unchanged (not mirrored)")
	_assert(absf(w.ships["beta"].position.z + 5.3e9) < 1000.0, "classic layout: blue starts 5.3 million km ahead")
	w.queue_free()

func _test_cm_stock_multiplier_and_policy() -> void:
	var w := SimulationWorld.new()
	get_root().add_child(w)
	var ids: Dictionary = DemoScenario.build(w, {"scenario": "ambush"})
	var red_stock: int = w.cm_ammo_remaining(ids["red_ids"][0])
	var blue_stock: int = w.cm_ammo_remaining(ids["blue_ids"][0])
	# heavy cruiser = 2 tubes x 8 rounds = 16 at multiplier 1.0
	_assert(red_stock == 24 and blue_stock == 8, "ambush: red gets 1.5x (24), blue 0.5x (8) of a heavy cruiser's 16 (got %d / %d)" % [red_stock, blue_stock])
	_assert(w.cm_policy_of(ids["blue_ids"][0]) == "auto", "enemy doctrine: blue counter-missile policy set from the scenario")
	w.queue_free()
