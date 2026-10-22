extends Node3D
## 标题背后的动态远景：雪夜，院门外。
## 全部用基本体拼：墙、门楼、灯笼、雪、街上的影子。不用任何贴图。
## 相机极慢地往前推，鼠标带一点点视差；灯笼会晃、火光会抖。

const K = preload("res://scripts/world/kit.gd")
const Figure = preload("res://scripts/world/figure.gd")

const GATE_Z := 0.0
const CAM_Z := 8.6
const LOOK := Vector3(0.0, 2.55, GATE_Z)

var cam: Camera3D
var _lamps: Array = []          # [灯体节点, 光源, 相位]
var _figs: Array = []           # 街上慢慢挪过去的影子
var _t := 0.0
var _parallax := Vector2.ZERO


func _ready() -> void:
	_sky()
	_ground()
	_wall()
	_lanterns()
	_snow()
	_shadows()
	_camera()


func _process(delta: float) -> void:
	_t += delta
	# 灯笼：轻轻摆，光跟着抖
	for row in _lamps:
		var node: Node3D = row[0]
		var light: OmniLight3D = row[1]
		var ph: float = row[2]
		node.rotation.z = sin(_t * 1.35 + ph) * 0.07
		node.rotation.x = cos(_t * 1.1 + ph) * 0.045
		light.light_energy = 1.25 + sin(_t * 7.3 + ph) * 0.10 + sin(_t * 2.1 + ph) * 0.06
	# 街上的影子：从左往右挪，出画了再从另一头进来
	for row in _figs:
		var fig: Node3D = row[0]
		var speed: float = row[1]
		fig.position.x += speed * delta
		if fig.position.x > 11.0:
			fig.position.x = -11.0
		fig.position.z = float(row[2]) + sin(_t * 0.6 + float(row[3])) * 0.25
	# 相机：极慢地推近 + 鼠标视差
	if cam != null:
		var target := Vector3(sin(_t * 0.11) * 0.22 + _parallax.x * 0.5,
			2.28 + sin(_t * 0.17) * 0.05 + _parallax.y * 0.18,
			CAM_Z - (1.0 - cos(_t * 0.07)) * 0.75)
		cam.position = cam.position.lerp(target, clampf(delta * 0.8, 0.0, 1.0))
		cam.look_at(LOOK + Vector3(_parallax.x * 0.35, _parallax.y * 0.12, 0.0))


## 鼠标位置（0..1），给一点点视差，别太抢。
func set_parallax(p: Vector2) -> void:
	_parallax = p - Vector2(0.5, 0.5)


# ---------- 搭景 ----------

func _sky() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#0a1220")
	sm.sky_horizon_color = Color("#1d2a3a")
	sm.ground_horizon_color = Color("#182130")
	sm.ground_bottom_color = Color("#0b1119")
	sm.sun_angle_max = 12.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#26364a")
	env.fog_density = 0.022
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# 月光：冷一点，从左上打下来
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("#a9c0e0")
	moon.light_energy = 0.9
	moon.rotation_degrees = Vector3(-38, 128, 0)
	add_child(moon)
	# 相机这一侧的补光：只为了让墙和雪有层次，不照亮远景
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#6f86a8")
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-16, -60, 0)
	add_child(fill)
	# 天上的月亮
	K.sphere(self, 1.9, K.mat(Color("#e6ecf5"), 0.55, 2.8), Vector3(-10.5, 14.5, -46.0))


func _ground() -> void:
	K.box(self, Vector3(70, 0.3, 70), Color("#dfe4ea"), Vector3(0, -0.15, 0))
	# 街心的雪被踩出一条脏痕
	K.box(self, Vector3(26, 0.06, 2.6), Color("#b9c0c8"), Vector3(0, 0.02, 5.4))
	for i in 9:
		var x := -12.0 + i * 3.0
		K.box(self, Vector3(1.6, 0.05, 1.1), Color("#c6ccd3"), Vector3(x + 0.4, 0.03, 5.2 + (i % 3) * 0.7))


