shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D asphalt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D markings : source_color, filter_linear_mipmap;
uniform sampler2D asphalt_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 white_paint : source_color = vec4(0.85, 0.85, 0.81, 1.0);
uniform vec4 yellow_paint : source_color = vec4(0.89, 0.7, 0.24, 1.0);

void fragment() {
	vec4 mask = texture(markings, UV);
	float white = clamp(max(mask.r, mask.b) * mask.a, 0.0, 1.0);
	float yellow = clamp(mask.g * mask.a, 0.0, 1.0);
	vec3 base = texture(asphalt, UV * 4.0).rgb;
	ALBEDO = mix(mix(base, white_paint.rgb, white), yellow_paint.rgb, yellow);
	NORMAL_MAP = texture(asphalt_normal, UV * 4.0).rgb;
	ROUGHNESS = 0.88;
}
