extends RefCounted
## SubsystemType
##
## ТЗ §25 Damage: "Damage must be subsystem based. Minimum systems:
## propulsion; maneuvering; sensors; communications; weapons; missile
## systems; counter-missile systems; point defense; power; structural
## integrity; defensive systems."
##
## Single source of truth for the subsystem list -- ShipSubsystems builds
## its condition map from this enum so every consumer (current and future)
## refers to the same 11 categories the ТЗ names, rather than each module
## inventing its own subset.
class_name SubsystemType

enum Type {
	PROPULSION,
	MANEUVERING,
	SENSORS,
	COMMUNICATIONS,
	WEAPONS,
	MISSILE_SYSTEMS,
	COUNTER_MISSILE_SYSTEMS,
	POINT_DEFENSE,
	POWER,
	STRUCTURAL_INTEGRITY,
	DEFENSIVE_SYSTEMS,
}
