shader_type spatial;

uniform vec4 paper : source_color = vec4(0.89, 0.84, 0.72, 1.0);
uniform sampler2D fiber_relief : hint_normal, repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 edge = min(UV, 1.0 - UV);
	float border = smoothstep(0.0, 0.10, min(edge.x, edge.y));
	float sheet = texture(fiber_relief, UV * vec2(2.5, 1.2)).r - 0.5;
	float fibers = texture(fiber_relief, UV * vec2(2.0, 7.0)).g - 0.5;
	float density = 0.81 + 0.13 * border + 0.16 * sheet + 0.08 * fibers;
	ALBEDO = paper.rgb * density;
	ROUGHNESS = 0.96;
	SPECULAR = 0.18;
	// 天光穿过薄纸，离糊边越远越透。弱透光避免入夜后整扇泛白。
	EMISSION = vec3(0.075, 0.054, 0.031) * border * (1.0 - UV.y * 0.48) * density;
}
