extends Node
## SimClock
##
## Deterministic fixed-timestep simulation clock (Milestone 1 / ТЗ §43, §44).
##
## The simulation MUST NOT be driven directly by Godot's variable-rate
## _process(delta). All physical state changes go through this clock so that,
## given the same initial state + seed + commands + timestep, the result is
## reproducible (ТЗ §43 Deterministic Simulation).
class_name SimClock

## Fixed physics step in seconds. 60 Hz simulation tick.
const FIXED_DT: float = 1.0 / 60.0

## Time scale multipliers supported by the UI (ТЗ §44 Time Control).
const ALLOWED_TIME_SCALES: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0, 25.0, 100.0]

var time_scale: float = 1.0
var paused: bool = false
var single_step_requested: bool = false

## Total simulated time in seconds since scenario start (NOT wall-clock time).
var sim_time: float = 0.0

## Number of fixed simulation ticks executed since scenario start.
var tick_count: int = 0

var _accumulator: float = 0.0

signal simulation_tick(dt: float, tick: int, sim_time: float)

func set_time_scale(scale: float) -> void:
	if not ALLOWED_TIME_SCALES.has(scale):
		push_warning("SimClock: unsupported time scale %s, ignoring" % scale)
		return
	time_scale = scale

func request_single_step() -> void:
	single_step_requested = true

## Call once per Godot _process(delta) or _physics_process(delta) frame.
## Advances the deterministic simulation by zero or more FIXED_DT ticks.
func advance(frame_delta: float) -> void:
	if paused and not single_step_requested:
		return

	if single_step_requested:
		_run_tick()
		single_step_requested = false
		return

	_accumulator += frame_delta * time_scale
	# Avoid spiral-of-death if the host frame stalls badly; simulation
	# correctness (§43) matters more than perfectly matching wall time.
	var max_ticks_per_frame := 100
	var ticks_run := 0
	while _accumulator >= FIXED_DT and ticks_run < max_ticks_per_frame:
		_run_tick()
		_accumulator -= FIXED_DT
		ticks_run += 1

func _run_tick() -> void:
	tick_count += 1
	sim_time += FIXED_DT
	simulation_tick.emit(FIXED_DT, tick_count, sim_time)
