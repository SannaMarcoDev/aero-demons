shader_type spatial;
// First transparent pass (render_priority -1): it rewrites only the already fogged opaque image, so fog is
// not applied twice and flames, tendrils and arcs are composited on top of the bent background.
render_mode unshaded, blend_mix, depth_draw_never, cull_front, fog_disabled, shadows_disabled;

#include "res://resources/shaders/vfx/energy_sphere_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 ink : source_color = vec4(0.03, 0.006, 0.07, 1.0);
// Mesh radius in sphere radii.
uniform float lens_radius = 3.4;
// Background pull at the silhouette, in sphere radii.
uniform float lens_strength : hint_range(0.0, 0.3) = 0.05;
uniform float pulse_strength : hint_range(0.0, 2.0) = 1.0;
uniform float phase = 0.0;

varying vec3 local_position;
varying flat vec3 local_camera;
varying flat vec3 centre;

void vertex() {
	local_position = VERTEX * lens_radius;
	local_camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz * lens_radius;
	vec4 view_centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_centre;
	// xy: centre in NDC, z: view depth of the centre (negative when it is behind the camera).
	centre = vec3(clip.xy / max(abs(clip.w), 0.0001), -view_centre.z);
}

void fragment() {
	vec3 rd = normalize(local_position - local_camera);
	float b = length(local_camera - rd * dot(local_camera, rd));
	// EMP shock: the limb of an expanding thin shell, launched by each surge.
	float age = es_surge_age(TIME + phase);
	float shell = 1.0 + age * 1.15;
	float width = 0.05 + age * 0.06;
	float ring = (sqrt(max(shell * shell - b * b, 0.0)) - sqrt(max((shell - width) * (shell - width) - b * b, 0.0))) / sqrt(2.0 * shell * width);
	// Keep the limb only: face-on the shell is thin and would tint the whole disc.
	ring = smoothstep(0.45, 1.0, ring) * pulse_strength * smoothstep(0.0, 0.08, age) * exp(-age * 1.1) * smoothstep(lens_radius, lens_radius - 0.5, shell);
	float shift = lens_strength * exp(-(b - 1.0) * 2.6) * step(1.0, b) + ring * 0.1;
	if (centre.z <= 0.0 || shift < 0.0015) {
		discard;
	}
	// The pixel's offset from the centre spans b sphere radii on screen: pull by shift / b of it.
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec2 uv = SCREEN_UV - (ndc - centre.xy) * 0.5 * min(shift / max(b, 1.0), 0.25);
	float depth = textureLod(depth_texture, uv, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth, 1.0);
	float radius_m = length(MODEL_MATRIX[0].xyz) / lens_radius;
	if (-view.z / view.w < centre.z - radius_m * 1.2) {
		uv = SCREEN_UV; // Never smear an aircraft in front of the sphere into the background.
	}
	vec3 color = textureLod(screen_texture, uv, 0.0).rgb;
	ALBEDO = color * (1.0 - ring * 0.45) + mix(ink.rgb, violet.rgb, 0.6) * ring * 0.5;
	ALPHA = smoothstep(0.0015, 0.006, shift);
}
