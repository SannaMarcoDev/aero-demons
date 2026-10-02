// Shared helpers for the explosion particle shaders. Kept free of TIME so the replay can swap the
// clock in each including shader without touching this file.

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + 1.0), f.x),
		f.y
	);
}

float fbm3(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.13 + 7.1) * 0.3 + value_noise(p * 4.37 - 3.7) * 0.15;
}

vec2 rotate2(vec2 p, float angle) {
	return vec2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle));
}

// ParticleProcessMaterial stores the age in CUSTOM.y and the particle's own (randomised) share of
// the emitter lifetime in CUSTOM.w; their ratio is the true 0..1 life of this particle.
float particle_age(vec4 custom) {
	return clamp(custom.y / max(custom.w, 0.0001), 0.0, 1.0);
}

// Blackbody-ish ramp in HDR: deep red embers, orange flame, yellow-white core. `bias` shifts the
// whole ramp hotter (towards 1) or cooler (towards 0) per blast variant.
vec3 fire_ramp(float heat, float bias) {
	float h = clamp(heat + (bias - 0.5) * 0.4, 0.0, 1.0);
	vec3 color = mix(vec3(0.35, 0.015, 0.0), vec3(2.2, 0.28, 0.02), smoothstep(0.02, 0.35, h));
	color = mix(color, vec3(4.6, 1.35, 0.16), smoothstep(0.3, 0.68, h));
	color = mix(color, vec3(7.5, 5.0, 2.1), smoothstep(0.66, 0.97, h));
	// Fade on the unbiased heat, so a hot variant does not make burnt-out smoke glow.
	return color * smoothstep(0.0, 0.08, heat);
}
