extends SceneTree
## Headless unit test for WeaponPanelController (ТЗ §56.3 item E,
## §1.10.8). Run:
## godot --headless --script res://simulation/tests/test_weapon_panel_controller.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const WeaponPanelController = preload("res://scripts/weapon_panel_controller.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const MissileState = preload("res://simulation/missile_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	_test_empty_selection_hides_panel()
	_test_hostile_selection_hides_panel()
	_test_multi_ship_selection_hides_panel()
	_test_ship_with_no_mounts_shows_no_sections()
	_test_energy_weapon_section_shown_with_arc_and_status()
	_test_missile_section_hidden_when_no_tubes()
	_test_missile_section_defaults_and_salvo_cycle_wraps()
	_test_throttle_cycle_toggles_label()
	_test_fire_missiles_caps_at_salvo_size_and_applies_throttle()
	_test_point_defense_hidden_when_no_mounts()
	_test_point_defense_toggle_persists_after_comm_delay()
	_test_pd_hold_prevents_engagement_this_tick()
	_test_counter_missiles_never_shown()

	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _passed)
	else:
		printerr("%d TEST(S) FAILED (%d passed)" % [_failures, _passed])
	quit(_failures)

func _make_ship(pos: Vector3 = Vector3.ZERO) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.defense = ShipDefenseState.new()
	return s

func _basic_two_side_world() -> SimulationWorld:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(Vector3.ZERO))
	world.set_team("alpha", "red")
	world.add_ship("bravo", _make_ship(Vector3(500_000.0, 0.0, 0.0)))
	world.set_team("bravo", "blue")
	return world

func _make_controller(world: SimulationWorld, selection: SelectionState, player_team: String = "red") -> WeaponPanelController:
	var controller := WeaponPanelController.new()
	controller.world = world
	controller.selection = selection
	controller.player_team = player_team
	return controller

func _tick_seconds(world: SimulationWorld, seconds: float, step: float = 0.1) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt: float = minf(step, remaining)
		world.tick_simulation(dt)
		remaining -= dt

func _has_row_kind(rows: Array, kind: String) -> bool:
	for row in rows:
		if String(row.get("kind", "")) == kind:
			return true
	return false

func _row_with_kind(rows: Array, kind: String) -> Dictionary:
	for row in rows:
		if String(row.get("kind", "")) == kind:
			return row
	return {}

func _any_label_contains(rows: Array, needle: String) -> bool:
	for row in rows:
		if String(row.get("label", "")).findn(needle) >= 0:
			return true
	return false

func _make_laser_mount(arc: Array = WeaponMount.broadside_arc()) -> WeaponMount:
	var laser := WeaponData.new()
	laser.id = "test_laser"
	laser.weapon_class = WeaponData.WeaponClass.ENERGY_LASER
	return WeaponMount.new(laser, arc)

func _test_empty_selection_hides_panel() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not controller.is_visible, "an empty selection must not show the weapon panel")
	_assert(controller.rows.is_empty(), "rows must be empty when hidden")

func _test_hostile_selection_hides_panel() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["bravo"])  # hostile to player_team "red"
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not controller.is_visible, "selecting a hostile contact must never show the player its loadout (no ground-truth leak)")

