extends Node

const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Title = preload("res://scripts/ui/screens/title_screen.gd")

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func put(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()

func _ready() -> void:
	# Run under isolated APPDATA/LOCALAPPDATA; never touch the project Memory.md.
	Game.save_path = "user://continue_safety.json"
	Game.meta_path = "user://continue_safety_meta.json"
	Game.memory_path = "user://continue_safety_memory.md"
	Game.no_save = false
	Game.meta = State.new_meta()
	Game.run = {}
	var path: String = Game.save_path
	var backup := path + SaveFile.BAK
	var old := State.new_run("scholar", Game.meta, 701)
	var valid := JSON.stringify({"run": old, "snapshots": {}})
	var bad := JSON.stringify({"run": {"role": "missing", "phase": "post"}, "snapshots": {}})
	put(path, bad)
	put(backup, valid)
	var st := Game.save_status()
	check(not st.main and st.backup, "语义损坏的主档必须被标记，并识别有效备档")
	check(Game.continue_game() and int(Game.run.seed) == 701, "语义损坏主档没有回退到有效备档")
	check(FileAccess.get_file_as_string(backup) == valid, "恢复后唯一有效备份被覆盖")
	check(FileAccess.get_file_as_string(path + ".bad") == bad, "恢复时未保留损坏的主档")
	check(Game.save_notice != "", "回退缺少提示")

	# Failure before replacement must leave both original files byte-for-byte intact.
	Game.run = {}
	put(path, bad)
	put(backup, valid)
	var tmp := ProjectSettings.globalize_path(path + SaveFile.TMP)
	check(DirAccess.make_dir_absolute(tmp) == OK, "未能创建写入失败夹具")
	check(Game.continue_game(), "写入失败不应阻止读取备份")
	check(FileAccess.get_file_as_string(path) == bad and FileAccess.get_file_as_string(backup) == valid, "恢复写入失败更改了原档")
	check(Game._recovering_backup, "写入失败后未保留恢复状态")
	DirAccess.remove_absolute(tmp)
	Game.save_game()
	check(not Game._recovering_backup and FileAccess.get_file_as_string(backup) == valid, "重试保存后未保留有效备份")

	# Inject failure after the bad primary has been parked and tmp has been verified.
	put(path, bad)
	put(backup, valid)
	var replacement := func(_from: String, _to: String) -> int: return ERR_CANT_CREATE
	var failed := SaveFile.write_from_backup(path, {"run": old, "snapshots": {}}, replacement)
	check(not failed.ok and failed.step == "replace", "最终替换失败未报告 replace")
	check(FileAccess.get_file_as_string(path) == bad and FileAccess.get_file_as_string(backup) == valid, "最终替换失败没有恢复主档或移动了有效备档")
	check(not FileAccess.file_exists(path + SaveFile.TMP), "最终替换失败后留下临时档")

	# If another file occupies the destination, keep it and preserve the old primary separately.
	var occupied := func(_from: String, to: String) -> int:
		put(to, "other writer")
		return ERR_CANT_CREATE
	failed = SaveFile.write_from_backup(path, {"run": old, "snapshots": {}}, occupied)
	var kept := str(failed.step).trim_prefix("restore_main: ")
	check(not failed.ok and str(failed.step).begins_with("restore_main: "), "占用目标时未报告坏主档留底位置")
	check(FileAccess.get_file_as_string(path) == "other writer" and FileAccess.get_file_as_string(kept) == bad and FileAccess.get_file_as_string(backup) == valid, "占用目标时文件被覆盖或备份被移动")

	# A future primary must not fall back and overwrite newer progress.
	var future := old.duplicate(true)
	future.version = int(old.version) + 100
	var newer := JSON.stringify({"run": future, "snapshots": {}})
	put(path, newer)
	put(backup, valid)
	Game.run = {}
	Game.go("title")
	check(Game.save_status().future and not Game.continue_game(), "未来版本主档必须拒绝续写")
	check(FileAccess.get_file_as_string(path) == newer and FileAccess.get_file_as_string(backup) == valid, "未来档被续写覆盖")
	var title := Title.new()
	check(title._continue_label() == "续写此录 · 需要新版", "未来版本标题提示不清楚")
	title._discard_and_new()
	check(Game.screen == "title" and FileAccess.get_file_as_string(path) == newer, "未来版本不能通过新开覆盖")
	# Future snapshots and unreadable files must also prevent accidental overwrite.
	put(path, JSON.stringify({"run": old, "snapshots": {"1": future}}))
	check(not Game.continue_game(), "未来版本回溯页不能被旧版本覆盖")
	put(path, bad)
	put(backup, "{broken")
	Game.run = {}
	Game.go("title")
	title._discard_and_new()
	check(Game.screen == "title" and FileAccess.get_file_as_string(path) == bad and FileAccess.get_file_as_string(backup) == "{broken", "坏档仍可通过新开覆盖")
	title.free()
	print("[continue_safety] %d checks, %d failed" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
