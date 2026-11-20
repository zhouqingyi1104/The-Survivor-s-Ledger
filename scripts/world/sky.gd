extends RefCounted
## 天光：天空、日月光、雾、环境光、下雪。晨 / 午 / 暮 / 夜四档，备劫时按时辰插值。

static var _snowflake: GradientTexture2D

const PRESETS := {
	"dawn":  {"elev": 18.0, "az": 70.0,  "sun": Color(1.0, 0.82, 0.66), "energy": 0.95, "top": Color("#8ea4bb"), "horizon": Color("#e9d3bb"), "ambient": Color("#b9b2a8"), "amb_e": 0.38, "fog": Color("#d9d2c7"), "fog_d": 0.010},
	"noon":  {"elev": 52.0, "az": 15.0,  "sun": Color(1.0, 0.97, 0.92), "energy": 1.05, "top": Color("#86a6c4"), "horizon": Color("#dfe4e6"), "ambient": Color("#c4c8cc"), "amb_e": 0.4, "fog": Color("#dfe3e5"), "fog_d": 0.008},
	"dusk":  {"elev": 10.0, "az": -70.0, "sun": Color(1.0, 0.58, 0.32), "energy": 0.9, "top": Color("#4f5e7e"), "horizon": Color("#e09a62"), "ambient": Color("#a08a84"), "amb_e": 0.32, "fog": Color("#c99c80"), "fog_d": 0.012},
	"night": {"elev": 42.0, "az": 30.0,  "sun": Color(0.55, 0.66, 0.92), "energy": 0.32, "top": Color("#070b16"), "horizon": Color("#1b2436"), "ambient": Color("#3a4766"), "amb_e": 0.32, "fog": Color("#141a26"), "fog_d": 0.018},
	"blood": {"elev": 30.0, "az": 30.0,  "sun": Color(0.95, 0.3, 0.25), "energy": 0.45, "top": Color("#1a0606"), "horizon": Color("#4a1414"), "ambient": Color("#5a2a2a"), "amb_e": 0.35, "fog": Color("#2a0d0d"), "fog_d": 0.02},
	"ruin":  {"elev": 25.0, "az": 40.0,  "sun": Color(0.6, 0.62, 0.7), "energy": 0.12, "top": Color("#20242c"), "horizon": Color("#2e333b"), "ambient": Color("#4a4e57"), "amb_e": 0.42, "fog": Color("#1c1f24"), "fog_d": 0.025},
}


## 建好天空、光、雾、雪，挂在 parent 下。返回句柄字典。
static func make(parent: Node3D, snow_extent := 24.0, residential := false) -> Dictionary:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_sky_affect = 0.4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	if residential:
		# 檐下保留天空的冷色反射，短半径接触阴影勾出柱脚和器物的落点。
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ssao_radius = 0.72
		env.ssao_intensity = 2.0
		env.ssao_light_affect = 0.23
		env.glow_bloom = 0.0
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	if residential:
		sun.shadow_blur = 1.45
		sun.directional_shadow_blend_splits = true
	parent.add_child(sun)

	var snow := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(snow_extent, 0.5, snow_extent)
	pm.direction = Vector3(0.2, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0.25, -0.5, 0)
	snow.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.albedo_color = Color(1, 1, 1, 0.9)
	if residential:
		if _snowflake == null:
			var falloff := Gradient.new()
			falloff.offsets = PackedFloat32Array([0.0, 0.32, 0.72, 1.0])
			falloff.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.79), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.0)])
			_snowflake = GradientTexture2D.new()
			_snowflake.width = 32
			_snowflake.height = 32
			_snowflake.gradient = falloff
			_snowflake.fill = GradientTexture2D.FILL_RADIAL
			_snowflake.fill_from = Vector2(0.5, 0.5)
			_snowflake.fill_to = Vector2(0.5, 0)
		flake.albedo_texture = _snowflake
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 贴着镜头的雪片会变成大白块，近处淡掉
	flake.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	flake.distance_fade_min_distance = 2.0
	flake.distance_fade_max_distance = 6.0
	quad.material = flake
	snow.draw_pass_1 = quad
	snow.lifetime = 9.0
	snow.preprocess = 9.0
	snow.position = Vector3(0, 14, 0)
	snow.visibility_aabb = AABB(Vector3(-snow_extent - 5, -20, -snow_extent - 5), Vector3(snow_extent * 2 + 10, 25, snow_extent * 2 + 10))
	parent.add_child(snow)
	return {"env": env, "sky": sky_mat, "sun": sun, "snow": snow, "residential": residential}


static func apply(h: Dictionary, preset: String, snow_amount := 0) -> void:
	set_values(h, PRESETS[preset])
	_set_snow(h, snow_amount)


## 两档之间插值（备劫时按时辰走）。
static func blend(h: Dictionary, a: String, b: String, t: float, snow_amount := 0) -> void:
	var pa: Dictionary = PRESETS[a]
	var pb: Dictionary = PRESETS[b]
	var v := {}
	for k in pa:
		v[k] = lerp(pa[k], pb[k], t)
	set_values(h, v)
	_set_snow(h, snow_amount)


## 改粒子数量会让整场雪重新开始下，所以只在真变了的时候改。
static func _set_snow(h: Dictionary, snow_amount: int) -> void:
	var snow: GPUParticles3D = h.snow
	if snow.amount != maxi(1, snow_amount):
		snow.amount = maxi(1, snow_amount)
	if snow.emitting != (snow_amount > 0):
		snow.emitting = snow_amount > 0


static func set_values(h: Dictionary, p: Dictionary) -> void:
	var sun: DirectionalLight3D = h.sun
	# 冬日的阳光从侧面落到院中，给木梁、石面和瓦口留下可读的阴面。夜景沿用月光。
	var daylight := smoothstep(0.50, 0.95, float(p.energy)) if h.get("residential", false) else 0.0
	sun.rotation_degrees = Vector3(-float(p.elev) + 6.0 * daylight, float(p.az) - 66.0 * daylight, 0)
	sun.light_color = Color(p.sun).lerp(Color("#ffe5c6"), 0.22 * daylight)
	sun.light_energy = p.energy
	var sky: ProceduralSkyMaterial = h.sky
	sky.sky_top_color = p.top
	sky.sky_horizon_color = p.horizon
	sky.ground_horizon_color = p.horizon
	sky.ground_bottom_color = Color(p.top).darkened(0.4)
	var env: Environment = h.env
	env.ambient_light_color = Color(p.ambient).lerp(Color("#aabccd"), 0.37 * daylight)
	env.ambient_light_energy = float(p.amb_e) * (1.0 - 0.15 * daylight)
	env.fog_light_color = p.fog
	env.fog_density = float(p.fog_d) * float(h.get("fog_mul", 1.0))
