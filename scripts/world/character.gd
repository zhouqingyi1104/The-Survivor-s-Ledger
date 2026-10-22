extends Node3D
## 人物：Quaternius 人形骨骼模型（CC0）+ 自制的衣色、冠帽、黄符、灯笼，动画用同一副骨骼的动画库（CC0）。
## 接口和旧的 figure.gd 一样：moving / working / lying / hopping / fall() / face()，换进来不用改别处。
## 衣服是 Blender 里从身体网格派生的（见 tools 里的 bl_dress.py），材质名 Robe / Pants / Shoes 可以按身份改色。

const K = preload("res://scripts/world/kit.gd")

const BODIES := {
	"male_short": "res://assets/models/characters/male_short.glb",
	"male_long": "res://assets/models/characters/male_long.glb",
	"female_short": "res://assets/models/characters/female_short.glb",
	"female_long": "res://assets/models/characters/female_long.glb",
}
const ANIM_LIB := "res://assets/third_party/quaternius/ual/UAL1_Standard.glb"
## 动作原速时的步速（米/秒，tests/anim_speed.gd 量的）。按实际速度挑走 / 慢跑 / 快跑，再按比例调播放速度，脚不打滑。
const WALK_SPEED := 1.0
const JOG_SPEED := 3.4
const SPRINT_SPEED := 4.8

## 身份 → 体型、衣色、冠帽、走路 / 待机动作
const LOOKS := {
	"scholar":   {"body": "male_long",   "robe": Color("#5d7286"), "pants": Color("#2b2f36"), "hat": "scholar",   "walk": "Walk_Formal"},
	"escort":    {"body": "male_short",  "robe": Color("#3b3430"), "pants": Color("#22201e"), "hat": "escort"},
	"herbalist": {"body": "female_long", "robe": Color("#56735a"), "pants": Color("#2f3a30"), "hat": ""},
	"watchman":  {"body": "male_short",  "robe": Color("#6e5c40"), "pants": Color("#3a3226"), "hat": "watchman",  "idle": "Idle_Torch"},
	"jiangshi":  {"body": "male_long",   "robe": Color("#1f2c44"), "pants": Color("#161b26"), "hat": "jiangshi",  "skin": Color("#a3b59b"), "idle": "A_TPose"},
	"villager":  {"body": "male_short",  "robe": Color("#7a6a55"), "pants": Color("#3b342c"), "hat": "villager"},
	"villager_f": {"body": "female_short", "robe": Color("#8a5a4a"), "pants": Color("#3b342c"), "hat": ""},
}

static var _scenes := {}
static var _lib: AnimationLibrary

var kind := "villager"
var moving := false
var hopping := false
var working := false
var lying := false
var speed_scale := 1.0
## 实际移动速度（米/秒）。不设（< 0）就按每帧位置变化自己量。
var move_speed := -1.0
## 主角用：被墙、屋顶挡住时透出剪影。要在 setup() 之前设。
var xray := false
## 脚步声（step_stone / step_wood / step_snow），空串不出声。每半个走路循环（一步）响一下
var step_sound := ""
## 干活时放哪个动作（Interact / Fixing_Kneeling / Crouch_Idle / Sitting_Idle / Spell_Simple_Idle）
var work_anim := "Interact"
var lantern_light: OmniLight3D

var _look: Dictionary
var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _cur := ""
var _t := 0.0
var _fallen := false
var _last_pos := Vector3.INF
var _measured := 0.0
var _step_phase := -1


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _anim_library() -> AnimationLibrary:
	if _lib == null:
		var n: Node = _scene(ANIM_LIB).instantiate()
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		_lib = ap.get_animation_library("")
		n.free()
	return _lib


