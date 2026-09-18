extends RefCounted
## HullState
##
## TEMPORARY SIMPLIFICATION (ТЗ §58): a single scalar hull integrity pool.
## This is explicitly NOT the final damage model — §25 requires per-subsystem
## damage (propulsion, sensors, weapons, etc.). This placeholder exists only
## so Milestone 4 (energy weapons) has something real to reduce when a shot
## penetrates wedge/sidewalls, instead of firing into a void.
## MUST be replaced by SubsystemDamageState before §59 Definition of Done.
class_name HullState

var max_integrity: float = 10_000.0  # ASSUMPTION placeholder, see ASSUMPTIONS.md
var integrity: float = 10_000.0

func is_destroyed() -> bool:
	return integrity <= 0.0

func apply_damage(amount: float) -> void:
	integrity = maxf(0.0, integrity - amount)
