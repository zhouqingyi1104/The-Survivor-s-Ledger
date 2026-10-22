extends Control
## 3D 界面的基类：3D 世界只建一次，Game 有变化时同步世界、重画 HUD（不整屏重建，人物位置不会丢）。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")

## main.gd 看到这个就把水墨底图藏起来，露出 3D 画面。
var uses_world := true
var world: Node3D
var hud: Control
var _dirty := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_world()
	hud = UI.full_rect(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	build_overlay()
	Game.changed.connect(_queue)
	refresh()


func _queue() -> void:
	if _dirty:
		return
	_dirty = true
	_refresh_deferred.call_deferred()


func _refresh_deferred() -> void:
	_dirty = false
	if is_inside_tree() and not Game.run.is_empty():
		refresh()


func refresh() -> void:
	UI.use_dark(false)
	sync_world()
	UI.clear(hud)
	build_hud()
	after_build()


## 子类重写：建 3D 世界（只调一次）。
func build_world() -> void:
	pass


## 子类重写：常驻的覆盖层（交互提示等，不随 HUD 重画）。
func build_overlay() -> void:
	pass


## 子类重写：把 Game.run 画进世界。
func sync_world() -> void:
	pass


## 子类重写：搭 HUD。
func build_hud() -> void:
	pass


## 子类重写：自动弹出的窗。
func after_build() -> void:
	pass


func modal_open() -> bool:
	return UI.host != null and UI.host.modal_count() > 0


# ---------- HUD 小部件 ----------

## 贴在屏幕某个角上的半透明面板。
func corner_panel(content: Control, anchor: int, margin := 14, alpha := 0.86) -> PanelContainer:
	var p := UI.panel(content, Color(UI.PAPER_LIGHT, alpha))
	hud.add_child(p)
	p.set_anchors_and_offsets_preset(anchor, Control.PRESET_MODE_MINSIZE, margin)
	var right: bool = anchor in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]
	var bottom: bool = anchor in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	var center_h: bool = anchor in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH if center_h else (Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	return p