func setup(k: String, robe := Color(0, 0, 0, 0)) -> Node3D:
	kind = k
	_t = randf() * 10.0
	_look = LOOKS.get(k, LOOKS.villager).duplicate()
	if robe.a > 0:
		_look.robe = robe
		if k == "villager" and robe.r > robe.b + 0.15:
			_look.body = "female_short"
			_look.hat = ""
	_model = _scene(BODIES[_look.body]).instantiate()
	add_child(_model)
	_skel = _model.find_child("Skeleton3D", true, false)
	_dress()
	_ap = AnimationPlayer.new()
	_model.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("", _anim_library())
	_accessories()
	if xray:
		_enable_xray()
	if kind == "jiangshi":
		var arms := ArmsForward.new()
		_skel.add_child(arms)
	_play(_look.get("idle", "Idle"), 0.0)
	_ap.seek(randf() * 1.0, true)
	return self


## 衣服、鞋按身份上色；僵尸的皮肤发青。
func _dress() -> void:
	for mi in _skel.find_children("*", "MeshInstance3D", false, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else ""
			match mname:
				"Robe":
					m.set_surface_override_material(s, _cloth(_look.robe))
				"Pants":
					m.set_surface_override_material(s, _cloth(_look.pants))
				"Shoes":
					m.set_surface_override_material(s, _cloth(Color("#1c1816")))
				_:
					if _look.has("skin") and m.name == "Body" and mat is StandardMaterial3D:
						var skin: StandardMaterial3D = mat.duplicate()
						skin.albedo_color = _look.skin
						m.set_surface_override_material(s, skin)


static func _cloth(c: Color) -> StandardMaterial3D:
	var key := "cloth|" + c.to_html()
	if K._mats.has(key):
		return K._mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	K._mats[key] = m
	return m


func _bone_node(bone: String) -> BoneAttachment3D:
	var b := BoneAttachment3D.new()
	b.bone_name = bone
	_skel.add_child(b)
	return b


## 冠帽、黄符、灯笼：挂在头骨 / 手骨上。头骨原点在后脑勺下沿，头顶约在 +0.24。
func _accessories() -> void:
	var head := _bone_node("Head")
	var top := Vector3(0, 0.235, 0.015)
	match _look.get("hat", ""):
		"scholar":
			K.box(head, Vector3(0.21, 0.12, 0.22), K.ROOF_EDGE, top + Vector3(0, 0.02, -0.01))
			for sx in [-1, 1]:
				K.box(head, Vector3(0.03, 0.24, 0.012), K.ROOF_EDGE, Vector3(sx * 0.045, 0.1, -0.12), Vector3(10, 0, 0))
		"escort":
			K.cyl(head, 0.112, 0.112, 0.05, K.CINNABAR, top + Vector3(0, -0.06, 0))
			K.sphere(head, 0.055, K.ROOF_EDGE, top + Vector3(0, 0.02, -0.03))
		"watchman":
			K.cyl(head, 0.02, 0.34, 0.15, Color("#b89a5e"), top + Vector3(0, 0.03, 0), Vector3.ZERO, 16)
			var hand := _bone_node("hand_r")
			var lan := K.node(hand, Vector3(0, 0.12, 0.05))
			K.sphere(lan, 0.09, K.mat(Color("#ff8a4a"), 0.5, 2.5), Vector3(0, -0.05, 0), Vector3(1, 1.3, 1))
			lantern_light = K.light(lan, Color("#ffae6b"), 1.2, 6.0, Vector3(0, -0.05, 0))
		"jiangshi":
			K.cyl(head, 0.13, 0.15, 0.12, K.ROOF_EDGE, top + Vector3(0, 0.03, 0), Vector3.ZERO, 16)
			K.cyl(head, 0.2, 0.2, 0.03, K.ROOF_EDGE, top + Vector3(0, -0.03, 0), Vector3.ZERO, 16)
			K.sphere(head, 0.04, K.CINNABAR, top + Vector3(0, 0.12, 0))
			var tal := K.box(head, Vector3(0.09, 0.2, 0.008), K.mat(K.PAPER, 0.8, 0.4), Vector3(0, 0.12, 0.125))
			tal.rotation_degrees.x = -12
			K.box(head, Vector3(0.016, 0.13, 0.01), K.CINNABAR, Vector3(0, 0.12, 0.13))
			var chest := _bone_node("spine_03")
			K.box(chest, Vector3(0.2, 0.2, 0.015), K.mat(K.GOLD, 0.5), Vector3(0, 0.05, 0.16))
		"villager":
			K.sphere(head, 0.05, K.ROOF_EDGE, top + Vector3(0, 0.0, -0.035))


## 材质的模板缓冲 X 光模式：挡住的部分画成淡金色剪影。材质复制一份，别的人不受影响。
func _enable_xray() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.material_override is BaseMaterial3D:
			mi.material_override = _xray_mat(mi.material_override)
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is BaseMaterial3D:
				mi.set_surface_override_material(s, _xray_mat(mat))


static func _xray_mat(mat: BaseMaterial3D) -> BaseMaterial3D:
	var m: BaseMaterial3D = mat.duplicate()
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	m.stencil_color = Color(1.0, 0.86, 0.55, 0.5)
	return m


func _play(anim: String, blend := 0.2) -> void:
	if anim == _cur or _ap == null:
		return
	if not _ap.has_animation(anim):
		anim = "Idle"
	_cur = anim
	_ap.play(anim, blend)


func _process(delta: float) -> void:
	if _ap == null or _fallen:
		return
	_t += delta * speed_scale
	_ap.speed_scale = speed_scale
	_measure(delta)
	if lying:
		_model.rotation_degrees.x = lerpf(_model.rotation_degrees.x, -90.0, delta * 6.0)
		_model.position.y = lerpf(_model.position.y, 0.62, delta * 6.0)
		_play("Idle")
		return
	_model.rotation_degrees.x = lerpf(_model.rotation_degrees.x, 0.0, delta * 8.0)
	if hopping:
		var ph := fmod(_t * 2.2, 1.0)
		_model.position.y = sin(ph * PI) * 0.32
		_play(_look.get("idle", "Idle"))
		return
	_model.position.y = lerpf(_model.position.y, 0.0, delta * 10.0)
	if moving:
		var gait := _gait(move_speed if move_speed >= 0.0 else _measured)
		_play(gait[0])
		_ap.speed_scale = gait[1]
		_footstep()
	elif working:
		_play(work_anim)
	else:
		_play(_look.get("idle", "Idle"))


func _footstep() -> void:
	if step_sound == "" or _ap.current_animation_length <= 0.0:
		return
	var phase := int(_ap.current_animation_position / (_ap.current_animation_length / 2.0))
	if phase != _step_phase:
		_step_phase = phase
		Sfx.play(step_sound, -9.0, 0.08)


func _measure(delta: float) -> void:
	var pos := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var v := minf(Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta, 20.0)
		_measured = lerpf(_measured, v, 1.0 - exp(-delta * 8.0))
	_last_pos = pos


## [动作, 播放速度]
func _gait(v: float) -> Array:
	if v < 1.9:
		return [_look.get("walk", "Walk"), clampf(v / WALK_SPEED, 0.6, 1.9)]
	if v < 4.2:
		return ["Jog_Fwd", clampf(v / JOG_SPEED, 0.6, 1.3)]
	return ["Sprint", clampf(v / SPRINT_SPEED, 0.7, 2.4)]


## 倒地。
func fall() -> void:
	hopping = false
	moving = false
	_fallen = true
	_model.position.y = 0.0
	_ap.speed_scale = 1.0
	_cur = "Death01"
	_ap.play("Death01", 0.1)


func face(dir: Vector3, weight := 1.0) -> void:
	if dir.length() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), weight)


## 僵尸：动画之后再把两臂掰成平举向前（骨骼的 +Y 是骨头朝向）。
class ArmsForward extends SkeletonModifier3D:
	const BONES := ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]
	const TARGET := Vector3(0.0, -0.08, 1.0)

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var target := TARGET.normalized()
		for bone_name in BONES:
			var i := sk.find_bone(bone_name)
			if i < 0:
				continue
			var parent := sk.get_bone_parent(i)
			var pg := sk.get_bone_global_pose(parent)
			var cur := pg * sk.get_bone_pose(i)
			var dir := cur.basis.y.normalized()
			var q := Quaternion(dir, target)
			var new_basis := Basis(q) * cur.basis
			var local := pg.basis.inverse() * new_basis
			sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())
