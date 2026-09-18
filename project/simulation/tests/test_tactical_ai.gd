extends SceneTree
## Headless test runner for TacticalAI (ТЗ §26): sensor-limited target
## selection for point defense and ship-to-ship weapons.
## Run via: godot --headless --script res://simulation/tests/test_tactical_ai.gd

const TacticalAI = preload("res://simulation/tactical_ai.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")

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
	return s

func _make_contact(target, state: int, estimated_position: Vector3) -> SensorContact:
	var c := SensorContact.new(target)
	c.state = state
	c.estimated_position = estimated_position
	return c

func _test_pd_ignores_undetected_missiles() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var missile := MissileState.new()
	missile.target = ship
	var contacts := {"m1": _make_contact(missile, ContactState.Type.UNKNOWN, Vector3(1000, 0, 0))}
	var result := TacticalAI.select_pd_target(ship, contacts)
	_assert(result["missile"] == null, "UNKNOWN contact should not be selected as a PD target")

func _test_pd_ignores_missiles_not_targeting_this_ship() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var other_ship := _make_ship(Vector3(50, 0, 0))
	var missile := MissileState.new()
	missile.target = other_ship  # targeting someone else
	var contacts := {"m1": _make_contact(missile, ContactState.Type.TRACKED, Vector3(1000, 0, 0))}
	var result := TacticalAI.select_pd_target(ship, contacts)
	_assert(result["missile"] == null, "a missile not targeting this ship should not be selected")

func _test_pd_selects_nearest_usable_missile() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var far_missile := MissileState.new()
	far_missile.target = ship
	var near_missile := MissileState.new()
	near_missile.target = ship
	var contacts := {
		"far": _make_contact(far_missile, ContactState.Type.TRACKED, Vector3(10000, 0, 0)),
		"near": _make_contact(near_missile, ContactState.Type.DETECTED, Vector3(1000, 0, 0)),
	}
	var result := TacticalAI.select_pd_target(ship, contacts)
	_assert(result["missile"] == near_missile, "should select the nearer usable contact, regardless of DETECTED vs TRACKED")

func _test_pd_uses_contact_estimate_not_true_position() -> void:
	# "No cheat vision": even if the true missile object sits far away,
	# selection must go by the CONTACT's estimated (possibly stale)
	# position, not missile.position directly.
	var ship := _make_ship(Vector3.ZERO)
	var missile_a := MissileState.new()
	missile_a.target = ship
	missile_a.position = Vector3(999999, 0, 0)  # true position: very far
	var missile_b := MissileState.new()
	missile_b.target = ship
	missile_b.position = Vector3(999999, 0, 0)  # true position: also very far
	var contacts := {
		"a": _make_contact(missile_a, ContactState.Type.ESTIMATED, Vector3(500, 0, 0)),   # stale estimate: close
		"b": _make_contact(missile_b, ContactState.Type.ESTIMATED, Vector3(5000, 0, 0)),  # stale estimate: farther
	}
	var result := TacticalAI.select_pd_target(ship, contacts)
	_assert(result["missile"] == missile_a, "selection must be driven by the contact's estimated_position, not the missile's true position")

func _test_pd_ignores_inactive_missiles() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var missile := MissileState.new()
	missile.target = ship
	missile.guidance_state = MissileState.GuidanceState.DETONATED
	var contacts := {"m1": _make_contact(missile, ContactState.Type.TRACKED, Vector3(1000, 0, 0))}
	var result := TacticalAI.select_pd_target(ship, contacts)
	_assert(result["missile"] == null, "an already-detonated (inactive) missile should not be selected")

func _test_weapon_target_selection_filters_by_hostile_list() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var hostile_ship := _make_ship(Vector3(1000, 0, 0))
	var neutral_ship := _make_ship(Vector3(10, 0, 0))  # much closer, but not in the hostile list
	var contacts := {
		"hostile": _make_contact(hostile_ship, ContactState.Type.TRACKED, Vector3(1000, 0, 0)),
		"neutral": _make_contact(neutral_ship, ContactState.Type.TRACKED, Vector3(10, 0, 0)),
	}
	var result := TacticalAI.select_weapon_target(ship, contacts, ["hostile"])
	_assert(result["ship_id"] == "hostile", "weapon target selection should only consider ids in the hostile list, even if a non-hostile contact is nearer")

func _test_weapon_target_selection_nearest_among_hostiles() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var near_hostile := _make_ship(Vector3(500, 0, 0))
	var far_hostile := _make_ship(Vector3(5000, 0, 0))
	var contacts := {
		"near": _make_contact(near_hostile, ContactState.Type.DETECTED, Vector3(500, 0, 0)),
		"far": _make_contact(far_hostile, ContactState.Type.TRACKED, Vector3(5000, 0, 0)),
	}
	var result := TacticalAI.select_weapon_target(ship, contacts, ["near", "far"])
	_assert(result["ship_id"] == "near", "should select the nearest hostile contact among multiple candidates")

func _test_weapon_target_selection_no_hostiles_returns_null() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var result := TacticalAI.select_weapon_target(ship, {}, [])
	_assert(result["ship_id"] == null, "no contacts/hostiles should return a null ship_id, not a crash or a bogus default")

func _init() -> void:
	_test_pd_ignores_undetected_missiles()
	_test_pd_ignores_missiles_not_targeting_this_ship()
	_test_pd_selects_nearest_usable_missile()
	_test_pd_uses_contact_estimate_not_true_position()
	_test_pd_ignores_inactive_missiles()
	_test_weapon_target_selection_filters_by_hostile_list()
	_test_weapon_target_selection_nearest_among_hostiles()
	_test_weapon_target_selection_no_hostiles_returns_null()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
