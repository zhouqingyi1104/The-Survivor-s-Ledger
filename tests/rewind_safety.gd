extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const PostScreen = preload("res://scripts/ui/screens/post_screen.gd")
const Player = preload("res://scripts/world/player.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")

var count := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	count += 1
	if not ok:
		failed += 1
		push_error(message)

func _ready() -> void:
	Game.no_save = false
	Game.save_path = "user://rewind_test_save.json"
	Game.meta_path = "user://rewind_test_meta.json"
	Game.memory_path = "user://rewind_test_memory.md"
	_scenario_meta_failure()
	_scenario_save_failure()
	_scenario_invalid_log()
	_scenario_backup_changes()
	_scenario_meta_middle()
	_scenario_recovery_backup()
	_scenario_demo()
	_scenario_frozen()
	_scenario_existing_temporary_files()
	_scenario_single_notification()
	print("[rewind_safety] %d checks, %d failures" % [count, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _prepare() -> void:
	for path in [Game.save_path, Game.meta_path, Game._rewind_path()]:
		SaveFile.forget(path)
	Game.run = {}
	Game.snapshots = {}
	Game.meta = State.new_meta()
	Game.new_game("scholar")
	Pre.start_disaster(Game.run)
	Game.run.phase = "post"
	Game.run.pday = 2
	Ledger.snapshot(Game.run, Game.snapshots)
	Game.run.phase = "dead"
	Game.save_game()
	Game.go("dead")

func _block_tmp(path: String) -> void:
	check(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + SaveFile.TMP)) == OK, "无法创建故障夹具")

func _unblock_tmp(path: String) -> void:
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + SaveFile.TMP)) == OK, "无法移除故障夹具")

func _scenario_meta_failure() -> void:
	_prepare()
	var initial_run := Game.run.duplicate(true)
	var initial_meta := Game.meta.duplicate(true)
	var initial_meta_bytes := FileAccess.get_file_as_string(Game.meta_path)
	_block_tmp(Game.meta_path)
	Game.rewind()
	check(Game._rewind_pending(), "底稿写入失败必须保留事务")
	check(Game.run == initial_run and Game.meta == initial_meta, "失败时内存不能提前接管回溯")
	check(FileAccess.get_file_as_string(Game.meta_path) == initial_meta_bytes, "底稿失败不应损坏原底稿")
	Game.rewind()
	check(Game._rewind_pending() and Game.run == initial_run, "重复重试不能再次消耗残页")
	_unblock_tmp(Game.meta_path)
	# Simulate a fresh process; _ready must resolve before touching the meta.
	Game.run = {}
	Game.meta = {}
	Game._ready()
	check(not Game._rewind_pending(), "重启未完成回溯")
	check(int(Game.meta.deaths) == 1, "重启后底稿回溯死亡数不是一次")
	check(Game.continue_game() and Game.run.phase == "post", "重启未恢复回溯后的局")
	check(int(Game.run.rebirths_left) == int(initial_run.rebirths_left) - 1, "回溯残页次数不正确")
	Game._ready()
	check(int(Game.meta.deaths) == 1, "重复加载重复结算死亡")

func _scenario_save_failure() -> void:
	_prepare()
	var initial_run := Game.run.duplicate(true)
	var save_before := FileAccess.get_file_as_string(Game.save_path)
	var meta_before := FileAccess.get_file_as_string(Game.meta_path)
	_block_tmp(Game.save_path)
	Game.rewind()
	check(Game._rewind_pending(), "本局写入失败必须保留事务")
	check(FileAccess.get_file_as_string(Game.save_path) == save_before and FileAccess.get_file_as_string(Game.meta_path) == meta_before, "本局写入失败改变了原始文件")
	check(Game.run == initial_run, "本局写入失败更改了内存中的原局")
	_unblock_tmp(Game.save_path)
	# Simulate interruption after the old main was moved to the backup.
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(Game.save_path), ProjectSettings.globalize_path(Game.save_path + SaveFile.BAK)) == OK, "无法模拟改名中断")
	Game.run = {}
	Game._ready()
	check(not Game._rewind_pending() and Game.continue_game(), "主档改名中间态未恢复")
	check(Game.run.phase == "post" and int(Game.meta.deaths) == 1, "主档恢复后回溯结果不一致")

