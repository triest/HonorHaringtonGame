extends RefCounted
## WedgeMeshBuilder
##
## Procedural placeholder mesh for one impeller wedge band (top or bottom),
## replacing the earlier flat-rectangle placeholder with a shape that
## actually reads as a "wedge" rather than a floating card:
##
## - TENT (V) cross-section: a raised ridge directly over the ship's
##   centerline, sloping down and outward toward the edges -- closer to
##   how the wedge is described as a band of stress bracketing the hull
##   from a generating axis, not a flat sheet floating above it.
## - FLARES toward bow/stern: narrower near amidships, widening toward the
##   bow/stern ends (and slightly beyond the hull's own length), since the
##   generating impeller rings sit at the bow/stern extremes (ТЗ §7/§9)
##   rather than the field being uniform along the hull.
##
## Still explicitly an ILLUSTRATIVE PLACEHOLDER (ASSUMPTIONS.md): no
## canonical cross-section geometry/proportions were found in the sources
## checked this session -- this is an engineering approximation of the
## verbal description ("wedge"-shaped stress band above/below the ship),
## not a citation of exact book geometry.
class_name WedgeMeshBuilder

## sign: +1.0 for the top (dorsal) wedge, -1.0 for the bottom (ventral).
static func build(length_m: float, hull_half_width: float, ridge_height: float, sign: float, rings: int = 20) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_length: float = length_m * 0.5
	# Extend a little past the hull's own bow/stern, since the wedge is a
	# field generated at those extremes, not clipped exactly to hull length.
	var wedge_half_length: float = half_length * 1.15

	var ridge_points: Array = []
	var left_points: Array = []
	var right_points: Array = []

	for i in range(rings + 1):
		var t: float = float(i) / float(rings)          # 0..1
		var signed_t: float = t * 2.0 - 1.0               # -1..1
		var z: float = lerp(-wedge_half_length, wedge_half_length, t)

		var width_scale: float = _width_profile(signed_t)
		var half_width: float = hull_half_width * width_scale

		ridge_points.append(Vector3(0.0, sign * ridge_height, z))
		left_points.append(Vector3(-half_width, sign * ridge_height * 0.12, z))
		right_points.append(Vector3(half_width, sign * ridge_height * 0.12, z))

	for i in range(rings):
		# Two sloped panels per ring segment: ridge->left and ridge->right,
		# forming the V/tent cross-section, stitched along the length.
		_add_quad(st, ridge_points[i], left_points[i], left_points[i + 1], ridge_points[i + 1])
		_add_quad(st, ridge_points[i], ridge_points[i + 1], right_points[i + 1], right_points[i])

	st.generate_normals()
	return st.commit()

## Narrower amidships, flaring toward the bow/stern extremes (where the
## generating impeller rings are, ТЗ §7/§9) -- the OPPOSITE taper from the
## hull's own "flattened spindle" (hull_mesh_builder.gd), which is widest
## amidships. Pure function, unit-testable without SurfaceTool.
static func _width_profile(signed_t: float) -> float:
	var t: float = clampf(absf(signed_t), 0.0, 1.0)
	return lerp(0.35, 1.0, t * t)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
