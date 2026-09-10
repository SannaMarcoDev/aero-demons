// Based on "Water Shader 3D Godot 4.3" by Godot Shaders:
// https://godotshaders.com/shader/water-shader-3d-godot-4-3/
// The caustic sampler is a Texture2D here so the existing procedural water asset
// can be reused without adding a generated Texture2DArray.

shader_type spatial;

render_mode depth_draw_always, cull_disabled, blend_mix;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

group_uniforms Waves;
uniform vec4 wave_1 = vec4(0.3, 4.0, 0.04, 90.0);
uniform vec4 wave_2 = vec4(-0.26, -0.19, 0.03, 55.0);
uniform vec4 wave_3 = vec4(-7.67, 5.63, 0.025, 35.0);
uniform vec4 wave_4 = vec4(-0.42, -1.63, 0.02, 25.0);
uniform vec4 wave_5 = vec4(1.66, 0.07, 0.025, 140.0);
uniform vec4 wave_6 = vec4(1.20, 1.14, 0.02, 75.0);
uniform vec4 wave_7 = vec4(-1.6, 7.3, 0.02, 45.0);
uniform vec4 wave_8 = vec4(-0.42, -1.63, 0.015, 18.0);

uniform float time_factor = 4.0;
uniform float noise_zoom = 2.0;
uniform float noise_amp = 0.18;

group_uniforms Water_colours;
uniform vec3 base_water_color : source_color = vec3(0.02, 0.25, 0.32);
uniform vec3 fresnel_water_color : source_color = vec3(0.12, 0.65, 0.75);
uniform vec4 deep_water_color : source_color = vec4(0.015, 0.08, 0.16, 1.0);
uniform vec4 shallow_water_color : source_color = vec4(0.07, 0.42, 0.46, 1.0);

group_uniforms Depth;
uniform float beers_law = 0.08;
uniform float depth_offset = -1.2;
uniform float near = 0.5;
uniform float far = 10000.0;

group_uniforms Edge_Detection;
uniform float edge_texture_scale = 0.02;
uniform float edge_texture_offset = 1.0;
uniform float edge_texture_speed = 0.04;
uniform float edge_foam_intensity = 1.2;
uniform float edge_fade_start = -3.0;
uniform float edge_fade_end = 6.6;
uniform sampler2D edge_foam_texture : hint_default_black;

group_uniforms WavePeakEffect;
uniform float peak_height_threshold = 0.5;
uniform vec3 peak_color : source_color = vec3(1.0);
uniform float peak_intensity = 0.75;
uniform sampler2D foam_texture : hint_default_black;
uniform float foam_intensity = 0.35;
uniform float foam_scale = 0.025;

group_uniforms Surface_details;
uniform float metallic = 0.25;
uniform float roughness = 0.08;
uniform float uv_scale_text_a = 0.01;
uniform vec2 uv_speed_text_a = vec2(0.06, 0.04);
uniform float uv_scale_text_b = 0.025;
uniform vec2 uv_speed_text_b = vec2(-0.035, 0.02);
uniform float normal_strength = 0.7;
uniform float uv_sampler_scale = 0.004;
uniform float blend_factor = 0.45;
uniform float perturbation_strength = 0.2;
uniform float perturbation_time = 0.15;
uniform sampler2D normalmap_a : hint_default_black;
uniform sampler2D normalmap_b : hint_default_black;
uniform sampler2D uv_sampler : hint_default_black;
uniform sampler2D caustic_sampler : hint_default_black;
uniform float caustics_intensity = 2.0;
uniform float caustic_distortion_strength = 0.002;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

float edge(float depth) {
	depth = 2.0 * depth - 1.0;
	return near * far / (far - depth * (near - far));
}

float dynamic_amplitude(vec2 pos, float time) {
	return 1.0 + 0.5 * sin(time + length(pos) * 0.001);
}

float hash(vec2 p) {
	return fract(sin(dot(p * 17.17, vec2(14.91, 67.31))) * 4791.9511);
}

float noise(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(p), hash(p + vec2(1.0, 0.0)), f.x),
		mix(hash(p + vec2(0.0, 1.0)), hash(p + vec2(1.0)), f.x),
		f.y
	);
}

