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
var _toast_entries := {}
var _modals := {}
var _screen: Control
var _backdrop: Control
var _reading_wash: ColorRect


class ToastEntry extends RefCounted:
	var panel: PanelContainer
	var label: Label
	var count := 1
	var tween: Tween


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


## 靛布书衣：四眼线订留在书脊上，页口和包角随匣子九宫缩放。
class ModalFrame extends PanelContainer:
	func _init() -> void:
		var cover := StyleBoxTexture.new()
		cover.texture = preload("res://assets/ui/ledger-cover.svg")
		cover.texture_margin_left = 18
		cover.texture_margin_right = 13
		cover.texture_margin_top = 14
		cover.texture_margin_bottom = 15
		cover.content_margin_left = 18
		cover.content_margin_right = 8
		cover.content_margin_top = 8
		cover.content_margin_bottom = 10
		add_theme_stylebox_override("panel", cover)

	func _draw() -> void:
		var thread := Color("#cabc98")
		var inset := minf(30.0, size.y * 0.15)
		draw_line(Vector2(10, inset), Vector2(10, size.y - inset), thread, 1.2, true)
		for i in 4:
			var y := lerpf(inset, size.y - inset, i / 3.0)
			draw_circle(Vector2(10, y), 2.3, Color("#1f302a"), true, -1, true)
			draw_line(Vector2(2, y + 1.5), Vector2(10, y), thread, 1.7, true)


func _title_slip(title: String) -> Label:
	var label := UI.heading(title, 26, Color("#4c3428"))
	var slip := StyleBoxTexture.new()
	slip.texture = preload("res://assets/ui/ledger-title-slip.svg")
	slip.texture_margin_left = 12
	slip.texture_margin_right = 10
	slip.texture_margin_top = 7
	slip.texture_margin_bottom = 8
	slip.content_margin_left = 17
	slip.content_margin_right = 13
	slip.content_margin_top = 0
	slip.content_margin_bottom = 0
	label.add_theme_stylebox_override("normal", slip)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label


func _ready() -> void:
	theme = UI.make_theme()
	UI.host = self
	# 根节点和装界面的容器都不吃鼠标，否则 3D 场景的点击、拖动转视角、滚轮缩放都到不了 _unhandled_input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var album := TextureRect.new()
	album.texture = preload("res://assets/ui/ferry-album.png")
	album.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	album.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	album.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	album.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = UI.full_rect(album)
	# 誓约与结算有直接排在画上的小字，覆一层薄纸，让松针和船影退到字后。
	_reading_wash = ColorRect.new()
	_reading_wash.color = Color(UI.PAPER_LIGHT, 0.57)
	_reading_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(UI.full_rect(_reading_wash))
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
	_reading_wash.visible = target in ["challenge", "dead", "ending"]
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
	head.add_child(_title_slip(title))
	head.add_child(UI.spacer())
	if closable:
		head.add_child(UI.button("合上", func(): close_modal(key)))
	outer.add_child(head)
	outer.add_child(UI.sep())
	m.body = UI.vbox(8)
	outer.add_child(m.body)
	var p := UI.panel(outer)
	var page_color := Color("#232b28") if m.dark else Color("#f2ead9")
	var page_edge := Color("#697267") if m.dark else Color("#bca98a")
	p.add_theme_stylebox_override("panel", UI._box(page_color, page_edge, 1, 0, 10, 12))
	var frame := ModalFrame.new()
	frame.add_child(p)
	center.add_child(frame)
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
	# 按原文合并；计数后缀只是显示内容，不能成为下一次查找的键。
	var entry: ToastEntry = _toast_entries.get(text)
	if entry != null and entry.tween != null:
		entry.tween.kill()
	if entry != null and is_instance_valid(entry.panel) and not entry.panel.is_queued_for_deletion():
		entry.count += 1
		entry.label.text = "%s ×%d" % [text, entry.count]
	else:
		entry = ToastEntry.new()
		entry.label = UI.label(text, 18, UI.PAPER_LIGHT)
		entry.panel = UI.panel(entry.label, Color(UI.INK, 0.88))
		entry.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toasts.add_child(entry.panel)
		_toast_entries[text] = entry
	# 淡出中的同句也复用原条，取消旧回调，再从完整驻留时间开始。
	entry.panel.modulate.a = 1.0
	entry.tween = create_tween()
	entry.tween.tween_interval(2.2)
	entry.tween.tween_property(entry.panel, "modulate:a", 0.0, 0.6)
	entry.tween.tween_callback(_expire_toast.bind(text, entry.panel))


func _expire_toast(text: String, panel: PanelContainer) -> void:
	# 旧节点的清理不能移除同文后来生成的新条。
	var entry: ToastEntry = _toast_entries.get(text)
	if entry != null and entry.panel == panel:
		_toast_entries.erase(text)
	if is_instance_valid(panel):
		panel.queue_free()


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
