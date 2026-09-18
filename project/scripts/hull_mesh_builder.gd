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
class_name HullMeshBuilder

## Builds a flattened-spindle hull mesh centered on the local origin, with
## the ship's local -Z as bow (matching attack_geometry.gd's convention)
## and local +Y as dorsal/top (wedge-protected axis).
##
## length_m/max_width_m/max_height_m: overall bounding dimensions.
## rings: number of cross-section rings along the length (mesh resolution).
## segments: number of points around each ring (mesh resolution).
static func build(length_m: float, max_width_m: float, max_height_m: float, rings: int = 14, segments: int = 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_length: float = length_m * 0.5
	var half_width: float = max_width_m * 0.5
	var half_height: float = max_height_m * 0.5

	var ring_points: Array = []  # Array[PackedVector3Array], one per ring
	for ring_i in range(rings + 1):
		var t: float = float(ring_i) / float(rings)  # 0 (bow) .. 1 (stern)
		var signed_t: float = t * 2.0 - 1.0           # -1 (bow) .. 1 (stern)
		var radius_scale: float = _radius_profile(signed_t)

		var points := PackedVector3Array()
		for seg_i in range(segments):
			var angle: float = TAU * float(seg_i) / float(segments)
			var ex: float = cos(angle) * half_width * radius_scale
			var ey: float = sin(angle) * half_height * radius_scale
			var z: float = lerp(-half_length, half_length, t)
			points.append(Vector3(ex, ey, z))
		ring_points.append(points)

	# Stitch rings into quads (as two triangles each).
	for ring_i in range(rings):
		var current: PackedVector3Array = ring_points[ring_i]
		var next: PackedVector3Array = ring_points[ring_i + 1]
		for seg_i in range(segments):
			var seg_next: int = (seg_i + 1) % segments
			var a: Vector3 = current[seg_i]
			var b: Vector3 = current[seg_next]
			var c: Vector3 = next[seg_i]
			var d: Vector3 = next[seg_next]
			_add_quad(st, a, b, d, c)

	# Bow/stern tip caps (fan triangles into the tip point).
	var bow_tip := Vector3(0, 0, -half_length)
	var stern_tip := Vector3(0, 0, half_length)
	_add_tip_cap(st, ring_points[0], bow_tip, true)
	_add_tip_cap(st, ring_points[rings], stern_tip, false)

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

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

static func _add_tip_cap(st: SurfaceTool, ring: PackedVector3Array, tip: Vector3, is_bow: bool) -> void:
	var count: int = ring.size()
	for i in range(count):
		var next_i: int = (i + 1) % count
		if is_bow:
			st.add_vertex(ring[i])
			st.add_vertex(tip)
			st.add_vertex(ring[next_i])
		else:
			st.add_vertex(ring[i])
			st.add_vertex(ring[next_i])
			st.add_vertex(tip)
