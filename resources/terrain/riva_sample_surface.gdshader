// Riva sample surface: Garda material system driven by real land use instead of noise.
// Masks/tint: tools/terrain/fetch_riva_sample.cjs. Terrain3D 1.0.2 geometry/geomorph contract from
// extras/shaders/minimum, shared with garda_surface.gdshader.
// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors (MIT).
// Material coordinates are world metres, never height/control/color-map texels.
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"

#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif
uniform vec3 _camera_pos = vec3(0.0);
uniform float _mesh_size = 48.0;
uniform uint _background_mode = 0u;
uniform uint _mouse_layer = 0x80000000u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// Noise is linear data (not source_color). The material supplies a seamless mipmapped texture.
uniform sampler2D surface_noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_size : hint_range(1.0, 16.0) = 4.0;
uniform float meso_size : hint_range(16.0, 256.0) = 72.0;
uniform float macro_size : hint_range(100.0, 10000.0) = 4500.0;
uniform float snow_line : hint_range(0.0, 4000.0) = 2700.0;
uniform float snow_transition : hint_range(50.0, 1000.0) = 450.0;
uniform float rock_start : hint_range(0.0, 1.0) = 0.20; // 1 - normal.y
uniform float rock_end : hint_range(0.0, 1.0) = 0.55;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 rock_tint : source_color = vec3(0.70, 0.68, 0.62); // pale Garda limestone

// Real land use, 4 m per texel (OpenStreetMap + ESA WorldCover).
uniform sampler2D masks_a : hint_default_black, filter_linear_mipmap, repeat_disable; // forest, vineyard/orchard, field, urban
uniform sampler2D masks_b : hint_default_black, filter_linear_mipmap, repeat_disable; // building, road, rock, water
uniform sampler2D masks_c : hint_default_black, filter_nearest_mipmap, repeat_disable; // row angle, parcel seed, kind, scrub
uniform vec4 mask_rect = vec4(-5120.0, -5120.0, 10240.0, 10240.0);
// Sentinel-2 low-pass colour divided by its land-cover class mean: 0.5 = class mean.
uniform sampler2D satellite_tint : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D context_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 context_rect = vec4(-30735.0, -30735.0, 61440.0, 61440.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_fade : hint_range(0.0, 2000.0) = 350.0;
uniform float lake_level = 65.0;

varying float v_vertex_xz_dist;
varying vec3 v_vertex;

// Native Terrain3D lookup, with explicit bounds protection at the 250 km perimeter.
ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv, _region_size);
	int layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			ivec2 pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
			if (all(greaterThanEqual(pos, ivec2(0))) && all(lessThan(pos, ivec2(_region_map_size)))) {
				layer_index = _region_map[pos.y * _region_map_size + pos.x] - 1;
			}
		}
	}
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

void vertex() {
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	vec2 shift = (scale < _vertex_spacing + 1e-6) ?
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))) :
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;
	UV = v_vertex.xz * _vertex_density;
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));
	ivec3 region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = region.z >= 0 ? floatBitsToUint(texelFetch(_control_maps, region, 0).r) : 0u;
	bool hole = bool(control >> 2u & 0x1u);
	if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer) && (hole || (_background_mode == 0u && region.z < 0))) {
		v_vertex.x = 0.0 / 0.0;
	} else {
		ivec3 end_region = get_index_coord(end_pos, VERTEX_PASS);
		float h0 = region.z >= 0 ? texelFetch(_height_maps, region, 0).r : 0.0;
		float h1 = end_region.z >= 0 ? texelFetch(_height_maps, end_region, 0).r : h0;
		v_vertex.y = mix(h0, h1, vertex_lerp);
	}
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

float height_at(vec2 uv) {
	ivec3 index = get_index_coord(uv, FRAGMENT_PASS);
	return index.z >= 0 ? texelFetch(_height_maps, index, 0).r : v_vertex.y;
}