func _scenario_invalid_log() -> void:
	_prepare()
	var file := FileAccess.open(Game._rewind_path(), FileAccess.WRITE)
	file.store_string("broken journal")
	file.close()
	var before_save := FileAccess.get_file_as_string(Game.save_path)
	var before_meta := FileAccess.get_file_as_string(Game.meta_path)
	Game.run = {}
	Game._ready()
	check(Game._rewind_pending(), "损坏日志必须保留")
	check(not Game.continue_game(), "损坏日志不能被当成正常续写")
	check(FileAccess.get_file_as_string(Game.save_path) == before_save and FileAccess.get_file_as_string(Game.meta_path) == before_meta, "损坏日志覆盖存档")
	check(Game.new_game("scholar") != "", "损坏日志不能开新局覆盖旧档")

func _put(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.close()

func _scenario_backup_changes() -> void:
	_prepare()
	_block_tmp(Game.save_path)
	Game.rewind()
	_unblock_tmp(Game.save_path)
	var original := FileAccess.get_file_as_string(Game.save_path)
	_put(Game.save_path + SaveFile.BAK, "different backup")
	check(not Game._ensure_rewind_resolved() and Game._rewind_pending(), "更改原备份后仍执行回溯")
	check(FileAccess.get_file_as_string(Game.save_path) == original and FileAccess.get_file_as_string(Game.save_path + SaveFile.BAK) == "different backup", "回溯覆盖了并发修改的备份")
	_prepare()
	_block_tmp(Game.meta_path)
	Game.rewind()
	_unblock_tmp(Game.meta_path)
	# Simulate interruption after the new primary was written but before meta.
	var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game._rewind_path()))
	var payload: Dictionary = JSON.parse_string(journal.payload)
	check(SaveFile.write(Game.save_path, payload.data).ok, "无法构造主档已写入夹具")
	_put(Game.save_path + SaveFile.BAK, "different backup after target")
	var target := FileAccess.get_file_as_string(Game.save_path)
	check(not Game._ensure_rewind_resolved() and Game._rewind_pending(), "主档已写入但备份变化时仍重放")
	check(FileAccess.get_file_as_string(Game.save_path) == target and FileAccess.get_file_as_string(Game.save_path + SaveFile.BAK) == "different backup after target", "已写目标状态的备份被覆盖")

func _scenario_meta_middle() -> void:
	_prepare()
	_block_tmp(Game.meta_path)
	Game.rewind()
	_unblock_tmp(Game.meta_path)
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(Game.meta_path), ProjectSettings.globalize_path(Game.meta_path + SaveFile.BAK)) == OK, "无法模拟底稿改名中断")
	Game.run = {}
	Game._ready()
	check(not Game._rewind_pending() and int(Game.meta.deaths) == 1, "底稿改名中间态未恢复")
	check(Game.continue_game() and Game.run.phase == "post", "底稿中间态恢复未能续玩")

func _scenario_recovery_backup() -> void:
	_prepare()
	var valid := FileAccess.get_file_as_string(Game.save_path)
	_put(Game.save_path + SaveFile.BAK, valid)
	_put(Game.save_path, "bad main")
	Game.run = {}
	_block_tmp(Game.save_path)
	check(Game.continue_game() and Game._recovering_backup, "备份恢复夹具无效")
	_unblock_tmp(Game.save_path)
	_block_tmp(Game.save_path)
	Game.rewind()
	_unblock_tmp(Game.save_path)
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(Game.save_path), ProjectSettings.globalize_path(Game.save_path + ".interrupted")) == OK, "无法模拟备份恢复时中断")
	Game.run = {}
	Game._ready()
	check(not Game._rewind_pending() and FileAccess.get_file_as_string(Game.save_path + SaveFile.BAK) == valid, "恢复时破坏唯一有效备份")
	check(Game.continue_game() and Game.run.phase == "post", "备份恢复的改名中间态无法重放")

func _scenario_demo() -> void:
	_prepare()
	_block_tmp(Game.save_path)
	Game.rewind()
	_unblock_tmp(Game.save_path)
	var saved := FileAccess.get_file_as_string(Game.save_path)
	var archive := FileAccess.get_file_as_string(Game.meta_path)
	var journal := FileAccess.get_file_as_string(Game._rewind_path())
	Game.no_save = true
	Game._ready()
	check(not Game._ensure_rewind_resolved(), "无保存模式不能重放真实事务")
	check(FileAccess.get_file_as_string(Game.save_path) == saved and FileAccess.get_file_as_string(Game.meta_path) == archive and FileAccess.get_file_as_string(Game._rewind_path()) == journal, "演示模式改动了真实事务")
	Game.no_save = false

