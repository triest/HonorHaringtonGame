extends RefCounted
## HullMeshBuilder
##
## Procedural placeholder ship hull mesh, built from the CANON silhouette
## description (ТЗ §7 Ship Representation; CANON_RULES.md "fifth check",
## verified against Honorverse Wiki content 2026-09-18):
##
##   "flattened spindle" -- narrowest at bow/stern (where the impeller
##   rings live), widest amidships, with "hammerhead" flares at the very
##   bow/stern tips on military ships (where chase weapons/point defense/
##   sensors concentrate, since bow/stern are NOT wedge-protected).
##
## This is explicitly a RENDERING-ONLY placeholder, not a specific
## canonical ship class's exact hull (no such geometry is given in the
## books to the precision a mesh needs, and fan art is not an acceptable
## source per §7). It exists so the demo scene shows a recognizably
## Honorverse-shaped silhouette instead of a generic BoxMesh, while a real
## per-class model pipeline is a later Milestone (§7/§51 Assets).
##
## 2026-09-28 (user: "модели кораблей и импеллеров то улучши, а то совсем
## черновик" -- the hull read as a smooth featureless blob/egg): two
## purely cosmetic upgrades on top of the SAME silhouette profile
## (_radius_profile is untouched, so every existing canon-derived shape
## decision stands):
##   1. A superellipse cross-section (_cross_section_unit) instead of a
##      perfect circle/ellipse -- flatter flanks, rounded corners, reads
##      as a built hull rather than a lathe-turned egg. The cardinal
##      (top/bottom/side) extents are UNCHANGED (same max radius_scale=1.0
##      there), so the mesh's overall bounding box is identical to before
##      -- test_hull_mesh_builder.gd's AABB checks still hold exactly.
##   2. Baked-in vertex colouring: a cheap "light from above" shading
##      gradient (dorsal brighter, ventral darker) plus a faint periodic
##      banding along the rings standing in for hull-plate seams. Neither
##      is a citation of a real lighting rig or plating pattern -- both
##      are illustrative surface detail so the procedural hull doesn't
##      read as a single flat-coloured blob under Godot's default lookdev
##      lighting. ShipView must set vertex_color_use_as_albedo=true on the
##      hull material for this to have any visible effect.
class_name HullMeshBuilder

## Rounded-rectangle-ish cross-section exponent: 2.0 would be a perfect
## ellipse (the old behaviour); higher values square off the flanks.
## Kept moderate so the hull still reads as a smooth warship hull, not a
## boxcar.
const CROSS_SECTION_EXPONENT: float = 3.0

