shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D crown_normals : filter_linear_mipmap_anisotropic;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.12;
varying vec3 crown_normal;
varying float camera_distance;
varying mat3 object_to_view;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float bend = pow(clamp(VERTEX.y / 16.0, 0.0, 1.0), 2.0);
	VERTEX.xz += vec2(1.0, 0.4) * sin(TIME * 1.2 + origin.x * 0.13 + origin.z * 0.19) * bend * wind_strength;
	// Authored crown normals, not card-facing normals: no black backs on crossed impostors.
	crown_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	object_to_view = MODELVIEW_NORMAL_MATRIX;
	camera_distance = distance(CAMERA_POSITION_WORLD, origin);
}
void fragment() {
	vec4 tex = texture(atlas, UV);
	ALBEDO = tex.rgb * COLOR.rgb * vec3(0.82, 0.94, 0.86);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL = normalize(crown_normal);
	if (UV.y > 0.25) {
		vec3 baked = texture(crown_normals, UV).rgb * 2.0 - 1.0;
		NORMAL = normalize(object_to_view * baked);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
	BACKLIGHT = ALBEDO * 0.18;
	float fade = smoothstep(6000.0, 7000.0, camera_distance);
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dither < fade) { discard; }
}
