shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha, shadows_disabled, diffuse_lambert_wrap, specular_disabled;

// Lit billow for camera-facing particle quads: each particle is born as fire and burns out into
// smoke in place, so the fireball rolls over into its own cloud instead of cross-fading into a
// separate one. A fake sphere normal lets the sun and the blast light shade every puff.
// The opaque core writes depth so the volumetric clouds, composited after the transparent pass,
// stop at the blast instead of being drawn over it.
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float seed_offset = 0.0;
// Share of the particle life spent burning; 0 gives plain smoke.
uniform float burn : hint_range(0.0, 1.0) = 0.35;
uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float heat_bias : hint_range(0.0, 1.0) = 0.5;
// 0 = pale grey warhead smoke, 1 = black oily fuel smoke.
uniform float soot : hint_range(0.0, 1.0) = 0.6;
uniform float density : hint_range(0.0, 2.0) = 1.0;

#include "res://resources/shaders/vfx/explosion_common.gdshaderinc"

varying float v_age;
varying float v_seed;
varying float v_spin;

void vertex() {
	v_age = particle_age(INSTANCE_CUSTOM);
	v_seed = hash11(float(INSTANCE_ID) + seed_offset);
	v_spin = INSTANCE_CUSTOM.x;

	float size = length(MODEL_MATRIX[0].xyz);
	VERTEX = vec3(rotate2(VERTEX.xy, v_spin) * size, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float radius = length(p);
	vec2 q = p * (1.3 + v_seed * 0.7) + vec2(v_seed * 17.3, v_seed * 9.1);
	vec2 drift = TIME * vec2(0.04, 0.07) + v_age * vec2(0.6, -0.9);
	// Domain-warped noise turns the round card into cauliflower-like lumps that roll as it ages.
	vec2 warp = vec2(fbm3(q * 1.4 + drift), fbm3(q * 1.4 + vec2(5.2, 1.3) - drift)) - 0.5;
	float n = fbm3(q * 2.1 + warp * 1.8 + drift * 0.5);

	// Lumpy silhouette whose edge erodes further as the cloud ages and thins out.
	float lumpy_radius = radius * (1.0 + (0.5 - n) * (0.9 + v_age * 0.4));
	float field = 1.0 - lumpy_radius;
	float body = smoothstep(0.0 + v_age * 0.12, 0.38 + v_age * 0.08, field);
	float fade = smoothstep(0.0, 0.035, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));

	// Sphere-ish normal in view space, roughened by the lumps so each one catches the light.
	vec2 view_xy = rotate2(p, v_spin);
	vec2 bump = vec2(dFdx(n), -dFdy(n)) / max(length(fwidth(p)), 0.0001);
	vec3 normal = vec3(view_xy * 0.8 + rotate2(bump, v_spin) * 0.22, sqrt(max(1.0 - radius * radius, 0.0)) + 0.25);
	NORMAL = normalize(normal);

	// Fire fills the young particle, then retreats into the noisy core and goes out.
	float burn_time = max(burn * (0.7 + 0.6 * v_seed), 0.0001);
	float core = clamp(1.2 - radius * 0.95 + (n - 0.5) * 1.1, 0.0, 1.3);
	float heat = burn > 0.0 ? clamp(core * (0.8 + 0.35 * v_seed) - v_age / burn_time, 0.0, 1.0) : 0.0;

	vec3 smoke = mix(vec3(0.21, 0.2, 0.19), vec3(0.04, 0.037, 0.034), soot);
	vec3 scorched = mix(vec3(0.13, 0.075, 0.04), vec3(0.045, 0.025, 0.014), soot);
	smoke = mix(scorched, smoke, smoothstep(0.0, 1.8, v_age / burn_time));
	ALBEDO = smoke * (0.65 + 0.7 * n) * (0.85 + 0.3 * v_seed);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.12 * (1.0 - soot));
	EMISSION = fire_ramp(heat, heat_bias) * glow * intensity;
	ALPHA = clamp(body * (0.75 + 0.5 * n) * fade * density * min(intensity, 1.0), 0.0, 1.0);
}
