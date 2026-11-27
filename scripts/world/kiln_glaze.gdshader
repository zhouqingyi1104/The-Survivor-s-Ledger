shader_type spatial;

uniform vec4 glaze : source_color = vec4(0.31, 0.25, 0.155, 1.0);
uniform vec4 bare_clay : source_color = vec4(0.49, 0.32, 0.20, 1.0);
uniform sampler2D mineral_grain : repeat_enable, filter_linear_mipmap;

void fragment() {
	float angle = UV.x * 6.283185;
	float height = UV.y;
	float drip = 0.019 * sin(angle * 5.0 + 0.8) + 0.014 * cos(angle * 9.0);
	float glazed = smoothstep(0.15 + drip, 0.174 + drip, height);
	// A shallow finger mark turns around the shoulder. The glass covers most of
	// the ridges below it, leaving a continuous reflection over the belly.
	float shoulder = smoothstep(0.50, 0.76, height) * (1.0 - smoothstep(0.88, 0.95, height));
	float throwing = sin(height * 145.0 + cos(2.0 * angle) + .6*sin(height*18.0));
	float soft = 1.0 - smoothstep(0.65, 2.6, fwidth(height * 145.0));
	float oxides = texture(mineral_grain, UV * vec2(3.0, 1.0)).g;
	float ash = 0.50 + 0.26 * sin(angle * 2.0 + height * 3.0) + 0.13 * cos(angle * 3.0 - height * 5.0);
	float pool = smoothstep(.4,.82,ash + .14 * oxides) * smoothstep(.12,.43,height);
	float lip = smoothstep(.93,.997,height);
	vec3 slip = glaze.rgb * mix(vec3(1.06,.96,.80),vec3(.62,.78,.69),pool);
	slip *= 1.0 + throwing * shoulder * soft * .018;
	slip = mix(slip,bare_clay.rgb,lip*.22);
	ALBEDO = mix(bare_clay.rgb * (0.88 + 0.18*oxides), slip, glazed);
	ROUGHNESS = mix(0.91, 0.38 - .13 * pool + .035 * oxides + .025 * throwing * shoulder * soft, glazed);
	SPECULAR = mix(0.20, 0.58, glazed);
}
