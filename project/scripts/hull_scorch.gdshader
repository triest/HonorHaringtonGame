// HullScorch -- one burn mark on a hull (a small quad laid on the hull
// surface by ShipDamageFx). Ragged-edged dark soot disc with an ember core
// that cools from white-orange to nothing over `ember_life` seconds of wall
// clock; the soot itself is permanent (persistent damage readout, ТЗ §42:
// driven only by ImpactRecord snapshots).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float start_time = 0.0;     // fx_clock_s() when the mark was made
uniform float fx_time = 0.0;
uniform float ember_life = 14.0;
uniform float seed = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 0.6;   // darker/larger look for bigger hits

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

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float n = vnoise(UV * 7.0 + vec2(seed * 3.7, seed * 1.3)) * 0.6 + vnoise(UV * 17.0 + vec2(seed)) * 0.4;
	float edge = r + (n - 0.5) * 0.7;                  // ragged boundary
	float soot = (1.0 - smoothstep(0.55, 1.0, edge)) * (0.55 + 0.4 * strength);
	float core = 1.0 - smoothstep(0.0, 0.55, edge);

	float age = max(fx_time - start_time, 0.0);
	float ember = core * exp(-age / (ember_life * 0.35)) * step(age, ember_life);

	vec3 dark = vec3(0.025, 0.02, 0.018);
	vec3 hot = mix(vec3(1.0, 0.35, 0.06), vec3(1.0, 0.9, 0.6), clamp(ember * 1.4 - 0.4, 0.0, 1.0));
	ALBEDO = mix(dark, hot * 1.6, clamp(ember, 0.0, 1.0));
	ALPHA = clamp(soot + ember * 0.8, 0.0, 0.92);
}
