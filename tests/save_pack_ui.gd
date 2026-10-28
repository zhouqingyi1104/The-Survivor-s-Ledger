extends Node
## 导入结果必须留在屏幕上，直到玩家看清备份路径并进入这一卷。
const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")

var failures := 0

func _ready() -> void:
	Game.save_path = "user://ui_import_save.json"
	Game.meta_path = "user://ui_import_meta.json"
	Game.memory_path = "user://ui_import_memory.md"
	Game.no_save = false
	Game.meta = State.new_meta()
	Game.run = {}
	var old_run := State.new_run("scholar", Game.meta, 711)
	var new_run := State.new_run("herbalist", Game.meta, 712)
	SaveFile.write(Game.save_path, {"run": old_run, "snapshots": {}})
	var pack := SavePack.pack({"run": new_run, "snapshots": {}}, "test", "test")
	var path := "user://ui_import.jyz"
	SaveFile.write_text(path, SavePack.to_text(pack))
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Dialogs.save_pack()
	var bad_dialog := FileDialog.new()
	Dialogs.add_child(bad_dialog)
	Dialogs._do_import_save("user://missing-ui-import.jyz", bad_dialog)
	check(main.has_modal("save_pack"), "失败后存档弹窗消失")
	check(not main.has_modal("save_import_result"), "失败却显示成功")
	var file_dialog := FileDialog.new()
	Dialogs.add_child(file_dialog)
	Dialogs._do_import_save(path, file_dialog)
	check(typeof(Game.run.get("hour")) == TYPE_INT, "导入后的备劫时辰不是整数")
	check(main.has_modal("save_import_result"), "成功结果没有停留")
	check(not main.has_modal("save_pack"), "原弹窗仍在")
	check(Game.screen == "title", "玩家阅读前已切换页面")
	var labels := main.find_children("*", "Label", true, false)
	var has_backup := false
	for label in labels:
		if str(label.text).contains("原来那一卷留在这里") and str(label.text).contains(".jyz"):
			has_backup = true
	check(has_backup, "结果页没有可恢复备份的路径")
	var buttons := main.find_children("*", "Button", true, false)
	var entered := false
	for button in buttons:
		if button.text == "进入这一卷":
			entered = true
			button.pressed.emit()
			break
	check(entered, "结果页缺少进入按钮")
	check(not main.has_modal("save_import_result"), "进入后结果页没有关闭")
	check(Game.screen == "pre" and str(Game.run.role) == "herbalist", "没有进入导入的备劫存档")
	print("[save_pack_ui] 失败 %d 处" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
