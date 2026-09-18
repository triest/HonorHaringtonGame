extends RefCounted
## WeaponMount
##
## A physical weapon mount on a ship: a WeaponData instance plus its firing
## arc and current cooldown (ТЗ §17: "Weapon resolution must consider:
## range; relative geometry; target orientation; wedge; sidewalls...").
##
## Firing arc is expressed as the set of AttackGeometry.Sector values, IN
## THE MOUNTING SHIP'S OWN LOCAL FRAME, from which the mount can bear on a
## target. This models CLOUD.md §2.2: "Energy Weapon Mounts: Lasers and
## Graser mounts located along the ship's broadside and chaser zones,
## limited by... exact firing arcs."
##
## ASSUMPTION: arcs are modeled at the coarse 6-sector granularity already
## used for defense (not a continuous firing cone). This is a documented
## simplification (ASSUMPTIONS.md) — sufficient for Milestone 4, revisit if
## finer-grained arcs are needed later.
class_name WeaponMount

const AttackGeometry = preload("res://simulation/attack_geometry.gd")

## Broadside mount: can fire to port or starboard of the mounting ship.
static func broadside_arc() -> Array:
	return [AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD]

## Chaser mount: can fire straight ahead (bow) only.
static func bow_chaser_arc() -> Array:
	return [AttackGeometry.Sector.BOW]

## Chaser mount: can fire straight astern (stern) only.
static func stern_chaser_arc() -> Array:
	return [AttackGeometry.Sector.STERN]

var weapon: WeaponData
var arc_sectors: Array = []  # Array[AttackGeometry.Sector]
var cooldown_remaining_s: float = 0.0
var condition: float = 1.0  # 1.0 = fully functional; synced each tick from the
                                  # mounting ship's own WEAPONS subsystem condition by
                                  # SimulationWorld._sync_subsystem_driven_conditions() (§25).

func _init(p_weapon: WeaponData = null, p_arc: Array = []) -> void:
	weapon = p_weapon
	arc_sectors = p_arc

func is_ready() -> bool:
	return cooldown_remaining_s <= 0.0 and condition > 0.0

## Call once per fixed simulation tick to advance cooldown.
func tick(dt: float) -> void:
	if cooldown_remaining_s > 0.0:
		cooldown_remaining_s = maxf(0.0, cooldown_remaining_s - dt)

func trigger_cooldown() -> void:
	cooldown_remaining_s = weapon.recharge_time_s if weapon != null else 0.0

func can_bear_on(sector) -> bool:
	return arc_sectors.has(sector)
