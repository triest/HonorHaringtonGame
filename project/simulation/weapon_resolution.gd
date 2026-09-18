extends RefCounted
## WeaponResolution
##
## Ties together geometry (AttackGeometry), defense (ShipDefenseState),
## and a WeaponMount to resolve one shot (ТЗ §17 Weapons).
##
## Deliberately a static utility, not a node: keeps combat resolution in
## "Simulation" per §42, independent of rendering/UI/timers.
class_name WeaponResolution

const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")

enum Outcome { OUT_OF_RANGE, NOT_READY, NO_ARC, WEDGE_BLOCKED, SIDEWALL_ATTENUATED, HIT_UNPROTECTED }

class ShotResult:
	var outcome: int
	var damage_dealt: float = 0.0
	var target_sector  # AttackGeometry.Sector, if the shot got far enough to be classified

	func _init(p_outcome: int, p_damage: float = 0.0, p_sector = null) -> void:
		outcome = p_outcome
		damage_dealt = p_damage
		target_sector = p_sector

## attacker_ship / target_ship: ShipPhysicsState. mount: WeaponMount owned by
## attacker_ship. target_defense: target_ship.defense (may be null).
## target_hull: HullState to apply damage to, if the shot penetrates.
static func fire(attacker_ship, mount, target_ship, target_hull) -> ShotResult:
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
		return ShotResult.new(Outcome.HIT_UNPROTECTED, full_damage)

	var resolution = defense.resolve_attack(attacker_ship.position, target_ship.position, target_ship.orientation, ShipDefenseState.DamageType.Type.ENERGY)
	var damage: float = mount.weapon.damage_per_hit * mount.condition * resolution.transmitted_fraction

	if damage > 0.0 and target_hull != null:
		target_hull.apply_damage(damage)

	var outcome: int = Outcome.HIT_UNPROTECTED
	if resolution.kind == ShipDefenseState.ResolutionKind.WEDGE_BLOCKED:
		outcome = Outcome.WEDGE_BLOCKED
	elif resolution.kind == ShipDefenseState.ResolutionKind.SIDEWALL_ATTENUATED:
		outcome = Outcome.SIDEWALL_ATTENUATED

	return ShotResult.new(outcome, damage, resolution.sector)
