extends RefCounted
## ShipDefenseState
##
## Impeller wedge + sidewall defensive state and attack resolution
## (ТЗ §9 Impeller Wedge, §10 Wedge Orientation, §16 Sidewalls;
## CLOUD.md §2.1; CANON_RULES.md).
##
## Deliberately NOT a single shieldHP pool (ТЗ §9: "Do NOT reduce all of
## this to shieldHP."). Wedge and sidewalls are modeled as distinct systems
## with distinct geometry and failure modes, per sector.
##
## CANON basis (see CANON_RULES.md for full citations, verified against
## Honorverse Wiki 2026-09-18):
## - Wedge (TOP/BOTTOM) is CONFIRMED CANON as effectively impenetrable while
##   powered: objects entering it are destroyed.
## - Broadside (PORT/STARBOARD) sidewalls are CONFIRMED CANON as gravitic
##   distortion that ATTENUATES energy attacks; explicitly NOT invulnerable
##   ("incapable of making a ship invulnerable").
## - Bow/stern sidewalls are CONFIRMED CANON as a two-stage wall whose first
##   stage is vulnerable to acute-angle beams, which missiles can "slip
##   past" before detonating, and whose use blocks impeller acceleration
##   while raised (see integrate() gating in ShipPhysicsState).
## - Sidewall overload/burnout as a hard "generator dies, hull exposed"
##   event is INTERPRETATION (not confirmed in sources found), kept here as
##   a documented game-design choice, not presented as CANON.
class_name ShipDefenseState

const DamageType = preload("res://simulation/damage_type.gd")

## Wedge is either fully up (ship under power) or down (no propulsion / no
## impeller drive engaged). ASSUMPTION: binary for Milestone 3; wedge
## strength scaling with propulsion damage is a later refinement, tracked
## in ASSUMPTIONS.md.
var wedge_up: bool = true

## Broadside sidewall condition in [0.0, 1.0]. 1.0 = fully functional.
## INTERPRETATION: modeled as an attenuation factor + a burnout threshold,
## per CANON_RULES.md note on unverified overload mechanic.
var port_sidewall_condition: float = 1.0
var starboard_sidewall_condition: float = 1.0

## Bow/stern sidewalls are NOT always up: raising them costs the ability to
## accelerate under impeller drive (CONFIRMED CANON, see CANON_RULES.md).
## The player/AI must choose to raise them; default is down (ship free to
## maneuver) per ASSUMPTION documented in ASSUMPTIONS.md.
var bow_sidewall_raised: bool = false
var stern_sidewall_raised: bool = false
var bow_sidewall_condition: float = 1.0
var stern_sidewall_condition: float = 1.0

## ASSUMPTION (documented in ASSUMPTIONS.md): threshold below which a
## sidewall is considered burned out / non-functional. Exact canonical
## value is UNKNOWN; kept configurable rather than hardcoded per §9 intent.
const SIDEWALL_BURNOUT_THRESHOLD: float = 0.0

## ASSUMPTION: half-angle, in radians, of the bow/stern "acute angle"
## vulnerability cone described in CANON_RULES.md (missiles/beams arriving
## close to dead-ahead/dead-astern partially bypass the first-stage bow/
## stern wall). Exact canonical angle is UNKNOWN; placeholder pending
## better source data.
const BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD: float = deg_to_rad(15.0)

## ASSUMPTION (ТЗ §21.25 CANON basis, no canonical numeric factor found):
## multiplier applied to the transmitted fraction for LASERHEAD attacks
## against sidewalls specifically, reflecting "more effective at
## penetrating sidewalls than a pure fusion explosive". Result is still
## clamped to [0, 1] -- this cannot make a sidewall transmit MORE than
## 100% of an attack, only close the gap faster as condition degrades.
## KINETIC currently uses the ENERGY baseline (multiplier 1.0) since no
## kinetic-specific canon figure exists either -- see ASSUMPTIONS.md.
const LASERHEAD_SIDEWALL_PENETRATION_MULTIPLIER: float = 1.5

