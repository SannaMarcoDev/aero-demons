shader_type spatial;
// One camera-facing ribbon per MultiMesh instance; the vertex stage rebuilds every bolt from TIME.
// Hot cores write depth so the volumetric clouds, composited later, stop in front of them.
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;

#include "res://resources/shaders/vfx/energy_sphere_common.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 spark : source_color = vec4(0.8, 0.72, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float phase = 0.0;
uniform float arc_rate : hint_range(0.0, 3.0) = 1.0;
// Hot core and halo half-width in metres; distant bolts keep a minimum on-screen width and dim instead.
uniform float arc_width = 2.5;
uniform float glow_width = 11.0;
uniform float min_pixels = 1.2;

varying float v_side;
varying float v_core;
varying float v_energy;

// Piecewise-linear value noise: straight segments between random knots read as lightning.
float jag(float s, float frequency, float seed) {
	float x = s * frequency;
	float i = floor(x);
	return mix(es_hash2(vec2(i, seed)), es_hash2(vec2(i + 1.0, seed)), x - i) - 0.5;
}

// Crawling bolts hop along a great circle just above the surface; jumping bolts leap outwards.
vec3 bolt(float s, vec2 seed, float flick, float jump) {
	vec3 a = es_direction(seed);
	vec3 side = normalize(cross(a, es_direction(seed + 5.3)));
	vec3 normal = cross(a, side);
	float span = mix(0.18, 0.7, es_hash2(seed + 2.1)) * (1.0 - jump * 0.55);
	vec3 dir = a * cos(span * s) + side * sin(span * s);
	float lift = mix(0.02, 0.1, es_hash2(seed + 3.7)) * sin(3.14159 * s);
	float leap = mix(0.35, 0.95, es_hash2(seed + 4.4)) * pow(s, 0.8);
	float pin = mix(sin(3.14159 * s), sqrt(s), jump);
	float amplitude = (0.025 + span * 0.09 + jump * 0.05) * pin;
	vec3 offset = normal * (jag(s, 6.0, seed.x) + jag(s, 13.0, seed.y) * 0.5 + jag(s, 29.0, flick) * 0.28);
	offset += dir * (jag(s, 9.0, seed.x + 1.0) * 0.6 + jag(s, 21.0, flick + 3.0) * 0.3);
	return dir * (1.0 + mix(lift, leap, jump)) + offset * amplitude;
}

void vertex() {
	float id = float(INSTANCE_ID);
	float s = UV.x;
	float side = UV.y * 2.0 - 1.0;
	float clock = TIME + phase;
	float surge_age = es_surge_age(clock);
	bool burst = es_hash(id * 9.1) > 0.68;
	float epoch;
	float age;
	float life;
	float fire = 1.0;
	if (burst) {
		// Surge slots all strike together at the start of each surge and reach further out.
		epoch = floor((clock - surge_age) * 8.0);
		age = surge_age - es_hash(id) * 0.12;
		life = mix(0.3, 0.55, es_hash2(vec2(id, epoch)));
	} else {
		float period = mix(0.7, 1.9, es_hash(id * 3.7)) / max(arc_rate, 0.01);
		float local = clock + es_hash(id) * period;
		epoch = floor(local / period);
		age = local - epoch * period;
		life = mix(0.09, 0.28, es_hash2(vec2(id, epoch)));
		fire = step(es_hash2(vec2(epoch, id + 0.5)), 0.5 + es_surge(clock) * 0.5);
	}
	float flick = floor(clock * 20.0) + id * 31.0;
	float energy = fire * step(0.0, age) * step(age, life) * smoothstep(0.0, 0.015, age) * sqrt(max(1.0 - age / life, 0.0));
	energy *= 0.65 + 0.35 * es_hash2(vec2(flick, id));
	vec2 seed = vec2(id * 13.7 + epoch * 1.31, epoch * 0.73 + id);
	float jump = burst ? 1.0 : step(0.62, es_hash2(seed + 9.9));
	vec3 view = (MODELVIEW_MATRIX * vec4(bolt(s, seed, flick, jump), 1.0)).xyz;
	vec3 ahead = (MODELVIEW_MATRIX * vec4(bolt(s + 0.02, seed, flick, jump), 1.0)).xyz;
	float pixel = max(-view.z, 0.0) * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float taper = mix(0.45 + 0.55 * sin(3.14159 * s), 1.0 - 0.75 * s, jump) * (burst ? 1.5 : 1.0);
	float core = max(arc_width * taper, min_pixels * pixel);
	float halo = max(glow_width * taper, core * 3.0);
	v_core = core / halo;
	v_energy = energy * min(arc_width * taper / core, 1.0);
	v_side = side;
	view += normalize(cross(ahead - view, view)) * side * halo;
	// Idle slots collapse to a point and rasterize nothing.
	POSITION = PROJECTION_MATRIX * vec4(energy > 0.0 ? view : (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, 1.0);
}

void fragment() {
	float d = abs(v_side);
	float core = 1.0 - smoothstep(v_core * 0.35, v_core, d);
	float halo = exp(-d * d * 7.0) * (1.0 - d);
	vec3 radiance = (spark.rgb * core * 5.0 + violet.rgb * halo * 1.6) * v_energy * emission_strength;
	// Straight alpha (fog-safe) carrying a premultiplied glow.
	ALPHA = max(clamp((core + halo * 0.5) * v_energy, 0.0, 1.0), 0.0005);
	ALBEDO = min(radiance / ALPHA, vec3(30000.0));
	DEPTH = core * v_energy > 0.4 ? FRAGCOORD.z : textureLod(depth_texture, SCREEN_UV, 0.0).r + 2e-7;
}
