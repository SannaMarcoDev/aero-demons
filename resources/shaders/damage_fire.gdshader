shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Draw material for the fire GPUParticles3D on a damaged airframe. Each particle is a
// camera-facing quad whose soft disc is eroded by 3D noise, so the sheet reads as torn
// flame licks rather than overlapping blobs. The erosion threshold rises with the
// particle's own age, which is what makes a lick burn away from the outside in.

uniform sampler2D heat_ramp : source_color, filter_linear;
uniform sampler3D flame_noise : filter_linear, repeat_enable;
uniform sampler2D depth_buffer : hint_depth_texture, filter_nearest;

// A lick spawns inside the wing skin, so without a depth fade the quad prints a hard
// straight seam where it cuts through the surface.
uniform float depth_fade : hint_range(0.0, 2.0) = 0.35;

uniform float noise_scale = 1.4;
uniform float noise_detail = 2.9;
// FastNoiseLite output clusters around 0.5, so raw samples modulate the disc by a few
// percent and every lick looks like the same smooth ellipse.
uniform float noise_contrast : hint_range(1.0, 8.0) = 2.6;
uniform float flow_speed = 1.1;
uniform float erosion : hint_range(0.0, 1.0) = 0.85;
uniform float burn_rate : hint_range(0.0, 1.5) = 0.72;
uniform float edge_softness : hint_range(0.02, 0.8) = 0.22;
uniform float core_size : hint_range(0.05, 1.0) = 0.42;
uniform float heat_gain : hint_range(0.2, 4.0) = 1.35;
uniform float energy = 4.5;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

varying float v_seed;
varying float v_phase;

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	v_phase = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = hash11(float(INSTANCE_ID) + 0.37);

	// Camera-facing billboard with the per-particle spin the process material wrote into
	// INSTANCE_CUSTOM.x, keeping the particle's own scale from MODEL_MATRIX.
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
	float disc = 1.0 - clamp(length(p), 0.0, 1.0);

	// Every particle shares the same UV, so seeding only the noise slice leaves them all
	// showing the same lick at different depths and the sheet stacks into visible layers.
	// Offsetting and scaling the sampled window per particle gives each one its own shape.
	vec2 nuv = UV * noise_scale * (0.75 + 0.5 * v_seed) + vec2(v_seed * 17.3, v_seed * 29.1);
	vec3 np = vec3(nuv, v_seed * 9.7 - TIME * flow_speed);
	float n = texture(flame_noise, np).r * 0.62
		+ texture(flame_noise, np * noise_detail + 3.1).r * 0.38;
	n = clamp((n - 0.5) * noise_contrast + 0.5, 0.0, 1.0);

	float shape = disc * mix(1.0, n, erosion);
	float threshold = v_phase * burn_rate;
	float mask = smoothstep(threshold, threshold + edge_softness, shape);

	// Hottest where the sheet is thickest and the fuel is freshest, so the base of the
	// flame runs white while the trailing licks fall to red.
	float heat = smoothstep(0.0, core_size, shape) * pow(1.0 - v_phase, 0.65);
	vec3 color = texture(heat_ramp, vec2(clamp(heat * heat_gain, 0.0, 1.0), 0.5)).rgb;

	float alpha = mask * COLOR.a * intensity;
	float raw = texture(depth_buffer, SCREEN_UV).x;
	if (raw > 0.0) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		alpha *= clamp((-(view.z / view.w) - (-VERTEX.z)) / depth_fade, 0.0, 1.0);
	}

	ALBEDO = color * COLOR.rgb * energy;
	ALPHA = alpha;
}