float fbm(vec2 x) {
	float height = 0.0;
	float amplitude = 0.5;
	float frequency = 3.0;
	for (int i = 0; i < 6; i++) {
		height += noise(x * frequency) * amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return height;
}

struct WaveResult {
	vec3 displacement;
	vec3 tangent;
	vec3 binormal;
	vec3 normal;
};

WaveResult gerstner_wave(vec4 params, vec2 pos, float time) {
	float steepness = params.z * dynamic_amplitude(pos, time);
	float wavelength = params.w;
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.81 / k);
	vec2 direction = normalize(params.xy);
	float phase = k * (dot(direction, pos) - c * time);
	float amplitude = steepness / k;

	vec3 displacement = vec3(
		direction.x * amplitude * cos(phase),
		amplitude * sin(phase),
		direction.y * amplitude * cos(phase)
	);
	vec3 tangent = vec3(
		1.0 - direction.x * direction.x * steepness * sin(phase),
		steepness * cos(phase),
		-direction.x * direction.y * steepness * sin(phase)
	);
	vec3 binormal = vec3(
		-direction.x * direction.y * steepness * sin(phase),
		steepness * cos(phase),
		1.0 - direction.y * direction.y * steepness * sin(phase)
	);

	return WaveResult(displacement, tangent, binormal, normalize(cross(tangent, binormal)));
}

