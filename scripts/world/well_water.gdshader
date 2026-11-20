shader_type spatial;

varying vec2 surface_pos;
void vertex() {
	surface_pos = VERTEX.xz;
}

void fragment() {
	// Small returning wave around the suspended pail; the rim shades the water at its edge.
	vec2 delta = surface_pos - vec2(0.10, 0.055);
	float r = max(length(delta), 0.001);
	float ripple = cos(51.0 * r - TIME * 1.65) * exp(-r * 4.5);
	float resolved = 1.0 - smoothstep(1.0, 3.0, fwidth(r) * 51.0);
	vec2 slope = delta / r * ripple * resolved * 0.068;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(slope.x, 0.0, slope.y));
	float edge = 1.0 - smoothstep(0.29, 0.54, length(surface_pos));
	ALBEDO = mix(vec3(0.015, 0.030, 0.029), vec3(0.034, 0.081, 0.075), edge) * (1.0 + 0.10 * ripple * resolved);
	ROUGHNESS = 0.14;
	SPECULAR = 0.64;
}
