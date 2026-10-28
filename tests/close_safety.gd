extends Node
## Run with isolated APPDATA and LOCALAPPDATA; all test files are user://.

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var checks := 0
var failures := 0
var notices: Array[String] = []
var save := "user://t_close_safety_save.json"
var meta := "user://t_close_safety_meta.json"
var memory := "user://t_close_safety_memory.md"
var lock_suffix := "#"
var locked: FileAccess

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	Game.toast.connect(_on_toast)
	for action in ["close", "choose"]:
		for suffix in [SaveFile.TMP, SaveFile.BAK, ""]:
			_test_locked(action, suffix)
		_test_save_failure(action)
	_test_restart_save_failure()
	_test_ending_keep()
	_test_directory_collision()
	_cleanup()
	print("[close_safety] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_locked(action: String, suffix: String) -> void:
	_cleanup()
	Game.no_save = false
	Game.save_path = save
	Game.meta_path = meta
	Game.memory_path = memory
	Game.meta = State.new_meta()
	Game.run = {}
	Game.snapshots = {}
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	Game.run.phase = "dead"
	Game.run.death_cause = "测试"
	Game.save_game()
	Game.go("dead")
	var before := Game.run.duplicate(true)
	var before_snapshots := Game.snapshots.duplicate(true)
	var life := str(Game.run.past_lives.id)
	# The Memory write warning occurs after settlement and before delete. Lock
	# the selected file there to exercise a real cleanup failure on Windows.
	lock_suffix = suffix
	Game.memory_path = "user://nonexistent-close-dir/Memory.md"
	Game.memory_status = "local"
	notices.clear()
	_call(action, life)
	check(locked != null, action + suffix + ": could not lock test file")
	var after := Game.run.duplicate(true)
	# Settlement marks this life archived; its other state must stay intact.
	if after.has("past_lives"): after.past_lives = before.past_lives
	check(Game.screen == "dead" and after == before and Game.snapshots == before_snapshots, action + suffix + ": failure discarded or left current life")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, action + suffix + ": settlement not recorded exactly once")
	check(FileAccess.file_exists(save) or FileAccess.file_exists(save + SaveFile.BAK), action + suffix + ": no recoverable save")
	var recoverable := SaveFile.read(save)
	check(str(recoverable.data.get("run", {}).get("past_lives", {}).get("id", "")) == life, action + suffix + ": remaining save is not the same life")
	check(notices.any(func(message: String): return message.contains("重试")), action + suffix + ": no retry notice")
	var settled := Game.run.duplicate(true)
	Game.rewind()
	Game.restart_from_cover(life)
	check(Game.run == settled and Game.screen == "dead", action + suffix + ": settled life could continue after failed cleanup")
	locked.close()
	locked = null
	Game.memory_path = memory
	_call(action, life)
	check(Game.run.is_empty() and Game.screen == ("title" if action == "close" else "challenge"), action + suffix + ": retry failed")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, action + suffix + ": retry paid twice")
	check(not FileAccess.file_exists(save) and not FileAccess.file_exists(save + SaveFile.BAK) and not FileAccess.file_exists(save + SaveFile.TMP), action + suffix + ": retry left old files")

func _on_toast(message: String) -> void:
	notices.append(message)
	if lock_suffix == "#" or not message.contains("Memory.md 未能写入"): return
	if lock_suffix == SaveFile.TMP:
		var temp := FileAccess.open(save + SaveFile.TMP, FileAccess.WRITE)
		temp.store_string("test")
		temp.close()
	locked = FileAccess.open(save + lock_suffix, FileAccess.READ)
	lock_suffix = "#"

func _test_save_failure(action: String) -> void:
	_cleanup()
	Game.no_save = false
	Game.save_path = save
	Game.meta_path = meta
	Game.memory_path = memory
	Game.meta = State.new_meta()
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	# The most recent disk copy still describes the living life.
	Game.save_game()
	Game.run.phase = "dead"
	Game.run.death_cause = "测试"
	Game.go("dead")
	var before := Game.run.duplicate(true)
	var life := str(Game.run.past_lives.id)
	var tmp := FileAccess.open(save + SaveFile.TMP, FileAccess.WRITE)
	tmp.store_string("locked")
	tmp.close()
	var guard := FileAccess.open(save + SaveFile.TMP, FileAccess.READ)
	notices.clear()
	_call(action, life)
	check(Game.screen == "dead" and Game.run == before, action + ": failed terminal save left the death screen")
	check(int(Game.meta.runs) == 0 and int(Game.meta.deaths) == 0, action + ": rewards sealed despite failed terminal save")
	check(SaveFile.read(save).data.get("run", {}).get("phase") != "dead", action + ": failed terminal save replaced prior save")
	check(notices.any(func(message: String): return message.contains("尚未结算") and message.contains("重试")), action + ": no terminal save retry notice")
	guard.close()
	_call(action, life)
	check(Game.run.is_empty() and int(Game.meta.runs) == 1, action + ": terminal save retry did not settle once")

