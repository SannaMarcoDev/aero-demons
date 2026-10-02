// Riva sample context (199.68 km of mesh chunks around the Terrain3D core): photo albedo (PAT orthophoto,
// Sentinel-2 outside Trentino, 8 m over 61 km, Sentinel-2 at 25.6 m beyond) with the core's material grain
// where its texels magnify.
// Keep the photo grading in step with riva_sample_surface.gdshader.
// Photo/cover textures: tools/terrain/fetch_riva_sample.cjs. Material coordinates are world metres.
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"
#include "res://resources/shaders/earth_curvature.gdshaderinc"

uniform sampler2D surface_noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meso_size : hint_range(16.0, 256.0) = 72.0;
// The 30 m DEM is smoother than the LiDAR: rock starts at a lower slope than in the core.
uniform float rock_start : hint_range(0.0, 1.0) = 0.18;
uniform float rock_end : hint_range(0.0, 1.0) = 0.45;

uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 photo_rect = vec4(-30720.0, -30720.0, 61440.0, 61440.0);
uniform sampler2D photo_far : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 photo_far_rect = vec4(-99840.0, -99840.0, 199680.0, 199680.0);
uniform float photo_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float photo_gain : hint_range(0.0, 2.0) = 1.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.6;
// WorldCover bare rock, snow/ice, water (80 m, texel centres on x = -99840 + k * 80).
uniform sampler2D cover : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 cover_rect = vec4(-99880.0, -99880.0, 199760.0, 199760.0);
uniform float lake_level = 65.0;

const vec3 LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	VERTEX.y -= curvature_drop(v_world); // unrotated, unscaled chunks
}

// Two-offset stochastic sampling selected by smooth noise, as in the core (no tile repeats).
vec4 sample_tile(sampler2D tex, vec2 uv, float id) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float k = textureGrad(surface_noise, uv * 0.13, dx * 0.13, dy * 0.13).r * 8.0;
	float cell = floor(k);
	vec2 a = sin(vec2(3.0, 7.0) * (cell + id * 13.0)) * 19.0;
	vec2 b = sin(vec2(3.0, 7.0) * (cell + 1.0 + id * 13.0)) * 19.0;
	return mix(textureGrad(tex, uv + a, dx, dy), textureGrad(tex, uv + b, dx, dy), smoothstep(0.15, 0.85, fract(k)));
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 n, float size, float id) {
	vec3 planes = pow(abs(n), vec3(4.0));
	planes /= dot(planes, vec3(1.0));
	return sample_tile(tex, p.xz / size, id) * planes.y
		+ sample_tile(tex, p.zy / size, id) * planes.x
		+ sample_tile(tex, p.xy / size, id) * planes.z;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec2 p = v_world.xz;
	float medium = texture(surface_noise, p / 170.0 + vec2(0.27)).r;
	vec3 cb = texture(cover, (p - cover_rect.xy) / cover_rect.zw).rgb;

	// Grain: material luminance relative to its texture mean (the top mip).
	float rock = smoothstep(rock_start, max(rock_start + 0.01, rock_end), 1.0 - n.y + (medium - 0.5) * 0.13);
	rock = max(rock, smoothstep(0.3, 0.7, cb.r));
	float stone = dot(triplanar(rock_albedo, v_world, n, meso_size, 0.0).rgb, LUMINANCE)
		/ max(dot(textureLod(rock_albedo, vec2(0.5), 14.0).rgb, LUMINANCE), 0.01);
	float soil = dot(sample_tile(ground_albedo, p / (meso_size * 0.35), 1.0).rgb, LUMINANCE)
		/ max(dot(textureLod(ground_albedo, vec2(0.5), 14.0).rgb, LUMINANCE), 0.01);
	float detail = clamp(mix(soil, stone, rock), 0.45, 1.7);

	// The 8 m photo hands over to the far one across the last 15% of its half-width (~4.6 km): the
	// orthophoto and Sentinel-2 differ in snow cover.
	vec3 albedo = texture(photo_far, (p - photo_far_rect.xy) / photo_far_rect.zw).rgb;
	vec2 q = abs(p - photo_rect.xy - photo_rect.zw * 0.5) / (photo_rect.zw * 0.5);
	float near = 1.0 - smoothstep(0.85, 1.0, max(q.x, q.y));
	albedo = mix(albedo, texture(photo, (p - photo_rect.xy) / photo_rect.zw).rgb, near); // no branch: implicit derivatives
	albedo = max(mix(vec3(dot(albedo, LUMINANCE)), albedo, photo_saturation), 0.0) * photo_gain;
	// The 8 m texels magnify near the core edge (~3 m screen pixels at 5 km).
	float footprint = length(fwidth(v_world.xz));
	albedo *= mix(1.0, detail, detail_strength * (1.0 - smoothstep(4.0, 16.0, footprint)));

	// Inland lakes and rivers above Garda (Ledro, Cavedine, Toblino, Adige); Garda is the water plane.
	float water = smoothstep(0.4, 0.6, cb.b) * step(lake_level + 3.0, v_world.y) * (1.0 - smoothstep(0.04, 0.15, 1.0 - n.y));
	ALBEDO = albedo;
	ROUGHNESS = mix(0.92, 0.12, water);
	SPECULAR = mix(0.25, 0.5, water);
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance(v_world);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
