extends RefCounted
## TacticalPlotProjector
##
## Pure geometry: maps a 3D world position to a position on the 2D
## tactical plot (ТЗ §56.2 items A/B -- top-down/God's-eye display).
## Like BeamFxMeshBuilder/SidewallMeshBuilder, this class computes
## SHAPE/GEOMETRY only -- it never decides which contacts exist or what
## they mean (tactical_plot.gd reads already-resolved SimulationWorld.
## sensor_contacts for that, §42). Kept separate purely so the
## world->plot mapping is headless-unit-testable without a live
## Control/Viewport, same pattern as
## simulation/tests/test_beam_fx_mesh_builder.gd.
##
## DISTANCE-COMPRESSION CONVENTION (ASSUMPTIONS.md §56.2, chosen this
## pass, INTERPRETATION): linear radial scale -- `plot_pixel_radius`
## pixels on screen represent `plot_range_m` metres in every direction
## from the plot's origin (normally the player ship's live position).
## A contact farther than `plot_range_m` is CLAMPED to the rim of the
## plot along its true bearing (still visible, at the edge, with
## `clamped == true` returned so the caller can draw an edge indicator)
## rather than disappearing off-plot -- the exact, uncompressed
## `range_m` is always returned alongside the (possibly-clamped) pixel
## offset, so the real canon-scale distance is never lost even when the
## icon position itself is compressed to fit the screen (§56.2 item 2:
## "the DISPLAYED range numbers... must be canon-scale", not the literal
## icon-to-icon pixel distance).
##
## BEARING CONVENTION: 0 rad = world -Z ("north", matching
## attack_geometry.gd's own "-Z = bow/forward" convention for this
## project), increasing CLOCKWISE when viewed from above (+X = 90
## degrees / "east"). This is a fixed north-up plot for this slice, not
## yet heading-relative to the player ship's own facing (ASSUMPTION -- a
## heading-up mode is a plausible future refinement; §56.2's own text
## does not require one).
class_name TacticalPlotProjector

## Returns a Dictionary:
##   plot_offset_px: Vector2 -- offset from the plot's centre pixel,
##     ready to add directly to a screen-space centre point (+X right,
##     +Y down, matching Godot's Control/CanvasItem 2D convention).
##   range_m: float -- the TRUE, uncompressed distance from origin to
##     world_pos, always accurate regardless of clamping.
##   bearing_rad: float -- in [0, TAU), see class doc above.
##   clamped: bool -- true if range_m exceeds plot_range_m, i.e. the
##     returned plot_offset_px was pulled in to the rim rather than
##     reflecting the true (larger) distance.
static func project(world_pos: Vector3, origin: Vector3, plot_range_m: float, plot_pixel_radius: float) -> Dictionary:
	var offset: Vector3 = world_pos - origin
	var planar := Vector2(offset.x, offset.z)
	var range_m: float = planar.length()

	var bearing_rad: float = atan2(offset.x, -offset.z)
	if bearing_rad < 0.0:
		bearing_rad += TAU

	var safe_range_m: float = maxf(plot_range_m, 0.001)
	var scale_px_per_m: float = plot_pixel_radius / safe_range_m
	var clamped: bool = plot_range_m > 0.0 and range_m > plot_range_m
	var plot_dist_px: float = minf(range_m * scale_px_per_m, plot_pixel_radius)

	var direction: Vector2 = Vector2.ZERO
	if range_m > 0.0001:
		direction = planar / range_m

	return {
		"plot_offset_px": direction * plot_dist_px,
		"range_m": range_m,
		"bearing_rad": bearing_rad,
		"clamped": clamped,
	}

## Inverse of `project()`: maps a pixel offset FROM THE PLOT'S CENTRE back
## to a world-space position, given the same origin/plot_range_m/
## plot_pixel_radius the forwards mapping used. ТЗ §56.3 item C ("RMB по
## точке пространства"): this is what turns a mouse click on the plot
## into an actual world-space move-order target point. Exact algebraic
## inverse of the UNCLAMPED case in project() (`plot_offset_px =
## planar_offset * (plot_pixel_radius / plot_range_m)`, planar_offset =
## (offset.x, offset.z)) -- a click outside the plot's own rim (e.g. in
## one of the square Control's corners, which project() itself can never
## produce since it always clamps a contact to the circle) simply
## extrapolates past `plot_range_m`, an honest, unsurprising result for a
## point the player chose to click there, not a bug to special-case.
##
## Returned world position keeps `origin`'s own Y (this plot is a flat,
## single-plane top-down display -- see class doc's BEARING CONVENTION;
## the plot has no notion of altitude to click into, and this project's
## demo ships all maneuver in a single Y-constant plane, see
## player_input.gd's own doc comment).
static func unproject(plot_offset_px: Vector2, origin: Vector3, plot_range_m: float, plot_pixel_radius: float) -> Vector3:
	var safe_radius_px: float = maxf(plot_pixel_radius, 0.001)
	var scale_m_per_px: float = plot_range_m / safe_radius_px
	var planar_m: Vector2 = plot_offset_px * scale_m_per_px
	return origin + Vector3(planar_m.x, 0.0, planar_m.y)
