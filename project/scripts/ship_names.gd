extends RefCounted
## ShipNames
##
## Display names for ship ids (the simulation keeps short stable ids such
## as "alpha"/"beta_2" that tests and replays depend on; the UI shows the
## scenario's in-universe names instead). Filled by the scenario builder.
class_name ShipNames

static var names: Dictionary = {}

static func of(id: String) -> String:
	return String(names.get(id, id))
