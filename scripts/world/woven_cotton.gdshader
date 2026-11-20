shader_type spatial;

uniform vec4 indigo : source_color = vec4(0.235, 0.35, 0.39, 1.0);
uniform vec4 thread : source_color = vec4(0.70, 0.72, 0.64, 1.0);
uniform vec4 linen : source_color = vec4(0.78, 0.70, 0.55, 1.0);

// A printed lozenge repeat remains readable from the courtyard. Fine yarn
// fades with distance so the two weave directions never shimmer in motion.
float repeat_line(float coord, float half_width) {
	float aa = max(fwidth(coord), 0.001);
	float d = abs(fract(coord + 0.5) - 0.5);
	return (1.0 - smoothstep(half_width, half_width + aa, d)) * (1.0 - smoothstep(0.18, 0.5, aa));
}

void fragment() {
	vec2 p = UV;
	vec2 lattice = p * vec2(5.0, 3.3);
	float print_mark = repeat_line(lattice.x + lattice.y, 0.033) * repeat_line(lattice.x - lattice.y, 0.17)
		+ repeat_line(lattice.x - lattice.y, 0.033) * repeat_line(lattice.x + lattice.y, 0.17);
	float hem = smoothstep(0.095, 0.107, p.x + 0.012 * sin(6.28 * p.y));
	float stripe = repeat_line((p.x - 0.82) * 15.0, 0.052) * smoothstep(0.74, 0.76, p.x) * (1.0 - smoothstep(0.89, 0.92, p.x));
	float weave = repeat_line(p.x * 132.0, 0.13) + repeat_line(p.y * 92.0, 0.12);
	vec3 cover = mix(indigo.rgb, thread.rgb, clamp(0.42 * print_mark + 0.74 * stripe, 0.0, 1.0));
	vec3 fabric = mix(linen.rgb * 0.86, cover, hem);
	float pillow_seam = smoothstep(0.032, 0.052, min(p.x, 1.0 - p.x));
	fabric = mix(linen.rgb * mix(0.73, 1.0, pillow_seam), fabric, UV2.x);
	ALBEDO = fabric * (0.96 + 0.04 * weave);
	ROUGHNESS = 0.93;
	SPECULAR = 0.20;
}
