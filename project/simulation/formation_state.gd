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

func set_station(ship_id: String, offset_local: Vector3) -> void:
	member_offsets[ship_id] = offset_local

func remove_member(ship_id: String) -> void:
	member_offsets.erase(ship_id)

func member_ids() -> Array:
	return member_offsets.keys()
