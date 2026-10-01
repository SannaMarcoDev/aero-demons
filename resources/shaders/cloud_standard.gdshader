shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://addons/clouds/cloud_pbr.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_texture : source_color, hint_default_black, filter_linear_mipmap_anisotropic;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform float material_specular = 0.5;
uniform bool normal_enabled = false;
uniform float normal_scale = 1.0;
uniform bool ao_enabled = false;
uniform float ao_light_affect = 0.0;
uniform bool vertex_color_albedo = false;
uniform bool emission_enabled = false;
uniform bool emission_multiply = false;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_energy = 1.0;
uniform vec4 backlight_color : source_color = vec4(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_scissor_threshold = 0.5;
uniform float alpha_hash_scale = 1.0;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 color = albedo_color * texture(albedo_texture, uv);
	if (vertex_color_albedo) { color *= COLOR; }
	ALBEDO = color.rgb;
	METALLIC = metallic * dot(texture(metallic_texture, uv), metallic_channel);
	ROUGHNESS = roughness * dot(texture(roughness_texture, uv), roughness_channel);
	SPECULAR = material_specular;
	if (normal_enabled) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (ao_enabled) {
		AO = dot(texture(ao_texture, uv), ao_channel);
		AO_LIGHT_AFFECT = ao_light_affect;
	}
	if (emission_enabled) {
		vec3 tex = texture(emission_texture, uv).rgb;
		EMISSION = (emission_multiply ? emission_color.rgb * tex : emission_color.rgb + tex) * emission_energy;
	}
	BACKLIGHT = backlight_color.rgb;
#ifdef CLOUD_ALPHA
	ALPHA = color.a;
#endif
#ifdef CLOUD_SCISSOR
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
#ifdef CLOUD_HASH
	ALPHA_HASH_SCALE = alpha_hash_scale;
#endif
	cloud_material_specular = SPECULAR;
	cloud_transmission = cloud_sun_transmittance((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}