func _test_restart_save_failure() -> void:
	_cleanup()
	Game.no_save = false
	Game.save_path = save
	Game.meta_path = meta
	Game.memory_path = memory
	Game.meta = State.new_meta()
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	Game.run.phase = "dead"
	Game.run.death_cause = "测试"
	Game.save_game()
	Game.go("dead")
	var life := str(Game.run.past_lives.id)
	lock_suffix = SaveFile.TMP
	Game.memory_path = "user://nonexistent-close-dir/Memory.md"
	Game.memory_status = "local"
	notices.clear()
	Game.restart_from_cover(life)
	check(locked != null, "restart: could not lock candidate temp")
	check(Game.screen == "dead" and str(Game.run.past_lives.id) == life, "restart: failed candidate replaced old life")
	check(SaveFile.read(save).data.get("run", {}).get("phase") == "dead", "restart: failed candidate lost terminal save")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, "restart: settlement missing or duplicated")
	check(notices.any(func(message: String): return message.contains("新一世保存失败") and message.contains("重试")), "restart: candidate failure omitted retry notice")
	locked.close()
	locked = null
	Game.memory_path = memory
	Game.restart_from_cover(life)
	var next_id := str(Game.run.get("past_lives", {}).get("id", ""))
	check(Game.screen == "pre" and next_id != "" and next_id != life, "restart: retry did not start a new life")
	check(str(SaveFile.read(save).data.get("run", {}).get("past_lives", {}).get("id", "")) == next_id, "restart: disk does not match new life")
	check(int(Game.meta.runs) == 1 and int(Game.meta.deaths) == 1, "restart: retry settled twice")

func _test_ending_keep() -> void:
	_cleanup()
	Game.no_save = false
	Game.save_path = save
	Game.meta_path = meta
	Game.memory_path = memory
	Game.meta = State.new_meta()
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	Game.run.phase = "ending"
	Game.run.pday = 20
	Game.save_game()
	Game.go("ending")
	var life := str(Game.run.past_lives.id)
	lock_suffix = SaveFile.TMP
	Game.memory_path = "user://nonexistent-close-dir/Memory.md"
	Game.memory_status = "local"
	Game.close_book(life)
	check(locked != null and Game.screen == "ending", "ending: failed cleanup did not retain ending")
	var settled := Game.run.duplicate(true)
	notices.clear()
	Game.keep_living(life)
	check(Game.run == settled and Game.screen == "ending", "ending: already settled life continued")
	check(notices.any(func(message: String): return message.contains("已结算")), "ending: continuation block was not explained")
	locked.close()
	locked = null
	Game.memory_path = memory
	check(Game.close_book(life), "ending: cleanup retry failed")

func _test_directory_collision() -> void:
	_cleanup()
	var collision := save + SaveFile.TMP
	var absolute := ProjectSettings.globalize_path(collision)
	check(DirAccess.make_dir_absolute(absolute) == OK, "directory: fixture creation failed")
	var result := SaveFile.forget(save)
	check(not bool(result.ok) and str(result.path) == collision, "directory: collision was reported as successful cleanup")
	check(DirAccess.dir_exists_absolute(absolute), "directory: collision was removed")
	check(DirAccess.remove_absolute(absolute) == OK, "directory: fixture cleanup failed")

func _call(action: String, life: String) -> void:
	if action == "close": Game.close_book(life)
	else: Game.choose_next_opening(life)

func _cleanup() -> void:
	SaveFile.forget(save)
	SaveFile.forget(meta)
	if FileAccess.file_exists(memory): DirAccess.remove_absolute(ProjectSettings.globalize_path(memory))
