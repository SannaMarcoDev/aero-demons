shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled;

// Draw material for the smoke GPUParticles3D. The quads stay lit by the scene sun: a
// spherical normal is faked across each billboard so a puff has a bright and a dark side
// and the trail keeps reading as volume when the aircraft turns into or away from the sun.

uniform sampler2D depth_buffer : hint_depth_texture, filter_nearest;
uniform sampler3D smoke_noise : filter_linear, repeat_enable;

uniform vec3 soot_tint : source_color = vec3(0.06, 0.055, 0.05);
uniform vec3 aged_tint : source_color = vec3(0.42, 0.42, 0.44);
uniform float aging : hint_range(0.0, 4.0) = 1.4;
uniform float noise_scale = 1.1;
uniform float noise_detail = 3.3;
uniform float noise_contrast : hint_range(1.0, 6.0) = 2.2;
uniform float churn_speed = 0.35;
uniform float erosion : hint_range(0.0, 1.0) = 0.75;
// Fresh soot leaves the airframe as a dense slug and only tears into wisps once it has
// expanded. Eroding a young puff as hard as an old one scatters the near trail into
// separate dark specks floating in the pale haze of the old ones.
uniform float erosion_young : hint_range(0.0, 1.0) = 0.3;
uniform float erosion_onset : hint_range(0.02, 1.0) = 0.35;
uniform float edge_start : hint_range(0.0, 1.0) = 0.15;
// Falloff exponent, not a threshold. Clipping the puff alpha to a flat plateau stamps a
// hard-edged disc, and the trail then reads as a string of dots no matter how many
// particles are in it; a plain gradient lets overlapping puffs accumulate into one body.
uniform float edge_falloff : hint_range(0.5, 4.0) = 1.6;
uniform float opacity : hint_range(0.0, 2.0) = 0.95;
// A puff spawns inside the wing surface, so without a depth fade the quad prints a hard
// straight edge where it cuts the airframe.
uniform float depth_fade = 1.6;
uniform float near_fade = 1.2;
uniform float normal_bend : hint_range(0.0, 1.0) = 0.8;
// Self-shadowing stand-in. Without it every puff is one flat albedo, and a trail seen
// against terrain rather than sky collapses into a featureless dark stain.
uniform float structure : hint_range(0.0, 1.0) = 0.55;
uniform float shade_variation : hint_range(0.0, 1.0) = 0.3;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

varying float v_seed;
varying float v_phase;

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	v_phase = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = hash11(float(INSTANCE_ID) + 1.73);

	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float a = INSTANCE_CUSTOM.x;
	vec2 rotated = vec2(
		VERTEX.x * cos(a) - VERTEX.y * sin(a),
		VERTEX.x * sin(a) + VERTEX.y * cos(a)
	);
	VERTEX = vec3(rotated.x * sx, rotated.y * sy, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float disc = 1.0 - smoothstep(edge_start, 1.0, d);

	vec3 np = vec3(UV * noise_scale + v_seed * 4.1, v_seed * 7.3 + TIME * churn_speed);
	float n = texture(smoke_noise, np).r * 0.6
		+ texture(smoke_noise, np * noise_detail + 1.7).r * 0.4;
	n = clamp((n - 0.5) * noise_contrast + 0.5, 0.0, 1.0);

	float shape = disc * mix(1.0, n,
		mix(erosion_young, erosion, smoothstep(0.0, erosion_onset, v_phase)));
	float alpha = pow(clamp(shape, 0.0, 1.0), edge_falloff) * COLOR.a * opacity * intensity;

	float scene_depth = 0.0;
	float raw = texture(depth_buffer, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	scene_depth = -(view.z / view.w);
	float frag_depth = -VERTEX.z;
	if (raw > 0.0) {
		alpha *= clamp((scene_depth - frag_depth) / depth_fade, 0.0, 1.0);
	}
	alpha *= smoothstep(0.0, near_fade, frag_depth);

	// Fresh soot is nearly black and only pales as the puff expands and thins out.
	vec3 tint = mix(soot_tint, aged_tint, clamp(pow(v_phase, 1.0 / aging), 0.0, 1.0));
	tint *= mix(1.0, 0.45 + 1.1 * n, structure);
	tint *= 1.0 + shade_variation * (v_seed - 0.5) * 2.0;
	ALBEDO = tint * COLOR.rgb;
	NORMAL = normalize(vec3(p * normal_bend, sqrt(max(1.0 - d * d, 0.02))));
	ROUGHNESS = 1.0;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
