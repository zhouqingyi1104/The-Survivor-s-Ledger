shader_type spatial;

varying float wall_x;
uniform float triptych_panel = -1.0;
void vertex() {
	wall_x = (MODEL_MATRIX * vec4(VERTEX, 1.0)).x;
}

// A vertical handscroll: distant washes disappear into mist at the base,
// darker folded rock catches dry-brush marks, and pines mark the near bank.
float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 h = fract(sin(dot(i, vec2(32.13, 71.19)) + vec4(0,32.13,71.19,103.32)) * 4375.49);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}

float ridge(float x, float off) {
	return 0.45 * grain(vec2(x * 3.5, off)) + 0.37 * grain(vec2(x * 8.0, off + 2.0))
		+ 0.13 * grain(vec2(x * 19.0, off)) + 0.05 * grain(vec2(x * 57.0, off + 1.5));
}

float wash(vec2 p, float top, float depth) {
	float d = top - p.y;
	return smoothstep(-0.004, 0.006, d) * (1.0 - smoothstep(0.012, depth, d));
}

float pine(vec2 p) {
	float trunk = 1.0 - smoothstep(0.012, 0.030, abs(p.x - 0.046 * sin(3.8 * p.y)));
	float needles = 0.0;
	for (int i = 0; i < 5; i++) {
		float h = 0.28 + 0.14 * float(i);
		float span = (1.0 - h) * 0.52;
		float skew = p.x * (mod(float(i), 2.0) - 0.36);
		float canopy = h - 0.33 * abs(p.x) + 0.12 * skew + 0.026 * cos(p.x * 38.0);
		needles = max(needles, (1.0 - smoothstep(0.013, 0.062, abs(p.y - canopy)))
			* (1.0 - smoothstep(span * 0.59, span, abs(p.x))));
	}
	return max(trunk, needles) * smoothstep(-0.01, 0.02, p.y) * (1.0 - smoothstep(0.84, 0.93, p.y));
}

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y);
	float phase = 0.0;
	if (triptych_panel >= 0.0) {
		p.x = (p.x + triptych_panel) / 3.0;
	} else if (wall_x < 0.0) {
		p.x = 1.0 - p.x;
		phase = 0.72;
	}
	float far = 0.48 + 0.37 * ridge(p.x + phase, 2.8);
	float mid = 0.31 + 0.51 * ridge(p.x + phase, 9.3);
	float near = 0.17 + 0.26 * ridge(p.x + phase, 14.8);
	float bank = 0.066 + 0.14 * ridge(p.x + phase, 25.3);
	float paper = grain(p * vec2(154.0, 319.0));
	float dry = grain(vec2(p.x * 19.0 + 7.5 * p.y, p.y * 10.0)) * 0.69 + paper * 0.31;
	float ink = 0.27 * wash(p, far, 0.24);
	ink = max(ink, (0.28 + 0.43 * dry) * wash(p, mid, 0.27));
	ink = max(ink, (0.43 + 0.44 * dry) * wash(p, near, 0.17));
	ink = max(ink, (0.58 + 0.29 * dry) * wash(p, bank, 0.075));
	for (int i = 0; i < 4; i++) {
		float x = 0.16 + 0.072 * float(i);
		float y = 0.062 + 0.14 * ridge(x + phase, 25.3);
		ink = max(ink, pine((p - vec2(x,y)) / vec2(0.27, 0.135 - 0.014 * float(i))) * 0.85);
	}
	vec3 color = mix(vec3(0.70, 0.62, 0.46), vec3(0.046, 0.058, 0.050), ink) * (0.96 + 0.06 * paper);
	vec2 stamp = abs((p - vec2(0.81,0.14)) / vec2(0.029,0.016));
	float seal = (1.0 - smoothstep(0.86, 1.06, max(stamp.x, stamp.y))) * (0.49 + 0.40 * paper);
	ALBEDO = mix(color, vec3(0.33,0.082,0.035), seal);
	ROUGHNESS = 0.97;
	SPECULAR = 0.13;
}
