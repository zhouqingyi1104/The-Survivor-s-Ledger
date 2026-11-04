extends Node3D
## 后两轮的短反馈：只读取已结算战报，不再预测或结算战斗。

signal finished

const Defense = preload("res://scripts/core/defense.gd")
const K = preload("res://scripts/world/kit.gd")
const SURFACE_POS := {
	"gate": Vector3(0, 1.5, 7.0),
	"window": Vector3(5.6, 1.7, 7.0),
	"wall": Vector3(-5.6, 1.5, 7.0),
}

var report: Dictionary = {}
var focus_surface := "gate"
var banner := ""
var duration := 2.2
var _elapsed := 0.0
var _done := false
var _pulse: MeshInstance3D
var _light: OmniLight3D


## 新破面优先；未破时先看进院、再看受损、最后看来袭最多的一面。
static func focus_for_report(rep: Dictionary) -> String:
	for sid in rep.get("broke", []):
		if sid in Defense.SURFACES:
			return str(sid)
	var chosen := "gate"
	var best := Vector3i(-1, -1, -1)
	for sid in Defense.SURFACES:
		var surface: Dictionary = rep.get("surfaces", {}).get(sid, {})
		var score := Vector3i(int(surface.get("enter", 0)), int(surface.get("dmg", 0)), int(surface.get("count", 0)))
		if score.x > best.x or (score.x == best.x and score.y > best.y) or (score.x == best.x and score.y == best.y and score.z > best.z):
			best = score
			chosen = sid
	return chosen


func play(_world: Node3D, rig: Node3D, rep: Dictionary) -> void:
	report = rep.duplicate(true)
	focus_surface = focus_for_report(report)
	var surface: Dictionary = report.get("surfaces", {}).get(focus_surface, {})
	var broken: bool = focus_surface in report.get("broke", [])
	var live_gate := int(report.get("live_gate", 0))
	var result := "被撞破" if broken else ("有人闯入" if int(surface.get("enter", 0)) > 0 else ("受到冲击" if int(surface.get("dmg", 0)) > 0 else "守住了"))
	if focus_surface == "gate" and live_gate > 0:
		result = "开着"
	banner = "第 %d 轮 · %s%s · 斩 %d 只" % [int(report.get("round", 0)) + 1,
		Defense.surface_name(focus_surface), result, int(report.get("killed", 0))]
	if int(report.get("enter", 0)) > 0:
		banner += " · 进院 %d 只" % int(report.enter)
	if live_gate > 0:
		banner += " · 门前来 %d 只" % live_gate
	var focus: Vector3 = SURFACE_POS[focus_surface]
	rig.goto(focus + Vector3(0, 7.8, 9.8), focus)
	var color := Color("#e36e51") if broken or int(surface.get("enter", 0)) > 0 else Color("#e9c575")
	_pulse = K.sphere(self, 0.6, K.mat(color, 0.5, 2.0, 0.32), focus + Vector3(0, 0, 0.3), Vector3(1.6, 1.6, 0.18))
	_light = K.light(self, color, 2.5, 5.0, focus + Vector3(0, 0.8, 1.0))
	Sfx.play("hit_plank" if broken else "hit_door", -6.0)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _pulse != null:
		var pulse := 1.0 + sin(_elapsed * 9.0) * 0.18
		_pulse.scale = Vector3(1.6, 1.6, 0.18) * pulse
		_light.light_energy = 1.4 + pulse
	if _elapsed >= duration:
		_finish()


func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
