extends RefCounted
## MissileState
##
## A missile as a real 3D simulation entity (ТЗ §18: "A missile must NOT
## simply animate from launcher to target. It must participate in
## simulation."). Minimum state per §18: Position, Velocity, Acceleration,
## Orientation, Target, GuidanceState, SensorState, TerminalState,
## ECMState, Lifetime, WarheadState.
##
## CANON basis (CANON_RULES.md, verified 2026-09-18, Honorverse Wiki
## "Missile"): a cited capital-ship missile example "could accelerate at
## 46,000 G for perhaps 180 seconds before its drive burned out" — used
## here as the DEFAULT placeholder for drive_max_acceleration_mps2 /
## drive_burn_time_s, explicitly documented as an example for ONE class/era,
## not a universal constant (ТЗ §11 forbids a single MAX_SPEED for all
## ships/missiles). Laserhead effective damage radius citation ("within
## 25,000 kilometers of the detonation") informs area-effect design later;
## it is NOT the terminal detonation TRIGGER range used here, which is a
## separate, unverified ASSUMPTION (see ASSUMPTIONS.md).
class_name MissileState

const KinematicsUtils = preload("res://simulation/kinematics_utils.gd")
const ContactState = preload("res://simulation/contact_state.gd")

enum GuidanceState { BOOST, MIDCOURSE, TERMINAL, DETONATED, SELF_DESTRUCTED, LOST, INTERCEPTED }

## ТЗ §23 Sensors: contact/tracking confidence states, reused here for the
## missile's own lock on its target. Aliases the shared ContactState enum
## (contact_state.gd) rather than duplicating it, now that
## sensor_resolution.gd needs the identical states for ship-level sensor
## contacts -- `MissileState.SensorState.TRACKED` keeps working exactly as
## before for all existing callers/tests.
const SensorState = ContactState.Type

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY

## Target reference. ASSUMPTION: direct object reference for this
## milestone (single-process simulation); a networked/save-friendly build
## would use a ship_id string + lookup instead. See ASSUMPTIONS.md.
##
## Deliberately UNTYPED (not `: ShipPhysicsState`): a counter-missile's
## target is an incoming MissileState, not a ship (ТЗ §20 Counter-Missiles).
## Both ShipPhysicsState and MissileState expose `position`/`velocity`, so
## MissileGuidance works against either via duck typing -- this is what
## lets counter-missiles reuse the same guidance code as offensive
## missiles instead of a parallel implementation.
var target = null

var guidance_state: int = GuidanceState.BOOST
var sensor_state: int = SensorState.UNKNOWN  # ТЗ §23: starts unknown, updated live by MissileGuidance.update_target_tracking() once wired; a caller that never wires sensors can still force TRACKED for backward-compatible "perfect tracking" tests.

## ТЗ §23 Sensors: this missile's own live sensor contact on `target`,
## lazily created and advanced by MissileGuidance.update_target_tracking().
## Left null (never created) for callers that do not opt into live sensor
## tracking -- those keep the old "perfect information" behavior via the
## sensor_state/target.position fallback path.
var sensor_contact = null
var lifetime_s: float = 0.0
var warhead_armed: bool = false
var has_detonated: bool = false

## Laserhead rod configuration (ТЗ AGENTS.md §21.1/§21.2, CANON: rods
## eject from bays, maneuver independently, settle ~100m ahead of the
## warhead between it and the target, each independently aimed).
## ASSUMPTION default rod_count = 6 (CANON example for the Mark 23 capital
## warhead, used as a reasonable default, NOT a universal constant --
## §11/§48 require this to be data-driven per missile class).
var rod_count: int = 6
var rod_offset_m: float = 100.0  ## CANON: "about a hundred meters" ahead of the warhead.
var laserhead_damage: float = 400.0  ## ASSUMPTION placeholder total yield, split across rods; see ASSUMPTIONS.md.

## ASSUMPTION (NOT found in canon sources checked): half-angle of the cone
## within which rods spread out from the boresight to individually align
## on the target from slightly different vectors, per §21.1 "each rod...
## allowing it to align itself with its target". Kept configurable and
## documented rather than invented as a hidden constant, per §4/§9 intent.
var rod_spread_half_angle_rad: float = deg_to_rad(20.0)

## CANON example value (see class doc); ASSUMPTION as a universal default.
## Named as constants (not just literal defaults below) so §34.2's
## flight-time estimator (SimulationWorld._resolve_missile_tot_coordination,
## via KinematicsUtils.estimate_boost_coast_time_to_distance_s) can
## reference the EXACT same design values every AI-launched missile
## actually gets at launch (see SimulationWorld._launch_missile_from_tube,
## which never customizes these) instead of duplicating the CANON example
## figure as a second, driftable literal.
const DEFAULT_DRIVE_MAX_ACCELERATION_MPS2: float = 46_000.0 * 9.80665
const DEFAULT_DRIVE_BURN_TIME_S: float = 180.0

var drive_max_acceleration_mps2: float = DEFAULT_DRIVE_MAX_ACCELERATION_MPS2
var drive_burn_time_s: float = DEFAULT_DRIVE_BURN_TIME_S
var drive_burn_remaining_s: float = DEFAULT_DRIVE_BURN_TIME_S

