extends Node
## 试玩报告的落盘测试：真导一次，看目录、文件、内容对不对，跑完删干净。
## 运行：godot --headless --path . res://tests/playtest_export.tscn
## 存档路径指向 user:// 下的临时文件；报告目录按时间戳建，跑完整个删掉。

const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var checks := 0
var failures := 0


func _ready() -> void:
	Game.save_path = "user://report_test_save.json"
	Game.meta_path = "user://report_test_meta.json"
	Game.no_save = false
	Game.meta = State.new_meta()
	Game.run = {}
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)

	# 1. 没有局也能导：至少底稿与设置
	var empty := Game.export_playtest()
	check(bool(empty.get("ok", false)), "空档导出失败：%s" % str(empty.get("note", "")))
	check(str(empty.get("dir", "")) != "", "空档导出没给路径")
	_cleanup(str(empty.get("dir", "")))

	# 2. 开一局再导：报告 + 存档 + 底稿都要在，内容要对得上
	var err := Game.new_game("escort")
	check(err == "", "开局失败：%s" % err)
	var result := Game.export_playtest()
	check(bool(result.get("ok", false)), "导出失败：%s" % str(result.get("note", "")))
	var dir := str(result.get("dir", ""))
	check(DirAccess.dir_exists_absolute(dir), "报告目录没建出来：%s" % dir)
	var files: Array = result.get("files", [])
	for want in ["report.md", "report_test_save.json", "report_test_meta.json"]:
		check(want in files, "少了文件：%s（实际 %s）" % [want, str(files)])
	var md := FileAccess.get_file_as_string(dir.path_join("report.md"))
	check(md.contains("镖局趟子手"), "报告里没写身份")
	check(md.contains(str(Game.run.seed)), "报告里没写种子")
	check(md.contains("请顺手回答三句"), "报告里没有留给玩家的问题")
	check(not md.contains("C:\\"), "报告把本机路径带出去了")
	# 附上的存档要能原样打开
	var copied = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("report_test_save.json")))
	check(typeof(copied) == TYPE_DICTIONARY, "附上的存档不是合法 JSON")
	check(int(copied.get("run", {}).get("seed", 0)) == int(Game.run.seed), "附上的存档不是这一局")

	_cleanup(dir)
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("[playtest_export] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _cleanup(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir): return
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	# 上一级 reports/ 空着就一起收掉
	var parent := dir.get_base_dir()
	var p := DirAccess.open(parent)
	if p != null and p.get_files().is_empty() and p.get_directories().is_empty():
		DirAccess.remove_absolute(parent)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
