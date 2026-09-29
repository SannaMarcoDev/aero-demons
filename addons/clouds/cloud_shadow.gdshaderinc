// Bind these through CloudLayer3D.shadow_materials / register_shadow_material().
// Per-material bindings deliberately avoid global state across worlds/viewports.
uniform sampler2DArray cloud_shadow_texture : filter_linear_mipmap, repeat_enable;
uniform bool cloud_shadow_enabled = false;
uniform vec3 cloud_shadow_deck = vec3(2000.0, 15000.0, 100000.0);
uniform vec3 cloud_shadow_sun_direction = vec3(0.0, 1.0, 0.0);

float cloud_sun_transmittance(vec3 world_position) {
	if (!cloud_shadow_enabled) return 1.0;
	vec2 slope = cloud_shadow_sun_direction.xz / max(cloud_shadow_sun_direction.y, 0.00001);
	// Same sun column below the cloud base: no arbitrary ground plane/range.
	vec2 foot = world_position.xz - slope * (world_position.y - cloud_shadow_deck.x);
	vec2 uv = foot / cloud_shadow_deck.z + 0.5;
	vec3 size = vec3(textureSize(cloud_shadow_texture, 0));
	// Compute derivatives before the altitude branch. Mipmaps integrate the
	// horizontal footprint only; 3D mipmaps would leak top-layer light below.
	vec2 dx = dFdx(uv) * size.xy;
	vec2 dy = dFdy(uv) * size.xy;
	float lod = max(0.0, 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0)));
	if (world_position.y >= cloud_shadow_deck.y) return 1.0;
	float altitude = clamp((world_position.y - cloud_shadow_deck.x)
		/ (cloud_shadow_deck.y - cloud_shadow_deck.x), 0.0, 1.0) * (size.z - 1.0);
	float lower = floor(altitude);
	float a = textureLod(cloud_shadow_texture, vec3(uv, lower), lod).r;
	float b = textureLod(cloud_shadow_texture, vec3(uv, min(lower + 1.0, size.z - 1.0)), lod).r;
	return clamp(mix(a, b, fract(altitude)), 0.0, 1.0);
}

// Match only the assigned sun. Omni/spot/other directional lights stay intact.
// Godot exposes no light ID to light(); co-directional suns cannot be separated.
float cloud_light_transmittance(vec3 world_position, vec3 world_light_direction,
		bool is_directional) {
	if (!is_directional || dot(world_light_direction, cloud_shadow_sun_direction) < 0.99999) return 1.0;
	return cloud_sun_transmittance(world_position);
}
