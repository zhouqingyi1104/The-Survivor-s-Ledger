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
	# 413games 的两套女身（CC0，见 assets/third_party/413games/NOTICE.txt）：女儿节的女仆和戴尖帽的月
	"maid": "res://assets/third_party/413games/base-motion-v7.glb",
	"moon": "res://assets/third_party/413games/moon-motion-v7.glb",
}
const ANIM_LIB := "res://assets/third_party/quaternius/ual/UAL1_Standard.glb"

## 两套骨骼：Quaternius 那套骨头叫 Head / spine_03 / pelvis，动作取 UAL 动画库；
## 413games 那套是 Mixamo 骨头（冒号被 Godot 换成下划线），模型自带 Camp_ 动作。
## top_bone 有的话用来量头顶，省得手调 head_top；own_hair / own_dress 是说模型自己有头发和衣饰，别再往上堆。
const RIGS := {
	"q": {"head": "Head", "chest": "spine_03", "hips": "pelvis", "hand_l": "hand_l", "hand_r": "hand_r",
		"top_bone": "", "head_top": 0.235, "scale": 1.0, "own_hair": false, "own_dress": false,
		"idle": "Idle", "walk": "Walk", "jog": "Jog_Fwd", "sprint": "Sprint", "work": "Interact", "death": "Death01"},
	"m": {"head": "mixamorig_Head", "chest": "mixamorig_Spine2", "hips": "mixamorig_Hips",
		"hand_l": "mixamorig_LeftHand", "hand_r": "mixamorig_RightHand",
		"top_bone": "", "head_top": 0.14, "scale": 0.92, "own_hair": true, "own_dress": true,
		"idle": "Camp_Idle", "walk": "Camp_Walk", "jog": "Camp_Walk", "sprint": "Camp_Walk",
		"work": "Camp_Wave", "death": "Camp_Idle"},
}
## 体型 → 骨骼
const BODY_RIG := {
	"male_short": "q", "male_long": "q", "female_short": "q", "female_long": "q",
	"maid": "m", "moon": "m",
}
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

## 主角（hero）：一律换成女身，加「仙气」这一套装束——披帛、腰绦、步摇、灵光，衣料改丝绸。
## moon = 戴尖帽那一套（仙气），maid = 女仆那一套，想换直接改这一个值。
const HERO_BODY := "moon"

## 仙气配色：月白的衣、青灰的绦、墨黑的发、冷白的光。身份色只用来染一点，别盖过去。
const FAIRY_ROBE := Color("#eef1f4")
const FAIRY_SASH := Color("#b9d6e2")
const FAIRY_HAIR := Color("#241f27")
const FAIRY_GLOW := Color("#cfeaff")

static var _scenes := {}
static var _lib: AnimationLibrary

var kind := "villager"
## 主角用：换女身、上仙气装束。要在 setup() 之前设。
var hero := false
## 开发 / 出图用：直接指定体型（maid / moon 等），不看身份。
var force_body := ""
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
var _rig: Dictionary
var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _cur := ""
var _t := 0.0
var _fallen := false
var _last_pos := Vector3.INF
var _measured := 0.0
var _step_phase := -1
## 仙气装束的活件，每帧要动
var _ribbons: Array = []
var _dangles: Array = []
var _motes: Node3D
## [BoneAttachment3D, 容器]：等着把缩放配回去的挂点
var _fixes: Array = []


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
	if hero:
		_hero_look()
	_rig = RIGS[BODY_RIG.get(_look.body, "q")]
	_model = _scene(BODIES[_look.body]).instantiate()
	_model.scale = Vector3.ONE * float(_rig.scale)
	add_child(_model)
	_skel = _model.find_child("Skeleton3D", true, false)
	# 女仆 / 月那两套模型里夹着一本读书动作用的书，平时藏起来
	var extra: Node3D = _model.find_child("ReadingBook", true, false)
	if extra != null:
		extra.visible = false
	_dress()
	_ap = _model.find_child("AnimationPlayer", true, false)
	if _ap == null:
		_ap = AnimationPlayer.new()
		_model.add_child(_ap)
		_ap.root_node = NodePath("..")
		_ap.add_animation_library("", _anim_library())
	_look.idle = _pick(str(_look.get("idle", "")), "idle")
	_look.walk = _pick(str(_look.get("walk", "")), "walk")
	_accessories()
	if xray:
		_enable_xray()
	if hero:
		_fairy_wear()
	if kind == "jiangshi":
		var arms := ArmsForward.new()
		_skel.add_child(arms)
	_play(_look.get("idle", "Idle"), 0.0)
	_ap.seek(randf() * 1.0, true)
	return self


