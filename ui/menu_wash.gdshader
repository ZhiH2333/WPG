shader_type canvas_item;
render_mode blend_mix;

void fragment() {
	float top_band = 1.0 - smoothstep(0.0, 0.22, UV.y);
	float bottom_band = smoothstep(0.42, 0.92, UV.y);
	float alpha = max(0.46, max(top_band * 0.72, bottom_band * 0.78));
	COLOR = vec4(0.07, 0.05, 0.04, alpha);
}
