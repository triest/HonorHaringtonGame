extends RefCounted
## ShipNames
##
## Display names for ship ids (the simulation keeps short stable ids such
## as "alpha"/"beta_2" that tests and replays depend on; the UI shows the
## scenario's in-universe names instead). Filled by the scenario builder.
class_name ShipNames

static var names: Dictionary = {}
## 2026-09-28 (mission editor): ship_id -> ShipClasses class_id, so the UI
## can show a ship's type (e.g. in a tooltip or card) without threading a
## second lookup through DemoScenario/ShipClasses call sites.
static var ship_class: Dictionary = {}

static func of(id: String) -> String:
	return String(names.get(id, id))

static func class_label(id: String) -> String:
	var cid: String = String(ship_class.get(id, ""))
	return ShipClasses.label(cid) if cid != "" else ""
