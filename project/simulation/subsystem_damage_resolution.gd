extends RefCounted
## SubsystemDamageResolution
##
## ТЗ §25 Damage: "Damage must be subsystem based... subsystem damage must
## change actual ship capabilities." This module decides WHICH subsystem(s)
## take condition damage when a hit lands, given the ATTACK SECTOR
## (AttackGeometry.Sector, already computed by WeaponResolution/
## MissileResolution for wedge/sidewall purposes) and the raw damage that
## got through.
##
## INTERPRETATION, not canon: no source found (book or wiki) specifying
## which physical subsystem sits behind which hull sector on a Honorverse
## warship. The sector -> subsystem mapping below is an ENGINEERING
## GUESS chosen for internal plausibility with earlier, already-documented
## interpretations in this codebase (hull_mesh_builder.gd's "hammerhead"
## bow/stern flares as likely drive/maneuvering machinery locations;
## broadside weapon arcs per weapon_mount.gd's `broadside_arc()`), NOT a
## citation. It is deliberately deterministic (ТЗ §43 forbids unseeded
## RNG) rather than a random subsystem pick.
##
## `STRUCTURAL_INTEGRITY` always takes a (smaller) share of every hit
## regardless of sector, since any penetrating hit stresses the hull
## generally, not just the specific system nearest the impact point.
class_name SubsystemDamageResolution

const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")

## ASSUMPTION mapping, see class doc. AttackGeometry.Sector -> the PRIMARY
## SubsystemType.Type most likely struck by a hit arriving from that
## direction (in the TARGET's own frame -- i.e. resolution.sector from
## WeaponResolution/MissileResolution, which already reports where the
## ATTACKER was relative to the TARGET's orientation).
const SECTOR_PRIMARY_SUBSYSTEM: Dictionary = {
	AttackGeometry.Sector.TOP: SubsystemType.Type.SENSORS,
	AttackGeometry.Sector.BOTTOM: SubsystemType.Type.COMMUNICATIONS,
	AttackGeometry.Sector.BOW: SubsystemType.Type.MANEUVERING,
	AttackGeometry.Sector.STERN: SubsystemType.Type.PROPULSION,
	AttackGeometry.Sector.PORT: SubsystemType.Type.WEAPONS,
	AttackGeometry.Sector.STARBOARD: SubsystemType.Type.POINT_DEFENSE,
}

## ASSUMPTION: no canonical figure for how much raw (hull-scale) damage it
## takes to knock out a subsystem. Chosen so a handful of solid hits with
## typical `WeaponData.damage_per_hit` (~100, see weapon_data.gd default)
## meaningfully erode a subsystem without a single grazing hit disabling
## it outright.
const CONDITION_LOSS_PER_DAMAGE: float = 1.0 / 2000.0

## Structural integrity's share of every hit, regardless of sector
## (ASSUMPTION: any penetrating hit stresses the hull generally).
const STRUCTURAL_SHARE: float = 0.5

## Applies condition damage to `subsystems` (a ShipSubsystems) for one hit
## of `damage_amount` (post-wedge/sidewall, i.e. what actually penetrated)
## arriving from `sector` (an AttackGeometry.Sector, or null if the hit
## could not be classified -- e.g. no defense state on the target). Returns
## a Dictionary {SubsystemType.Type: condition_loss_applied} for
## inspection/testing. No-ops (returns {}) if `subsystems` is null or
## damage_amount <= 0 -- callers that don't pass a ShipSubsystems (the
## default, for backward compatibility) get no subsystem damage at all,
## same as before this module existed.
static func apply_hit(subsystems, damage_amount: float, sector) -> Dictionary:
	if subsystems == null or damage_amount <= 0.0:
		return {}

	var condition_loss: float = damage_amount * CONDITION_LOSS_PER_DAMAGE
	var applied: Dictionary = {}

	var primary_type = SECTOR_PRIMARY_SUBSYSTEM.get(sector, SubsystemType.Type.STRUCTURAL_INTEGRITY)
	subsystems.apply_damage(primary_type, condition_loss)
	applied[primary_type] = condition_loss

	if primary_type != SubsystemType.Type.STRUCTURAL_INTEGRITY:
		var structural_loss: float = condition_loss * STRUCTURAL_SHARE
		subsystems.apply_damage(SubsystemType.Type.STRUCTURAL_INTEGRITY, structural_loss)
		applied[SubsystemType.Type.STRUCTURAL_INTEGRITY] = structural_loss

	return applied
