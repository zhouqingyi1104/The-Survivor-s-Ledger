shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.60, 0.52, 0.42, 1.0);
uniform vec4 frost_color : source_color = vec4(0.81, 0.81, 0.76, 1.0);
uniform bool flagstone = false;
varying vec2 yard_pos;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), w.x),
			mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), w.x), w.y);
}

void vertex() {
	yard_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float broad = grain(yard_pos * 0.86);
	float fleck = grain(yard_pos * 9.5);
	float fine = grain(yard_pos * 38.0);
	vec3 bed = base_color.rgb * (0.77 + 0.30 * broad + 0.16 * fleck + 0.06 * fine);
	if (flagstone) {
		// Weathering follows the stone grain across each broad tread.
		float vein = grain(yard_pos * vec2(2.8, 13.0));
		ALBEDO = bed * (0.91 + 0.17 * vein);
		ROUGHNESS = 0.86;
	} else {
		// A little frost survives beside the plum tree, garden and shaded walls.
		float drift = max(1.0 - length((yard_pos - vec2(-7.5, 5.5)) / vec2(3.5, 2.0)),
				1.0 - length((yard_pos - vec2(5.0, 4.5)) / vec2(3.2, 2.4)));
		drift = max(drift, smoothstep(7.7, 10.0, abs(yard_pos.x)) * 0.80);
		float frost = smoothstep(0.47, 0.76, drift + (broad - 0.47) * 1.4 + (fleck - 0.5) * 0.35);
		ALBEDO = mix(bed, frost_color.rgb * (0.88 + fine * 0.15), frost * 0.88);
		ROUGHNESS = 0.98;
	}
}
