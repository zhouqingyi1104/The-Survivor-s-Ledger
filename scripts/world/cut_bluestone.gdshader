shader_type spatial;

uniform sampler2D stone_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_arm : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float polished : hint_range(0.0, 1.0) = 0.0;
varying vec3 stone_pos;
varying vec3 stone_normal_world;

void vertex() {
	stone_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stone_normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(stone_normal_world);
	// Each face is dressed from one slab. Planar projections meet on chiseled arrises.
	vec3 tangent = vec3(1,0,0);
	vec3 bitangent = vec3(0,0,-1);
	if (abs(n.y) < 0.72) {
		tangent = abs(n.x) > abs(n.z) ? vec3(0,0,-sign(n.x)) : vec3(sign(n.z),0,0);
		bitangent = vec3(0,1,0);
	}
	vec2 uv = vec2(dot(stone_pos, tangent), dot(stone_pos, bitangent)) * 0.84;
	vec3 scan = texture(stone_color, uv).rgb;
	float luma = dot(scan, vec3(0.25, 0.60, 0.15));
	float worn_top = polished * smoothstep(0.30, 0.91, n.y);
	vec3 dry_stone = mix(vec3(luma), scan, 0.13) * vec3(0.80, 0.98, 1.08);
	ALBEDO = mix(dry_stone, 0.38 * dry_stone + vec3(0.091,0.115,0.113), polished * 0.92) * COLOR.rgb;
	vec2 bump = texture(stone_normal, uv).rg * 2.0 - 1.0;
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(n + (0.35 - 0.23 * worn_top) * (tangent * bump.x + bitangent * bump.y)));
	vec3 arm = texture(stone_arm, uv).rgb;
	AO = mix(0.76, 1.0, arm.r);
	ROUGHNESS = mix(mix(0.49, 0.92, arm.g), 0.39 + 0.09 * arm.g, worn_top);
	SPECULAR = 0.36;
}
