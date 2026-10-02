// Shared by every energy sphere layer: the same hashes and discharge clock keep them in sync.
// Callers pass their own time; replays rewrite TIME only in the main shader sources.

float es_hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float es_hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 es_direction(vec2 seed) {
	float z = es_hash2(seed) * 2.0 - 1.0;
	float a = es_hash2(seed + 17.3) * 6.2831853;
	float s = sqrt(1.0 - z * z);
	return vec3(s * cos(a), z, s * sin(a));
}

vec3 es_turn(vec3 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// Orthonormal frame whose z faces the camera: the whirl and the tendrils are framed for the viewer.
mat3 es_view_frame(vec3 local_camera) {
	vec3 z = normalize(local_camera);
	vec3 helper = abs(z.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 x = normalize(cross(helper, z));
	return mat3(x, cross(z, x), z);
}

// Discharge clock: one surge every ~6.5 s at a random offset. Seconds since the latest surge.
float es_surge_age(float t) {
	const float period = 6.5;
	float epoch = floor(t / period);
	float age = t - (epoch + es_hash(epoch) * 0.55) * period;
	if (age < 0.0) {
		epoch -= 1.0;
		age = t - (epoch + es_hash(epoch) * 0.55) * period;
	}
	return age;
}

float es_surge(float t) {
	float age = es_surge_age(t);
	return smoothstep(0.0, 0.06, age) * exp(-age * 1.7);
}
