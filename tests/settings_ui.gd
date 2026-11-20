extends Node
## 设置界面的鼠标 + 键盘验收：按键重绑全流程（改键 / 冲突 / 取消 / 恢复默认）与画面三项。
## 鼠标走视口路由、改键靠捕获节点收键，必须在窗口下跑：
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/settings_ui.tscn

const InputCfg = preload("res://scripts/core/input_cfg.gd")
const VideoCfg = preload("res://scripts/core/video_cfg.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
const Home = preload("res://scripts/core/home.gd")

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
	await get_tree().process_frame
	get_tree().root.add_child(main)
	get_tree().current_scene = main
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

	await check_courtyard_hotkeys()
	print("设置界面验收：%d 项检查，%d 处失败" % [checks, failures])
	_quit()


func courtyard() -> void:
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 4242)
	Pre.start_disaster(Game.run)
	Game.speed = 0
	Game.go("post")
	await frames(8)


func check_courtyard_hints(journal: String, inventory: String, wait_key: String) -> void:
	var pending: Label = main._screen.hud.find_child("NpcPendingSubtitle", true, false)
	var count := Dialogs.npc_pending_count(Game.run)
	check(pending.is_visible_in_tree() and pending.text == ("邻人待回话 %d · %s" % [count, journal] if count else journal),
		"劫余录按键或邻人待回话提示不对：" + pending.text)
	var seal: Button = main._screen._live.inventory_seal
	check(seal.is_visible_in_tree() and seal.tooltip_text == "存货（%s）" % inventory, "存货印章提示不对：" + seal.tooltip_text)
	var wait_button := text_button("等一刻")
	check(wait_button.tooltip_text.ends_with("快捷键 %s。" % wait_key), "等一刻提示不对：" + wait_button.tooltip_text)


func exercise_courtyard_keys(journal: int, inventory: int, wait_key: int) -> void:
	await push_key(journal)
	check(main.has_modal("journal"), "按显示的劫余录键没有开卷")
	await push_key(KEY_ESCAPE)
	await push_key(inventory)
	check(main.has_modal("inventory"), "按显示的存货键没有打开存货")
	await push_key(KEY_ESCAPE)
	var before := int(Game.run.t)
	await push_key(wait_key)
	check(int(Game.run.t) > before, "按 %s 后时间停在 %d，当前事件为 %s" % [OS.get_keycode_string(wait_key), before, Game.run.pending_event])


func exercise_move_and_pause(rotate_key: int, cancel_key: int, pause_key: int) -> void:
	var rotate_name := OS.get_keycode_string(rotate_key)
	var cancel_name := OS.get_keycode_string(cancel_key)
	main._screen._start_move(int(Home.core(Game.run, "bed").uid))
	await frames()
	check(str(toasts.back()).ends_with("（%s 转方向，%s 取消）" % [rotate_name, cancel_name]), "挪动家具的提示键不对")
	check(main._screen._live.place.visible and main._screen._live.place.text.ends_with("%s 转向 · %s 取消" % [rotate_name, cancel_name]), "摆放中的转向、取消键不对")
	var rotation := int(Game.placing_rot)
	await push_key(rotate_key)
	check(Game.placing_rot == (rotation + 90) % 360, "按显示的转向键没有旋转家具")
	await push_key(cancel_key)
	check(Game.placing.is_empty() and main.modal_count() == 0, "按显示的取消键没有结束摆放")
	check(main._screen._live.speed_status.text == "已暂停（按 %s 继续）" % OS.get_keycode_string(pause_key), "暂停提示键不对")
	await push_key(pause_key)
	check(Game.speed == 1, "按显示的继续键没有恢复时间")
	await push_key(pause_key)
	check(Game.speed == 0, "再按一次没有暂停")


func start_fight_and_guard(key: int) -> void:
	Game.run.fight = NightFight.begin(1, true, Game.run)
	Game.refresh()
	await frames()
	check(main._screen._live.guard_hint.text.begins_with("%s / 右键：架刀" % OS.get_keycode_string(key)), "架刀提示键不对")
	await push_key(key)
	check(float(Game.run.fight.block_cd) > 0.0, "按显示的架刀键没有进入格挡冷却")


func check_courtyard_hotkeys() -> void:
	await courtyard()
	check_courtyard_hints("J", "I", "Q")
	await push_key(KEY_ESCAPE)
	for pair in [["劫余录", KEY_Y], ["行囊", KEY_H], ["等一刻（跳到下个节点）", KEY_U],
			["招架", KEY_V], ["转个方向", KEY_B], ["取消 / 设置", KEY_M], ["暂停 / 继续", KEY_P]]:
		await click(rebind_button(pair[0]))
		await push_key(pair[1])
	await push_key(KEY_ESCAPE)
	check_courtyard_hints("Y", "H", "U")
	var before := int(Game.run.t)
	for old_key in [KEY_J, KEY_I, KEY_Q]:
		await push_key(old_key)
	check(main.modal_count() == 0 and int(Game.run.t) == before, "改键后旧键仍触发宅院操作")
	await exercise_move_and_pause(KEY_B, KEY_M, KEY_P)
	await start_fight_and_guard(KEY_V)
	check_courtyard_hints("点印翻阅", "H", "U")
	var journal_seal: Button
	for button in main._screen.hud.find_children("*", "Button", true, false):
		if button.tooltip_text == "劫余录":
			journal_seal = button
			break
	await click(journal_seal)
	check(main.has_modal("journal"), "战时点击劫余录印章没有开卷")
	await push_key(KEY_ESCAPE)
	var foe: Dictionary = Game.run.fight.foes[0]
	foe.x = main._screen.player.global_position.x
	foe.z = main._screen.player.global_position.z
	await push_key(KEY_Y)
	check(main.modal_count() == 0 and int(foe.hp) == 1, "战时按劫余录键应当挥刀")
	Game.run.fight = {}
	await exercise_courtyard_keys(KEY_Y, KEY_H, KEY_U)
	await courtyard()
	Game.run.pday = 2
	Game.run.t = Post.DAY + 120
	Post.trade_refresh(Game.run)
	await frames()
	check(Dialogs.npc_pending_count(Game.run) > 0, "缺少邻人待回话的真实状态")
	check_courtyard_hints("Y", "H", "U")
	await push_key(KEY_M)
	await click(text_button("按键全部恢复默认"))
	await push_key(KEY_ESCAPE)
	check_courtyard_hints("J", "I", "Q")
	# 第二日 08:00 的求药事件会在原地拦下等候。用与改绑相同的清晨验证恢复后的三个动作。
	await courtyard()
	await exercise_move_and_pause(KEY_R, KEY_ESCAPE, KEY_SPACE)
	await start_fight_and_guard(KEY_K)
	Game.run.fight = {}
	await exercise_courtyard_keys(KEY_J, KEY_I, KEY_Q)


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
	await frames(1)
	var release := ev.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await frames(5)


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
