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
## project.godot defines no input actions yet, and adding a full input
## map is out of scope for this minimal vertical-slice camera; §56.1 item
## 5's player-order hotkeys are a separate, later piece of work):
## - Right-mouse-drag: orbit (yaw/pitch) around the pivot.
## - Mouse wheel: zoom in/out.
## - Arrow keys: keyboard-only orbit fallback.
## - +/-: keyboard-only zoom fallback.
##
## Orbits around a PIVOT POINT (set via frame_on(), called by main.gd with
## the same ship-midpoint/spread calculation the old fixed camera used),
## not around the camera's own position -- this is a rendering-only
## convenience node; it never reads or writes simulation state directly
## (§42), only the pivot point main.gd hands it.
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
	var half_fov_rad: float = deg_to_rad(fov * 0.5)
	var required_distance: float = (spread / tan(half_fov_rad)) * 1.6
	distance = required_distance
	_base_distance = required_distance
	far = required_distance * 3.0 + 10000.0

	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	yaw = atan2(view_dir.x, view_dir.z)
	pitch = clampf(asin(clampf(view_dir.y, -1.0, 1.0)), MIN_PITCH, MAX_PITCH)
	_update_transform()

## Pure function: camera offset from the pivot for a given yaw/pitch/
## distance. Y-up, yaw measured from +Z toward +X, matching Godot's
## default -Z-forward convention closely enough for an orbit camera (a
## rendering convenience, not a simulation-facing coordinate system).
## Unit-testable without a scene tree -- see
## simulation/tests/test_orbit_camera.gd.
static func _spherical_offset(yaw: float, pitch: float, distance: float) -> Vector3:
	var horizontal: float = cos(pitch) * distance
	return Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)

func _update_transform() -> void:
	global_position = pivot + _spherical_offset(yaw, pitch, distance)
	look_at(pivot, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * MOUSE_ORBIT_SPEED
		pitch = clampf(pitch + event.relative.y * MOUSE_ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
		_update_transform()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(_base_distance * MIN_DISTANCE_SCALE, distance * MOUSE_ZOOM_STEP)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(_base_distance * MAX_DISTANCE_SCALE, distance / MOUSE_ZOOM_STEP)
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

	if orbit_delta == 0.0 and pitch_delta == 0.0 and zoom_delta == 0.0:
		return

	yaw += orbit_delta * KEY_ORBIT_SPEED * delta
	pitch = clampf(pitch + pitch_delta * KEY_ORBIT_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if zoom_delta != 0.0:
		distance = clampf(distance * (1.0 + zoom_delta * KEY_ZOOM_SPEED * delta), _base_distance * MIN_DISTANCE_SCALE, _base_distance * MAX_DISTANCE_SCALE)
	_update_transform()