## 主角：换成女身，身份色往月白里提一提，走路用端正的步子。冠帽照旧，身份还认得出。
func _hero_look() -> void:
	_look.fairy = true
	_look.body = force_body if force_body != "" else HERO_BODY
	_look.walk = "Walk_Formal"
	if _look.get("idle", "Idle") == "Idle_Torch":
		_look.idle = "Idle"
	if BODY_RIG.get(_look.body, "q") == "m":
		# 自带发型、尖帽和衣饰，冠帽、发髻、束腰都不用再堆
		_look.hat = ""
		return
	_look.hair = FAIRY_HAIR
	_look.skin = Color("#f2dbc6")
	_look.robe = (_look.robe as Color).lerp(FAIRY_ROBE, 0.32)
	_look.pants = (_look.pants as Color).lerp(FAIRY_ROBE, 0.05)
	# 男式的方冠罩在女身的头上会变成一块盖住额头的黑板，换成一支玉冠；斗笠留着，江湖气正好
	if _look.get("hat", "") != "watchman":
		_look.hat = "jade"


## 仙气装束：披帛（肩上两条长飘带）、腰绦、长发高髻、步摇、绕身的灵光。
## 飘带挂在骨头上，跟着人一起动；灵光挂在模型根上，不跟着动作抖。
func _fairy_wear() -> void:
	# 挂在脊柱 / 骨盆上，不挂锁骨：锁骨的骨头是横着的，飘带的"往下"会变成往外飞
	var sash := _silk(FAIRY_SASH)
	var chest := _bone("chest")
	var hips := _bone("hips")
	var s := float(_rig.scale)
	# 链长按身高配：从胸口垂到小腿，往后拖一点，别直愣愣地贴着身子
	for sx in [-1, 1]:
		_ribbons.append(Ribbon.make(chest, Vector3(sx * 0.185, 0.02, -0.06) / s, 0.145 / s, 0.085 / s, sash, 1.35, randf() * TAU, 0.055))
		_ribbons.append(Ribbon.make(hips, Vector3(sx * 0.075, -0.03, -0.05) / s, 0.105 / s, 0.05 / s, sash, 1.85, randf() * TAU, 0.07))
	if not _rig.get("own_hair", false):
		_hair()
	if not _rig.get("own_dress", false):
		_belt()
	_motes = Motes.make(_model, FAIRY_GLOW, 0.44 / s, 1.5 / s)
	K.light(self, FAIRY_GLOW, 0.5, 2.6, Vector3(0, 1.15, 0))


## 束腰：一圈青灰的带子，压在衣摆接缝上（那块模型的裙边是锯齿的，不遮一下像撕破了）。
func _belt() -> void:
	var pelvis := _bone("hips")
	var band := _silk(Color("#3f5a63"))
	K.cyl(pelvis, 0.168, 0.186, 0.075, band, Vector3(0, 0.02, 0), Vector3.ZERO, 20)
	K.cyl(pelvis, 0.176, 0.176, 0.018, K.mat(K.GOLD, 0.35, 0.3), Vector3(0, 0.02, 0), Vector3.ZERO, 20)


