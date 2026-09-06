shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D noise_texture : repeat_enable, filter_linear;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 6.5;
uniform float plume_width = 0.75;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.035;
uniform float flow_speed = 16.0;

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	float z_norm = clamp(VERTEX.z, 0.0, 1.0);
	float active_len = plume_length * mix(0.25, 1.0, throttle);
	VERTEX.z = z_norm * active_len;

	float expansion = 1.0 + 0.45 * sin(z_norm * PI * 0.85);
	float active_width = plume_width * mix(0.7, 1.0, throttle) * expansion;
	VERTEX.xy *= active_width;

	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float active_len = plume_length * mix(0.25, 1.0, throttle);
	float axial = clamp(v_local_pos.z / max(active_len, 0.001), 0.0, 1.0);

	// Throttle scaling
	float t_amount = mix(0.1, 1.0, pow(throttle, 1.2));
	if (t_amount <= 0.01) {
		discard;
	}

	// Multi-frequency scrolling noise for heat ripples
	vec2 flow_uv1 = vec2(UV.x * 2.5 + TIME * 0.4, UV.y * 1.2 - TIME * flow_speed * 0.09);
	vec2 flow_uv2 = vec2(UV.x * 4.0 - TIME * 0.6, UV.y * 2.2 - TIME * flow_speed * 0.14);

	vec2 offset1 = (texture(noise_texture, flow_uv1).rg - vec2(0.5)) * 2.0;
	vec2 offset2 = (texture(noise_texture, flow_uv2).rg - vec2(0.5)) * 2.0;
	vec2 normal_offset = (offset1 * 0.65 + offset2 * 0.35);

	// Smooth envelope: fades softly at nozzle, edges, and tail
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(v_local_pos, 1.0)).xyz);
	vec3 norm = normalize(v_world_normal);
	float rim = 1.0 - abs(dot(view_dir, norm));
	float envelope = pow(rim, 0.8) * pow(1.0 - axial, 0.8) * smoothstep(0.0, 0.1, axial);

	float strength = distortion_strength * envelope * t_amount;
	if (strength <= 0.0005) {
		discard;
	}

	vec2 distorted_uv = SCREEN_UV + normal_offset * strength;

	// Depth check to avoid refracting foreground objects
	float bg_depth = texture(depth_texture, SCREEN_UV).x;
	float distorted_depth = texture(depth_texture, distorted_uv).x;
	if (distorted_depth < bg_depth - 0.001) {
		distorted_uv = SCREEN_UV;
	}

	vec3 refracted_col = texture(screen_texture, distorted_uv).rgb;

	// Soft depth fade
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, bg_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -view_coords.z / view_coords.w;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) * 3.0, 0.0, 1.0);

	ALBEDO = refracted_col;
	ALPHA = clamp(envelope * t_amount * depth_fade * 1.5, 0.0, 0.7);
}
