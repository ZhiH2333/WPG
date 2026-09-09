shader_type canvas_item;

// osu ButtonSystem：按 Y 剪切成右倾平行四边形，hover 时略提亮。
uniform vec4 fill_color : source_color = vec4(0.2, 0.18, 0.24, 0.92);
uniform float shear : hint_range(0.0, 0.6) = 0.16;
uniform float hover : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	VERTEX.x -= VERTEX.y * shear;
}

void fragment() {
	vec3 lit = fill_color.rgb + vec3(0.14, 0.11, 0.13) * hover;
	COLOR = vec4(lit, fill_color.a);
}
