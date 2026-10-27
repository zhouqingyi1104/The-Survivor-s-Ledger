extends Node
## 存档导入导出的落盘测试：导→改→导回来→原样恢复；导入前自动留档；坏文件不动现状。
## 运行：godot --headless --path . res://tests/save_pack_io.tscn
## 只用 user:// 下的临时文件；backups/ 里本次新产生的文件跑完删掉（不碰玩家真备份）。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")

var checks := 0
var failures := 0
var pack_path := "user://t_pack_test.jyz"
var before_backups: Array = []


func _ready() -> void:
	Game.save_path = "user://t_pack_save.json"
	Game.meta_path = "user://t_pack_meta.json"
	Game.no_save = false
	Game.meta = State.new_meta()
	Game.run = {}
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	SaveFile.forget(pack_path)
	before_backups = _backup_files()

	# 1. 开一局、推到第 5 日、导出
	check(Game.new_game("herbalist") == "", "开局失败")
	Pre.start_disaster(Game.run)          # 进劫后，才谈得上"第 5 日"
	Game.run.pday = 5
	Game.run.seed = 777001
	Game.run.log.append("【第5日·08:00】导出前的标记。")
	var exported := Game.export_save_to(pack_path)
	check(bool(exported.ok), "导出失败：%s" % str(exported.note))
	check(FileAccess.file_exists(pack_path), "导出后文件不在")
	var parsed := SavePack.parse(FileAccess.get_file_as_string(pack_path))
	check(bool(parsed.ok), "导出的文件自己都读不回来：%s" % str(parsed.note))
	check(int(parsed.data.get("run", {}).get("pday", 0)) == 5, "导出的存档不是第 5 日")

	# 2. 换一局（把内存里的局覆盖掉），再导入回来
	check(Game.new_game("scholar") == "", "第二次开局失败")
	check(str(Game.run.role) == "scholar", "第二次开局没换身份（用例前提）")
	var imported := Game.import_save_from(pack_path)
	check(bool(imported.ok), "导入失败：%s" % str(imported.note))
	check(int(Game.run.pday) == 5, "导入后没回到第 5 日：%d" % int(Game.run.pday))
	check(str(Game.run.role) == "herbalist", "导入后身份不对：%s" % str(Game.run.role))
	check(Game.run.log.has("【第5日·08:00】导出前的标记。"), "导入后日志里的标记丢了")
	check(str(imported.info.get("backup", "")) != "", "导入前没给原来那一卷留档")
	check(FileAccess.file_exists(str(imported.info.get("backup", ""))), "留档文件不在：%s" % str(imported.info.get("backup", "")))

	# 3. 坏文件：拒掉，且不许动现在这一局
	var bad := "user://t_pack_bad.jyz"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"hello\": 1}")
	f.close()
	var rejected := Game.import_save_from(bad)
	check(not bool(rejected.ok), "坏文件竟然导入成功")
	check(str(rejected.note) != "", "坏文件拒绝时没给一句话")
	check(int(Game.run.pday) == 5 and str(Game.run.role) == "herbalist", "坏文件把现有的一局改掉了")
	SaveFile.forget(bad)

	# 4. 不存在的文件
	var missing := Game.import_save_from("user://definitely_not_here.jyz")
	check(not bool(missing.ok), "不存在的文件竟然导入成功")
	check(str(missing.note).contains("找不到"), "缺文件时的话术不对：%s" % str(missing.note))

	# 5. 导入完该落在哪一页
	check(Game.screen_for_run() == "post", "进行中的局应该回宅院：%s" % Game.screen_for_run())
	Game.run.phase = "dead"
	check(Game.screen_for_run() == "dead", "死局应该回残页")
	Game.run.phase = "ending"
	check(Game.screen_for_run() == "ending", "结局应该回结局页")

	_cleanup()
	print("[save_pack_io] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _backup_files() -> Array:
	var out := []
	var d := DirAccess.open("user://backups")
	if d == null: return out
	for name in d.get_files():
		out.append(name)
	return out


func _cleanup() -> void:
	SaveFile.forget(pack_path)
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	# 只删本次新产生的留档，玩家的真备份一条都不碰
	var d := DirAccess.open("user://backups")
	if d != null:
		for name in d.get_files():
			if not before_backups.has(name):
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://backups".path_join(name)))


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
