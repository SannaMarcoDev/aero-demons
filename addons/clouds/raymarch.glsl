#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc; vec4 atm_a; vec4 atm_b; vec4 atm_c;
} p;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D out_clouds;
layout(set = 0, binding = 2) uniform sampler3D noise_tex;
layout(set = 0, binding = 3) uniform sampler2D weather_tex;
layout(set = 0, binding = 4) uniform sampler2D depth_tex;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
layout(set = 0, binding = 6) uniform sampler3D light_tex;
// Cloud shadow cache; p.cam_pos.w = 1 when it holds live shadows.
layout(set = 0, binding = 7) uniform sampler2DArray shadow_tex;
#include "density.glslinc"
#include "atmosphere.glslinc"

float scene_distance(vec2 uv) {
	float d = texture(depth_tex, uv).r;
	if (d <= 0.0) return 1e9;
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return length((p.inv_view * vec4(vp.xyz / vp.w, 1.0)).xyz - p.cam_pos.xyz);
}
float hg(float mu, float g) {
	float d = 1.0 + g * g - 2.0 * g * mu;
	return (1.0 - g * g) / (d * sqrt(d));
}
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(out_clouds);
	if (any(greaterThanEqual(pix, size))) return;
	vec2 uv = (vec2(pix) + 0.5) / vec2(size);
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 rd = normalize((p.inv_view * vec4(normalize(vp.xyz / vp.w), 0.0)).xyz);
	vec3 ro = p.cam_pos.xyz;
	float t0 = 0.0;
	float t1 = min(scene_distance(uv), 110000.0);
	if (abs(rd.y) < 1e-5) {
		if (ro.y <= p.deck.x || ro.y >= p.deck.y) t1 = 0.0;
	} else {
		float a = (p.deck.x - ro.y) / rd.y;
		float b = (p.deck.y - ro.y) / rd.y;
		t0 = max(0.0, min(a, b));
		t1 = min(t1, max(a, b));
	}
	float mu = dot(rd, p.sun_dir.xyz);
	float phase = 0.35 + 0.24 * mix(hg(mu, -0.2), hg(mu, 0.65), 0.8);
	vec3 haze = vec3(0.263, 0.380, 0.604) + p.sun_color.rgb
		* (pow(max(mu, 0.0), 8.0) * 3.14159265 * 0.30);
	vec4 acc = vec4(0.0, 0.0, 0.0, 1.0);
	// Sun seen by the air between the camera and the first cloud: computed
	// once, so distant bases are veiled by shadowed haze under the deck.
	float air_vis = -1.0;
	float t = t0;
	for (int i = 0; i < int(p.misc.y) && t < t1 && acc.a > 0.01; i++) {
		float dt = min(clamp(45.0 + t * 0.005, 45.0, 200.0), t1 - t);
		float tm = t + dt * 0.5;
		vec3 pos = ro + rd * tm;
		vec2 shape = textureLod(shape_tex, field_uv(pos), 0.0).rg;
		float sdf = shape.g;
		// One fetch: R is the eroded contour, G its conservative bound.
		// Never step by the noisy contour's unbounded slope. Include the
		// full detail support (310m) and half voxel diagonal (<180m) in the
		// skip margin; even the preceding half-step (<=100m) remains empty.
		if (sdf > 590.0) {
			t = tm + max(dt * 0.5, max(40.0, (sdf - 490.0) * 0.9));
			continue;
		}
		float d = density_at(pos, shape.r);
		d *= 1.0 - smoothstep(70000.0, 110000.0, tm);
		if (d > 0.000001) {
			vec2 tau = textureLod(light_tex, field_uv(pos), 0.0).rg;
			// deck.z darkens the inside: the cloud above hides the sky and
			// multiple scattering fades faster with depth (0.30 = original).
			float occlusion = mix(0.30, 1.0, p.deck.z);
			float sky_access = exp(-tau.y * occlusion);
			vec3 ambient = mix(vec3(0.025, 0.040, 0.075), vec3(0.22, 0.30, 0.44), sky_access);
			float sun = exp(-tau.x) * phase * 1.4 + 0.22 * exp(-tau.x * occlusion);
			vec3 light = ambient + p.sun_color.rgb * sun;
			if (p.atm_c.x > 0.5) {
				if (air_vis < 0.0)
					air_vis = path_sun_visibility(ro, rd, tm, 0.5, p.cam_pos.w > 0.5);
				Aerial air = atm_aerial(ro, rd, tm, air_vis);
				light = light * air.transmittance + air.inscatter;
			} else {
				light = mix(haze, light, exp(-tm * 0.000018));
			}
			float alpha = 1.0 - exp(-d * dt);
			acc.rgb += acc.a * alpha * light;
			acc.a *= 1.0 - alpha;
		}
		t += dt;
	}
	imageStore(out_clouds, pix, acc);
}
