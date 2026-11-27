shader_type spatial;

// 折屏由左至右连续展卷；独幅挂轴使用完整的画心。
uniform sampler2D sheet : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int leaf = -1;

void fragment() {
	vec2 uv = UV;
	if (leaf >= 0) {
		uv.x = (uv.x + float(leaf)) / 3.0;
	}
	ALBEDO = texture(sheet, uv).rgb;
	ROUGHNESS = 0.97;
	SPECULAR = 0.13;
}
