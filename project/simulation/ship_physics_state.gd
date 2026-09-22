extends RefCounted
## ShipPhysicsState
##
## Full 3D inertial physical state of a single ship (ТЗ §6 True 3D Simulation,
## §11 Spacecraft Kinematics, §12 Inertial Movement).
##
## This is simulation state, not a visual node. Rendering (a Node3D) must
## read from this object; it must never define combat/physics rules itself
## (ТЗ §42 Simulation Architecture: "Rendering must display simulation state
## rather than define combat rules.").
##
## CANON/ASSUMPTION notes:
## - ASSUMPTION: acceleration is expressed directly in m/s^2 (not "g") in the
##   simulation core; UI layers may display it as a multiple of g
##   (1 g = 9.80665 m/s^2). Exact per-class accelerations are CANON only
##   where a ship class explicitly documents them in ASSUMPTIONS.md /
##   ship data; otherwise treat as UNKNOWN and keep configurable.
## - ASSUMPTION: this milestone uses classical (non-relativistic) Newtonian
##   integration. A relativistic velocity cap (ТЗ §15 Speed of Light) is a
##   documented TODO for the kinematics milestone and is NOT implemented yet;
##   see docs/ASSUMPTIONS.md.
class_name ShipPhysicsState

const KinematicsUtils = preload("res://simulation/kinematics_utils.gd")
const SPEED_OF_LIGHT_MPS: float = KinematicsUtils.SPEED_OF_LIGHT_MPS
const SubsystemType = preload("res://simulation/subsystem_type.gd")

## Position in simulation-space meters (double precision required at scale;
## see docs/ASSUMPTIONS.md re: origin rebasing, ТЗ §14).
var position: Vector3 = Vector3.ZERO

var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO

## Ship orientation as a quaternion (ТЗ §6: "Quaternion/equivalent for
## orientation").
var orientation: Quaternion = Quaternion.IDENTITY
var angular_velocity: Vector3 = Vector3.ZERO
var angular_acceleration: Vector3 = Vector3.ZERO

## Commanded thrust direction, ship-local space, unit vector or zero.
var commanded_thrust_local: Vector3 = Vector3.ZERO

## Physical properties (ASSUMPTION defaults; MUST be overridden by
## data-driven ship class definitions per ТЗ §8, not hardcoded per-ship).
##
## ТЗ §62.1: mass is load-bearing. Acceleration is F/m
## (`effective_max_thrust() / mass_kg`), not a per-ship arcade cap.
var mass_kg: float = 1.0e9
## Rated impeller thrust in newtons. Default ~500 m/s^2 at the default
## 1e9 kg mass (~51 g) -- placeholder, not a canon class rating.
var max_thrust_n: float = 5.0e11
var max_angular_speed_rad_s: float = 0.3

## Compatibility alias used by existing tests/callers that still think
## in m/s^2. Reading returns current F/m; writing sets `max_thrust_n`
## so that F/m equals the requested acceleration at the CURRENT mass.
var max_acceleration_mps2: float:
	get:
		return max_thrust_n / maxf(mass_kg, 1.0)
	set(value):
		max_thrust_n = value * maxf(mass_kg, 1.0)

## Hull dimensions for rendering/geometry purposes (ТЗ §7 Ship
## Representation, §8 Ship Database: "dimensions" is an explicit data
## field). ASSUMPTION placeholder defaults (~a light cruiser scale guess,
## not tied to any specific canon class) -- MUST be overridden per ship
## class once a real ship database exists. NOT used by physics/combat
## math in this milestone, only by the rendering layer
## (scripts/hull_mesh_builder.gd) to build a proportioned hull silhouette
## instead of a uniform placeholder cube.
var length_m: float = 500.0
var max_width_m: float = 90.0
var max_height_m: float = 60.0

## Propulsion/compensator condition in [0.0, 1.0]; degraded by damage
## (ТЗ §12, §25). 1.0 = fully functional. PRE-DATES `subsystems` below --
## kept as-is for backward compatibility (every existing caller/test sets
## these directly); see `subsystems` doc comment for how the two combine.
var propulsion_condition: float = 1.0
var compensator_condition: float = 1.0

## Wedge/sidewall defensive state (ТЗ §9, §10, §16). Optional: null means
## "no defense system modeled yet" (e.g. missiles/debris), not "wedge down".
var defense: ShipDefenseState = null

