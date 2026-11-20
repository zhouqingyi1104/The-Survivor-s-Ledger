shader_type spatial;

uniform sampler2D surface_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_arm : repeat_enable, filter_linear_mipmap;
uniform sampler2D snow_color : source_color, repeat_enable, filter_linear_mipmap;
uniform bool flagstone = false;
uniform bool courtyard = true;
varying vec2 yard_pos;
varying vec2 scan_offset;

void vertex() {
	yard_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float stone_id = floor(COLOR.a * 255.0 + 0.5);
	scan_offset = fract(stone_id * vec2(0.61803, 0.41421));
}

void fragment() {
	vec2 uv = yard_pos / (flagstone ? 2.8 : 2.1);
	if (flagstone) {
		uv += scan_offset;
	}
	vec3 scan = texture(surface_color, uv).rgb;
	vec2 relief = texture(surface_normal, uv).rg * 2.0 - 1.0;
	vec2 arm = texture(surface_arm, uv).rg;
	float value = dot(scan, vec3(0.2126, 0.7152, 0.0722));
	float wet = courtyard ? 1.0 - smoothstep(0.8, 2.0, distance(yard_pos, vec2(-3.0, 1.5))) : 0.0;
	float strength;
	if (flagstone) {
		// Hewn faces keep their mineral veins. Passing feet polish the crest of the stone.
		float polish = 1.0 - smoothstep(0.25, 1.25, abs(yard_pos.x));
		ALBEDO = mix(vec3(value), scan, 0.09) * vec3(1.31, 1.48, 1.50) * COLOR.rgb * (1.0 - 0.31 * wet);
		ROUGHNESS = clamp(0.39 + 0.46 * arm.g - 0.13 * polish - 0.28 * wet, 0.23, 0.95);
		strength = 0.34;
	} else {
		// Frost remains in the lee of the trees and walls. The ground under the winch stays damp.
		float drift = max(1.0 - length((yard_pos - vec2(-7.5, 5.5)) / vec2(3.4, 2.1)),
				1.0 - length((yard_pos - vec2(6.2, 4.8)) / vec2(3.6, 2.2)));
		drift = max(drift, 0.68 * smoothstep(7.4, 9.9, abs(yard_pos.x)));
		float patches = texture(surface_color, uv * 0.43 + 0.31).r;
		float frost = smoothstep(0.20, 0.68, drift + 0.95 * patches + value * 0.40 - 0.26);
		vec3 soil = mix(vec3(value), scan, 0.51) * vec3(1.15, 1.08, 1.01);
		soil = mix(soil, vec3(0.155, 0.116, 0.082), 0.20);
		vec3 snow = texture(snow_color, yard_pos / 4.7).rgb * vec3(0.94, 1.02, 1.09);
		ALBEDO = mix(soil * (1.0 - 0.24 * wet), snow, frost);
		ROUGHNESS = mix(0.72 + 0.27 * arm.g - 0.17 * wet, 0.96, frost);
		strength = mix(0.52, 0.08, frost);
	}
	// The scan is projected along world XZ, including on the merged and rotated treads.
	vec3 up = VIEW_MATRIX[1].xyz;
	float top = max(0.0, dot(NORMAL, up));
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(relief.x, 0.0, -relief.y) * strength * top);
	AO = mix(1.0, arm.r, 0.5);
}
