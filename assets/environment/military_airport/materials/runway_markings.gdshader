shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D asphalt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D markings : source_color, filter_linear_mipmap;
uniform sampler2D asphalt_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 white_paint : source_color = vec4(0.85, 0.85, 0.81, 1.0);
uniform vec4 yellow_paint : source_color = vec4(0.89, 0.7, 0.24, 1.0);
uniform vec3 white_channels = vec3(1.0, 0.0, 1.0);
uniform vec3 yellow_channels = vec3(0.0, 1.0, 0.0);

void fragment() {
	vec4 mask = texture(markings, UV);
	vec3 white_mask = mask.rgb * white_channels;
	float white = clamp(max(max(white_mask.r, white_mask.g), white_mask.b) * mask.a, 0.0, 1.0);
	float yellow = clamp(dot(mask.rgb, yellow_channels) * mask.a, 0.0, 1.0);
	// The texture contains road shoulders: repeating across its width creates extra roads.
	vec3 base = texture(asphalt, UV).rgb;
	ALBEDO = mix(mix(base, white_paint.rgb, white), yellow_paint.rgb, yellow);
	NORMAL_MAP = texture(asphalt_normal, UV).rgb;
	ROUGHNESS = 0.88;
}
