shader_type canvas_item;

uniform vec4 overlay_color : source_color = vec4(0.02, 0.04, 0.07, 0.82);
uniform float left_gradient_width : hint_range(0.1, 0.9) = 0.52;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
    vec2 uv = UV;

    // Left-to-right fade for UI backing
    float left_fade = 1.0 - smoothstep(0.15, left_gradient_width, uv.x);
    float alpha = left_fade * 0.85;

    // Top and bottom edge darkening
    float edge_v = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
    alpha = max(alpha, (1.0 - edge_v) * 0.7);

    // Screen corner vignette
    float vig = length((uv - 0.5) * 1.2);
    vig = smoothstep(0.45, 1.0, vig);
    alpha = max(alpha, vig * vignette_strength);

    COLOR = vec4(overlay_color.rgb, alpha);
}
