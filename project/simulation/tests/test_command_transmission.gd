extends SceneTree
## Headless test runner for the §25/§31 communication-delayed individual
## order transmission added this pass: `SimulationWorld.transmit_*`
## wrappers around the pre-existing immediate `issue_individual_order_now`/
## `set_ship_target`/`clear_ship_target`/`set_ship_weapons_free`/
## `return_ship_to_formation` APIs (see simulation_world.gd's own doc
## comments on those constants/functions for the full rationale). Closes
## two honestly-logged gaps at once: §31 "account for communication
## limitations" for individual orders, and §25's own worked example
## "communications damage -> degraded command/reporting".
##
## Deliberately full-tick (`SimulationWorld.tick_simulation`) tests
## throughout -- the entire point of this mechanic is what happens across
## several ticks (nothing happens, then something happens), which a
## single isolated call cannot exercise.
## Run via: godot --headless --path . --script res://simulation/tests/test_command_transmission.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const IndividualOrder = preload("res://simulation/individual_order.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship(with_subsystems: bool = false) -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	if with_subsystems:
		s.subsystems = ShipSubsystems.new()
	return s

func _hold_order() -> IndividualOrder:
	var o := IndividualOrder.new()
	o.kind = IndividualOrder.Kind.HOLD
	return o

func _tick_seconds(world: SimulationWorld, seconds: float, step: float = 0.1) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt: float = minf(step, remaining)
		world.tick_simulation(dt)
		remaining -= dt

func _test_transmit_does_not_apply_immediately() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship())
	world.transmit_individual_order_now("alpha", _hold_order())
	_assert(not world.is_ship_overriding_formation("alpha"), "transmit_individual_order_now must NOT take effect before any time has passed -- it is queued, not immediate")

func _test_transmit_applies_after_base_delay_with_healthy_comms() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(true))  # condition == 1.0 -> base delay only
	world.transmit_individual_order_now("alpha", _hold_order())
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S - 0.15)
	_assert(not world.is_ship_overriding_formation("alpha"), "order should still be in transit just before the base transmission delay elapses")
	_tick_seconds(world, 0.3)
	_assert(world.is_ship_overriding_formation("alpha"), "order should have landed once at least the base transmission delay has elapsed")

func _test_no_subsystems_uses_base_delay_not_worst_case() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(false))  # no ShipSubsystems at all
	world.transmit_individual_order_now("alpha", _hold_order())
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(world.is_ship_overriding_formation("alpha"), "a ship with no ShipSubsystems should use the healthy-comms baseline delay, not hang forever or use a worst-case value")

func _test_degraded_communications_lengthens_delay() -> void:
	var world := SimulationWorld.new()
	var ship := _make_ship(true)
	ship.subsystems.apply_damage(SubsystemType.Type.COMMUNICATIONS, 0.5)  # condition -> 0.5, delay doubles
	world.add_ship("alpha", ship)
	world.transmit_individual_order_now("alpha", _hold_order())
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(not world.is_ship_overriding_formation("alpha"), "with COMMUNICATIONS condition 0.5, the order should NOT have landed yet at just past the healthy-comms base delay")
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S)
	_assert(world.is_ship_overriding_formation("alpha"), "with COMMUNICATIONS condition 0.5 (delay doubled to ~2x base), the order should have landed by ~2x the base delay")

func _test_transmit_ship_target_and_weapons_free_are_delayed() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(true))
	world.transmit_ship_target("alpha", "bravo")
	world.transmit_ship_weapons_free("alpha", false)
	_assert(not world.ship_combat_directives.has("alpha"), "designation/weapons_free must not exist yet before the transmission delay elapses")
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "bravo", "designation should have landed after the transmission delay")
	_assert(world.ship_combat_directives["alpha"].weapons_free == false, "hold-fire order should have landed after the transmission delay")

func _test_transmit_clear_target_and_return_to_formation() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(true))
	world.set_ship_target("alpha", "bravo")  # immediate API, sets it right away
	world.issue_individual_order_now("alpha", _hold_order())  # immediate API
	_assert(world.is_ship_overriding_formation("alpha"), "sanity check: alpha should start under individual command")

	world.transmit_clear_ship_target("alpha")
	world.transmit_return_ship_to_formation("alpha")
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "bravo", "clear_ship_target must not apply before the delay elapses")
	_assert(world.is_ship_overriding_formation("alpha"), "return_ship_to_formation must not apply before the delay elapses")

	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(world.ship_combat_directives["alpha"].manual_target_ship_id == "", "clear_ship_target should have applied once the delay elapsed")
	_assert(not world.is_ship_overriding_formation("alpha"), "return_ship_to_formation should have applied once the delay elapsed")

func _test_immediate_apis_remain_synchronous() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(true))
	world.issue_individual_order_now("alpha", _hold_order())
	_assert(world.is_ship_overriding_formation("alpha"), "the pre-existing immediate API must still take effect with zero delay, completely unaffected by this pass")

func _test_remove_ship_discards_pending_transmission() -> void:
	var world := SimulationWorld.new()
	world.add_ship("alpha", _make_ship(true))
	world.transmit_individual_order_now("alpha", _hold_order())
	world.remove_ship("alpha")
	world.add_ship("alpha", _make_ship(true))  # re-add a fresh ship under the same id
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(not world.is_ship_overriding_formation("alpha"), "a pending transmission queued for a removed ship must not resurrect state on a later, unrelated ship reusing the same id")

func _test_delayed_order_actually_overrides_formation_keeping_once_landed() -> void:
	# End-to-end sanity: once a transmitted HOLD order lands, it must
	# actually zero this ship's thrust/angular velocity the same way the
	# immediate API already does (verified in test_individual_orders.gd) --
	# this test only proves the TRANSMISSION seam doesn't drop or mangle
	# the order on its way through the pending queue.
	var world := SimulationWorld.new()
	var ship := _make_ship(true)
	ship.commanded_thrust_local = Vector3(5.0, 0, 0)
	ship.angular_velocity = Vector3(0.1, 0, 0)
	world.add_ship("alpha", ship)
	world.transmit_individual_order_now("alpha", _hold_order())
	_tick_seconds(world, world.INDIVIDUAL_ORDER_BASE_TRANSMISSION_DELAY_S + 0.15)
	_assert(ship.commanded_thrust_local == Vector3.ZERO, "HOLD order, once landed via transmission, should zero thrust exactly like the immediate API does")
	_assert(ship.angular_velocity == Vector3.ZERO, "HOLD order, once landed via transmission, should zero angular velocity exactly like the immediate API does")

func _init() -> void:
	_test_transmit_does_not_apply_immediately()
	_test_transmit_applies_after_base_delay_with_healthy_comms()
	_test_no_subsystems_uses_base_delay_not_worst_case()
	_test_degraded_communications_lengthens_delay()
	_test_transmit_ship_target_and_weapons_free_are_delayed()
	_test_transmit_clear_target_and_return_to_formation()
	_test_immediate_apis_remain_synchronous()
	_test_remove_ship_discards_pending_transmission()
	_test_delayed_order_actually_overrides_formation_keeping_once_landed()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
