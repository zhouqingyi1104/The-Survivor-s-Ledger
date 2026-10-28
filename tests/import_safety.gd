extends Node

const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")

var checks := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)

func put(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_string(content)
	f.close()

func _ready() -> void:
	# This test must run with isolated APPDATA and LOCALAPPDATA.
	Game.save_path = "user://import_safety_save.json"
	Game.meta_path = "user://import_safety_meta.json"
	Game.memory_path = "user://import_safety_memory.md"
	Game.no_save = false
	Game.meta = State.new_meta()
	var old := State.new_run("scholar", Game.meta, 701)
	var incoming := State.new_run("herbalist", Game.meta, 702)
	var future := old.duplicate(true)
	future.version = int(old.version) + 100
	var future_pack := SavePack.to_text(SavePack.pack({"run": future, "snapshots": {}}, "future", "test"))
	check(not SavePack.parse(future_pack).ok, "未来版本局不能错误导入")
	var future_snapshot := SavePack.to_text(SavePack.pack({"run": old, "snapshots": {"1": future}}, "future", "test"))
	check(not SavePack.parse(future_snapshot).ok, "未来版本快照不能错误导入")
	for field in ["role", "phase", "home", "attrs", "flags", "explore", "plots"]:
		var broken := incoming.duplicate(true)
		broken.erase(field)
		var bad_pack := SavePack.to_text(SavePack.pack({"run": broken, "snapshots": {}}, "test", "test"))
		check(not SavePack.parse(bad_pack).ok, "缺失 %s 应拒绝导入" % field)
	var broken_snapshot := SavePack.to_text(SavePack.pack({"run": old, "snapshots": {"1": {"version": 21}}}, "test", "test"))
	check(not SavePack.parse(broken_snapshot).ok, "无法使用的快照应拒绝导入")
	var missing_hp := incoming.duplicate(true)
	missing_hp.attrs.erase("hp")
	check(not SavePack.parse(SavePack.to_text(SavePack.pack({"run": missing_hp, "snapshots": {}}, "test", "test"))).ok, "缺少气血应拒绝导入")
	var fractional_time := incoming.duplicate(true)
	fractional_time.t = 1.5
	check(not SavePack.parse(SavePack.to_text(SavePack.pack({"run": fractional_time, "snapshots": {}}, "test", "test"))).ok, "非整数时间应拒绝导入")
	var old_save := {"run": old, "snapshots": {}}
	var new_save := {"run": incoming, "snapshots": {}}
	var pack := "user://import_safety.jyz"
	put(pack, SavePack.to_text(SavePack.pack(new_save, "test", "test")))
	var dir := ProjectSettings.globalize_path("user://backups")
	var main := Game.save_path
	var bak := main + SaveFile.BAK
	var tmp := ProjectSettings.globalize_path(main + SaveFile.TMP)
	Game.no_save = true
	Game.run = {}
	var dry := Game.import_save_from(pack)
	check(not dry.ok and Game.run.is_empty(), "禁止写盘时不能假报导入成功")
	Game.no_save = false

	# A blocked backup directory rejects takeover before changing memory or disk.
	Game.run = old.duplicate(true)
	Game.snapshots = {}
	put(main, JSON.stringify(old_save))
	var original := FileAccess.get_file_as_string(main)
	var invalid_path := "user://invalid_import.jyz"
	put(invalid_path, SavePack.to_text(SavePack.pack({"run": missing_hp, "snapshots": {}}, "test", "test")))
	var rejected := Game.import_save_from(invalid_path)
	check(not rejected.ok and Game.run.seed == 701 and FileAccess.get_file_as_string(main) == original, "语义损坏的导入不应接管内存或覆盖磁盘")
	put("user://backups", "not a directory")
	var result := Game.import_save_from(pack)
	check(not result.ok, "备份目录不可创建时应拒绝导入")
	check(Game.run.seed == 701 and FileAccess.get_file_as_string(main) == original, "备份失败改变了原局")
	DirAccess.remove_absolute(dir)

	# A save-write failure must leave the existing memory and the primary and backup intact.
	put(bak, original)
	DirAccess.make_dir_absolute(tmp)
	result = Game.import_save_from(pack)
	check(not result.ok, "目标不能写时不应报告导入成功")
	check(Game.run.seed == 701, "写盘失败改变了内存中的原局")
	check(FileAccess.get_file_as_string(main) == original and FileAccess.get_file_as_string(bak) == original, "写盘失败改变了磁盘原档")
	check(str(result.info.get("backup", "")) != "", "写盘失败仍应给出已成功留存的备份")
	DirAccess.remove_absolute(tmp)

	# Title import with no in-memory run: recoverable backup is an actual JYZ.
	Game.run = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main))
	result = Game.import_save_from(pack)
	check(result.ok and Game.run.seed == 702, "仅备档应允许导入")
	check(typeof(Game.run.t) == TYPE_INT and typeof(Game.run.seed) == TYPE_INT, "导入 JSON 整数必须和续写一样归一化")
	var saved := SavePack.parse(FileAccess.get_file_as_string(str(result.info.get("backup", ""))))
	check(saved.ok and saved.data.run.seed == 701, "仅备档的自动留档应可直接导入原局")

	# Corrupt primary must not hide a valid backup; preserve both files if neither is valid.
	Game.run = {}
	put(main, "{broken")
	put(bak, original)
	result = Game.import_save_from(pack)
	check(result.ok, "损坏主档应采用可读备档")
	saved = SavePack.parse(FileAccess.get_file_as_string(str(result.info.get("backup", ""))))
	check(saved.ok and saved.data.run.seed == 701, "损坏主档时应留住有效备档")
	Game.run = {}
	put(main, JSON.stringify({"run": {"role": "missing", "phase": "post"}, "snapshots": {}}))
	put(bak, original)
	result = Game.import_save_from(pack)
	check(result.ok, "语义损坏的主档不应遮住有效备档")
	saved = SavePack.parse(FileAccess.get_file_as_string(str(result.info.get("backup", ""))))
	check(saved.ok and saved.data.run.seed == 701, "语义损坏时应留存可导回的备档")
	Game.run = {}
	put(main, "{broken")
	put(bak, "{also broken")
	result = Game.import_save_from(pack)
	check(not result.ok and FileAccess.get_file_as_string(main) == "{broken" and FileAccess.get_file_as_string(bak) == "{also broken", "两份坏档必须拒绝导入并保留原件")

	# Repeated backups in the same second are distinct and importable.
	Game.run = old.duplicate(true)
	var first: Dictionary = Game._backup_before_import()
	var second: Dictionary = Game._backup_before_import()
	check(first.ok and second.ok and first.path != second.path, "同秒备份不能覆盖")
	check(SavePack.parse(FileAccess.get_file_as_string(first.path)).ok and SavePack.parse(FileAccess.get_file_as_string(second.path)).ok, "重复备份必须均可读取")

	# Import destination follows the same phase/active-exploration routing as Continue.
	Game.run = incoming.duplicate(true)
	check(Game.screen_for_run() == "pre", "备劫导入应回备劫界面")
	Game.run.phase = "post"
	Game.run.explore = {"site": "fixture"}
	check(Game.screen_for_run() == "explore", "现场探索导入应回探索界面")
	Game.run.explore = {}
	check(Game.screen_for_run() == "post", "宅院导入应回宅院")
	Game.run.phase = "dead"
	check(Game.screen_for_run() == "dead", "死局导入应回残页")
	Game.run.phase = "ending"
	check(Game.screen_for_run() == "ending", "结局导入应回结局页")
	print("[import_safety] %d checks, %d failed" % [checks, failed])
	get_tree().quit(0 if failed == 0 else 1)
