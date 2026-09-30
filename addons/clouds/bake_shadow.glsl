#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc;
} p;
layout(r16f, set = 0, binding = 1) uniform restrict writeonly image2DArray out_shadow;
layout(set = 0, binding = 2) uniform sampler3D noise_tex;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
#include "density.glslinc"

// Each invocation integrates ONE sun-aligned column from top to bottom.
// Array layers are altitude boundaries, including both ends of the cloud slab.
// Horizontal-only mipmaps must NOT average illumination between altitudes.
// Unlike the cloud lighting cache, this includes clear air between/under banks.
void main() {
	ivec2 column = ivec2(gl_GlobalInvocationID.xy);
	ivec3 size = imageSize(out_shadow);
	if (any(greaterThanEqual(column, size.xy))) return;
	vec2 foot = ((vec2(column) + 0.5) / vec2(size.xy) - 0.5) * p.deck.w;
	float dy = (p.deck.y - p.deck.x) / float(size.z - 1);
	vec2 slope = p.sun_dir.xz / p.sun_dir.y;
	// Bounded bake workload; near-horizontal sunlight needs higher sampling.
	// ponytail: max 64 samples/slab; adaptive integration if sub-degree suns matter.
	int steps = clamp(int(ceil(dy / (64.0 * p.sun_dir.y))), 1, 64);
	float ds = dy / (float(steps) * p.sun_dir.y);
	float tau = 0.0;
	imageStore(out_shadow, ivec3(column, size.z - 1), vec4(1.0));
	for (int h = size.z - 2; h >= 0; --h) {
		if (tau < 16.0) {
			for (int j = 0; j < steps; ++j) {
				float y = p.deck.x + (float(h + 1) - (float(j) + 0.5) / float(steps)) * dy;
				vec2 xz = foot + slope * (y - p.deck.x);
				vec3 pos = vec3(xz.x, y, xz.y);
				tau += density_at(pos, shape_distance(pos)) * ds;
				if (tau >= 16.0) break;
			}
		}
		// Filter transmission, not optical depth: sub-texel gaps remain gaps.
		imageStore(out_shadow, ivec3(column, h), vec4(exp(-min(tau, 16.0))));
	}
}
