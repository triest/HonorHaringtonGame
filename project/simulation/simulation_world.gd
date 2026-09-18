extends Node
## SimulationWorld
##
## Owns all ShipPhysicsState instances and drives them from SimClock ticks.
## This is the root of the "Simulation" subsystem (ТЗ §42 Simulation
## Architecture). It has no knowledge of rendering.
class_name SimulationWorld

var clock: SimClock
var ships: Dictionary = {}  # String ship_id -> ShipPhysicsState

func _ready() -> void:
	clock = SimClock.new()
	add_child(clock)
	clock.simulation_tick.connect(_on_simulation_tick)

func _process(delta: float) -> void:
	clock.advance(delta)

func add_ship(ship_id: String, state: ShipPhysicsState) -> void:
	ships[ship_id] = state

func remove_ship(ship_id: String) -> void:
	ships.erase(ship_id)

func get_ship(ship_id: String) -> ShipPhysicsState:
	return ships.get(ship_id)

func _on_simulation_tick(dt: float, _tick: int, _sim_time: float) -> void:
	for ship_id in ships.keys():
		var state: ShipPhysicsState = ships[ship_id]
		state.integrate(dt)
