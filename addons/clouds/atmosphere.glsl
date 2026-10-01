#[compute]
#version 450

// Aerial perspective on opaque geometry, after the sky and before transparents.
// With the cloud shadow cache bound, the sunlit part of the haze is shadowed
// by the clouds along each view ray: shafts, darker air under cloud banks.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc; vec4 atm_a; vec4 atm_b; vec4 atm_c;
} p;
layout(set = 0, binding = 3) uniform sampler2DArray shadow_tex;
// x = temporal jitter seed, y = 1 when shadow_tex holds the live cloud shadows.
layout(push_constant, std430) uniform Frame { vec4 frame; } pc;
#include "atmosphere.glslinc"

// Rays toward or just below the horizon are integrated this far.
const float SKY_DISTANCE = 1e6;

float frame_jitter(ivec2 pix) {
	return fract(52.9829189 * fract(dot(vec2(pix) + pc.frame.x * 5.588238,
		vec2(0.06711056, 0.00583715))));
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(color_image);
	if (any(greaterThanEqual(pix, size))) return;
	float d = texelFetch(depth_tex, pix, 0).r;
	vec2 uv = (vec2(pix) + 0.5) / vec2(size);
	vec3 ro = p.cam_pos.xyz;
	vec4 color = imageLoad(color_image, pix);
	vec3 dir;
	float dist;
	if (d <= 0.0) {
		vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
		dir = normalize((p.inv_view * vec4(normalize(vp.xyz / vp.w), 0.0)).xyz);
		if (dir.y >= 0.0) {
			// Sky3D already contains the air's light; only remove what the
			// clouds' shadows take away from it (shafts toward the horizon).
			float vis = path_sun_visibility(ro, dir, SHADOW_RANGE, frame_jitter(pix), pc.frame.y > 0.5);
			float h0 = ro.y - p.atm_a.w;
			vec3 near_transmittance = exp(-atm_optical_depth(h0, h0 + dir.y * SHADOW_RANGE, SHADOW_RANGE));
			if (vis < 1.0) {
				vec3 loss = (atm_color(dir, 1.0) - atm_color(dir, vis)) * (1.0 - near_transmittance);
				color.rgb = max(color.rgb - loss, color.rgb * 0.35);
			}
			// Sky3D has no low haze: fade its horizon into the same air the
			// ground below converges to, so both sides meet without a seam.
			// Only air beyond a vertical ray's is added: the zenith stays Sky3D.
			vec3 far_depth = atm_optical_depth(h0, h0 + dir.y * SKY_DISTANCE, SKY_DISTANCE);
			vec3 zenith_depth = atm_optical_depth(h0, h0 + SKY_DISTANCE, SKY_DISTANCE);
			float cover = 1.0 - exp(-p.atm_c.y * max(far_depth.g - zenith_depth.g, 0.0));
			if (cover > 0.001) {
				vec3 far_transmittance = exp(-far_depth);
				vec3 shadowed = (1.0 - near_transmittance) / max(1.0 - far_transmittance, vec3(1e-4));
				vec3 air = mix(atm_color(dir, 1.0), atm_color(dir, vis), clamp(shadowed, 0.0, 1.0));
				color.rgb = mix(color.rgb, air, cover);
			}
			imageStore(color_image, pix, color);
			return;
		}
		// Below the horizon, past the far plane, the dome shows its dark ground
		// color: veil it like ground reached at the haze base, so far
		// water/terrain meets the horizon.
		dist = clamp((ro.y - p.atm_a.w) / -dir.y, 0.0, SKY_DISTANCE);
	} else {
		vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
		vec3 delta = (p.inv_view * vec4(vp.xyz / vp.w, 1.0)).xyz - ro;
		dist = length(delta);
		dir = delta / max(dist, 1e-3);
	}
	float h0 = ro.y - p.atm_a.w;
	vec3 transmittance = exp(-atm_optical_depth(h0, h0 + dir.y * dist, dist));
	float vis = path_sun_visibility(ro, dir, dist, frame_jitter(pix), pc.frame.y > 0.5);
	// Shadows are only known for the first SHADOW_RANGE: air beyond it stays
	// sunlit, so the sub-horizon fill does not converge to shadowed skylight.
	float near = min(dist, SHADOW_RANGE);
	vec3 near_transmittance = exp(-atm_optical_depth(h0, h0 + dir.y * near, near));
	color.rgb = color.rgb * transmittance + atm_color(dir, vis) * (1.0 - near_transmittance)
		+ atm_color(dir, 1.0) * (near_transmittance - transmittance);
	imageStore(color_image, pix, color);
}