## Builds a flattened-spindle hull mesh centered on the local origin, with
## the ship's local -Z as bow (matching attack_geometry.gd's convention)
## and local +Y as dorsal/top (wedge-protected axis).
##
## length_m/max_width_m/max_height_m: overall bounding dimensions.
## rings: number of cross-section rings along the length (mesh resolution).
## segments: number of points around each ring (mesh resolution).
static func build(length_m: float, max_width_m: float, max_height_m: float, rings: int = 22, segments: int = 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_length: float = length_m * 0.5
	var half_width: float = max_width_m * 0.5
	var half_height: float = max_height_m * 0.5

	var ring_points: Array = []  # Array[PackedVector3Array], one per ring
	var ring_colors: Array = []  # Array[PackedColorArray], one per ring
	for ring_i in range(rings + 1):
		var t: float = float(ring_i) / float(rings)  # 0 (bow) .. 1 (stern)
		var signed_t: float = t * 2.0 - 1.0           # -1 (bow) .. 1 (stern)
		var radius_scale: float = _radius_profile(signed_t)
		# Faint hull-plate seam banding every third ring -- purely
		# illustrative surface breakup, not a citation of a real plating
		# layout (see class doc comment).
		var seam: float = 0.95 if ring_i % 3 == 0 else 1.0

		var points := PackedVector3Array()
		var colors := PackedColorArray()
		for seg_i in range(segments):
			var angle: float = TAU * float(seg_i) / float(segments)
			var shape: Vector2 = _cross_section_unit(angle)
			var ex: float = shape.x * half_width * radius_scale
			var ey: float = shape.y * half_height * radius_scale
			var z: float = lerp(-half_length, half_length, t)
			points.append(Vector3(ex, ey, z))
			# Cheap baked "light from above": dorsal (shape.y near 1)
			# brighter, ventral (shape.y near -1) darker -- stands in for
			# a real light-probe/AO bake so the hull doesn't read as one
			# flat tone under a single directional light.
			var shade: float = lerp(0.7, 1.05, (shape.y + 1.0) * 0.5) * seam
			colors.append(Color(shade, shade, shade, 1.0))
		ring_points.append(points)
		ring_colors.append(colors)

	# Stitch rings into quads (as two triangles each).
	for ring_i in range(rings):
		var current: PackedVector3Array = ring_points[ring_i]
		var next: PackedVector3Array = ring_points[ring_i + 1]
		var cur_c: PackedColorArray = ring_colors[ring_i]
		var next_c: PackedColorArray = ring_colors[ring_i + 1]
		for seg_i in range(segments):
			var seg_next: int = (seg_i + 1) % segments
			var a: Vector3 = current[seg_i]
			var b: Vector3 = current[seg_next]
			var c: Vector3 = next[seg_i]
			var d: Vector3 = next[seg_next]
			_add_quad(st, a, b, d, c, cur_c[seg_i], cur_c[seg_next], next_c[seg_next], next_c[seg_i])

	# Bow/stern tip caps (fan triangles into the tip point).
	var bow_tip := Vector3(0, 0, -half_length)
	var stern_tip := Vector3(0, 0, half_length)
	var tip_color := Color(0.85, 0.85, 0.85, 1.0)
	_add_tip_cap(st, ring_points[0], ring_colors[0], bow_tip, tip_color, true)
	_add_tip_cap(st, ring_points[rings], ring_colors[rings], stern_tip, tip_color, false)

	st.generate_normals()
	return st.commit()

## CANON silhouette profile: narrow at both ends (impeller ring locations),
## wide amidships, with a small "hammerhead" flare bump near each tip
## before it closes to a point. Pure function so it can be unit-tested
## without SurfaceTool/rendering (see test_hull_mesh_builder.gd).
static func _radius_profile(signed_t: float) -> float:
	var t: float = clampf(signed_t, -1.0, 1.0)
	var spindle: float = sin(PI * (t + 1.0) * 0.5)  # 0 at |t|=1, 1 at t=0

	# Hammerhead flare: a bump centered around |t| ~ 0.82, tapering to zero
	# at the exact tip and blending into the main spindle body.
	var flare_center: float = 0.82
	var flare_width: float = 0.12
	var dist_from_flare: float = absf(absf(t) - flare_center)
	var flare: float = 0.0
	if dist_from_flare < flare_width:
		flare = (1.0 - dist_from_flare / flare_width) * 0.35

	return clampf(spindle + flare, 0.02, 1.0)  # never fully zero: avoid degenerate tip ring

## Unit-circle-ish cross-section shape (superellipse, see
## CROSS_SECTION_EXPONENT doc above): (cos, sin) at exponent 2.0 would be
## a perfect ellipse; higher exponents flatten the flanks and round the
## corners, reading as a built hull rather than a lathe-turned egg. The
## cardinal points (angle = 0, PI/2, PI, 3PI/2) always land at exactly
## (+/-1, 0) / (0, +/-1) for ANY exponent -- the overall bounding box is
## unchanged from the old pure-circle version. Pure function, unit-
## testable without SurfaceTool (see test_hull_mesh_builder.gd).
static func _cross_section_unit(angle: float) -> Vector2:
	var c: float = cos(angle)
	var s: float = sin(angle)
	var n: float = 2.0 / CROSS_SECTION_EXPONENT
	var x: float = signf(c) * pow(absf(c), n)
	var y: float = signf(s) * pow(absf(s), n)
	return Vector2(x, y)

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

static func _add_tip_cap(st: SurfaceTool, ring: PackedVector3Array, ring_colors: PackedColorArray, tip: Vector3, tip_color: Color, is_bow: bool) -> void:
	var count: int = ring.size()
	for i in range(count):
		var next_i: int = (i + 1) % count
		if is_bow:
			st.set_color(ring_colors[i])
			st.add_vertex(ring[i])
			st.set_color(tip_color)
			st.add_vertex(tip)
			st.set_color(ring_colors[next_i])
			st.add_vertex(ring[next_i])
		else:
			st.set_color(ring_colors[i])
			st.add_vertex(ring[i])
			st.set_color(ring_colors[next_i])
			st.add_vertex(ring[next_i])
			st.set_color(tip_color)
			st.add_vertex(tip)
