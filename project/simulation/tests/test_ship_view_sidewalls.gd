extends SceneTree
const ShipView = preload("res://scripts/ship_view.gd")
## Headless unit test for ShipView's sidewall-visibility decisions (ТЗ
## §16 Sidewalls, §56.1 item 2 vertical-slice visualization). These are
## pure static functions specifically so they are testable without
## instantiating a Node3D/scene tree -- mirrors WedgeMeshBuilder.
## _width_profile's testable-pure-helper pattern (test_wedge_mesh_
## builder.gd). This test does NOT touch MeshInstance3D wiring itself;
## that is exercised visually (headless test runs cannot verify
## on-screen rendering) but the visibility LOGIC it depends on is fully
## covered here.
## Run: godot4 --headless --script res://simulation/tests/test_ship_view_sidewalls.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_broadside_visible_when_undamaged()
	failures += _test_broadside_hidden_when_burned_out()
	failures += _test_broadside_hidden_exactly_at_burnout_threshold()
	failures += _test_bow_stern_hidden_when_not_raised_even_at_full_condition()
	failures += _test_bow_stern_visible_when_raised_and_undamaged()
	failures += _test_bow_stern_hidden_when_raised_but_burned_out()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_broadside_visible_when_undamaged() -> int:
	var ok: bool = ShipView._broadside_sidewall_visible(1.0) == true
	if not ok:
		printerr("FAIL broadside_visible_when_undamaged")
		return 1
	return 0

func _test_broadside_hidden_when_burned_out() -> int:
	var ok: bool = ShipView._broadside_sidewall_visible(0.0) == false
	if not ok:
		printerr("FAIL broadside_hidden_when_burned_out")
		return 1
	return 0

func _test_broadside_hidden_exactly_at_burnout_threshold() -> int:
	# ship_defense_state.gd's SIDEWALL_BURNOUT_THRESHOLD is the condition
	# AT OR BELOW which a sidewall is non-functional -- visibility must
	# use a strict ">" so the boundary itself reads as "down", consistent
	# with ShipDefenseState's own is_sidewall_functional-style checks.
	var ok: bool = ShipView._broadside_sidewall_visible(ShipDefenseState.SIDEWALL_BURNOUT_THRESHOLD) == false
	if not ok:
		printerr("FAIL broadside_hidden_exactly_at_burnout_threshold")
		return 1
	return 0

func _test_bow_stern_hidden_when_not_raised_even_at_full_condition() -> int:
	# Default state (ship_defense_state.gd): bow_sidewall_raised = false.
	# A fully-functional but un-raised bow wall must not render, since
	# raising it is a deliberate player/AI choice that costs impeller
	# acceleration (CONFIRMED CANON).
	var ok: bool = ShipView._bow_stern_sidewall_visible(false, 1.0) == false
	if not ok:
		printerr("FAIL bow_stern_hidden_when_not_raised_even_at_full_condition")
		return 1
	return 0

func _test_bow_stern_visible_when_raised_and_undamaged() -> int:
	var ok: bool = ShipView._bow_stern_sidewall_visible(true, 1.0) == true
	if not ok:
		printerr("FAIL bow_stern_visible_when_raised_and_undamaged")
		return 1
	return 0

func _test_bow_stern_hidden_when_raised_but_burned_out() -> int:
	var ok: bool = ShipView._bow_stern_sidewall_visible(true, 0.0) == false
	if not ok:
		printerr("FAIL bow_stern_hidden_when_raised_but_burned_out")
		return 1
	return 0
