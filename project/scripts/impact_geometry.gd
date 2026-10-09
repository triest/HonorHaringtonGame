extends RefCounted
## ImpactGeometry
##
## Pure, static, render-side geometry for impact feedback (ТЗ §42: no
## simulation state is read or written). Answers one question: "where on THIS
## ship's wedge / sidewall panel / hull does a strike that arrived along this
## bearing show up?" -- in the ship's local frame (-Z bow, +X starboard, +Y top,
## AttackGeometry convention), so records captured from the simulation can be
## drawn anywhere without touching live objects.
##
## Shapes mirror what ShipView actually builds (hull = flattened spindle, here
## the ellipsoid with the same extents; wedge = WedgeMeshBuilder tent;
## sidewalls = SidewallMeshBuilder panels), so effects sit on the visible
## geometry rather than floating beside it.
class_name ImpactGeometry

const AttackGeometry = preload("res://simulation/attack_geometry.gd")
const MissileResolution = preload("res://simulation/missile_resolution.gd")
const WedgeMeshBuilder = preload("res://scripts/wedge_mesh_builder.gd")

## Dimension bundle shared by every helper. Same numbers ShipView uses for its
## wedge (1.1 x width, 0.9 x height, 1.15 x half length) and panels (0.55 x width).
static func dims_for(length_m: float, width_m: float, height_m: float) -> Dictionary:
	return {
		"half_length": length_m * 0.5,
		"half_width": width_m * 0.5,
		"half_height": height_m * 0.5,
		"wedge_half_length": length_m * 0.5 * 1.15,
		"wedge_half_width": width_m * 1.1,
		"ridge_height": height_m * 0.9,
		"broadside_offset": width_m * 0.55,
	}

## Strike point of a rod/beam on the wedge: the bearing is intersected with the
## wedge's mid surface, clamped to its footprint, then dropped onto the V-shaped
## surface (ridge on the centreline, low at the flanks).
static func wedge_hit_center_local(rod_local: Vector3, wedge_half_length: float, hull_half_width: float, ridge_height: float) -> Vector3:
	var dir: Vector3 = _safe_dir(rod_local)
	var sign_y: float = 1.0 if dir.y >= 0.0 else -1.0
	var t: float = (ridge_height * 0.5) / maxf(absf(dir.y), 0.05)
	var z: float = clampf(dir.z * t, -wedge_half_length, wedge_half_length)
	var half_w: float = hull_half_width * WedgeMeshBuilder._width_profile(z / maxf(wedge_half_length, 0.001))
	var x: float = clampf(dir.x * t, -half_w, half_w)
	var edge_fraction: float = clampf(absf(x) / maxf(half_w, 0.001), 0.0, 1.0)
	var y: float = sign_y * lerpf(ridge_height, ridge_height * 0.12, edge_fraction)
	return Vector3(x, y, z)

## Strike point on a sidewall panel, in SHIP-local coordinates. PORT/STARBOARD
## are the flat broadside planes at x = -/+broadside_offset; BOW/STERN the
## end planes at z = -/+half_length. Any other sector returns the hull point.
static func sidewall_hit_center_local(rod_local: Vector3, sector: int, dims: Dictionary) -> Vector3:
	var dir: Vector3 = _safe_dir(rod_local)
	var hh: float = dims["half_height"]
	match sector:
		AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD:
			var side: float = 1.0 if sector == AttackGeometry.Sector.STARBOARD else -1.0
			var t: float = dims["broadside_offset"] / maxf(absf(dir.x), 0.05)
			var panel_half_length: float = dims["half_length"] * 1.05
			return Vector3(side * dims["broadside_offset"], clampf(dir.y * t, -hh, hh), clampf(dir.z * t, -panel_half_length, panel_half_length))
		AttackGeometry.Sector.BOW, AttackGeometry.Sector.STERN:
			var end: float = 1.0 if sector == AttackGeometry.Sector.STERN else -1.0
			var t2: float = dims["half_length"] / maxf(absf(dir.z), 0.05)
			return Vector3(clampf(dir.x * t2, -dims["half_width"], dims["half_width"]), clampf(dir.y * t2, -hh, hh), end * dims["half_length"])
		_:
			return hull_surface_point_local(rod_local, dims)

## Point where the bearing meets the hull ellipsoid (semi-axes = half extents).
static func hull_surface_point_local(rod_local: Vector3, dims: Dictionary) -> Vector3:
	var dir: Vector3 = _safe_dir(rod_local)
	var a: float = maxf(dims["half_width"], 0.001)
	var b: float = maxf(dims["half_height"], 0.001)
	var c: float = maxf(dims["half_length"], 0.001)
	var k: float = sqrt(pow(dir.x / a, 2.0) + pow(dir.y / b, 2.0) + pow(dir.z / c, 2.0))
	return dir / maxf(k, 0.000001)

## Outward unit normal of the hull ellipsoid at `point` (for scorch marks, vents).
static func hull_normal_local(point: Vector3, dims: Dictionary) -> Vector3:
	var a: float = maxf(dims["half_width"], 0.001)
	var b: float = maxf(dims["half_height"], 0.001)
	var c: float = maxf(dims["half_length"], 0.001)
	var n := Vector3(point.x / (a * a), point.y / (b * b), point.z / (c * c))
	return n.normalized() if n.length_squared() > 0.0 else Vector3.UP

## Where a strike of `outcome` (MissileResolution.Outcome) from `sector`
## (AttackGeometry.Sector, -1 = unknown) along `rod_local` is drawn.
static func strike_point_local(outcome: int, sector: int, rod_local: Vector3, dims: Dictionary) -> Vector3:
	match outcome:
		MissileResolution.Outcome.WEDGE_BLOCKED:
			return wedge_hit_center_local(rod_local, dims["wedge_half_length"], dims["wedge_half_width"], dims["ridge_height"])
		MissileResolution.Outcome.SIDEWALL_ATTENUATED:
			return sidewall_hit_center_local(rod_local, sector, dims)
		_:
			return hull_surface_point_local(rod_local, dims)

## World-space size covering `pixels` screen pixels at `world_pos` as seen by the
## viewport's current camera -- keeps thin lines and small particles visible at
## engagement ranges of millions of kilometres. Falls back to `fallback` when
## there is no camera (headless).
static func world_size_for_pixels(viewport: Viewport, world_pos: Vector3, pixels: float, fallback: float = 5.0) -> float:
	if viewport == null:
		return fallback
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null:
		return fallback
	var dist: float = cam.global_position.distance_to(world_pos)
	var viewport_h: float = maxf(viewport.get_visible_rect().size.y, 1.0)
	var per_pixel: float = 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / viewport_h
	return maxf(per_pixel * pixels, 1.0)

static func _safe_dir(v: Vector3) -> Vector3:
	return v.normalized() if v.length_squared() > 0.0 else Vector3.UP
