shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 4.2;
uniform float plume_width = 0.32;
uniform float emission_energy : hint_range(0.1, 50.0) = 5.0;
uniform float flow_speed = 18.0;

uniform vec4 color_core : source_color = vec4(1.0, 1.0, 1.0, 1.0);       // Ultra-hot white core
uniform vec4 color_mid : source_color = vec4(0.4, 0.85, 1.0, 1.0);      // Electric cyan
uniform vec4 color_tail : source_color = vec4(0.1, 0.3, 0.95, 1.0);      // Saturated deep blue

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	float z_norm = clamp(VERTEX.z, 0.0, 1.0);
	float active_len = plume_length * mix(0.15, 1.0, pow(throttle, 1.1));
	VERTEX.z = z_norm * active_len;

	// Core tapers gracefully to a sharp supersonic needle
	float taper = pow(1.0 - z_norm, 1.4);
	float radius = plume_width * mix(0.4, 0.85, throttle) * taper;
	VERTEX.xy *= radius;

	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float active_len = plume_length * mix(0.15, 1.0, pow(throttle, 1.1));
	float axial = clamp(v_local_pos.z / max(active_len, 0.001), 0.0, 1.0);

	// Longitudinal streaking noise (stretched along Y)
	vec2 flow_uv = vec2(UV.x * 2.5, UV.y * 0.35 - TIME * flow_speed * 0.1);
	float streak1 = texture(noise_texture, flow_uv).r;
	float streak2 = texture(noise_texture, vec2(flow_uv.x * 2.1 + 0.35, flow_uv.y * 1.6 - TIME * flow_speed * 0.14)).g;
	float streaks = mix(streak1, streak2, 0.5);

	// Axial attenuation
	float axial_falloff = pow(1.0 - axial, 1.6);

	// View-angle rim thickness
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(v_local_pos, 1.0)).xyz);
	vec3 norm = normalize(v_world_normal);
	float rim = 1.0 - abs(dot(view_dir, norm));
	float thickness = pow(rim, 0.7);

	// Head-on view alignment
	vec3 local_z_world = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float head_on = pow(clamp(dot(view_dir, -local_z_world), 0.0, 1.0), 1.5);

	// Throttle energy curve
	float t_factor = mix(0.1, 1.0, pow(throttle, 1.3));
	float flame_val = (streaks * 0.5 + 0.6) * axial_falloff * (thickness * 0.7 + head_on * 1.5 + 0.25) * t_factor;

	// Color gradient along flame
	vec3 col = mix(color_tail.rgb, color_mid.rgb, smoothstep(0.75, 0.2, axial));
	col = mix(col, color_core.rgb, smoothstep(0.35, 0.02, axial) * (streaks * 0.4 + 0.6));

	// Soft depth fade
	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -view_coords.z / view_coords.w;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) * 4.0, 0.0, 1.0);

	ALBEDO = col * flame_val * emission_energy;
	ALPHA = clamp(flame_val * depth_fade, 0.0, 1.0);
}
