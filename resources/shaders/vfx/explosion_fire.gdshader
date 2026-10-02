shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Additive fire for camera-facing particle quads. Mode 0 is a burning core lobe, 1 the first-frames
// white flash and 2 the soft glare halo that sells the brightness even with glow disabled.
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float flash_mode : hint_range(0.0, 2.0) = 0.0;
uniform float seed_offset = 0.0;
uniform float heat_bias : hint_range(0.0, 1.0) = 0.5;
// Floor on the quad size as a fraction of camera distance, so a far-away blast still pops.
uniform float min_view_size = 0.0;

#include "res://resources/shaders/vfx/explosion_common.gdshaderinc"

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = particle_age(INSTANCE_CUSTOM);
	v_seed = hash11(float(INSTANCE_ID) + seed_offset);

	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	size = max(size, length(CAMERA_POSITION_WORLD - center) * min_view_size);
	VERTEX = vec3(rotate2(VERTEX.xy, INSTANCE_CUSTOM.x) * size, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);

	if (flash_mode > 1.5) {
		// Glare: gaussian halo with a hot pinpoint, gone in a fraction of a second.
		float halo = exp(-radius * radius * 5.5) * 0.55 + exp(-radius * radius * 28.0) * 0.45;
		float fade = pow(1.0 - v_age, 2.4);
		ALBEDO = mix(vec3(2.2, 1.05, 0.38), vec3(4.0, 2.9, 1.6), heat_bias) * intensity;
		ALPHA = clamp(halo * fade, 0.0, 1.0);
	} else if (flash_mode > 0.5) {
		float disc = 1.0 - smoothstep(0.15, 1.0, radius);
		float rays = value_noise(vec2(atan(p.y, p.x) * 4.0 + v_seed * 31.0, radius * 2.0));
		float fade = pow(1.0 - v_age, 2.0);
		ALBEDO = vec3(9.0, 7.2, 4.8) * (0.8 + 0.4 * rays) * intensity;
		ALPHA = clamp(disc * disc * fade * (0.75 + 0.25 * rays), 0.0, 1.0);
	} else {
		vec2 flow = p * (2.6 + v_seed * 2.2) + vec2(v_seed * 19.7, v_seed * 7.1);
		float erosion = fbm3(flow + TIME * vec2(0.35, -0.2) + v_age * 1.7);
		float shape = (1.0 - smoothstep(0.2, 1.0, radius + (erosion - 0.5) * 0.6));
		float heat = clamp((1.0 - v_age * 1.05) * (0.55 + 0.6 * erosion) * (1.25 - radius * 0.6), 0.0, 1.0);
		float fade = pow(1.0 - v_age, 1.2);
		ALBEDO = fire_ramp(heat, heat_bias) * intensity;
		ALPHA = clamp(shape * fade, 0.0, 1.0);
	}
}
