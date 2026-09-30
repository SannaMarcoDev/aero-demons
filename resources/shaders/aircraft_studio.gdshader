shader_type canvas_item;

uniform bool photograph = false;
uniform vec2 rect_size = vec2(1282.0, 570.0);
varying vec2 box_uv;

void vertex() {
	box_uv = VERTEX / rect_size;
}

void fragment() {
	if (photograph) {
		float edge = smoothstep(0.0, 0.14, box_uv.x) * smoothstep(0.0, 0.14, 1.0 - box_uv.x);
		edge *= smoothstep(0.0, 0.16, box_uv.y) * smoothstep(0.0, 0.18, 1.0 - box_uv.y);
		float luma = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR.rgb = mix(vec3(luma), COLOR.rgb, 0.65) * 0.82;
		COLOR.a *= edge;
	} else {
		vec2 pixel = FRAGCOORD.xy;
		float grain = fract(sin(dot(floor(pixel), vec2(12.9898, 78.233))) * 43758.5453);
		float dots = smoothstep(0.18, 0.46, length(fract(pixel / 4.0) - 0.5));
		float light = exp(-length((UV - vec2(0.36, 0.47)) * vec2(1.2, 1.8)) * 2.0);
		vec3 studio = mix(vec3(0.025, 0.033, 0.041), vec3(0.16, 0.18, 0.20), light);
		studio += (grain - 0.5) * 0.025;
		studio *= mix(0.86, 1.0, dots);
		COLOR.rgb *= studio;
	}
}
