// Earth curvature: a vertex drops by d^2 / 2R with its horizontal distance d from the player camera.
// scripts/maps/earth_curvature.gd sets both uniforms (not CAMERA_POSITION_WORLD: shadow passes render from
// the light). earth_radius 0 keeps the map flat. Displace VERTEX only: textures follow the flat world.
uniform float earth_radius = 0.0;
uniform vec3 curvature_origin = vec3(0.0);

float curvature_drop(vec3 world) {
	vec2 d = world.xz - curvature_origin.xz;
	return earth_radius > 0.0 ? dot(d, d) / (2.0 * earth_radius) : 0.0;
}
