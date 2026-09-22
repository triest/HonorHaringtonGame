extends SceneTree
## Headless test runner for PointDefenseMount/PointDefenseResolution's
## §22.1 firing-arc restriction (a mount can now be limited to the subset
## of AttackGeometry.Sector values it can physically bear on, mirroring
## WeaponMount's existing arc model -- see point_defense_mount.gd's class
## doc comment for the full rationale and the CLOUD.md broadside/chase
## PD-count canon basis).
## Run via: godot --headless --path . --script res://simulation/tests/test_point_defense_arc.gd

const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")
const PointDefenseResolution = preload("res://simulation/point_defense_resolution.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const SimulationWorld = preload("res://simulation/simulation_world.gd")

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, message: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: ", message)

func _make_ship() -> ShipPhysicsState:
	var s := ShipPhysicsState.new()
	s.position = Vector3.ZERO
	return s

## Places a missile 15,000m from the origin (inside PointDefenseMount.max_engagement_range_m == 20,000m, comfortably outside the missile's own 5,000m self-arm-detonation threshold so the full-tick test's missile survives long enough for PD to actually engage it), in the direction that
## AttackGeometry.classify() resolves to `sector` for a ship at the
## origin with identity orientation (matches attack_geometry.gd's own
## documented axis convention: -Z=bow, +Z=stern, -X=port, +X=starboard,
## +Y=top, -Y=bottom).
func _missile_in_sector(sector) -> MissileState:
	var offset: Vector3
	match sector:
		AttackGeometry.Sector.BOW: offset = Vector3(0, 0, -15000)
		AttackGeometry.Sector.STERN: offset = Vector3(0, 0, 15000)
		AttackGeometry.Sector.PORT: offset = Vector3(-15000, 0, 0)
		AttackGeometry.Sector.STARBOARD: offset = Vector3(15000, 0, 0)
		AttackGeometry.Sector.TOP: offset = Vector3(0, 15000, 0)
		AttackGeometry.Sector.BOTTOM: offset = Vector3(0, -15000, 0)
	var m := MissileState.new()
	m.position = offset
	m.guidance_state = MissileState.GuidanceState.MIDCOURSE
	return m

func _test_default_mount_is_omnidirectional() -> void:
	# Regression: every mount constructed before this pass (empty
	# arc_sectors) must keep engaging regardless of bearing, exactly like
	# every pre-existing PD test already assumes.
	var ship := _make_ship()
	var sectors: Array = [AttackGeometry.Sector.BOW, AttackGeometry.Sector.STERN, AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD, AttackGeometry.Sector.TOP, AttackGeometry.Sector.BOTTOM]
	for sector in sectors:
		var mount := PointDefenseMount.new()
		mount.reaction_time_s = 0.0
		var missile := _missile_in_sector(sector)
		var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
		_assert(result.outcome != PointDefenseResolution.Outcome.NO_ARC, "default (empty arc_sectors) mount must never return NO_ARC, sector=%s" % AttackGeometry.sector_name(sector))
		_assert(result.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "default mount with zero reaction time should fire immediately regardless of bearing, sector=%s" % AttackGeometry.sector_name(sector))

func _test_bow_chaser_blocks_missile_outside_arc() -> void:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.arc_sectors = PointDefenseMount.bow_chaser_arc()
	mount.reaction_time_s = 0.0
	var missile := _missile_in_sector(AttackGeometry.Sector.STERN)
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(result.outcome == PointDefenseResolution.Outcome.NO_ARC, "bow-chaser-only mount must not bear on a missile approaching from STERN")

func _test_bow_chaser_allows_missile_inside_arc() -> void:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.arc_sectors = PointDefenseMount.bow_chaser_arc()
	mount.reaction_time_s = 0.0
	var missile := _missile_in_sector(AttackGeometry.Sector.BOW)
	var result := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(result.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "bow-chaser-only mount must engage a missile approaching from BOW")

func _test_broadside_arc_covers_port_and_starboard_only() -> void:
	var ship := _make_ship()
	var mount_port := PointDefenseMount.new()
	mount_port.arc_sectors = PointDefenseMount.broadside_arc()
	mount_port.reaction_time_s = 0.0
	var result_port := PointDefenseResolution.engage(mount_port, ship, _missile_in_sector(AttackGeometry.Sector.PORT), 0.1)
	_assert(result_port.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "broadside mount must bear on PORT")

	var mount_starboard := PointDefenseMount.new()
	mount_starboard.arc_sectors = PointDefenseMount.broadside_arc()
	mount_starboard.reaction_time_s = 0.0
	var result_starboard := PointDefenseResolution.engage(mount_starboard, ship, _missile_in_sector(AttackGeometry.Sector.STARBOARD), 0.1)
	_assert(result_starboard.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "broadside mount must bear on STARBOARD")

	var mount_bow := PointDefenseMount.new()
	mount_bow.arc_sectors = PointDefenseMount.broadside_arc()
	mount_bow.reaction_time_s = 0.0
	var result_bow := PointDefenseResolution.engage(mount_bow, ship, _missile_in_sector(AttackGeometry.Sector.BOW), 0.1)
	_assert(result_bow.outcome == PointDefenseResolution.Outcome.NO_ARC, "broadside mount must NOT bear on BOW")

func _test_stern_chaser_arc() -> void:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.arc_sectors = PointDefenseMount.stern_chaser_arc()
	mount.reaction_time_s = 0.0
	var hit := PointDefenseResolution.engage(mount, ship, _missile_in_sector(AttackGeometry.Sector.STERN), 0.1)
	_assert(hit.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "stern-chaser-only mount must bear on STERN")
	var miss := PointDefenseResolution.engage(mount, ship, _missile_in_sector(AttackGeometry.Sector.BOW), 0.1)
	_assert(miss.outcome == PointDefenseResolution.Outcome.NO_ARC, "stern-chaser-only mount must NOT bear on BOW")

## Same "leaving arc resets progress" contract as
## test_point_defense.gd's _test_missile_leaving_range_resets_progress --
## a mount that has already scored hits on a target must not keep that
## progress banked once its own ship turns and the target rotates out of
## the mount's arc (the ship's orientation changing, not the missile
## moving, is what flips the classified sector here).
func _test_ship_turning_out_of_arc_resets_tracking_progress() -> void:
	var ship := _make_ship()
	var mount := PointDefenseMount.new()
	mount.arc_sectors = PointDefenseMount.bow_chaser_arc()
	mount.reaction_time_s = 0.0
	mount.recharge_time_s = 0.0
	mount.hits_required_to_kill = 5
	var missile := _missile_in_sector(AttackGeometry.Sector.BOW)

	var scoring := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(scoring.outcome == PointDefenseResolution.Outcome.SHOT_FIRED, "sanity: bow-chaser should land a shot on a BOW missile before the ship turns")
	var hits_before: int = mount._hits_scored
	_assert(hits_before > 0, "sanity: at least one hit must be scored before the turn")

	# Turn the ship 180 degrees around its vertical axis: the missile,
	# still physically at the same world position, is now off the
	# mount's own STERN arc-wise (BOW no longer -- it never moved).
	ship.orientation = Quaternion(Vector3.UP, PI)
	var after_turn := PointDefenseResolution.engage(mount, ship, missile, 0.1)
	_assert(after_turn.outcome == PointDefenseResolution.Outcome.NO_ARC, "after the ship turns 180 degrees, the same missile must now read as NO_ARC for a bow-chaser mount")
	_assert(mount._hits_scored == 0, "turning out of arc must reset scored hits, exactly like leaving range does")

## End-to-end sanity through the real per-tick world loop (ТЗ project
## convention: every new combat mechanic gets at least one
## SimulationWorld.tick_simulation() test, not just isolated
## engage() calls) -- same shape as
## test_pd_missile_continuous_degradation.gd's
## _test_world_sync_reflects_in_effective_getters(), extended with a
## real active missile targeting the ship so TacticalAI.select_pd_target
## actually picks it, and sensor detection (§23) has to happen live too.
func _test_world_tick_bow_chaser_engages_bow_but_not_stern() -> void:
	var world_hit := SimulationWorld.new()
	var ship_hit := _make_ship()
	world_hit.add_ship("defender", ship_hit)
	var mount_hit := PointDefenseMount.new()
	mount_hit.arc_sectors = PointDefenseMount.bow_chaser_arc()
	mount_hit.reaction_time_s = 0.0
	world_hit.add_pd_mount("defender", mount_hit)
	var missile_hit := _missile_in_sector(AttackGeometry.Sector.BOW)
	missile_hit.target = ship_hit
	world_hit.add_missile("inbound_bow", missile_hit, "")

	var world_miss := SimulationWorld.new()
	var ship_miss := _make_ship()
	world_miss.add_ship("defender", ship_miss)
	var mount_miss := PointDefenseMount.new()
	mount_miss.arc_sectors = PointDefenseMount.bow_chaser_arc()
	mount_miss.reaction_time_s = 0.0
	world_miss.add_pd_mount("defender", mount_miss)
	var missile_miss := _missile_in_sector(AttackGeometry.Sector.STERN)
	missile_miss.target = ship_miss
	world_miss.add_missile("inbound_stern", missile_miss, "")

	# A few ticks: enough for sensor detection (DETECTED on the very
	# first in-range/emitting tick, see sensor_resolution.gd) and PD
	# reaction (reaction_time_s == 0 here) to both resolve.
	for i in range(5):
		world_hit.tick_simulation(1.0 / 60.0)
		world_miss.tick_simulation(1.0 / 60.0)

	_assert(mount_hit.cooldown_remaining_s > 0.0, "world tick: bow-chaser mount must have fired (cooldown consumed) at a real BOW-approaching missile")
	_assert(mount_miss.cooldown_remaining_s == 0.0, "world tick: bow-chaser mount must never fire at a real STERN-approaching missile (out of its arc every tick)")
	_assert(mount_miss._tracking_target == null, "world tick: bow-chaser mount must never even start tracking a STERN-approaching missile")

func _init() -> void:
	_test_default_mount_is_omnidirectional()
	_test_bow_chaser_blocks_missile_outside_arc()
	_test_bow_chaser_allows_missile_inside_arc()
	_test_broadside_arc_covers_port_and_starboard_only()
	_test_stern_chaser_arc()
	_test_ship_turning_out_of_arc_resets_tracking_progress()
	_test_world_tick_bow_chaser_engages_bow_but_not_stern()

	print("")
	print("Passed: ", _passed, " Failed: ", _failures)
	if _failures > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