## "Design" (un-throttled, full-power) values, captured once at launch
## configuration time so set_throttle() can be called more than once and
## always compute from the original design point rather than compounding.
var _base_drive_max_acceleration_mps2: float = drive_max_acceleration_mps2
var _base_drive_burn_time_s: float = drive_burn_time_s
var _base_captured: bool = false

## ТЗ AGENTS.md §18.1 (CANON): "drives were frequently adjustable, allowing
## the acceleration to be 'stepped down' in order to increase the powered
## lifetime". Reducing acceleration extends burn time/powered range, at
## the tactical cost of giving the target longer to react.
##
## ASSUMPTION (physically-grounded, not itself a canon citation): this
## models the trade-off as a constant delta-v budget --
## base_accel * base_burn_time == throttled_accel * throttled_burn_time --
## i.e. the missile carries a fixed total impulse and throttling only
## changes how it is spent over time. Call BEFORE the missile starts
## burning (drive_burn_remaining_s == drive_burn_time_s); throttling
## mid-burn is not modeled.
func set_throttle(fraction: float) -> void:
	if not _base_captured:
		_base_drive_max_acceleration_mps2 = drive_max_acceleration_mps2
		_base_drive_burn_time_s = drive_burn_time_s
		_base_captured = true

	var clamped: float = clampf(fraction, 0.05, 1.0)  # avoid div-by-zero / absurd endurance
	drive_max_acceleration_mps2 = _base_drive_max_acceleration_mps2 * clamped
	drive_burn_time_s = _base_drive_burn_time_s / clamped
	drive_burn_remaining_s = drive_burn_time_s

## Powered range under the current (possibly throttled) configuration,
## assuming a straight-line burn from rest: distance = 0.5 * a * t^2.
## This is an ENGINEERING CHECK / UI-facing estimate, not used by the
## guidance/integration code itself (which integrates tick-by-tick against
## the real, possibly-curving flight path).
func estimated_powered_range_m() -> float:
	return 0.5 * drive_max_acceleration_mps2 * drive_burn_time_s * drive_burn_time_s

## ASSUMPTION placeholders, not found in canon sources during this
## session's verification pass — see ASSUMPTIONS.md.
var max_lifetime_s: float = 600.0
var terminal_detonation_range_m: float = 50_000.0
var max_turn_rate_rad_s: float = 0.5

func is_active() -> bool:
	return guidance_state == GuidanceState.BOOST or guidance_state == GuidanceState.MIDCOURSE or guidance_state == GuidanceState.TERMINAL

## True once this missile has been killed by a counter-missile (ТЗ §20)
## rather than reaching its own target/self-destructing.
func is_intercepted() -> bool:
	return guidance_state == GuidanceState.INTERCEPTED

## Advances the missile by one fixed simulation tick. Guidance direction is
## supplied by the caller (MissileGuidance) so this class stays pure
## kinematics/state, same separation of concerns as ShipPhysicsState.
func integrate(dt: float, desired_thrust_world_dir: Vector3) -> void:
	if not is_active():
		return

	lifetime_s += dt
	if lifetime_s >= max_lifetime_s:
		guidance_state = GuidanceState.SELF_DESTRUCTED
		return

	if drive_burn_remaining_s > 0.0:
		guidance_state = GuidanceState.BOOST if lifetime_s < 2.0 else GuidanceState.MIDCOURSE
		var thrust_dir := desired_thrust_world_dir
		if thrust_dir.length_squared() > 1.0:
			thrust_dir = thrust_dir.normalized()
		acceleration = thrust_dir * drive_max_acceleration_mps2
		drive_burn_remaining_s = maxf(0.0, drive_burn_remaining_s - dt)
	else:
		# CANON: "drive burned out" — coasts ballistically from here on,
		# no further course correction. This matches the cited example's
		# framing (burn time is finite) rather than unlimited-endurance
		# arcade missiles (ТЗ §11 prohibits universal arcade constants).
		acceleration = Vector3.ZERO

	var result: Array = KinematicsUtils.integrate_linear(position, velocity, acceleration, dt)
	velocity = result[0]
	position = result[1]

	if velocity.length_squared() > 0.0:
		# Missiles are drive-aligned: orientation follows velocity vector
		# rather than an independently commanded facing (ASSUMPTION,
		# reasonable for a reaction-drive kinetic vehicle; ships are not
		# modeled this way because they can thrust off-axis).
		orientation = _look_rotation(velocity.normalized())

	if target != null and guidance_state != GuidanceState.SELF_DESTRUCTED:
		var dist: float = position.distance_to(target.position)
		if dist <= terminal_detonation_range_m:
			guidance_state = GuidanceState.TERMINAL if guidance_state != GuidanceState.TERMINAL else guidance_state
			# ASSUMPTION: arm + detonate threshold at 10% of terminal range —
			# see ASSUMPTIONS.md, not a canonical figure. Actual detonation
			# (warhead -> hull damage) is applied by the caller via
			# MissileResolution.resolve_detonation(), keeping "does it hit"
			# logic out of pure kinematic state, same separation as ships.
			if dist <= terminal_detonation_range_m * 0.1:
				warhead_armed = true

static func _look_rotation(forward: Vector3) -> Quaternion:
	if forward.length_squared() <= 0.0:
		return Quaternion.IDENTITY
	var basis := Basis.looking_at(forward, Vector3.UP) if absf(forward.dot(Vector3.UP)) < 0.999 else Basis.looking_at(forward, Vector3.RIGHT)
	return basis.get_rotation_quaternion()
