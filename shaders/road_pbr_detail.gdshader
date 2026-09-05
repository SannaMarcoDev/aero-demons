shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Road Generator trimsheet texture (lane markings, shoulders, etc.)
uniform sampler2D markings_texture : source_color, filter_linear_mipmap, repeat_enable;

// High-resolution seamless PBR asphalt detail maps
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;

// Tiling & Mapping mode
uniform bool use_world_mapping = false;
uniform vec2 uv_detail_scale = vec2(2.0, 8.0);
uniform vec2 world_detail_scale = vec2(0.35, 0.35);

// Asphalt Appearance
uniform vec4 asphalt_tint : source_color = vec4(0.85, 0.85, 0.85, 1.0);
uniform float asphalt_roughness_mult : hint_range(0.0, 2.0) = 1.0;
uniform float normal_depth : hint_range(0.0, 3.0) = 1.2;

// Lane Markings Blending
// Note: markings_texture is sampled in Linear space by Godot (source_color hint).
// In Linear space, trimsheet bare asphalt is ~ rgb(0.046, 0.050, 0.046) and painted lines are > 0.5.
uniform float markings_threshold : hint_range(0.05, 0.5) = 0.20;
uniform float markings_softness : hint_range(0.01, 0.2) = 0.08;
uniform float markings_wear : hint_range(0.0, 1.0) = 0.25;
uniform float markings_roughness : hint_range(0.0, 1.0) = 0.55;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 1. Compute detail UV coordinates
	vec2 detail_uv;
	if (use_world_mapping) {
		detail_uv = v_world_pos.xz * world_detail_scale;
	} else {
		// Each lane in the trimsheet occupies 1/8 (0.125) in UV.x.
		// Mapping fract(UV.x * 8.0) scales each lane smoothly from 0.0 to 1.0 across its width.
		vec2 road_coords = vec2(fract(UV.x * 8.0), UV.y);
		detail_uv = road_coords * uv_detail_scale;
	}

	// 2. Sample textures
	vec4 markings_sample = texture(markings_texture, UV);
	vec4 detail_col_sample = texture(detail_albedo, detail_uv);
	vec3 detail_norm_sample = texture(detail_normal, detail_uv).rgb;
	float detail_rough_sample = texture(detail_roughness, detail_uv).r;

	// 3. Detect painted lane markings vs bare asphalt in trimsheet
	// Linear space asphalt reference:
	vec3 ref_asphalt_linear = vec3(0.046, 0.050, 0.046);
	float marking_dist = length(markings_sample.rgb - ref_asphalt_linear);
	float marking_mask = smoothstep(
		markings_threshold - markings_softness,
		markings_threshold + markings_softness,
		marking_dist
	);

	// Subtle shoulder bevel darkening from trimsheet
	float shoulder_shading = clamp(markings_sample.g / 0.05, 0.5, 1.0);

	// 4. Blend Albedo
	vec3 base_asphalt = detail_col_sample.rgb * asphalt_tint.rgb * shoulder_shading;
	// Painted markings weathered with asphalt detail grain
	vec3 painted_line = markings_sample.rgb * mix(vec3(1.0), detail_col_sample.rgb * 1.6, markings_wear);
	ALBEDO = mix(base_asphalt, painted_line, marking_mask);

	// 5. Blend Roughness
	float base_roughness = clamp(detail_rough_sample * asphalt_roughness_mult, 0.05, 0.98);
	ROUGHNESS = mix(base_roughness, markings_roughness, marking_mask);

	// 6. Normal Mapping
	if (use_world_mapping) {
		// Screen-space cotangent frame normal perturbation for world-mapped coordinates
		vec3 q0 = dFdx(VERTEX);
		vec3 q1 = dFdy(VERTEX);
		vec2 st0 = dFdx(detail_uv);
		vec2 st1 = dFdy(detail_uv);
		vec3 n = normalize(NORMAL);
		vec3 t = q1 * st0.y - q0 * st1.y;
		vec3 b = q0 * st1.x - q1 * st0.x;
		vec3 n_tex = detail_norm_sample * 2.0 - 1.0;
		n_tex.xy *= normal_depth;
		mat3 tbn = mat3(normalize(cross(n, t)), normalize(cross(b, n)), n);
		NORMAL = normalize(tbn * n_tex);
	} else {
		// Native tangent-space normal map (mesh has generated tangents)
		NORMAL_MAP = detail_norm_sample;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
