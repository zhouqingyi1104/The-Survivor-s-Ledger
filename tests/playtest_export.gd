extends Node
## 试玩报告的落盘测试：真导一次，看目录、文件、内容对不对，跑完删干净。
## 运行：godot --headless --path . res://tests/playtest_export.tscn
## 存档路径指向 user:// 下的临时文件；报告目录按时间戳建，跑完整个删掉。

const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Ledger = preload("res://scripts/core/ledger.gd")

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
	# 模拟两次整点存档之间发生的变化：报告必须和当前画面同一时刻，不能抄旧磁盘档。
	var disk_before := FileAccess.get_file_as_string(Game.save_path)
	Pre.start_disaster(Game.run)
	Game.run.pday = 1
	Game.run.home.water = 9
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	Game.run.pday = 2
	Game.run.home.water = 3
	Game.meta.daoxin = 42
	Game.save_notice = "先前存档失败警告"
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
	check(int(copied.get("run", {}).get("pday", 0)) == 2, "导出的是旧磁盘档，未包含当前时间")
	check(int(copied.get("snapshots", {}).get("1", {}).get("home", {}).get("water", -1)) == 9, "导出未包含真实回溯快照")
	check(str(result.get("save_source", "")) == "current", "当前快照来源未说明")
	check(md.contains("内存快照") and md.contains("原存档未改写"), "报告未说明当前快照来源")
	check(_dialog_text(result).contains("本局快照") and _dialog_text(result).contains("原存档未改写"), "界面未说明当前快照")
	var meta_copy = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("report_test_meta.json")))
	check(int(meta_copy.get("daoxin", 0)) == 42, "底稿不是当前内存快照")
	check(FileAccess.get_file_as_string(Game.save_path) == disk_before, "导报告不应改写玩家存档")
	check(Game.save_notice == "先前存档失败警告", "导出报告清掉了已有存档警告")

	# 用报告副本作为隔离的主档走实际续写，再调用真实回溯规则。
	var original_run: Dictionary = Game.run
	var original_snapshots: Dictionary = Game.snapshots
	var original_save := Game.save_path
	var original_meta_path := Game.meta_path
	Game.save_path = "user://report_loaded_test.json"
	Game.meta_path = "user://report_loaded_meta.json"
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	var copy_error := DirAccess.copy_absolute(dir.path_join("report_test_save.json"), ProjectSettings.globalize_path(Game.save_path))
	check(copy_error == OK, "无法复制附件到隔离续写路径")
	Game.run = {}
	Game.snapshots = {}
	check(Game.continue_game(), "报告附件无法通过实际续写流程")
	check(int(Game.run.pday) == 2 and int(Game.run.home.water) == 3, "续写没有恢复当前局面")
	var rewind := Ledger.rewind(Game.run, Game.snapshots, Game.meta.duplicate(true))
	check(not rewind.is_empty() and int(rewind.pday) == 1 and int(rewind.home.water) == 9, "真实回溯无法恢复导出前的快照")
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	Game.save_path = original_save
	Game.meta_path = original_meta_path
	Game.run = original_run
	Game.snapshots = original_snapshots
	Game.save_notice = "先前存档失败警告"
	_cleanup(dir)

	# 报告读取器有按需补字段行为，不能因此改变要导出的快照或内存局面。
	var original_past: Dictionary = Game.run.past_lives
	var original_director: Dictionary = Game.run.director
	Game.run.past_lives = {}
	Game.run.director = {}
	var untouched := Game.export_playtest()
	check(bool(untouched.get("ok", false)), "空状态字段的报告导出失败")
	var untouched_save = JSON.parse_string(FileAccess.get_file_as_string(str(untouched.dir).path_join("report_test_save.json")))
	check(untouched_save.run.past_lives.is_empty() and untouched_save.run.director.is_empty(), "报告读取器改写了导出的局面")
	check(Game.run.past_lives.is_empty() and Game.run.director.is_empty(), "导出报告改写了内存局面")
	Game.run.past_lives = original_past
	Game.run.director = original_director
	_cleanup(str(untouched.dir))

	# 同一秒的重复导出独占不同目录，不覆盖旧报告。
	var one := Game._create_report_dir("collision-test")
	var two := Game._create_report_dir("collision-test")
	check(bool(one.ok) and bool(two.ok) and str(one.dir) != str(two.dir), "同名导出覆盖了已有报告")
	_cleanup(ProjectSettings.globalize_path(str(one.dir)))
	_cleanup(ProjectSettings.globalize_path(str(two.dir)))

	# 在报告目录把目标名占为目录，模拟快照写入失败，不能伪报成功。
	for blocked_name in ["report_test_save.json", "report_test_meta.json"]:
		var created := Game._create_report_dir("write-fail-test")
		var test_dir := str(created.dir)
		var blocked := ProjectSettings.globalize_path(test_dir.path_join(blocked_name))
		check(DirAccess.make_dir_absolute(blocked) == OK, "无法建立写入失败夹具")
		var failed := Game._export_playtest_to(test_dir)
		check(not bool(failed.get("ok", true)), "必要附件写入失败却返回成功：%s" % blocked_name)
		check(str(failed.get("note", "")).contains("写入失败"), "写入失败未告诉玩家原因")
		check(FileAccess.get_file_as_string(Game.save_path) == disk_before, "写入失败修改了玩家存档")
		check(Game.save_notice == "先前存档失败警告", "写入失败清掉已有存档警告")
		DirAccess.remove_absolute(blocked)
		_cleanup(ProjectSettings.globalize_path(test_dir))

	# 标题页没有载入局时，附磁盘主档，但报告不得虚称正在记录磁盘里的局面。
	Game.run = {}
	Game.snapshots = {}
	var title := Game.export_playtest()
	check(bool(title.get("ok", false)), "标题页有磁盘档时导出失败")
	check(str(title.get("save_source", "")) == "disk", "标题页未注明磁盘主档来源")
	var title_dir := str(title.get("dir", ""))
	check(FileAccess.get_file_as_string(title_dir.path_join("report_test_save.json")) == disk_before, "标题页未原样附带磁盘档")
	var title_report := FileAccess.get_file_as_string(title_dir.path_join("report.md"))
	check(title_report.contains("没有读取其局面") and title_report.contains("当前没有在进行的局"), "标题报告虚称描述了磁盘局面")
	check(title_report.contains("动态世情：未载入本局"), "标题报告虚称动态世情开启")
	check(_dialog_text(title).contains("磁盘上已有的主存档"), "界面未说明标题主档来源")
	_cleanup(title_dir)

	# 只有备份时，明确主档缺失，但保留备份供排查。
	var backup_file := FileAccess.open(Game.save_path + SaveFile.BAK, FileAccess.WRITE)
	backup_file.store_string(disk_before)
	backup_file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	var backup_only := Game.export_playtest()
	check(bool(backup_only.get("ok", false)), "仅有备份时导出失败")
	check(str(backup_only.get("save_source", "")) == "none", "仅有备份误称有主档")
	check("report_test_save.json.bak" in backup_only.get("files", []), "仅有备份时漏附备份")
	var backup_md := FileAccess.get_file_as_string(str(backup_only.dir).path_join("report.md"))
	check(backup_md.contains("没有主存档") and backup_md.contains("备份"), "未说明主档缺失及备份情况")
	var backup_ui := _dialog_text(backup_only)
	check(backup_ui.contains("没有可附的主存档") and backup_ui.contains("已附磁盘上的上一份存档备份"), "界面未区别主档缺失和附带备份")
	_cleanup(str(backup_only.dir))

	# 附件存在但复制失败时不能报成功，且继续保留存档告警。
	Game.memory_path = "user://report_memory_test.md"
	var memory_file := FileAccess.open(Game.memory_path, FileAccess.WRITE)
	memory_file.store_string("隔离测试档案")
	memory_file.close()
	for blocked_name in ["report_test_save.json.bak", "Memory.md"]:
		var created := Game._create_report_dir("copy-fail-test")
		var test_dir := str(created.dir)
		var blocked := ProjectSettings.globalize_path(test_dir.path_join(blocked_name))
		check(DirAccess.make_dir_absolute(blocked) == OK, "无法建立复制失败夹具")
		var failed := Game._export_playtest_to(test_dir)
		check(not bool(failed.get("ok", true)) and str(failed.get("note", "")).contains("复制失败"), "附件复制失败未报错：%s" % blocked_name)
		check(_dialog_text(failed).contains("没导出来"), "附件失败未显示在界面")
		check(Game.save_notice == "先前存档失败警告", "复制失败清掉已有存档警告")
		DirAccess.remove_absolute(blocked)
		_cleanup(ProjectSettings.globalize_path(test_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.memory_path))
	Game.memory_path = ""
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("[playtest_export] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _dialog_text(result: Dictionary) -> String:
	var body := VBoxContainer.new()
	Dialogs._playtest_report(body, result)
	var texts := []
	for child in body.get_children():
		if child is Label: texts.append(child.text)
	body.free()
	return "\n".join(texts)


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
