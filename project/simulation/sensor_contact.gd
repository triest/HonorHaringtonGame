extends RefCounted
## SensorContact
##
## ТЗ §23 Sensors: per-observed-target sensor knowledge held by an
## observer (ship or missile). Tracks confidence state (ContactState.Type),
## the best current position/velocity estimate, and when that estimate was
## last refreshed by an actual detection (as opposed to dead-reckoned).
##
## CANON basis: "On Basilisk Station" ch.3 (primary source, see
## CANON_RULES.md "Седьмая сверка") confirms passive gravitic sensors
## detect impeller-wedge signatures, and that a unit can reduce its
## detectability by powering its impellers down. This class does not
## itself decide detectability (that is SensorResolution's job, keeping
## detection *rules* out of the data-holding class per ТЗ §8/§48
## data-driven separation) -- it only holds the observer's current belief
## about one target.
class_name SensorContact

const ContactState = preload("res://simulation/contact_state.gd")

## Identity of the observed entity. Duck-typed on purpose (ShipPhysicsState
## or MissileState) -- SensorContact does not care which, only that the
## target exposes .position and .velocity.
var target = null

var state: int = ContactState.Type.UNKNOWN

## Best current estimate (dead-reckoned when state == ESTIMATED).
var estimated_position: Vector3 = Vector3.ZERO
var estimated_velocity: Vector3 = Vector3.ZERO
var estimated_angular_velocity: Vector3 = Vector3.ZERO
var estimated_orientation: Quaternion = Quaternion.IDENTITY
var last_detection_sim_time: float = -INF

## Consecutive sim-seconds this contact has been continuously detected;
## drives the DETECTED -> TRACKED upgrade. Reset to 0 whenever detection
## is lost.
var continuous_detection_s: float = 0.0

## Sim-seconds since detection was lost; drives ESTIMATED -> LOST decay.
## Reset to 0 on every fresh detection.
var time_since_lost_s: float = 0.0


func _init(p_target = null) -> void:
	target = p_target
