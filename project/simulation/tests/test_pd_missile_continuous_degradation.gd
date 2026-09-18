extends SceneTree
## Headless test runner for the §25 continuous-degradation falloff added
## this pass to PointDefenseMount/MissileTube: closes the "hard on/off
## only" half of the honest gap recorded in ASSUMPTIONS.md/CHANGELOG.md
## for POINT_DEFENSE/MISSILE_SYSTEMS (WEAPONS already scaled damage
## continuously via mount.condition; PD/missile tubes previously only
## gated at condition <= 0.0 via is_ready()).
##
## Covers: the new effective_* getters in isolation (condition == 1.0
## backward-compat identity + condition < 1.0 scaling direction/magnitude),
## PointDefenseResolution.engage() actually taking longer to acquire/
## recharge and reaching a shorter range under degraded condition, and
## MissileTube.is_ready()/the launch-AI range check in SimulationWorld
## respecting the degraded values -- plus one sync-through-the-world
## sanity check via SimulationWorld.tick_simulation(), same pattern as
## test_subsystem_damage_consumers.gd, since that is where a real bug was
## previously found at the module-boundary that isolated tests missed.
## Run via: godot --headless --path . --script res://simulation/tests/test_pd_missile_continuous_degradation.gd

const SimulationWorld = preload("res://simulation/simulation_world.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const MissileState = preload("res://simulation/missile_state.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _almost_equal(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _test_pd_effective_getters_identity_at_full_condition() -> void:
	var mount := PointDefenseMount.new()
	mount.condition = 1.0
	_assert(_almost_equal(mount.effective_reaction_time_s(), mount.reaction_time_s), "PD condition=1.0: effective_reaction_time_s must equal raw reaction_time_s (backward compat)")
	_assert(_almost_equal(mount.effective_recharge_time_s(), mount.recharge_time_s), "PD condition=1.0: effective_recharge_time_s must equal raw recharge_time_s (backward compat)")
	_assert(_almost_equal(mount.effective_engagement_range_m(), mount.max_engagement_range_m), "PD condition=1.0: effective_engagement_range_m must equal raw max_engagement_range_m (backward compat)")

func _test_pd_effective_getters_scale_with_condition() -> void:
	var mount := PointDefenseMount.new()
	mount.condition = 0.5
	_assert(_almost_equal(mount.effective_reaction_time_s(), mount.reaction_time_s / 0.5), "PD condition=0.5: reaction time should double")
	_assert(_almost_equal(mount.effective_recharge_time_s(), mount.recharge_time_s / 0.5), "PD condition=0.5: recharge time should double")
	_assert(_almost_equal(mount.effective_engagement_range_m(), mount.max_engagement_range_m * 0.5), "PD condition=0.5: engagement range should halve")

func _test_pd_effective_getters_floor_near_zero_condition() -> void:
	var mount := PointDefenseMount.new()
	mount.condition = 0.0
	_assert(mount.effective_reaction_time_s() < 1e9 and mount.effective_reaction_time_s() > 0.0, "PD condition=0.0: effective_reaction_time_s must stay finite/positive (floored), not INF/NaN")
	_assert(mount.effective_engagement_range_m() == 0.0, "PD condition=0.0: effective_engagement_range_m must be exactly 0.0 (no floor on the linear-scaling one)")

func _test_pd_engage_takes_longer_to_acquire_when_degraded() -> void:
	# Same reaction_time_s ticked amount produces SHOT_FIRED at full
	# condition but only ACQUIRING at half condition, since the effective
	# reaction time has doubled.
	var mount_full := PointDefenseMount.new()
	mount_full.condition = 1.0
	var mount_degraded := PointDefenseMount.new()
	mount_degraded.condition = 0.5

	var ship := ShipPhysicsState.new()
	ship.position = Vector3.ZERO
	var missile := MissileState.new()
	missile.position = Vector3(0, 0, 5000.0)
	missile.guidance_state = MissileState.GuidanceState.BOOST

	var dt: float = mount_full.reaction_time_s  # exactly the FULL-condition reaction time
	var result_full := PointDefenseResolution.engage(mount_full, ship, missile, dt)
	var result_degraded := PointDefenseResolution.engage(mount_degraded, ship, missile, dt)

	_assert(result_full.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "PD full condition: exactly reaction_time_s of tracking should fire")
	_assert(result_degraded.outcome == PointDefenseResolution.Outcome.ACQUIRING, "PD half condition: same dt should still be ACQUIRING (effective reaction time doubled)")

func _test_pd_engage_recharge_takes_longer_when_degraded() -> void:
	var mount := PointDefenseMount.new()
	mount.condition = 0.5
	var ship := ShipPhysicsState.new()
	ship.position = Vector3.ZERO
	var missile := MissileState.new()
	missile.position = Vector3(0, 0, 5000.0)
	missile.guidance_state = MissileState.GuidanceState.BOOST

	# A single call with dt == the (doubled) effective reaction time reaches
	# the acquire threshold AND is_ready() (fresh mount, no cooldown yet) in
	# the same tick, so it fires immediately -- same "reaction time reached
	# this tick already fires" behavior as the acquire test above.
	var expected_effective_recharge: float = mount.effective_recharge_time_s()
	var fired := PointDefenseResolution.engage(mount, ship, missile, mount.effective_reaction_time_s())
	_assert(fired.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "PD half condition: should fire once effective reaction time is reached")
	_assert(_almost_equal(mount.cooldown_remaining_s, expected_effective_recharge), "PD half condition: cooldown after firing must be the DOUBLED effective recharge time, not the raw one")

	# The mount is now on cooldown: an immediate second engagement attempt
	# must be refused (NOT_READY) even though tracking/acquire is already
	# satisfied, and the cooldown must still reflect the doubled recharge
	# time until it actually ticks down.
	var second := PointDefenseResolution.engage(mount, ship, missile, 0.0)
	_assert(second.outcome == PointDefenseResolution.Outcome.NOT_READY, "PD half condition: an immediate second shot must be blocked by the (longer) recharge cooldown")

func _test_pd_engage_out_of_range_at_reduced_effective_range() -> void:
	var mount := PointDefenseMount.new()
	mount.condition = 0.5  # effective_engagement_range_m() = 10,000 m (half of the 20,000 m default)
	var ship := ShipPhysicsState.new()
	ship.position = Vector3.ZERO
	var missile := MissileState.new()
	missile.position = Vector3(0, 0, 15_000.0)  # inside the RAW 20,000 m range, outside the effective 10,000 m one
	missile.guidance_state = MissileState.GuidanceState.BOOST

	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(result.outcome == PointDefenseResolution.Outcome.OUT_OF_RANGE, "PD half condition: a target inside raw range but outside the shrunk effective range must be OUT_OF_RANGE")

func _test_missile_tube_effective_getters() -> void:
	var tube := MissileTube.new()
	tube.condition = 1.0
	_assert(_almost_equal(tube.effective_reload_time_s(), tube.reload_time_s), "Tube condition=1.0: effective_reload_time_s must equal raw reload_time_s")
	_assert(_almost_equal(tube.effective_max_range_m(), tube.max_range_m), "Tube condition=1.0: effective_max_range_m must equal raw max_range_m")

	tube.condition = 0.25
	_assert(_almost_equal(tube.effective_reload_time_s(), tube.reload_time_s / 0.25), "Tube condition=0.25: reload time should quadruple")
	_assert(_almost_equal(tube.effective_max_range_m(), tube.max_range_m * 0.25), "Tube condition=0.25: range should be quartered")

func _test_missile_tube_is_ready_respects_effective_reload_time() -> void:
	var tube := MissileTube.new()
	tube.condition = 0.5  # effective_reload_time_s() = 10.0 s (double the 5.0 s default)
	tube.time_since_last_launch_s = 7.0  # past the RAW reload time, not past the effective one
	_assert(not tube.is_ready(), "Tube half condition: must not be ready before the DOUBLED effective reload time has elapsed")
	tube.time_since_last_launch_s = 10.0
	_assert(tube.is_ready(), "Tube half condition: must be ready once the doubled effective reload time has elapsed")

func _test_world_sync_reflects_in_effective_getters() -> void:
	# Sanity check through the real per-tick sync path
	# (SimulationWorld._sync_subsystem_driven_conditions), same pattern as
	# test_subsystem_damage_consumers.gd, since a real cross-module bug was
	# previously only caught by a test that went through the full world
	# loop rather than calling engage()/is_ready() in isolation.
	var world := SimulationWorld.new()
	var ship := ShipPhysicsState.new()
	ship.position = Vector3.ZERO
	ship.subsystems = ShipSubsystems.new()
	ship.subsystems.get_state(SubsystemType.Type.POINT_DEFENSE).integrity = 0.4
	ship.subsystems.get_state(SubsystemType.Type.MISSILE_SYSTEMS).integrity = 0.4
	world.add_ship("s1", ship)

	var pd_mount := PointDefenseMount.new()
	world.pd_mounts["s1"] = [pd_mount]
	var tube := MissileTube.new()
	world.missile_tubes["s1"] = [tube]

	world.tick_simulation(0.1)

	_assert(_almost_equal(pd_mount.condition, 0.4), "World sync: PD mount condition should be synced from ShipSubsystems (0.4)")
	_assert(_almost_equal(pd_mount.effective_engagement_range_m(), pd_mount.max_engagement_range_m * 0.4), "World sync: PD effective range should reflect the synced 0.4 condition")
	_assert(_almost_equal(tube.condition, 0.4), "World sync: missile tube condition should be synced from ShipSubsystems (0.4)")
	_assert(_almost_equal(tube.effective_max_range_m(), tube.max_range_m * 0.4), "World sync: tube effective range should reflect the synced 0.4 condition")

func _init() -> void:
	_test_pd_effective_getters_identity_at_full_condition()
	_test_pd_effective_getters_scale_with_condition()
	_test_pd_effective_getters_floor_near_zero_condition()
	_test_pd_engage_takes_longer_to_acquire_when_degraded()
	_test_pd_engage_recharge_takes_longer_when_degraded()
	_test_pd_engage_out_of_range_at_reduced_effective_range()
	_test_missile_tube_effective_getters()
	_test_missile_tube_is_ready_respects_effective_reload_time()
	_test_world_sync_reflects_in_effective_getters()

	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		quit(1)
	else:
		quit(0)