func _wall() -> void:
	var stone := Color("#4a5158")
	var dark := Color("#2f343a")
	# 院墙：中间留出大门
	for side in [-1, 1]:
		var x: float = side * 5.9
		K.box(self, Vector3(10.0, 3.4, 0.5), stone, Vector3(x, 1.7, GATE_Z))
		K.prism(self, Vector3(10.4, 0.55, 1.1), dark, Vector3(x, 3.55, GATE_Z))
	# 门框与门扇
	K.box(self, Vector3(0.45, 3.9, 0.6), dark, Vector3(-1.55, 1.95, GATE_Z))
	K.box(self, Vector3(0.45, 3.9, 0.6), dark, Vector3(1.55, 1.95, GATE_Z))
	for side in [-1, 1]:
		K.box(self, Vector3(1.3, 3.4, 0.14), Color("#3b2f28"), Vector3(side * 0.82, 1.7, GATE_Z - 0.05))
	K.box(self, Vector3(0.1, 3.4, 0.2), Color("#6a5236"), Vector3(0, 1.7, GATE_Z - 0.12))
	# 门楼：屋檐压在门上
	K.prism(self, Vector3(5.6, 0.75, 2.3), dark, Vector3(0, 4.0, GATE_Z))
	K.box(self, Vector3(3.6, 0.28, 0.9), Color("#584a3d"), Vector3(0, 3.72, GATE_Z + 0.1))
	# 院里透出来的一点暖光：门缝里能看见有人在
	var inner := K.light(self, Color("#ffab5e"), 2.4, 8.5, Vector3(0.0, 2.1, GATE_Z - 1.6))
	inner.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	# 门前的石阶与石墩
	K.box(self, Vector3(3.4, 0.16, 1.1), Color("#9aa1a8"), Vector3(0, 0.08, GATE_Z + 1.0))
	for side in [-1, 1]:
		K.box(self, Vector3(0.5, 0.7, 0.5), Color("#8d949b"), Vector3(side * 2.1, 0.35, GATE_Z + 1.25))
	# 院内露出的屋顶一角，让画面后面有东西
	K.prism(self, Vector3(9.0, 2.2, 5.0), Color("#2b3036"), Vector3(0.5, 4.4, GATE_Z - 4.6))
	# 前景门洞：远一点、窄一点，只在四角压一压，别挡脸
	var near := Color("#0d1116")
	K.box(self, Vector3(1.1, 7.2, 0.6), near, Vector3(-4.9, 3.3, CAM_Z + 0.4))
	K.box(self, Vector3(1.1, 7.2, 0.6), near, Vector3(4.9, 3.3, CAM_Z + 0.4))
	K.box(self, Vector3(9.0, 1.05, 0.7), near, Vector3(0, 6.9, CAM_Z + 0.4))


func _lanterns() -> void:
	for side in [-1, 1]:
		var root := K.node(self, Vector3(side * 1.9, 3.5, GATE_Z + 0.55))
		K.box(root, Vector3(0.05, 0.75, 0.05), Color("#2a2e33"), Vector3(0, -0.35, 0))
		var body := K.sphere(root, 0.34, K.mat(Color("#c0392b"), 0.7, 1.9), Vector3(0, -0.78, 0), Vector3(1, 1.25, 1))
		K.cyl(root, 0.06, 0.06, 0.12, K.mat(Color("#b8893b"), 0.5), Vector3(0, -0.45, 0))
		K.cyl(root, 0.06, 0.06, 0.10, K.mat(Color("#b8893b"), 0.5), Vector3(0, -1.12, 0))
		var light := K.light(root, Color("#ff9b52"), 1.25, 7.5, Vector3(0, -0.78, 0))
		_lamps.append([root, light, float(side) * 1.7])


func _snow() -> void:
	var p := GPUParticles3D.new()
	p.amount = 1100
	p.lifetime = 10.0
	p.preprocess = 8.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.4, 9)
	pm.direction = Vector3(0.12, -1.0, 0.05)
	pm.spread = 6.0
	pm.initial_velocity_min = 1.1
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.25, -0.35, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.94, 0.96, 1.0, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 7.0, -1.0)
	add_child(p)


func _shadows() -> void:
	# 街那头的影子：离镜头远一点，只看得出是人形
	for row in [[-7.5, 0.5, 1.1, 0.0], [-3.6, 0.38, 2.3, 1.9], [3.4, 0.46, 0.7, 3.4]]:
		var fig: Node3D = Figure.new()
		add_child(fig)
		fig.setup("jiangshi")
		fig.hopping = true
		fig.speed_scale = 0.85
		fig.position = Vector3(float(row[0]), 0.0, float(row[2]))
		fig.face(Vector3(1, 0, 0), 1.0)
		_figs.append([fig, float(row[1]), float(row[2]), float(row[3])])


func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.position = Vector3(0.0, 2.3, CAM_Z)
	add_child(cam)
	cam.look_at(LOOK)
	cam.current = true
