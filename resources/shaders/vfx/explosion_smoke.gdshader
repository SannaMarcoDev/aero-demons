shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float seed_offset = 0.0;

varying float v_age;
varying float v_seed;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + 1.0), f.x),
		f.y
	);
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
	float distance_from_center = length(p);
	float disc = 1.0 - smoothstep(0.12, 1.0, distance_from_center);
	vec2 flow = p * (2.2 + v_seed * 2.2) + vec2(v_seed * 13.3, v_seed * 29.2);
	float body = value_noise(flow + TIME * vec2(0.06, -0.12));
	float detail = value_noise(flow * 3.1 - TIME * vec2(0.13, 0.09));
	float density = mix(body, detail, 0.32);
	float shape = disc * mix(0.38, 1.0, density);
	float fade_in = smoothstep(0.02, 0.16, v_age);
	float fade_out = 1.0 - smoothstep(0.64, 1.0, v_age);
	float alpha = pow(clamp(shape, 0.0, 1.0), 1.7) * fade_in * fade_out * intensity;

	vec3 fresh = vec3(0.22, 0.10, 0.045);
	vec3 soot = vec3(0.035, 0.032, 0.03);
	vec3 aged = vec3(0.12, 0.12, 0.13);
	vec3 color = mix(fresh, soot, smoothstep(0.06, 0.34, v_age));
	color = mix(color, aged, smoothstep(0.58, 0.94, v_age));
	color *= 0.65 + density * 0.52;

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
