// Riva sample buildings: extruded OSM footprints, gabled when near-rectangular
// (tools/terrain/build_riva_sample.gd). Roofs (UV.x = 1) project the orthophoto from above, pulled toward
// the footprint centroid (UV2) so OSM/photo offsets do not paint streets on them, and blended with the
// footprint mean (COLOR, sRGB). Walls: plaster varied per building (UV.y seed) with procedural floors,
// windows and shutters up to the eaves (UV2 = base, eaves heights).
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"

uniform vec3 wall_color : source_color = vec3(0.62, 0.57, 0.50);
uniform float wall_variation : hint_range(0.0, 0.5) = 0.2;
uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 photo_rect = vec4(-5120.0, -5120.0, 10240.0, 10240.0);
// Photo sample = centroid + (point - centroid) * roof_inset; the footprint mean fills the rest.
uniform float roof_inset : hint_range(0.5, 1.0) = 0.85;
uniform float roof_photo : hint_range(0.0, 1.0) = 0.75;
uniform float roof_gain : hint_range(0.0, 2.0) = 1.0;
// Footprint means and the photo carry haze: a little saturation brings back the clay tiles.
uniform float roof_saturation : hint_range(0.0, 2.0) = 1.4;
uniform float floor_height : hint_range(2.5, 4.5) = 3.1;
uniform float bay_width : hint_range(2.0, 6.0) = 3.4;
uniform vec3 glass_color : source_color = vec3(0.10, 0.12, 0.14);
uniform vec3 shutter_green : source_color = vec3(0.22, 0.32, 0.22);
uniform vec3 shutter_brown : source_color = vec3(0.36, 0.25, 0.17);

const vec3 LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

varying vec3 v_world;
varying vec3 v_normal;
varying float v_roof;
varying vec3 v_hash;
varying vec2 v_extra;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_roof = UV.x;
	v_hash = fract(sin(UV.y * vec3(1289.898, 7823.3, 3771.9)) * 43758.5453);
	v_extra = UV2;
}

// Anti-aliased [a, b] band of a repeating 0..1 coordinate; w = its screen derivative.
float band(float f, float a, float b, float w) {
	return smoothstep(a - w, a + w, f) - smoothstep(b - w, b + w, f);
}

void fragment() {
	float glass = 0.0;
	if (v_roof > 0.5) {
		vec2 p = mix(v_extra, v_world.xz, roof_inset);
		vec2 dx = dFdx(v_world.xz) * roof_inset / photo_rect.zw;
		vec2 dy = dFdy(v_world.xz) * roof_inset / photo_rect.zw;
		vec3 roof = textureGrad(photo, (p - photo_rect.xy) / photo_rect.zw, dx, dy).rgb;
		roof = mix(pow(COLOR.rgb, vec3(2.2)), roof, roof_photo);
		ALBEDO = max(mix(vec3(dot(roof, LUMINANCE)), roof, roof_saturation), 0.0) * roof_gain;
	} else {
		// Plaster from white to ochre, never green.
		vec3 wall = wall_color * (1.0 + (v_hash.x - 0.5) * 2.0 * wall_variation) * mix(vec3(1.0), vec3(1.08, 0.97, 0.84), v_hash.y);
		vec2 tangent = normalize(vec2(-v_normal.z, v_normal.x) + vec2(1e-5, 0.0));
		float height = v_world.y - v_extra.x;
		float bay = bay_width * (0.9 + 0.2 * v_hash.z);
		vec2 cell = vec2(dot(v_world.xz, tangent) / bay, (height - 0.3) / floor_height);
		vec2 f = fract(cell);
		vec2 w = fwidth(cell);
		// Windows stop below the eaves and on gable ends; the pattern fades to its mean when it aliases.
		float rows = step(0.0, cell.y) * (1.0 - smoothstep(v_extra.y - 1.2, v_extra.y - 0.6, v_world.y));
		float detail = 1.0 - smoothstep(0.12, 0.35, max(w.x, w.y));
		float shuttered = step(0.35, v_hash.z);
		float window = band(f.x, 0.34, 0.66, w.x) * band(f.y, 0.22, 0.78, w.y);
		float shutter = (band(f.x, 0.20, 0.34, w.x) + band(f.x, 0.66, 0.80, w.x)) * band(f.y, 0.22, 0.78, w.y) * shuttered;
		window = mix(0.32 * 0.56, window, detail) * rows;
		shutter = mix(0.28 * 0.56 * shuttered, shutter, detail) * rows;
		vec3 shutters = mix(shutter_green, shutter_brown, step(0.65, v_hash.y));
		// Darker plinth: splash and grime near the ground.
		wall *= mix(0.82, 1.0, smoothstep(0.0, 2.5, height));
		ALBEDO = mix(mix(wall, shutters, shutter), glass_color, window);
		glass = window * detail;
	}
	ROUGHNESS = mix(0.85, 0.15, glass);
	SPECULAR = mix(0.3, 0.5, glass);
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance(v_world);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
