shader_type spatial;
render_mode blend_add, unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

// Emissive volume for a jet afterburner plume, ray-marched in object space with +Z as the
// exhaust direction and the nozzle exit at z = 0, so its shape stays correct from every
// angle instead of collapsing into a billboard when seen from behind.
//
// The mesh is a unit BoxMesh that vertex() stretches over the plume bounds, so the shader
// owns the geometry and nothing has to be kept in sync with it. Because that happens after
// culling is computed, the MeshInstance needs an extra_cull_margin covering plume_length.

uniform sampler2D temperature_ramp : source_color, filter_linear;
uniform sampler3D turbulence : filter_linear, repeat_enable;
uniform sampler2D depth_buffer : hint_depth_texture, filter_nearest;

uniform float throttle : hint_range(0.0, 1.0) = 1.0;
uniform float plume_length = 3.2;
uniform float idle_length : hint_range(0.05, 1.0) = 0.3;
uniform float nozzle_radius = 0.33;
uniform float spread : hint_range(0.5, 4.0) = 1.6;
uniform float radial_falloff : hint_range(0.5, 8.0) = 2.4;
// Above 2 the radial profile becomes a soft-edged top hat, which fills the nozzle mouth
// the way a real plume does instead of tapering to a point at the axis.
uniform float radial_shape : hint_range(1.0, 6.0) = 3.0;
uniform float axial_falloff : hint_range(0.2, 6.0) = 1.5;
uniform float emission_energy = 1.6;
// Self-extinction: without it the march just sums the whole depth of the plume, the axis
// saturates to white and the turbulent structure nearest the camera is averaged away.
uniform float absorption : hint_range(0.0, 12.0) = 3.0;
uniform float idle_energy : hint_range(0.0, 1.0) = 0.12;

uniform float turbulence_scale = 1.6;
uniform float turbulence_detail = 3.1;
uniform float turbulence_amount : hint_range(0.0, 2.0) = 0.8;
uniform float turbulence_onset : hint_range(0.0, 1.0) = 0.12;
uniform float turbulence_floor : hint_range(0.0, 1.0) = 0.45;
// Fractal noise clusters tightly around 0.5, so without expanding it around the midpoint
// the plume only gets a few percent of modulation and reads as a smooth blob.
uniform float turbulence_contrast : hint_range(1.0, 8.0) = 3.0;
// Eddies are stretched along the flow, so a head-on ray keeps the mottling instead of
// averaging it away over its whole path.
uniform float turbulence_stretch : hint_range(0.02, 1.0) = 0.18;
uniform float flow_speed = 6.0;

uniform float core_heat : hint_range(0.2, 6.0) = 1.0;
uniform float core_focus : hint_range(0.2, 8.0) = 2.6;
uniform float cooling : hint_range(0.0, 2.0) = 0.85;
uniform float shock_count = 4.0;
uniform float shock_strength : hint_range(0.0, 1.5) = 0.5;
uniform float shock_decay : hint_range(0.0, 8.0) = 2.6;

const int STEPS = 48;

varying vec3 v_object_pos;

// Offsets each pixel's first sample so the fixed step count stops resolving into
// concentric shells around the plume axis.
float dither(vec2 pixel) {
	vec3 p = fract(vec3(pixel.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float bound_radius() {
	return nozzle_radius * spread * (1.0 + 0.9 * turbulence_amount);
}

void vertex() {
	VERTEX.xy *= 2.0 * bound_radius();
	VERTEX.z = (VERTEX.z + 0.5) * plume_length;
	v_object_pos = VERTEX;
}

float plume_radius(float axial) {
	// pow() of a negative base is undefined and the NaN spreads through the whole march,
	// which a ray grazing the z = 0 face can otherwise trigger.
	return nozzle_radius * mix(1.0, spread, pow(clamp(axial, 0.0, 1.0), 0.8));
}

void fragment() {
	float len = plume_length * mix(idle_length, 1.0, throttle);
	float rmax = bound_radius();

	vec3 ro = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 rd = normalize(v_object_pos - ro);

	vec3 t0 = (vec3(-rmax, -rmax, 0.0) - ro) / rd;
	vec3 t1 = (vec3(rmax, rmax, len) - ro) / rd;
	vec3 tsmall = min(t0, t1);
	vec3 tbig = max(t0, t1);
	float tnear = max(max(tsmall.x, tsmall.y), max(tsmall.z, 0.0));
	float tfar = min(min(tbig.x, tbig.y), tbig.z);

	// Stop the march at opaque geometry so the plume never bleeds through the airframe.
	float raw_depth = texture(depth_buffer, SCREEN_UV).x;
	if (raw_depth > 0.0) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
		tfar = min(tfar, length(view.xyz / view.w));
	}
	if (tfar <= tnear) {
		discard;
	}

	vec3 accumulated = vec3(0.0);
	{
		float dt = (tfar - tnear) / float(STEPS);
		float t = tnear + dt * dither(FRAGCOORD.xy);
		float transmittance = 1.0;

		for (int i = 0; i < STEPS; i++) {
			if (transmittance < 0.004) {
				break;
			}
			vec3 p = ro + rd * t;
			t += dt;
			float axial = clamp(p.z / len, 0.0, 1.0);

			vec3 flow = vec3(p.xy, (p.z - TIME * flow_speed) * turbulence_stretch)
				* turbulence_scale;
			float noise = texture(turbulence, flow).r * 0.65
				+ texture(turbulence, flow * turbulence_detail).r * 0.35;
			noise = clamp((noise - 0.5) * turbulence_contrast + 0.5, 0.0, 1.0);

			float radius = plume_radius(axial);
			float r = length(p.xy) / radius;

			// The shear layer at the plume edge tears up right at the nozzle while the core
			// stays coherent for a while, so turbulence is driven by radius as well as
			// distance. Perturbing the radius, not just the density, breaks the silhouette.
			float breakup = turbulence_amount * max(turbulence_floor,
				max(smoothstep(0.15, 0.95, r), smoothstep(turbulence_onset, 0.75, axial)));
			r /= max(1.0 + (noise - 0.45) * breakup, 0.2);

			float density = exp(-radial_falloff * pow(max(r, 0.0001), radial_shape))
				* pow(max(1.0 - axial, 0.0), axial_falloff);
			density *= mix(1.0, 0.35 + noise * 1.5, breakup);
			// The exponential tail is still faintly non-zero where the proxy box ends, which
			// would print the box silhouette onto the sky, so fade it out before the faces.
			density *= smoothstep(1.0, 0.72, length(p.xy) / rmax);

			float temperature = core_heat * (1.0 - axial * cooling) * exp(-core_focus * r * r);
			float shock = 0.5 + 0.5 * cos(axial * shock_count * TAU);
			float diamonds = shock_strength * shock * exp(-shock_decay * axial)
				* smoothstep(1.0, 0.25, r);
			temperature *= 1.0 + diamonds;
			density *= 1.0 + diamonds * 0.6;
			vec3 color = texture(temperature_ramp, vec2(clamp(temperature, 0.0, 1.0), 0.5)).rgb;

			accumulated += color * density * dt * transmittance;
			transmittance *= exp(-density * absorption * dt);
		}
	}

	ALBEDO = accumulated * emission_energy * mix(idle_energy, 1.0, pow(throttle, 1.4));
	ALPHA = 1.0;
}
