extends Node
## 窗口输入验收：Esc 关闭最上层可关闭弹窗，同时保护强制选择和按键重绑。
## tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/modal_escape.tscn

const InputCfg = preload("res://scripts/core/input_cfg.gd")

var main: Control
var checks := 0
var failures := 0
var confirmed := 0
var leaked := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		leaked += 1


func push_escape(pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	event.echo = echo
	get_viewport().push_input(event)
	await frames()


func empty_body(_body: VBoxContainer) -> void:
	pass


func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://modal-escape-%d.json" % OS.get_process_id()
	Game.meta_path = "user://modal-escape-meta-%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
	await frames(8)

	# 底层确认按钮绑定 Esc：关闭弹窗的同一次输入不能顺带确认。
	var button := Button.new()
	button.text = "底层确认"
	var shortcut := Shortcut.new()
	var shortcut_event := InputEventKey.new()
	shortcut_event.keycode = KEY_ESCAPE
	shortcut.events = [shortcut_event]
	button.shortcut = shortcut
	button.pressed.connect(func(): confirmed += 1)
	main.add_child(button)
	main.open_modal("one", "普通弹窗", empty_body)
	await frames()
	await push_escape()
	check(not main.has_modal("one"), "Esc 未关闭普通弹窗")
	check(confirmed == 0 and leaked == 0, "关闭弹窗的 Esc 穿透触发了底层确认或输入")
	await push_escape(false)

	main.open_modal("bottom", "底层", empty_body)
	main.open_modal("top", "上层", empty_body)
	await frames()
	await push_escape()
	check(main.has_modal("bottom") and not main.has_modal("top"), "Esc 未仅关闭最上层")
	await push_escape(true, true)
	check(main.has_modal("bottom"), "按住 Esc 的重复事件关闭了下一层")
	await push_escape(false)
	await push_escape()
	check(not main.has_modal("bottom"), "再次按 Esc 未关闭剩余弹窗")
	await push_escape(false)

	main.open_modal("bottom", "底层", empty_body)
	main.open_modal("locked", "必须选择", empty_body, false)
	await frames()
	await push_escape()
	check(main.has_modal("locked") and main.has_modal("bottom"), "Esc 绕过不可关闭的最上层")
	check(confirmed == 0 and leaked == 0, "不可关闭弹窗让 Esc 穿透")
	await push_escape(false)
	main.close_modal("locked")
	main.close_modal("bottom")

	# 存档备份中的文件选择器是独立 Window，Esc 应先由该窗口消费。
	Dialogs.save_pack()
	Dialogs._pick_load_path()
	await frames(8)
	var file_dialog: FileDialog
	for child in Dialogs.get_children():
		if child is FileDialog and child.visible:
			file_dialog = child
			break
	check(file_dialog != null, "未打开存档文件选择器")
	if file_dialog != null:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = true
		Input.parse_input_event(event)
		await frames(8)
		check(not is_instance_valid(file_dialog) or not file_dialog.visible, "Esc 未关闭存档文件选择器")
		check(main.has_modal("save_pack"), "关闭文件选择器时底层存档备份也被关闭")
		await push_escape(false)
		await push_escape()
		check(not main.has_modal("save_pack"), "第二次按 Esc 未关闭存档备份")
		await push_escape(false)

	# 用真实设置界面的捕获器，仅取消操作，不改写真实玩家键位或配置。
	var keys_before := InputCfg.snapshot()
	Dialogs.settings(false)
	await frames()
	var row: HBoxContainer
	for candidate in main.find_children("*", "Button", true, false):
		if candidate.text == "改键" and candidate.get_parent().get_child(0).text == "翻找 / 查看":
			row = candidate.get_parent()
			break
	check(row != null, "设置中找不到改键行")
	if row != null:
		Dialogs._start_rebind("interact", row.get_child(1), row)
		check(Dialogs._capture.active, "未进入改键状态")
		await push_escape()
		check(main.has_modal("settings") and not Dialogs._capture.active, "重绑时 Esc 没有先取消重绑并保留设置")
		check(InputCfg.snapshot() == keys_before, "取消改键改变了绑定")
		await push_escape(false)
		await push_escape()
		check(not main.has_modal("settings"), "取消改键后再次按 Esc 未关闭设置")
		await push_escape(false)
	check(confirmed == 0 and leaked == 0, "设置中的 Esc 穿透到底层")
	print("弹窗 Esc 验收：%d 项检查，%d 处失败" % [checks, failures])
	main.queue_free()
	await frames()
	get_tree().quit(0 if failures == 0 else 1)
