shader_type spatial;
render_mode world_vertex_coords;

uniform vec4 dye : source_color = vec4(0.35, 0.4, 0.44, 1.0);
varying vec2 textile_coords;

void vertex() {
	// 四向院落共用世界坐标。布的正面、背面和薄包边沿同一褶线变形。
	textile_coords = vec2(VERTEX.x + VERTEX.z, VERTEX.y);
	float hang = clamp((1.85 - VERTEX.y) / 0.82, 0.0, 1.0);
	float wave = textile_coords.x * 29.0;
	float depth = mix(0.008, 0.027, hang);
	vec3 fold = vec3(0.7, 0.0, -0.7);
	VERTEX += fold * (cos(wave) * depth);
	VERTEX.y -= (0.5 + 0.5 * cos(wave * 0.5)) * hang * 0.032;
	vec3 slope = vec3(-29.0 * sin(wave) * depth, -cos(wave) * 0.019 / 0.82, -29.0 * sin(wave) * depth);
	NORMAL = normalize(NORMAL - slope * dot(fold, NORMAL));
}

void fragment() {
	vec2 grain = textile_coords * 115.0;
	float warp = 0.5 + 0.5 * cos(grain.x * TAU);
	float weave = 0.5 + 0.5 * cos(grain.y * TAU);
	float visible_threads = 1.0 - smoothstep(0.25, 0.80, max(fwidth(grain.x), fwidth(grain.y)));
	ALBEDO = dye.rgb * (0.98 + (warp * weave - 0.25) * visible_threads * 0.06);
	ROUGHNESS = 0.94;
}
