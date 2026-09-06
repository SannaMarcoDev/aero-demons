shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Procedural fire for camera-facing particle quads. The low-frequency cells push each
// particle edge differently, so overlapping cards read as separate fire lobes.
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float flash_mode : hint_range(0.0, 1.0) = 0.0;
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
	float disc = 1.0 - smoothstep(0.28, 1.0, distance_from_center);
	vec2 flow = p * (3.2 + v_seed * 2.8) + vec2(v_seed * 19.7, v_seed * 7.1);
	float large_noise = value_noise(flow + TIME * vec2(0.35, -0.18));
	float fine_noise = value_noise(flow * 2.7 - TIME * vec2(0.22, 0.41));
	float erosion = mix(large_noise, fine_noise, 0.38);
	float shape = disc * mix(0.48, 1.0, erosion);
	float edge = smoothstep(0.11 + v_age * 0.16, 0.48, shape);
	float fade = flash_mode > 0.5 ? pow(1.0 - v_age, 3.5) : pow(1.0 - v_age, 1.35);

	float heat = clamp((1.0 - v_age * 0.82) * (0.72 + 0.28 * erosion), 0.0, 1.0);
	vec3 color = mix(vec3(0.48, 0.008, 0.001), vec3(2.4, 0.16, 0.012), smoothstep(0.08, 0.48, heat));
	color = mix(color, vec3(4.2, 0.95, 0.08), smoothstep(0.38, 0.73, heat));
	color = mix(color, vec3(7.0, 4.0, 1.25), smoothstep(0.67, 0.96, heat) * smoothstep(0.75, 0.0, distance_from_center));
	if (flash_mode > 0.5) {
		color = vec3(8.0, 5.7, 2.8) * (0.72 + 0.28 * erosion);
	}

	ALBEDO = color * intensity;
	ALPHA = clamp(edge * fade * intensity, 0.0, 1.0);
}
