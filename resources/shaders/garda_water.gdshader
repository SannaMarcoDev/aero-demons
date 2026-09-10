// Deep, cold water for the flight map. Opaque on purpose: SunshineClouds
// composites before transparency and must see the water's depth, not its bed.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Water;
uniform vec3 water_color : source_color = vec3(0.055, 0.145, 0.18);
uniform float surface_roughness : hint_range(0.08, 0.6) = 0.23;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.38;

group_uniforms Ripples;
uniform sampler2D wave_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float ripple_size : hint_range(1.0, 200.0) = 32.0;
uniform float wave_size : hint_range(50.0, 2000.0) = 240.0;
uniform float swell_size : hint_range(200.0, 5000.0) = 1800.0;

varying vec3 world_position;

void vertex() {
	// The map is enormous. Shading waves in world metres avoids UV stretching
	// and a tessellated grid whose cells are larger than the waves themselves.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	// Fixed phase: retain the approved ripples without scrolling them.
	vec2 drift = vec2(9.6, 3.6);
	float distance_to_camera = length(VERTEX);
	float fine_weight = 1.0 - smoothstep(250.0, 3000.0, distance_to_camera);
	float wave_weight = 1.0 - smoothstep(2500.0, 16000.0, distance_to_camera);
	float swell_weight = 1.0 - smoothstep(18000.0, 65000.0, distance_to_camera);

	vec2 fine = texture(wave_normal, (p - drift) / ripple_size).rg * 2.0 - 1.0;
	// Rotate the second layer and its slopes together; no sliding checkerboard.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 waves = texture(wave_normal, turn * (p - drift * 0.7) / wave_size).rg * 2.0 - 1.0;
	waves = transpose(turn) * waves;
	vec2 swell = texture(wave_normal, (p - drift * 0.35) / swell_size).rg * 2.0 - 1.0;
	vec2 slope = normal_strength * (fine * fine_weight + waves * 0.6 * wave_weight + swell * 0.28 * swell_weight);
	vec3 world_normal = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// Subtle wind patches, not luminous foam or tropical caustics.
	float patch = texture(surface_noise, (p - drift * 0.25) / 11000.0).r;
	ALBEDO = water_color * mix(0.88, 1.12, patch);
	METALLIC = 0.0;
	SPECULAR = 0.35; // Godot dielectric F0 = 0.16 * SPECULAR^2: water ~0.02.
	// Broaden unresolved glints instead of sparkling at flight altitude.
	ROUGHNESS = clamp(surface_roughness + 0.10 * (1.0 - fine_weight) + 0.04 * patch, 0.08, 0.6);
}
