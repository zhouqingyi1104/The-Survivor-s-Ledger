extends Control
## 所有界面的基类：Game 有变化就整屏重画（原型阶段界面不大，整屏重画最省事也最不容易出错）。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")

var _dirty := false


func _ready() -> void:
	Game.changed.connect(_queue)
	build()
	after_build()


func _queue() -> void:
	if _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	UI.clear(self)
	build()
	after_build()


## 子类重写：搭界面。
func build() -> void:
	pass


## 子类重写：搭完界面后要自动弹出的窗（事件、外出、夜报）。
func after_build() -> void:
	pass


## 整屏的外边距容器，子类往里面加东西。
func page(margin := 18) -> VBoxContainer:
	var m := UI.full_rect(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	add_child(m)
	var v := UI.vbox(12)
	m.add_child(v)
	return v
