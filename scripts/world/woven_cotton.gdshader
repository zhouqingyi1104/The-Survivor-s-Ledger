shader_type spatial;

uniform sampler2D cover_print : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 linen : source_color = vec4(0.78, 0.70, 0.55, 1.0);

void fragment() {
	vec3 cover = texture(cover_print, UV).rgb;
	float pillow_seam = smoothstep(0.032, 0.052, min(UV.x, 1.0 - UV.x));
	ALBEDO = mix(linen.rgb * mix(0.73, 1.0, pillow_seam), cover, UV2.x);
	ROUGHNESS = 0.93;
	SPECULAR = 0.20;
}
