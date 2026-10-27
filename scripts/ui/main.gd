extends Control
## 主场景：水墨背景、界面切换、弹窗层、提示条，以及截图用的演示模式（--demo / --shot）。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Demo = preload("res://scripts/dev/demo.gd")

const SCREENS := {
	"title": "res://scripts/ui/screens/title_screen.gd",
	"roles": "res://scripts/ui/screens/roles_screen.gd",
	"difficulty": "res://scripts/ui/screens/difficulty_screen.gd",
	"challenge": "res://scripts/ui/screens/challenge_screen.gd",
	"talents": "res://scripts/ui/screens/talents_screen.gd",
	"pre": "res://scripts/ui/screens/pre_screen.gd",
	"post": "res://scripts/ui/screens/post_screen.gd",
	"dead": "res://scripts/ui/screens/dead_screen.gd",
	"ending": "res://scripts/ui/screens/ending_screen.gd",
	"explore": "res://scripts/ui/screens/explore_screen.gd",
}

var _holder: Control
var _modal_layer: Control
var _toasts: VBoxContainer
var _modals := {}
var _screen: Control
var _backdrop: Control


## 弹窗：Game 一有变化就重画内容，所以弹窗里的按钮按下去，界面马上跟着变。
class Modal extends Control:
	const UI = preload("res://scripts/ui/ui_kit.gd")
	var key := ""
	var closable := true
	var build_fn: Callable
	var body: VBoxContainer
	## 3D 场景上的弹窗用夜色（和 HUD 一致），2D 页面上的用宣纸
	var dark := false
	var _dirty := false

	func _ready() -> void:
		Game.changed.connect(_queue)

	func _queue() -> void:
		if _dirty:
			return
		_dirty = true
		_rebuild.call_deferred()

	func _rebuild() -> void:
		_dirty = false
		if not is_inside_tree():
			return
		UI.clear(body)
		UI.use_dark(dark)
		build_fn.call(body)
		UI.use_dark(false)


## 远山：几层淡墨山影，压在宣纸底色上。
class Backdrop extends Control:
	const UI = preload("res://scripts/ui/ui_kit.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.PAPER)
		draw_circle(Vector2(size.x * 0.82, size.y * 0.2), 46, Color(UI.CINNABAR, 0.12))
		var layers := [[0.62, 70.0, 0.045, 0.7], [0.72, 55.0, 0.06, 2.1], [0.84, 40.0, 0.08, 4.3]]
		for layer in layers:
			var pts := PackedVector2Array()
			pts.append(Vector2(0, size.y))
			var x := 0.0
			while x <= size.x + 8:
				var t := x / maxf(size.x, 1.0)
				var y: float = size.y * layer[0] - layer[1] * (0.55 + 0.45 * sin(t * 7.0 + layer[3])) * (0.6 + 0.4 * sin(t * 2.3 + layer[3] * 1.7))
				pts.append(Vector2(x, y))
				x += 8
			pts.append(Vector2(size.x, size.y))
			draw_colored_polygon(pts, Color(UI.INK, layer[2]))


func _ready() -> void:
	theme = UI.make_theme()
	UI.host = self
	# 根节点和装界面的容器都不吃鼠标，否则 3D 场景的点击、拖动转视角、滚轮缩放都到不了 _unhandled_input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = UI.full_rect(Backdrop.new())
	add_child(_backdrop)
	_holder = UI.full_rect(Control.new())
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_modal_layer = UI.full_rect(Control.new())
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	_toasts = UI.vbox(6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position.y = 18
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	Game.screen_changed.connect(_show)
	Game.toast.connect(show_toast)
	_show(Game.screen)
	_run_demo_if_asked()


func _show(target: String) -> void:
	for key in _modals.keys():
		close_modal(key)
	if _screen != null:
		_holder.remove_child(_screen)
		_screen.queue_free()
	_screen = UI.full_rect(load(SCREENS[target]).new())
	_backdrop.visible = not ("uses_world" in _screen)
	_holder.add_child(_screen)


# ---------- 弹窗 ----------

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or (key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE):
		return
	# 改键时的 Esc 先交给捕获器，取消改键而不关闭设置。
	if is_instance_valid(Dialogs._capture) and Dialogs._capture.active:
		return
	if _modal_layer.get_child_count() == 0:
		return
	# 始终只处理最上层；强制选择的弹窗也要挡住底层与游戏快捷键。
	get_viewport().set_input_as_handled()
	if key_event.echo:
		return
	var top := _modal_layer.get_child(_modal_layer.get_child_count() - 1) as Modal
	if top != null and top.closable:
		close_modal(top.key)


func open_modal(key: String, title: String, build: Callable, closable := true, width := 760.0) -> void:
	if _modals.has(key):
		return
	var m := Modal.new()
	m.key = key
	m.closable = closable
	m.build_fn = build
	m.dark = _screen != null and _screen.get("dark_ui") == true
	if m.dark:
		m.theme = UI.dark_theme()
	UI.use_dark(m.dark)
	UI.full_rect(m)
	var dim := UI.full_rect(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.42) if m.dark else Color(0.12, 0.09, 0.06, 0.55)
	m.add_child(dim)
	var center := UI.full_rect(CenterContainer.new())
	m.add_child(center)
	var outer := UI.vbox(10)
	outer.custom_minimum_size = Vector2(width, 0)
	var head := UI.hbox(8)
	head.add_child(UI.heading(title, 26, UI.GOLD if m.dark else UI.CINNABAR))
	head.add_child(UI.spacer())
	if closable:
		head.add_child(UI.button("合上", func(): close_modal(key)))
	outer.add_child(head)
	outer.add_child(UI.sep())
	m.body = UI.vbox(8)
	outer.add_child(m.body)
	var p := UI.panel(outer, UI.PAPER_LIGHT)
	center.add_child(p)
	_modal_layer.add_child(m)
	_modals[key] = m
	build.call(m.body)
	UI.use_dark(false)
	Sfx.play("ui_open", -10.0, 0.03)


func close_modal(key: String) -> void:
	if not _modals.has(key):
		return
	var m: Control = _modals[key]
	_modals.erase(key)
	Sfx.play("ui_close", -12.0, 0.03)
	_modal_layer.remove_child(m)
	m.queue_free()


func has_modal(key: String) -> bool:
	return _modals.has(key)


func modal_count() -> int:
	return _modals.size()


func show_toast(text: String) -> void:
	var p := UI.panel(UI.label(text, 18, UI.PAPER_LIGHT), Color(UI.INK, 0.88))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# ---------- 截图演示 ----------
# godot --path . -- --demo=post --shot=res://shots/post.png

func _run_demo_if_asked() -> void:
	var demo := ""
	var shot := ""
	var delay := 1.2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demo="):
			demo = arg.trim_prefix("--demo=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--delay="):
			delay = float(arg.trim_prefix("--delay="))
	if demo == "":
		return
	Game.no_save = true
	await get_tree().process_frame
	Demo.setup(demo)
	for k in 3:
		await get_tree().process_frame
	Demo.after_screen(demo, _screen)
	if shot == "":
		return
	await get_tree().create_timer(delay).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot).get_base_dir())
	img.save_png(ProjectSettings.globalize_path(shot))
	print("截图已保存：", shot)
	get_tree().quit()
