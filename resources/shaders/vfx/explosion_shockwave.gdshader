shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Expanding pressure shell: a camera-facing disc that redraws the scene behind it pushed outwards
// at its rim, with a faint hot edge. Drawn before the other explosion layers so they stay on top.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float seed_offset = 0.0;
uniform float strength : hint_range(0.0, 3.0) = 1.0;

#include "res://resources/shaders/vfx/explosion_common.gdshaderinc"

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = particle_age(INSTANCE_CUSTOM);
	v_seed = hash11(float(INSTANCE_ID) + seed_offset);
	float size = length(MODEL_MATRIX[0].xyz);
	VERTEX = vec3(VERTEX.xy * size, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float uneven = 0.025 * (value_noise(vec2(atan(p.y, p.x) * 3.0 + v_seed * 20.0, 0.0)) - 0.5);
	float shell = smoothstep(0.45, 0.9 + uneven, radius) * (1.0 - smoothstep(0.92 + uneven, 1.0, radius));
	float fade = pow(1.0 - v_age, 1.7) * strength * min(intensity, 1.0);

	// Convert a push in quad UV into screen UV so the warp keeps its size at any distance.
	float screen_per_uv = length(fwidth(SCREEN_UV)) / max(length(fwidth(UV)), 0.00001);
	vec2 direction = radius > 0.001 ? p / radius : vec2(0.0);
	vec2 warp = direction * shell * fade * 0.045 * screen_per_uv;
	vec3 behind = textureLod(screen_texture, SCREEN_UV - warp, 0.0).rgb;

	ALBEDO = behind + vec3(1.6, 1.05, 0.6) * shell * fade * 0.18;
	ALPHA = clamp(shell * min(fade * 3.0, 1.0), 0.0, 1.0);
}
