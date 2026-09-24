shader_type spatial;
render_mode unshaded;

uniform sampler3D energy_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 violet : source_color = vec4(0.38, 0.025, 0.95, 1.0);
uniform vec4 magenta : source_color = vec4(0.85, 0.035, 0.48, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float pulse_amount : hint_range(0.0, 0.2) = 0.055;
uniform float core_radius : hint_range(0.2, 0.8) = 0.55;
uniform float filament_width : hint_range(0.003, 0.06) = 0.017;
uniform float pattern_scale : hint_range(0.3, 3.0) = 1.0;
uniform float phase = 0.0;

varying vec3 local_position;
varying flat vec3 local_camera;

vec3 turn(vec3 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

float clouds(vec3 p, float t) {
	p = turn(p, t * 0.11 + p.y * 0.35) * pattern_scale;
	float broad = texture(energy_noise, p * 0.52 + vec3(0.0, t * 0.018, 0.0)).r;
	float detail = texture(energy_noise, p * 1.9 - vec3(t * 0.012, 0.0, 0.0)).r;
	return broad * 0.75 + detail * 0.25;
}

// Bent planes intersect the sphere as continuous, curved dark filaments: no UV seams.
float filaments(vec3 p, float t) {
	p = turn(p, t * 0.07);
	float bend = 0.10 * sin(p.y * 4.0 + p.z * 2.0 + t * 0.12);
	float a = abs(dot(p, normalize(vec3(0.8, 0.45, 0.4))) + bend - 0.1);
	float b = abs(dot(p, normalize(vec3(-0.3, 0.9, 0.3))) - bend + 0.24);
	float c = abs(dot(p, normalize(vec3(0.6, -0.25, 0.75))) + bend - 0.35);
	float distance_to_arc = min(a, min(b, c));
	float aa = max(fwidth(distance_to_arc), 0.001);
	float width = filament_width * (0.8 + 0.25 * sin(p.x * 5.0 + p.y * 3.0 + t * 0.2));
	return 1.0 - smoothstep(width - aa, width + aa, distance_to_arc);
}

void vertex() {
	local_position = VERTEX;
	local_camera = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	float t = TIME * animation_speed + phase;
	vec3 p = normalize(local_position);
	vec3 ray = normalize(local_position - local_camera);
	vec3 closest = local_camera - ray * dot(local_camera, ray);
	float impact2 = dot(closest, closest);
	float facing = clamp(dot(p, -ray), 0.0, 1.0);
	float n = clouds(p, t);
	float pulse = 1.0 + pulse_amount * sin(t * 1.1) + 0.012 * sin(t * 8.3) * sin(t * 5.7);

	// Analytic intersections with two interior spheres supply true view-dependent parallax.
	// ponytail: layered surfaces, not a volume integral; raymarch only if fly-through is needed.
	float core_hit = 1.0 - smoothstep(core_radius * core_radius - 0.012, core_radius * core_radius + 0.012, impact2);
	vec3 core_point = closest - ray * sqrt(max(core_radius * core_radius - impact2, 0.0));
	float core_facing = sqrt(max(1.0 - impact2 / (core_radius * core_radius), 0.0));
	float core_edge = pow(1.0 - core_facing, 3.0) * core_hit;
	vec3 color = vec3(0.003, 0.0005, 0.006);
	color += violet.rgb * (0.012 + n * 0.025) * (1.0 - core_hit * 0.9);
	color += mix(violet.rgb, magenta.rgb, 0.65) * core_edge * (0.35 + clouds(core_point * 1.4, -t) * 0.75);

	float inner_radius = 0.84;
	float inner_hit = 1.0 - smoothstep(0.69, 0.71, impact2);
	vec3 inner_point = closest - ray * sqrt(max(inner_radius * inner_radius - impact2, 0.0));
	float inner_noise = clouds(inner_point * 1.3, -t * 0.65 + 8.0);
	float inner_energy = smoothstep(0.40, 0.70, inner_noise);
	float inner_arcs = filaments(inner_point / inner_radius, -t * 0.5 + 4.0);
	color += mix(violet.rgb, magenta.rgb, inner_noise) * inner_energy * inner_hit * 0.11 * (1.0 - core_hit * 0.93);
	color *= 1.0 - inner_arcs * inner_hit * 0.55;

	float surface_energy = smoothstep(0.43, 0.73, n);
	float wisps = pow(max(1.0 - abs(n - 0.53) * 15.0, 0.0), 3.0);
	color += mix(violet.rgb, magenta.rgb, smoothstep(0.45, 0.7, n)) * (surface_energy * 0.055 + wisps * 0.012) * (1.0 - core_hit * 0.90);
	float arcs = filaments(p, t);
	color *= 1.0 - arcs * 0.96;
	float rim = pow(1.0 - facing, 5.0);
	color += violet.rgb * rim * (0.6 + n * 0.8) * (1.0 - arcs * 0.65);
	// Unshaded HDR albedo is the emitted radiance (EMISSION is ignored in this path).
	ALBEDO = color * emission_strength * pulse;
}