## 高挽的发髻 + 垂到背心的长发。模型自带的双丫髻留着，这两件压在后面。
func _hair() -> void:
	var head := _bone("head")
	var top := Vector3(0, _head_top(), 0.015)
	var hc: Color = _look.get("hair", FAIRY_HAIR)
	var hair := K.mat(hc, 0.5)
	var gold := K.mat(Color("#d9b25e"), 0.32, 0.35)
	# 高髻
	K.sphere(head, 0.078, hair, top + Vector3(0, 0.01, -0.075), Vector3(1.0, 0.86, 1.0))
	# 垂到背心的长发：贴着后背往下，别从侧面穿到胸前去
	var fall := K.capsule(head, 0.07, 0.38, hair, top + Vector3(0, -0.30, -0.155), Vector3(6, 0, 0))
	fall.scale = Vector3(1.1, 1.0, 0.5)
	# 步摇：金簪横插，坠一颗会晃的珠子
	K.cyl(head, 0.0055, 0.0055, 0.13, gold, top + Vector3(0.02, 0.03, -0.055), Vector3(0, 0, 74))
	var dangle := K.node(head, top + Vector3(0.088, 0.062, -0.055))
	K.sphere(dangle, 0.017, K.mat(FAIRY_GLOW, 0.25, 2.2), Vector3(0, -0.062, 0))
	_dangles.append(dangle)
	# 眉心一点朱砂
	K.sphere(head, 0.0075, K.mat(K.CINNABAR, 0.4, 0.6), top + Vector3(0, -0.062, 0.10))


## 丝绸：比布衣亮、有边缘光，还带一点自发光，暗处也飘得起来。
static func _silk(c: Color) -> StandardMaterial3D:
	var key := "silk|" + c.to_html()
	if K._mats.has(key):
		return K._mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.52
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = c.lightened(0.4)
	m.emission_energy_multiplier = 0.12
	K._mats[key] = m
	return m


