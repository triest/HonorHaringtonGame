extends RefCounted
## SidewallMeshBuilder
##
## Procedural placeholder mesh for one sidewall panel (ТЗ §16 Sidewalls;
## CLOUD.md §2.1; ship_defense_state.gd, which is the actual source of
## truth for which sidewall is up/functional -- this file only builds
## GEOMETRY, never decides visibility).
##
## Unlike the wedge (wedge_mesh_builder.gd -- a tented band flaring toward
## bow/stern, generated at the impeller rings), sidewalls are CANON-
## described as flanking gravitic walls bracketing the hull on a given
## face, not a raised ridge -- so this is deliberately a FLAT panel, not a
## tent. Two shapes are needed because the two sidewall pairs sit on
## different faces of the ship:
##
## - BROADSIDE (port/starboard): a panel running the length of the hull,
##   standing in the Y (height) x Z (length) plane, facing outward along
##   +/-X. Always potentially up while its condition is above burnout
##   (ship_defense_state.gd: no "raised" flag for these, only condition).
## - BOW/STERN: a panel capping the bow or stern, standing in the X
##   (width) x Y (height) plane, facing along +/-Z. Only shown while
##   explicitly raised (ship_defense_state.gd: bow_sidewall_raised /
##   stern_sidewall_raised), since raising these costs impeller
##   acceleration (CONFIRMED CANON) and is not the default state.
##
## Both are explicitly ILLUSTRATIVE PLACEHOLDERS (ASSUMPTIONS.md): no
## canonical sidewall proportions/geometry were found in the sources
## checked this session -- flat panels are an engineering approximation
## of "gravitic wall bracketing a face", not a citation of exact book
## geometry (same placeholder status as WedgeMeshBuilder/HullMeshBuilder).
class_name SidewallMeshBuilder

## A broadside (port or starboard) sidewall panel: spans the ship's
## length_m along Z, height_m along Y, centered on the hull's vertical
## midpoint and lying flat in the X=0 plane (ShipView positions/offsets it
## to the correct +/-X side; this builder only produces the local shape).
static func build_broadside(length_m: float, height_m: float) -> ArrayMesh:
	# Extend a little past the hull's own bow/stern, mirroring
	# WedgeMeshBuilder's convention, so the panel does not visibly stop
	# short of the hull tips.
	var half_length: float = length_m * 0.5 * 1.05
	var half_height: float = height_m * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st,
		Vector3(0.0, -half_height, -half_length),
		Vector3(0.0, -half_height, half_length),
		Vector3(0.0, half_height, half_length),
		Vector3(0.0, half_height, -half_length))
	st.generate_normals()
	return st.commit()

## A bow or stern sidewall cap: spans width_m along X, height_m along Y,
## lying flat in the Z=0 plane (ShipView positions/offsets it to the
## correct bow (-Z) or stern (+Z) side per attack_geometry.gd's
## -Z=bow convention).
static func build_bow_stern(width_m: float, height_m: float) -> ArrayMesh:
	var half_width: float = width_m * 0.5
	var half_height: float = height_m * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st,
		Vector3(-half_width, -half_height, 0.0),
		Vector3(half_width, -half_height, 0.0),
		Vector3(half_width, half_height, 0.0),
		Vector3(-half_width, half_height, 0.0))
	st.generate_normals()
	return st.commit()

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
