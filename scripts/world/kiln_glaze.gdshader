shader_type spatial;

uniform vec4 glaze : source_color = vec4(0.31, 0.25, 0.155, 1.0);
uniform vec4 bare_clay : source_color = vec4(0.49, 0.32, 0.20, 1.0);
uniform sampler2D mineral_grain : repeat_enable, filter_linear_mipmap;

void fragment() {
	float angle = UV.x * 6.283185;
	float height = UV.y;
	float drip = 0.019 * sin(angle * 5.0 + 0.8) + 0.014 * cos(angle * 9.0);
	float glazed = smoothstep(0.15 + drip, 0.174 + drip, height);
	float throwing = 0.5 + 0.5 * sin(height * 218.0 + 0.6 * cos(2.0 * angle));
	float soft = 1.0 - smoothstep(0.5, 2.0, fwidth(height * 218.0));
	// A little iron in the glaze breaks the highlight along the thrown clay.
	// The same deposited grains carry colour and roughness across each vessel.
	float oxides = texture(mineral_grain, UV * vec2(3.0, 1.0)).g;
	float iron_spots = smoothstep(0.68,0.85,oxides);
	float ash = 0.50 + 0.26 * sin(angle * 2.0 + height * 4.0) + 0.13 * cos(angle * 5.0 - height * 7.0);
	vec3 slip = glaze.rgb * (0.73 + ash * 0.53 + (throwing - 0.5) * 0.09 * soft);
	slip = mix(slip, slip * vec3(0.73,0.56,0.43), iron_spots * 0.49);
	ALBEDO = mix(bare_clay.rgb * (0.72 + 0.42*oxides), slip, glazed);
	ROUGHNESS = mix(0.93, 0.25 + 0.13 * ash + 0.10 * oxides + 0.08 * throwing * soft, glazed);
	SPECULAR = mix(0.20, 0.58, glazed);
}
