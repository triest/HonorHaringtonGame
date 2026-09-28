extends SceneTree
const SimulationWorld = preload("res://simulation/simulation_world.gd")
const DemoScenario = preload("res://scripts/demo_scenario.gd")
const SelectionState = preload("res://scripts/selection_state.gd")
const CommandBar = preload("res://scripts/command_bar.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")

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
	# Give alpha a live sensor track on every blue ship (bypass waiting for
	# real detection -- this test is about the SELECTION LOGIC, not sensors).
	for bid in ["beta", "beta_2", "beta_3", "beta_4"]:
		var c := SensorContact.new(world.ships[bid])
		c.state = ContactState.Type.TRACKED
		c.estimated_position = world.ships[bid].position
		c.estimated_velocity = world.ships[bid].velocity
		world.sensor_contacts["alpha"][bid] = c
	# beta_3 is the most damaged (lowest structural condition); beta_2's
	# WEAPONS (not structural) is badly hurt -- must NOT be picked.
	world.ships["beta_3"].subsystems.apply_damage(SubsystemType.Type.STRUCTURAL_INTEGRITY, 0.6)
	world.ships["beta_2"].subsystems.apply_damage(SubsystemType.Type.WEAPONS, 0.95)
	world.ships["beta_4"].is_wreck = true  # dead ships must be ignored even though "destroyed" reads as maximally damaged

	var sel := SelectionState.new()
	sel.select_only(["alpha"])
	var bar := CommandBar.new()
	bar.world = world
	bar.selection = sel
	bar.player_team = "red"

	bar._attack_weakest()

	# transmit_ship_target()/transmit_ship_weapons_free() are comm-delayed
	# (§25/§31) -- tick forward past the delay before checking that they
	# actually landed.
	var dt := 1.0 / 60.0
	for i in range(120):
		world.tick_simulation(dt)

	_check(sel.designated_target_id == "beta_3", "should designate the lowest-STRUCTURAL_INTEGRITY live, tracked contact (beta_3), got '%s'" % sel.designated_target_id)
	_check(world.get_weapon_target_designation("alpha") == "beta_3", "alpha's actual weapon target designation should be beta_3")
	var directive = world.ship_combat_directives.get("alpha")
	_check(directive != null and directive.weapons_free, "weapons_free should be turned on by the order")

	print("Passed: ", passed, " Failed: ", failures)
	print("ALL TESTS PASSED" if failures == 0 else "SOME TESTS FAILED")
	quit(1 if failures > 0 else 0)
