// MissileTrail -- ONE draw call for every missile trail in the battle.
//
// MissileTrailFx packs each trail as a chain of ribbon segments inside a single
// MultiMesh; each instance is one segment. Per-instance data (render-only,
// ТЗ §42):
//   MODEL_MATRIX[3].xyz  A = head-side end of the segment (render space)
//   MODEL_MATRIX[0].xyz  D = B - A (B = older, tail-side end)
//   INSTANCE_CUSTOM.x    ribbon width in screen pixels
//   INSTANCE_CUSTOM.y/z  normalised trail coordinate at A / B (0 = head, 1 = tail)
//   INSTANCE_CUSTOM.w    kind: 0 = offensive missile, 1 = counter-missile
// The quad is expanded camera-facing in the vertex stage, so the CPU never
// builds camera-dependent geometry and the ribbon keeps a constant screen width
// from a single ship length away to millions of kilometres.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform vec4 head_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform vec4 cm_head_color : source_color = vec4(0.7, 1.0, 1.0, 1.0);
uniform vec4 cm_tail_color : source_color = vec4(0.1, 0.65, 0.9, 1.0);
uniform float intensity = 1.6;
uniform float fade_power = 1.6;
uniform float px_k = 0.001;      // world metres per pixel per metre of distance (set per frame)

varying float v_s;
varying float v_kind;
varying float v_across;

void vertex() {
	vec3 a = MODEL_MATRIX[3].xyz;
	vec3 d = MODEL_MATRIX[0].xyz;
	float u = VERTEX.x + 0.5;                      // 0 at A .. 1 at B
	vec3 p = a + d * u;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - p;
	float dist = max(length(to_cam), 0.001);
	vec3 c = cross(d, to_cam / dist);
	float cl = length(c);
	vec3 side = cl > 0.000001 ? c / cl : vec3(0.0);
	float width_px = INSTANCE_CUSTOM.x * mix(1.0, 0.35, mix(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z, u));
	p += side * (VERTEX.y * 2.0 * width_px * dist * px_k);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_s = mix(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z, u);
	v_kind = INSTANCE_CUSTOM.w;
	v_across = VERTEX.y * 2.0;                     // -1..1 across the ribbon
}

void fragment() {
	float alpha = pow(clamp(1.0 - v_s, 0.0, 1.0), fade_power) * (1.0 - v_across * v_across);
	vec3 hot = mix(head_color.rgb, cm_head_color.rgb, v_kind);
	vec3 cool = mix(tail_color.rgb, cm_tail_color.rgb, v_kind);
	ALBEDO = mix(hot, cool, clamp(v_s, 0.0, 1.0)) * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
