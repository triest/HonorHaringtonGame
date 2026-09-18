extends SceneTree
## Headless test runner for TacticalAI's "respond to damage" / "retreat" /
## "disengage" slice (ТЗ §26) -- both the pure TacticalAI functions and
## SimulationWorld's wiring of them (_resolve_damage_response,
## _resolve_weapons_ai's disengage check).
## Run via: godot --headless --path . --script res://simulation/tests/test_tactical_ai_retreat.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const TacticalAI = preload("res://simulation/tactical_ai.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")

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

func _make_hull(integrity: float, max_integrity: float = 10_000.0) -> HullState:
	var h := HullState.new()
	h.max_integrity = max_integrity
	h.integrity = integrity
	return h

func _test_is_critically_damaged_thresholds() -> void:
	_assert(not TacticalAI.is_critically_damaged(null), "a null hull (no hull tracked) should never be treated as critically damaged")
	_assert(not TacticalAI.is_critically_damaged(_make_hull(10_000.0)), "a full-integrity hull should not be critically damaged")
	_assert(not TacticalAI.is_critically_damaged(_make_hull(3_001.0)), "just above the default 30% threshold should not be critically damaged")
	_assert(TacticalAI.is_critically_damaged(_make_hull(3_000.0)), "exactly at the default 30% threshold should be critically damaged")
	_assert(TacticalAI.is_critically_damaged(_make_hull(100.0)), "a near-destroyed hull should be critically damaged")
	_assert(TacticalAI.is_critically_damaged(_make_hull(4_000.0), 0.5), "a custom higher threshold should also be respected")

func _test_select_retreat_vector_world_averages_away_from_hostiles() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var contacts: Dictionary = {}

	var contact_a := SensorContact.new(null)
	contact_a.state = ContactState.Type.TRACKED
	contact_a.estimated_position = Vector3(1000.0, 0, 0)
	contacts["hostile_a"] = contact_a

	var contact_b := SensorContact.new(null)
	contact_b.state = ContactState.Type.TRACKED
	contact_b.estimated_position = Vector3(0, 0, 1000.0)
	contacts["hostile_b"] = contact_b

	# A non-hostile contact at the same distance must NOT influence the result.
	var contact_neutral := SensorContact.new(null)
	contact_neutral.state = ContactState.Type.TRACKED
	contact_neutral.estimated_position = Vector3(-1000.0, 0, 0)
	contacts["neutral_c"] = contact_neutral

	var away: Vector3 = TacticalAI.select_retreat_vector_world(ship, contacts, ["hostile_a", "hostile_b"])
	_assert(away.length() > 0.0, "should produce a non-zero retreat direction when hostile contacts exist")
	_assert(away.x < -0.01 and away.z < -0.01, "should retreat away from BOTH hostiles (negative X and negative Z), ignoring the neutral contact")

func _test_select_retreat_vector_world_zero_with_no_usable_hostiles() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var contacts: Dictionary = {}
	var contact := SensorContact.new(null)
	contact.state = ContactState.Type.LOST  # not a "usable" state
	contact.estimated_position = Vector3(1000.0, 0, 0)
	contacts["hostile_a"] = contact

	var away: Vector3 = TacticalAI.select_retreat_vector_world(ship, contacts, ["hostile_a"])
	_assert(away == Vector3.ZERO, "should return ZERO when no hostile contact is in a usable sensor state")

func _test_critically_damaged_ship_retreats_and_stops_firing() -> void:
	var world := SimulationWorld.new()

	var alpha := _make_ship(Vector3(1000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	beta.defense.port_sidewall_condition = 0.4
	beta.defense.starboard_sidewall_condition = 0.4

	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")

	var weapon := WeaponData.new()
	weapon.max_range_m = 500_000.0
	weapon.damage_per_hit = 100.0
	weapon.recharge_time_s = 0.0
	var mount := WeaponMount.new(weapon, WeaponMount.broadside_arc())
	world.add_weapon_mount("alpha", mount)

	var alpha_hull := _make_hull(500.0)  # 5% integrity -- well below the 30% threshold
	world.hulls["alpha"] = alpha_hull
	var beta_hull := HullState.new()
	world.hulls["beta"] = beta_hull
	var beta_starting_integrity: float = beta_hull.integrity

	alpha.commanded_thrust_local = Vector3.FORWARD  # would otherwise close on beta; must be overridden

	for i in range(3):
		world.tick_simulation(1.0 / 60.0)

	_assert(beta_hull.integrity == beta_starting_integrity, "a critically damaged ship's AI should NOT fire on a hostile -- it is disengaging")
	_assert(alpha.commanded_thrust_local.dot(Vector3(1, 0, 0)) > 0.0, "a critically damaged ship should thrust away from its known hostile (beta is at -X relative to alpha, so away is +X)")

func _test_healthy_ship_still_fires_and_does_not_retreat() -> void:
	var world := SimulationWorld.new()

	var alpha := _make_ship(Vector3(1000.0, 0, 0))
	var beta := _make_ship(Vector3.ZERO)
	beta.defense.port_sidewall_condition = 0.4
	beta.defense.starboard_sidewall_condition = 0.4

	world.add_ship("alpha", alpha)
	world.add_ship("beta", beta)
	world.set_team("alpha", "red")
	world.set_team("beta", "blue")

	var weapon := WeaponData.new()
	weapon.max_range_m = 500_000.0
	weapon.damage_per_hit = 100.0
	weapon.recharge_time_s = 0.0
	var mount := WeaponMount.new(weapon, WeaponMount.broadside_arc())
	world.add_weapon_mount("alpha", mount)

	world.hulls["alpha"] = _make_hull(10_000.0)  # full health
	var beta_hull := HullState.new()
	world.hulls["beta"] = beta_hull
	var beta_starting_integrity: float = beta_hull.integrity

	alpha.commanded_thrust_local = Vector3.ZERO

	for i in range(3):
		world.tick_simulation(1.0 / 60.0)

	_assert(beta_hull.integrity < beta_starting_integrity, "a healthy ship's AI should still fire on a hostile as before")
	_assert(alpha.commanded_thrust_local == Vector3.ZERO, "a healthy ship's commanded thrust should not be touched by the damage-response rule")

func _init() -> void:
	_test_is_critically_damaged_thresholds()
	_test_select_retreat_vector_world_averages_away_from_hostiles()
	_test_select_retreat_vector_world_zero_with_no_usable_hostiles()
	_test_critically_damaged_ship_retreats_and_stops_firing()
	_test_healthy_ship_still_fires_and_does_not_retreat()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
