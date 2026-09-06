shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float seed_offset = 0.0;

varying float v_age;
varying float v_seed;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = hash11(float(INSTANCE_ID) + seed_offset);

	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float spin = INSTANCE_CUSTOM.x;
	vec2 rotated = vec2(
		VERTEX.x * cos(spin) - VERTEX.y * sin(spin),
		VERTEX.x * sin(spin) + VERTEX.y * cos(spin)
	);
	VERTEX = vec3(rotated.x * sx, rotated.y * sy, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float uneven = 0.018 * sin(atan(p.y, p.x) * 9.0 + v_seed * 20.0);
	float outer = 1.0 - smoothstep(0.78 + uneven, 0.96 + uneven, radius);
	float inner = smoothstep(0.62 + uneven, 0.78 + uneven, radius);
	float ring = outer * inner;
	float fade = pow(1.0 - v_age, 2.8);
	ALBEDO = vec3(3.0, 1.25, 0.34) * intensity;
	ALPHA = clamp(ring * fade * 0.6 * intensity, 0.0, 1.0);
}
