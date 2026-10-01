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

const int SHADOW_STEPS = 16;
const float SHADOW_RANGE = 80000.0;

// Same lookup as cloud_shadow.gdshaderinc: sun transmittance at a world point.
float sun_visibility(vec3 pos) {
	if (pos.y >= p.deck.y) return 1.0;
	vec2 foot = pos.xz - p.sun_dir.xz / max(p.sun_dir.y, 1e-5) * (pos.y - p.deck.x);
	vec2 uv = foot / p.deck.w + 0.5;
	float top = float(textureSize(shadow_tex, 0).z - 1);
	float layer = clamp((pos.y - p.deck.x) / (p.deck.y - p.deck.x), 0.0, 1.0) * top;
	float lower = floor(layer);
	// One mip of horizontal blur keeps 16 jittered taps from sparkling.
	float a = textureLod(shadow_tex, vec3(uv, lower), 1.0).r;
	float b = textureLod(shadow_tex, vec3(uv, min(lower + 1.0, top)), 1.0).r;
	return clamp(mix(a, b, fract(layer)), 0.0, 1.0);
}

// Scattering-weighted fraction of the first 80 km of the ray that sees the sun.
float path_sun_visibility(vec3 ro, vec3 dir, float dist, ivec2 pix) {
	if (pc.frame.y < 0.5 || p.atm_c.w <= 0.0 || p.sun_dir.y <= 0.0) return 1.0;
	float len = min(dist, SHADOW_RANGE);
	float jitter = fract(52.9829189 * fract(dot(vec2(pix) + pc.frame.x * 5.588238,
		vec2(0.06711056, 0.00583715))));
	float h0 = ro.y - p.atm_a.w;
	float total = 0.0;
	float lit = 0.0;
	for (int i = 0; i < SHADOW_STEPS; i++) {
		// Quadratic spacing: dense near the camera where shafts are resolved.
		float f = (float(i) + jitter) / float(SHADOW_STEPS);
		float t = len * f * f;
		float h = h0 + dir.y * t;
		float density = p.atm_a.x * exp(-max(h, -2.0 * p.atm_a.y) / p.atm_a.y)
			+ AIR_BETA.g * p.atm_a.z * exp(-max(h, -2.0 * AIR_HEIGHT) / AIR_HEIGHT);
		float w = density * exp(-atm_optical_depth(h0, h, t).g) * f;
		total += w;
		lit += w * sun_visibility(ro + dir * t);
	}
	return mix(1.0, total > 0.0 ? lit / total : 1.0, p.atm_c.w);
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
			float vis = path_sun_visibility(ro, dir, SHADOW_RANGE, pix);
			if (vis >= 1.0) return;
			float h0 = ro.y - p.atm_a.w;
			vec3 veil = 1.0 - exp(-atm_optical_depth(h0, h0 + dir.y * SHADOW_RANGE, SHADOW_RANGE));
			vec3 loss = (atm_color(dir, 1.0) - atm_color(dir, vis)) * veil;
			color.rgb = max(color.rgb - loss, color.rgb * 0.35);
			imageStore(color_image, pix, color);
			return;
		}
		// Below the horizon, past the far plane, the dome shows its dark ground
		// color: veil it like ground reached at the haze base, so far
		// water/terrain meets the horizon.
		dist = clamp((ro.y - p.atm_a.w) / -dir.y, 0.0, 1e6);
	} else {
		vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
		vec3 delta = (p.inv_view * vec4(vp.xyz / vp.w, 1.0)).xyz - ro;
		dist = length(delta);
		dir = delta / max(dist, 1e-3);
	}
	float h0 = ro.y - p.atm_a.w;
	vec3 transmittance = exp(-atm_optical_depth(h0, h0 + dir.y * dist, dist));
	float vis = path_sun_visibility(ro, dir, dist, pix);
	// Shadows are only known for the first SHADOW_RANGE: air beyond it stays
	// sunlit, so the sub-horizon fill does not converge to shadowed skylight.
	float near = min(dist, SHADOW_RANGE);
	vec3 near_transmittance = exp(-atm_optical_depth(h0, h0 + dir.y * near, near));
	color.rgb = color.rgb * transmittance + atm_color(dir, vis) * (1.0 - near_transmittance)
		+ atm_color(dir, 1.0) * (near_transmittance - transmittance);
	imageStore(color_image, pix, color);
}