func _test_multi_ship_selection_hides_panel() -> void:
	var world := _basic_two_side_world()
	world.add_ship("gamma", _make_ship(Vector3(0, 0, 1000)))
	world.set_team("gamma", "red")
	var selection := SelectionState.new()
	selection.select_only(["alpha", "gamma"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not controller.is_visible, "a multi-ship group selection has no single ship's loadout to show, so the panel must stay hidden")

func _test_ship_with_no_mounts_shows_no_sections() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(controller.is_visible, "a lone own-ship selection must show the panel even with nothing mounted")
	_assert(controller.rows.is_empty(), "§1.10.8 hard requirement: a ship with no weapons at all must show no weapon sections")

func _test_energy_weapon_section_shown_with_arc_and_status() -> void:
	var world := _basic_two_side_world()
	world.add_weapon_mount("alpha", _make_laser_mount(WeaponMount.bow_chaser_arc()))
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(controller.is_visible, "a ship with an energy mount must show the panel")
	_assert(_any_label_contains(controller.rows, "ENERGY WEAPONS"), "energy section header must appear")
	_assert(_any_label_contains(controller.rows, "laser"), "the mounted weapon's class must be named")
	_assert(_any_label_contains(controller.rows, "bow"), "the mount's firing arc must be shown")
	_assert(_any_label_contains(controller.rows, "ready"), "a fresh mount (no cooldown) must show as ready")
	_assert(not _any_label_contains(controller.rows, "MISSILES"), "a ship with no missile tubes must not show a MISSILES section")
	_assert(not _any_label_contains(controller.rows, "POINT DEFENSE"), "a ship with no PD mounts must not show a POINT DEFENSE section")

func _test_missile_section_hidden_when_no_tubes() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not _any_label_contains(controller.rows, "MISSILES"), "§1.10.8 hard requirement: no missile tubes -> no MISSILES section")

func _test_missile_section_defaults_and_salvo_cycle_wraps() -> void:
	var world := _basic_two_side_world()
	world.add_missile_tube("alpha", MissileTube.new())
	world.add_missile_tube("alpha", MissileTube.new())
	world.add_missile_tube("alpha", MissileTube.new())
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()

	_assert(_any_label_contains(controller.rows, "MISSILES (3/3 tubes ready)"), "all 3 fresh tubes should show as ready")
	var salvo_row: Dictionary = _row_with_kind(controller.rows, "SALVO_CYCLE")
	_assert(not salvo_row.is_empty(), "a SALVO_CYCLE row must exist when tubes are mounted")
	_assert(String(salvo_row.get("label", "")).findn("salvo size: 1") >= 0, "salvo size must default to 1")

	controller.execute_row("SALVO_CYCLE")
	_assert(String(_row_with_kind(controller.rows, "SALVO_CYCLE").get("label", "")).findn("salvo size: 2") >= 0, "cycling once with 3 tubes should go to 2")
	controller.execute_row("SALVO_CYCLE")
	_assert(String(_row_with_kind(controller.rows, "SALVO_CYCLE").get("label", "")).findn("salvo size: 3") >= 0, "cycling again should go to 3 (== tube count)")
	controller.execute_row("SALVO_CYCLE")
	_assert(String(_row_with_kind(controller.rows, "SALVO_CYCLE").get("label", "")).findn("salvo size: 1") >= 0, "cycling past the tube count must wrap back to 1")

func _test_throttle_cycle_toggles_label() -> void:
	var world := _basic_two_side_world()
	world.add_missile_tube("alpha", MissileTube.new())
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()

	_assert(String(_row_with_kind(controller.rows, "THROTTLE_CYCLE").get("label", "")).findn("FULL BURN") >= 0, "throttle profile must default to FULL BURN")
	controller.execute_row("THROTTLE_CYCLE")
	_assert(String(_row_with_kind(controller.rows, "THROTTLE_CYCLE").get("label", "")).findn("EXTENDED RANGE") >= 0, "cycling throttle once should switch to EXTENDED RANGE")
	controller.execute_row("THROTTLE_CYCLE")
	_assert(String(_row_with_kind(controller.rows, "THROTTLE_CYCLE").get("label", "")).findn("FULL BURN") >= 0, "cycling throttle again should return to FULL BURN")

