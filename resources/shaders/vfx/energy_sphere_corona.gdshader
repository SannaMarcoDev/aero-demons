shader_type spatial;
// Back faces, so the shell still renders with the camera inside it. The march stops at the opaque
// scene and every fragment writes its own DEPTH, which the (late) depth test checks instead of the far
// shell: aircraft inside the corona are wrapped correctly.
// Dense smoke writes the depth of its front: the volumetric clouds are composited after transparents
// and would otherwise be drawn over the flames whenever a cloud bank sits behind the sphere.
render_mode unshaded, blend_mix, depth_draw_always, cull_front, shadows_disabled;

#include "res://resources/shaders/vfx/energy_sphere_common.gdshaderinc"

uniform sampler3D energy_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 magenta : source_color = vec4(0.85, 0.035, 0.48, 1.0);
uniform vec4 ink : source_color = vec4(0.03, 0.006, 0.07, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float animation_speed : hint_range(0.0, 3.0) = 1.0;
uniform float phase = 0.0;
// Mesh radius in sphere radii; the script keeps it just above the tallest flame.
uniform float outer_radius = 1.6;
uniform float flame_height : hint_range(0.1, 1.0) = 0.38;
uniform float flame_density : hint_range(0.0, 80.0) = 34.0;
uniform float plasma : hint_range(0.0, 4.0) = 1.0;
// Local travel direction scaled by how hard the flames lean (0..1); they stream away from it.
uniform vec3 travel = vec3(0.0);
uniform int steps : hint_range(12, 128) = 56;

varying vec3 local_position;
varying flat vec3 local_camera;
varying flat float radius_m;

void vertex() {
	local_position = VERTEX * outer_radius;
	local_camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz * outer_radius;
	radius_m = length(MODEL_MATRIX[0].xyz) / outer_radius;
}

// Ink tongues: noise is advected outwards along a fixed noise axis, so it rises without stretching.
float flame(vec3 p, float r, float h, float t, float surge, float gust) {
	vec3 n = p / r;
	float lean = length(travel);
	float behind = lean > 0.0 ? max(dot(n, -travel / lean), 0.0) * lean : 0.0;
	// Only the sideways part of the motion bends a tongue; straight behind it just streams longer.
	vec3 root = es_turn(normalize(n + (travel - n * dot(n, travel)) * h * 1.1), t * 0.12);
	vec3 q = root * 1.45 + vec3(0.0, 0.0, h * 0.7 - t * 0.5);
	float broad = texture(energy_noise, q).r;
	// The coarse octave warps the fine one: curling, smoky licks instead of straight spikes.
	float f = broad * 0.68 + texture(energy_noise, q * 2.4 + vec3(broad * 0.9, 7.4, -t * 0.7)).r * 0.32;
	float reach = (0.6 + gust * 1.0) * (1.0 + behind * 1.3) + surge * 0.35;
	float d = (f - 0.46 - h / reach * 0.26) * 7.0;
	return clamp(d, 0.0, 1.0) * smoothstep(0.02, 0.16, h);
}

void fragment() {
	vec3 ro = local_camera;
	vec3 rd = normalize(local_position - local_camera);
	float b = dot(ro, rd);
	float disc = b * b - dot(ro, ro) + outer_radius * outer_radius;
	if (disc <= 0.0) {
		discard;
	}
	float t0 = max(-b - sqrt(disc), 0.0);
	float t1 = -b + sqrt(disc);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	t1 = min(t1, length(view.xyz / view.w) / radius_m);
	if (t1 <= t0) {
		discard;
	}

	float t = TIME * animation_speed + phase;
	float surge = es_surge(TIME + phase);
	// About 10 m per step on a 500 m sphere; grazing rays through the long trail get the most samples.
	int count = int(clamp((t1 - t0) / 0.04, 10.0, float(steps)));
	float dt = (t1 - t0) / float(count);
	// Tongues gather along the silhouette, as in the reference; only a thin veil crosses the face.
	float impact = length(ro - rd * b);
	// Slow gusts make some sides flare much taller than others: an irregular, living silhouette.
	// The noise is so coarse that one sample per ray, where it grazes the sphere, is enough.
	float gust = texture(energy_noise, normalize(ro - rd * b + 0.0001) * 0.45 + vec3(t * 0.04, 1.7, -t * 0.03)).r;
	float limb = mix(0.06, 1.0, smoothstep(0.75, 1.02, impact));
	// The plasma skin only shows as the crisp rim; seen face-on it would veil the whirl.
	float rim = plasma * smoothstep(0.94, 1.0, impact);
	// Interleaved gradient noise trades step banding for fine static grain.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec3 color = vec3(0.0);
	float transmittance = 1.0;
	float front = -1.0;
	for (int i = 0; i < count; i++) {
		float march = t0 + (float(i) + jitter) * dt;
		vec3 p = ro + rd * march;
		float r = length(p);
		float h = (r - 1.0) / flame_height;
		// Plasma skin hugging the surface plus a faint aura: limb brightening comes from the path length.
		float skin = exp(-max(h, 0.0) * 11.0) * (1.0 + surge * 2.5) + exp(-max(h, 0.0) * 1.6) * 0.05 * smoothstep(outer_radius, outer_radius - 0.3, r);
		float d = flame(p, r, h, t, surge, gust) * limb * smoothstep(outer_radius, outer_radius - 0.15, r);
		vec3 emitted = mix(violet.rgb, magenta.rgb, 0.25) * skin * rim * 2.0;
		// Flames are lit from below: glowing roots, magenta fringes, black tips.
		emitted += mix(magenta.rgb, violet.rgb, clamp(h, 0.0, 1.0)) * d * (1.0 - d) * 1.2 * exp(-h * 2.5);
		emitted += violet.rgb * d * exp(-h * 12.0) * 1.0;
		float sigma = d * flame_density + skin * rim * 2.0;
		float a = 1.0 - exp(-sigma * dt);
		color += transmittance * (emitted * dt + ink.rgb * mix(1.0, 0.35, clamp(h, 0.0, 1.0)) * d * a);
		transmittance *= 1.0 - a;
		if (front < 0.0 && transmittance < 0.6) {
			front = march;
		}
		if (transmittance < 0.01) {
			break;
		}
	}
	// blend_mix with straight alpha keeps fog correct; emission-only pixels get a tiny alpha floor.
	float alpha = clamp(1.0 - transmittance, 0.0, 1.0);
	ALPHA = max(alpha, 0.0005);
	ALBEDO = min(color * emission_strength / ALPHA, vec3(30000.0));
	// Thin smoke keeps the depth already there (a hair closer, to pass the test), so it never punches a
	// hole in the clouds.
	vec4 clip = PROJECTION_MATRIX * vec4(normalize(VERTEX) * front * radius_m, 1.0);
	DEPTH = front > 0.0 ? clip.z / clip.w : depth + 2e-7;
}
