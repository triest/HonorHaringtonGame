extends Node3D
## DEV TOOL: close-up of a single procedural hull, for verifying silhouette
## shape independent of engagement-scale framing (see screenshot_capture.gd
## for the full two-ship scene). Not part of the shipped game.
var _frames_waited: int = 0
const FRAMES_TO_WAIT: int = 10

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-35)) * Basis(Vector3(0, 1, 0), deg_to_rad(40)), Vector3.ZERO)
	key_light.light_energy = 1.6
	add_child(key_light)

	var ship := ShipPhysicsState.new()
	ship.length_m = 500.0
	ship.max_width_m = 90.0
	ship.max_height_m = 60.0
	ship.defense = ShipDefenseState.new()

	var view := ShipView.new()
	view.bind(ship)
	add_child(view)

	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.far = ship.length_m * 20.0
	add_child(camera)
	camera.look_at_from_position(Vector3(ship.length_m * 0.9, ship.length_m * 0.35, ship.length_m * 0.9), Vector3.ZERO, Vector3.UP)

func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited < FRAMES_TO_WAIT:
		return
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = OS.get_environment("SCREENSHOT_OUTPUT_PATH")
	if output_path.is_empty():
		output_path = "user://closeup.png"
	image.save_png(output_path)
	print("SCREENSHOT_SAVED: %s" % output_path)
	get_tree().quit()
