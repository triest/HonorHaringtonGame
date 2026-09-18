extends RefCounted
## FormationState
##
## ТЗ §27/§28/§29 (Tactical Command System / Command Hierarchy / Formation
## Orders) + Milestone 10 (Formation Command) + AGENTS.md §61 "Combat
## Philosophy — Nelson in a Skirt" ("wall of battle / formation fighting"
## is the primary mode of fleet combat).
##
## First slice, deliberately the simplest useful thing: one guide ship,
## and a set of member ships each holding a fixed relative station
## (offset, in the GUIDE's own local/body frame) to that guide. This is
## the "wall" -- ships keeping formation on a lead unit -- not yet the
## full Level 1 command hierarchy (element/division/squadron/task force/
## fleet, §28) or formation ORDERS (§29: change course, change formation,
## etc.). Those remain open for later Milestone 10 passes.
##
## Deliberately NOT a "no cheat vision" (§26) situation: formation-
## keeping is coordination between FRIENDLY ships of the same command,
## who are assumed to know each other's true position via short-range
## communication/tactical link -- this is a different information
## channel from sensor-based detection of a potentially hostile contact,
## and is not modeled as sensor-limited.
class_name FormationState

var guide_ship_id: String = ""

## ship_id -> Vector3 desired station offset, expressed in the GUIDE
## ship's own local/body frame (so the whole formation rotates with the
## guide, not fixed to world axes). The guide itself is never a key here.
var member_offsets: Dictionary = {}

## §33 Formation Leader: explicit chain-of-command order (ship_id) used
## by SimulationWorld/TacticalAI to pick a successor if the current guide
## is destroyed or incapacitated ("determine successor", step 1 of §33).
## Empty (the default) means "no curated chain of command was set for
## this formation" -- the caller then falls back to
## `member_offsets.keys()` in their existing deterministic Dictionary
## insertion order (§43 Deterministic Simulation: no RNG, no reliance on
## time-of-day). Does not have to list every member -- an id missing from
## here simply is never considered before the fallback list.
var succession_order: Array = []

## §33 step 4 ("account for communication limitations"). Set by
## SimulationWorld to the accumulated simulation time (SimulationWorld's
## own tick-accumulated clock, NOT wall time -- see
## SimulationWorld.world_sim_time) at which the CURRENT guide was first
## observed lost/incapacitated, or -1.0 while the guide is fine. This is
## deliberately NOT modeling the speed-of-light command lag described in
## CANON_RULES.md §7 ("Command Lag") -- that concerns fleet actions
## across millions of kilometers, where light-lag is seconds to minutes;
## at this project's current 1v1/few-ship tactical ranges (kilometers to
## low tens of thousands of km) true light-lag is a small fraction of a
## second and not worth a dedicated mechanic yet. What this DOES model,
## honestly labeled as an ASSUMPTION engineering choice (see
## ASSUMPTIONS.md), is a short crew recognition/succession-procedure
## delay: subordinates do not instantly know the moment their guide goes
## silent and instantly reorganize -- see
## SimulationWorld.COMMAND_TRANSFER_DELAY_S.
var guide_lost_since: float = -1.0

func set_station(ship_id: String, offset_local: Vector3) -> void:
	member_offsets[ship_id] = offset_local

func remove_member(ship_id: String) -> void:
	member_offsets.erase(ship_id)

func member_ids() -> Array:
	return member_offsets.keys()

## §33: set (or replace) the explicit chain-of-command order. Duplicated
## defensively so later mutation of the caller's array does not silently
## change this formation's succession behind its back.
func set_succession_order(order: Array) -> void:
	succession_order = order.duplicate()
