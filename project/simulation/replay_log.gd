extends RefCounted
## ReplayLog
##
## ТЗ §45 Replay / §43 Deterministic Simulation, Milestone 12 first slice.
##
## Plain data recording of one simulation run: every COMMAND issued
## through SimulationWorld's public order-issuing API (see
## SimulationWorld._record_command / .start_recording), plus every
## discrete combat/state EVENT resolved during ticks (see
## SimulationWorld._record_event). §37 Battle Reports' event list
## ("target destroyed", "ship damaged", "formation broken", ...)
## overlaps almost exactly with what Replay itself needs, so this one
## log is written to serve both, though no Battle Report UI/formatting
## exists yet -- that is a rendering-layer concern, not started.
##
## HONEST STATUS: this is recording + serialization only.
##   * Does NOT yet include periodic full-state snapshots (§45 "Seek
##     should be implemented through snapshots IF PRACTICAL" --
##     deliberately deferred: snapshotting would need every stateful
##     class in the simulation, roughly two dozen of them, to support
##     to_dict()/from_dict(), a substantial separate pass). §45 already
##     hedges this as optional; today, "seeking" a replay means
##     rebuilding the SAME initial ship/formation/mount setup a scenario
##     script already constructs, then calling
##     SimulationWorld.apply_recorded_command() for every recorded
##     command at its recorded tick while advancing tick_simulation() --
##     proven bit-for-bit reproducible by test_replay_log.gd's own
##     "replay reproduces the original run" test, since this simulation
##     has NO unseeded randomness anywhere (grep confirms none exists;
##     every combat/sensor resolution formula is deterministic).
##   * `random_seed` is stored for forward compatibility with
##     ASSUMPTIONS.md's original "Replay and Scenario Accuracy" entry,
##     which anticipated a FUTURE seeded-randomness need (e.g. sensor
##     noise) -- it is inert today (nothing reads it) and defaults to 0.
##   * Only a handful of event types are wired so far (ship_destroyed,
##     weapon_hit, missile_launched, formation_leader_lost) -- see
##     CHANGELOG.md/ASSUMPTIONS.md for the full list of §37 event types
##     still NOT recorded (contact detected, missile launch detected,
##     incoming missile, subsystem damaged, formation broken beyond
##     leader loss, command lost, retreat initiated).
##   * Playback UI (play/pause/speed/event navigation/trajectory & missile
##     track drawing) is entirely unbuilt -- §38 Tactical UI itself is
##     only an early prototype.
class_name ReplayLog

var random_seed: int = 0

## Array[Dictionary{tick:int, sim_time:float, name:String, args:Dictionary}]
## `args` uses only JSON-safe value types (String/bool/int/float/Array/
## Dictionary) -- see SimulationWorld's individual _record_command call
## sites, and IndividualOrder.to_dict()/FormationOrder.to_dict() for how
## order objects are flattened -- so the whole log round-trips through
## JSON via to_dict()/from_dict()/save_to_file()/load_from_file().
var commands: Array = []

## Array[Dictionary{tick:int, sim_time:float, type:String, data:Dictionary}]
var events: Array = []

func record_command(tick: int, sim_time: float, command_name: String, args: Dictionary) -> void:
	commands.append({"tick": tick, "sim_time": sim_time, "name": command_name, "args": args})

func record_event(tick: int, sim_time: float, event_type: String, data: Dictionary) -> void:
	events.append({"tick": tick, "sim_time": sim_time, "type": event_type, "data": data})

func to_dict() -> Dictionary:
	return {
		"random_seed": random_seed,
		"commands": commands.duplicate(true),
		"events": events.duplicate(true),
	}

static func from_dict(d: Dictionary) -> ReplayLog:
	var log := ReplayLog.new()
	log.random_seed = int(d.get("random_seed", 0))
	log.commands = (d.get("commands", []) as Array).duplicate(true)
	log.events = (d.get("events", []) as Array).duplicate(true)
	return log

## Returns false (and records nothing) if the file cannot be opened for
## writing -- e.g. an invalid path -- rather than crashing.
func save_to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true

## Returns null if the file cannot be opened or does not contain a JSON
## object (corrupt/foreign file), rather than crashing.
static func load_from_file(path: String) -> ReplayLog:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return ReplayLog.from_dict(parsed)
