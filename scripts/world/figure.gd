extends Node3D
## 人物：用胶囊、圆柱拼的低多边形小人，关节可动（髋-膝、肩-肘），程序动画：
## 走路（摆腿屈膝、摆臂）、干活（手在身前忙）、躺下（睡觉）、僵尸蹦跳、倒地。
## 局部 +Z 是正面。kind：scholar / escort / herbalist / watchman / jiangshi / villager。

const K = preload("res://scripts/world/kit.gd")

const ROBES := {
	"scholar": Color("#5d6f80"), "escort": Color("#3a3330"), "herbalist": Color("#4f6a52"),
	"watchman": Color("#6b5a3f"), "jiangshi": Color("#24324a"), "villager": Color("#7a6a55"),
}
## 长袍盖住腿；短打露出裤腿。
const LONG_ROBE := ["scholar", "herbalist", "jiangshi"]

var kind := "villager"
var moving := false
var hopping := false
var working := false
var lying := false
var speed_scale := 1.0
var lantern_light: OmniLight3D

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _hips: Array = []
var _knees: Array = []
var _shoulders: Array = []
var _elbows: Array = []
var _t := 0.0
var _fall := -1.0


func setup(k: String, robe := Color(0, 0, 0, 0)) -> Node3D:
	kind = k
	_t = randf() * 10.0
	var robe_color: Color = robe if robe.a > 0 else ROBES.get(k, ROBES.villager)
	var skin: Color = K.JIANGSHI_SKIN if k == "jiangshi" else K.SKIN
	var trouser := robe_color.darkened(0.5)
	var long: bool = k in LONG_ROBE
	_body = K.node(self)
	# 腿：髋 → 大腿 → 膝 → 小腿 → 鞋
	for sx in [-1, 1]:
		var hip := K.node(_body, Vector3(sx * 0.1, 0.9, 0))
		K.capsule(hip, 0.075, 0.48, trouser, Vector3(0, -0.22, 0))
		var knee := K.node(hip, Vector3(0, -0.44, 0))
		K.capsule(knee, 0.062, 0.46, trouser, Vector3(0, -0.21, 0))
		K.box(knee, Vector3(0.11, 0.07, 0.24), K.ROOF_EDGE, Vector3(0, -0.43, 0.05))
		_hips.append(hip)
		_knees.append(knee)
	# 躯干
	_torso = K.node(_body, Vector3(0, 0.92, 0))
	if long:
		K.cyl(_torso, 0.21, 0.33, 0.78, robe_color, Vector3(0, -0.3, 0), Vector3.ZERO, 14)
	else:
		K.cyl(_torso, 0.21, 0.25, 0.3, robe_color, Vector3(0, -0.02, 0), Vector3.ZERO, 14)
	K.cyl(_torso, 0.19, 0.215, 0.5, robe_color, Vector3(0, 0.3, 0), Vector3.ZERO, 14)
	K.cyl(_torso, 0.218, 0.218, 0.07, robe_color.darkened(0.4), Vector3(0, 0.08, 0), Vector3.ZERO, 14)
	# 交领
	K.box(_torso, Vector3(0.05, 0.36, 0.02), robe_color.lightened(0.35), Vector3(0.03, 0.36, 0.19), Vector3(0, 0, 22))
	K.box(_torso, Vector3(0.05, 0.36, 0.02), robe_color.lightened(0.35), Vector3(-0.03, 0.36, 0.195), Vector3(0, 0, -22))
	K.capsule(_torso, 0.11, 0.5, robe_color, Vector3(0, 0.52, 0), Vector3(0, 0, 90))
	# 头
	_head = K.node(_torso, Vector3(0, 0.62, 0))
	K.cyl(_head, 0.055, 0.06, 0.1, skin, Vector3(0, 0.0, 0))
	K.sphere(_head, 0.13, skin, Vector3(0, 0.17, 0), Vector3(0.95, 1.08, 1.0))
	K.sphere(_head, 0.135, K.ROOF_EDGE, Vector3(0, 0.2, -0.02), Vector3(1.0, 1.0, 0.95), true)
	for sx in [-1, 1]:
		K.sphere(_head, 0.018, K.ROOF_EDGE, Vector3(sx * 0.045, 0.18, 0.12))
		K.box(_head, Vector3(0.05, 0.01, 0.01), K.ROOF_EDGE, Vector3(sx * 0.045, 0.215, 0.122), Vector3(0, 0, sx * -8))
	# 手臂：肩 → 上臂 → 肘 → 前臂（宽袖）→ 手
	for sx in [-1, 1]:
		var sh := K.node(_torso, Vector3(sx * 0.25, 0.5, 0))
		K.capsule(sh, 0.065, 0.34, robe_color, Vector3(0, -0.15, 0))
		var el := K.node(sh, Vector3(0, -0.3, 0))
		K.cyl(el, 0.065, 0.11, 0.3, robe_color, Vector3(0, -0.14, 0), Vector3.ZERO, 10)
		K.sphere(el, 0.048, skin, Vector3(0, -0.33, 0.01))
		_shoulders.append(sh)
		_elbows.append(el)
	_hat(k, robe_color)
	if k == "jiangshi":
		for sh in _shoulders:
			sh.rotation_degrees.x = -88
		K.box(_torso, Vector3(0.2, 0.2, 0.02), K.mat(K.GOLD, 0.5), Vector3(0, 0.28, 0.215))
		var tal := K.box(_head, Vector3(0.11, 0.24, 0.01), K.mat(K.PAPER, 0.8, 0.4), Vector3(0, 0.16, 0.135))
		tal.rotation_degrees.x = -10
		K.box(_head, Vector3(0.02, 0.16, 0.012), K.CINNABAR, Vector3(0, 0.16, 0.142))
	return self


