extends RefCounted
## TacticalPlotSelection
##
## Pure geometry helper for ТЗ §56.3 item A ("Multi-select... LMB drag-box
## select multiple contacts"): given already-projected 2D icon positions
## (screen/Control-local pixel coordinates, exactly what
## TacticalPlotProjector.project()'s "plot_offset_px" + the plot's own
## centre already produce) and a click point or drag rectangle, decide
## which icon id(s) are hit. Like TacticalPlotProjector itself, this
## class invents no selection POLICY (what CTRL/SHIFT/plain-click do with
## the result is SelectionState's job, called from tactical_plot.gd) --
## it only answers "which ids are under this point/inside this
## rectangle", so it is headless-unit-testable without a live Control/
## Viewport or a real mouse event, same pattern as
## simulation/tests/test_tactical_plot_projector.gd.
class_name TacticalPlotSelection

## Each icon dictionary: {"id": String, "pos": Vector2, "radius": float}
## (Control-local pixel coordinates, same space as the click point).

## Returns the id of the icon whose centre is CLOSEST to `point` among
## all icons within their own hit radius of it, or "" if none qualify.
## Closest-wins (not first-in-array-wins) so that hit-testing does not
## silently depend on _contacts' insertion order when two icons overlap
## on a crowded plot.
static func hit_test(point: Vector2, icons: Array) -> String:
	var best_id: String = ""
	var best_dist: float = INF
	for icon in icons:
		var dist: float = point.distance_to(icon["pos"])
		if dist <= icon["radius"] and dist < best_dist:
			best_dist = dist
			best_id = icon["id"]
	return best_id

## Returns the ids of every icon whose centre falls within `rect`
## (a Rect2 in the same pixel space as each icon's "pos" -- callers
## should pass an already-normalized/abs() rect since drag direction is
## arbitrary, e.g. built via Rect2(a, b - a).abs()).
static func box_test(rect: Rect2, icons: Array) -> Array:
	var hits: Array = []
	for icon in icons:
		if rect.has_point(icon["pos"]):
			hits.append(icon["id"])
	return hits
