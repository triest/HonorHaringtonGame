extends RefCounted
## AttackGeometry
##
## Classifies a world-space attack vector (weapon -> target) against a
## target ship's orientation into one of six sectors (ТЗ §10 Wedge
## Orientation / CLOUD.md §"Направление атаки"):
##
##   TOP, BOTTOM, BOW, STERN, PORT, STARBOARD
##
## Ship-local axis convention (ASSUMPTION, documented in ASSUMPTIONS.md):
##   -Z = bow (forward, matches Godot's default "forward" for Node3D/Camera3D)
##   +Z = stern
##   +Y = top (dorsal, wedge-protected)
##   -Y = bottom (ventral, wedge-protected)
##   +X = starboard
##   -X = port
##
## This module does no rendering and knows nothing about wedge/sidewall
## strength — it only answers "which sector did this attack come from",
## per §10: "For every attack, calculate the 3D attack vector relative to
## the target's orientation... Distance alone is insufficient."
class_name AttackGeometry

enum Sector { TOP, BOTTOM, BOW, STERN, PORT, STARBOARD }

## attacker_position, target_position: world-space positions.
## target_orientation: the target ship's orientation quaternion.
## Returns the Sector the attack vector approaches from, in the target's
## local frame.
static func classify(attacker_position: Vector3, target_position: Vector3, target_orientation: Quaternion) -> Sector:
	var world_dir := (attacker_position - target_position)
	if world_dir.length_squared() <= 0.0:
		# Degenerate case (same position); treat as bow by convention rather
		# than crashing on normalize().
		return Sector.BOW
	world_dir = world_dir.normalized()

	# Rotate the world-space direction into the target's local frame by
	# applying the inverse of its orientation.
	var local_dir: Vector3 = target_orientation.inverse() * world_dir

	# Pick the dominant axis of the local-space direction to the attacker.
	var ax := absf(local_dir.x)
	var ay := absf(local_dir.y)
	var az := absf(local_dir.z)

	if ay >= ax and ay >= az:
		return Sector.TOP if local_dir.y > 0.0 else Sector.BOTTOM
	elif ax >= ay and ax >= az:
		return Sector.STARBOARD if local_dir.x > 0.0 else Sector.PORT
	else:
		# local -Z is bow: attacker in the -Z direction from the target
		# means the attack is arriving from the bow.
		return Sector.BOW if local_dir.z < 0.0 else Sector.STERN

static func sector_name(sector: Sector) -> String:
	match sector:
		Sector.TOP: return "TOP"
		Sector.BOTTOM: return "BOTTOM"
		Sector.BOW: return "BOW"
		Sector.STERN: return "STERN"
		Sector.PORT: return "PORT"
		Sector.STARBOARD: return "STARBOARD"
	return "UNKNOWN"
