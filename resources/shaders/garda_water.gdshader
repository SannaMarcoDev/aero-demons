// Lake Garda. Opaque on purpose: CloudAtmosphere hazes the opaque pass only, so the lake fades into
// the distance with its shores. Transparency is rebuilt instead: the Terrain3D lake bed (bound by
// scripts/maps/riva_water.gd) gives the depth, the orthophoto the bed seen through it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"
#include "res://resources/shaders/earth_curvature.gdshaderinc"

group_uniforms Water;
// Light scattered back by deep water, and absorption per metre: red goes first, the shallows turn green-blue.
uniform vec3 deep_color : source_color = vec3(0.025, 0.1, 0.105);
uniform vec3 absorption = vec3(0.5, 0.11, 0.095);
uniform float bed_visibility : hint_range(0.0, 1.0) = 0.9;
uniform float shore_foam : hint_range(0.0, 1.0) = 0.5;

group_uniforms Wind;
// World x/z. Peler and Ora blow along the lake axis.
uniform vec2 wind_direction = vec2(0.12, 1.0);
// m/s: the mean squared slope follows Cox-Munk (0.003 + 0.00512 U), so it sets the width of the sun glitter.
uniform float wind_speed : hint_range(0.0, 15.0) = 5.0;
// Gusts and calm patches travelling with the wind; slicks are glassy streaks along it.
uniform float gustiness : hint_range(0.0, 1.0) = 0.5;
uniform float slicks : hint_range(0.0, 1.0) = 0.4;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
// Wind-sea slope tile (tools/water/build_wave_texture.gd): RG slope, BA slope squared. Its peak
// wavelength is an eighth of wave_tile: 6 m, a fetch-limited breeze on the lake.
uniform sampler2D waves : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wave_tile : hint_range(8.0, 200.0) = 48.0;
uniform sampler2D foam_noise : filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms Bed;
// The terrain's orthophotos: the same pixels continue under the waterline.
uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 photo_rect = vec4(-20480.0, -20480.0, 40960.0, 40960.0);
uniform sampler2D photo_core : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 photo_core_rect = vec4(-5120.0, -5120.0, 10240.0, 10240.0);
// Terrain3D maps, bound at runtime. Unbound (region map all 0), the lake is deep everywhere.
uniform highp sampler2DArray terrain_heights : filter_nearest, repeat_disable;
uniform int terrain_region_map[1024];
uniform int terrain_region_size = 512;
uniform float terrain_vertex_spacing = 4.0;

// The sea tile three times: scale, angle from the wind, drift (m/s); weights' squares sum to 1.
const vec3 WAVE_LAYERS[3] = { vec3(1.0, 0.0, 1.4), vec3(0.37, 0.61, 0.9), vec3(0.13, -1.05, 0.55) };
const float WAVE_WEIGHTS[3] = { 0.78, 0.52, 0.35 };
const float NO_BED = -100000.0;

varying vec3 world_position;

void vertex() {
	// Shading in world metres: the plane's cells are far larger than the waves.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y -= curvature_drop(world_position); // unrotated, unscaled plane; flat unless earth_radius is set
}

float bed_texel(ivec2 t) {
	ivec2 region = ivec2(floor(vec2(t) / float(terrain_region_size))) + 16;
	if (any(lessThan(region, ivec2(0))) || any(greaterThanEqual(region, ivec2(32)))) {
		return NO_BED;
	}
	int layer = terrain_region_map[region.y * 32 + region.x] - 1;
	if (layer < 0) {
		return NO_BED;
	}
	return texelFetch(terrain_heights, ivec3(t - (region - 16) * terrain_region_size, layer), 0).r;
}

// Bilinear between Terrain3D vertices, as its mesh is drawn.
float bed_height(vec2 p) {
	vec2 uv = p / terrain_vertex_spacing;
	ivec2 t = ivec2(floor(uv));
	vec2 f = fract(uv);
	float a = mix(bed_texel(t), bed_texel(t + ivec2(1, 0)), f.x);
	float b = mix(bed_texel(t + ivec2(0, 1)), bed_texel(t + ivec2(1, 1)), f.x);
	return mix(a, b, f.y);
}

