// Burley + GGX receiver, shared by Garda's existing shaders and standard materials.
// Ambient, emission, probes and mesh shadows remain engine-managed.
#include "cloud_shadow.gdshaderinc"
varying float cloud_transmission;
varying float cloud_material_specular;

float cloud_schlick(float cosine) {
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
	vec3 halfway = (LIGHT + VIEW) / max(length(LIGHT + VIEW), 0.0001);
	float lh = clamp(dot(LIGHT, halfway), 0.0, 1.0);
	float fd90 = 2.0 * lh * lh * ROUGHNESS - 0.5;
	float diffuse = (1.0 + fd90 * cloud_schlick(nl)) * (1.0 + fd90 * cloud_schlick(nv)) * nl / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * attenuation * (diffuse + max(vec3(1.0 / PI - diffuse), vec3(0.0)) * BACKLIGHT);
	if (nl > 0.0 && ROUGHNESS > 0.0) {
		float nh = clamp(dot(NORMAL, halfway), 0.0, 1.0);
		float a = max(ROUGHNESS * ROUGHNESS, 0.0001);
		float denominator = 1.0 - nh * nh + nh * nh * a * a;
		float distribution = a * a / max(PI * denominator * denominator, 0.0000001);
		float visibility = 0.5 / mix(2.0 * nl * nv, nl + nv, a);
		vec3 f0 = mix(vec3(0.16 * cloud_material_specular * cloud_material_specular), ALBEDO, METALLIC);
		float f90 = clamp(dot(f0, vec3(16.5)), METALLIC, 1.0);
		vec3 fresnel = f0 + (vec3(f90) - f0) * cloud_schlick(lh);
		SPECULAR_LIGHT += LIGHT_COLOR * attenuation * SPECULAR_AMOUNT * nl * distribution * visibility * fresnel;
	}
}
