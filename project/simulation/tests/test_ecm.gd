extends SceneTree
## Headless test runner for ECM (ТЗ §24): jamming range reduction and
## decoy-return substitution in SensorResolution.
## Run via: godot --headless --script res://simulation/tests/test_ecm.gd

const SensorContact = preload("res://simulation/sensor_contact.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const ECMState = preload("res://simulation/ecm_state.gd")

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
	s.velocity = Vector3.ZERO
	s.defense = ShipDefenseState.new()
	s.defense.wedge_up = true
	return s

func _test_no_ecm_detects_normally() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, null)
	_assert(contact.state == ContactState.Type.DETECTED, "no ECM: normal detection within range should succeed")

func _test_jamming_shrinks_effective_range() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var ecm := ECMState.new()
	ecm.jamming_active = true
	ecm.jamming_range_multiplier = 0.4
	var contact := SensorContact.new(target)
	# Base range 2000m; jamming shrinks effective range to 800m, target is
	# at 1000m -- should NOT be detected under jamming though it would be
	# without it.
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, ecm)
	_assert(contact.state == ContactState.Type.UNKNOWN, "jamming should shrink effective sensor range enough to prevent detection at 1000m with a 0.4x multiplier on a 2000m base range")

func _test_detection_still_possible_closer_under_jamming() -> void:
	var target := _make_ship(Vector3(500, 0, 0))
	var ecm := ECMState.new()
	ecm.jamming_active = true
	ecm.jamming_range_multiplier = 0.4
	var contact := SensorContact.new(target)
	# Effective range = 2000*0.4 = 800m; target at 500m should still be
	# detectable -- jamming degrades range, it doesn't blind entirely.
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, ecm)
	_assert(contact.state == ContactState.Type.DETECTED, "close enough target should still be detected despite jamming")

func _test_inactive_jamming_has_no_effect() -> void:
	var target := _make_ship(Vector3(1000, 0, 0))
	var ecm := ECMState.new()
	ecm.jamming_active = false
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 2000.0, ecm)
	_assert(contact.state == ContactState.Type.DETECTED, "ECMState present but jamming_active=false should not affect detection")

func _test_decoy_closer_than_target_is_reported_instead() -> void:
	var target := _make_ship(Vector3(0, 0, 10000))
	var ecm := ECMState.new()
	ecm.jamming_active = true
	ecm.jamming_range_multiplier = 1.0  # isolate the decoy effect from range effect
	var decoy_pos := Vector3(0, 0, 3000)
	ecm.add_decoy(decoy_pos)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 20000.0, ecm)
	_assert(contact.state == ContactState.Type.DETECTED, "should still register a detection (of the decoy)")
	_assert(contact.estimated_position.is_equal_approx(decoy_pos), "closer decoy should be reported as the apparent contact position instead of the true target")

func _test_decoy_farther_than_target_is_ignored() -> void:
	var target := _make_ship(Vector3(0, 0, 1000))
	var ecm := ECMState.new()
	ecm.jamming_active = true
	ecm.jamming_range_multiplier = 1.0
	ecm.add_decoy(Vector3(0, 0, 9000))  # farther than the true target
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 20000.0, ecm)
	_assert(contact.estimated_position.is_equal_approx(Vector3(0, 0, 1000)), "a decoy farther than the true target should not override the true position")

func _test_max_decoys_enforced() -> void:
	var ecm := ECMState.new()
	var accepted := 0
	for i in range(10):
		if ecm.add_decoy(Vector3(i, 0, 0)):
			accepted += 1
	_assert(accepted == ECMState.MAX_DECOYS, "add_decoy should refuse beyond MAX_DECOYS (canon: only a handful deployable at a time)")

func _test_clear_decoys() -> void:
	var ecm := ECMState.new()
	ecm.add_decoy(Vector3(1, 0, 0))
	ecm.add_decoy(Vector3(2, 0, 0))
	ecm.clear_decoys()
	_assert(ecm.decoy_positions.is_empty(), "clear_decoys should empty the decoy list")

func _init() -> void:
	_test_no_ecm_detects_normally()
	_test_jamming_shrinks_effective_range()
	_test_detection_still_possible_closer_under_jamming()
	_test_inactive_jamming_has_no_effect()
	_test_decoy_closer_than_target_is_reported_instead()
	_test_decoy_farther_than_target_is_ignored()
	_test_max_decoys_enforced()
	_test_clear_decoys()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
