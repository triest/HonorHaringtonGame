extends RefCounted
## MissileResolution
##
## Applies a missile's laserhead detonation to its target (ТЗ AGENTS.md
## §21 Laserheads). As of this pass, this models the CANON detonation
## sequence (§21.1, verified against Honorverse Wiki 2026-09-18):
##
##   missile reaches terminal bearing
##   -> `rod_count` lasing rods eject and each maneuvers to its own
##      position ~`rod_offset_m` ahead of the warhead
##   -> each rod is resolved as an INDEPENDENT attack against the target's
##      wedge/sidewalls (own call to ShipDefenseState.resolve_attack, own
##      position) rather than one single ray from the missile's own
##      position.
##
## INTERPRETATION / scope limits, honestly documented rather than silently
## assumed (§21.4 lists related UNKNOWNs):
## - This implements the Mark-23-style "FOCUSED" warhead: all rods aim at
##   the SAME target and are damage-summed. The Mark-13-style
##   "independently targetable submunition" warhead (§21.2), where
##   different rods can strike DIFFERENT targets, is NOT implemented here
##   -- MissileState only carries a single `target`. That is a separate,
##   larger feature (multi-target submunition dispersal) left as a
##   documented TODO, not invented.
## - The per-rod angular spread (`rod_spread_half_angle_rad`) is an
##   ASSUMPTION, not a canonical figure (see missile_state.gd/ASSUMPTIONS.md).
##   Because rod_offset_m (~100m) is tiny next to realistic engagement
##   distances (km+), the rods will in practice almost always classify
##   into the SAME AttackGeometry sector as each other -- this is
##   consistent with canon (one Gaussian pulse, one general attack
##   direction) rather than a bug; the independent resolution exists so
##   per-rod damage/outcome is real, auditable simulation state, not a
##   hidden multiplier.
class_name MissileResolution

const ShipDefenseState = preload("res://simulation/ship_defense_state.gd")
const MissileState = preload("res://simulation/missile_state.gd")
const LasingRod = preload("res://simulation/lasing_rod.gd")
const DamageType = preload("res://simulation/damage_type.gd")

enum Outcome { NOT_ARMED, ALREADY_DETONATED, NO_TARGET, WEDGE_BLOCKED, SIDEWALL_ATTENUATED, HIT_UNPROTECTED }

class RodResult:
	var sector
	var outcome: int
	var damage: float

	func _init(p_sector, p_outcome: int, p_damage: float) -> void:
		sector = p_sector
		outcome = p_outcome
		damage = p_damage

class DetonationResult:
	var outcome: int
	var damage_dealt: float = 0.0
	var rod_results: Array = []  # Array[RodResult]

	func _init(p_outcome: int, p_damage: float = 0.0, p_rod_results: Array = []) -> void:
		outcome = p_outcome
		damage_dealt = p_damage
		rod_results = p_rod_results

## Computes the world-space positions the missile's lasing rods take up at
## detonation: a fan of `missile.rod_count` points, each `rod_offset_m`
## ahead of the warhead along the boresight to the target, spread within a
## cone of `rod_spread_half_angle_rad` (§21.1/§21.2). Pure function, easy
## to unit test independent of ShipDefenseState.
static func compute_rod_positions(missile) -> Array:
	var target = missile.target
	if target == null:
		return []

	var boresight: Vector3 = (target.position - missile.position)
	if boresight.length_squared() <= 0.0:
		boresight = Vector3.FORWARD
	else:
		boresight = boresight.normalized()

	var reference: Vector3 = Vector3.UP
	if absf(boresight.dot(Vector3.UP)) > 0.999:
		reference = Vector3.RIGHT

	var perpendicular: Vector3 = boresight.cross(reference).normalized()

	var positions: Array = []
	var count: int = maxi(1, missile.rod_count)
	for i in range(count):
		var spin_angle: float = TAU * float(i) / float(count)
		var spread_axis: Vector3 = perpendicular.rotated(boresight, spin_angle)
		var rod_dir: Vector3 = boresight.rotated(spread_axis, missile.rod_spread_half_angle_rad)
		positions.append(missile.position + rod_dir * missile.rod_offset_m)

	return positions

## Call once, when missile.warhead_armed is true and it should detonate
## this tick. target_hull: HullState to damage (may be null to skip
## damage application, e.g. for a dry-run check).
static func resolve_detonation(missile, target_hull) -> DetonationResult:
	if missile.has_detonated:
		return DetonationResult.new(Outcome.ALREADY_DETONATED)
	if not missile.warhead_armed:
		return DetonationResult.new(Outcome.NOT_ARMED)
	if missile.target == null:
		return DetonationResult.new(Outcome.NO_TARGET)

	missile.has_detonated = true
	missile.guidance_state = MissileState.GuidanceState.DETONATED

	var target = missile.target
	var rod_positions: Array = compute_rod_positions(missile)
	var damage_per_rod: float = missile.laserhead_damage / float(rod_positions.size())

	var defense = target.defense
	var rod_results: Array = []
	var total_damage: float = 0.0
	var any_unprotected: bool = false
	var any_attenuated: bool = false

	for rod_position in rod_positions:
		if defense == null:
			rod_results.append(RodResult.new(null, Outcome.HIT_UNPROTECTED, damage_per_rod))
			total_damage += damage_per_rod
			any_unprotected = true
			continue

		# ТЗ §21.25 CANON: laserhead penetrates sidewalls more effectively than
		# a plain explosive/kinetic warhead -- pass LASERHEAD so
		# ShipDefenseState applies its penetration multiplier.
		var resolution = defense.resolve_attack(rod_position, target.position, target.orientation, DamageType.Type.LASERHEAD)
		var rod_damage: float = damage_per_rod * resolution.transmitted_fraction
		total_damage += rod_damage

		var rod_outcome: int = Outcome.HIT_UNPROTECTED
		if resolution.kind == ShipDefenseState.ResolutionKind.WEDGE_BLOCKED:
			rod_outcome = Outcome.WEDGE_BLOCKED
		elif resolution.kind == ShipDefenseState.ResolutionKind.SIDEWALL_ATTENUATED:
			rod_outcome = Outcome.SIDEWALL_ATTENUATED
			any_attenuated = true
		else:
			any_unprotected = true

		rod_results.append(RodResult.new(resolution.sector, rod_outcome, rod_damage))

	if total_damage > 0.0 and target_hull != null:
		target_hull.apply_damage(total_damage)

	var overall_outcome: int = Outcome.WEDGE_BLOCKED
	if any_unprotected:
		overall_outcome = Outcome.HIT_UNPROTECTED
	elif any_attenuated:
		overall_outcome = Outcome.SIDEWALL_ATTENUATED

	return DetonationResult.new(overall_outcome, total_damage, rod_results)
