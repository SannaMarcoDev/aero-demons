shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, depth_draw_never, depth_test_disabled;

// Original, bounded emission/refraction volume. Proxy occupies [-1,1] XY, [-0.5,0.5] Z.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D flow_noise : repeat_enable, filter_linear;
uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform float nozzle_radius = 0.45;
uniform float plume_length = 1.6;
uniform float haze_length = 3.6;
uniform float distortion = 3.0;
uniform float brightness = 1.0;
uniform float turbulence = 0.2;
uniform float phase = 0.0;
uniform int steps = 24;
uniform float distance_fade = 1.0;
uniform vec4 hot_color : source_color = vec4(1.0, 0.85, 0.67, 1.0);
uniform vec4 edge_color : source_color = vec4(0.70, 0.45, 1.0, 1.0);
uniform vec4 halo_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
varying vec3 local_surface;
varying flat mat4 view_to_local;

void vertex() {
    local_surface = VERTEX;
    view_to_local = inverse(MODELVIEW_MATRIX);
}

float scene_distance(vec2 uv, vec3 origin, vec3 direction, mat4 inv_projection) {
    float d = textureLod(depth_texture, uv, 0.0).r;
    vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
    p /= p.w;
    return dot((view_to_local * p).xyz - origin, direction);
}

void fragment() {
    vec3 origin = (view_to_local * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 direction = normalize(local_surface - origin);
    // Nonzero reciprocals keep exact rear/side views well-defined.
    vec3 inv_ray = 1.0 / mix(vec3(-1.0), vec3(1.0), greaterThanEqual(direction, vec3(0.0))) / max(abs(direction), vec3(0.00001));
    vec3 a = (vec3(-1.0, -1.0, -0.5) - origin) * inv_ray;
    vec3 b = (vec3(1.0, 1.0, 0.5) - origin) * inv_ray;
    vec3 lo = min(a, b);
    vec3 hi = max(a, b);
    float entry = max(max(max(lo.x, lo.y), lo.z), 0.0);
    float exit_t = min(min(hi.x, hi.y), hi.z);
    exit_t = min(exit_t, scene_distance(SCREEN_UV, origin, direction, INV_PROJECTION_MATRIX));
    if (exit_t <= entry || power < 0.001 || distance_fade < 0.001) { discard; }

    float stride = (exit_t - entry) / float(steps);
    // Static subpixel integration offset breaks marching bands without temporal flicker.
    float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
    vec3 metric = vec3(nozzle_radius * 2.4, nozzle_radius * 2.4, haze_length);
    float ds = length(direction * metric) * stride / nozzle_radius;
    float haze = 0.0;
    vec2 bend = vec2(0.0);
    vec3 light = vec3(0.0);
    // Integrate the thin luminous nozzle as a plane, not jittered volume samples.
    // This keeps the mouth smooth at dry thrust and avoids a white slab in side views.
    float nozzle_t = (-0.5 - origin.z) * inv_ray.z;
    vec2 nozzle_xy = (origin + direction * nozzle_t).xy * 2.4;
    float nozzle_r = length(nozzle_xy);
    // Derivatives outside the intersection branch keep the stationary grille antialiased.
    float grille_aa = max(length(fwidth(nozzle_xy)) * 0.65, 0.001);
    float grille = 0.0;
    if (nozzle_t >= entry - 0.00001 && nozzle_t <= exit_t) {
        float nozzle = 1.0 - smoothstep(0.88, 1.0, nozzle_r);
        float angle = atan(nozzle_xy.y, nozzle_xy.x + 0.00001);
        float spokes = abs(sin(angle * 6.0)) * nozzle_r / 6.0;
        float rings = min(abs(nozzle_r - 0.28), min(abs(nozzle_r - 0.53), abs(nozzle_r - 0.78)));
        float ribs = 1.0 - smoothstep(0.016 - grille_aa, 0.016 + grille_aa, min(spokes, rings));
        float hub = 1.0 - smoothstep(0.14, 0.18, nozzle_r);
        // Fade subpixel detail instead of letting distant engines sparkle.
        grille = ribs * (1.0 - hub) * nozzle * (1.0 - smoothstep(0.08, 0.18, grille_aa));
        vec3 face_color = mix(hot_color.rgb, halo_color.rgb * 0.6, hub);
        light += face_color * nozzle * power * power * mix(0.7, 1.6, burn);
    }
    float active_length = plume_length * mix(mix(0.12, 0.42, power), 1.0, burn);
    float haze_end = mix(0.28, 1.0, power);
    for (int i = 0; i < steps; i++) {
        vec3 p = origin + direction * (entry + (float(i) + 0.2 + jitter * 0.6) * stride);
        p.z += 0.5;
        float z = p.z * haze_length;
        vec3 flow_uv = vec3(p.xy * 1.15, z / nozzle_radius * 0.18 - clock) + vec3(phase);
        float n = textureLod(flow_noise, flow_uv, 0.0).r;
        float m = textureLod(flow_noise, flow_uv * 2.0 + vec3(0.19, 0.43, 0.71), 0.0).r;
        vec2 eddy = (vec2(n, m) - 0.5) * 2.0;
        vec2 xy = p.xy * 2.4 + eddy * turbulence * (0.06 + p.z * 0.42);
        float r = length(xy);
        float spread = 0.92 + p.z * 1.15;
        float gas = exp(-3.0 * r * r / (spread * spread));
        gas *= smoothstep(0.0, 0.035, p.z) * (1.0 - smoothstep(haze_end * 0.35, haze_end, p.z));
        gas *= 0.65 + n * 0.7;
        haze += gas * ds;
        bend += eddy * gas * ds;

        // Broad, coherent pink-violet jet; weak compression, not a string of bright beads.
        float axial = z / max(active_length, 0.01);
        float cell = 1.0 + 0.08 * burn * cos(z / nozzle_radius * 3.7);
        float jet_radius = 0.90 - 0.18 * smoothstep(0.0, 1.0, axial);
        float radial = exp(-2.4 * pow(r / jet_radius, 4.0));
        float tail = 1.0 - smoothstep(0.25, 1.0, axial);
        float flame = radial * tail * (0.94 + 0.12 * n) * cell;
        float thrust = power * power * mix(0.16, 1.0, burn);
        light += edge_color.rgb * flame * thrust * 1.1 * ds;
        // Warm translucent outer halo, separate from the violet centre.
        float halo = exp(-1.8 * r * r) * smoothstep(0.35, 0.85, r)
            * (1.0 - smoothstep(0.1, 1.25, axial));
        light += halo_color.rgb * halo * thrust * ds;
    }
    // Keep the flame-holder rings and spokes legible through the bright foreground gas.
    light *= 1.0 - grille * 0.8;
    float coverage = (1.0 - exp(-haze * 0.55)) * smoothstep(0.0, 0.16, power) * distance_fade;
    if (coverage < 0.001) { discard; }
    float camera_distance = length(VERTEX);
    float pixel_scale = min(1.8, 12.0 / max(camera_distance, 1.0));
    vec2 offset = bend / max(haze, 0.001) * 2.8 * distortion * power * pixel_scale / VIEWPORT_SIZE;
    vec2 uv = clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999));
    // Do not pull nearer aircraft/foreground silhouettes into the hot air.
    float shifted_depth = scene_distance(uv, origin, direction, INV_PROJECTION_MATRIX);
    uv = mix(SCREEN_UV, uv, smoothstep(entry, entry + 0.08, shifted_depth));
    // Unshaded output carries HDR radiance directly (also feeds environment glow).
    ALBEDO = textureLod(screen_texture, uv, 0.0).rgb + light * brightness * distance_fade / max(coverage, 0.001);
    ALPHA = coverage;
}
