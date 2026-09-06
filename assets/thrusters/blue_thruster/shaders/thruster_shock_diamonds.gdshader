shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 5.5;
uniform float plume_width = 0.46;
uniform float emission_energy : hint_range(0.1, 40.0) = 5.5;

uniform float shock_count : hint_range(1.0, 12.0) = 6.0;
uniform float shock_decay : hint_range(0.2, 5.0) = 1.4;
uniform float shock_sharpness : hint_range(1.0, 10.0) = 4.0;
uniform float flow_speed = 12.0;

uniform vec4 color_core : source_color = vec4(1.0, 1.0, 1.0, 1.0);       // White-hot center
uniform vec4 color_shock : source_color = vec4(0.25, 0.8, 1.0, 1.0);     // Brilliant cyan / electric blue
uniform vec4 color_outer : source_color = vec4(0.08, 0.25, 0.9, 1.0);    // Deep royal blue / violet

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	float z_norm = clamp(VERTEX.z, 0.0, 1.0);
	float active_len = plume_length * mix(0.18, 1.0, pow(throttle, 1.2));
	VERTEX.z = z_norm * active_len;

	// Supersonic expansion envelope + periodic shock diamond pinch nodes
	float phase = pow(z_norm, 0.88) * shock_count * PI * 2.0;
	float envelope = mix(1.0, 0.35, pow(z_norm, 0.85));
	float diamond_pinch = 1.0 - 0.22 * cos(phase);
	float radial_scale = plume_width * mix(0.6, 1.0, throttle) * envelope * diamond_pinch;
	VERTEX.xy *= radial_scale;

	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float active_len = plume_length * mix(0.18, 1.0, pow(throttle, 1.2));
	float axial = clamp(v_local_pos.z / max(active_len, 0.001), 0.0, 1.0);

	float shock_throttle = smoothstep(0.2, 0.75, throttle);
	if (shock_throttle <= 0.001) {
		discard;
	}

	// Supersonic cells compress slightly downstream as the plume slows
	float phase = pow(axial, 0.88) * shock_count;
	float wave = 1.0 - abs(fract(phase) * 2.0 - 1.0);
	float diamond_node = pow(wave, shock_sharpness);
	float mach_disk = smoothstep(0.8, 1.0, wave);

	// Criss-cross oblique shock reflection waves
	float angle = UV.x * TAU;
	float obl1 = 0.5 + 0.5 * sin(phase * TAU + angle * 2.0);
	float obl2 = 0.5 + 0.5 * sin(phase * TAU - angle * 2.0);
	float shock_lattice = max(pow(obl1, 3.5), pow(obl2, 3.5));

	// High-speed jitter along flow
	float micro_flicker = 1.0 + 0.04 * sin(TIME * 50.0 + axial * 35.0);

	// Axial decay
	float decay = exp(-axial * shock_decay) * (1.0 - pow(axial, 2.6));

	// View thickness
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(v_local_pos, 1.0)).xyz);
	vec3 norm = normalize(v_world_normal);
	float rim = 1.0 - abs(dot(view_dir, norm));
	float view_thickness = pow(rim, 0.75);

	// Rear view boost (staring down nozzle)
	vec3 local_z_world = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float head_on = pow(clamp(dot(view_dir, -local_z_world), 0.0, 1.0), 2.0);

	// Combine components
	float shock_val = (diamond_node * 1.5 + mach_disk * 2.2 + shock_lattice * 0.9 + wave * 0.2) * decay * shock_throttle * micro_flicker;
	shock_val *= (view_thickness * 0.8 + head_on * 1.5 + 0.2);

	// Color gradient: Mach disc core is incandescent white, outer wave is electric cyan, envelope is deep royal blue
	vec3 col = mix(color_outer.rgb, color_shock.rgb, smoothstep(0.08, 0.65, diamond_node + shock_lattice * 0.4));
	col = mix(col, color_core.rgb, mach_disk * smoothstep(0.9, 0.1, axial));

	// Soft depth fade
	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -view_coords.z / view_coords.w;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) * 4.0, 0.0, 1.0);

	ALBEDO = col * shock_val * emission_energy;
	ALPHA = clamp(shock_val * depth_fade, 0.0, 1.0);
}
