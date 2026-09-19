shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength = 0.12;
varying float blade_height;
void vertex() {
	blade_height = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance_fade = 1.0 - smoothstep(55.0, 92.0, distance(world, CAMERA_POSITION_WORLD));
	VERTEX.y *= distance_fade;
	VERTEX.xz += vec2(1.0, 0.45) * sin(TIME * 1.8 + world.x * 0.21 + world.z * 0.17) * UV.y * UV.y * wind_strength * distance_fade;
}
void fragment() {
	ALBEDO = COLOR.rgb * mix(vec3(0.035, 0.045, 0.012), vec3(0.12, 0.17, 0.039), blade_height);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = ALBEDO * 0.25;
}
