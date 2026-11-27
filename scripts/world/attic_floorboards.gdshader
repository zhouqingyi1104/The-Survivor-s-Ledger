shader_type spatial;

uniform sampler2D wood_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wood_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wood_arm : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 oiled_oak : source_color = vec4(0.53, 0.41, 0.30, 1.0);

void fragment() {
	vec3 timber = texture(wood_color, UV).rgb;
	float grain = dot(timber, vec3(0.30, 0.56, 0.14));
	// A worn oil finish retains the annual rings; dark knots no longer read as pits.
	vec3 warm = mix(vec3(1.0), COLOR.rgb, 0.23);
	ALBEDO = oiled_oak.rgb * warm * (0.57 + 0.90 * smoothstep(0.025, 0.61, grain));
	NORMAL_MAP = texture(wood_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.22;
	vec3 arm = texture(wood_arm, UV).rgb;
	ROUGHNESS = mix(0.58, 0.81, arm.g);
	AO = mix(0.87, 1.0, arm.r);
	SPECULAR = 0.29;
}