## ТЗ §22.1 Formation mutual defensive coverage -- first slice. ASSUMPTION
## (no canonical numeric factor found, same honest-placeholder status as
## every other bare number in this file): when a formation neighbor is
## positioned to plausibly interpose its own wedge/sidewall envelope
## along this ship's otherwise-undefended bow or stern axis (computed by
## SimulationWorld._formation_bow_stern_coverage -- this class itself
## knows nothing about formations, only receives the two resulting
## booleans, same separation of concerns as everywhere else in this
## file), the transmitted fraction of an attack that would otherwise be
## fully UNPROTECTED (no sidewall raised, or sidewall burned out) is cut
## by half rather than passing through untouched. Deliberately narrower
## than the acute-angle sidewall-bypass case below: this first slice only
## mitigates the "no functioning bow/stern wall at all" gap §22.1's own
## honest-gap paragraph names, not the separate raised-sidewall bypass
## mechanic, which stays exactly as it was pre-§22.1.
const FORMATION_COVERAGE_TRANSMITTED_FRACTION_WHEN_UNPROTECTED: float = 0.5

enum ResolutionKind {
	WEDGE_BLOCKED,       ## TOP/BOTTOM, wedge up: effectively impenetrable.
	SIDEWALL_ATTENUATED, ## PORT/STARBOARD (or raised bow/stern): reduced by sidewall condition.
	UNPROTECTED,         ## BOW/STERN with no sidewall raised, or wedge down on TOP/BOTTOM.
	FORMATION_COVERED,   ## §22.1: BOW/STERN gap with no functioning sidewall of its own, but a covering formation neighbor reduces (does not eliminate) the transmitted fraction.
}

class AttackResolution:
	var sector: AttackGeometry.Sector
	var kind: int  # ResolutionKind
	var transmitted_fraction: float  # 0.0 = fully blocked, 1.0 = full effect reaches hull

	func _init(p_sector: AttackGeometry.Sector, p_kind: int, p_fraction: float) -> void:
		sector = p_sector
		kind = p_kind
		transmitted_fraction = p_fraction

## world_attack_dir: unit vector from target to attacker is NOT required;
## caller passes attacker/target positions and target orientation, matching
## AttackGeometry.classify's signature, plus the local-space attack vector
## angle-to-axis for the bow/stern acute-angle check.
## formation_bow_covered / formation_stern_covered (ТЗ §22.1, both
## default false so every pre-existing caller/test is byte-for-byte
## unaffected): whether a formation neighbor is currently positioned to
## cover this ship's bow (resp. stern) gap this tick -- see the class doc
## on FORMATION_COVERAGE_TRANSMITTED_FRACTION_WHEN_UNPROTECTED above.
## Irrelevant to every sector other than BOW/STERN.
func resolve_attack(attacker_position: Vector3, target_position: Vector3, target_orientation: Quaternion, damage_type: int = DamageType.Type.ENERGY, formation_bow_covered: bool = false, formation_stern_covered: bool = false) -> AttackResolution:
	var sector := AttackGeometry.classify(attacker_position, target_position, target_orientation)

	match sector:
		AttackGeometry.Sector.TOP, AttackGeometry.Sector.BOTTOM:
			if wedge_up:
				return AttackResolution.new(sector, ResolutionKind.WEDGE_BLOCKED, 0.0)
			return AttackResolution.new(sector, ResolutionKind.UNPROTECTED, 1.0)

		AttackGeometry.Sector.PORT:
			return _resolve_broadside(sector, port_sidewall_condition, damage_type)
		AttackGeometry.Sector.STARBOARD:
			return _resolve_broadside(sector, starboard_sidewall_condition, damage_type)

		AttackGeometry.Sector.BOW:
			return _resolve_bow_stern(sector, attacker_position, target_position, target_orientation, bow_sidewall_raised, bow_sidewall_condition, true, damage_type, formation_bow_covered)
		AttackGeometry.Sector.STERN:
			return _resolve_bow_stern(sector, attacker_position, target_position, target_orientation, stern_sidewall_raised, stern_sidewall_condition, false, damage_type, formation_stern_covered)

	return AttackResolution.new(sector, ResolutionKind.UNPROTECTED, 1.0)

