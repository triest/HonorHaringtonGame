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
## 2026-09-27 (user: "drop the HP bar, do module damage as the spec
## says"): OPT-IN spread model. With `spread_rng` set (the demo scenario
## seeds one, so runs stay deterministic -- §43), each hit/rod picks the
## module it wrecks from a weighted table for the struck aspect instead
## of always the same one module per side (old table: every port hit ->
## WEAPONS, every starboard hit -> POINT_DEFENSE). Broadside hits land in
## what lives along the broadside (mounts, tubes, PD clusters, sidewall
## generators, power runs); bow hits -> maneuvering/sensors/chasers;
## stern -> impeller nodes/power; top/bottom (rare: wedge) -> sensors,
## comms. ASSUMPTION (weights are not canon figures). Default null = the
## old fixed table, so every existing test is unaffected.
static var spread_rng: RandomNumberGenerator = null
## Opt-in override of STRUCTURAL_SHARE (-1 = use the constant). The demo
## lowers it so ships lose weapons/sensors/drive BEFORE they break up --
## capability loss first, destruction last.
static var structural_share_override: float = -1.0
## One laserhead = one wound: all rods of a single detonation land in the
## same module (picked on the first rod), so a hit reads as "the missile
## tubes were hit", not six scratches spread over six systems.
static var _sticky_active: bool = false
static var _sticky_type: int = -1
static func begin_sticky() -> void:
	_sticky_active = true
	_sticky_type = -1
static func end_sticky() -> void:
	_sticky_active = false
	_sticky_type = -1
const _T := SubsystemType.Type
static func _spread_table(sector) -> Array:
	match sector:
		AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD:
			return [[_T.WEAPONS, 3.0], [_T.MISSILE_SYSTEMS, 3.0], [_T.POINT_DEFENSE, 2.0], [_T.COUNTER_MISSILE_SYSTEMS, 1.0], [_T.DEFENSIVE_SYSTEMS, 2.5], [_T.POWER, 1.0], [_T.SENSORS, 1.0], [_T.COMMUNICATIONS, 0.7]]
		AttackGeometry.Sector.BOW:
			return [[_T.MANEUVERING, 3.0], [_T.SENSORS, 2.0], [_T.WEAPONS, 1.5], [_T.COMMUNICATIONS, 1.0], [_T.POWER, 0.7]]
		AttackGeometry.Sector.STERN:
			return [[_T.PROPULSION, 4.0], [_T.POWER, 2.0], [_T.MANEUVERING, 1.0]]
		AttackGeometry.Sector.TOP, AttackGeometry.Sector.BOTTOM:
			return [[_T.SENSORS, 2.0], [_T.COMMUNICATIONS, 2.0], [_T.PROPULSION, 1.0]]
	return [[_T.STRUCTURAL_INTEGRITY, 1.0]]

static func _spread_pick(sector) -> int:
	var table: Array = _spread_table(sector)
	var total: float = 0.0
	for e in table:
		total += e[1]
	var r: float = spread_rng.randf() * total
	for e in table:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return table[table.size() - 1][0]

static func apply_hit(subsystems, damage_amount: float, sector) -> Dictionary:
	if subsystems == null or damage_amount <= 0.0:
		return {}

	var condition_loss: float = damage_amount * CONDITION_LOSS_PER_DAMAGE
	var applied: Dictionary = {}

	var primary_type = SECTOR_PRIMARY_SUBSYSTEM.get(sector, SubsystemType.Type.STRUCTURAL_INTEGRITY)
	if spread_rng != null:
		if _sticky_active and _sticky_type >= 0:
			primary_type = _sticky_type
		else:
			primary_type = _spread_pick(sector)
			if _sticky_active:
				_sticky_type = primary_type
	subsystems.apply_damage(primary_type, condition_loss)
	applied[primary_type] = condition_loss

	if primary_type != SubsystemType.Type.STRUCTURAL_INTEGRITY:
		var structural_loss: float = condition_loss * (structural_share_override if structural_share_override >= 0.0 else STRUCTURAL_SHARE)
		subsystems.apply_damage(SubsystemType.Type.STRUCTURAL_INTEGRITY, structural_loss)
		applied[SubsystemType.Type.STRUCTURAL_INTEGRITY] = structural_loss

	return applied
