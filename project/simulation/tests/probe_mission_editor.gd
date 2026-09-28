extends SceneTree
## Headless sanity check of the Mission Editor rebuild path: instances
## main.tscn (default 4x4 builds immediately, per _ready()), then invokes
## the editor's on_confirm with a DIFFERENT mixed composition and checks
## the world/UI actually rebuilt onto it cleanly.
var main
var n := 0
var failures := 0
var passed := 0

func _check(c: bool, m: String) -> void:
	if c:
		passed += 1
	else:
		failures += 1
		print("FAIL: ", m)

func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		_check(main.world.ships.size() == 8, "default _ready() build should have 8 ships, got %d" % main.world.ships.size())
		_check(main.world.ships.has("alpha_4") and not main.world.ships.has("alpha_5"), "default should be exactly 4 red ships")
		var new_setup := {
			"red": [{"class_id": "destroyer", "count": 2}, {"class_id": "battlecruiser", "count": 1}],
			"blue": [{"class_id": "light_cruiser", "count": 3}],
		}
		main.mission_editor.on_confirm.call(new_setup)
	elif n == 5:
		_check(main.world.ships.size() == 6, "rebuilt world should have 3+3=6 ships, got %d" % main.world.ships.size())
		_check(main.world.ships.has("alpha") and main.world.ships.has("alpha_3") and not main.world.ships.has("alpha_4"), "red side should be exactly 3 ships after rebuild")
		_check(main.world.ships.has("beta") and main.world.ships.has("beta_3") and not main.world.ships.has("beta_4"), "blue side should be exactly 3 ships after rebuild")
		_check(main.world.missile_tubes["alpha"].size() == 2, "alpha (destroyer) should have 2 tubes, got %d" % main.world.missile_tubes["alpha"].size())
		_check(main.world.missile_tubes["alpha_3"].size() == 6, "alpha_3 (battlecruiser, 3rd red ship) should have 6 tubes, got %d" % main.world.missile_tubes["alpha_3"].size())
		_check(main.world.missile_tubes["beta"].size() == 3, "beta (light_cruiser) should have 3 tubes, got %d" % main.world.missile_tubes["beta"].size())
		_check(main.world.teams["alpha"] == "red" and main.world.teams["beta"] == "blue", "teams should be set correctly after rebuild")
		_check(main.world.formations.has("red_line") and main.world.formations["red_line"].member_ids().size() == 2, "red formation should have the guide + 2 members after rebuild")
		_check(main.selection.selected_ids == ["alpha", "alpha_2", "alpha_3"], "selection should default to the new red roster, got %s" % [main.selection.selected_ids])
		_check(main.world.world_sim_time < 1.0, "world_sim_time should have reset to ~0 on rebuild, got %f" % main.world.world_sim_time)
		_check(ShipNames.of("alpha_3") != "alpha_3", "ShipNames should have a display name for the new roster's ships")
		var live_shipviews := 0
		for ch in main.get_children():
			if ch is ShipView:
				live_shipviews += 1
		_check(live_shipviews == 6, "exactly 6 live ShipView nodes should remain after rebuild+GC settles, got %d" % live_shipviews)
		print("Passed: ", passed, " Failed: ", failures)
		print("ALL TESTS PASSED" if failures == 0 else "SOME TESTS FAILED")
		quit(1 if failures > 0 else 0)
	return false
