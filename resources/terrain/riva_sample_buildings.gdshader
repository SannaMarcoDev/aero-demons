// Riva sample buildings: extruded OSM footprints, gabled when near-rectangular
// (tools/terrain/build_riva_sample.gd). Roofs (UV.x = 1) take the orthophoto colour under the footprint
// (COLOR, sRGB); walls a plaster tone varied per building (UV.y seed).
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"

uniform vec3 wall_color : source_color = vec3(0.62, 0.57, 0.50);
uniform float wall_variation : hint_range(0.0, 0.5) = 0.2;
uniform float roof_gain : hint_range(0.0, 2.0) = 1.0;
// The footprint mean includes shadows and haze: a little saturation brings back the clay tiles.
uniform float roof_saturation : hint_range(0.0, 2.0) = 1.4;

varying vec3 v_world;
varying float v_roof;
varying vec3 v_wall;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_roof = UV.x;
	vec3 h = fract(sin(UV.y * vec3(1289.898, 7823.3, 3771.9)) * 43758.5453);
	// Brightness and warmth only: plaster from white to ochre, never green.
	v_wall = wall_color * (1.0 + (h.x - 0.5) * 2.0 * wall_variation) * mix(vec3(1.0), vec3(1.08, 0.97, 0.84), h.y);
}

void fragment() {
	vec3 roof = pow(COLOR.rgb, vec3(2.2));
	roof = max(mix(vec3(dot(roof, vec3(0.2126, 0.7152, 0.0722))), roof, roof_saturation), 0.0) * roof_gain;
	ALBEDO = mix(v_wall, roof, v_roof);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance(v_world);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