func _test_fire_missiles_caps_at_salvo_size_and_applies_throttle() -> void:
	var world := _basic_two_side_world()
	# Tick once BEFORE tubes exist purely to populate sensor contacts,
	# same convention as test_missile_launch_order.gd -- adding tubes only
	# afterward means the automatic missile-launch AI never gets a turn
	# to fire on its own, so every missile created below is unambiguously
	# attributable to this test's own FIRE_MISSILES click.
	world.tick_simulation(1.0 / 60.0)
	for i in range(4):
		var tube := MissileTube.new()
		tube.reload_time_s = 0.0
		world.add_missile_tube("alpha", tube)

	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	controller.execute_row("SALVO_CYCLE")  # 1 -> 2
	controller.execute_row("THROTTLE_CYCLE")  # FULL_BURN -> EXTENDED_RANGE
	controller.execute_row("FIRE_MISSILES")

	_assert(world.missiles.size() == 2, "FIRE with salvo size 2 out of 4 ready tubes must launch exactly 2 missiles, not all 4")
	for missile_id in world.missiles.keys():
		var missile = world.missiles[missile_id]
		_assert(missile.drive_max_acceleration_mps2 < MissileState.DEFAULT_DRIVE_MAX_ACCELERATION_MPS2, "EXTENDED RANGE profile must reduce drive acceleration below the full-burn default")
		_assert(missile.drive_burn_time_s > MissileState.DEFAULT_DRIVE_BURN_TIME_S, "EXTENDED RANGE profile must increase burn time above the full-burn default")

func _test_point_defense_hidden_when_no_mounts() -> void:
	var world := _basic_two_side_world()
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not _any_label_contains(controller.rows, "POINT DEFENSE"), "§1.10.8 hard requirement: no PD mounts -> no POINT DEFENSE section")

func _test_point_defense_toggle_persists_after_comm_delay() -> void:
	var world := _basic_two_side_world()
	world.add_pd_mount("alpha", PointDefenseMount.new())
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()

	_assert(_any_label_contains(controller.rows, "POINT DEFENSE: AUTO"), "PD must default to AUTO")
	controller.execute_row("PD_TOGGLE")
	# world.transmit_ship_pd_hold is comm-delayed, same as
	# transmit_ship_weapons_free -- the underlying world state (and thus
	# what the NEXT sync() would show) only flips once the delay elapses.
	_assert(not world.ship_pd_hold.get("alpha", false), "PD hold must not take effect before the comm delay elapses")
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.2)
	_assert(world.ship_pd_hold.get("alpha", false), "PD hold must take effect once the comm delay has elapsed")
	controller.sync()
	_assert(_any_label_contains(controller.rows, "POINT DEFENSE: HOLD"), "the panel must reflect HOLD once the world state has actually flipped")

func _test_pd_hold_prevents_engagement_this_tick() -> void:
	var world := _basic_two_side_world()
	var mount := PointDefenseMount.new()
	mount.reaction_time_s = 0.0  # fire the same tick a target becomes usable
	mount.hits_required_to_kill = 5  # avoid an instant intercept muddying the assertion
	world.add_pd_mount("alpha", mount)
	var missile := MissileState.new()
	missile.position = Vector3(0, 0, -15000.0)  # inside PD's default 20,000m engagement range, well outside the 5,000m warhead-arm threshold (10% of terminal_detonation_range_m) so the missile does not self-destruct mid-test
	missile.target = world.get_ship("alpha")
	world.add_missile("incoming", missile, "bravo")

	world.set_ship_pd_hold("alpha", true)
	world.tick_simulation(1.0 / 60.0)
	_assert(mount.cooldown_remaining_s == 0.0, "a held PD mount must not engage even a usable in-range target")

	world.set_ship_pd_hold("alpha", false)
	world.tick_simulation(1.0 / 60.0)
	_assert(mount.cooldown_remaining_s > 0.0, "sanity check: with hold cleared, the same setup must actually engage")

func _test_counter_missiles_never_shown() -> void:
	var world := _basic_two_side_world()
	world.add_weapon_mount("alpha", _make_laser_mount())
	world.add_missile_tube("alpha", MissileTube.new())
	world.add_pd_mount("alpha", PointDefenseMount.new())
	var selection := SelectionState.new()
	selection.select_only(["alpha"])
	var controller := _make_controller(world, selection)
	controller.sync()
	_assert(not _any_label_contains(controller.rows, "COUNTER-MISSILE"), "§56.3 item E honest gap: COUNTER-MISSILES has no backing launch-decision mechanic and must never appear, even with every other section present")
