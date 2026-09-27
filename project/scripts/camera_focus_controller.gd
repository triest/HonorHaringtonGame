extends Node
## CameraFocusController
##
## §56.3 item F: translates the quick-center hotkey (project.godot
## [input] "camera_focus_selection") into a CameraFocus.compute() call
## fed to OrbitCamera.focus_on(). Same convention as PlayerInput
## (scripts/player_input.gd, ТЗ §56.1 item 5): a plain Node added to the
## tree so it can receive _unhandled_input, reading a named Input Map
## action rather than a raw key check (unlike OrbitCamera's own existing
## orbit/zoom controls -- see that file's updated class doc comment for
## why those were left alone).
##
## Split into _unhandled_input (the only Input-touching line) and
## try_focus() (everything else) so a headless test can call try_focus()
## directly with a synthetic world/selection and no InputEvent at all --
## same split as OrderMenuController.try_open(), and same reasoning as
## PlayerInput's own test file (simulation/tests/test_player_input.gd)
## for why _unhandled_input itself is still exercised too, via a
## synthetic InputEventAction (no live window/mouse needed for that
## either).
##
## `camera` is deliberately NOT exercised by this class's own headless
## test with a REAL OrbitCamera instance -- OrbitCamera extends
## Camera3D, and instantiating a Camera3D-derived node outside a live
## scene tree hits the exact same engine-side "not inside tree"
## limitation already logged in test_orbit_camera.gd's own file doc
## comment (confirmed again this pass with a throwaway probe script
## before writing this class, not just assumed). So this file's own test
## exercises try_focus() with `camera = null` (must return false, not
## crash) and CameraFocus.compute() directly and thoroughly (pure, no
## such limitation) -- the actual live "does pressing Home move the
## camera" effect is headless-unverifiable, same honest-gap status as
## every other §56.3 item's live-input effect (B/C/D/E) before a real
## player's own pass.
class_name CameraFocusController

var world: SimulationWorld = null
var selection: SelectionState = null
var camera: OrbitCamera = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_focus_selection"):
		try_focus()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				back()
			KEY_F:
				view_selection(true)
			KEY_F1:
				view_all()
			KEY_F2:
				view_own_squadron()

## Returns true if a focus point was resolved and applied, false if
## there was nothing to focus on (no camera assigned, or CameraFocus.
## compute() came back empty) -- callers may ignore the return value;
## it exists purely to make this testable without inspecting camera
## state.
func try_focus() -> bool:
	if camera == null:
		return false
	if camera.use_floating_origin:
		return view_selection(false)
	var result: Dictionary = CameraFocus.compute(world, selection)
	if result.is_empty():
		return false
	camera.focus_on(result["pivot"], result["spread"])
	# 2026-09-27: keep FOLLOWING what was focused (ships move hundreds of
	# km/s -- a static pivot loses a zoomed-in ship within a second). Ids
	# are captured now, so changing the selection later does not yank the
	# camera; stop_follow() (Esc / command bar) releases it.
	follow_ids = selection.selected_ids.duplicate() if not selection.selected_ids.is_empty() else [selection.designated_target_id]
	camera.follow_provider = Callable(self, "_follow_pivot")
	return true

var follow_ids: Array = []

func stop_follow() -> void:
	follow_ids = []
	if camera != null:
		camera.follow_provider = Callable()

## Centroid of the followed ids still alive (null = nothing to follow).
func _follow_pivot():
	if world == null or follow_ids.is_empty():
		return null
	var c := Vector3.ZERO
	var n: int = 0
	for id in follow_ids:
		var s = world.ships.get(id)
		if s == null:
			s = world.missiles.get(id)
		if s != null:
			c += s.position
			n += 1
	if n == 0:
		return null
	return c / float(n)


