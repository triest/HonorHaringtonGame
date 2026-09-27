extends Camera3D
## OrbitCamera
##
## Player-controllable orbit/zoom camera (ТЗ §56.1 item 1: "One Godot
## scene with a camera the player can see the battle through (free/orbit
## camera is enough -- no cinematic camera work)"). Replaces the earlier
## fixed camera transform that main.gd computed once at scene start and
## never let the player change.
##
## Controls (deliberately raw Input/key checks, not an Input Map action --
## project.godot did not define any input actions when this class was
## first written; §56.1 item 5 has since added a real [input] map for
## per-ship order hotkeys, and §56.3 item F (see camera_focus_controller.gd)
## follows that newer convention for the quick-center hotkey specifically,
## but the orbit/zoom controls below are left as raw Input checks rather
## than being retrofitted into named actions -- out of scope for item F,
## which only needed a NEW control, not a rewrite of this file's existing
## ones):
## - Right-mouse-drag: orbit (yaw/pitch) around the pivot.
## - Mouse wheel: zoom in/out.
## - Arrow keys: keyboard-only orbit fallback.
## - +/-: keyboard-only zoom fallback.
##
## Orbits around a PIVOT POINT (set via frame_on(), called by main.gd with
## the same ship-midpoint/spread calculation the old fixed camera used),
## not around the camera's own position -- this is a rendering-only
## convenience node; it never reads or writes simulation state directly
## (§42), only the pivot point main.gd/CameraFocusController hand it.
class_name OrbitCamera

var pivot: Vector3 = Vector3.ZERO
var distance: float = 10000.0
var yaw: float = 0.0    # radians, around Y, measured from +Z
var pitch: float = 0.4  # radians, elevation above the XZ plane

var _base_distance: float = 10000.0

const MIN_PITCH: float = -1.396  # -80 degrees; avoid gimbal flip at the poles
const MAX_PITCH: float = 1.396   # +80 degrees
const MIN_DISTANCE_SCALE: float = 0.05
const MAX_DISTANCE_SCALE: float = 20.0
const MOUSE_ORBIT_SPEED: float = 0.005   # radians per pixel of mouse motion
const MOUSE_ZOOM_STEP: float = 0.9       # multiplicative zoom per wheel notch
const KEY_ORBIT_SPEED: float = 1.2       # radians/sec, keyboard fallback
const KEY_ZOOM_SPEED: float = 1.5        # fraction/sec, keyboard fallback

## Called once by main.gd with the same midpoint/spread it already
## computes from live ship positions. Sets up the pivot and an initial
## viewing angle/distance that reproduces the old fixed camera's framing
## exactly, so the first frame looks unchanged -- only what happens AFTER
## that first frame (player input) is new.
func frame_on(new_pivot: Vector3, spread: float) -> void:
	pivot = new_pivot
	fov = 60.0
	var required_distance: float = _required_distance_for_spread(spread, fov)
	distance = required_distance
	_base_distance = required_distance
	far = _required_far_for_base_distance(required_distance)

	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	yaw = atan2(view_dir.x, view_dir.z)
	pitch = clampf(asin(clampf(view_dir.y, -1.0, 1.0)), MIN_PITCH, MAX_PITCH)
	_update_transform()

## §56.3 item F (§1.10.1 "быстро центрироваться на выбранном корабле,
## группе или контакте"): re-centers the pivot and re-fits the zoom
## distance to `spread` WITHOUT touching yaw/pitch -- unlike frame_on()
## (the one-time initial framing shot, which also picks a starting
## viewing angle), a quick-center keeps whatever angle the player has
## already orbited to; only WHERE the camera is looking and HOW FAR
## changes. Also rebases `_base_distance` to the new framing distance, so
## the player's subsequent scroll-wheel/keyboard zoom range (MIN/MAX_
## DISTANCE_SCALE) is relative to whatever was just focused on (a single
## ship, say), not the original whole-battle framing from frame_on() --
## otherwise a focus on one ship would still only let the player zoom
## across the ORIGINAL battle-wide distance range, which defeats the
## point of focusing.
##
## `far` is only ever GROWN here, never shrunk (§1.10.2 "дальние объекты
## автоматически остаются видимыми"): focusing in tight on one ship must
## not clip other, farther-out contacts out of the 3D view entirely.
func focus_on(new_pivot: Vector3, spread: float) -> void:
	pivot = new_pivot
	var required_distance: float = _required_distance_for_spread(spread, fov)
	if use_floating_origin:
		required_distance = maxf(required_distance, 1500.0)
	distance = required_distance
	_base_distance = required_distance
	far = maxf(far, _required_far_for_base_distance(required_distance))
	_update_transform()