## 衣服、鞋按身份上色；僵尸的皮肤发青。主角用丝绸料，头发按仙气配色。
func _dress() -> void:
	var fairy: bool = _look.get("fairy", false)
	for mi in _skel.find_children("*", "MeshInstance3D", false, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else ""
			match mname:
				"Robe":
					m.set_surface_override_material(s, _silk(_look.robe) if fairy else _cloth(_look.robe))
				"Pants":
					m.set_surface_override_material(s, _silk(_look.pants) if fairy else _cloth(_look.pants))
				"Shoes":
					m.set_surface_override_material(s, _cloth(Color("#1c1816")))
				_:
					if _look.has("hair") and mname.begins_with("MI_Hair"):
						m.set_surface_override_material(s, K.mat(_look.hair, 0.5))
					elif _look.has("skin") and m.name == "Body" and mat is StandardMaterial3D:
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


## 按骨骼取挂件用的容器：head / chest / hips / hand_l / hand_r
## 骨架可能带着缩放导进来（413games 那套是 MMD 单位，骨头上约 1/100），挂在骨头上的东西会被一起缩小。
## 所以在骨头下面垫一层容器，每帧按骨头的实际缩放配个反的，挂件就一律按米来写。
func _bone(key: String) -> Node3D:
	var b := BoneAttachment3D.new()
	b.bone_name = str(_rig.get(key, "Head"))
	_skel.add_child(b)
	var w := Node3D.new()
	b.add_child(w)
	_fixes.append([b, w])
	return w


## 把挂点容器的缩放配成骨头缩放的反数，抵消骨架自带的缩放。
func _fix_bone_scale() -> void:
	for pair in _fixes:
		var b: BoneAttachment3D = pair[0]
		var w: Node3D = pair[1]
		var s: Vector3 = b.global_transform.basis.get_scale()
		w.scale = Vector3(
			1.0 / s.x if absf(s.x) > 0.0001 else 1.0,
			1.0 / s.y if absf(s.y) > 0.0001 else 1.0,
			1.0 / s.z if absf(s.z) > 0.0001 else 1.0)


## 头顶离头骨原点有多高。有 HeadTop_End 的骨骼（Mixamo）直接量，量不到就按体型给的数。
## 注意量出来的是骨架自己的单位，要先乘骨架的缩放才是米。
func _head_top() -> float:
	var tb := str(_rig.get("top_bone", ""))
	if tb != "":
		var i := _skel.find_bone(tb)
		var h := _skel.find_bone(str(_rig.head))
		if i >= 0 and h >= 0:
			var s := _skeleton_scale()
			return (_skel.get_bone_global_pose(i).origin - _skel.get_bone_global_pose(h).origin).y * s
	return float(_rig.get("head_top", 0.235))


## 骨架自身带着的缩放（Mixamo 那套约 1/100）
func _skeleton_scale() -> float:
	var n: Node = _skel
	var s := 1.0
	while n != null and n != self:
		if n is Node3D:
			s *= (n as Node3D).scale.y
		n = n.get_parent()
	return s


## 动作名按骨骼选：这一套没有（比如 UAL 的 Interact）就退回本套的对应动作。
func _pick(name: String, key: String) -> String:
	if name != "" and _ap != null and _ap.has_animation(name):
		return name
	return str(_rig.get(key, "Idle"))


## 冠帽、黄符、灯笼：挂在头骨 / 手骨上。头骨原点在后脑勺下沿，头顶约在 +0.24。
func _accessories() -> void:
	var head := _bone("head")
	var top := Vector3(0, _head_top(), 0.015)
	# 女身的头比男身小一圈：冠帽往下压、往里收，别悬在头发上面
	var hs := 0.88 if _look.get("fairy", false) else 1.0
	if hs < 1.0:
		top += Vector3(0, -0.05, 0)
	match _look.get("hat", ""):
		"scholar":
			K.box(head, Vector3(0.21, 0.12, 0.22) * hs, K.ROOF_EDGE, top + Vector3(0, 0.02, -0.01))
			for sx in [-1, 1]:
				K.box(head, Vector3(0.03, 0.24, 0.012) * hs, K.ROOF_EDGE, Vector3(sx * 0.045, 0.1, -0.12) * hs, Vector3(10, 0, 0))
		"escort":
			K.cyl(head, 0.112, 0.112, 0.05, K.CINNABAR, top + Vector3(0, -0.06, 0))
			K.sphere(head, 0.055, K.ROOF_EDGE, top + Vector3(0, 0.02, -0.03))
		"watchman":
			K.cyl(head, 0.02, 0.34, 0.15, Color("#b89a5e"), top + Vector3(0, 0.03, 0), Vector3.ZERO, 16)
			var hand := _bone("hand_r")
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
			var chest := _bone("chest")
			K.box(chest, Vector3(0.2, 0.2, 0.015), K.mat(K.GOLD, 0.5), Vector3(0, 0.05, 0.16))
		"villager":
			K.sphere(head, 0.05, K.ROOF_EDGE, top + Vector3(0, 0.0, -0.035))
		"jade":
			# 玉冠：一支横穿的玉管压在髻上，金簪从中间过去
			var jade := K.mat(Color("#8ec6ae"), 0.3, 0.18)
			K.cyl(head, 0.042, 0.042, 0.15, jade, top + Vector3(0, 0.02, -0.075), Vector3(0, 0, 90), 12)
			K.box(head, Vector3(0.05, 0.045, 0.05) * hs, jade, top + Vector3(0, 0.055, -0.075))
			K.cyl(head, 0.008, 0.008, 0.2, K.mat(K.GOLD, 0.35, 0.3), top + Vector3(0, 0.03, -0.075), Vector3(0, 0, 90), 8)


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
		anim = str(_rig.get("idle", "Idle"))
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
		_play(str(_rig.get("idle", "Idle")))
		return
	_model.rotation_degrees.x = lerpf(_model.rotation_degrees.x, 0.0, delta * 8.0)
	if hopping:
		var ph := fmod(_t * 2.2, 1.0)
		_model.position.y = sin(ph * PI) * 0.32
		_play(_look.idle)
		return
	_model.position.y = lerpf(_model.position.y, 0.0, delta * 10.0)
	if moving:
		var gait := _gait(move_speed if move_speed >= 0.0 else _measured)
		_play(gait[0])
		_ap.speed_scale = gait[1]
		_footstep()
	elif working:
		_play(_pick(work_anim, "work"))
	else:
		_play(_look.idle)
	_tick_fairy(delta, moving)


## 飘带、灵光、步摇坠子的每帧摆动。站着摆得小，走起来摆得开。
func _tick_fairy(delta: float, walking: bool) -> void:
	_fix_bone_scale()
	if _ribbons.is_empty() and _dangles.is_empty() and _motes == null:
		return
	var wind := 1.0 if walking else 0.42
	for r in _ribbons:
		r.tick(_t, wind)
	for d in _dangles:
		d.rotation.z = sin(_t * 2.1) * 0.22 * wind
		d.rotation.x = sin(_t * 1.5 + 0.8) * 0.14 * wind
	if _motes != null:
		_motes.tick(_t, delta)
	if _look.get("fairy", false) and not walking and not working:
		# 仙气：站着的时候脚不离地，人轻轻浮着
		_model.position.y = 0.05 + sin(_t * 1.1) * 0.035


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
		return [_look.walk, clampf(v / WALK_SPEED, 0.6, 1.9)]
	if v < 4.2:
		return [str(_rig.jog), clampf(v / JOG_SPEED, 0.6, 1.3)]
	return [str(_rig.sprint), clampf(v / SPRINT_SPEED, 0.7, 2.4)]


## 倒地。
func fall() -> void:
	hopping = false
	moving = false
	_fallen = true
	_model.position.y = 0.0
	_ap.speed_scale = 1.0
	_cur = _pick("Death01", "death")
	_ap.play(_cur, 0.1)


func face(dir: Vector3, weight := 1.0) -> void:
	if dir.length() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), weight)


