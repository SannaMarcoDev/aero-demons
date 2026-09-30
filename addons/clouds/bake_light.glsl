#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc;
} p;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image3D out_light;
layout(set = 0, binding = 2) uniform sampler3D noise_tex;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
#include "density.glslinc"

float optical_depth(vec3 pos, vec3 direction) {
	float tau = 0.0;
	float t = 0.0;
	for (int i = 0; i < 40; i++) {
		float dt = 75.0 + float(i) * 12.0;
		vec3 q = pos + direction * (t + dt * 0.5);
		if (q.y >= p.deck.y || q.y <= p.deck.x) break;
		tau += density_at(q, shape_distance(q)) * dt;
		t += dt;
	}
	return tau;
}
void main() {
	ivec3 pix = ivec3(gl_GlobalInvocationID);
	ivec3 size = imageSize(out_light);
	if (any(greaterThanEqual(pix, size))) return;
	vec3 uv = (vec3(pix) + 0.5) / vec3(size);
	vec3 pos = vec3((uv.x - 0.5) * p.deck.w, mix(p.deck.x, p.deck.y, uv.y), (uv.z - 0.5) * p.deck.w);
	// No visible medium further away than this interpolation-safe margin.
	vec2 tau = vec2(0.0);
	if (shape_distance(pos) < 1000.0) {
		tau.x = optical_depth(pos, p.sun_dir.xyz);
		tau.y = optical_depth(pos, vec3(0.0, 1.0, 0.0));
	}
	imageStore(out_light, pix, vec4(tau, 0.0, 0.0));
}