# ------------------------------------------------------------------ views
## 2026-09-27 (user: "I want to zoom into a ship at any moment and then go
## back"): named views with a BACK stack. Every view change pushes the
## current camera state; back() (Esc / Backspace / "Назад") flies to the
## previous one. Flights are smooth (OrbitCamera.fly_to) when the live
## floating-origin camera is in use.
const CLOSE_UP_DISTANCE_M: float = 1800.0
const HISTORY_MAX: int = 20
var _history: Array = []

func _snapshot() -> Dictionary:
	return {"pivot": camera.look_point() if camera.has_method("look_point") else camera.pivot, "distance": camera.target_distance if ("target_distance" in camera and camera.target_distance > 0.0) else camera.distance, "yaw": camera.yaw, "pitch": camera.pitch, "follow": follow_ids.duplicate()}

func _push() -> void:
	if camera == null:
		return
	_history.append(_snapshot())
	if _history.size() > HISTORY_MAX:
		_history.pop_front()

func _go(pivot: Vector3, dist: float, ids: Array) -> void:
	follow_ids = ids.duplicate()
	camera.follow_provider = Callable(self, "_follow_pivot") if not ids.is_empty() else Callable()
	if camera.use_floating_origin:
		camera.fly_to(pivot, dist)
	else:
		camera.pivot = pivot
		camera.distance = dist
		camera._update_transform()

## Selected ships (or designated target): close = single-hull close-up
## (only meaningful for one ship; several ships get a framing that fits).
func view_selection(close: bool) -> bool:
	if camera == null or world == null or selection == null:
		return false
	var result: Dictionary = CameraFocus.compute(world, selection)
	if result.is_empty():
		return false
	var ids: Array = selection.selected_ids.duplicate() if not selection.selected_ids.is_empty() else [selection.designated_target_id]
	var dist: float = OrbitCamera._required_distance_for_spread(result["spread"], camera.fov)
	if close and ids.size() == 1:
		dist = CLOSE_UP_DISTANCE_M
	_push()
	_go(result["pivot"], maxf(dist, CLOSE_UP_DISTANCE_M), ids)
	return true

func view_ids(ids: Array, close: bool) -> void:
	if camera == null or world == null or ids.is_empty():
		return
	var pts: Array = []
	for id in ids:
		if world.ships.has(id):
			pts.append(world.ships[id].position)
	if pts.is_empty():
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var spread: float = CameraFocus.MIN_FOCUS_SPREAD_M
	for p in pts:
		spread = maxf(spread, c.distance_to(p))
	var dist: float = CLOSE_UP_DISTANCE_M if (close and ids.size() == 1) else maxf(CLOSE_UP_DISTANCE_M, OrbitCamera._required_distance_for_spread(spread, camera.fov))
	_push()
	_go(c, dist, ids)

func view_own_squadron() -> void:
	if world == null:
		return
	var team: String = ""
	if selection != null and not selection.selected_ids.is_empty():
		team = String(world.teams.get(selection.selected_ids[0], ""))
	if team == "":
		team = String(world.teams.get("alpha", ""))
	var ids: Array = []
	for sid in world.ships.keys():
		if String(world.teams.get(sid, "")) == team and not world.ships[sid].is_wreck:
			ids.append(sid)
	view_ids(ids, false)

func view_all() -> void:
	if camera == null or world == null:
		return
	var pts: Array = []
	for sid in world.ships.keys():
		if not world.ships[sid].is_wreck:
			pts.append(world.ships[sid].position)
	if pts.is_empty():
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var spread: float = 1.0
	for p in pts:
		spread = maxf(spread, c.distance_to(p))
	_push()
	_go(c, OrbitCamera._required_distance_for_spread(spread, camera.fov), [])

func back() -> void:
	if camera == null:
		return
	if _history.is_empty():
		view_all()
		_history.clear()
		return
	var h: Dictionary = _history.pop_back()
	camera.yaw = h["yaw"]
	camera.pitch = h["pitch"]
	_go(h["pivot"], h["distance"], h["follow"])
