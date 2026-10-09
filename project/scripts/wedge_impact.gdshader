// WedgeImpact -- ShipView's impeller-wedge material, with up to 8 concurrent
// strike ripples and two looks:
//   fresnel_mode = 0  BRIGHT   : the original glowing additive band.
//   fresnel_mode = 1  FRESNEL  : "almost invisible until hit" -- the resting
//                     wedge is a faint rim-lit ghost; absorbing a strike
//                     lights the whole frame, strongest on the grazing rim.
//
// Render-only (ТЗ §42): every uniform is written by ShipView from an
// ImpactRecord snapshot; the shader invents no hit/damage logic.
//
// hits[i].xyz   ship-local centre of the strike on the wedge surface (m)
// hits[i].w     wall-clock start time of the strike (seconds, ShipView.fx_clock_s)
// hit_params[i].x  energy 0..1 (0 = slot unused); .y reserved
//
// Effects run on WALL-CLOCK time (fx_time), never sim time: at x2000 a
// detonation lasts one tick, but the ripple must stay readable for a human.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform vec4 hit_color : source_color = vec4(0.8, 0.93, 1.0, 1.0);
uniform vec4 hits[8];
uniform vec4 hit_params[8];
uniform float fx_time = 0.0;
uniform float ship_size = 500.0;       // ship length (m): scales every ripple
uniform float ripple_life = 1.4;       // seconds of wall-clock
uniform float ripple_speed = 0.55;     // ship lengths / second at energy 1
uniform float fresnel_mode : hint_range(0.0, 1.0) = 0.0;
uniform float fresnel_power = 2.2;
uniform float idle_alpha_fresnel = 0.06;   // resting alpha floor in FRESNEL mode
uniform float frame_flash_gain = 1.7;      // whole-wedge flash on absorption

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	// Rim factor: 1 at grazing angles, 0 face-on (two-sided surface -> abs).
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);

	vec3 col = base_color.rgb * COLOR.rgb;
	float a = base_color.a * COLOR.a;
	// FRESNEL mode: fade the resting band to a faint rim-lit ghost.
	float resting = mix(1.0, idle_alpha_fresnel + 0.55 * rim, fresnel_mode);
	a *= resting;

	float glow = 0.0;
	float frame = 0.0;
	for (int i = 0; i < 8; i++) {
		float e = hit_params[i].x;
		float age = fx_time - hits[i].w;
		if (e > 0.0 && age >= 0.0 && age < ripple_life) {
			float k = age / ripple_life;
			float d = distance(lpos, hits[i].xyz);
			float radius = ship_size * ripple_speed * (0.35 + 0.65 * e) * age;
			float width = ship_size * 0.035 * (1.0 + 2.5 * k);
			float x = (d - radius) / width;
			float ring = exp(-x * x);
			float flash = exp(-d / (ship_size * (0.05 + 0.10 * e))) * exp(-age * 7.0);
			float fade = (1.0 - k) * (1.0 - k);
			glow += e * (ring * fade * 0.9 + flash * 1.6);
			frame += e * exp(-age * 3.2) * fade;
		}
	}

	// Whole-frame flash: subtle in BRIGHT mode, dramatic in FRESNEL mode,
	// concentrated on the rim so the wedge's silhouette "rings" when it absorbs.
	float frame_flash = frame * (0.25 + 0.75 * rim) * frame_flash_gain * (0.35 + 1.15 * fresnel_mode);
	glow = clamp(glow + frame_flash, 0.0, 2.2);

	ALBEDO = mix(col, hit_color.rgb, clamp(glow, 0.0, 1.0)) * (1.0 + 0.5 * glow);
	ALPHA = clamp(a + glow, 0.0, 1.0);
}