## 飘带（披帛 / 腰绦）：一串首尾相接的小片，靠每节错开一点相位摆，看着像被风带着飘。
## 关键：相位差要小（行波，不是正负交替），幅度也要小——否则链子会自己折回来团成一团。
class Ribbon extends Node3D:
	const SEGS := 7

	var _segs: Array[Node3D] = []
	var _amp := 0.05
	var _freq := 1.5
	var _phase := 0.0
	var _lean := 0.035

	static func make(parent: Node3D, pos: Vector3, seg_len: float, width: float, mat: Material,
			freq: float, phase: float, lean: float) -> Ribbon:
		var r := Ribbon.new()
		r.position = pos
		r._freq = freq
		r._phase = phase
		r._lean = lean
		parent.add_child(r)
		var node: Node3D = r
		for i in range(SEGS):
			var seg := Node3D.new()
			if i > 0:
				seg.position = Vector3(0, -seg_len, 0)
			node.add_child(seg)
			var k := float(i) / float(SEGS - 1)
			K.box(seg, Vector3(width * (1.0 - k * 0.55), seg_len, 0.012), mat, Vector3(0, -seg_len * 0.5, 0))
			r._segs.append(seg)
			node = seg
		return r

	func tick(t: float, wind: float) -> void:
		for i in _segs.size():
			var s := _segs[i]
			var k := float(i) / float(_segs.size() - 1)
			# 每节只错 0.45 弧度，从根到尖传一遍，像鞭子那样甩
			var ph := t * _freq - k * 0.45 + _phase
			s.rotation.x = _lean + _amp * wind * sin(ph) * (0.25 + 0.75 * k)
			s.rotation.z = _amp * 0.7 * wind * sin(ph * 0.8 + 1.1) * (0.25 + 0.75 * k)


## 灵光：绕着人慢慢转的一圈小光点，各自上下浮、忽明忽暗。
class Motes extends Node3D:
	const COUNT := 22

	var _pts: Array[MeshInstance3D] = []
	var _spin := 0.3

	static func make(parent: Node3D, color: Color, radius: float, height: float) -> Motes:
		var m := Motes.new()
		parent.add_child(m)
		var glow := K.mat(color, 0.25, 1.7, 0.55)
		for i in COUNT:
			var a := TAU * float(i) / float(COUNT) + randf() * 0.4
			var pivot := Node3D.new()
			var r := radius * (0.45 + randf() * 0.55)
			pivot.position = Vector3(cos(a) * r, 0.12 + randf() * height, sin(a) * r)
			pivot.set_meta("a", a)
			m.add_child(pivot)
			var mi := K.sphere(pivot, 0.009 + randf() * 0.011, glow, Vector3.ZERO)
			m._pts.append(mi)
		m._spin = 0.22 + randf() * 0.16
		return m

	func tick(t: float, delta: float) -> void:
		rotation.y += delta * _spin
		for mi in _pts:
			var a: float = mi.get_parent().get_meta("a", 0.0)
			mi.position.y = sin(t * 0.9 + a * 2.0) * 0.16
			var s := 0.7 + 0.4 * sin(t * 2.1 + a * 3.0)
			mi.scale = Vector3(s, s, s)


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
