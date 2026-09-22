extends RefCounted
## ShipFactory
##
## Builds a live, fully-armed ship inside a SimulationWorld from a
## data-driven ShipClassData record (ТЗ §8 Ship Database, §48 Data-Driven
## Design). This is the first code path that constructs a ship's physics
## state, hull, energy mounts, missile tubes, and point-defense batteries
## from DATA rather than a test/scenario hand-assembling each piece --
## closing the "none of §8.1/§8.2/§8.3 is wired into project/simulation
## yet" HONEST GAP recorded in AGENTS.md, and the ship-loadout half of the
## PD-arc gap recorded when point_defense_resolution.gd's arc model was
## added ("no existing scenario/ship loadout assigns a real positional
## PD-battery yet").
##
## Intended for both direct use by tests/scenarios and, later, by the
## Milestone 13 scenario loader (ТЗ §46) -- a scenario is expected to
## reference a ShipClassData resource path plus spawn transform, not
## reconstruct a ship's internals inline.
class_name ShipFactory

const ShipPhysicsState = preload("res://simulation/ship_physics_state.gd")
const HullState = preload("res://simulation/hull_state.gd")
const ShipSubsystems = preload("res://simulation/ship_subsystems.gd")
const WeaponData = preload("res://simulation/weapon_data.gd")
const WeaponMount = preload("res://simulation/weapon_mount.gd")
const MissileTube = preload("res://simulation/missile_tube.gd")
const PointDefenseMount = preload("res://simulation/point_defense_mount.gd")

## Standard gravity, m/s^2 -- ТЗ §8.1's canon acceleration figures are
## given in G; the simulation core works in m/s^2 (ShipPhysicsState doc
## comment, ТЗ §62.1). Same constant CLOUD.md/AGENTS.md use elsewhere for
## G-based figures.
const STANDARD_GRAVITY_MPS2: float = 9.80665

## Spawns `class_data` into `world` as `ship_id`, fully armed, and returns
## the new ShipPhysicsState (also already registered via world.add_ship()).
## `with_subsystems` attaches a full ShipSubsystems container (ТЗ §25) so
## the spawned ship participates in per-subsystem damage degradation like
## any other §25-aware ship; default true since this is the richer,
## spec-complete option and every mount/tube this factory attaches already
## has its own `condition` field synced from subsystem state each tick
## (SimulationWorld._sync_subsystem_driven_conditions()).
static func spawn_ship(world, ship_id: String, class_data: ShipClassData, position: Vector3, velocity: Vector3 = Vector3.ZERO, orientation: Quaternion = Quaternion.IDENTITY, team: String = "", with_subsystems: bool = true) -> ShipPhysicsState:
	assert(class_data.is_valid(), "ShipClassData for '%s' is missing canonical_name/mass_kg/source_note" % ship_id)

	var state := ShipPhysicsState.new()
	state.position = position
	state.velocity = velocity
	state.orientation = orientation
	state.mass_kg = class_data.mass_kg
	var rated_accel_mps2: float = class_data.rated_acceleration_g * STANDARD_GRAVITY_MPS2
	state.max_thrust_n = rated_accel_mps2 * class_data.mass_kg
	state.max_angular_speed_rad_s = class_data.max_angular_speed_rad_s
	state.length_m = class_data.length_m
	state.max_width_m = class_data.max_width_m
	state.max_height_m = class_data.max_height_m
	if with_subsystems:
		state.subsystems = ShipSubsystems.new()

	# HullState.max_integrity stays the existing flat ASSUMPTION placeholder
	# (10,000, see hull_state.gd) rather than a new per-class scaling
	# formula invented for this pass -- no canonical hull-point figure
	# exists for any class to anchor such a formula against (ТЗ §8.4 step
	# 7: "widen to UNKNOWN ... rather than manufacturing false precision").
	# See ASSUMPTIONS.md for this open gap.
	var hull := HullState.new()

	world.add_ship(ship_id, state, hull)
	if team != "":
		world.set_team(ship_id, team)

	var laser_data := WeaponData.new()
	laser_data.id = "%s_laser" % class_data.canonical_name
	laser_data.display_name = "%s Laser" % class_data.canonical_name
	laser_data.weapon_class = WeaponData.WeaponClass.ENERGY_LASER

	var graser_data := WeaponData.new()
	graser_data.id = "%s_graser" % class_data.canonical_name
	graser_data.display_name = "%s Graser" % class_data.canonical_name
	graser_data.weapon_class = WeaponData.WeaponClass.ENERGY_GRASER

	_add_energy_mounts(world, ship_id, laser_data, WeaponMount.broadside_arc(), class_data.broadside_laser_mounts)
	_add_energy_mounts(world, ship_id, graser_data, WeaponMount.broadside_arc(), class_data.broadside_graser_mounts)
	_add_energy_mounts(world, ship_id, laser_data, WeaponMount.bow_chaser_arc(), class_data.fore_laser_mounts)
	_add_energy_mounts(world, ship_id, graser_data, WeaponMount.bow_chaser_arc(), class_data.fore_graser_mounts)
	_add_energy_mounts(world, ship_id, laser_data, WeaponMount.stern_chaser_arc(), class_data.aft_laser_mounts)
	_add_energy_mounts(world, ship_id, graser_data, WeaponMount.stern_chaser_arc(), class_data.aft_graser_mounts)

	var total_tubes: int = class_data.broadside_missile_tubes + class_data.fore_missile_tubes + class_data.aft_missile_tubes
	if total_tubes > 0:
		# ASSUMPTION: total magazine capacity divided evenly across all
		# spawned tubes (per-tube arc is not modeled, see ShipClassData doc
		# comment) -- integer division, any remainder dropped rather than
		# invented back in.
		var ammo_per_tube: int = int(class_data.missile_magazine_total / float(total_tubes))
		for i in range(total_tubes):
			var tube := MissileTube.new()
			if ammo_per_tube > 0:
				tube.ammo_count = ammo_per_tube
			world.add_missile_tube(ship_id, tube)

	_add_pd_mounts(world, ship_id, PointDefenseMount.broadside_arc(), class_data.broadside_pd_mounts)
	_add_pd_mounts(world, ship_id, PointDefenseMount.bow_chaser_arc(), class_data.fore_pd_mounts)
	_add_pd_mounts(world, ship_id, PointDefenseMount.stern_chaser_arc(), class_data.aft_pd_mounts)

	return state

static func _add_energy_mounts(world, ship_id: String, weapon: WeaponData, arc: Array, count: int) -> void:
	for i in range(count):
		world.add_weapon_mount(ship_id, WeaponMount.new(weapon, arc))

static func _add_pd_mounts(world, ship_id: String, arc: Array, count: int) -> void:
	for i in range(count):
		var mount := PointDefenseMount.new()
		mount.arc_sectors = arc
		world.add_pd_mount(ship_id, mount)
