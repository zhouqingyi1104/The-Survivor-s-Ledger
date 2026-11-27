shader_type spatial;

uniform sampler2D stone_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_arm : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 slate : source_color = vec4(0.40, 0.42, 0.41, 1.0);

void fragment() {
	vec3 sample_color = texture(stone_color, UV).rgb;
	float value = dot(sample_color, vec3(0.30, 0.56, 0.14));
	vec3 arm = texture(stone_arm, UV).rgb;
	ALBEDO = slate.rgb * (0.80 + 0.46 * smoothstep(0.05, 0.54, value)) * COLOR.r;
	NORMAL_MAP = texture(stone_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.24;
	ROUGHNESS = mix(0.70, 0.91, arm.g);
	AO = mix(0.82, 1.0, arm.r);
	SPECULAR = 0.24;
}
