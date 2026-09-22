extends RefCounted
## CommandEchelon
##
## ТЗ §28 Command Hierarchy (Milestone 10/14 debt, first slice). §28's
## default hierarchy is:
##
##   Fleet > Task Force > Squadron > Division > Element > Ship
##
## and explicitly requires: "The hierarchy must be configurable because
## organizational structures can differ by faction and era." This class
## is deliberately generic to satisfy that: `kind` is a free-form String
## label (NOT a hardcoded enum of the five canonical levels), and the
## tree can be built to any depth via `parent_id`/`child_echelon_ids` --
## nothing here enforces "exactly 5 levels" or the canonical names. A
## scenario using the canonical default hierarchy just happens to set
## `kind` to "Fleet"/"Task Force"/"Squadron"/"Division"/"Element" at each
## level; a faction/era wanting a different structure can use different
## names and/or depth with the exact same class and SimulationWorld API.
##
## Sits ABOVE the existing flat FormationState (guide + member ships) --
## does not replace or change it. A CommandEchelon is either:
##   * an INTERNAL node: `child_echelon_ids` non-empty, no commanded
##     formation of its own (`commanded_formation_id == ""`) -- e.g. a
##     Squadron whose real children are Division-level echelons.
##   * a LEAF node: `commanded_formation_id` points at an existing
##     FormationState registered via SimulationWorld.add_formation --
##     e.g. an Element/Division-level echelon that directly commands one
##     flat guide+members formation.
## Mixing both (children AND a commanded formation on the same node) is
## disallowed by SimulationWorld.add_command_echelon/
## attach_formation_to_echelon (push_error + no-op) -- this keeps
## "collect every formation under this echelon" (see
## SimulationWorld._collect_formation_ids_under_echelon) a single
## unambiguous recursive walk with no special-casing.
##
## THIS PASS ONLY covers order CASCADING (SimulationWorld.
## issue_echelon_order: issue the same intention down to every formation
## under an echelon's subtree). Honestly NOT covered yet: an echelon's
## own "leader" ship/succession (§33 is currently FORMATION-level only,
## not echelon-level), per-echelon status/reporting, and any
## echelon-specific order kinds beyond what FormationOrder already has
## (e.g. §29's "target distribution" at Fleet scale) -- see
## ASSUMPTIONS.md.
class_name CommandEchelon

var echelon_id: String = ""

## Free-form label, e.g. "Fleet", "Task Force", "Squadron", "Division",
## "Element" for the canonical §28 default -- NOT validated or
## constrained against any fixed list (see class doc: the hierarchy
## must be configurable per faction/era).
var kind: String = ""

## "" = root echelon (no parent). Set by SimulationWorld.add_command_echelon.
var parent_id: String = ""

## Array[String] of child echelon_ids. Non-empty only for an INTERNAL
## node (see class doc). Never contains `echelon_id` itself (self-
## parenting is refused by SimulationWorld.add_command_echelon).
var child_echelon_ids: Array = []

## Non-"" only for a LEAF node: the formation_id (SimulationWorld.
## formations key) this echelon directly commands.
var commanded_formation_id: String = ""

func is_leaf() -> bool:
	return commanded_formation_id != ""

## ТЗ §45 Replay: flattens to JSON-safe types, mirroring FormationOrder.
## to_dict()/from_dict() -- see that class for the round-trip convention
## this follows.
func to_dict() -> Dictionary:
	return {
		"echelon_id": echelon_id,
		"kind": kind,
		"parent_id": parent_id,
		"child_echelon_ids": child_echelon_ids.duplicate(),
		"commanded_formation_id": commanded_formation_id,
	}

static func from_dict(d: Dictionary) -> CommandEchelon:
	var echelon := CommandEchelon.new()
	echelon.echelon_id = String(d.get("echelon_id", ""))
	echelon.kind = String(d.get("kind", ""))
	echelon.parent_id = String(d.get("parent_id", ""))
	var children: Array = d.get("child_echelon_ids", [])
	echelon.child_echelon_ids = children.duplicate()
	echelon.commanded_formation_id = String(d.get("commanded_formation_id", ""))
	return echelon
