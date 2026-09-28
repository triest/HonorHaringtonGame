extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

var passed := 0
var failures := 0
func _check(c: bool, m: String) -> void:
	if c: passed += 1
	else:
		failures += 1
		print("FAIL: ", m)

func _alpha_missile_count(world) -> int:
	var n := 0
	for mid in world.missiles.keys():
		if world.missile_owners.get(mid, "") == "alpha":
			n += 1
	return n

func _init() -> void:
	var world := SimulationWorld.new()
	get_root().add_child(world)
	DemoScenario.build(world)
	for sid in world.ships.keys():
		if world.teams[sid] == "blue":
			world.ships[sid].position.z += 3.1e8
	# Give alpha a live, in-range, in-arc target and drive its own hull
	# straight to critical without waiting for a real missile exchange.
	world.transmit_ship_target("alpha", "beta")
	world.transmit_ship_weapons_free("alpha", true)
	world.ships["alpha"].subsystems.apply_damage(SubsystemType.Type.STRUCTURAL_INTEGRITY, 0.75)  # -> 25% condition, below the 30% disengage threshold
	var dt := 1.0 / 60.0

	# --- Phase 1: no override -- ship should go silent and get shoved onto a retreat course.
	for i in range(120):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
	var missiles_launched_without_override: int = _alpha_missile_count(world)
	_check(missiles_launched_without_override == 0, "a critical, unoverridden ship should not have launched any missiles, got %d" % missiles_launched_without_override)
	_check(world.ships["alpha"].commanded_thrust_local.z > 0.0, "a critical, unoverridden ship should have been pushed onto a retreat course (away from the enemy, +Z for red), got %s" % world.ships["alpha"].commanded_thrust_local)

	# --- Phase 2: admiral overrides -- "Драться до конца".
	world.set_ship_hold_the_line("alpha", true)
	world.ships["alpha"].commanded_thrust_local = Vector3(0, 0, -0.8)  # simulate the player re-ordering it back toward the fight
	var missiles_before: int = _alpha_missile_count(world)
	for i in range(180):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
		# _resolve_damage_response must NOT re-apply retreat thrust once overridden.
		_check(not (world.ships["alpha"].commanded_thrust_local.z > 0.0), "hold-the-line ship should never be forced onto a retreat course")
	var missiles_after: int = _alpha_missile_count(world)
	_check(missiles_after > missiles_before, "an overridden critical ship should resume launching missiles at its still-valid target (before=%d after=%d)" % [missiles_before, missiles_after])

	# --- Phase 3: admiral rescinds the order -- old behavior resumes.
	world.set_ship_hold_the_line("alpha", false)
	for i in range(90):
		for sid in world.weapon_mounts.keys():
			for m in world.weapon_mounts[sid]:
				m.tick(dt)
		world.tick_simulation(dt)
	_check(world.ships["alpha"].commanded_thrust_local.z > 0.0, "rescinding the order should let the automatic retreat resume")

	print("Passed: ", passed, " Failed: ", failures)
	print("ALL TESTS PASSED" if failures == 0 else "SOME TESTS FAILED")
	quit(1 if failures > 0 else 0)
