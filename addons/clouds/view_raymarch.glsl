#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc; vec4 atm_a; vec4 atm_b; vec4 atm_c;
} p;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image3D out_view;
layout(set = 0, binding = 2) uniform sampler3D noise_tex;
layout(set = 0, binding = 3) uniform sampler2D weather_tex;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
layout(set = 0, binding = 6) uniform sampler3D light_tex;
layout(set = 0, binding = 7) uniform sampler2DArray shadow_tex;
#include "cloud_march.glslinc"

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec3 size = imageSize(out_view);
	if (any(greaterThanEqual(pix, size.xy))) return;
	vec2 uv = (vec2(pix) + 0.5) / vec2(size.xy);
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 rd = normalize((p.inv_view * vec4(normalize(vp.xyz / vp.w), 0.0)).xyz);
	vec3 ro = p.cam_pos.xyz;
	// No opaque-depth clipping: neighbours must not leak terrain silhouettes
	// into the cache. The transparent draw still uses the ordinary depth test.
	vec2 range = cloud_ray_range(ro, rd, 110000.0);
	vec4 acc = vec4(0.0, 0.0, 0.0, 1.0);
	float air_vis = -1.0;
	float t = range.x;
	int steps = 0;
	for (int slice = 0; slice < size.z; slice++) {
		// Matches cloud_view.gdshaderinc; first slice is exactly clear air at 0 m.
		float distance = 1000.0 * (exp(float(slice) / float(size.z - 1) * log(111.0)) - 1.0);
		march_cloud_segment(ro, rd, min(range.y, distance), t, acc, steps, air_vis);
		imageStore(out_view, ivec3(pix, slice), acc);
	}
}
