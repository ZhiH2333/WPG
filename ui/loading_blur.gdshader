shader_type canvas_item;

// 加载页底图：高 LOD + 大半径采样，再压成暗色。
uniform float blur_lod : hint_range(0.0, 8.0) = 6.0;
uniform float blur_spread : hint_range(0.0, 0.12) = 0.045;
uniform float dim_amount : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	float inner = blur_spread;
	float outer = blur_spread * 2.2;
	vec4 acc = textureLod(TEXTURE, UV, blur_lod) * 0.22;
	acc += textureLod(TEXTURE, UV + vec2(inner, 0.0), blur_lod) * 0.10;
	acc += textureLod(TEXTURE, UV - vec2(inner, 0.0), blur_lod) * 0.10;
	acc += textureLod(TEXTURE, UV + vec2(0.0, inner), blur_lod) * 0.10;
	acc += textureLod(TEXTURE, UV - vec2(0.0, inner), blur_lod) * 0.10;
	acc += textureLod(TEXTURE, UV + vec2(inner, inner), blur_lod) * 0.07;
	acc += textureLod(TEXTURE, UV - vec2(inner, inner), blur_lod) * 0.07;
	acc += textureLod(TEXTURE, UV + vec2(inner, -inner), blur_lod) * 0.07;
	acc += textureLod(TEXTURE, UV + vec2(-inner, inner), blur_lod) * 0.07;
	acc += textureLod(TEXTURE, UV + vec2(outer, 0.0), blur_lod) * 0.025;
	acc += textureLod(TEXTURE, UV - vec2(outer, 0.0), blur_lod) * 0.025;
	acc += textureLod(TEXTURE, UV + vec2(0.0, outer), blur_lod) * 0.025;
	acc += textureLod(TEXTURE, UV - vec2(0.0, outer), blur_lod) * 0.025;
	acc.rgb = mix(acc.rgb, vec3(0.03, 0.025, 0.035), dim_amount);
	COLOR = vec4(acc.rgb, 1.0);
}
