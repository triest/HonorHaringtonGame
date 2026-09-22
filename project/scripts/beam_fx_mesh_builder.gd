extends RefCounted
## BeamFxMeshBuilder
##
## Procedural placeholder mesh for one energy-weapon beam effect (ТЗ
## §56.1 item 3: "a line/beam for energy weapons ... purely so a player
## can SEE combat happening"). Pure GEOMETRY only -- like
## SidewallMeshBuilder/WedgeMeshBuilder, this file never decides whether
## a shot happened or what it hit; WeaponFx (scripts/weapon_fx.gd) reads
## already-resolved SimulationWorld.last_tick_weapon_shots and only uses
## this to build the visible shape.
##
## Built in LOCAL space along -Z, from z=0 (muzzle end) to z=-length_m
## (target end), centered on X/Y -- matches attack_geometry.gd's own
## "-Z = bow/forward" convention, so WeaponFx can position the node at
## the attacker and orient it with Node3D.look_at(target) (which points
## local -Z at the look_at target) with no extra sign-flip math. Two
## crossed thin quads
## (an "X" cross-section), not a cylinder, so the beam still reads as a
## line from any camera angle without needing a billboard shader --
## explicitly the same "illustrative placeholder, not canon-accurate"
## status as every other mesh builder in scripts/ (ASSUMPTIONS.md).
class_name BeamFxMeshBuilder

static func build(length_m: float, width_m: float) -> ArrayMesh:
	var half_width: float = width_m * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Quad 1: lies in the X-Z plane (facing +/-Y).
	_add_quad(st,
		Vector3(-half_width, 0.0, 0.0),
		Vector3(half_width, 0.0, 0.0),
		Vector3(half_width, 0.0, -length_m),
		Vector3(-half_width, 0.0, -length_m))
	# Quad 2: lies in the Y-Z plane (facing +/-X), crossed with quad 1 so
	# the beam reads as a line from any horizontal viewing angle.
	_add_quad(st,
		Vector3(0.0, -half_width, 0.0),
		Vector3(0.0, half_width, 0.0),
		Vector3(0.0, half_width, -length_m),
		Vector3(0.0, -half_width, -length_m))
	st.generate_normals()
	return st.commit()

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
