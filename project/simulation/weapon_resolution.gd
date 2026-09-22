extends RefCounted
## WeaponResolution
##
## Ties together geometry (AttackGeometry), defense (ShipDefenseState),
## and a WeaponMount to resolve one shot (ТЗ §17 Weapons).
##
## Deliberately a static utility, not a node: keeps combat resolution in
## "Simulation" per §42, independent of rendering/UI/timers.
##
## ТЗ §25 Damage: optional `target_subsystems` (the TARGET's
## ShipSubsystems) lets a penetrating hit also degrade a subsystem via
## SubsystemDamageResolution, using the same `resolution.sector` already
## computed for wedge/sidewall purposes. Omitting it (the default) keeps
## pre-§25 behavior (hull damage only) -- every existing caller/test is
## unaffected.
class_name WeaponResolution

const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const SubsystemDamageResolution = preload("res://simulation/subsystem_damage_resolution.gd")

enum Outcome { OUT_OF_RANGE, NOT_READY, NO_ARC, WEDGE_BLOCKED, SIDEWALL_ATTENUATED, FORMATION_COVERED, HIT_UNPROTECTED }

class ShotResult:
	var outcome: int
	var damage_dealt: float = 0.0
	var target_sector  # AttackGeometry.Sector, if the shot got far enough to be classified
	var subsystem_damage: Dictionary = {}  # SubsystemType.Type -> condition_loss, if target_subsystems was passed

	func _init(p_outcome: int, p_damage: float = 0.0, p_sector = null, p_subsystem_damage: Dictionary = {}) -> void:
		outcome = p_outcome
		damage_dealt = p_damage
		target_sector = p_sector
		subsystem_damage = p_subsystem_damage

## attacker_ship / target_ship: ShipPhysicsState. mount: WeaponMount owned by
## attacker_ship. target_defense: target_ship.defense (may be null).
## target_hull: HullState to apply damage to, if the shot penetrates.
## target_subsystems: optional ShipSubsystems (ТЗ §25) belonging to
## target_ship; when provided, a penetrating hit also degrades a
## sector-appropriate subsystem (see SubsystemDamageResolution).
## target_formation_coverage: optional Dictionary (ТЗ §22.1, computed by
## SimulationWorld._formation_bow_stern_coverage) with "bow"/"stern" bool
## keys -- whether a formation neighbor currently covers target_ship's
## bow/stern gap this tick. Missing keys default to false, so every
## pre-existing caller/test (which never passes this) is unaffected.
static func fire(attacker_ship, mount, target_ship, target_hull, target_subsystems = null, target_formation_coverage: Dictionary = {}) -> ShotResult:
	if mount == null or mount.weapon == null:
		return ShotResult.new(Outcome.NOT_READY)

	if not mount.is_ready():
		return ShotResult.new(Outcome.NOT_READY)

	var distance: float = attacker_ship.distance_to(target_ship)
	if distance > mount.weapon.max_range_m:
		return ShotResult.new(Outcome.OUT_OF_RANGE)

	# Arc check: which sector, in the ATTACKER's own frame, does the target
	# occupy? The mount must be able to bear on that sector.
	var firing_sector = AttackGeometry.classify(target_ship.position, attacker_ship.position, attacker_ship.orientation)
	if not mount.can_bear_on(firing_sector):
		return ShotResult.new(Outcome.NO_ARC)

	# The shot is fired: consume the recharge cycle regardless of whether it
	# penetrates (CLOUD.md §2.2: "limited by weapon charging cycles").
	mount.trigger_cooldown()

	# Defense check: which sector, in the TARGET's own frame, does the
	# attacker occupy? That determines wedge/sidewall interaction (§9, §10).
	var defense = target_ship.defense
	if defense == null:
		var full_damage: float = mount.weapon.damage_per_hit * mount.condition
		if target_hull != null:
			target_hull.apply_damage(full_damage)
		var sub_damage: Dictionary = SubsystemDamageResolution.apply_hit(target_subsystems, full_damage, null)
		return ShotResult.new(Outcome.HIT_UNPROTECTED, full_damage, null, sub_damage)

	var resolution = defense.resolve_attack(attacker_ship.position, target_ship.position, target_ship.orientation, ShipDefenseState.DamageType.Type.ENERGY, target_formation_coverage.get("bow", false), target_formation_coverage.get("stern", false))
	var damage: float = mount.weapon.damage_per_hit * mount.condition * resolution.transmitted_fraction

	if damage > 0.0 and target_hull != null:
		target_hull.apply_damage(damage)

	var outcome: int = Outcome.HIT_UNPROTECTED
	if resolution.kind == ShipDefenseState.ResolutionKind.WEDGE_BLOCKED:
		outcome = Outcome.WEDGE_BLOCKED
	elif resolution.kind == ShipDefenseState.ResolutionKind.SIDEWALL_ATTENUATED:
		outcome = Outcome.SIDEWALL_ATTENUATED
	elif resolution.kind == ShipDefenseState.ResolutionKind.FORMATION_COVERED:
		outcome = Outcome.FORMATION_COVERED

	var sub_damage: Dictionary = SubsystemDamageResolution.apply_hit(target_subsystems, damage, resolution.sector)
	return ShotResult.new(outcome, damage, resolution.sector, sub_damage)
