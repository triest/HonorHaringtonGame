extends RefCounted
## ShipSubsystems
##
## ТЗ §25 Damage: container holding one SubsystemState per SubsystemType
## for a ship. This is the canonical, complete-per-ТЗ subsystem damage
## model going forward.
##
## HONEST STATUS (not overclaiming "done"): several subsystems already had
## their OWN pre-existing condition fields before this Milestone, added
## ad hoc as each earlier system was built -- `ShipPhysicsState.propulsion_condition`
## / `.compensator_condition` (§9/§18), `WeaponMount.condition` (§17),
## `PointDefenseMount.condition` (§22), `ShipDefenseState`'s sidewall
## conditions (§9). Those are NOT yet unified with this container (that
## would mean rewriting those modules to read from here instead of their
## own fields -- a real refactor, deliberately deferred rather than
## rushed to avoid destabilizing already-tested systems). This container
## currently actively DRIVES ONE consumer: SensorResolution reads
## `get_condition(SubsystemType.Type.SENSORS)` to degrade detection range
## (see sensor_resolution.gd), directly implementing the ТЗ §25 example
## "sensor damage -> degraded tracking". COMMUNICATIONS, POWER,
## STRUCTURAL_INTEGRITY, MISSILE_SYSTEMS and COUNTER_MISSILE_SYSTEMS have
## no consumer wired yet -- there is no command/reporting system (§26/§28)
## for COMMUNICATIONS to degrade, no live power-budget model, and
## MissileGuidance/CounterMissileResolution do not yet read a launching
## ship's subsystem state. See ASSUMPTIONS.md for the full gap list.
class_name ShipSubsystems

const SubsystemType = preload("res://simulation/subsystem_type.gd")
const SubsystemState = preload("res://simulation/subsystem_state.gd")

var _states: Dictionary = {}

func _init() -> void:
	for type_value in SubsystemType.Type.values():
		_states[type_value] = SubsystemState.new()

func get_state(type: int) -> SubsystemState:
	return _states[type]

func get_condition(type: int) -> float:
	return _states[type].integrity

func is_disabled(type: int) -> bool:
	return _states[type].is_disabled()

func apply_damage(type: int, amount: float) -> void:
	_states[type].apply_damage(amount)

func repair(type: int, amount: float) -> void:
	_states[type].repair(amount)
