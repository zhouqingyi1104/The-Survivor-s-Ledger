extends Node
## Run with isolated APPDATA/LOCALAPPDATA. All paths used below are user:// scratch files.

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var checks := 0
var failures := 0
var notices: Array[String] = []
var good_meta := "user://t_settlement_meta.json"
var save := "user://t_settlement_save.json"
var memory := "user://t_settlement_Memory.md"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	Game.toast.connect(func(message: String): notices.append(message))
	for action in ["close", "choose", "restart"]:
		_test_action(action)
	_test_interrupted_after_settlement()
	_test_no_save()
	_cleanup()
	print("[settlement_safety] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _prepare() -> void:
	_cleanup()
	Game.no_save = false
	Game.save_path = save
	Game.meta_path = good_meta
	Game.memory_path = memory
	Game.meta = State.new_meta()
	Game.run = {}
	Game.snapshots = {}
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	Game.run.pday = 5
	Game.run.phase = "dead"
	Game.run.death_cause = "测试"
	Game.save_game()
	Game.go("dead")

func _test_action(action: String) -> void:
	_prepare()
	var before_run := Game.run.duplicate(true)
	var before_meta := Game.meta.duplicate(true)
	var before_save := FileAccess.get_file_as_string(save)
	var before_backup := FileAccess.get_file_as_string(save + SaveFile.BAK)
	var before_memory := FileAccess.get_file_as_string(memory)
	var life := str(Game.run.past_lives.id)
	# An absent parent reliably forces the write failure while the actual save is writable.
	Game.meta_path = "user://nonexistent-settlement-dir/meta.json"
	for retry in 2:
		notices.clear()
		_call_action(action, life)
		check(Game.run == before_run and Game.meta == before_meta, action + ": failed attempt changed in-memory life or rewards")
		check(FileAccess.get_file_as_string(save) == before_save and FileAccess.get_file_as_string(save + SaveFile.BAK) == before_backup, action + ": failed attempt deleted/changed save or backup")
		check(FileAccess.get_file_as_string(memory) == before_memory, action + ": failed attempt changed Memory.md")
		check(Game.screen == "dead", action + ": failed attempt left the life screen")
		check(notices.any(func(message: String): return message.contains("底稿保存失败") and message.contains("重试")), action + ": failed attempt omitted actionable notice")
	Game.meta_path = good_meta
	_call_action(action, life)
	check(Game.save_notice == "", action + ": resolved failure notice was left on screen")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, action + ": retry did not settle once")
	var disk := SaveFile.read(good_meta)
	check(int(disk.data.get("runs", 0)) == 1 and int(disk.data.get("deaths", 0)) == 1, action + ": successful settlement did not persist")
	if action == "close":
		check(Game.run.is_empty() and Game.screen == "title" and not FileAccess.file_exists(save), "close: successful retry did not close")
	elif action == "choose":
		check(Game.run.is_empty() and Game.screen == "challenge" and not FileAccess.file_exists(save), "choose: successful retry did not open choices")
	else:
		check(Game.run.get("phase", "") == "pre" and str(Game.run.past_lives.id) != life, "restart: successful retry did not create a new life")
	_call_action(action, life)
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, action + ": stale callback settled twice")

func _call_action(action: String, life: String) -> void:
	match action:
		"close": Game.close_book(life)
		"choose": Game.choose_next_opening(life)
		"restart": Game.restart_from_cover(life)

func _test_interrupted_after_settlement() -> void:
	_prepare()
	var life := str(Game.run.past_lives.id)
	check(bool(Game.end_run().get("saved", false)), "first settlement did not persist")
	var paid := int(Game.meta.daoxin)
	# Simulate interruption after meta committed and before the old life was removed.
	Game.run = {}
	Game.meta = SaveFile.read(good_meta).data
	check(Game.continue_game(), "could not reopen the pre-settlement save")
	check(Game.close_book(life), "already settled life could not be closed")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1 and int(Game.meta.daoxin) == paid, "interrupted close duplicated rewards")

func _test_no_save() -> void:
	_prepare()
	Game.no_save = true
	Game.meta_path = "user://nonexistent-settlement-dir/meta.json"
	check(Game.close_book(), "demo mode could not close without disk writes")
	check(int(Game.meta.runs) == 1, "demo mode did not settle in memory")

func _cleanup() -> void:
	SaveFile.forget(save)
	SaveFile.forget(good_meta)
	if FileAccess.file_exists(memory): DirAccess.remove_absolute(ProjectSettings.globalize_path(memory))
