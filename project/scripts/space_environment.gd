extends RefCounted
## SpaceEnvironment
##
## Builds (and applies) the cinematic look for the battle scene: HDR glow for
## beams/plumes/flashes, ACES-style tonemapping, a restrained dust fog and a
## dark ambient. Pure rendering configuration (ТЗ §42) -- it touches only
## Environment / WorldEnvironment resources, never the simulation.
##
## Rendering method: written for Forward+ (the project default, see
## project.godot). Volumetric fog is Forward+ only and is silently skipped on
## Compatibility; glow and tonemapping work on both. Everything is a plain
## property assignment, so the same values can be set by hand in the Inspector
## (see the deployment checklist in CHANGELOG.md / the chat summary).
class_name SpaceEnvironment

## Quality presets for the optional features.
enum Quality { LOW, MEDIUM, HIGH }

## Returns a fresh Environment configured for deep space.
static func build(quality: int = Quality.MEDIUM, volumetric_fog: bool = true) -> Environment:
	var env := Environment.new()

	# --- Background / ambient: near-black, a hint of blue so shadowed hulls keep form.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.022, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.13, 0.15, 0.2, 1.0)
	env.ambient_light_energy = 0.5

	# --- Tonemapping: ACES keeps saturated neon beams from clipping to white.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# --- Glow / bloom: HDR threshold so only genuinely bright things bloom.
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.8
	env.glow_strength = 1.1
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	# Mid-sized soft levels for a filmic halo, widest level for a faint haze.
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.set_glow_level(6, 0.3)

	# --- Colour grading: slight contrast/saturation lift for punchy VFX.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	# --- Optional screen-space polish (Forward+). Kept cheap at LOW.
	env.ssao_enabled = quality >= Quality.HIGH
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6

	# --- Volumetric fog: faint, local "dust" so beams and plumes have air to
	# scatter in. Space is a vacuum; this is a stylistic choice, kept very low
	# density so it reads as depth, not as atmosphere.
	if volumetric_fog and quality >= Quality.MEDIUM:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0006 if quality == Quality.MEDIUM else 0.0009
		env.volumetric_fog_albedo = Color(0.45, 0.55, 0.8, 1.0)
		env.volumetric_fog_emission = Color(0.01, 0.015, 0.03, 1.0)
		env.volumetric_fog_emission_energy = 0.6
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_length = 150.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0

	return env

## Applies the look to `world_environment` (creating nothing else). If the node
## already has an Environment its values are replaced.
static func apply(world_environment: WorldEnvironment, quality: int = Quality.MEDIUM, volumetric_fog: bool = true) -> void:
	if world_environment == null:
		return
	world_environment.environment = build(quality, volumetric_fog)
