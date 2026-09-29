#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D cloud_tex;
layout(set = 0, binding = 3) uniform sampler2D depth_tex;

layout(set = 0, binding = 2) uniform Params {
	mat4 inv_view;
	mat4 inv_proj;
	vec4 cam_pos;
	vec4 sun_dir;
	vec4 sun_color;
	vec4 deck;
	vec4 misc;
} p;

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(color_image);
	if (pix.x >= size.x || pix.y >= size.y) {
		return;
	}
	vec2 uv = (vec2(pix) + 0.5) / vec2(size);

	vec4 scene = imageLoad(color_image, pix);

	// One bilinear upsample, not an extra blur over translucent edges.
	vec4 cloud = texture(cloud_tex, uv);
	scene.rgb = scene.rgb * cloud.a + cloud.rgb;
	imageStore(color_image, pix, scene);
}
