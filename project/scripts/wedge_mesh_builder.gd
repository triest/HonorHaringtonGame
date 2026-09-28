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
##
## 2026-09-28 (user: "модели кораблей и импеллеров то улучши, а то совсем
## черновик"): the previous flat, uniform-alpha fill read as a solid grey
## triangle, not a stress band of energy. Baked-in vertex colours now
## carry TWO gradients so ShipView's material (vertex_color_use_as_albedo
## + additive blending) renders it as a glowing band instead of a flat
## card:
##   - ridge->edge: brightest/most opaque along the centre ridge, fading
##     toward the flanks (a cross-section brightness falloff, not a flat
##     fill).
##   - length-wise: brighter near the bow/stern ends, where the field is
##     actually generated (the impeller rings), dimmer amidships -- a
##     direct visual echo of this file's own "generated at the rings, not
##     uniform along the hull" reasoning above, not a new claim.
## Positions/AABB are completely unchanged by this -- colour only.
class_name WedgeMeshBuilder

## Ridge (bright core) and edge (dim flank) vertex colours. Alpha carries
## most of the falloff since the material blends additively; RGB stays
## close to white so ShipView's base albedo_color supplies the actual hue.
const RIDGE_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.03)
## Length-wise brightness multiplier range: dim amidships, bright at the
## bow/stern generating ends.
const LENGTHWISE_DIM_MIN: float = 0.35

## sign: +1.0 for the top (dorsal) wedge, -1.0 for the bottom (ventral).
static func build(length_m: float, hull_half_width: float, ridge_height: float, sign: float, rings: int = 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_length: float = length_m * 0.5
	# Extend a little past the hull's own bow/stern, since the wedge is a
	# field generated at those extremes, not clipped exactly to hull length.
	var wedge_half_length: float = half_length * 1.15

	var ridge_points: Array = []
	var left_points: Array = []
	var right_points: Array = []
	var ridge_colors: Array = []
	var edge_colors: Array = []

	for i in range(rings + 1):
		var t: float = float(i) / float(rings)          # 0..1
		var signed_t: float = t * 2.0 - 1.0               # -1..1
		var z: float = lerp(-wedge_half_length, wedge_half_length, t)

		var width_scale: float = _width_profile(signed_t)
		var half_width: float = hull_half_width * width_scale
		var length_glow: float = _lengthwise_glow(signed_t)

		ridge_points.append(Vector3(0.0, sign * ridge_height, z))
		left_points.append(Vector3(-half_width, sign * ridge_height * 0.12, z))
		right_points.append(Vector3(half_width, sign * ridge_height * 0.12, z))
		ridge_colors.append(_scaled(RIDGE_COLOR, length_glow))
		edge_colors.append(_scaled(EDGE_COLOR, length_glow))

	for i in range(rings):
		# Two sloped panels per ring segment: ridge->left and ridge->right,
		# forming the V/tent cross-section, stitched along the length.
		_add_quad(st, ridge_points[i], left_points[i], left_points[i + 1], ridge_points[i + 1],
			ridge_colors[i], edge_colors[i], edge_colors[i + 1], ridge_colors[i + 1])
		_add_quad(st, ridge_points[i], ridge_points[i + 1], right_points[i + 1], right_points[i],
			ridge_colors[i], ridge_colors[i + 1], edge_colors[i + 1], edge_colors[i])

	st.generate_normals()
	return st.commit()

## Narrower amidships, flaring toward the bow/stern extremes (where the
## generating impeller rings are, ТЗ §7/§9) -- the OPPOSITE taper from the
## hull's own "flattened spindle" (hull_mesh_builder.gd), which is widest
## amidships. Pure function, unit-testable without SurfaceTool.
static func _width_profile(signed_t: float) -> float:
	var t: float = clampf(absf(signed_t), 0.0, 1.0)
	return lerp(0.35, 1.0, t * t)

## Brightness multiplier along the wedge's length: dim amidships, brighter
## toward the bow/stern ends -- see class doc comment. Pure function,
## unit-testable without SurfaceTool.
static func _lengthwise_glow(signed_t: float) -> float:
	var t: float = clampf(absf(signed_t), 0.0, 1.0)
	return lerp(LENGTHWISE_DIM_MIN, 1.0, t * t)

static func _scaled(c: Color, brightness: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * brightness)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(cd)
	st.add_vertex(d)
