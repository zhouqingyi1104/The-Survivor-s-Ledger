shader_type spatial;

uniform vec4 field : source_color = vec4(0.48, 0.30, 0.23, 1.0);
uniform vec4 indigo : source_color = vec4(0.20, 0.30, 0.30, 1.0);
uniform vec4 yarn : source_color = vec4(0.76, 0.64, 0.44, 1.0);

void fragment() {
	// 尺寸为米；四角连续包边。菱花只织在边栏和毯心，家具下面留素地。
	vec2 p = (UV - 0.5) * vec2(2.65, 2.30);
	vec2 edge = vec2(1.325, 1.15) - abs(p);
	float d = min(edge.x, edge.y);
	float aa = max(fwidth(d), 0.001);
	vec3 color = mix(indigo.rgb, field.rgb, smoothstep(0.158 - aa, 0.158 + aa, d));
	float edging = 1.0 - smoothstep(0.006, 0.006 + aa, min(abs(d - 0.024), abs(d - 0.134)));
	float along = edge.x < edge.y ? p.y : p.x;
	float lozenge = abs(fract(along / 0.16 + 0.5) - 0.5) * 0.16 + abs(d - 0.079);
	float border = 1.0 - smoothstep(0.026, 0.026 + aa, lozenge);
	float center = abs(p.x) * 0.74 + abs(p.y);
	float medallion = 1.0 - smoothstep(0.012, 0.012 + aa, min(abs(center - 0.51), abs(center - 0.45)));
	color = mix(color, yarn.rgb, max(edging, max(border, medallion * 0.62)));
	vec2 thread = UV * vec2(176.0, 128.0);
	float fade = 1.0 - smoothstep(0.20, 0.72, max(fwidth(thread.x), fwidth(thread.y)));
	float ribs = cos(thread.y * 6.283185) * 0.053 + cos(thread.x * 6.283185) * 0.025;
	ALBEDO = color * (1.0 + fade * ribs);
	ROUGHNESS = 0.94;
}
