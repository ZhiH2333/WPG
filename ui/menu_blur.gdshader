shader_type canvas_item;

// osu 式背景处理：打开叠层时对下方画面做 mip 模糊 + 压暗。
// blur_amount 用 screen texture 的 LOD 实现，0 时等价直通。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 4.0) = 0.0;
uniform float dim_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base_color = textureLod(screen_tex, SCREEN_UV, blur_amount);
	base_color.rgb = mix(base_color.rgb, vec3(0.05, 0.04, 0.06), dim_amount);
	COLOR = vec4(base_color.rgb, 1.0);
}
