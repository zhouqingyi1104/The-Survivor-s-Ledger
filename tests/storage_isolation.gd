extends Node
## 测试隔离：直接拉起的测试不能把存档写进玩家真实目录。
## 运行：godot --headless --path . res://tests/storage_isolation.tscn
##
## 背景：曾经有一个批次用默认路径写过存档，在玩家的
## `app_userdata/劫余录/` 里留下 `save.json.bak`。`has_save()` 把备份也算数，
## 所以标题界面会以为还有旧卷，停在「另起一卷」的确认上。
## 这条测试盯的是"测试进程的落盘位置"本身，不是某个功能的存档格式。

const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	var temp := OS.get_temp_dir().replace("\\", "/")
	var save := Game.save_path.replace("\\", "/")
	var meta := Game.meta_path.replace("\\", "/")
	var memory := Game.memory_path.replace("\\", "/")

	# 三个落盘位置都得在临时目录里
	check(not save.begins_with("user://"), "save_path 还指着 user://：" + save)
	check(save.begins_with(temp), "save_path 不在临时目录：" + save)
	check(meta.begins_with(temp), "meta_path 不在临时目录：" + meta)
	check(memory.begins_with(temp), "memory_path 不在临时目录：" + memory)
	# memory_path 为空会退到项目根 Memory.md（给 AI 的背景档案），测试不能碰
	check(Game.memory_path != "", "memory_path 为空，测试会写项目根的 Memory.md")
	check(not save.to_lower().contains("app_userdata"), "存档仍落在 app_userdata：" + save)

	# 真写一次，确认文件确实进临时目录
	Game.meta = State.new_meta()
	var written := SaveFile.write(Game.meta_path, {"probe": true})
	check(FileAccess.file_exists(Game.meta_path), "写不进隔离目录：%s" % str(written))
	check(not FileAccess.file_exists("user://probe_isolation.json"), "探针写到了 user:// 根目录")
	SaveFile.forget(Game.meta_path)

	print("测试隔离：%d 项，失败 %d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
