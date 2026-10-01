shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "cloud_shadow.gdshaderinc"

// Opaque metallic/roughness PBR receiver. Godot still handles ambient, probes,
// emission, mesh shadows and fog; only the assigned sun's DIRECT light is dimmed.
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform float roughness : hint_range(0.04, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float material_specular : hint_range(0.0, 1.0) = 0.5;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform vec2 uv_scale = vec2(1.0);
varying float cloud_transmission;

void fragment() {
	vec2 uv = UV * uv_scale;
	ALBEDO = albedo_color.rgb * texture(albedo_texture, uv).rgb;
	vec3 orm = texture(orm_texture, uv).rgb;
	AO = orm.r;
	ROUGHNESS = clamp(roughness * orm.g, 0.04, 1.0);
	METALLIC = metallic * orm.b;
	SPECULAR = material_specular;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	EMISSION = emission_color;
	cloud_transmission = cloud_sun_transmittance((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	AO *= cloud_ambient_occlusion(cloud_transmission);
}

float schlick_weight(float cosine) {
	float m = 1.0 - clamp(cosine, 0.0, 1.0);
	return m * m * m * m * m;
}

void light() {
	float attenuation = ATTENUATION;
	vec3 world_light = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	if (LIGHT_IS_DIRECTIONAL && dot(world_light, cloud_shadow_sun_direction) >= 0.99999) {
		attenuation *= cloud_transmission;
	}
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	float nv = max(dot(NORMAL, VIEW), 0.0001);
	if (nl > 0.0) {
		vec3 halfway = normalize(LIGHT + VIEW);
		float nh = clamp(dot(NORMAL, halfway), 0.0, 1.0);
		float lh = clamp(dot(LIGHT, halfway), 0.0, 1.0);
		float fd90 = 2.0 * lh * lh * ROUGHNESS - 0.5;
		float diffuse = (1.0 + fd90 * schlick_weight(nl)) * (1.0 + fd90 * schlick_weight(nv));
		// Godot multiplies diffuse by ALBEDO and (1 - METALLIC) afterwards.
		DIFFUSE_LIGHT += LIGHT_COLOR * attenuation * diffuse * nl / PI;
		float a = ROUGHNESS * ROUGHNESS;
		float denominator = 1.0 - nh * nh + nh * nh * a * a;
		float distribution = a * a / (PI * denominator * denominator);
		float visibility = 0.5 / mix(2.0 * nl * nv, nl + nv, a);
		vec3 f0 = mix(vec3(0.16 * material_specular * material_specular), ALBEDO, METALLIC);
		float f90 = clamp(dot(f0, vec3(16.5)), METALLIC, 1.0);
		vec3 fresnel = f0 + (vec3(f90) - f0) * schlick_weight(lh);
		SPECULAR_LIGHT += LIGHT_COLOR * attenuation * SPECULAR_AMOUNT * nl * distribution * visibility * fresnel;
	}
}
