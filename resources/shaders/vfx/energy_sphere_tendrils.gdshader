shader_type spatial;
// Ink ribbons, one per MultiMesh instance. Each one is born outside the sphere, whips around it on a
// spiral framed for the viewer and is swallowed head first; then it respawns with a new path.
// The ink body writes depth so the volumetric clouds, composited later, stop in front of it.
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;

#include "res://resources/shaders/vfx/energy_sphere_common.gdshaderinc"

uniform sampler3D energy_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 magenta : source_color = vec4(0.85, 0.035, 0.48, 1.0);
uniform vec4 ink : source_color = vec4(0.03, 0.006, 0.07, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float animation_speed : hint_range(0.0, 3.0) = 1.0;
uniform float phase = 0.0;
// Ribbon half-width in metres; far ribbons keep a minimum on-screen width and fade instead.
uniform float tendril_width = 10.0;
uniform float min_pixels = 1.0;

varying float v_side;
varying float v_s;
varying float v_alpha;
varying float v_seed;

vec3 rotate(vec3 v, vec3 axis, float angle) {
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}

vec3 tendril(float s, vec2 seed, float t, mat3 frame) {
	float spin = t * mix(0.3, 0.55, es_hash2(seed + 5.2));
	float theta = es_hash2(seed + 3.9) * 6.2831853 + mix(2.4, 4.4, es_hash2(seed + 2.6)) * s + spin;
	float radius = mix(mix(1.5, 2.15, es_hash2(seed)), mix(0.94, 1.02, es_hash2(seed + 1.3)), pow(s, 0.8));
	radius += (sin(s * 7.0 + t * 1.3 + seed.x) * 0.06 + sin(s * 17.0 - t * 2.1 + seed.y) * 0.025) * (1.0 - s * 0.6);
	float axis_angle = es_hash2(seed + 6.1) * 6.2831853;
	vec3 local = rotate(vec3(cos(theta), sin(theta), 0.0) * radius, vec3(cos(axis_angle), sin(axis_angle), 0.0), (es_hash2(seed + 4.8) - 0.5) * 1.8);
	return frame * local;
}

void vertex() {
	float id = float(INSTANCE_ID);
	float s = UV.x;
	float side = UV.y * 2.0 - 1.0;
	float t = TIME * animation_speed + phase;
	float period = mix(5.5, 9.0, es_hash(id * 2.3));
	float local = t + es_hash(id) * period;
	float epoch = floor(local / period);
	float life = (local - epoch * period) / period;
	vec2 seed = vec2(id * 7.31 + epoch * 1.7, epoch * 0.37 + id * 3.1);
	vec3 camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	mat3 frame = es_view_frame(camera);
	vec3 view = (MODELVIEW_MATRIX * vec4(tendril(s, seed, t, frame), 1.0)).xyz;
	vec3 ahead = (MODELVIEW_MATRIX * vec4(tendril(s + 0.01, seed, t, frame), 1.0)).xyz;
	float pixel = max(-view.z, 0.0) * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float width = tendril_width * pow(sin(3.14159 * s), 0.6);
	float drawn = max(width, min_pixels * pixel);
	// The visible stretch slides from tail to head over the life: ink drawn in, then swallowed.
	float head = mix(-0.2, 1.35, life);
	v_alpha = smoothstep(head - 0.55, head - 0.25, s) * smoothstep(head + 0.05, head - 0.12, s);
	v_alpha *= smoothstep(0.0, 0.12, life) * smoothstep(1.0, 0.85, life) * min(width / max(drawn, 0.001), 1.0);
	v_side = side;
	v_s = s;
	v_seed = es_hash2(seed);
	view += normalize(cross(ahead - view, view)) * side * drawn;
	POSITION = PROJECTION_MATRIX * vec4(view, 1.0);
}

void fragment() {
	float t = TIME * animation_speed + phase;
	float d = abs(v_side);
	float body = 1.0 - smoothstep(0.5, 1.0, d);
	float breakup = texture(energy_noise, vec3(v_s * 2.4 - t * 0.7, v_seed * 7.0, 0.3)).r;
	float alpha = body * v_alpha * smoothstep(0.18, 0.4, breakup);
	if (alpha < 0.003) {
		discard;
	}
	float edge = smoothstep(0.35, 0.9, d);
	vec3 color = ink.rgb * 0.6 + mix(violet.rgb, magenta.rgb, v_s) * edge * (0.08 + v_s * 0.22);
	ALPHA = alpha * 0.95;
	ALBEDO = color * emission_strength;
	DEPTH = alpha > 0.5 ? FRAGCOORD.z : textureLod(depth_texture, SCREEN_UV, 0.0).r + 2e-7;
}
