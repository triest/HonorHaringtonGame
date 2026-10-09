// CapitalHull -- ShipView's hull material: makes the procedural spindle read as
// a plated dreadnought without any texture assets.
//
//  * PLATING   : two-level panel grid in ship-local space (large armour plates,
//                small seams), per-plate tint variation, bevel-style edge
//                darkening, and a roughness/metallic split between plate and seam.
//  * EMISSIVE  : cyan strip lights running the length of the hull, rows of lit
//                windows on the dorsal band (flicker slowly, die as damage
//                rises) and a thruster glow at the stern driven by `engine_glow`.
//  * DAMAGE    : `damage` 0..1 (hull fraction lost, from ImpactRecord snapshots)
//                blackens plates, tears holes through the plating to a dark
//                interior and lets molten-orange cracks glow; windows go dark.
//
// Render-only (ТЗ §42): every uniform is written by ShipView; nothing here
// feeds back into the simulation. Uses baked vertex colour (HullMeshBuilder's
// light-from-above gradient) as the base shading, as before.
shader_type spatial;
render_mode cull_back;

uniform vec3 half_extents = vec3(45.0, 25.0, 250.0);   // ship half width / height / length (m)
uniform vec4 plate_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform vec4 strip_color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform vec4 window_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec4 engine_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform float plate_scale = 1.0;              // multiplies panel counts
uniform float engine_glow : hint_range(0.0, 1.0) = 1.0;   // propulsion condition
uniform float damage : hint_range(0.0, 1.0) = 0.0;        // hull fraction lost
uniform float fx_time = 0.0;                  // wall clock (windows flicker, embers pulse)
uniform float rim_amount = 0.35;

varying vec3 lpos;
varying vec3 lnorm;

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

// Distance (0 at a seam line, 1 mid-plate) for a repeating grid coordinate.
float seam(float v, float width) {
	float f = abs(fract(v) - 0.5) * 2.0;     // 1 at cell centre .. 0 at seam
	return smoothstep(0.0, width, f);
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	// Hull-surface coordinates: length (z), and an angle around the long axis.
	float z = lpos.z / half_extents.z;                              // -1 bow .. +1 stern
	float ang = atan(lpos.y / max(half_extents.y, 0.001), lpos.x / max(half_extents.x, 0.001)); // -pi..pi
	float u = z * 22.0 * plate_scale;                               // large plates along the hull
	float v = ang * 3.0 * plate_scale;                              // around the hull
	vec2 big = vec2(u, v);
	vec2 cell = floor(big * vec2(1.0, 1.0));
	float plate_id = hash21(cell);

	float seam_big = seam(u, 0.07) * seam(v, 0.07);                 // 0 on seams, 1 on plates
	float seam_small = seam(u * 4.0, 0.12) * seam(v * 4.0, 0.12);
	float plating = mix(0.55, 1.0, seam_big) * mix(0.82, 1.0, seam_small);

	// Plate tint variation + faint streaking.
	float streak = vnoise(vec2(u * 0.35, v * 6.0));
	vec3 base = plate_color.rgb * COLOR.rgb;
	base *= 0.82 + 0.3 * plate_id;
	base *= 0.9 + 0.2 * streak;
	base *= plating;

	// ---- Damage: scorch, holes, glowing cracks -----------------------------
	float dmg_noise = vnoise(vec2(u * 0.9 + 3.1, v * 2.2 + 7.7)) * 0.65 + vnoise(vec2(u * 3.0, v * 7.0)) * 0.35;
	float burn = smoothstep(0.35, 0.85, dmg_noise + damage * 0.9 - 0.35) * damage;
	base = mix(base, base * vec3(0.12, 0.1, 0.09), clamp(burn * 1.4, 0.0, 0.95));
	float hole_mask = smoothstep(0.78, 0.9, dmg_noise + damage * 0.55 - 0.12);
	hole_mask *= step(0.25, damage);
	base = mix(base, vec3(0.015, 0.012, 0.012), hole_mask);
	float ridge = pow(1.0 - abs(2.0 * vnoise(vec2(u * 1.3 + 1.7, v * 3.4)) - 1.0), 10.0);
	float cracks = ridge * smoothstep(0.15, 0.7, damage) * (1.0 - hole_mask * 0.5);
	float pulse = 0.75 + 0.25 * sin(fx_time * 2.3 + plate_id * 6.28);

	// ---- Emissive: strip lights, windows, thrusters -------------------------
	// Strips: thin lines along the hull at a few fixed angles, broken into dashes.
	float strip_angle = abs(sin(ang * 3.0 + 0.0));                  // bright near angle multiples
	float strip_line = smoothstep(0.985, 1.0, strip_angle);
	float dash = step(0.35, fract(u * 0.5 + plate_id * 0.2));
	float strips = strip_line * dash * (1.0 - clamp(burn * 1.5 + hole_mask, 0.0, 1.0));

	// Windows: small cells on the dorsal band (angle around +90 degrees).
	float dorsal = smoothstep(0.55, 0.9, sin(ang));
	vec2 wcell = floor(vec2(u * 5.0, v * 14.0));
	float w_on = step(0.55, hash21(wcell + 11.0));
	float w_flicker = step(0.04 + damage * 0.5, hash21(wcell + floor(fx_time * 0.5) * 3.7));
	vec2 wf = fract(vec2(u * 5.0, v * 14.0));
	float w_shape = step(0.2, wf.x) * step(wf.x, 0.8) * step(0.3, wf.y) * step(wf.y, 0.7);
	float windows = dorsal * w_on * w_flicker * w_shape * (1.0 - clamp(burn * 2.0 + hole_mask, 0.0, 1.0));

	// Thruster glow: stern (+z) and bow (-z) impeller ring flare.
	float ends = smoothstep(0.82, 1.0, abs(z));
	float thrust = ends * engine_glow * (0.7 + 0.3 * vnoise(vec2(ang * 5.0, fx_time * 3.0)));

	vec3 emission = strip_color.rgb * strips * 2.2
			+ window_color.rgb * windows * 1.6
			+ engine_color.rgb * thrust * 2.6
			+ ember_color.rgb * cracks * pulse * 3.0;

	ALBEDO = base;
	METALLIC = mix(0.55, 0.25, 1.0 - seam_big) * (1.0 - burn * 0.6);
	ROUGHNESS = clamp(mix(0.38, 0.65, 1.0 - seam_big) + burn * 0.3, 0.0, 1.0);
	EMISSION = emission;
	RIM = rim_amount;
	RIM_TINT = 0.5;
}
