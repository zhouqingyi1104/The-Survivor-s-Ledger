extends Node
## 设置界面的鼠标 + 键盘验收：按键重绑全流程（改键 / 冲突 / 取消 / 恢复默认）与画面三项。
## 鼠标走视口路由、改键靠捕获节点收键，必须在窗口下跑：
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/settings_ui.tscn

const InputCfg = preload("res://scripts/core/input_cfg.gd")
const VideoCfg = preload("res://scripts/core/video_cfg.gd")

var main: Control
var checks := 0
var failures := 0
var toasts: Array = []


func check(ok: bool, msg: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(msg)
	return ok


func frames(n := 6) -> void:
	for k in n: await get_tree().process_frame


func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://settings-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://settings-ui-meta-%d.json" % OS.get_process_id()
	Game.toast.connect(_on_toast)
	# 开局 deterministic：不管机器上有没有存过的改绑，先回默认（boot 时的快照就是默认）
	InputCfg.restore()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(150).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	# 标题界面的「设置」按钮走的就是这条（不在游戏里，没有动态世情那一行）
	Dialogs.settings(false)
	await frames(6)

	# ---------- 按键 ----------
	check(main._modals.has("settings"), "设置弹窗没开")
	check(main.modal_count() == 1, "设置弹窗叠层了：%d" % main.modal_count())
	var rebind_btns := 0
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == "改键":
			rebind_btns += 1
	check(rebind_btns == InputCfg.ORDER.size(), "改键按钮数不对：%d（期望 %d）" % [rebind_btns, InputCfg.ORDER.size()])
	check(keys_label_text("翻找 / 查看") == "E", "interact 行没显示默认键 E：" + keys_label_text("翻找 / 查看"))
	check(keys_label_text("行囊") == "I / Tab", "inventory 行没显示 I / Tab：" + keys_label_text("行囊"))

	# 改键：点「改键」→ 按 Q → 行里变 Q、InputMap 变、cfg 落盘
	await click(rebind_button("翻找 / 查看"))
	check(rebind_button("翻找 / 查看").text == "按下新键…", "点了改键按钮没进入等待按键状态")
	# 用 Z 做靶子：Q 现在是「等一刻」的默认键
	await push_key(KEY_Z)
	check(keys_label_text("翻找 / 查看") == "Z", "改键后行里没变成 Z：" + keys_label_text("翻找 / 查看"))
	check(InputCfg.keys_of("interact") == [90], "改键后 InputMap 没变：%s" % str(InputCfg.keys_of("interact")))
	check(rebind_button("翻找 / 查看").text == "改键", "改完键按钮文字没恢复")
	var saved := InputCfg.read()
	check(saved.get("interact", []) == [90], "改键没写进 cfg：%s" % str(saved))

	# 冲突：sleep 绑 Z（已被 interact 占了）→ 提示给了谁、绑定不动
	await click(rebind_button("就寝"))
	await push_key(KEY_Z)
	check(InputCfg.keys_of("sleep") == [78], "冲突键竟然绑上了：%s" % str(InputCfg.keys_of("sleep")))
	check(toasts.any(func(t): return str(t).contains("已经给了") and str(t).contains("翻找")), "冲突没提示给了谁：%s" % str(toasts))
	check(rebind_button("就寝").text == "改键", "冲突后按钮文字没恢复")

	# Esc 取消：不动绑定
	await click(rebind_button("劫余录"))
	await push_key(KEY_ESCAPE)
	check(InputCfg.keys_of("journal") == [74], "Esc 取消没生效，绑定被改了")
	check(keys_label_text("劫余录") == "J", "Esc 取消后行里显示不对")

	# 恢复默认：全回默认、cfg 删掉
	await click(text_button("按键全部恢复默认"))
	check(keys_label_text("翻找 / 查看") == "E", "恢复默认后 interact 没回 E")
	check(keys_label_text("就寝") == "N", "恢复默认后 sleep 没回 N")
	check(not FileAccess.file_exists("user://input.cfg"), "恢复默认后 cfg 还在")

	# ---------- 画面 ----------
	# 垂直同步：默认是开（VideoCfg.defaults），所以断言写成"翻转前后对比"，
	# 不预设初始值——免得把默认值猜反了还以为是按钮没反应
	var vs := video_button("垂直同步：")
	var vs_was_on: bool = vs.text.contains("开")
	await click(vs)
	check(video_button("垂直同步：").text.contains("开") != vs_was_on,
		"垂直同步按钮文字没翻过来：" + video_button("垂直同步：").text)
	check(bool(VideoCfg.read().vsync) == (not vs_was_on), "垂直同步没存进 cfg")
	await click(video_button("垂直同步："))
	check(video_button("垂直同步：").text.contains("开") == vs_was_on, "垂直同步没翻回去")

	# 分辨率：三档循环，文字跟着走（只对数断言，不依赖 × 两边空格的写法）
	var res := video_button("分辨率：")
	check(res.text.contains("1280") and res.text.contains("720"), "分辨率初始档不对：" + res.text)
	await click(res)
	check(video_button("分辨率：").text.contains("1600") and video_button("分辨率：").text.contains("900"),
		"分辨率没走到第二档：" + video_button("分辨率：").text)
	check(int(VideoCfg.read().resolution) == 1, "分辨率没存进 cfg")
	await click(video_button("分辨率："))
	check(video_button("分辨率：").text.contains("1920") and video_button("分辨率：").text.contains("1080"),
		"分辨率没走到第三档：" + video_button("分辨率：").text)
	await click(video_button("分辨率："))
	check(video_button("分辨率：").text.contains("1280") and video_button("分辨率：").text.contains("720"),
		"分辨率没循环回第一档：" + video_button("分辨率：").text)

	# 全屏：真翻窗口模式，再翻回来（这一下会真的全屏，是功能在生效）
	await click(video_button("全屏："))
	check(video_button("全屏：").text.contains("开"), "全屏按钮文字没翻过来")
	check(bool(VideoCfg.read().fullscreen), "全屏没存进 cfg")
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "全屏没真的套到窗口上")
	await frames(4)
	await click(video_button("全屏："))
	check(video_button("全屏：").text.contains("关"), "全屏没翻回去")
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "窗口没回到窗口模式")

	# 设置弹窗全程只有一个，没有叠层
	check(main.modal_count() == 1, "测到后面设置弹窗叠层了：%d" % main.modal_count())

	print("设置界面验收：%d 项检查，%d 处失败" % [checks, failures])
	_quit()