## Pure function, extracted from frame_on()/focus_on() so both share the
## exact same "distance needed for this fov to frame this spread" formula
## instead of two copies drifting apart. MIN_FOCUS_SPREAD_M-scale floor on
## `spread` lives in the caller (CameraFocus.compute), not here -- this
## function only does the trig, it doesn't know why a caller might hand
## it a near-zero spread (see camera_focus.gd's own doc comment).
static func _required_distance_for_spread(spread: float, fov_deg: float) -> float:
	var half_fov_rad: float = deg_to_rad(fov_deg * 0.5)
	return (spread / tan(half_fov_rad)) * 1.6

## §56.3 item G (§1.10.3 zoom levels -- "переход между уровнями должен
## происходить исключительно изменением масштаба камеры"): BUG this pass
## fixes -- `far` used to be sized off `required_distance` alone (a fixed
## 3x multiplier), but the player's actual reachable zoom-out distance is
## `_base_distance * MAX_DISTANCE_SCALE` (20x), not 3x. Once a battle's
## initial framing spread was large enough, scrolling all the way out
## pushed the camera PAST its own far clip plane -- the entire 3D view
## went blank (everything clipped, not just "distant contacts lost"),
## silently breaking the FLEET-VIEW extreme of zooming out. Sizing far
## off the same MAX_DISTANCE_SCALE the zoom clamp itself uses (with a
## 1.2x safety margin so the camera is never sitting exactly ON the far
## plane) guarantees distance < far at every reachable zoom step, for
## both the whole-battle frame_on() shot and a focus_on() quick-center
## onto a small selection (whose own max-zoom-out distance is smaller,
## but still must not exceed ITS far -- far only ever grows via maxf() at
## the call site, never shrinks, so an earlier wide framing's far is kept
## if it was already bigger).
static func _required_far_for_base_distance(base_distance: float) -> float:
	return base_distance * MAX_DISTANCE_SCALE * 1.2 + 10000.0

## Pure function: camera offset from the pivot for a given yaw/pitch/
## distance. Y-up, yaw measured from +Z toward +X, matching Godot's
## default -Z-forward convention closely enough for an orbit camera (a
## rendering convenience, not a simulation-facing coordinate system).
## Unit-testable without a scene tree -- see
## simulation/tests/test_orbit_camera.gd.
static func _spherical_offset(yaw: float, pitch: float, distance: float) -> Vector3:
	var horizontal: float = cos(pitch) * distance
	return Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)

## 2026-09-27 live game only (main.gd turns it on; default off keeps every
## existing test's pivot+offset expectations): floating render origin +
## absolute zoom limits, so the player can zoom from the whole
## multi-million-km battle down to a single 500 m hull. See RenderOrigin.
var use_floating_origin: bool = false
const ABS_MIN_DISTANCE_M: float = 350.0
const ABS_MAX_DISTANCE_M: float = 4.0e10
## Optional per-frame pivot provider (Callable returning Vector3 or null):
## CameraFocusController sets it to "centroid of the followed ships" so the
## camera stays on a ship moving at hundreds of km/s.
var follow_provider: Callable = Callable()

func _min_distance() -> float:
	return ABS_MIN_DISTANCE_M if use_floating_origin else _base_distance * MIN_DISTANCE_SCALE

func _max_distance() -> float:
	return ABS_MAX_DISTANCE_M if use_floating_origin else _base_distance * MAX_DISTANCE_SCALE

## 2026-09-27 (user: "zoom into a ship at any moment, then go back"):
## smooth camera flights. fly_to() animates distance (log-space) and the
## pivot (a decaying offset from the old look-at point) instead of
## jumping, and the mouse wheel sets a smoothed target distance.
var target_distance: float = -1.0
var _pivot_offset: Vector3 = Vector3.ZERO
## Fixed-duration eased flight (smoothstep), so a jump across millions of
## km lands exactly, in the same time as a short one.
const FLY_TIME_S: float = 0.9
const WHEEL_TIME_S: float = 0.2
var _fly_t: float = 1.0
var _fly_dur: float = FLY_TIME_S
var _fly_start_offset: Vector3 = Vector3.ZERO
var _fly_start_dist: float = 1.0

