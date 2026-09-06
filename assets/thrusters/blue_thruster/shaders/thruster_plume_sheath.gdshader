shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 6.2;
uniform float plume_width = 0.72;
uniform float emission_energy : hint_range(0.1, 20.0) = 1.6;
uniform float flow_speed = 10.0;
uniform float turbulence_amount : hint_range(0.0, 2.0) = 0.9;

uniform vec4 color_halo : source_color = vec4(0.15, 0.35, 0.85, 1.0);
uniform vec4 color_fringe : source_color = vec4(0.3, 0.08, 0.6, 1.0);

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	float z_norm = clamp(VERTEX.z, 0.0, 1.0);
	float active_len = plume_length * mix(0.2, 1.0, pow(throttle, 1.2));
	VERTEX.z = z_norm * active_len;

	// Wider conical expansion and soft boundary
	float expansion = 1.0 + 0.45 * sin(z_norm * PI * 0.85);
	float active_width = plume_width * mix(0.6, 1.0, throttle) * expansion;
	VERTEX.xy *= active_width;

	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float active_len = plume_length * mix(0.2, 1.0, pow(throttle, 1.2));
	float axial = clamp(v_local_pos.z / max(active_len, 0.001), 0.0, 1.0);

	// Slow rolling turbulent noise
	vec2 flow_uv = vec2(UV.x * 1.5, UV.y * 0.45 - TIME * flow_speed * 0.05);
	float noise = texture(noise_texture, flow_uv).r;

	// Edge breakup
	float edge_mask = smoothstep(0.12, 0.88, noise);
	float axial_falloff = pow(1.0 - axial, 1.25);

	// Soft Fresnel rim
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(v_local_pos, 1.0)).xyz);
	vec3 norm = normalize(v_world_normal);
	float rim = 1.0 - abs(dot(view_dir, norm));
	float soft_rim = pow(rim, 1.1);

	float t_energy = mix(0.08, 1.0, pow(throttle, 1.4));
	float halo_density = axial_falloff * soft_rim * mix(0.45, edge_mask, turbulence_amount) * t_energy;

	vec3 col = mix(color_halo.rgb, color_fringe.rgb, axial);

	// Soft depth fade
	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -view_coords.z / view_coords.w;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) * 3.0, 0.0, 1.0);

	ALBEDO = col * halo_density * emission_energy;
	ALPHA = clamp(halo_density * depth_fade, 0.0, 1.0);
}
