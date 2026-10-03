// Optional, layer-local view-ray integration. RGB = accumulated cloud light,
// A = transmission from the camera to the requested distance (not opacity).
uniform sampler3D cloud_view_texture : filter_linear, repeat_disable;
uniform bool cloud_view_enabled = false;

vec4 cloud_view_at(vec2 uv, float distance_m) {
	if (!cloud_view_enabled) return vec4(0.0, 0.0, 0.0, 1.0);
	vec3 size = vec3(textureSize(cloud_view_texture, 0));
	float slice = clamp(log(1.0 + max(distance_m, 0.0) / 1000.0) / log(111.0), 0.0, 1.0);
	// Map slice endpoints to texel centres, not the outside faces of the volume.
	return textureLod(cloud_view_texture, vec3(uv, (0.5 + slice * (size.z - 1.0)) / size.z), 0.0);
}

vec4 cloud_view_fog(vec4 cloud) {
	float opacity = clamp(1.0 - cloud.a, 0.0, 1.0);
	return vec4(cloud.rgb / max(opacity, 0.0001), opacity);
}
