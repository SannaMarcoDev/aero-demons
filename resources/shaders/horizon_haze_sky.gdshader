// Panorama sky with an atmospheric haze band at the horizon.
// Godot's own fog cannot do this: sky.glsl blends fog over the whole dome with a
// constant alpha, so it has no view direction to concentrate haze near the horizon.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 haze_color : source_color = vec3(0.53, 0.62, 0.73);
uniform float haze_top : hint_range(0.0, 1.0) = 0.34;
uniform float haze_bottom : hint_range(-1.0, 0.0) = -0.14;
uniform float haze_curve : hint_range(0.5, 8.0) = 2.4;
uniform float haze_strength : hint_range(0.0, 1.0) = 1.0;

void sky() {
	vec2 uv = vec2(atan(EYEDIR.x, -EYEDIR.z), acos(EYEDIR.y));
	uv.x = uv.x < 0.0 ? uv.x + TAU : uv.x;
	uv /= vec2(TAU, PI);
	float haze = 1.0 - smoothstep(haze_bottom, haze_top, EYEDIR.y);
	COLOR = mix(texture(panorama, uv).rgb, haze_color, pow(haze, haze_curve) * haze_strength);
}