func _scenario_frozen() -> void:
	_prepare()
	_block_tmp(Game.save_path)
	Game.rewind()
	var before_main := FileAccess.get_file_as_string(Game.save_path)
	var before_meta := FileAccess.get_file_as_string(Game.meta_path)
	var before_log := FileAccess.get_file_as_string(Game._rewind_path())
	Game.save_game()
	Game.save_meta()
	check(Game._rewind_pending() and FileAccess.get_file_as_string(Game.save_path) == before_main and FileAccess.get_file_as_string(Game.meta_path) == before_meta and FileAccess.get_file_as_string(Game._rewind_path()) == before_log, "自动保存改动待完成事务")
	check(not bool(Game.export_save_to("user://unexpected-export.jyz").ok), "事务未完成时错误报告存档导出成功")
	check(not bool(Game.export_playtest().ok), "事务未完成时错误报告试玩报告成功")
	var run_before := Game.run.duplicate(true)
	Game.keep_living()
	check(Game.run == run_before and Game._rewind_pending(), "待完成事务仍能推进到守宅")
	Game.run.phase = "post"
	var screen := PostScreen.new()
	screen.world = Node3D.new()
	screen.player = Player.new()
	screen.rig = CamRig.new()
	screen.player.enabled = true
	screen.rig.input_enabled = true
	var t_before := int(Game.run.t)
	screen._process(100.0)
	check(int(Game.run.t) == t_before and not screen.player.enabled and not screen.rig.input_enabled, "未决事务没有冻结时间和移动")
	var reply_before := Game.run.duplicate(true)
	StoryDirector._sent = {"state": {"archive": {"sha256": ""}}}
	StoryDirector._sent_run = Game.run
	StoryDirector._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"source\":\"ark-plan\",\"plan\":{}}".to_utf8_buffer())
	check(Game.run == reply_before and StoryDirector._sent.is_empty(), "未决事务接纳了旧的动态世情回复")
	screen.world.free()
	screen.player.free()
	screen.rig.free()
	screen.free()
	_unblock_tmp(Game.save_path)

func _scenario_existing_temporary_files() -> void:
	for target_side in ["save", "meta"]:
		for identical in [false, true]:
			_prepare()
			_block_tmp(Game.save_path)
			Game.rewind()
			_unblock_tmp(Game.save_path)
			var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game._rewind_path()))
			var payload: Dictionary = JSON.parse_string(journal.payload)
			var target_path: String = Game.save_path if target_side == "save" else Game.meta_path
			var tmp := target_path + SaveFile.TMP
			var content := JSON.stringify(payload.data if target_side == "save" else payload.meta, "\t") if identical else "unrelated player file"
			_put(tmp, content)
			var save_before := FileAccess.get_file_as_string(Game.save_path)
			var meta_before := FileAccess.get_file_as_string(Game.meta_path)
			var log_before := FileAccess.get_file_as_string(Game._rewind_path())
			check(not Game._ensure_rewind_resolved() and Game._rewind_pending(), target_side + ": 已存在的临时文件未阻挡回溯")
			check(FileAccess.get_file_as_string(tmp) == content, target_side + ": 临时文件被截断或删除")
			check(FileAccess.get_file_as_string(Game.save_path) == save_before and FileAccess.get_file_as_string(Game.meta_path) == meta_before and FileAccess.get_file_as_string(Game._rewind_path()) == log_before, target_side + ": 冲突时事务或存档发生改变")
			check(Game.save_notice.contains("无法确认归属") and Game.save_notice.contains("手动移出留存"), target_side + ": 缺少临时文件留存说明")
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp)) == OK, target_side + ": 无法移走测试临时文件")
			check(Game._ensure_rewind_resolved() and not Game._rewind_pending(), target_side + ": 临时文件移走后不能重试")

func _scenario_single_notification() -> void:
	for retry in [false, true]:
		_prepare()
		if retry:
			_block_tmp(Game.save_path)
			Game.rewind()
			_unblock_tmp(Game.save_path)
			check(Game._rewind_pending(), "通知恢复夹具未保留事务")
		var counts := {"screen": 0, "changed": 0}
		var on_screen := func(_target: String): counts.screen += 1
		var on_changed := func(): counts.changed += 1
		Game.screen_changed.connect(on_screen)
		Game.changed.connect(on_changed)
		Game.rewind()
		Game.screen_changed.disconnect(on_screen)
		Game.changed.disconnect(on_changed)
		var name := "恢复成功" if retry else "普通成功"
		check(Game.run.phase == "post" and not Game._rewind_pending(), name + ": 未完成回溯")
		check(int(counts.screen) == 1 and int(counts.changed) == 1, name + ": 应仅切换和通知一次")
