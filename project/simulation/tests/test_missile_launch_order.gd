extends SceneTree
## Headless test runner for SimulationWorld.order_missile_launch (§30
## "missile launch", Milestone 11 -- a discrete one-time salvo order,
## distinct from the standing "weapon mode" posture already covered in
## test_ship_combat_directive.gd). Run via:
## godot --headless --path . --script res://simulation/tests/test_missile_launch_order.gd
##
## Full-tick-adjacent but deliberately calling `order_missile_launch`
## directly rather than `tick_simulation` for most cases -- this order
## is, by design, NOT part of the per-tick AI resolution loop at all
## (see its doc comment in simulation_world.gd), so exercising it
## directly is the honest way to test it; a couple of tests do combine
## it with `tick_simulation` to prove it does not disturb the standing
## directive/automatic AI.

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")

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

func _make_hull(fraction: float = 1.0) -> HullState:
	var h := HullState.new()
	h.max_integrity = 1000.0
	h.integrity = 1000.0 * fraction
	return h

func _make_tube() -> MissileTube:
	var tube := MissileTube.new()
	tube.ammo_count = 3
	tube.reload_time_s = 0.0  # ready regardless of time_since_last_launch_s
	tube.max_range_m = 5_000_000.0
	return tube

func _test_no_target_falls_back_to_standing_automatic_selection() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("near", near)
	world.add_ship("far", far)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	# Tick BEFORE the tube exists, purely to populate sensor contacts
	# (refreshed at the top of tick_simulation) -- adding the tube only
	# afterward means the automatic missile-launch AI never gets a turn
	# to fire on its own, so the single launch below is unambiguously
	# attributable to order_missile_launch itself.
	world.tick_simulation(1.0 / 60.0)
	world.add_missile_tube("alpha", _make_tube())

	var launched: int = world.order_missile_launch("alpha")

	_assert(launched == 1, "with no explicit target, order_missile_launch should fire using the same standing/automatic target resolution as the AI")
	_assert(world.missiles.size() == 1, "exactly one missile should have been created")
	var missile = world.missiles.values()[0]
	_assert(missile.target == near, "with no manual designation, the automatic nearest-hostile pick (near) should be used, not far")

func _test_explicit_target_overrides_standing_designation_without_changing_it() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	var far := _make_ship(Vector3(0, 0, -900_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("near", near)
	world.add_ship("far", far)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.set_team("far", "blue")
	world.set_ship_target("alpha", "near")  # standing designation: near
	world.tick_simulation(1.0 / 60.0)  # populate sensor contacts; no tube yet, so the automatic AI cannot have fired
	world.add_missile_tube("alpha", _make_tube())

	var launched: int = world.order_missile_launch("alpha", "far")  # one-time order: fire at FAR instead

	_assert(launched >= 1, "an explicit one-time target should launch when the tube is ready and target is in range")
	var found_far_shot := false
	for m in world.missiles.values():
		if m.target == far:
			found_far_shot = true
	_assert(found_far_shot, "order_missile_launch with an explicit target should launch at that target, not the standing designation")
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "near", "a one-time explicit-target order must NOT overwrite the ship's standing manual target designation")

func _test_invalid_explicit_target_does_not_fall_back() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var near := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("near", near)
	world.set_team("alpha", "red")
	world.set_team("near", "blue")
	world.tick_simulation(1.0 / 60.0)
	world.add_missile_tube("alpha", _make_tube())

	var launched: int = world.order_missile_launch("alpha", "nonexistent_ship")

	_assert(launched == 0, "an explicit target that is not a usable hostile contact should NOT silently fall back to automatic selection -- a one-time order fires at the named target or not at all")
	_assert(world.missiles.is_empty(), "no missile should be created when the explicitly ordered target is invalid")

func _test_hold_fire_suppresses_explicit_order_too() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.tick_simulation(1.0 / 60.0)
	world.add_missile_tube("alpha", _make_tube())
	world.set_ship_weapons_free("alpha", false)

	var launched: int = world.order_missile_launch("alpha", "beta")

	_assert(launched == 0, "a ship under an explicit hold-fire directive should not launch even on a direct one-time order -- weapons_free has one consistent meaning everywhere")
	_assert(world.missiles.is_empty(), "no missile should be created while holding fire")

func _test_critically_damaged_ship_does_not_launch() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var alpha_hull := _make_hull(0.1)  # 10% integrity, well under CRITICAL_HULL_FRACTION (0.3)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha, alpha_hull)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.tick_simulation(1.0 / 60.0)
	world.add_missile_tube("alpha", _make_tube())

	var launched: int = world.order_missile_launch("alpha", "beta")

	_assert(launched == 0, "a critically damaged (disengaging) ship should not launch missiles even on a direct one-time order")

func _test_out_of_range_target_does_not_launch() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -9_000_000.0))  # beyond the tube's 5,000,000m range
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.tick_simulation(1.0 / 60.0)
	world.add_missile_tube("alpha", _make_tube())

	var launched: int = world.order_missile_launch("alpha", "beta")

	_assert(launched == 0, "a target beyond the tube's effective range should not be launched at, even on a direct one-time order")
	_assert(world.missiles.is_empty(), "no missile should be created for an out-of-range explicit order")

func _test_unready_tube_does_not_launch_and_is_not_double_counted() -> void:
	var world := SimulationWorld.new()
	var alpha := _make_ship(Vector3.ZERO)
	var beta := _make_ship(Vector3(0, 0, -500_000.0))
	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")
	world.tick_simulation(1.0 / 60.0)
	var spent_tube := _make_tube()
	spent_tube.ammo_count = 0  # out of ammo -- never ready
	var ready_tube := _make_tube()
	world.add_missile_tube("alpha", spent_tube)
	world.add_missile_tube("alpha", ready_tube)

	var launched: int = world.order_missile_launch("alpha", "beta")

	_assert(launched == 1, "order_missile_launch should fire only from ready tubes and report the exact count launched, not the tube count")
	_assert(spent_tube.ammo_count == 0, "an out-of-ammo tube must not be touched by a one-time order")
	_assert(ready_tube.ammo_count == 2, "the one ready tube should have consumed exactly one round")

func _test_missing_ship_or_no_tubes_returns_zero_without_error() -> void:
	var world := SimulationWorld.new()
	_assert(world.order_missile_launch("ghost", "beta") == 0, "ordering a launch for a ship that doesn't exist should return 0, not error")

	var alpha := _make_ship(Vector3.ZERO)
	world.add_ship("alpha", alpha)
	_assert(world.order_missile_launch("alpha", "beta") == 0, "a ship with no missile tubes at all should return 0")

func _init() -> void:
	_test_no_target_falls_back_to_standing_automatic_selection()
	_test_explicit_target_overrides_standing_designation_without_changing_it()
	_test_invalid_explicit_target_does_not_fall_back()
	_test_hold_fire_suppresses_explicit_order_too()
	_test_critically_damaged_ship_does_not_launch()
	_test_out_of_range_target_does_not_launch()
	_test_unready_tube_does_not_launch_and_is_not_double_counted()
	_test_missing_ship_or_no_tubes_returns_zero_without_error()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
