extends SceneTree
## Headless test runner for ShipClassData/ShipFactory (ТЗ §8 Ship Database,
## §48 Data-Driven Design) -- the first pass that wires the CANON ship-class
## reference data from AGENTS.md §8.1/§8.2/§8.3 into project/simulation as
## real, loadable `.tres` records instead of remaining reference prose (see
## the "HONEST GAP" notes those sections carried before this pass).
## Run via: godot --headless --path . --script res://simulation/tests/test_ship_class_data.gd

const ShipClassData = preload("res://simulation/ship_class_data.gd")
const ShipFactory = preload("res://simulation/ship_factory.gd")
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _assert_eq(actual, expected, message: String) -> void:
	_assert(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func _test_medusa_data_loads_and_is_valid() -> void:
	var medusa: ShipClassData = load("res://data/ships/medusa_class.tres")
	_assert(medusa != null, "medusa_class.tres must load")
	_assert(medusa.is_valid(), "medusa_class.tres must be valid (name/mass/source_note all set)")
	_assert_eq(medusa.canonical_name, "Medusa-class", "medusa canonical_name")
	_assert_eq(medusa.length_m, 1383.0, "medusa length_m (CANON, AGENTS.md §8.1)")
	_assert(medusa.rated_acceleration_g > 400.0 and medusa.rated_acceleration_g < 403.0, "medusa rated_acceleration_g must match CANON 402.3 G")
	_assert(medusa.source_note != "", "medusa source_note must record CANON/ASSUMPTION provenance (§8.4 step 6)")

func _test_sultan_data_loads_and_is_valid() -> void:
	var sultan: ShipClassData = load("res://data/ships/sultan_class.tres")
	_assert(sultan != null, "sultan_class.tres must load")
	_assert(sultan.is_valid(), "sultan_class.tres must be valid")
	_assert_eq(sultan.canonical_name, "Sultan-class", "sultan canonical_name")
	_assert(sultan.rated_acceleration_g > 489.0 and sultan.rated_acceleration_g < 489.4, "sultan rated_acceleration_g must match CANON 489.2 G")

func _test_spawn_produces_correct_physics_and_mount_counts() -> void:
	var medusa: ShipClassData = load("res://data/ships/medusa_class.tres")
	var world := SimulationWorld.new()
	var state := ShipFactory.spawn_ship(world, "medusa_1", medusa, Vector3.ZERO)

	_assert(state == world.get_ship("medusa_1"), "spawn_ship must register the ship in the world")
	_assert_eq(state.mass_kg, medusa.mass_kg, "spawned ship mass_kg must equal class data")

	# §62.1: acceleration is F/m, never a hardcoded cap -- the CANON G
	# rating must round-trip exactly through max_thrust_n/mass_kg.
	var expected_accel: float = medusa.rated_acceleration_g * ShipFactory.STANDARD_GRAVITY_MPS2
	_assert(is_equal_approx(state.effective_max_acceleration(), expected_accel), "spawned ship's effective_max_acceleration() must reproduce the class's CANON G rating via F/m")

	var expected_energy_mounts: int = medusa.broadside_laser_mounts + medusa.broadside_graser_mounts + medusa.fore_laser_mounts + medusa.fore_graser_mounts + medusa.aft_laser_mounts + medusa.aft_graser_mounts
	_assert_eq(world.weapon_mounts["medusa_1"].size(), expected_energy_mounts, "spawned energy mount count must equal sum of class data zone counts")

	var expected_tubes: int = medusa.broadside_missile_tubes + medusa.fore_missile_tubes + medusa.aft_missile_tubes
	_assert_eq(world.missile_tubes["medusa_1"].size(), expected_tubes, "spawned missile tube count must equal sum of class data zone counts")

	var expected_pd: int = medusa.broadside_pd_mounts + medusa.fore_pd_mounts + medusa.aft_pd_mounts
	_assert_eq(world.pd_mounts["medusa_1"].size(), expected_pd, "spawned PD mount count must equal sum of class data zone counts")

	# Milestone-relevant regression: prior to this pass, CHANGELOG.md
	# explicitly noted no scenario/ship loadout assigned real positional
	# (broadside vs. chase) PD batteries -- every PD mount was
	# omnidirectional. Verify spawned PD mounts actually carry the
	# CLOUD.md-derived arc, not the omnidirectional default.
	var broadside_pd_seen: int = 0
	var chaser_pd_seen: int = 0
	for mount in world.pd_mounts["medusa_1"]:
		if mount.arc_sectors == PointDefenseMount.broadside_arc():
			broadside_pd_seen += 1
		elif mount.arc_sectors == PointDefenseMount.bow_chaser_arc() or mount.arc_sectors == PointDefenseMount.stern_chaser_arc():
			chaser_pd_seen += 1
	_assert_eq(broadside_pd_seen, medusa.broadside_pd_mounts, "spawned broadside PD mounts must carry PointDefenseMount.broadside_arc(), not the omnidirectional default")
	_assert(chaser_pd_seen == medusa.fore_pd_mounts + medusa.aft_pd_mounts, "spawned chase PD mounts must carry a chaser arc, not the omnidirectional default")

	# Energy mounts: same arc-assignment check via WeaponMount.
	var broadside_energy_seen: int = 0
	for mount in world.weapon_mounts["medusa_1"]:
		if mount.arc_sectors == WeaponMount.broadside_arc():
			broadside_energy_seen += 1
	_assert_eq(broadside_energy_seen, medusa.broadside_laser_mounts + medusa.broadside_graser_mounts, "spawned broadside energy mounts must carry WeaponMount.broadside_arc()")

func _test_missile_magazine_is_divided_across_spawned_tubes() -> void:
	var sultan: ShipClassData = load("res://data/ships/sultan_class.tres")
	var world := SimulationWorld.new()
	ShipFactory.spawn_ship(world, "sultan_1", sultan, Vector3.ZERO)
	var tubes: Array = world.missile_tubes["sultan_1"]
	var total_tubes: int = sultan.broadside_missile_tubes + sultan.fore_missile_tubes + sultan.aft_missile_tubes
	_assert_eq(tubes.size(), total_tubes, "sultan total tube count")
	var total_ammo: int = 0
	for tube in tubes:
		total_ammo += tube.ammo_count
	# Integer division per-tube, so the total can be slightly less than
	# the magazine figure (remainder dropped, see ShipFactory doc comment)
	# but never more, and never zero when a real magazine is recorded.
	_assert(total_ammo <= sultan.missile_magazine_total, "distributed ammo must not exceed the class's CANON magazine total")
	_assert(total_ammo > sultan.missile_magazine_total - total_tubes, "distributed ammo must not lose more than one round per tube to integer rounding")

func _test_full_tick_with_two_data_driven_ships() -> void:
	# End-to-end sanity check through the real tick loop (per AGENTS.md
	# instructions: "for each new combat mechanic, try to have at least
	# one end-to-end test via SimulationWorld.tick_simulation()") -- two
	# CANON-sourced classes, spawned entirely from data, ticked forward,
	# and confirmed to still integrate physics correctly (no crash, no
	# NaN, inertial motion consistent with the assigned thrust/orientation).
	var medusa: ShipClassData = load("res://data/ships/medusa_class.tres")
	var sultan: ShipClassData = load("res://data/ships/sultan_class.tres")
	var world := SimulationWorld.new()
	# Deliberately NOT assigning teams here: this test isolates
	# data-driven PHYSICS (thrust/mass/acceleration wired from
	# ShipClassData), not Tactical AI/Crossing-the-T behavior (already
	# covered by test_tactical_ai.gd/test_crossing_the_t.gd) -- a hostile
	# team pair would let `_resolve_crossing_t_maneuver` autonomously
	# override `commanded_thrust_local` with an intercept course instead
	# of honoring the manual command asserted below.
	var s1 := ShipFactory.spawn_ship(world, "medusa_1", medusa, Vector3.ZERO)
	var s2 := ShipFactory.spawn_ship(world, "sultan_1", sultan, Vector3(500000, 0, 0))

	s1.commanded_thrust_local = Vector3(0, 0, -1)  # bow-forward, per attack_geometry.gd's -Z=bow convention

	for i in range(60):
		world.tick_simulation(1.0 / 60.0)

	_assert(not is_nan(s1.position.x) and not is_nan(s1.position.y) and not is_nan(s1.position.z), "medusa position must remain finite after 60 ticks")
	_assert(s1.position.z < 0.0, "thrusting medusa must have moved in the commanded bow-forward (-Z) direction")
	_assert(world.get_ship("medusa_1") != null and world.get_ship("sultan_1") != null, "both data-driven ships must still exist after a normal tick run (no destruction expected, no contact)")

func _init() -> void:
	_test_medusa_data_loads_and_is_valid()
	_test_sultan_data_loads_and_is_valid()
	_test_spawn_produces_correct_physics_and_mount_counts()
	_test_missile_magazine_is_divided_across_spawned_tubes()
	_test_full_tick_with_two_data_driven_ships()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