// Interpolate normals at ALL distances: no screen-size threshold switching to nearest.
vec3 terrain_normal(vec2 uv) {
	vec2 p = floor(uv);
	vec2 f = fract(uv);
	float h00 = height_at(p);
	float h10 = height_at(p + vec2(1, 0));
	float h01 = height_at(p + vec2(0, 1));
	float h11 = height_at(p + vec2(1, 1));
	vec3 n00 = vec3(h00 - h10, _vertex_spacing, h00 - h01);
	vec3 n10 = vec3(h10 - height_at(p + vec2(2, 0)), _vertex_spacing, h10 - h11);
	vec3 n01 = vec3(h01 - h11, _vertex_spacing, h01 - height_at(p + vec2(0, 2)));
	vec3 n11 = vec3(h11 - height_at(p + vec2(2, 1)), _vertex_spacing, h11 - height_at(p + vec2(1, 2)));
	return normalize(mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y));
}

struct Surface {
	vec4 albedo_height;
	vec4 normal_rough;
};

// Continuous two-offset stochastic sampling. Offsets are selected by smooth noise,
// not by terrain cells. Adjacent intervals share a sample, so there is no tile seam.
// Explicit derivatives keep mipmapping/anisotropy valid in material branches.
Surface sample_tile(vec2 uv, vec2 dx, vec2 dy, float id) {
	float k = textureGrad(surface_noise, uv * 0.13, dx * 0.13, dy * 0.13).r * 8.0;
	float cell = floor(k);
	vec2 a = sin(vec2(3.0, 7.0) * (cell + id * 13.0)) * 19.0;
	vec2 b = sin(vec2(3.0, 7.0) * (cell + 1.0 + id * 13.0)) * 19.0;
	float w = smoothstep(0.15, 0.85, fract(k));
	vec4 aa = textureGrad(_texture_array_albedo, vec3(uv + a, id), dx, dy);
	vec4 ab = textureGrad(_texture_array_albedo, vec3(uv + b, id), dx, dy);
	vec4 na = textureGrad(_texture_array_normal, vec3(uv + a, id), dx, dy);
	vec4 nb = textureGrad(_texture_array_normal, vec3(uv + b, id), dx, dy);
	return Surface(mix(aa, ab, w), mix(na, nb, w));
}

Surface sample_scales(vec2 p, vec2 dx, vec2 dy, float id) {
	// Existing rocky_terrain_02 is an aerial grass/stone scan, appropriate at this scale.
	float meso_id = (id == 2.0 || id == 3.0) ? 1.0 : id;
	float size = meso_id == 1.0 ? meso_size * 0.35 : meso_size;
	Surface meso = sample_tile(p / size, dx / size, dy / size, meso_id);
	float footprint = max(length(dx), length(dy));
	float fine = 1.0 - smoothstep(0.15, 2.5, footprint);
	if (fine > 0.001) {
		Surface detail = sample_tile(p / detail_size, dx / detail_size, dy / detail_size, id);
		// Mean-normalized detail preserves the meso palette as fine mips disappear.
		vec3 mean = vec3(0.435, 0.293, 0.198);
		if (id == 2.0) { mean = vec3(0.315, 0.232, 0.102); }
		if (id == 3.0) { mean = vec3(0.421, 0.300, 0.197); }
		if (id == 4.0) { mean = vec3(0.376, 0.376, 0.386); }
		const vec3 luminance = vec3(0.2126, 0.7152, 0.0722);
		float detail_ratio = clamp(dot(detail.albedo_height.rgb, luminance) / dot(mean, luminance), 0.25, 2.5);
		meso.albedo_height.rgb *= mix(1.0, detail_ratio, fine * 0.55);
		meso.albedo_height.a = mix(meso.albedo_height.a, detail.albedo_height.a, fine * 0.7);
		meso.normal_rough = mix(meso.normal_rough, detail.normal_rough, fine * 0.85);
	}
	return meso;
}

