extends Node
## 真实 1280×720 窗口：试玩三问的入口、草稿、错误和本地导出。
## 使用隔离 APPDATA/LOCALAPPDATA 运行，不连接服务；中文键事件不代表真实输入法验收。

const State = preload("res://scripts/core/state.gd")
const Report = preload("res://scripts/core/playtest_report.gd")
const KEYS := ["annoying", "unclear", "pacing"]

var main: Control
var checks := 0
var failures := 0
var finished := 0
var starting_dirs := PackedStringArray()
var original_save := ""
var original_meta := ""


func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(func():
		push_error("playtest_feedback_ui 超时")
		get_tree().quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("此测试需要真实窗口；headless 不能验证鼠标点击。")
		get_tree().quit(1)
		return
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.save_path = "user://feedback-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://feedback-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = ""
	original_save = Game.save_path
	original_meta = Game.meta_path
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = {}
	Game.snapshots = {}
	Game.go("title")
	starting_dirs = report_dirs()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(10)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var selected := 0
	for test in [test_entries, test_draft_refresh_cancel, test_blank_export, test_filled_export_duplicate, test_failure_retry, test_length_limit, test_scroll, test_scene_reset]:
		if only != "" and str(test.get_method()) != only: continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0:
		check(selected > 0 and finished == selected, "测试中途退出：只完成 %d/%d" % [finished, selected])
	await close_modals()
	Game.save_path = original_save
	Game.meta_path = original_meta
	for dir in report_dirs():
		if dir not in starting_dirs: cleanup_report(dir)
	main.queue_free()
	await frames(4)
	print("[playtest_feedback_ui] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames(count := 5) -> void:
	for k in count: await get_tree().process_frame


func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames(3)


func fixture(screen := "pre") -> void:
	await close_modals()
	Game.run = State.new_run("scholar", Game.meta, 73105)
	Game.snapshots = {}
	Game.run.director.enabled = false
	if screen == "title":
		Game.run = {}
	elif screen == "dead":
		Game.run.phase = "dead"
		Game.run.attrs.hp = 0
		Game.run.death_cause = "试玩反馈测试夹具"
	elif screen == "ending":
		Game.run.phase = "ending"
		Game.run.pday = 20
		Game.run.kills = 15
		Game.run.waves_survived = 7
	Game.go(screen)
	await frames(10)


func form() -> Control:
	return main._modals.get("playtest_feedback")


func edits() -> Dictionary:
	var out := {}
	if form() == null: return out
	for edit in form().find_children("*", "TextEdit", true, false):
		if edit.has_meta("feedback_key"):
			out[str(edit.get_meta("feedback_key"))] = edit
	return out


func tagged(root: Node, key: String) -> Button:
	if root == null: return null
	for button in root.find_children("*", "Button", true, false):
		if button.has_meta(key) and bool(button.get_meta(key)): return button
	return null


func named_button(root: Node, text: String) -> Button:
	for button in root.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null


func report_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	var parent := DirAccess.open("user://reports")
	if parent == null: return out
	for dir in parent.get_directories(): out.append("user://reports".path_join(dir))
	out.sort()
	return out


func new_report_dirs(before: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for dir in report_dirs():
		if dir not in before: out.append(dir)
	return out


func cleanup_report(path: String) -> void:
	# 只处理本次导出的平面报告目录；不递归、不碰运行前已有目录。
	if path in starting_dirs: return
	var dir := DirAccess.open(path)
	if dir == null: return
	for file in dir.get_files(): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func texts(root: Node) -> String:
	var out := []
	if root == null: return ""
	for label in root.find_children("*", "Label", true, false): out.append(label.text)
	return "\n".join(out)


func facts() -> Array:
	return [Game.run.duplicate(true), Game.meta.duplicate(true), Game.snapshots.duplicate(true), Game.save_notice]


func reveal(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null and parent != main:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames(3)


func click(control: Control) -> void:
	if control == null:
		check(false, "找不到可点击的控件")
		return
	await reveal(control)
	var pos := control.get_global_rect().get_center()
	check(control.is_visible_in_tree() and get_viewport().get_visible_rect().has_point(pos), "按钮/输入框不在可点击视口内")
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion)
	await frames(1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		get_viewport().push_input(event)
		await frames(1)
	await frames(5)


func escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		get_viewport().push_input(event)
		await frames(2)


func type_unicode(edit: TextEdit, value: String) -> void:
	await click(edit)
	for character in value:
		var event := InputEventKey.new()
		event.pressed = true
		if character == "\n":
			event.keycode = KEY_ENTER
			event.physical_keycode = KEY_ENTER
		else:
			event.unicode = character.unicode_at(0)
		get_viewport().push_input(event)
		event = event.duplicate()
		event.pressed = false
		get_viewport().push_input(event)
		await frames(1)
	await frames(3)


func put(edit: TextEdit, value: String) -> void:
	edit.select_all()
	edit.insert_text_at_caret(value)
	await frames(3)


func open_form() -> void:
	Dialogs.playtest_feedback()
	await frames(5)
	check(form() != null and edits().size() == 3, "三问表单未打开/缺少输入框")


func test_entries() -> void:
	for screen in ["title", "dead", "ending", "settings"]:
		await fixture("pre" if screen == "settings" else screen)
		var before := report_dirs()
		var entry: Button
		if screen == "settings":
			Dialogs.settings(true)
			await frames(5)
			entry = tagged(main._modals.get("settings"), "feedback_entry")
		else:
			entry = named_button(main._screen, "导出试玩报告")
		check(entry != null, "%s 缺少反馈入口" % screen)
		if entry == null: return
		await click(entry)
		check(form() != null and edits().size() == 3, "%s 入口没有打开三问" % screen)
		if form() == null: return
		for key in KEYS:
			check(edits().has(key) and edits()[key].text == "", "%s 入口草稿有遗漏或串局" % screen)
		await click(tagged(form(), "feedback_cancel"))
		check(form() == null and report_dirs() == before, "%s 取消却导出文件" % screen)
		if screen == "settings": check(main.has_modal("settings"), "取消反馈关闭了底层设置")
	finished += 1


func test_draft_refresh_cancel() -> void:
	await fixture()
	var before := report_dirs()
	var unchanged := facts()
	await open_form()
	var answers := {"annoying": "找水很烦\n第二行", "unclear": "门为什么坏？\n# 原话", "pacing": "第八天开始重复。"}
	await type_unicode(edits().annoying, answers.annoying)
	check(edits().annoying.text == answers.annoying, "中文/换行键事件没有进入输入框")
	for key in ["unclear", "pacing"]: await put(edits()[key], answers[key])
	Game.changed.emit()
	await frames(8)
	for key in KEYS: check(edits()[key].text == answers[key], "弹窗刷新丢失草稿：%s" % key)
	check(facts() == unchanged, "填写/刷新修改了本局或底稿")
	await click(tagged(form(), "feedback_cancel"))
	check(form() == null and report_dirs() == before, "取消草稿写出了报告")
	await open_form()
	for key in KEYS: check(edits()[key].text == "", "取消后新表单残留旧草稿")
	await click(edits().annoying)
	await escape()
	check(form() == null and report_dirs() == before, "输入框聚焦时 Esc 没取消/产生文件")
	finished += 1


func test_blank_export() -> void:
	await fixture("title")
	var before := report_dirs()
	var unchanged := facts()
	await open_form()
	await click(tagged(form(), "feedback_submit"))
	check(form() == null and main.has_modal("playtest_report"), "空答不能直接导出/未展示结果")
	var created := new_report_dirs(before)
	check(created.size() == 1, "空答导出没有独占一份报告")
	if created.size() != 1: return
	var report := FileAccess.get_file_as_string(created[0].path_join("report.md"))
	check(report.count("未填写") >= 3, "空答报告没有明确三问未填写")
	check(report.contains("当前没有在进行的局"), "标题空局报告虚称存在本局")
	check(facts() == unchanged, "空答导出改写了局面/底稿/告警")
	finished += 1


func test_filled_export_duplicate() -> void:
	await fixture()
	Game.save_notice = "反馈前已有告警"
	var before := report_dirs()
	var unchanged := facts()
	await open_form()
	var answers := {"annoying": "米不够了。\n```\n# 这只是玩家原话\n```", "unclear": "同院人的约定怎么看？", "pacing": "还没玩完，暂不判断。"}
	for key in KEYS: await put(edits()[key], answers[key])
	await shot("filled-form")
	var submit := tagged(form(), "feedback_submit")
	if submit == null:
		check(false, "填写后没有提交按钮")
		return
	var callbacks := []
	for connection in submit.pressed.get_connections(): callbacks.append(connection.callable)
	check(not callbacks.is_empty(), "提交按钮未接入导出")
	await click(submit)
	for callback in callbacks:
		if callback.is_valid(): callback.call()
	await frames(5)
	check(form() == null and main.has_modal("playtest_report"), "填写成功后未关闭表单/显示结果")
	var created := new_report_dirs(before)
	check(created.size() == 1, "同一次提交的重复回调产生了多份报告")
	if created.size() != 1: return
	var report := FileAccess.get_file_as_string(created[0].path_join("report.md"))
	for key in KEYS: check(report.contains(answers[key]), "导出丢失玩家原文：%s" % key)
	check(report.contains("玩家自述"), "玩家回答与客观记录没有区分")
	check(facts() == unchanged, "填写导出改变了原局/底稿/快照/告警")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "反馈导出写入了原存档路径")
	await shot("export-result")
	finished += 1


func test_failure_retry() -> void:
	await fixture()
	var before := report_dirs()
	var unchanged := facts()
	await open_form()
	var answer := "别丢这段话\n写失败以后还要继续。"
	await put(edits().annoying, answer)
	# 附件与 report.md 同名，触发真实失败；只改测试进程的路径，不接触原档。
	Game.save_path = "user://report.md"
	await click(tagged(form(), "feedback_submit"))
	check(form() != null and main.has_modal("playtest_report"), "失败后表单被关闭/没有错误结果")
	check(texts(main._modals.get("playtest_report")).contains("没导出来"), "失败却显示成功")
	if form() == null:
		Game.save_path = original_save
		return
	await escape()
	check(form() != null and not main.has_modal("playtest_report"), "关闭错误结果时丢失了反馈表单")
	check(edits().annoying.text == answer, "失败后丢失玩家草稿")
	Game.save_path = original_save
	await click(tagged(form(), "feedback_submit"))
	check(form() == null and main.has_modal("playtest_report"), "修正写入条件后不能重试")
	var success_reports := 0
	for dir in new_report_dirs(before):
		if FileAccess.file_exists(dir.path_join(original_save.get_file())):
			success_reports += 1
			check(FileAccess.get_file_as_string(dir.path_join("report.md")).contains(answer), "重试报告没有保留原文")
	check(success_reports == 1, "失败重试未产生唯一成功报告")
	check(facts() == unchanged, "导出失败/重试改变了原局或告警")
	finished += 1


func test_length_limit() -> void:
	await fixture()
	var before := report_dirs()
	await open_form()
	var overlong := "问".repeat(4001)
	await put(edits().annoying, overlong)
	check(edits().annoying.text == overlong, "超长输入被静默截断")
	check(texts(form()).contains("4000"), "超长没有明确说明 4000 字上限")
	var submit := tagged(form(), "feedback_submit")
	if submit != null and not submit.disabled:
		await click(submit)
		if main.has_modal("playtest_report"): await escape()
	check(form() != null and report_dirs() == before, "超长提交产生报告/丢失表单")
	if form() == null: return
	check(edits().annoying.text == overlong, "超长拒绝后丢失原文")
	await put(edits().annoying, "问".repeat(4000))
	submit = tagged(form(), "feedback_submit")
	check(submit != null and not submit.disabled, "修正至 4000 字后仍不能提交")
	await click(submit)
	check(form() == null and new_report_dirs(before).size() == 1, "正好 4000 字未能导出")
	finished += 1


func test_scroll() -> void:
	await fixture()
	await open_form()
	var modal: Control = form()
	var viewport := get_viewport().get_visible_rect()
	var scrolls := modal.find_children("*", "ScrollContainer", true, false)
	check(not scrolls.is_empty(), "反馈表单没有滚动容器")
	if scrolls.is_empty(): return
	var scroll := scrolls[0] as ScrollContainer
	check(viewport.encloses(scroll.get_global_rect()), "三问滚动区域超出 720 高视口")
	var overflow := scroll.get_v_scroll_bar().max_value > scroll.size.y + 1
	if overflow:
		var pos := scroll.get_global_rect().position + Vector2(5, 5)
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		get_viewport().push_input(motion)
		await frames(1)
		for k in 8:
			for pressed in [true, false]:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_WHEEL_DOWN
				event.position = pos
				event.pressed = pressed
				get_viewport().push_input(event)
				await frames(1)
		await frames(4)
		check(scroll.scroll_vertical > 0, "鼠标滚轮不能查看第三问")
	await click(edits().pacing)
	check(edits().pacing.has_focus(), "第三问无法实际点击输入")
	await shot("form-bottom")
	await click(tagged(form(), "feedback_cancel"))
	check(form() == null, "滚动后取消按钮无法点击")
	finished += 1


func test_scene_reset() -> void:
	await fixture()
	var before := report_dirs()
	await open_form()
	await shot("form")
	await put(edits().annoying, "上一局的草稿")
	Game.go("title")
	await frames(10)
	check(form() == null and report_dirs() == before, "离开场景保留了旧表单/导出了文件")
	Game.run = State.new_run("escort", Game.meta, 84106)
	Game.go("pre")
	await frames(10)
	await open_form()
	for key in KEYS: check(edits()[key].text == "", "换局后串入上一局草稿")
	await escape()
	finished += 1


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "res://build/feedback-qa/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var picture := get_viewport().get_texture().get_image()
	check(picture.save_png(dir.path_join(name + ".png")) == OK, "截图失败：" + name)
