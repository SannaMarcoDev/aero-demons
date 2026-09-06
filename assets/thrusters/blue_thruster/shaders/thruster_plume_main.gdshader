shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 5.5;
uniform float plume_width = 0.52;
uniform float emission_energy : hint_range(0.1, 40.0) = 3.0;
uniform float flow_speed = 14.0;
uniform float turbulence_amount : hint_range(0.0, 2.0) = 0.75;

// Major exhaust colors
uniform vec4 color_nozzle : source_color = vec4(0.7, 0.9, 1.0, 1.0);     // Hot electric cyan nozzle lip
uniform vec4 color_body : source_color = vec4(0.12, 0.45, 1.0, 1.0);     // Main vivid flame body
uniform vec4 color_tail : source_color = vec4(0.48, 0.08, 0.8, 1.0);     // Violet/deep purple tail

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	float z_norm = clamp(VERTEX.z, 0.0, 1.0);
	float active_len = plume_length * mix(0.2, 1.0, pow(throttle, 1.2));
	VERTEX.z = z_norm * active_len;

	// Supersonic aerodynamic expansion: expands slightly behind nozzle, then tapers
	float expansion = 1.0 + 0.32 * sin(z_norm * PI) * (1.0 - z_norm * 0.45);
	float active_width = plume_width * mix(0.65, 1.0, throttle) * expansion;
	VERTEX.xy *= active_width;

	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float active_len = plume_length * mix(0.2, 1.0, pow(throttle, 1.2));
	float axial = clamp(v_local_pos.z / max(active_len, 0.001), 0.0, 1.0);

	// High-speed longitudinal flow streaks
	vec2 flow_uv1 = vec2(UV.x * 3.5, UV.y * 0.35 - TIME * flow_speed * 0.11);
	vec2 flow_uv2 = vec2(UV.x * 5.0 + 0.35, UV.y * 0.8 - TIME * flow_speed * 0.17);

	float n1 = texture(noise_texture, flow_uv1).r;
	float n2 = texture(noise_texture, flow_uv2).g;
	float noise = mix(n1, n2, 0.45);

	// Boundary breakup and turbulent erosion
	float erosion = mix(1.0, 0.4 + noise * 1.0, turbulence_amount * smoothstep(0.08, 0.85, axial));

	// Longitudinal density falloff along the plume
	float axial_falloff = pow(1.0 - axial, 1.2);

	// View-angle cylinder thickness (Fresnel / limb brightening)
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(v_local_pos, 1.0)).xyz);
	vec3 norm = normalize(v_world_normal);
	float rim = 1.0 - abs(dot(view_dir, norm));
	float view_fade = pow(rim, 0.55);

	// Looking straight down the barrel (rear look-down)
	vec3 local_z_world = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float head_on = pow(clamp(dot(view_dir, -local_z_world), 0.0, 1.0), 2.0);

	// Throttle energy multiplier
	float t_energy = mix(0.12, 1.0, pow(throttle, 1.3));

	// Combine flame density with visible streaks
	float flame_density = axial_falloff * erosion * (noise * 0.5 + 0.6) * (view_fade * 1.1 + head_on * 1.4 + 0.25) * t_energy;

	// Temporal jitter / shimmer
	flame_density *= 1.0 + 0.04 * sin(TIME * 45.0 + UV.x * 20.0);

	// Color gradient along plume: hot cyan lip -> deep cobalt body -> violet tail
	vec3 col = mix(color_tail.rgb, color_body.rgb, smoothstep(0.85, 0.25, axial));
	col = mix(col, color_nozzle.rgb, smoothstep(0.3, 0.0, axial) * (noise * 0.25 + 0.75));

	// Soft depth fade against solid geometry
	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -view_coords.z / view_coords.w;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) * 4.0, 0.0, 1.0);

	ALBEDO = col * flame_density * emission_energy;
	ALPHA = clamp(flame_density * depth_fade, 0.0, 1.0);
}