void add_surface(float id, float weight, vec3 n, vec3 dx, vec3 dy,
		inout vec3 albedo, inout vec3 detail_normal, inout float roughness, inout float total) {
	if (weight <= 0.001) { return; }
	// Triplanar only where needed. Continuous weights prevent projection threshold seams.
	vec3 planes = pow(abs(n), vec3(4.0));
	planes /= dot(planes, vec3(1.0));
	vec4 alb = vec4(0.0);
	float rough = 0.0;
	vec3 perturbation = vec3(0.0);
	if (planes.y > 0.001) {
		Surface s = sample_scales(v_vertex.xz, dx.xz, dy.xz, id);
		alb += s.albedo_height * planes.y;
		rough += s.normal_rough.a * planes.y;
		vec2 nm = s.normal_rough.xy * 2.0 - 1.0;
		perturbation += vec3(nm.x, 0.0, -nm.y) * planes.y;
	}
	if (planes.x > 0.001) {
		Surface s = sample_scales(v_vertex.zy, dx.zy, dy.zy, id);
		alb += s.albedo_height * planes.x;
		rough += s.normal_rough.a * planes.x;
		vec2 nm = s.normal_rough.xy * 2.0 - 1.0;
		perturbation += vec3(0.0, -nm.y, nm.x) * planes.x;
	}
	if (planes.z > 0.001) {
		Surface s = sample_scales(v_vertex.xy, dx.xy, dy.xy, id);
		alb += s.albedo_height * planes.z;
		rough += s.normal_rough.a * planes.z;
		vec2 nm = s.normal_rough.xy * 2.0 - 1.0;
		perturbation += vec3(nm.x, -nm.y, 0.0) * planes.z;
	}
	float height_weight = weight * (0.3 + alb.a * alb.a);
	// Moderate, material-specific palette; no low-resolution RGB multiplier.
	vec3 tint = vec3(1.0);
	if (id == 2.0 || id == 3.0) {
		float luminance = dot(alb.rgb, vec3(0.2126, 0.7152, 0.0722));
		alb.rgb = mix(vec3(luminance), alb.rgb, 0.45);
	}
	if (id == 2.0) { tint = vec3(0.67, 0.88, 0.52); }
	if (id == 3.0) { tint = vec3(1.10, 1.03, 0.83); }
	if (id == 0.0) { tint = rock_tint; }
	albedo += alb.rgb * tint * height_weight;
	detail_normal += perturbation * height_weight;
	roughness += rough * height_weight;
	total += height_weight;
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Plant rows across a parcel: 1 on the canopy, 0 between rows. Rows narrower than a
// pixel fade to their coverage instead of aliasing.
float rows(vec2 p, float angle, float spacing, float coverage) {
	vec2 across = vec2(-sin(angle), cos(angle));
	float u = dot(p, across) / spacing;
	float w = fwidth(u);
	float s = abs(fract(u) - 0.5) * 2.0;
	float canopy = 1.0 - smoothstep(coverage - w, coverage + w, s);
	return mix(canopy, coverage, smoothstep(0.25, 0.7, w));
}

void fragment() {
	vec2 uv = UV; // Terrain3D editor/checker overlay injection expects this local.
	vec3 n = terrain_normal(uv);
	vec3 dx = dFdxCoarse(v_vertex);
	vec3 dy = dFdyCoarse(v_vertex);
	vec2 p = v_vertex.xz;
	float continental = textureGrad(surface_noise, p / 37000.0, dx.xz / 37000.0, dy.xz / 37000.0).r;
	float large = textureGrad(surface_noise, p / macro_size + continental * 0.7, dx.xz / macro_size, dy.xz / macro_size).r;
	float medium = textureGrad(surface_noise, p / 170.0 + vec2(0.27), dx.xz / 170.0, dy.xz / 170.0).r;
	float small = textureGrad(surface_noise, p / 23.0, dx.xz / 23.0, dy.xz / 23.0).r;
	vec2 muv = (p - mask_rect.xy) / mask_rect.zw;
	vec4 ma = texture(masks_a, muv);
	vec4 mb = texture(masks_b, muv);
	vec4 mc = texture(masks_c, muv);
	// Break the 4 m texel edges with fine noise, not with a visible blur.
	float edge_noise = (small - 0.5) * 0.3;

	float slope = 1.0 - n.y;
	float rock = smoothstep(rock_start, max(rock_start + 0.01, rock_end), slope + (medium - 0.5) * 0.13);
	rock = max(rock, smoothstep(0.3, 0.7, mb.b + edge_noise) * smoothstep(0.02, 0.12, slope));
	float snow = smoothstep(snow_line, snow_line + snow_transition,
		v_vertex.y + (large - 0.5) * 420.0 + (small - 0.5) * 80.0 + n.z * 160.0);
	snow *= 1.0 - smoothstep(0.18, 0.48, slope);
	float dry = smoothstep(0.38, 0.66, large * 0.8 + medium * 0.15 + small * 0.05 + n.z * 0.15);
	vec3 albedo = vec3(0.0);
	vec3 perturbation = vec3(0.0);
	float roughness = 0.0;
	float total = 0.0;
	add_surface(2.0, (1.0 - rock) * (1.0 - snow) * (1.0 - dry), n, dx, dy, albedo, perturbation, roughness, total);
	add_surface(3.0, (1.0 - rock) * (1.0 - snow) * dry, n, dx, dy, albedo, perturbation, roughness, total);
	add_surface(0.0, rock * (1.0 - snow), n, dx, dy, albedo, perturbation, roughness, total);
	add_surface(4.0, snow, n, dx, dy, albedo, perturbation, roughness, total);
	float inv_weight = 1.0 / max(total, 0.0001);
	perturbation *= inv_weight * normal_strength;
	perturbation -= n * dot(n, perturbation);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(n + perturbation));
	float macro = 1.0 + ((large - 0.5) * 0.8 + (medium - 0.5) * 0.4) * macro_strength;
	vec3 ground = albedo * inv_weight * macro;
	float rough = roughness * inv_weight;
	float open_ground = (1.0 - rock) * (1.0 - snow);

	// Scrub: darker, patchy grass.
	float scrub = smoothstep(0.3, 0.7, mc.a + edge_noise) * open_ground;
	ground = mix(ground, ground * vec3(0.55, 0.62, 0.48) * mix(0.8, 1.15, small), scrub * 0.85);

	// Woodland canopy; the 3D trees stand on it.
	float forest = smoothstep(0.3, 0.7, ma.r + edge_noise) * (1.0 - rock * 0.6) * (1.0 - snow);
	vec3 canopy = vec3(0.030, 0.050, 0.022) * mix(0.72, 1.28, medium) * mix(0.8, 1.2, small);
	ground = mix(ground, canopy, forest * 0.9);

	// Cultivated parcels: real outlines, row direction along each parcel's longest edge.
	float angle = mc.r * PI;
	float seed = mc.g;
	float vine = smoothstep(0.3, 0.7, ma.g + edge_noise * 0.5);
	float field = smoothstep(0.3, 0.7, ma.b + edge_noise * 0.5) * (1.0 - vine);
	if (field > 0.001) {
		vec3 crop = mix(vec3(0.085, 0.120, 0.040), vec3(0.165, 0.180, 0.075), fract(seed * 7.13));
		if (fract(seed * 3.71) > 0.72) { crop = mix(vec3(0.150, 0.125, 0.075), vec3(0.230, 0.200, 0.120), fract(seed * 11.3)); }
		float furrows = rows(p, angle, 0.9, 0.5);
		crop *= mix(0.88, 1.06, furrows) * mix(0.9, 1.1, small);
		ground = mix(ground, crop, field);
	}
	if (vine > 0.001) {
		float orchard = step(0.75, mc.b);
		float spacing = mix(2.6, 4.6, orchard);
		float canopy_rows = rows(p, angle, spacing, mix(0.42, 0.55, orchard));
		// Orchard trees are separate crowns along the row.
		float along = dot(p, vec2(cos(angle), sin(angle))) / 3.6;
		float crowns = mix(1.0, smoothstep(0.75, 0.35, abs(fract(along) - 0.5) * 2.0), orchard * (1.0 - smoothstep(0.25, 0.7, fwidth(along))));
		vec3 leaves = mix(vec3(0.050, 0.080, 0.028), vec3(0.042, 0.070, 0.030), orchard) * mix(0.85, 1.15, fract(seed * 5.3));
		vec3 between = mix(vec3(0.120, 0.120, 0.070), vec3(0.090, 0.110, 0.050), fract(seed * 9.1));
		ground = mix(ground, mix(between, leaves, canopy_rows * crowns), vine);
	}

	// Settlements: yards and paving, then roofs and streets from the real footprints.
	float urban = smoothstep(0.3, 0.7, ma.a + edge_noise * 0.5);
	vec3 paving = mix(vec3(0.150, 0.145, 0.135), vec3(0.070, 0.085, 0.045), smoothstep(0.45, 0.7, medium * 0.6 + small * 0.4));
	ground = mix(ground, paving, urban * 0.85);
	rough = mix(rough, 0.85, urban);
	float road = smoothstep(0.25, 0.65, mb.g);
	ground = mix(ground, vec3(0.055, 0.055, 0.060) * mix(0.9, 1.1, small), road);
	rough = mix(rough, 0.8, road);
	float building = smoothstep(0.35, 0.65, mb.r);
	// One colour per building (masks_c.g): weathered coppi or grey flat roofs.
	vec3 roof = fract(seed * 5.71) > 0.3 ? mix(vec3(0.20, 0.105, 0.065), vec3(0.27, 0.155, 0.10), fract(seed * 13.7))
		: mix(vec3(0.15, 0.145, 0.14), vec3(0.24, 0.235, 0.225), fract(seed * 13.7));
	roof *= mix(0.92, 1.05, small);
	ground = mix(ground, roof, building);
	rough = mix(rough, 0.7, building);

	// Pebble shores at the lake level (Riva/Torbole beaches), outside the towns.
	// Only the strip next to the water: the Riva/Torbole plains lie just above the lake level.
	float near_water = smoothstep(0.02, 0.15, textureLod(masks_b, muv, 2.5).a);
	float shore = (1.0 - smoothstep(lake_level + 0.8, lake_level + 2.0, v_vertex.y + (medium - 0.5) * 0.8))
		* near_water * (1.0 - smoothstep(0.2, 0.6, slope)) * (1.0 - building) * (1.0 - road) * (1.0 - urban * 0.7);
	if (shore > 0.001) {
		Surface gravel = sample_tile(p / 5.0, dx.xz / 5.0, dy.xz / 5.0, 5.0);
		ground = mix(ground, gravel.albedo_height.rgb * vec3(0.80, 0.78, 0.72), shore);
	}
	// Rivers and ponds above the lake (Sarca, Varone): the lake itself is the water plane.
	float water = smoothstep(0.4, 0.6, mb.a) * step(lake_level + 0.5, v_vertex.y);
	ground = mix(ground, vec3(0.020, 0.045, 0.050), water);
	rough = mix(rough, 0.12, water);

	// Regional colour from the satellite: low-pass and class-relative, never its detail.
	vec2 cuv = (p - context_rect.xy) / context_rect.zw;
	vec3 tint = clamp(texture(satellite_tint, cuv).rgb * 2.0, vec3(0.7), vec3(1.4));
	ground *= mix(vec3(1.0), tint, tint_strength);
	// Last metres of the sample: hand over to the baked context colour.
	float edge = min(min(p.x - mask_rect.x, mask_rect.x + mask_rect.z - p.x), min(p.y - mask_rect.y, mask_rect.y + mask_rect.w - p.y));
	ground = mix(ground, texture(context_albedo, cuv).rgb, 1.0 - smoothstep(0.0, edge_fade, edge));

	ALBEDO = ground;
	ROUGHNESS = clamp(rough, 0.1, 1.0);
	SPECULAR = mix(0.25, 0.5, water);
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance(v_vertex);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
