extends RefCounted
## LasingRod
##
## One X-ray lasing rod ejected from a missile's warhead at detonation
## (ТЗ AGENTS.md §21.1, CANON per Honorverse Wiki): rods eject from bays on
## the missile's sides, maneuver independently to a position ~100m ahead of
## the warhead between it and the target, and each fires its own
## independently-aimed beam once the nuclear pulse pumps it via the
## gravity-lens ring.
##
## This is a short-lived resolution-time construct, not a persistent
## simulation entity ticked every frame -- rods exist only at the instant
## of detonation, which matches the canon sequence (eject -> align -> fire
## all happen in the terminal phase, not over an extended tracked flight).
## If a future milestone needs rods to be visible/trackable for a few
## simulation ticks before firing, this class is the natural place to add
## that, but §21.4 leaves the exact timing UNKNOWN, so it is not invented.
class_name LasingRod

var position: Vector3
var damage_potential: float

func _init(p_position: Vector3, p_damage_potential: float) -> void:
	position = p_position
	damage_potential = p_damage_potential
