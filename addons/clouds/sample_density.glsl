#[compute]
#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc;
} p;
layout(std430, set = 0, binding = 1) restrict writeonly buffer Result { float density; } result;
layout(set = 0, binding = 2) uniform sampler3D noise_tex;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
layout(push_constant, std430) uniform Probe { vec4 position; } probe;
#include "density.glslinc"

void main() {
	vec3 pos = probe.position.xyz;
	result.density = density_at(pos, shape_distance(pos));
}
