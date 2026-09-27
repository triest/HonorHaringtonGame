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
const ALLOWED_TIME_SCALES: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0]

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

	# 2026-09-27: optional external cap (e.g. auto-slowdown while missiles
	# are in their terminal approach), 0 = no cap.
	var eff_scale: float = time_scale
	if scale_cap > 0.0:
		eff_scale = minf(eff_scale, scale_cap)
	_accumulator += frame_delta * eff_scale
	# 2026-09-27 (live demo at canon scale, hundreds of missiles in
	# flight): optional adaptive coarsening + per-frame CPU budget. Both
	# default OFF (max_dt_multiplier = 1, frame_budget_ms = 0) so every
	# existing test/caller still gets exactly FIXED_DT ticks as before.
	#  * max_dt_multiplier > 1: at high time scales each tick covers
	#    FIXED_DT * m sim-seconds (m grows with time_scale, capped), so
	#    25x/100x don't require 1,500-6,000 ticks per real second.
	#  * frame_budget_ms > 0: stop running ticks once this frame has spent
	#    the budget and drop the backlog, so the window stays responsive;
	#    the sim then honestly runs slower than the requested scale, and
	#    `effective_time_scale` reports what was actually achieved.
	var m: int = 1
	if max_dt_multiplier > 1 and eff_scale > 1.0:
		m = clampi(int(eff_scale / 4.0), 1, max_dt_multiplier)
	var step: float = FIXED_DT * float(m)
	var max_ticks_per_frame := 100
	var ticks_run := 0
	var t0: int = Time.get_ticks_usec()
	var sim_before: float = sim_time
	while _accumulator >= step and ticks_run < max_ticks_per_frame:
		_run_tick(step)
		_accumulator -= step
		ticks_run += 1
		if frame_budget_ms > 0.0 and float(Time.get_ticks_usec() - t0) / 1000.0 > frame_budget_ms:
			_accumulator = minf(_accumulator, step)
			break
	if frame_delta > 0.0:
		var achieved: float = (sim_time - sim_before) / frame_delta
		effective_time_scale = lerpf(effective_time_scale, achieved, 0.1)

## See advance(): both default to the old exact behavior.
var max_dt_multiplier: int = 1
var scale_cap: float = 0.0
var frame_budget_ms: float = 0.0
## Smoothed actually-achieved sim-seconds per real second (UI readout).
var effective_time_scale: float = 1.0

func _run_tick(step: float = FIXED_DT) -> void:
	tick_count += 1
	sim_time += step
	simulation_tick.emit(step, tick_count, sim_time)