func fly_to(new_pivot: Vector3, new_distance: float) -> void:
	_pivot_offset = (pivot + _pivot_offset) - new_pivot
	pivot = new_pivot
	_start_flight(clampf(new_distance, _min_distance(), _max_distance()), FLY_TIME_S)

func _start_flight(new_target: float, dur: float) -> void:
	target_distance = new_target
	_fly_start_offset = _pivot_offset
	_fly_start_dist = distance
	_fly_t = 0.0
	_fly_dur = dur

func look_point() -> Vector3:
	return pivot + _pivot_offset

func _update_transform() -> void:
	if use_floating_origin:
		RenderOrigin.origin = pivot + _pivot_offset
		# Depth range follows the zoom (near/far ratio ~1e5): a 500 m hull
		# seen from 2 km must not share a depth buffer with a far plane at
		# 1e11 m (that made hulls vanish entirely). Anything farther than
		# `far` is sub-pixel anyway; BattleOverlay's screen-space symbols
		# (which do not depend on the far plane) show it instead.
		near = clampf(distance * 0.001, 0.5, 1.0e5)
		far = clampf(distance * 100.0, 1.0e5, 1.0e10)
		global_position = _spherical_offset(yaw, pitch, distance)
		look_at(Vector3.ZERO, Vector3.UP)
		return
	global_position = pivot + _spherical_offset(yaw, pitch, distance)
	look_at(pivot, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * MOUSE_ORBIT_SPEED
		pitch = clampf(pitch + event.relative.y * MOUSE_ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
		_update_transform()
	elif event is InputEventMouseButton and event.pressed:
		if use_floating_origin and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var base: float = target_distance if target_distance > 0.0 else distance
			var f: float = 0.7 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.7
			_start_flight(clampf(base * f, _min_distance(), _max_distance()), WHEEL_TIME_S)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(_min_distance(), distance * MOUSE_ZOOM_STEP)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(_max_distance(), distance / MOUSE_ZOOM_STEP)
			_update_transform()

func _process(delta: float) -> void:
	var orbit_delta: float = 0.0
	var pitch_delta: float = 0.0
	if Input.is_key_pressed(KEY_LEFT):
		orbit_delta -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		orbit_delta += 1.0
	if Input.is_key_pressed(KEY_UP):
		pitch_delta += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pitch_delta -= 1.0

	var zoom_delta: float = 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom_delta -= 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom_delta += 1.0

	var following: bool = false
	if follow_provider.is_valid():
		var p = follow_provider.call()
		if p != null:
			pivot = p
			following = true
	if use_floating_origin and _fly_t < 1.0:
		_fly_t = minf(1.0, _fly_t + delta / maxf(_fly_dur, 0.001))
		var e: float = smoothstep(0.0, 1.0, _fly_t)
		if target_distance > 0.0:
			distance = exp(lerpf(log(_fly_start_dist), log(target_distance), e))
		# Offset shrinks on a log scale too, so a millions-of-km hop reads
		# as a flight rather than an instant cut followed by a long crawl.
		var start_len: float = _fly_start_offset.length()
		if start_len > 1.0:
			var end_len: float = 1.0
			var cur_len: float = exp(lerpf(log(start_len), log(end_len), e))
			_pivot_offset = _fly_start_offset / start_len * cur_len
		if _fly_t >= 1.0:
			_pivot_offset = Vector3.ZERO
			if target_distance > 0.0:
				distance = target_distance
			target_distance = -1.0
	if orbit_delta == 0.0 and pitch_delta == 0.0 and zoom_delta == 0.0:
		if following or use_floating_origin:
			_update_transform()
		return

	yaw += orbit_delta * KEY_ORBIT_SPEED * delta
	pitch = clampf(pitch + pitch_delta * KEY_ORBIT_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if zoom_delta != 0.0:
		distance = clampf(distance * (1.0 + zoom_delta * KEY_ZOOM_SPEED * delta), _min_distance(), _max_distance())
	_update_transform()
