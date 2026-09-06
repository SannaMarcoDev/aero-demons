shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float emission_energy : hint_range(0.1, 30.0) = 8.0;
uniform vec4 color_idle : source_color = vec4(0.9, 0.25, 0.05, 1.0);
uniform vec4 color_thrust : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 color_afterburner : source_color = vec4(0.65, 0.85, 1.0, 1.0);
uniform vec4 color_core_hot : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float pulsation_speed = 35.0;
uniform float flicker_amount : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	if (dist > 1.0) {
		discard;
	}

	float angle = atan(center.y, center.x);

	// Flame holder geometry patterns (radial vanes + concentric rings)
	float vanes = 0.5 + 0.5 * cos(angle * 16.0);
	float rings = 0.5 + 0.5 * cos(dist * 28.0);
	float pattern = mix(rings, vanes, 0.4);

	// Temporal turbulent flicker
	float flicker = 1.0 + flicker_amount * sin(TIME * pulsation_speed + dist * 10.0)
		+ flicker_amount * 0.5 * cos(TIME * pulsation_speed * 1.7 + angle * 4.0);

	// Color blending based on throttle
	vec4 base_color = mix(color_idle, color_thrust, smoothstep(0.05, 0.6, throttle));
	base_color = mix(base_color, color_afterburner, smoothstep(0.6, 1.0, throttle));

	// White-hot center core
	float core = exp(-dist * dist * 3.5);
	vec3 final_color = mix(base_color.rgb, color_core_hot.rgb, core * smoothstep(0.3, 1.0, throttle));

	// Intensity modulation with throttle
	float throttle_curve = mix(0.15, 1.0, pow(throttle, 1.3));
	float intensity = (core * 2.0 + pattern * 0.8 + 0.2) * (1.0 - dist * 0.6) * throttle_curve * flicker;

	ALBEDO = final_color * intensity * emission_energy;
	ALPHA = smoothstep(1.0, 0.85, dist);
}
