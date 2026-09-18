extends RefCounted
## DamageType
##
## Shared attacker damage-type classification, used by ShipDefenseState to
## vary sidewall attenuation by attack type (ТЗ AGENTS.md §21.25, CANON:
## "laserhead beam... more effective at penetrating sidewalls than a pure
## fusion explosive"). A single-file enum so weapon_data.gd, missile_state.gd
## and ship_defense_state.gd all reference the same values without an
## import cycle.
class_name DamageType

enum Type {
	ENERGY,     ## Direct-fire lasers/grasers (ТЗ §17 Weapons).
	LASERHEAD,  ## Missile warhead lasing rods (ТЗ §21 Laserheads) -- CANON:
	            ## penetrates sidewalls better than a generic explosive.
	KINETIC,    ## Reserved for future non-laser warhead types (ТЗ §21.25
	            ## implies these should attenuate MORE through a sidewall
	            ## than a laserhead of equivalent yield). Not produced by
	            ## any weapon/missile in the codebase yet -- reserved so
	            ## the enum doesn't need to change shape later.
}
