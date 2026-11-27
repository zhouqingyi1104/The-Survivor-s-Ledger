shader_type spatial;
render_mode specular_schlick_ggx;

varying vec2 bank_pos;

void vertex() {
	bank_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Fade a wave before its crests occupy less than two screen pixels.
float wave(float phase) {
	return sin(phase) * (1.0 - smoothstep(1.2, 3.14, fwidth(phase)));
}

void fragment() {
	vec2 p = bank_pos;
	float bank = smoothstep(1.55, 3.10, abs(p.y - 5.0));
	float current = 0.64 * sin(p.x * 0.39 + p.y * 0.56 - TIME * 0.21)
		+ 0.36 * sin(p.x * 0.20 - p.y * 0.83 + TIME * 0.13);
	float lee = smoothstep(-0.50, 0.68, current);
	float swell = wave(p.x * 1.47 + p.y * 1.06 + 1.75 * current - TIME * 0.79);
	float riffle = wave(p.x * 4.49 - p.y * 2.20 + 2.50 * current - TIME * 1.04);
	float cross = wave(p.x * 0.52 + p.y * 5.58 + 1.12 * swell + TIME * 0.76);
	vec2 tilt = vec2(0.065 * swell + lee * 0.045 * riffle, 0.030 * swell + lee * 0.030 * cross);
	tilt *= mix(1.0, 0.54, bank);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(tilt.x, 0.0, tilt.y));
	ALBEDO = mix(vec3(0.032, 0.071, 0.078), vec3(0.084, 0.108, 0.094), bank)
		* (0.97 + 0.05 * current);
	ROUGHNESS = 0.30 + bank * 0.09 - lee * 0.04;
	SPECULAR = 0.66;
}
