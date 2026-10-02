shader_type spatial;
render_mode unshaded;

#include "res://resources/shaders/vfx/energy_sphere_common.gdshaderinc"

uniform sampler3D energy_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 magenta : source_color = vec4(0.85, 0.035, 0.48, 1.0);
uniform vec4 ink : source_color = vec4(0.03, 0.006, 0.07, 1.0);
uniform vec4 spark : source_color = vec4(0.8, 0.72, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float animation_speed : hint_range(0.0, 3.0) = 1.0;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.08;
uniform float core_radius : hint_range(0.2, 0.7) = 0.4;
uniform float swirl : hint_range(0.0, 4.0) = 1.6;
uniform float pattern_scale : hint_range(0.3, 3.0) = 1.0;
uniform float phase = 0.0;

varying vec3 local_position;
varying flat vec3 local_camera;

void vertex() {
	local_position = VERTEX;
	local_camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

// Whirlpool around the view axis. Log-polar flow drags the pattern inwards along spiral arms; the
// spiral itself is fixed and spins rigidly, so it never shears into noise however long it runs.
float whirl(vec3 p, mat3 frame, float t, float twist, float spin, float inflow, float seed, out float rho) {
	vec3 v = p * frame;
	rho = acos(clamp(v.z / length(v), -1.0, 1.0)) * 0.63662;
	float lr = log(rho + 0.06);
	float warp = texture(energy_noise, es_turn(p, t * 0.07) * 0.55 + seed).r;
	float angle = atan(v.y, v.x) + twist * lr + t * spin + (warp - 0.5) * 2.6;
	vec3 q = vec3(cos(angle), sin(angle), 0.0) * 0.34 * pattern_scale + vec3(seed, seed * 1.7, lr * 0.3 + t * inflow);
	return texture(energy_noise, q).r;
}

void fragment() {
	float t = TIME * animation_speed + phase;
	float surge = es_surge(TIME + phase);
	mat3 frame = es_view_frame(local_camera);
	vec3 p = normalize(local_position);
	vec3 ray = normalize(local_position - local_camera);
	vec3 closest = local_camera - ray * dot(local_camera, ray);
	float impact2 = dot(closest, closest);
	float aa = max(fwidth(impact2) * 1.5, 0.0005);

	// Outer ink skin: dark spiral arms with luminous veins along their contours.
	float rho;
	float arms = whirl(p, frame, t, swirl, 0.3, 0.12, 0.0, rho);
	float detail = texture(energy_noise, es_turn(p, t * 0.3) * 3.1 + vec3(4.1, 1.3, -t * 0.2)).r;
	// Fine turbulence for the close shots, faded out before it can shimmer at range.
	float fine = texture(energy_noise, es_turn(p, t * 0.5) * 8.5 + vec3(1.9, -t * 0.35, 0.6)).r;
	float near = 1.0 - smoothstep(0.08, 0.3, fwidth(p.x) * 8.5);
	float cover = smoothstep(0.36, 0.54, arms * 0.7 + detail * 0.2 + mix(0.5, fine, near) * 0.1) * smoothstep(0.0, 0.25, rho);
	// Sparse, broken veins: one contour of the arms, lit only where the detail noise allows.
	float vein = 1.0 - smoothstep(0.0, 0.016 + fwidth(arms) * 1.5, abs(arms - 0.47));
	vein *= smoothstep(0.48, 0.6, texture(energy_noise, es_turn(p, -t * 0.15) * 0.9 + 2.7).r);
	vein *= 1.0 - smoothstep(0.03, 0.12, fwidth(arms)); // Far away the veins would only sparkle.
	vein *= mix(1.0, smoothstep(0.3, 0.6, fine), near);

	// Analytic interior spheres give true parallax: plasma layer, then the black eye with a hot rim.
	// ponytail: layered surfaces, not a volume integral; the sphere is never entered.
	const float inner_radius = 0.8;
	float inner_hit = 1.0 - smoothstep(inner_radius * inner_radius - aa, inner_radius * inner_radius + aa, impact2);
	vec3 inner_point = closest - ray * sqrt(max(inner_radius * inner_radius - impact2, 0.0));
	float inner_rho;
	float glow = whirl(inner_point / inner_radius, frame, t, swirl * 1.5, 0.5, 0.2, 7.0, inner_rho);
	float plasma = smoothstep(0.36, 0.72, glow) * inner_hit;
	vec3 cell = inner_point * 26.0;
	float star = es_hash2(floor(cell.xy) + floor(cell.z) * 7.13);
	float twinkle = smoothstep(0.2, 0.0, length(fract(cell) - 0.5)) * step(0.9, star) * (0.5 + 0.5 * sin(t * 7.0 + star * 60.0));
	twinkle *= (1.0 - smoothstep(0.15, 0.5, fwidth(cell.x))) * inner_hit;

	float core2 = core_radius * core_radius;
	float core_hit = 1.0 - smoothstep(core2 - aa, core2 + aa, impact2);
	float core_facing = sqrt(max(1.0 - impact2 / core2, 0.0));
	vec3 eye = vec3(0.002, 0.0, 0.006) + mix(violet.rgb, magenta.rgb, 0.6) * pow(1.0 - core_facing, 5.0) * 0.9;

	vec3 color = mix(ink.rgb * 1.6, eye, core_hit);
	plasma *= 1.0 - core_hit * 0.6;
	color = color * (1.0 - plasma * 0.6) + mix(violet.rgb, magenta.rgb, smoothstep(0.45, 0.8, glow)) * plasma * (0.26 + surge * 0.5);
	color += spark.rgb * twinkle * 1.2;
	color = mix(color, ink.rgb * 0.7, cover * 0.92);
	color += mix(violet.rgb, magenta.rgb, detail) * vein * (0.5 + surge * 1.2);

	float facing = clamp(dot(p, -ray), 0.0, 1.0);
	color += violet.rgb * pow(1.0 - facing, 3.0) * 0.45;
	float pulse = 1.0 + pulse_amount * sin(t * 1.3) + 0.02 * sin(t * 9.1) * sin(t * 5.3);
	// Unshaded HDR albedo is the emitted radiance (EMISSION is ignored in this path).
	ALBEDO = color * emission_strength * pulse * (1.0 + surge * 0.6);
}
