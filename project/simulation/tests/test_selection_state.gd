extends SceneTree
const SelectionState = preload("res://scripts/selection_state.gd")
## Headless unit test for SelectionState (ТЗ §56.3 item A). Run:
## godot4 --headless --script res://simulation/tests/test_selection_state.gd

func _init() -> void:
	var failures: int = 0
	failures += _test_select_only_replaces_selection()
	failures += _test_toggle_adds_new_id()
	failures += _test_toggle_removes_existing_id()
	failures += _test_add_only_never_removes()
	failures += _test_add_only_does_not_duplicate()
	failures += _test_clear_empties_selection()
	failures += _test_is_selected_reflects_state()
	failures += _test_selection_changed_signal_fires()
	failures += _test_selection_changed_not_emitted_on_noop_clear()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(failures)

func _test_select_only_replaces_selection() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha", "beta"])
	sel.select_only(["gamma"])
	if sel.selected_ids != ["gamma"]:
		printerr("FAIL select_only_replaces_selection: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_toggle_adds_new_id() -> int:
	var sel := SelectionState.new()
	sel.toggle("alpha")
	if sel.selected_ids != ["alpha"]:
		printerr("FAIL toggle_adds_new_id: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_toggle_removes_existing_id() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha", "beta"])
	sel.toggle("alpha")
	if sel.selected_ids != ["beta"]:
		printerr("FAIL toggle_removes_existing_id: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_add_only_never_removes() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha"])
	sel.add_only(["beta", "alpha"])
	if sel.selected_ids != ["alpha", "beta"]:
		printerr("FAIL add_only_never_removes: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_add_only_does_not_duplicate() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha"])
	sel.add_only(["alpha"])
	if sel.selected_ids != ["alpha"]:
		printerr("FAIL add_only_does_not_duplicate: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_clear_empties_selection() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha", "beta"])
	sel.clear()
	if not sel.is_empty():
		printerr("FAIL clear_empties_selection: %s" % [sel.selected_ids])
		return 1
	return 0

func _test_is_selected_reflects_state() -> int:
	var sel := SelectionState.new()
	sel.select_only(["alpha"])
	if not sel.is_selected("alpha") or sel.is_selected("beta"):
		printerr("FAIL is_selected_reflects_state")
		return 1
	return 0

func _test_selection_changed_signal_fires() -> int:
	var sel := SelectionState.new()
	var received: Array = []
	sel.selection_changed.connect(func(ids): received.append(ids.duplicate()))
	sel.select_only(["alpha"])
	sel.toggle("beta")
	if received.size() != 2:
		printerr("FAIL selection_changed_signal_fires: received=%s" % [received])
		return 1
	return 0

func _test_selection_changed_not_emitted_on_noop_clear() -> int:
	var sel := SelectionState.new()
	var fire_count: int = 0
	sel.selection_changed.connect(func(_ids): fire_count += 1)
	sel.clear()  # already empty -- should not emit
	if fire_count != 0:
		printerr("FAIL selection_changed_not_emitted_on_noop_clear: fire_count=%d" % fire_count)
		return 1
	return 0
