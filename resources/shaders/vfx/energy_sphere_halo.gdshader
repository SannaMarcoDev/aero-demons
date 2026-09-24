shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform float halo_strength : hint_range(0.0, 4.0) = 0.65;
uniform float halo_width : hint_range(0.01, 0.4) = 0.13;
uniform float animation_speed = 0.35;
uniform float pulse_amount = 0.055;
uniform float phase = 0.0;
varying vec3 local_position;
varying flat vec3 local_camera;

void vertex() {
	local_position = VERTEX;
	local_camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(local_position - local_camera);
	vec3 closest = local_camera - ray * dot(local_camera, ray);
	float impact = length(closest);
	float solid_radius = 1.0 / (1.0 + halo_width);
	float band = clamp((impact - solid_radius) / (1.0 - solid_radius), 0.0, 1.0);
	// Back faces are hidden by the opaque sphere; fade continuously to the outer silhouette.
	float glow = exp(-band * 4.5) * (1.0 - smoothstep(0.45, 1.0, band));
	float t = TIME * animation_speed + phase;
	ALBEDO = violet.rgb * halo_strength * glow * (1.0 + pulse_amount * sin(t * 1.1));
	ALPHA = 1.0;
}