WaveResult wave(vec2 pos, float time) {
	WaveResult result;
	result.displacement = vec3(0.0);
	result.tangent = vec3(1.0, 0.0, 0.0);
	result.binormal = vec3(0.0, 0.0, 1.0);
	result.normal = vec3(0.0, 1.0, 0.0);

	WaveResult current;
	current = gerstner_wave(wave_1, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_2, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_3, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_4, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_5, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_6, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_7, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;
	current = gerstner_wave(wave_8, pos, time);
	result.displacement += current.displacement;
	result.tangent += current.tangent;
	result.binormal += current.binormal;
	result.normal += current.normal;

	result.displacement.y += fbm(pos * (noise_zoom / 50.0)) * noise_amp;
	return result;
}

varying float wave_height;
varying vec3 world_position;
varying mat3 tbn_matrix;
varying mat4 inv_mvp;

void vertex() {
	float time = TIME / time_factor;
	WaveResult wave_result = wave(VERTEX.xz, time);
	VERTEX += wave_result.displacement;
	wave_height = wave_result.displacement.y;

	vec3 normal = normalize((MODELVIEW_MATRIX * vec4(wave_result.normal, 0.0)).xyz);
	vec3 tangent = normalize((MODELVIEW_MATRIX * vec4(wave_result.tangent, 0.0)).xyz);
	vec3 binormal = normalize((MODELVIEW_MATRIX * vec4(cross(wave_result.normal, wave_result.tangent), 0.0)).xyz);
	tbn_matrix = mat3(tangent, binormal, normal);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inv_mvp = inverse(PROJECTION_MATRIX * MODELVIEW_MATRIX);
}

float random_value(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 fraction = fract(p);
	vec2 smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(
		mix(random_value(cell), random_value(cell + vec2(1.0, 0.0)), smooth_fraction.x),
		mix(random_value(cell + vec2(0.0, 1.0)), random_value(cell + vec2(1.0)), smooth_fraction.x),
		smooth_fraction.y
	);
}

float layered_noise(vec2 p, float scale) {
	return smooth_noise(p * scale) * 0.5
		+ smooth_noise(p * scale * 2.0) * 0.25
		+ smooth_noise(p * scale * 4.0) * 0.125;
}

vec2 perturb_uv(vec2 uv, vec2 world_pos, float time, float strength) {
	vec2 noise_offset = vec2(
		layered_noise(world_pos * 0.003 + time * 0.06, 1.0),
		layered_noise(world_pos * 0.003 + time * 0.06 + vec2(10.0), 1.0)
	);
	return uv + noise_offset * strength;
}

vec3 world_position_from_depth(vec2 screen_uv, float raw_depth, mat4 inverse_projection, mat4 inverse_view) {
	vec4 clip_position = vec4(screen_uv * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_position = inverse_projection * clip_position;
	view_position /= view_position.w;
	return (inverse_view * view_position).xyz;
}

void fragment() {
	vec2 uv = world_position.xz;
	vec2 uv_offset = texture(uv_sampler, uv * uv_sampler_scale).rg - vec2(0.5);

	vec2 base_uv_a = (uv + uv_speed_text_a * TIME + uv_offset) * uv_scale_text_a;
	vec2 base_uv_b = (uv + uv_speed_text_b * TIME + uv_offset) * uv_scale_text_b;
	vec2 animated_uv_a = perturb_uv(base_uv_a, world_position.xz, TIME, perturbation_strength);
	vec2 animated_uv_b = perturb_uv(base_uv_b, world_position.xz, TIME, perturbation_time);

	vec3 normal_sample_a = texture(normalmap_a, animated_uv_a).rgb * 2.0 - 1.0;
	vec3 normal_sample_b = texture(normalmap_b, animated_uv_b).rgb * 2.0 - 1.0;
	vec3 combined_normal = normalize(mix(normalize(normal_sample_a), normalize(normal_sample_b), blend_factor));
	vec3 perturbed_normal = normalize(tbn_matrix * (combined_normal * normal_strength));

	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 scene_world_position = world_position_from_depth(SCREEN_UV, depth_raw, inverse(PROJECTION_MATRIX), INV_VIEW_MATRIX);
	float water_depth = max(world_position.y - scene_world_position.y, 0.0);
	float camera_depth = INV_VIEW_MATRIX[3].y - world_position.y;
	if (camera_depth < 0.0) {
		float depth_factor = smoothstep(-10.0, 0.0, camera_depth);
		ALPHA -= depth_factor * 0.3;
	}

	float depth_blend = 1.0 - exp(-max(water_depth + depth_offset, 0.0) * beers_law);
	depth_blend = clamp(depth_blend, 0.0, 1.0);
	float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, 2.5 + depth_blend_power * 2.5).rgb;
	vec3 depth_color = mix(shallow_water_color.rgb, deep_water_color.rgb, depth_blend_power);
	float screen_mix = mix(0.02, 0.005, depth_blend_power);
	vec3 water_color = mix(depth_color, screen_color * depth_color, screen_mix);

	float depth_difference = water_depth;

	vec4 caustic_screen_position = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 caustic_local_position = inv_mvp * caustic_screen_position;
	caustic_local_position /= caustic_local_position.w;
	vec2 caustic_uv = caustic_local_position.xz * 0.01 + 0.5;
	caustic_uv += perturbed_normal.xz * caustic_distortion_strength;
	float caustic_a = texture(caustic_sampler, caustic_uv * 3.0 + vec2(TIME * 0.025, -TIME * 0.018)).r;
	float caustic_b = texture(caustic_sampler, caustic_uv * 5.0 - vec2(TIME * 0.015, TIME * 0.022)).r;
	float caustic = mix(caustic_a, caustic_b, 0.5);
	water_color *= 1.0 + pow(caustic, 1.5) * (1.0 - depth_blend_power) * caustics_intensity;

	float fresnel_factor = fresnel(5.0, NORMAL, VIEW);
	vec3 surface_color = mix(base_water_color, fresnel_water_color, fresnel_factor);

	vec2 edge_uv = world_position.xz * edge_texture_scale + edge_texture_offset + TIME * edge_texture_speed;
	float edge_fade = smoothstep(edge_fade_start, edge_fade_end, depth_difference);
	vec3 edge_foam_color = texture(edge_foam_texture, edge_uv).rgb * edge_foam_intensity;
	vec3 depth_color_adjusted = mix(edge_foam_color, water_color, edge_fade);

	float peak_factor = smoothstep(peak_height_threshold, peak_height_threshold + 0.2, wave_height);
	peak_factor *= fbm(world_position.xz * 0.01 + TIME * 0.1);
	vec3 peak_surface_color = mix(surface_color, peak_color, peak_intensity);
	vec3 final_color = mix(surface_color, peak_surface_color, peak_factor);

	vec2 foam_uv = world_position.xz * foam_scale + TIME * 0.1;
	float foam_sample = texture(foam_texture, foam_uv).r;
	float foam_blend_factor = smoothstep(0.0, 1.0, peak_factor) * foam_sample * foam_intensity;
	final_color = mix(final_color, vec3(1.0), foam_blend_factor);

	ALBEDO = clamp(final_color + depth_color_adjusted, vec3(0.0), vec3(1.0));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL = perturbed_normal;
}