// The 2.5 m photo, handing over to the 1 m one over the last 4% of its half-width (as the terrain).
vec3 photo_at(vec2 p, vec2 dx, vec2 dy) {
	vec3 wide = textureGrad(photo, (p - photo_rect.xy) / photo_rect.zw, dx / photo_rect.zw, dy / photo_rect.zw).rgb;
	vec2 q = abs(p - photo_core_rect.xy - photo_core_rect.zw * 0.5) / (photo_core_rect.zw * 0.5);
	float core = 1.0 - smoothstep(0.96, 1.0, max(q.x, q.y));
	if (core <= 0.0) { return wide; }
	vec3 fine = textureGrad(photo_core, (p - photo_core_rect.xy) / photo_core_rect.zw, dx / photo_core_rect.zw, dy / photo_core_rect.zw).rgb;
	return mix(wide, fine, core);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 dpdx = dFdx(p);
	vec2 dpdy = dFdy(p);
	float footprint = max(max(length(dpdx), length(dpdy)), 0.001); // metres per pixel
	vec2 wind = normalize(wind_direction);
	vec2 across = vec2(-wind.y, wind.x);

	// Wind field: gust patches (kilometres) and cat's paws (hundreds of metres) drift downwind.
	vec2 drift = wind * TIME * 4.0;
	float gust = texture(wind_noise, (p - drift) / 3400.0).r * 0.6 + texture(wind_noise, (p - drift * 1.5) / 650.0 + 0.37).r * 0.4;
	gust = mix(1.0, smoothstep(0.32, 0.68, gust) * 1.7 + 0.1, gustiness);
	// Slicks: soft, meandering bands a few times longer than wide, not lines (they run towards the
	// vanishing point whenever the camera looks down the lake).
	vec2 bend = vec2(texture(wind_noise, p / 5200.0 + 0.13).r, texture(wind_noise, p / 5200.0 + 0.71).r) - 0.5;
	vec2 rows = vec2(dot(p, wind) - TIME * 1.5, dot(p, across)) / vec2(1900.0, 560.0) + bend * 1.2;
	float slick = smoothstep(0.5, 0.78, texture(wind_noise, rows + vec2(0.0, 0.61)).r) * slicks;
	float local_wind = wind_speed * gust;

	// The sea tile turned, scaled and drifting apart: the layers hide its repeat and keep the crests changing. Mipmaps
	// average slope and squared slope (LEAN mapping): what a pixel no longer resolves becomes roughness,
	// so the chop fades into a broad, steady glitter with distance instead of flickering.
	vec2 slope = vec2(0.0);
	float lost = 0.0;
	for (int i = 0; i < 3; i++) {
		vec3 layer = WAVE_LAYERS[i];
		float angle = atan(wind.y, wind.x) + layer.y;
		vec2 along = vec2(cos(angle), sin(angle));
		mat2 to_tile = mat2(vec2(along.x, -along.y), vec2(along.y, along.x));
		vec4 sea = texture(waves, (to_tile * p - vec2(layer.z * TIME, 0.0)) / (wave_tile * layer.x));
		float weight = WAVE_WEIGHTS[i] * (1.0 - slick * 0.4 * float(i)); // films damp the short waves
		slope += weight * (transpose(to_tile) * sea.rg);
		lost += weight * weight * (max(sea.b - sea.r * sea.r, 0.0) + max(sea.a - sea.g * sea.g, 0.0));
	}
	float variance = 0.003 + 0.00512 * local_wind * (1.0 - 0.6 * slick);
	slope *= sqrt(variance);
	lost *= variance;

	// The lake bed: depth, refraction and Beer-Lambert absorption down and back up.
	float bed = bed_height(p);
	float depth = max(world_position.y - bed, 0.0);
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float nv = clamp(dot(world_normal, view), 0.0, 1.0);
	float refracted_sin = sqrt(1.0 - nv * nv) / 1.33; // water ior
	float refracted_cos = sqrt(1.0 - refracted_sin * refracted_sin);
	vec2 away = -view.xz / max(length(view.xz), 0.0001);
	vec2 bed_p = p + away * min(depth * refracted_sin / refracted_cos, 6.0) - slope * min(depth, 10.0) * 0.3;
	vec3 transmittance = exp(-absorption * depth * (1.0 + 1.0 / max(refracted_cos, 0.2)));
	// Beyond a few metres per pixel the shallow rim is thinner than a pixel: let it go before it shimmers.
	// At grazing angles the reflection hides it anyway.
	transmittance *= bed_visibility * (1.0 - smoothstep(4.0, 16.0, footprint)) * smoothstep(0.06, 0.3, view.y);
	// The photo's bright shore pixels are lit air-side: under water they lose some light.
	vec3 bed_color = photo_at(bed_p, dpdx, dpdy) * 0.75;
	vec3 body = mix(deep_color, bed_color, transmittance);
	// Reflection takes what refraction gives up (Schlick, F0 0.02).
	float fresnel = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
	body *= 1.0 - fresnel;

	// Foam where the water thins out against the shore, lapping in bands that run ashore.
	float grain = texture(foam_noise, p / 5.0 + wind * TIME * 0.03).r;
	float patches = texture(foam_noise, p / 23.0 - across * TIME * 0.02).r;
	float edge = 1.0 - smoothstep(0.0, 1.2, depth + (patches - 0.5) * 0.8);
	float bands = 0.5 + 0.5 * sin(depth * 9.0 + TIME * 1.4 + patches * 5.0);
	float foam = smoothstep(0.35, 0.7, grain * edge * (1.0 + bands)) * shore_foam;
	foam *= 1.0 - smoothstep(1.5, 6.0, footprint);

	// GGX alpha from the slope variance the normal no longer carries (Godot: alpha = roughness^2).
	// Grazing, masking leaves the facets that face the camera: the split-sum radiance does not know,
	// and a full-width lobe would reflect Sky3D's dark ground instead of the horizon.
	float alpha = sqrt(0.0009 + lost) * mix(0.35, 1.0, smoothstep(0.0, 0.45, view.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALBEDO = mix(body, vec3(0.82, 0.85, 0.84), foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.354, 0.5, foam); // Godot F0 = 0.16 * SPECULAR^2: water 0.02.
	ROUGHNESS = mix(clamp(sqrt(alpha), 0.05, 0.6), 0.75, foam);
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance(world_position);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
