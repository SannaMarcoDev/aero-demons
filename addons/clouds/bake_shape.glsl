#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;
layout(set = 0, binding = 0) uniform Params {
	mat4 inv_view; mat4 inv_proj; vec4 cam_pos; vec4 sun_dir;
	vec4 sun_color; vec4 deck; vec4 misc;
} p;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image3D out_shape;
layout(std430, set = 0, binding = 2) readonly buffer Cells { vec4 data[]; } cells;
layout(set = 0, binding = 3) uniform sampler3D noise_tex;

// Yaw-rotated conservative ellipsoid distance (Lipschitz <= 1).
float ellipsoid(vec3 pos, int i) {
	vec4 c = cells.data[i], r = cells.data[i + 1];
	vec3 q = pos - c.xyz;
	q.xz = vec2(q.x * c.w + q.z * r.w, -q.x * r.w + q.z * c.w);
	return (length(q / r.xyz) - 1.0) * min(r.x, min(r.y, r.z));
}
float unite(float a, float b) {
	float h = max(250.0 - abs(a - b), 0.0) / 250.0;
	return min(a, b) - h * h * 62.5;
}
void main() {
	ivec3 pix = ivec3(gl_GlobalInvocationID);
	ivec3 size = imageSize(out_shape);
	if (any(greaterThanEqual(pix, size))) return;
	vec3 uv = (vec3(pix) + 0.5) / vec3(size);
	vec3 pos = vec3(uv.x * p.deck.w, mix(p.deck.x, p.deck.y, uv.y), uv.z * p.deck.w);
	ivec2 bin = ivec2(floor(uv.xz * 10.0));
	ivec2 range = ivec2(cells.data[bin.y * 10 + bin.x].xy);
	// Matches FIELD_CLAMP / SHAPE_BLEND in noise_gen.gd. CPU binning
	// includes the entire influence region, not just the visible surface.
	float field = 4000.0;
	for (int i = range.x; i < range.y; i += 2) field = unite(field, ellipsoid(pos, i));
	// Intermediate-scale erosion breaks analytic arcs; the rising bodies,
	// not noise, determine the silhouettes. Four periods across the map.
	// Erosion only removes matter, so the un-eroded G field stays a safe
	// distance bound regardless of the contour's local noise gradients.
	vec4 n = textureLod(noise_tex, (pos - vec3(p.deck.w * 0.5, 0.0, p.deck.w * 0.5)) / 25000.0, 0.0);
	// Developing crowns need broad, rounded recesses, not a fine rough
	// skin over an exposed analytic oval. Keep thin low banks intact.
	float crown = smoothstep(p.deck.x + 1800.0, p.deck.x + 5000.0, pos.y);
	float erosion = max(0.0, (n.b - 0.43) * 1000.0 + (n.a - 0.5) * 300.0
		+ crown * max(0.0, 0.78 - n.g) * 1200.0);
	imageStore(out_shape, pix, vec4(field + erosion, field, 0.0, 0.0));
}
