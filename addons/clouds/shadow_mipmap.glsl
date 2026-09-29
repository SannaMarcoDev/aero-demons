#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2DArray shadow_tex;
layout(r16f, set = 0, binding = 1) uniform restrict writeonly image2DArray out_mip;
layout(push_constant, std430) uniform Level { ivec4 size_mip; } level;

void main() {
	ivec3 pixel = ivec3(gl_GlobalInvocationID);
	if (any(greaterThanEqual(pixel.xy, level.size_mip.xy))) return;
	ivec3 source = ivec3(pixel.xy * 2, pixel.z);
	float transmission = 0.0;
	for (int y = 0; y < 2; ++y)
		for (int x = 0; x < 2; ++x)
			transmission += texelFetch(shadow_tex, source + ivec3(x, y, 0), level.size_mip.z).r;
	imageStore(out_mip, pixel, vec4(transmission * 0.25));
}
