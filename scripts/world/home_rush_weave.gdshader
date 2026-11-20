shader_type spatial;

uniform vec4 straw : source_color = vec4(0.64, 0.52, 0.35, 1.0);
uniform vec4 binding : source_color = vec4(0.28, 0.35, 0.30, 1.0);

void fragment() {
	// 经草隔根挑起，纬绳用两股合捻。远处淡去细纹，留下席边和较宽的绳带。
	vec2 thread = UV * vec2(79.0, 33.0);
	vec2 f = fract(thread) - 0.5;
	float visible = 1.0 - smoothstep(0.3, 1.4, max(fwidth(thread.x), fwidth(thread.y)));
	float over = mod(floor(thread.x) + floor(thread.y), 2.0);
	float rib = mix(cos(f.x * 6.2832), cos(f.y * 6.2832), over);
	float twist = sin((thread.x * 0.5 + thread.y) * 3.1416);
	vec2 to_edge = min(UV, vec2(1.0) - UV);
	float edge = min(to_edge.x * 2.0, to_edge.y);
	float hem = 1.0 - smoothstep(0.030, 0.037, edge);
	float stripe = 1.0 - smoothstep(0.006, 0.011, abs(edge - 0.061));
	float reed_band = 0.94 + 0.04 * sin(thread.y * 0.51 + UV.x * 2.5);
	ALBEDO = mix(straw.rgb * reed_band, binding.rgb, max(hem, stripe * 0.68)) * (1.0 + visible * (0.20 * rib + 0.04 * twist));
	ROUGHNESS = 0.92 - 0.06 * visible * rib;
	NORMAL_MAP = vec3(0.5 + 0.10 * visible * (1.0 - over) * sin(f.x * 6.2832),
			0.5 + 0.10 * visible * over * sin(f.y * 6.2832), 1.0);
}
