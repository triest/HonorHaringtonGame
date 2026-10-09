// SidewallCrackle -- material for ShipView's four sidewall panels.
//
// Resting look matches the old translucent card. Two render-only behaviours
// are added (ТЗ §42; every uniform is written by ShipView):
//  1. CONDITION flicker: as the panel's `condition` falls from 1.0 toward 0.0
//     the field gets unstable -- random dropouts, thin arcs of electricity and
//     a drift toward red. Intensity = (1 - condition)^1.5, so a healthy panel is
//     rock steady and a failing one visibly sputters.
//  2. STRIKE crackle: an attenuated hit (SIDEWALL_ATTENUATED) sprays bright
//     filament sparks around the strike point for ~`crackle_life` seconds.
//
// hits[i].xyz   PANEL-local strike centre (m; panel plane is local x = 0)
// hits[i].w     wall-clock start (seconds, ShipView.fx_clock_s)
// hit_params[i].x  energy 0..1 (0 = unused)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(0.95, 0.75, 0.15, 0.22);
uniform vec4 spark_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 fail_color : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform vec4 hits[6];
uniform vec4 hit_params[6];
uniform float condition : hint_range(0.0, 1.0) = 1.0;
uniform float fx_time = 0.0;
uniform float ship_size = 500.0;
uniform float crackle_life = 0.9;

varying vec3 lpos;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Thin bright filaments: the crest of a ridged noise field, re-seeded every
// `rate` frames-per-second so the arcs jump like real discharge.
float arcs(vec2 p, float seed, float scale) {
	float n = vnoise(p * scale + vec2(seed * 7.3, seed * 3.1));
	float ridge = 1.0 - abs(2.0 * n - 1.0);
	return pow(ridge, 14.0);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float instability = pow(1.0 - clamp(condition, 0.0, 1.0), 1.5);
	float tick = floor(fx_time * 20.0);              // arcs re-seed 20x / second
	vec2 p = vec2(lpos.z, lpos.y) / max(ship_size, 1.0);

	// Dropouts: the field stutters, more often and deeper as condition falls.
	float dropout = step(hash11(tick + floor(lpos.z / (ship_size * 0.12 + 0.001)) * 13.7), instability * 0.75);
	float ambient_arcs = arcs(p, tick, 38.0) * instability * 1.6;

	vec3 col = mix(base_color.rgb, fail_color.rgb, instability * 0.75);
	float a = base_color.a * (1.0 - 0.8 * instability * dropout);

	float spark = ambient_arcs;
	for (int i = 0; i < 6; i++) {
		float e = hit_params[i].x;
		float age = fx_time - hits[i].w;
		if (e > 0.0 && age >= 0.0 && age < crackle_life) {
			float k = age / crackle_life;
			float d = distance(lpos.yz, hits[i].yz);
			float radius = ship_size * (0.07 + 0.10 * e) * (0.5 + 0.8 * k);
			float fall = exp(-pow(d / radius, 2.0));
			float fade = (1.0 - k) * (1.0 - k);
			float s = arcs(p, tick + float(i) * 5.0, 90.0) + 0.55 * arcs(p, tick + 17.0 + float(i), 150.0);
			float flash = exp(-d / (ship_size * 0.03 + 0.001)) * exp(-age * 9.0);
			spark += e * fade * (fall * s * 2.2 + flash * 1.4);
			a += e * fade * fall * 0.25;
		}
	}
	spark = clamp(spark, 0.0, 2.0);
	ALBEDO = mix(col, spark_color.rgb, clamp(spark, 0.0, 1.0)) * (1.0 + 0.6 * spark);
	ALPHA = clamp(a + spark, 0.0, 1.0);
}
