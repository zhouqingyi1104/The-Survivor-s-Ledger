shader_type spatial;
render_mode cull_disabled, shadows_disabled;

float pigment(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	vec4 corners = fract(sin(dot(cell,vec2(55.71,87.39)) + vec4(0.0,55.71,87.39,143.10)) * 37181.53);
	return mix(mix(corners.x, corners.y, f.x), mix(corners.z, corners.w, f.x), f.y);
}

void fragment() {
	float spread = pigment(UV * vec2(18.0,7.0));
	float grit = pigment(UV * vec2(97.0,23.0));
	vec2 p = (UV - 0.5) * 2.0;
	float edge = pow(abs(p.x), 4.0) + pow(abs(p.y + 0.11*sin(5.0*p.x)), 1.5);
	float stain = 1.0 - smoothstep(0.42, 1.02, edge + 0.54 * spread);
	ALBEDO = mix(vec3(0.052,0.016,0.009),vec3(0.132,0.038,0.019),spread);
	ROUGHNESS = 0.78 + 0.18 * grit;
	ALPHA = stain * (0.47 + 0.43*grit);
}
