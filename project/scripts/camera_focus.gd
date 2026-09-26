extends RefCounted
## CameraFocus
##
## §56.3 item F ("быстро центрироваться на выбранном корабле, группе или
## контакте", §1.10.1): pure helper that turns the current SelectionState
## into a (pivot, spread) pair for OrbitCamera.focus_on() -- kept as a
## static, world/selection-argument function (not a method on
## SelectionState or a new node) so it stays headless-unit-testable
## without a scene tree, same convention as TacticalPlotProjector/
## TacticalPlotSelection (§42: this class computes a pure geometric
## answer, it never touches `world` beyond reading positions, and it
## invents no new "what is selected" concept of its own).
##
## Resolves ids SelectionState already tracks (selected_ids /
## designated_target_id) to REAL Vector3 positions via world.ships/
## world.missiles -- true positions, not sensor-contact estimates. The
## command camera is a god's-eye view over the whole battle (§1.10.1:
## "камера не привязана к кабине или корпусу корабля"), not fog-of-war
## limited the way TacticalPlot's contact rendering is; main.gd.
## _frame_camera_on_ships already reads world.ships[...].position
## directly for this same reason, so this is consistent with the
## existing initial-framing code, not a new exception.
##
## PRIORITY when both a selection and a designated target exist
## (ASSUMPTION, logged in ASSUMPTIONS.md "§56.3 item F"): the player's
## OWN `selected_ids` wins over `designated_target_id` -- centering on
## "what I'm commanding" is the more useful default when both are
## present (e.g. mid-order-menu with a target designated); the
## designated hostile target is only used as the centering point when
## there is no own-ship/group selection at all, e.g. the player wants to
## eyeball an enemy contact before selecting anything of their own.
class_name CameraFocus

## Floor on the returned "spread" so a single-ship focus never asks
## OrbitCamera to fit a zero-size box (which would put the camera AT the
## pivot -- a degenerate distance of 0). Not a claim about any specific
## ship class's actual length_m (ship_factory.gd/ARCHITECTURE.md own
## that); just large enough that a lone-ship quick-center still leaves
## the ship readably framed rather than filling the whole screen.
const MIN_FOCUS_SPREAD_M: float = 400.0

## Returns {"pivot": Vector3, "spread": float}, or {} if nothing
## resolvable is currently selected/designated -- callers (see
## CameraFocusController.try_focus()) should treat {} as "nothing to
## focus on, leave the camera exactly where it is" rather than a crash or
## a fallback to some other point.
static func compute(world: SimulationWorld, selection: SelectionState) -> Dictionary:
	if world == null or selection == null:
		return {}

	var ids: Array = selection.selected_ids
	if ids.is_empty() and selection.has_designated_target():
		ids = [selection.designated_target_id]
	if ids.is_empty():
		return {}

	var positions: Array = []
	for id in ids:
		var resolved = _resolve_position(world, id)
		if resolved != null:
			positions.append(resolved)
	if positions.is_empty():
		return {}

	var centroid: Vector3 = Vector3.ZERO
	for p in positions:
		centroid += p
	centroid /= positions.size()

	var spread: float = MIN_FOCUS_SPREAD_M
	for p in positions:
		spread = maxf(spread, centroid.distance_to(p))

	return {"pivot": centroid, "spread": spread}

## `id` may name a ship (world.ships) or a missile (world.missiles) --
## the only two kinds of id SelectionState/TacticalPlot ever register
## (see tactical_plot.gd's _register_icon call sites: one per ship
## contact, one per missile contact, plus the pov ship's own id). Returns
## null (not Vector3.ZERO -- a real position at the origin must not be
## silently treated as "unresolvable") if `id` matches neither.
static func _resolve_position(world: SimulationWorld, id: String):
	if world.ships.has(id):
		return world.ships[id].position
	if world.missiles.has(id):
		return world.missiles[id].position
	return null
