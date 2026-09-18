extends RefCounted
## SubsystemState
##
## ТЗ §25 Damage: per-subsystem condition. Pure data (ТЗ §8/§48
## data-driven separation) -- what damaged condition actually DOES to
## ship capability is decided by the consuming system (SensorResolution
## for SENSORS, etc.), same separation as ShipDefenseState/HullState.
class_name SubsystemState

## 1.0 = fully functional, 0.0 = fully disabled. Never negative (clamped).
var integrity: float = 1.0

func apply_damage(amount: float) -> void:
	integrity = clampf(integrity - amount, 0.0, 1.0)

func repair(amount: float) -> void:
	integrity = clampf(integrity + amount, 0.0, 1.0)

## ASSUMPTION: no canonical "how damaged before a subsystem stops working
## entirely" figure found -- 0.0 (fully destroyed) is the only point at
## which this class itself calls a subsystem disabled; degraded-but-
## functioning behavior in between is up to each consumer (e.g.
## SensorResolution scaling range continuously by integrity rather than
## having its own separate threshold).
func is_disabled() -> bool:
	return integrity <= 0.0
