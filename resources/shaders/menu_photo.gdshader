shader_type canvas_item;

void fragment() {
	// COLOR already contains the photograph and CanvasItem modulation.
	// Keep white titles legible without flattening the rest of the photograph.
	float shade = mix(0.04, 0.82, smoothstep(0.35, 1.0, UV.y));
	COLOR.rgb = mix(COLOR.rgb, vec3(0.015, 0.025, 0.035), shade);
}