## ТЗ §21.25 CANON: laserhead penetrates sidewalls better than a plain
## explosive/kinetic warhead of equivalent yield. Modeled as a multiplier
## on the transmitted fraction, clamped to [0,1] so it can only narrow the
## gap, never exceed "fully through".
func _penetration_multiplier(damage_type: int) -> float:
	if damage_type == DamageType.Type.LASERHEAD:
		return LASERHEAD_SIDEWALL_PENETRATION_MULTIPLIER
	return 1.0

func _resolve_broadside(sector: AttackGeometry.Sector, condition: float, damage_type: int) -> AttackResolution:
	if condition <= SIDEWALL_BURNOUT_THRESHOLD:
		return AttackResolution.new(sector, ResolutionKind.UNPROTECTED, 1.0)
	# Linear attenuation by remaining condition (ASSUMPTION: exact curve is
	# UNKNOWN/not canonical; documented in ASSUMPTIONS.md), scaled by the
	# attacker's damage-type penetration multiplier.
	var transmitted: float = clampf((1.0 - condition) * _penetration_multiplier(damage_type), 0.0, 1.0)
	return AttackResolution.new(sector, ResolutionKind.SIDEWALL_ATTENUATED, transmitted)

func _resolve_bow_stern(sector: AttackGeometry.Sector, attacker_position: Vector3, target_position: Vector3, target_orientation: Quaternion, raised: bool, condition: float, is_bow: bool, damage_type: int, formation_covered: bool = false) -> AttackResolution:
	if not raised or condition <= SIDEWALL_BURNOUT_THRESHOLD:
		# §22.1: no functioning sidewall of this ship's own on this axis at
		# all -- if a formation neighbor is covering the gap, mitigate it
		# (still worse than a raised sidewall would be); otherwise unchanged
		# pre-§22.1 behavior.
		if formation_covered:
			var covered_fraction: float = clampf(FORMATION_COVERAGE_TRANSMITTED_FRACTION_WHEN_UNPROTECTED * _penetration_multiplier(damage_type), 0.0, 1.0)
			return AttackResolution.new(sector, ResolutionKind.FORMATION_COVERED, covered_fraction)
		return AttackResolution.new(sector, ResolutionKind.UNPROTECTED, 1.0)

	# CANON: first-stage bow/stern wall is vulnerable to acute-angle beams
	# and can be "slipped past" by missiles near the ship's own axis
	# (CANON_RULES.md). Model: an attack whose local direction is within
	# BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD of the ship's own bow/stern axis
	# bypasses most of the wall's protection.
	var world_dir: Vector3 = (attacker_position - target_position)
	if world_dir.length_squared() <= 0.0:
		world_dir = Vector3.FORWARD
	world_dir = world_dir.normalized()
	var local_dir: Vector3 = target_orientation.inverse() * world_dir
	var axis: Vector3 = Vector3(0, 0, -1) if is_bow else Vector3(0, 0, 1)
	var angle_from_axis: float = local_dir.angle_to(axis)

	if angle_from_axis <= BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD:
		# Near dead-ahead/dead-astern: wall mostly bypassed (ASSUMPTION:
		# not a canonical numeric fraction, placeholder pending better data).
		var bypass_fraction: float = clampf(0.6 * _penetration_multiplier(damage_type), 0.0, 1.0)
		return AttackResolution.new(sector, ResolutionKind.SIDEWALL_ATTENUATED, bypass_fraction)

	var transmitted: float = clampf((1.0 - condition) * _penetration_multiplier(damage_type), 0.0, 1.0)
	return AttackResolution.new(sector, ResolutionKind.SIDEWALL_ATTENUATED, transmitted)