## ТЗ §25 Damage: optional ShipSubsystems (the canonical, complete
## 11-subsystem container -- see ship_subsystems.gd). Null (the default)
## means "no subsystem damage modeling for this ship", identical to
## pre-§25 behavior. When present, `effective_max_thrust()` ALSO
## scales by this ship's own PROPULSION and MANEUVERING subsystem
## condition, ON TOP OF (multiplied with, not replacing)
## `propulsion_condition`/`compensator_condition` above -- this is the
## direct implementation of the ТЗ §25 example "propulsion damage ->
## degraded acceleration" via the canonical container, without having to
## migrate the older fields (a deliberately deferred unification, see
## ASSUMPTIONS.md).
var subsystems = null

## ТЗ §63.1 (Ship Destruction, Wrecks, and Progressive Combat Damage):
## true once this ship has been destroyed and become an inert wreck
## (set by SimulationWorld._resolve_ship_destruction, never here). A
## wreck keeps its physics state and continues to obey momentum/inertia
## (ТЗ §12) via SimulationWorld._integrate_ships exactly like a live
## ship -- nothing about `ShipPhysicsState.integrate()` itself changes --
## but every combat/command/AI resolver in SimulationWorld checks this
## flag and skips a wreck entirely (no weapons fire, no missile launch,
## no point defense, no formation/individual command, no damage-
## triggered retreat, no outgoing sensor observation): a wreck has no
## crew or power left to do any of those things. It REMAINS a valid
## incoming sensor CONTACT for other ships (via _update_sensors) and a
## valid physics object -- see AGENTS.md §63.1, "a destroyed ship must
## NOT disappear".
var is_wreck: bool = false

func effective_max_thrust() -> float:
	var result: float = max_thrust_n * propulsion_condition * compensator_condition
	if subsystems != null:
		result *= subsystems.get_condition(SubsystemType.Type.PROPULSION)
		result *= subsystems.get_condition(SubsystemType.Type.MANEUVERING)
	return result

## Attainable linear acceleration in m/s^2 (ТЗ §62.1: a = F/m).
## Existing maneuver code (formation-keeping, individual orders) reads
## this rather than dividing by mass itself.
func effective_max_acceleration() -> float:
	return effective_max_thrust() / maxf(mass_kg, 1.0)

## Advances this ship's physical state by exactly one fixed simulation tick.
## Thrust -> acceleration -> velocity -> position (ТЗ §12).
func integrate(dt: float) -> void:
	# CANON (CANON_RULES.md, verified 2026-09-18): raising a bow or stern
	# sidewall blocks impeller acceleration while that wall is active.
	# Broadside sidewalls and the wedge itself do not have this restriction.
	var thrust_blocked_by_sidewall := defense != null and (defense.bow_sidewall_raised or defense.stern_sidewall_raised)

	var thrust_world := Vector3.ZERO
	if not thrust_blocked_by_sidewall:
		thrust_world = orientation * commanded_thrust_local
		if thrust_world.length_squared() > 1.0:
			thrust_world = thrust_world.normalized()

	# F = ma => a = F / m
	# We calculate acceleration based on the effective maximum thrust available.
	acceleration = (thrust_world * effective_max_thrust()) / maxf(mass_kg, 1.0)

	# Semi-implicit (symplectic) Euler via the shared kinematics helper, so
	# ships and missiles apply identical integration + c-clamp logic
	# (ТЗ §12, §15). See kinematics_utils.gd.
	var result: Array = KinematicsUtils.integrate_linear(position, velocity, acceleration, dt)
	velocity = result[0]
	position = result[1]

	orientation = KinematicsUtils.integrate_orientation(orientation, angular_velocity, dt)

func closure_velocity_towards(other: ShipPhysicsState) -> float:
	var to_other := (other.position - position)
	if to_other.length_squared() <= 0.0:
		return 0.0
	var rel_velocity := relative_velocity(other)
	return -rel_velocity.dot(to_other.normalized())

## ТЗ §13: relativeVelocity = targetVelocity - attackerVelocity
func relative_velocity(target: ShipPhysicsState) -> Vector3:
	return target.velocity - velocity

func distance_to(other: ShipPhysicsState) -> float:
	return position.distance_to(other.position)
