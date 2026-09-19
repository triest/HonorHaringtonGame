extends SceneTree
## Headless test runner for TacticalAI (ТЗ §26): sensor-limited target
## selection for point defense and ship-to-ship weapons.
## Run via: godot --headless --script res://simulation/tests/test_tactical_ai.gd

const TacticalAI = preload("res://simulation/tactical_ai.gd")
const SensorContact = preload("res://simulation/sensor_contact.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const HullState = preload("res://simulation/hull_state.gd")

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

## §30 "target"/"target priority" directed selection (Milestone 11,
## second slice) -- see ship_combat_directive.gd.
func _test_directed_target_selection_returns_designated_hostile_even_if_farther() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var near_hostile := _make_ship(Vector3(500, 0, 0))
	var far_hostile := _make_ship(Vector3(5000, 0, 0))
	var contacts := {
		"near": _make_contact(near_hostile, ContactState.Type.DETECTED, Vector3(500, 0, 0)),
		"far": _make_contact(far_hostile, ContactState.Type.TRACKED, Vector3(5000, 0, 0)),
	}
	var result := TacticalAI.select_directed_weapon_target(ship, contacts, ["near", "far"], "far")
	_assert(result["ship_id"] == "far", "a manually designated target should be selected even though it is not the nearest hostile")
	_assert(result["ship"] == far_hostile, "the returned ship should be the designated target's true object")

func _test_directed_target_selection_rejects_non_hostile_designation() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var neutral_ship := _make_ship(Vector3(10, 0, 0))
	var contacts := {"neutral": _make_contact(neutral_ship, ContactState.Type.TRACKED, Vector3(10, 0, 0))}
	var result := TacticalAI.select_directed_weapon_target(ship, contacts, [], "neutral")
	_assert(result["ship_id"] == null, "a designated target not in the hostile list should not be selectable, even if a usable contact exists for it")

func _test_directed_target_selection_rejects_unusable_contact() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var hostile_ship := _make_ship(Vector3(500, 0, 0))
	var contacts := {"hostile": _make_contact(hostile_ship, ContactState.Type.UNKNOWN, Vector3(500, 0, 0))}
	var result := TacticalAI.select_directed_weapon_target(ship, contacts, ["hostile"], "hostile")
	_assert(result["ship_id"] == null, "a designated target this ship's sensors have lost (UNKNOWN state) should not be selectable")

func _test_directed_target_selection_rejects_empty_designation() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var hostile_ship := _make_ship(Vector3(500, 0, 0))
	var contacts := {"hostile": _make_contact(hostile_ship, ContactState.Type.TRACKED, Vector3(500, 0, 0))}
	var result := TacticalAI.select_directed_weapon_target(ship, contacts, ["hostile"], "")
	_assert(result["ship_id"] == null, "an empty designation string should never resolve to a target")

## §34.1 Doubling -- TacticalAI.select_formation_target_for_member.
func _test_formation_target_selection_degenerates_to_plain_selection_when_uncoordinated() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var near_hostile := _make_ship(Vector3(500, 0, 0))
	var far_hostile := _make_ship(Vector3(5000, 0, 0))
	var contacts := {
		"near": _make_contact(near_hostile, ContactState.Type.DETECTED, Vector3(500, 0, 0)),
		"far": _make_contact(far_hostile, ContactState.Type.TRACKED, Vector3(5000, 0, 0)),
	}
	var result := TacticalAI.select_formation_target_for_member(ship, contacts, ["near", "far"], {}, {})
	_assert(result["ship_id"] == "near", "with no hulls tracked and no prior assignments, coordinated selection should match plain nearest-hostile selection")

func _test_formation_target_selection_avoids_overcommitted_target_when_alternative_exists() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var near_hostile := _make_ship(Vector3(500, 0, 0))
	var far_hostile := _make_ship(Vector3(5000, 0, 0))
	var contacts := {
		"near": _make_contact(near_hostile, ContactState.Type.DETECTED, Vector3(500, 0, 0)),
		"far": _make_contact(far_hostile, ContactState.Type.TRACKED, Vector3(5000, 0, 0)),
	}
	# "near" already has 2 formation-mates assigned (the default cap) -- a
	# third member should be steered to "far" instead of piling on, even
	# though "near" is still the nearer contact.
	var assigned_counts := {"near": 2}
	var result := TacticalAI.select_formation_target_for_member(ship, contacts, ["near", "far"], {}, assigned_counts, 2)
	_assert(result["ship_id"] == "far", "a target already claimed by max_useful_attackers formation-mates should be deprioritized while an uncommitted alternative exists (§34.1)")

func _test_formation_target_selection_still_picks_overcommitted_target_if_it_is_the_only_option() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var only_hostile := _make_ship(Vector3(500, 0, 0))
	var contacts := {"only": _make_contact(only_hostile, ContactState.Type.DETECTED, Vector3(500, 0, 0))}
	var assigned_counts := {"only": 5}
	var result := TacticalAI.select_formation_target_for_member(ship, contacts, ["only"], {}, assigned_counts, 2)
	_assert(result["ship_id"] == "only", "a ship should never be left without a target purely because the only visible hostile is already over-committed")

func _test_formation_target_selection_deprioritizes_neutralized_target() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var wounded := _make_ship(Vector3(500, 0, 0))  # nearer, but hull already critically damaged
	var healthy := _make_ship(Vector3(5000, 0, 0))
	var wounded_hull := HullState.new()
	wounded_hull.max_integrity = 1000.0
	wounded_hull.integrity = 100.0  # 10% -- below the default 0.3 critical fraction
	var healthy_hull := HullState.new()
	var contacts := {
		"wounded": _make_contact(wounded, ContactState.Type.DETECTED, Vector3(500, 0, 0)),
		"healthy": _make_contact(healthy, ContactState.Type.TRACKED, Vector3(5000, 0, 0)),
	}
	var hulls := {"wounded": wounded_hull, "healthy": healthy_hull}
	var result := TacticalAI.select_formation_target_for_member(ship, contacts, ["wounded", "healthy"], hulls, {})
	_assert(result["ship_id"] == "healthy", "an already-near-destroyed target should be deprioritized in favor of a full-health one, even though it is nearer (avoid overkill, §34.1)")

func _test_formation_target_selection_still_picks_neutralized_target_if_it_is_the_only_option() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var wounded := _make_ship(Vector3(500, 0, 0))
	var wounded_hull := HullState.new()
	wounded_hull.max_integrity = 1000.0
	wounded_hull.integrity = 50.0
	var contacts := {"wounded": _make_contact(wounded, ContactState.Type.DETECTED, Vector3(500, 0, 0))}
	var hulls := {"wounded": wounded_hull}
	var result := TacticalAI.select_formation_target_for_member(ship, contacts, ["wounded"], hulls, {})
	_assert(result["ship_id"] == "wounded", "a lone near-dead target is still better than no target at all")

func _test_formation_target_selection_no_hostiles_returns_null() -> void:
	var ship := _make_ship(Vector3.ZERO)
	var result := TacticalAI.select_formation_target_for_member(ship, {}, [], {}, {})
	_assert(result["ship_id"] == null, "no contacts/hostiles should return a null ship_id, same as select_weapon_target")

func _init() -> void:
	_test_pd_ignores_undetected_missiles()
	_test_pd_ignores_missiles_not_targeting_this_ship()
	_test_pd_selects_nearest_usable_missile()
	_test_pd_uses_contact_estimate_not_true_position()
	_test_pd_ignores_inactive_missiles()
	_test_weapon_target_selection_filters_by_hostile_list()
	_test_weapon_target_selection_nearest_among_hostiles()
	_test_weapon_target_selection_no_hostiles_returns_null()
	_test_directed_target_selection_returns_designated_hostile_even_if_farther()
	_test_directed_target_selection_rejects_non_hostile_designation()
	_test_directed_target_selection_rejects_unusable_contact()
	_test_directed_target_selection_rejects_empty_designation()

	_test_formation_target_selection_degenerates_to_plain_selection_when_uncoordinated()
	_test_formation_target_selection_avoids_overcommitted_target_when_alternative_exists()
	_test_formation_target_selection_still_picks_overcommitted_target_if_it_is_the_only_option()
	_test_formation_target_selection_deprioritizes_neutralized_target()
	_test_formation_target_selection_still_picks_neutralized_target_if_it_is_the_only_option()
	_test_formation_target_selection_no_hostiles_returns_null()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
