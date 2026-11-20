shader_type spatial;

uniform vec4 lime : source_color = vec4(0.80, 0.76, 0.66, 1.0);
uniform sampler2D plaster_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D plaster_arm : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 surface_m;
varying float height_m;

float patch_value(vec2 cell) {
	vec3 h = fract(cell.xyx * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float patches(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(patch_value(cell), patch_value(cell + vec2(1, 0)), f.x),
			mix(patch_value(cell + vec2(0, 1)), patch_value(cell + vec2(1)), f.x), f.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = MODEL_NORMAL_MATRIX * NORMAL;
	surface_m = abs(n.y) > 0.7 ? world.xz : vec2(world.x + world.z, world.y);
	height_m = world.y;
}

void fragment() {
	vec2 uv = surface_m * 0.72;
	vec3 arm = texture(plaster_arm, uv).rgb;
	float broad = patches(surface_m * 0.85);
	float brush = patches(surface_m * vec2(4.0, 1.6));
	float dry = smoothstep(0.35, 1.7, height_m + 0.22 * broad);
	ALBEDO = lime.rgb * (0.77 + 0.125 * broad + 0.065 * brush + 0.08 * dry);
	ROUGHNESS = mix(0.81, 0.98, arm.g);
	AO = mix(0.85, 1.0, arm.r);
	NORMAL_MAP = texture(plaster_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.48;
}
