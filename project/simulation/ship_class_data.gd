extends Resource
## ShipClassData
##
## Data-driven ship class record (ТЗ §8 Ship Database, §48 Data-Driven
## Design: "Do not hardcode ship characteristics into combat code";
## §8's own field list: canonical name/class/faction/era/dimensions/mass/
## acceleration/armament/missile tubes/point-defense/canonical references/
## confidence-uncertainty -- this Resource is that list turned into actual
## fields instead of prose).
##
## This is the first real implementation of §8/§48 in `project/simulation`.
## Until this pass, AGENTS.md §8.1/§8.2/§8.3 explicitly recorded "none of
## the above is wired into project/simulation as actual data yet" as an
## HONEST GAP -- concrete class records live under `project/data/ships/`
## as `.tres` resources using this script, loaded by `ShipFactory`
## (ship_factory.gd), not hand-constructed per test/scenario.
##
## Every numeric field here MUST trace to one of:
##   CANON       -- a sourced number from AGENTS.md §8.1/§8.2/§8.3 (which
##                   themselves cite Honorverse Wiki class/weapon articles,
##                   verified 2026-09-19/22).
##   ASSUMPTION  -- filled in per AGENTS.md §8.4's logical-extrapolation
##                   method (anchor + step recorded in `source_note`), or
##                   an existing engineering placeholder already used
##                   elsewhere in the codebase (e.g. WeaponData/MissileTube
##                   defaults) -- never an arbitrary invented number.
## `source_note` is REQUIRED to say which of the two applies and why; a
## `.tres` record with numbers and no `source_note` violates §8 exactly
## like an invented number would (AGENTS.md §8.4 step 6).
class_name ShipClassData

## --- Identity (§8: canonical name/class/faction/era/canonical references) ---
@export var canonical_name: String = ""          ## e.g. "Medusa-class" -- the CLASS, not an individual hull (§8.3: names of individual ships are deliberately out of scope).
@export var ship_type: String = ""                ## §8.2 tonnage-hierarchy bucket, e.g. "Superdreadnought", "Battlecruiser".
@export var faction: String = ""                  ## e.g. "Manticore", "Haven". Also usable directly as SimulationWorld.set_team()'s team id.
@export var era: String = ""                      ## Free-text tech-generation marker (§8.1: "numbers tagged by ERA, not one fixed table").
@export_multiline var source_note: String = ""    ## Citation + CANON/ASSUMPTION tag per AGENTS.md §8.4 step 6. Required.

## --- Dimensions and mass (§8: dimensions, mass) ---
@export var length_m: float = 0.0
@export var max_width_m: float = 0.0
@export var max_height_m: float = 0.0
@export var mass_kg: float = 0.0

## --- Propulsion (§8: acceleration, propulsion, compensator) ---
## CANON acceleration figures in AGENTS.md §8.1/§8.2 are given in G
## (standard gravities); the simulation core works in m/s^2 (ТЗ §62.1,
## ShipPhysicsState doc comment). `ShipFactory` converts using the
## standard constant, then derives `max_thrust_n = rated_acceleration_mps2
## * mass_kg` so `ShipPhysicsState.effective_max_acceleration()` (F/m)
## reproduces the CANON rating exactly at full condition -- never a
## separate hardcoded acceleration cap (§62.1's own requirement).
@export var rated_acceleration_g: float = 0.0     ## Sustained/typical rating (not the "maximum" figure where the source gives both -- see §8.1 Agamemnon "at 80% compensator load").
@export var max_angular_speed_rad_s: float = 0.3   ## ASSUMPTION: no canonical turn-rate figure exists for any class; shared engineering placeholder identical to ShipPhysicsState's own default.

## --- Energy weapons (§8: armament), by firing zone per CLOUD.md §2.2 /
## WeaponMount.broadside_arc()/bow_chaser_arc()/stern_chaser_arc() ---
@export var broadside_laser_mounts: int = 0
@export var broadside_graser_mounts: int = 0
@export var fore_laser_mounts: int = 0
@export var fore_graser_mounts: int = 0
@export var aft_laser_mounts: int = 0
@export var aft_graser_mounts: int = 0

## --- Missile tubes (§8: missile tubes, missile capacity) ---
## MissileTube (missile_tube.gd) does not model a firing arc (HONEST GAP,
## see ASSUMPTIONS.md) -- broadside/fore/aft counts are recorded as CANON
## reference data for a future arc-aware launcher, but ShipFactory today
## spawns them as plain, arc-less MissileTube instances (identical
## capability regardless of zone), consistent with every existing
## scenario/test.
@export var broadside_missile_tubes: int = 0
@export var fore_missile_tubes: int = 0
@export var aft_missile_tubes: int = 0
@export var missile_magazine_total: int = 0        ## Total reloads across the whole class (§8.3 "Magazine: N missiles"); ShipFactory divides evenly across spawned tubes -- ASSUMPTION distribution, see source_note.

## --- Counter-missile tubes (§8: counter-missile capability) ---
## HONEST GAP: the simulation has no distinct "counter-missile tube" class
## yet -- a counter-missile is just a MissileState whose `target` is
## another MissileState (see counter_missile_resolution.gd /
## simulation_world.gd `_resolve_counter_missile_intercepts`), launched
## through the same generic missile-launch path as an offensive missile.
## This field is CANON reference data only in this pass; ShipFactory does
## not yet spawn a dedicated launcher from it. See ASSUMPTIONS.md.
@export var counter_missile_tubes: int = 0
@export var counter_missile_magazine_total: int = 0

## --- Point defense (§8: point-defense), by firing zone --------------------
## Uses the arc-aware PointDefenseMount (point_defense_resolution.gd,
## closed 2026-09-22) -- this is the first ship data that actually assigns
## real positional PD batteries (broadside + chase) instead of the
## omnidirectional default every prior scenario/test used (explicitly
## flagged as not-yet-done in CHANGELOG.md when the arc mechanic itself
## was added).
@export var broadside_pd_mounts: int = 0
@export var fore_pd_mounts: int = 0
@export var aft_pd_mounts: int = 0

func is_valid() -> bool:
	return canonical_name != "" and mass_kg > 0.0 and source_note != ""