func _hat(k: String, robe: Color) -> void:
	match k:
		"scholar":
			K.box(_head, Vector3(0.24, 0.14, 0.24), K.ROOF_EDGE, Vector3(0, 0.33, -0.01))
			for sx in [-1, 1]:
				K.box(_head, Vector3(0.035, 0.28, 0.015), K.ROOF_EDGE, Vector3(sx * 0.05, 0.16, -0.15), Vector3(12, 0, 0))
		"escort":
			K.cyl(_head, 0.138, 0.138, 0.06, K.CINNABAR, Vector3(0, 0.25, 0))
			K.sphere(_head, 0.06, K.ROOF_EDGE, Vector3(0, 0.33, -0.03))
		"herbalist":
			K.sphere(_head, 0.14, Color("#34473a"), Vector3(0, 0.23, 0), Vector3.ONE, true)
		"watchman":
			K.cyl(_head, 0.02, 0.38, 0.16, Color("#b89a5e"), Vector3(0, 0.36, 0), Vector3.ZERO, 14)
			var lan := K.node(_elbows[1], Vector3(0, -0.42, 0.06))
			K.sphere(lan, 0.1, K.mat(Color("#ff8a4a"), 0.5, 2.5), Vector3(0, -0.08, 0), Vector3(1, 1.3, 1))
			lantern_light = K.light(lan, Color("#ffae6b"), 1.2, 6.0, Vector3(0, -0.08, 0))
		"jiangshi":
			K.cyl(_head, 0.15, 0.17, 0.13, K.ROOF_EDGE, Vector3(0, 0.33, 0), Vector3.ZERO, 14)
			K.cyl(_head, 0.24, 0.24, 0.035, K.ROOF_EDGE, Vector3(0, 0.27, 0), Vector3.ZERO, 14)
			K.sphere(_head, 0.045, K.CINNABAR, Vector3(0, 0.43, 0))
			K.box(_head, Vector3(0.07, 0.24, 0.02), K.ROOF_EDGE, Vector3(0, 0.15, -0.15))
		_:
			K.sphere(_head, 0.06, K.ROOF_EDGE, Vector3(0, 0.33, -0.04))


func _process(delta: float) -> void:
	if _fall >= 0.0:
		_fall = minf(1.0, _fall + delta * 2.5)
		_body.rotation_degrees.x = lerpf(0, -88, ease(_fall, 0.5))
		_body.position.y = lerpf(0, 0.12, _fall)
		return
	_t += delta * speed_scale
	if lying:
		_body.rotation_degrees.x = lerpf(_body.rotation_degrees.x, -90.0, delta * 6.0)
		_body.position.y = lerpf(_body.position.y, 0.62, delta * 6.0)
		_pose_legs(0, 0)
		return
	_body.rotation_degrees.x = lerpf(_body.rotation_degrees.x, 0.0, delta * 8.0)
	if hopping:
		var ph := fmod(_t * 2.2, 1.0)
		_body.position.y = sin(ph * PI) * 0.32
		_torso.rotation_degrees.x = sin(ph * TAU) * 4.0
		_pose_legs(-8.0 * sin(ph * PI), 14.0 * sin(ph * PI))
		return
	if kind == "jiangshi":
		_body.position.y = lerpf(_body.position.y, 0.0, delta * 8.0)
		_torso.rotation_degrees.z = sin(_t * 0.9) * 2.0
		return
	if moving:
		var s := sin(_t * 8.5)
		_hips[0].rotation_degrees.x = s * 30.0
		_hips[1].rotation_degrees.x = -s * 30.0
		_knees[0].rotation_degrees.x = maxf(0.0, -s) * 42.0
		_knees[1].rotation_degrees.x = maxf(0.0, s) * 42.0
		_shoulders[0].rotation_degrees.x = -s * 24.0
		_shoulders[1].rotation_degrees.x = s * 24.0
		_elbows[0].rotation_degrees.x = -12.0
		_elbows[1].rotation_degrees.x = -12.0
		_body.position.y = absf(cos(_t * 8.5)) * 0.04
		return
	_pose_legs(0, 0)
	_body.position.y = lerpf(_body.position.y, 0.0, delta * 8.0)
	if working:
		var w := sin(_t * 7.0)
		for k in 2:
			_shoulders[k].rotation_degrees.x = lerpf(_shoulders[k].rotation_degrees.x, -50.0 + w * 14.0 * (1 if k == 0 else -1), delta * 10.0)
			_elbows[k].rotation_degrees.x = lerpf(_elbows[k].rotation_degrees.x, -40.0, delta * 10.0)
		_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, 12.0, delta * 6.0)
		return
	_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, 0.0, delta * 6.0)
	var breath := sin(_t * 1.3) * 3.0
	for k in 2:
		_shoulders[k].rotation_degrees.x = lerpf(_shoulders[k].rotation_degrees.x, breath * (1 if k == 0 else -1), delta * 6.0)
		_elbows[k].rotation_degrees.x = lerpf(_elbows[k].rotation_degrees.x, -6.0, delta * 6.0)


func _pose_legs(hip: float, knee: float) -> void:
	for k in 2:
		_hips[k].rotation_degrees.x = hip
		_knees[k].rotation_degrees.x = knee


## 倒地（僵尸被斩、人被扑倒）。
func fall() -> void:
	hopping = false
	moving = false
	_fall = 0.0


func face(dir: Vector3, weight := 1.0) -> void:
	if dir.length() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), weight)
