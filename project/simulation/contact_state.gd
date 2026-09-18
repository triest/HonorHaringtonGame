extends RefCounted
## ContactState
##
## Shared sensor-contact confidence states (ТЗ §23 Sensors):
## UNKNOWN / DETECTED / TRACKED / ESTIMATED / UNCERTAIN / LOST.
##
## Single source of truth for this enum -- MissileState.SensorState
## aliases to this (see missile_state.gd) instead of duplicating the
## values, now that sensor_resolution.gd needs the same states for ship
## sensor contacts and must stay in sync with what missiles use for their
## own target lock.
class_name ContactState

enum Type { UNKNOWN, DETECTED, TRACKED, ESTIMATED, UNCERTAIN, LOST }
