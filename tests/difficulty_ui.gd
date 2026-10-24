extends Node
## 选难度界面的鼠标验收：整张卡点得中、切得动、不叠层，「就这个」把难度带下去。
## 鼠标要走视口路由，必须在窗口下跑（--headless 不收 GUI 输入，悬停探针返回 null，
## 本测试会因此失败并提示）：
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/difficulty_ui.tscn

const State = preload("res://scripts/core/state.gd")

var main: Control
var checks := 0
var failures := 0


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
	Game.save_path = "user://difficulty-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://difficulty-ui-meta-%d.json" % OS.get_process_id()
	Game.meta = State.new_meta()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	Game.pending_role = "scholar"
	Game.go("difficulty")
	await frames(8)
	var screen: Node = main.get_child(1).get_child(0)
	check(screen != null and screen._picked == "normal", "没进选难度界面，或默认没选中寻常年景")
	var mild := card("mild")
	var doom := card("doom")
	check(mild != null and doom != null, "难度卡没都挂上 difficulty_pick（点不动的回归）")
	# 鼠标路由自检：先把话说清楚，别让 headless 下的空结果冒充成界面坏了
	await hover(mild)
	if not check(get_viewport().gui_get_hovered_control() != null,
			"鼠标事件路由不到控件：本测试要在窗口模式下跑（去掉 --headless，加 --rendering-method gl_compatibility）"):
		_quit()
		return
	# 点「暖冬」：选中项、底部按钮、「已选中」标记都要跟着走
	await click(mild)
	check(screen._picked == "mild", "点暖冬卡没选中：_picked=%s" % screen._picked)
	check(text_of("就这个").contains("暖冬"), "底部确认按钮没跟着选中项变：" + text_of("就这个"))
	check(card_id(tag_owner()) == "mild", "「已选中」标记没移到暖冬卡上")
	# 再点「永夜」：换选中项，且界面不能叠层。
	# 卡要按 id 重新找——选中后整屏重画，旧的卡节点已经释放了。
	var labels: int = screen.find_children("*", "Label", true, false).size()
	await click(card("doom"))
	check(screen._picked == "doom", "点永夜卡没选中：_picked=%s" % screen._picked)
	check(screen.find_children("*", "Label", true, false).size() == labels, "每点一次界面就叠一层")
	check(text_of("就这个").contains("永夜"), "底部确认按钮没跟着选中项变：" + text_of("就这个"))
	check(card_id(tag_owner()) == "doom", "「已选中」标记没移到永夜卡上")
	# 「就这个」把选中的难度带给下一屏
	await click(text_button("就这个"))
	check(Game.screen == "challenge" and Game.pending_difficulty == "doom", "难度没带进立愿界面")
	print("选难度界面鼠标验收：%d 项检查，%d 处失败" % [checks, failures])
	_quit()


# ---------- 工具 ----------

func card(id: String) -> Control:
	for n in main.find_children("*", "Control", true, false):
		if n.has_meta("difficulty_pick") and str(n.get_meta("difficulty_pick")) == id:
			return n as Control
	return null


## 卡上记的难度 id（重画后旧节点会释放，只能按 id 认卡，不能存引用）
func card_id(c: Control) -> String:
	if c != null and c.has_meta("difficulty_pick"):
		return str(c.get_meta("difficulty_pick"))
	return ""


func text_button(prefix: String) -> Button:
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.begins_with(prefix):
			return b as Button
	return null


func text_of(prefix: String) -> String:
	var b := text_button(prefix)
	return b.text if b != null else ""


## 「已选中」标记挂在哪个卡上
func tag_owner() -> Control:
	for n in main.find_children("*", "PanelContainer", true, false):
		var tagged := false
		for l in n.find_children("*", "Label", true, false):
			if (l as Label).text == "已选中":
				tagged = true
		if not tagged:
			continue
		var p: Node = n
		while p != null and not (p is Control and (p as Control).has_meta("difficulty_pick")):
			p = p.get_parent()
		return p as Control
	return null


func hover(c: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = c.get_global_rect().get_center()
	get_viewport().push_input(motion)
	await frames(2)


func click(c: Control) -> void:
	if not check(c != null, "找不到可点的控件"):
		return
	var point: Vector2 = c.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(point), "点击目标在视口外")
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
	for path in [Game.save_path, Game.meta_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.queue_free()
	await frames(4)
	get_tree().quit(0 if failures == 0 else 1)
