extends SceneTree
## Headless test runner for SensorResolution (ТЗ §23 Sensors).
## Run via: godot --headless --script res://simulation/tests/test_sensor_resolution.gd

const SensorContact = preload("res://simulation/sensor_contact.gd")
const SensorResolution = preload("res://simulation/sensor_resolution.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(pos: Vector3, wedge_up: bool = true) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = pos
	s.velocity = Vector3.ZERO
	s.defense = ShipDefenseState.new()
	s.defense.wedge_up = wedge_up
	return s

func _test_detection_when_in_range_and_emitting() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "in-range emitting target should become DETECTED")
	_assert(contact.estimated_position.is_equal_approx(Vector3(1000, 0, 0)), "estimated position should match true position on detection")

func _test_no_detection_when_wedge_down() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), false)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.UNKNOWN, "wedge-down target in range should NOT be detected")

func _test_no_detection_when_out_of_range() -> void:
	var target := _make_ship(Vector3(10_000_000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.UNKNOWN, "out-of-range target should not be detected")

func _test_missile_detectable_while_burning_not_while_coasting() -> void:
	var missile := MissileState.new()
	missile.position = Vector3(500, 0, 0)
	missile.velocity = Vector3.ZERO
	missile.drive_burn_remaining_s = 10.0
	var contact := SensorContact.new(missile)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "burning missile should be detected")

	var coasting := MissileState.new()
	coasting.position = Vector3(500, 0, 0)
	coasting.velocity = Vector3.ZERO
	coasting.drive_burn_remaining_s = 0.0
	var contact2 := SensorContact.new(coasting)
	SensorResolution.update_contact(contact2, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact2.state == ContactState.Type.UNKNOWN, "coasting (unpowered) missile should not be freshly detected")

func _test_detected_upgrades_to_tracked_after_sustained_contact() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	for i in range(10):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.TRACKED, "sustained detection should upgrade DETECTED -> TRACKED")

func _test_loss_of_detection_goes_to_estimated_then_lost() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	for i in range(3):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "losing detection should transition to ESTIMATED")

	for i in range(60):
		SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.LOST, "ESTIMATED should decay to LOST after grace period expires")

func _test_estimated_dead_reckons_position() -> void:
	var target := _make_ship(Vector3(0, 0, 0), true)
	target.velocity = Vector3(100, 0, 0)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3(0, 0, -1_000), 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3(0, 0, -1_000), 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "should be ESTIMATED after loss")
	_assert(contact.estimated_position.x > 0.0, "dead reckoning should advance estimated position using last known velocity")

func _test_contact_resumes_detection_after_reappearing() -> void:
	var target := _make_ship(Vector3(1000, 0, 0), true)
	var contact := SensorContact.new(target)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	target.defense.wedge_up = false
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.ESTIMATED, "should be ESTIMATED after loss")
	target.defense.wedge_up = true
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "reappearing target should re-detect as DETECTED")


func _test_coasting_ship_has_shorter_effective_range_than_burning_ship() -> void:
	# ТЗ §23 next slice (ASSUMPTIONS.md "Заметность от тяги"): a ship
	# with wedge up but zero current thrust is only detectable within
	# MIN_SIGNATURE_FRACTION (0.35) of the base range; a ship burning at
	# its full rated acceleration is detectable at the full base range.
	# Distance chosen (500,000 of a 1,000,000 base range) sits strictly
	# between 0.35x and 1.0x, so this is a real range difference, not a
	# coincidence of the two test setups' own math.
	var coasting := _make_ship(Vector3(500_000, 0, 0), true)
	# acceleration left at its default Vector3.ZERO -- genuinely
	# coasting, not just "not integrated yet".
	var coasting_contact := SensorContact.new(coasting)
	SensorResolution.update_contact(coasting_contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(coasting_contact.state == ContactState.Type.UNKNOWN, "coasting ship (wedge up, zero thrust) beyond 0.35x range should NOT be freshly detected")

	var burning := _make_ship(Vector3(500_000, 0, 0), true)
	burning.acceleration = Vector3(burning.effective_max_acceleration(), 0, 0)
	var burning_contact := SensorContact.new(burning)
	SensorResolution.update_contact(burning_contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(burning_contact.state == ContactState.Type.DETECTED, "ship burning at full rated thrust should be detected at the same distance a coasting ship is not")


func _test_signature_strength_scales_continuously_with_thrust_ratio() -> void:
	# Half-thrust should land strictly between the coasting floor and the
	# full-thrust ceiling -- catches a regression to a binary on/off
	# implementation disguised as "scaling".
	var half_thrust := _make_ship(Vector3(675_000, 0, 0), true)
	half_thrust.acceleration = Vector3(half_thrust.effective_max_acceleration() * 0.5, 0, 0)
	# expected effective range = 1,000,000 * (0.35 + 0.5*0.65) = 675,000
	var contact := SensorContact.new(half_thrust)
	SensorResolution.update_contact(contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact.state == ContactState.Type.DETECTED, "half-thrust ship exactly at its own effective range boundary should still be detected (<=, not <)")

	var half_thrust_just_beyond := _make_ship(Vector3(676_000, 0, 0), true)
	half_thrust_just_beyond.acceleration = Vector3(half_thrust_just_beyond.effective_max_acceleration() * 0.5, 0, 0)
	var contact2 := SensorContact.new(half_thrust_just_beyond)
	SensorResolution.update_contact(contact2, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(contact2.state == ContactState.Type.UNKNOWN, "half-thrust ship just beyond its own effective range should not be detected")


func _test_full_burn_missile_detectable_farther_than_extended_range_missile() -> void:
	# Same idea for missiles: MissileState.set_throttle() (ТЗ §56.3 item
	# E "EXTENDED RANGE") throttles down drive_max_acceleration_mps2,
	# which should also shrink the missile's own detection signature --
	# a quieter burn is a fair trade for extended range, not a free
	# stealth bonus AND free range with no downside.
	var full_burn := MissileState.new()
	full_burn.position = Vector3(500_000, 0, 0)
	full_burn.velocity = Vector3.ZERO
	full_burn.drive_burn_remaining_s = 10.0
	var full_contact := SensorContact.new(full_burn)
	SensorResolution.update_contact(full_contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(full_contact.state == ContactState.Type.DETECTED, "un-throttled (full burn) missile should be detected at 0.5x base range")

	var extended_range := MissileState.new()
	extended_range.position = Vector3(500_000, 0, 0)
	extended_range.velocity = Vector3.ZERO
	extended_range.set_throttle(0.05)
	extended_range.drive_burn_remaining_s = 10.0
	var extended_contact := SensorContact.new(extended_range)
	SensorResolution.update_contact(extended_contact, Vector3.ZERO, 1.0, 1_000_000.0)
	_assert(extended_contact.state == ContactState.Type.UNKNOWN, "min-throttle (extended range) missile should NOT be detected at the same 0.5x base range distance")

func _init() -> void:
	_test_detection_when_in_range_and_emitting()
	_test_no_detection_when_wedge_down()
	_test_no_detection_when_out_of_range()
	_test_missile_detectable_while_burning_not_while_coasting()
	_test_detected_upgrades_to_tracked_after_sustained_contact()
	_test_loss_of_detection_goes_to_estimated_then_lost()
	_test_estimated_dead_reckons_position()
	_test_contact_resumes_detection_after_reappearing()
	_test_coasting_ship_has_shorter_effective_range_than_burning_ship()
	_test_signature_strength_scales_continuously_with_thrust_ratio()
	_test_full_burn_missile_detectable_farther_than_extended_range_missile()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
