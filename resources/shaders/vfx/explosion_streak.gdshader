shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Incandescent fragments flung out of the blast. The process material aligns each particle's Y
// axis to its velocity; the quad is stretched along it behind the particle and turned around it to
// face the camera, so streaks read from any angle.
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float heat_bias : hint_range(0.0, 1.0) = 0.5;
// Streak length and width per unit of particle scale.
uniform float stretch = 4.0;
uniform float width = 0.3;

#include "res://resources/shaders/vfx/explosion_common.gdshaderinc"

varying float v_age;

void vertex() {
	v_age = particle_age(INSTANCE_CUSTOM);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float size = length(axis);
	axis = size > 0.0001 ? axis / size : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(axis, normalize(CAMERA_POSITION_WORLD - center));
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	// Fragments slow down as they cool, so the streak shortens with age.
	float length_now = size * stretch * (1.0 - 0.65 * v_age);
	VERTEX = center + side * VERTEX.x * size * width + axis * (VERTEX.y - 0.5) * length_now;
	MODELVIEW_MATRIX = VIEW_MATRIX;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float core = exp(-across * across * 6.0) * (1.0 - smoothstep(0.15, 1.0, along));
	float heat = (1.0 - v_age) * (1.0 - along * 0.6);
	ALBEDO = (fire_ramp(heat, heat_bias) + vec3(1.2, 0.8, 0.4) * (1.0 - along) * (1.0 - v_age)) * intensity;
	ALPHA = clamp(core * pow(1.0 - v_age, 1.4), 0.0, 1.0);
}
