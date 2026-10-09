extends RefCounted
## ImpactRecord
##
## Builds the plain-data "impact record" the simulation publishes for every
## missile laserhead detonation (SimulationWorld.last_tick_impacts), so the
## render layer can show WHERE a strike landed, WHAT the defence did and
## WHAT it cost -- without ever touching live simulation objects (ТЗ §42:
## rendering only displays already-resolved state).
##
## The record is a snapshot: every value is a copied primitive / Vector3 /
## Quaternion / Array of Dictionaries. Nothing in it references a
## ShipPhysicsState, HullState or MissileState, so a renderer physically
## cannot mutate simulation state through it. Building it consumes no RNG and
## changes no simulation state, so it cannot affect determinism (ТЗ §43).
##
## Two producers share one layout: laserhead detonations (kind "missile",
## several rods) and energy-beam shots (kind "beam", exactly one "rod" whose
## position is the attacker). Rod outcomes always use MissileResolution.Outcome
## numbering; beam outcomes are mapped by beam_outcome_to_rod_outcome().
##
## Record layout (all keys always present):
##   kind: String ("missile" | "beam")
##   tick: int, sim_time: float
##   attacker_ship_id: String, target_ship_id: String
##   missile_position: Vector3        (sim coordinates, metres)
##   target_position: Vector3, target_orientation: Quaternion  (at detonation)
##   rods: Array[Dictionary] {position: Vector3, sector: int (-1 = none),
##         outcome: int (MissileResolution.Outcome), incoming: float, damage: float}
##   total_incoming: float            (yield offered to the defence)
##   total_damage: float              (yield that got through)
##   overall_outcome: int             (MissileResolution.Outcome)
##   hull_before: float, hull_after: float, hull_max: float   (0 if no hull)
##   wedge_up: bool
##   sidewalls: Dictionary {port, starboard, bow, stern} conditions after the hit
##   subsystems: Array                (SubsystemType keys that took damage)
class_name ImpactRecord

const MissileResolution = preload("res://simulation/missile_resolution.gd")
const WeaponResolution = preload("res://simulation/weapon_resolution.gd")

## `det` is the MissileResolution.DetonationResult just returned by
## resolve_detonation(); `target` the ShipPhysicsState struck; hull_before is
## sampled by the caller BEFORE resolve_detonation applied damage.
static func build(tick: int, sim_time: float, attacker_ship_id: String, target_ship_id: String, missile_position: Vector3, target, target_hull, hull_before: float, det) -> Dictionary:
	var rods: Array = []
	var total_incoming: float = 0.0
	for rod in det.rod_results:
		var sector_id: int = -1
		if rod.sector != null:
			sector_id = int(rod.sector)
		rods.append({
			"position": rod.position,
			"sector": sector_id,
			"outcome": rod.outcome,
			"incoming": rod.incoming,
			"damage": rod.damage,
		})
		total_incoming += rod.incoming

	return _assemble("missile", tick, sim_time, attacker_ship_id, target_ship_id, missile_position, target, rods, total_incoming, det.damage_dealt, det.outcome, hull_before, target_hull, det.subsystem_damage.keys())

## Beam shot record. `result` is the WeaponResolution.ShotResult, `incoming`
## the yield offered to the defence (damage_per_hit * mount condition).
## Returns an empty Dictionary for shots that produce no strike to show (miss,
## out of range, not ready, no arc) so callers can `if rec.is_empty()`.
static func build_beam(tick: int, sim_time: float, attacker_ship_id: String, target_ship_id: String, attacker, target, target_hull, hull_before: float, result, incoming: float) -> Dictionary:
	var rod_outcome: int = beam_outcome_to_rod_outcome(result.outcome)
	if rod_outcome < 0:
		return {}
	var sector_id: int = -1
	if result.target_sector != null:
		sector_id = int(result.target_sector)
	var rods: Array = [{
		"position": attacker.position,
		"sector": sector_id,
		"outcome": rod_outcome,
		"incoming": incoming,
		"damage": result.damage_dealt,
	}]
	return _assemble("beam", tick, sim_time, attacker_ship_id, target_ship_id, attacker.position, target, rods, incoming, result.damage_dealt, rod_outcome, hull_before, target_hull, result.subsystem_damage.keys())

## WeaponResolution.Outcome -> MissileResolution.Outcome, or -1 when the shot
## has nothing to show on the target.
static func beam_outcome_to_rod_outcome(beam_outcome: int) -> int:
	match beam_outcome:
		WeaponResolution.Outcome.WEDGE_BLOCKED:
			return MissileResolution.Outcome.WEDGE_BLOCKED
		WeaponResolution.Outcome.SIDEWALL_ATTENUATED:
			return MissileResolution.Outcome.SIDEWALL_ATTENUATED
		WeaponResolution.Outcome.FORMATION_COVERED:
			return MissileResolution.Outcome.FORMATION_COVERED
		WeaponResolution.Outcome.HIT_UNPROTECTED:
			return MissileResolution.Outcome.HIT_UNPROTECTED
		_:
			return -1

static func _assemble(kind: String, tick: int, sim_time: float, attacker_ship_id: String, target_ship_id: String, source_position: Vector3, target, rods: Array, total_incoming: float, total_damage: float, overall_outcome: int, hull_before: float, target_hull, subsystem_keys: Array) -> Dictionary:
	var defense = target.defense
	var sidewalls: Dictionary = {"port": 0.0, "starboard": 0.0, "bow": 0.0, "stern": 0.0}
	var wedge_up: bool = false
	if defense != null:
		wedge_up = defense.wedge_up
		sidewalls = {
			"port": defense.port_sidewall_condition,
			"starboard": defense.starboard_sidewall_condition,
			"bow": defense.bow_sidewall_condition,
			"stern": defense.stern_sidewall_condition,
		}
	var hull_after: float = 0.0
	var hull_max: float = 0.0
	if target_hull != null:
		hull_after = target_hull.integrity
		hull_max = target_hull.max_integrity
	return {
		"kind": kind,
		"tick": tick,
		"sim_time": sim_time,
		"attacker_ship_id": attacker_ship_id,
		"target_ship_id": target_ship_id,
		"missile_position": source_position,
		"target_position": target.position,
		"target_orientation": target.orientation,
		"rods": rods,
		"total_incoming": total_incoming,
		"total_damage": total_damage,
		"overall_outcome": overall_outcome,
		"hull_before": hull_before,
		"hull_after": hull_after,
		"hull_max": hull_max,
		"wedge_up": wedge_up,
		"sidewalls": sidewalls,
		"subsystems": subsystem_keys,
	}