# ---------- 工具 ----------

func _on_toast(text: String) -> void:
	toasts.append(text)


## 按中文名找按键行，取行里的键名 Label / 改键按钮（行 = [名字, 键名, 空, 按钮]）
func key_row(label_text: String) -> HBoxContainer:
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text in ["改键", "按下新键…"]:
			var row: HBoxContainer = b.get_parent()
			if row != null and row.get_child_count() >= 4 and row.get_child(0) is Label \
					and str((row.get_child(0) as Label).text) == label_text:
				return row
	return null


func keys_label_text(label_text: String) -> String:
	var row := key_row(label_text)
	return str((row.get_child(1) as Label).text) if row != null else ""


func rebind_button(label_text: String) -> Button:
	var row := key_row(label_text)
	return row.get_child(row.get_child_count() - 1) as Button if row != null else null


func text_button(prefix: String) -> Button:
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and (b.text == prefix or b.text.begins_with(prefix)):
			return b as Button
	return null


## 画面三项的按钮（按前缀找：分辨率 / 全屏 / 垂直同步）
func video_button(prefix: String) -> Button:
	return text_button(prefix)


## 推一个物理按键（捕获节点收它）。真实按键事件 physical/keycode 都带。
func push_key(key: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(6)


## 控件矩形是画布（视口）空间，推送的鼠标位置要走窗口空间：aspect=expand 下按
## 覆盖缩放 + 居中偏移换算。窗口没变尺寸时是恒等（早期各测试都在这个前提下跑的）。
func to_window(canvas_point: Vector2) -> Vector2:
	var vp := get_viewport()
	var canvas_size := vp.get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return canvas_point
	var scalev: float = maxf(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var offset: Vector2 = (window_size - canvas_size * scalev) * 0.5
	return canvas_point * scalev + offset


func hover(c: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = to_window(c.get_global_rect().get_center())
	get_viewport().push_input(motion)
	await frames(2)


func click(c: Control) -> void:
	if not check(c != null, "找不到可点的控件"):
		return
	# 行可能在滚动容器里，先滚到能看见
	var sc: ScrollContainer = null
	var ancestor: Node = c.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			sc = ancestor as ScrollContainer
			break
		ancestor = ancestor.get_parent()
	if sc != null:
		sc.ensure_control_visible(c)
		await frames(3)
		# ensure 只保证"刚能看见"，中心可能还在可视区外；不满足就直接滚到居中
		if not sc.get_global_rect().has_point(c.get_global_rect().get_center()):
			var target: int = sc.scroll_vertical + int(c.get_global_rect().get_center().y - sc.get_global_rect().get_center().y)
			sc.scroll_vertical = clampi(target, 0, maxi(0, int(sc.get_v_scroll_bar().max_value)))
			await frames(3)
	var center: Vector2 = c.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(center), "点击目标在视口外")
	var point: Vector2 = to_window(center)
	await hover(c)
	await frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	get_viewport().push_input(press)
	await frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	get_viewport().push_input(release)
	await frames(6)


func _quit() -> void:
	# 测试动过真配置：按键回默认（删 cfg），画面回默认
	InputCfg.restore()
	VideoCfg.save(VideoCfg.defaults())
	VideoCfg.apply(VideoCfg.defaults())
	for path in [Game.save_path, Game.meta_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.queue_free()
	await frames(4)
	get_tree().quit(0 if failures == 0 else 1)
