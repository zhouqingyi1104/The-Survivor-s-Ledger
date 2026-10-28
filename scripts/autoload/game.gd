extends Node
## 全局单例：持有当前这一局（run）、跨轮回的记忆（meta）和生死簿快照，负责存读档与切换界面。
## 界面只通过 act() 调用核心逻辑，调用完由这里统一做快照、存档、广播刷新。

signal changed
signal screen_changed(screen: String)
signal toast(text: String)

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const MemoryFile = preload("res://scripts/core/life_memory_file.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Opening = preload("res://scripts/core/opening.gd")
const Director = preload("res://scripts/core/director.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")
const PlaytestReport = preload("res://scripts/core/playtest_report.gd")
const InputCfg = preload("res://scripts/core/input_cfg.gd")

const SAVE_PATH := "user://save.json"
const META_PATH := "user://meta.json"

var run: Dictionary = {}
var meta: Dictionary = {}
var snapshots: Dictionary = {}
var screen := "title"
var last_gain: Dictionary = {}
## 演示 / 截图模式：不读写玩家存档。
var no_save := false
## 劫中的时间流速档位：0 暂停，1 正常，2 快，3 极快。
var speed := 1
## 演出（夜袭、走路）期间为 true：照常存档、广播，但先不切界面，演完再 refresh()。
var hold_screen := false
## 存档位置（测试时会改到别的文件）。
var save_path := SAVE_PATH
var meta_path := META_PATH
## 存档/前世档案出了事要告诉玩家的话（标题界面第一屏显示，不静默吞掉）。
var save_notice := ""
## 写盘失败只提示一次，别每次行动都弹。
var _save_warned := false
## 恢复自备档后，首次成功保存前不能让坏主档轮换覆盖唯一的好备档。
var _recovering_backup := false
## 空值为项目根 Memory.md；隔离存档的测试必须显式指定独立路径。
var memory_path := ""
var memory_status := "local"
## 正在摆放的家具（空 = 不在摆放）：界面选好家具后置上，点地面放下。
var placing := ""
var placing_rot := 0
## 挪位中的家具 uid；-1 表示添置。
var moving_uid := -1
## 摆放预览的固定落点（截图和测试用；null 时跟着鼠标）
var placing_at = null
## 选难度界面挂着：刚挑的身份，定了难度就照这个开局
var pending_role := ""
## 已经定好的难度，接着去挑挑战（了愿）
var pending_difficulty := "normal"
## 开局模式，由挑战界面在开局前设好：
##   pending_endless  守到死——开局就把 run.endless 打开，第二十日天亮不进结局
##   pending_daily    每日一局——种子按本地日期给，同一天所有人同一副牌
var pending_endless := false
var pending_daily := false
var pending_opening_setup: Dictionary = {}


func _ready() -> void:
	# Demo mode is declared before autoload startup, not after main scene loads.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demo=") and arg.trim_prefix("--demo=") != "": no_save = true
	Data.ensure()
	# Recover a durable rewind before reading or renaming either constituent file.
	if _rewind_pending() and not _ensure_rewind_resolved():
		meta = State.new_meta()
		return
	var got := SaveFile.read(meta_path)
	var data: Dictionary = Data.normalize(got.data)
	meta = data if not data.is_empty() else State.new_meta()
	# 主档坏了通常是上次写盘中途断掉：已经退回备份就读回来，两份都坏才另起，
	# 并把读不出的那份另存留底（不直接覆盖），玩家至少还有东西可以发给别人看。
	if got.note in ["main_bad", "main_missing"]:
		save_notice = "跨轮回的底稿没能完整读回，已改用上一份备份。"
		if not no_save: _preserve_broken(meta_path)
	elif got.note == "none" and FileAccess.file_exists(meta_path):
		save_notice = "跨轮回的底稿读不出来，已另存留底并重新起账。"
		if not no_save: _preserve_broken(meta_path)


# ---------- 界面切换 ----------

func _clear_placement() -> void:
	placing = ""
	moving_uid = -1


func go(target: String) -> void:
	_clear_placement()
	screen = target
	screen_changed.emit(target)


func _screen_for_phase() -> String:
	match run.get("phase", ""):
		"pre":
			return "pre"
		"post":
			return "explore" if not run.explore.is_empty() else "post"
		"dead":
			return "dead"
		"ending":
			return "ending"
	return "title"


# ---------- 统一入口 ----------

## 调核心逻辑。返回非空字符串就当作提示弹出来。
func act(fn: Callable) -> Variant:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return null
	var res = fn.call()
	if typeof(res) == TYPE_STRING and res != "":
		toast.emit(res)
		Sfx.play("ui_error", -9.0, 0.0)
	_after()
	return res


func _after(skip_save := false) -> void:
	if _rewind_pending(): return
	if run.is_empty():
		changed.emit()
		return
	# 每天卯时开始时记一页快照，翻生死簿时翻回这里
	if run.phase == "post" and int(run.pday) > 0 and not snapshots.has(str(run.pday)):
		Ledger.snapshot(run, snapshots)
	if not skip_save: save_game()
	var target := _screen_for_phase()
	if target != screen and not hold_screen:
		go(target)
	changed.emit()


## 演出结束后补一次：该切界面就切，该弹夜报就弹。
func refresh() -> void:
	_after()


# ---------- 开局 / 轮回 ----------

func role_unlocked(role_id: String) -> bool:
	var r: Dictionary = Data.table("roles")[role_id]
	match r.get("unlock", ""):
		"first_death":
			return int(meta.deaths) > 0
	return true


func new_game(role_id: String, difficulty_id := "normal", goals: Array = [], boons: Array = [], vows: Array = [], endless := false, daily := false, companions: Array = [], opening_id := "plain") -> String:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return "先处理未完成的回溯，再重新开局。"
	# Validate and apply on a candidate. A stale/invalid selection cannot replace a life.
	var candidate := State.new_run(role_id, meta, daily_seed() if daily else randi(), difficulty_id, goals, boons, vows)
	# 守到死：Post.ack_dawn 看 run.endless —— 第 20 日天亮照常开新的一天，不进结局
	candidate.endless = endless
	if daily:
		candidate.flags["daily"] = today_text()
		# Past.begin runs before this flag. Daily runs carry no private legacy source.
		candidate.identity = {}
		candidate.opening["inherited"] = []
		candidate.cycle_inquiry = {"schema": 1, "closed": true, "sources": []}
	# 同院的人（备劫前带回来的帮手）
	candidate.companions = companions.duplicate()
	var result := Opening.apply(candidate, opening_id, str(Opening.view(candidate).token))
	if result != "": return result
	if opening_id != "plain": Director.note_choice(candidate, "今世开局筹备", str(Opening.view(candidate).summary))
	# Persist the candidate before replacing the current life.
	if not no_save:
		var data := {"run": candidate, "snapshots": {}}
		var saved := SaveFile.write_from_backup(save_path, data) if _recovering_backup else SaveFile.write(save_path, data)
		if not bool(saved.ok):
			return "新一世保存失败，请检查存档目录后重试；旧卷仍在。"
	_clear_placement()
	run = candidate
	_recovering_backup = false
	snapshots = {}
	last_gain = {}
	pending_opening_setup = {}
	if not no_save: save_meta()
	_after(true)
	return ""


## 快速开局：第一个已解锁的身份、寻常年景、不立愿、不带人、普通开局，直接进城备劫。
## 想挑身份、难度、誓约与开局筹备的，从标题的「自选开局」走原来那四屏。
func quick_start() -> String:
	var role_id := quick_role()
	if role_id == "":
		return "没有可用的身份。"
	return new_game(role_id)


## 快速开局用的身份：身份表里第一个已解锁的。
func quick_role() -> String:
	for id in Data.table("roles"):
		if role_unlocked(id):
			return id
	return ""


## 今天（本地日期）写成 2026-10-24。
func today_text() -> String:
	return State.today_text()


## 每日一局的种子：只取日期，不掺时刻，所以同一天开机拿到的都是同一副牌。
func daily_seed() -> int:
	return State.daily_seed()


## 选完身份，先去定难度（原版 DifficultySelect / ChallengeSetup）。
func pick_difficulty(role_id: String) -> void:
	pending_opening_setup = {}
	pending_role = role_id
	pending_difficulty = "normal"
	go("difficulty")


func has_save() -> bool:
	if no_save: return false
	if _rewind_pending(): return true
	# 备份也算——主档写坏时玩家仍然能续上，别在标题界面把入口藏掉
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + SaveFile.BAK)


## 主档和备份各自还能不能用：标题界面用它决定「续写此录」后面跟不跟一句实话。
func save_status() -> Dictionary:
	var main := _read_continue_candidate(save_path)
	var backup := _read_continue_candidate(save_path + SaveFile.BAK)
	return {"main": main.ok, "backup": backup.ok, "future": main.future or (not main.ok and backup.future)}


func _read_continue_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "future": false, "data": {}}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {"ok": false, "future": false, "data": {}}
	var validation := SavePack.validate_data(json.data)
	return {"ok": validation.ok, "future": validation.future, "data": json.data if validation.ok else {}}


## 续上一卷。返回 false 表示主档和备份都读不出来（此时不静默新开，交给调用方决定）。
func continue_game() -> bool:
	if _rewind_pending() and not _ensure_rewind_resolved(): return false
	var main := _read_continue_candidate(save_path)
	var backup := _read_continue_candidate(save_path + SaveFile.BAK)
	# 更新版本的主档可能包含旧版无法理解的信息；不能自动退回并覆盖它。
	if main.future or (not main.ok and backup.future):
		save_notice = "这一卷来自更新的游戏版本，请用更新版本打开；原文件未改动。"
		toast.emit(save_notice)
		return false
	if not main.ok and not backup.ok:
		save_notice = "这一卷的主档和备份都读不出来。原文件留在存档目录里，没有删。"
		toast.emit("存档读不出来。")
		return false
	var from_backup: bool = not main.ok
	var data: Dictionary = Data.normalize(backup.data if from_backup else main.data)
	data = Migrate.save(data)
	_clear_placement()
	run = data.get("run", {})
	snapshots = data.get("snapshots", {})
	_recovering_backup = from_backup
	if from_backup:
		save_notice = ("主存档不在了，已经接着上一份备份往下写（可能退回一步）。" if not FileAccess.file_exists(save_path)
			else "主存档写坏了，已经接着上一份备份往下写（可能退回一步）。")
		toast.emit(save_notice)
	else:
		save_notice = ""
	_after()
	return true


## 翻回昨日。
func rewind() -> void:
	# A previous attempt must finish before another rewind is considered.
	if _rewind_pending():
		_ensure_rewind_resolved()
		return
	if _life_settled():
		toast.emit("这一世已结算，请先合上旧卷或另选下一世开局。")
		return
	var candidate_run := run.duplicate(true)
	var candidate_snaps := snapshots.duplicate(true)
	var candidate_meta := meta.duplicate(true)
	var back := Ledger.rewind(candidate_run, candidate_snaps, candidate_meta)
	if back.is_empty():
		toast.emit("翻不回去了。")
		return
	if no_save:
		run = back
		snapshots = candidate_snaps
		meta = candidate_meta
		_after()
		return
	var payload := {"data": {"run": back, "snapshots": candidate_snaps}, "meta": candidate_meta,
		"save_path": ProjectSettings.globalize_path(save_path), "meta_path": ProjectSettings.globalize_path(meta_path),
		"save_before": _rewind_file_hash(save_path), "save_backup_before": _rewind_file_hash(save_path + SaveFile.BAK),
		"meta_before": _rewind_file_hash(meta_path), "meta_backup_before": _rewind_file_hash(meta_path + SaveFile.BAK),
		"recovering_backup": _recovering_backup}
	var encoded := JSON.stringify(payload, "\t")
	var journal_path := _rewind_path()
	if FileAccess.file_exists(journal_path + SaveFile.TMP) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(journal_path + SaveFile.TMP)):
		_rewind_error("回溯事务的临时文件已存在，请先手动留存。")
		return
	var journal := SaveFile.write(journal_path, {"version": 1, "payload": encoded, "sha256": encoded.sha256_text()})
	if not bool(journal.ok):
		_rewind_error("无法保存回溯记录（%s），原局未改动。" % str(journal.step))
		return
	_ensure_rewind_resolved()


func _rewind_path() -> String:
	return save_path + ".rewind"


func _rewind_pending() -> bool:
	if no_save: return false
	return FileAccess.file_exists(_rewind_path()) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_rewind_path()))


func _rewind_file_hash(path: String) -> String:
	if not FileAccess.file_exists(path): return "missing"
	return FileAccess.get_file_as_string(path).sha256_text()


func _rewind_error(reason: String) -> void:
	save_notice = reason + " 回溯尚未完成，请检查存档目录后重试；原始文件和回溯记录均已保留。"
	toast.emit(save_notice)


# A file may be at its old state, its desired state, or between the two atomic
# renames (main missing and the previous main present as the backup).
func _rewind_checkpoint(path: String, before: String, backup_before: String, target: String, recovering := false) -> bool:
	var main := _rewind_file_hash(path)
	var backup := _rewind_file_hash(path + SaveFile.BAK)
	# Initial state, including the case where the candidate happens to match.
	if main == before and backup == backup_before: return true
	# General writes park the prior main in .bak; backup recovery retains .bak.
	var resulting_backup := backup_before if recovering or before == "missing" else before
	if main == target and backup == resulting_backup: return true
	# Interruption between parking the prior main and replacing it.
	if main == "missing" and before != "missing" and backup == resulting_backup: return true
	return false


func _ensure_rewind_resolved() -> bool:
	if no_save: return false
	if not _rewind_pending(): return true
	var path := _rewind_path()
	if not FileAccess.file_exists(path):
		_rewind_error("回溯记录不是文件。")
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_rewind_error("回溯记录损坏。")
		return false
	var wrapper: Dictionary = parser.data
	if wrapper.get("version") != 1 or not wrapper.get("payload") is String:
		_rewind_error("回溯记录的格式无法识别。")
		return false
	var encoded: String = wrapper.payload
	if encoded.sha256_text() != str(wrapper.get("sha256", "")) or parser.parse(encoded) != OK or not parser.data is Dictionary:
		_rewind_error("回溯记录校验失败。")
		return false
	var payload: Dictionary = parser.data
	if str(payload.get("save_path", "")) != ProjectSettings.globalize_path(save_path) or str(payload.get("meta_path", "")) != ProjectSettings.globalize_path(meta_path) or not payload.get("data") is Dictionary or not payload.get("meta") is Dictionary:
		_rewind_error("回溯记录与当前存档不匹配。")
		return false
	var data: Dictionary = payload.data
	if not bool(SavePack.validate_data(data).ok):
		_rewind_error("回溯记录中的本局无法读取。")
		return false
	for key in ["save_before", "save_backup_before", "meta_before", "meta_backup_before"]:
		if not payload.get(key) is String:
			_rewind_error("回溯记录缺少校验信息。")
			return false
	var target_save := JSON.stringify(data, "\t").sha256_text()
	var target_meta := JSON.stringify(payload.meta, "\t").sha256_text()
	if not _rewind_checkpoint(save_path, payload.save_before, payload.save_backup_before, target_save, bool(payload.get("recovering_backup", false))) or not _rewind_checkpoint(meta_path, payload.meta_before, payload.meta_backup_before, target_meta):
		_rewind_error("存档或底稿已被其他操作更改。")
		return false
	# SaveFile writes to fixed .tmp paths. An existing file (even one with the
	# expected bytes) has no ownership marker, so never truncate or remove it.
	# Check both sides before writing either, and let the player move it aside.
	for item in [[save_path, target_save], [meta_path, target_meta]]:
		var target_path: String = item[0]
		if _rewind_file_hash(target_path) == item[1]: continue
		var temp_path := target_path + SaveFile.TMP
		if FileAccess.file_exists(temp_path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(temp_path)):
			_rewind_error("临时路径 %s 已存在，无法确认归属；请先手动移出留存后重试。" % ProjectSettings.globalize_path(temp_path))
			return false
	if _rewind_file_hash(save_path) != target_save:
		var result := SaveFile.write_from_backup(save_path, data) if bool(payload.get("recovering_backup", false)) else SaveFile.write(save_path, data)
		if not bool(result.ok):
			_rewind_error("回溯本局写入失败（%s）。" % str(result.step))
			return false
	if _rewind_file_hash(meta_path) != target_meta:
		var result := SaveFile.write(meta_path, payload.meta)
		if not bool(result.ok):
			_rewind_error("回溯底稿写入失败（%s）。" % str(result.step))
			return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		_rewind_error("回溯已写入，但无法移除完成记录。")
		return false
	# A successful recovery always refreshes the archive, including when a
	# startup failure is retried from the title with no life loaded.
	meta = Data.normalize(payload.meta)
	if not run.is_empty():
		_clear_placement()
		run = Data.normalize(data.run)
		snapshots = Data.normalize(data.snapshots)
		_recovering_backup = false
		_sync_life_memory()
		go(_screen_for_phase())
		changed.emit()
	save_notice = ""
	return true


## 这一轮结束（翻回扉页 / 合上 / 劫满），结算道心。
func ending_bonus(value: Dictionary = {}) -> int:
	return Ledger.ending_bonus(run if value.is_empty() else value)


func _same_life(expected_life: String) -> bool:
	return not run.is_empty() and (expected_life == "" or str(Past.state(run).id) == expected_life)


func _life_settled() -> bool:
	if run.is_empty(): return false
	var life := Past.state(run)
	var book := Past.book(meta)
	return bool(life.archived) or life.id in book.sealed_ids or (int(life.generation) > 0 and int(life.generation) <= int(book.count))


## Ensure a restart can recover this terminal life before its rewards are sealed.
func _persist_before_settlement() -> bool:
	if no_save: return true
	var data := {"run": run, "snapshots": snapshots}
	# Avoid needlessly rotating an already-current main and its previous backup.
	if not _recovering_backup and FileAccess.file_exists(save_path) and FileAccess.get_file_as_string(save_path) == JSON.stringify(data, "\t"):
		return true
	var result := SaveFile.write_from_backup(save_path, data) if _recovering_backup else SaveFile.write(save_path, data)
	if not bool(result.ok):
		save_notice = ("旧卷已结算，但本局未能保存；请检查存档目录后重试。" if _life_settled()
			else "本局未能保存，尚未结算；请检查存档目录后重试。")
		toast.emit(save_notice)
		return false
	_recovering_backup = false
	if save_notice in ["本局未能保存，尚未结算；请检查存档目录后重试。", "旧卷已结算，但本局未能保存；请检查存档目录后重试。"]:
		save_notice = ""
	return true


func end_run(bonus := -1) -> Dictionary:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return {"lines": [], "total": 0, "days": 0, "settled": false, "saved": false}
	if run.is_empty(): return {"lines": [], "total": 0, "days": 0, "settled": false, "saved": false}
	# Settlement mutates both the life and its archive. Work on copies until the
	# archive is safely on disk, so a failed write can be retried without either
	# losing the life or rewarding it twice.
	var candidate_run := run.duplicate(true)
	var candidate_meta := meta.duplicate(true)
	var gain := Ledger.end_run(candidate_run, candidate_meta, bonus)
	if gain.get("settled", false) and candidate_run.phase == "ending":
		candidate_meta.endings = int(candidate_meta.endings) + 1
	if not no_save:
		var result := SaveFile.write(meta_path, candidate_meta)
		if not bool(result.ok):
			_warn_save_failed(result)
			save_notice = "跨轮回底稿保存失败，本局未合卷。请检查磁盘后重试。"
			toast.emit(save_notice)
			return {"lines": [], "total": 0, "days": 0, "settled": false, "saved": false}
	run = candidate_run
	meta = candidate_meta
	last_gain = gain
	last_gain["saved"] = true
	if save_notice == "跨轮回底稿保存失败，本局未合卷。请检查磁盘后重试。":
		save_notice = ""
	if not no_save: _sync_life_memory()
	return last_gain


## 带着记忆回到三日之前（同一身份重开）。
func restart_from_cover(expected_life := "") -> void:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return
	if not _same_life(expected_life): return
	var role_id: String = run.role
	var d := str(run.get("difficulty", "normal"))
	# 开局模式（守到死 / 每日一局）跟着带过去，别让重开一局把模式丢了
	var endless := bool(run.get("endless", false))
	var daily := str(run.get("flags", {}).get("daily", "")) != ""
	# 同院的人也带过去——回到三日之前，院里还是这几个人（誓约/凭仗/了愿另说，
	# 那三样是"这一局挑的挑战"，重开不带走）
	var mates: Array = (run.get("companions", []) as Array).duplicate()
	var opening_id := str(run.get("opening", {}).get("choice", "plain"))
	if opening_id == "": opening_id = "plain"
	if not _persist_before_settlement(): return
	if not bool(end_run(Ledger.ending_bonus(run)).get("saved", false)): return
	var result := new_game(role_id, d, [], [], [], endless, daily, mates, opening_id)
	if result == "新一世保存失败，请检查存档目录后重试；旧卷仍在。":
		toast.emit(result)
		return
	if result != "":
		var fallback := new_game(role_id, d, [], [], [], endless, daily, mates, "plain")
		if fallback != "":
			toast.emit(fallback)
			return
		toast.emit("先前开局已不适用，这一世使用普通行囊；可在结局页另选开局。")


## Settle this life once, then explicitly choose how to prepare the next one.
func choose_next_opening(expected_life := "") -> void:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return
	if not _same_life(expected_life) or not run.get("phase", "") in ["dead", "ending"]: return
	var role_id := str(run.role)
	var difficulty_id := str(run.get("difficulty", "normal"))
	var setup := {"endless": bool(run.get("endless", false)), "daily": Past.daily(run), "mates": (run.get("companions", []) as Array).duplicate()}
	if not _persist_before_settlement(): return
	if not bool(end_run(Ledger.ending_bonus(run)).get("saved", false)): return
	if not _delete_save(): return
	run = {}
	snapshots = {}
	pending_role = role_id
	pending_difficulty = difficulty_id
	pending_opening_setup = setup
	go("challenge")


func close_book(expected_life := "") -> bool:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return false
	if not _same_life(expected_life): return false
	if not _persist_before_settlement(): return false
	if not bool(end_run(Ledger.ending_bonus(run)).get("saved", false)): return false
	if not _delete_save(): return false
	run = {}
	snapshots = {}
	go("title")
	changed.emit()
	return true


## 劫满后守宅：转无尽，尸潮继续升级。
func keep_living(expected_life := "") -> void:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return
	if not _same_life(expected_life): return
	if _life_settled():
		toast.emit("这一世已结算，请先合上旧卷或另选下一世开局。")
		return
	var block := Mainline.continue_block(run)
	if block != "":
		toast.emit(block)
		return
	block = Mainline.continued(run)
	if block != "":
		toast.emit(block)
		return
	run.endless = true
	run.phase = "post"
	Post.begin_day(run)
	_after()


func buy_talent(id: String) -> void:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return
	var t: Dictionary = Data.table("talents")[id]
	if id in meta.talents:
		return
	if int(meta.daoxin) < int(t.cost):
		toast.emit("道心不够。")
		return
	meta.daoxin = int(meta.daoxin) - int(t.cost)
	meta.talents.append(id)
	save_meta()
	toast.emit("悟得心法：%s" % t.name)
	changed.emit()


# ---------- 存读档 ----------

func save_game() -> void:
	if _rewind_pending(): return
	if run.is_empty() or no_save:
		return
	var data := {"run": run, "snapshots": snapshots}
	var result := SaveFile.write_from_backup(save_path, data) if _recovering_backup else SaveFile.write(save_path, data)
	if not result.ok:
		_warn_save_failed(result)
	else:
		_recovering_backup = false
	save_meta()


func save_meta() -> void:
	if _rewind_pending(): return
	if no_save:
		return
	var result := SaveFile.write(meta_path, meta)
	if not result.ok:
		_warn_save_failed(result)
		return
	_sync_life_memory()


# ---------- 存档备份与搬运（.jyz） ----------

## 把当前这一局导出成一个 .jyz 文件到玩家指定的位置。返回 {"ok": bool, "note": String}。
func export_save_to(path: String) -> Dictionary:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return {"ok": false, "note": "请先处理未完成的回溯，再导出存档。"}
	if run.is_empty():
		return {"ok": false, "note": "现在没有可以导出的局。"}
	# 先把内存里的状态落盘，导出的文件和存档目录里的那份必须一致
	save_game()
	var stamp := "%04d%02d%02d-%02d%02d" % [
		int(Time.get_datetime_dict_from_system().year), int(Time.get_datetime_dict_from_system().month),
		int(Time.get_datetime_dict_from_system().day), int(Time.get_datetime_dict_from_system().hour),
		int(Time.get_datetime_dict_from_system().minute)]
	var envelope := SavePack.pack({"run": run, "snapshots": snapshots},
		str(ProjectSettings.get_setting("application/config/version", "?")), stamp)
	var result := SaveFile.write_text(path, SavePack.to_text(envelope))
	if not bool(result.ok):
		return {"ok": false, "note": "文件写不进去（%s，错误 %d）。" % [str(result.step), int(result.error)]}
	return {"ok": true, "note": ""}


## 默认的文件名，界面拿去填在保存框里。
func suggested_save_name() -> String:
	var role_name: String = str(State.role(run).get("name", "一局")) if not run.is_empty() else "一局"
	var stamp := "%04d%02d%02d-%02d%02d" % [
		int(Time.get_datetime_dict_from_system().year), int(Time.get_datetime_dict_from_system().month),
		int(Time.get_datetime_dict_from_system().day), int(Time.get_datetime_dict_from_system().hour),
		int(Time.get_datetime_dict_from_system().minute)]
	return SavePack.suggest_name(run, role_name, stamp)


## 从 .jyz 导入并直接接管那一局。
## **顶掉之前先把手上这一卷另存一份**到 user://backups/——导入不该让玩家丢掉正在玩的局，
## 有了这一步就不必再弹一个"确定要覆盖吗"，玩家事后想回去还能导回来。
## 返回 {"ok": bool, "note": String, "info": Dictionary}。
func import_save_from(path: String) -> Dictionary:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return {"ok": false, "note": "请先处理未完成的回溯，再导入存档。", "info": {}}
	if no_save:
		return {"ok": false, "note": "当前禁止写盘，不能导入存档。", "info": {}}
	if not FileAccess.file_exists(path):
		return {"ok": false, "note": "找不到这个文件。", "info": {}}
	var parsed := SavePack.parse(FileAccess.get_file_as_string(path))
	if not bool(parsed.ok):
		return {"ok": false, "note": str(parsed.note), "info": {}}
	var backup := _backup_before_import()
	if not bool(backup.ok):
		return {"ok": false, "note": str(backup.note), "info": {}}
	var data: Dictionary = parsed.data
	# 写盘成功之前不接管内存，也不写跨轮回底稿。留档失败和存档失败都必须让界面报错。
	var written := SaveFile.write_preserving_backup(save_path, data)
	if not bool(written.ok):
		return {"ok": false, "note": "导入未完成：存档写入失败（%s，错误 %d）。原来的一卷未接管。" % [str(written.step), int(written.error)], "info": {"backup": str(backup.path)}}
	_clear_placement()
	run = data.get("run", {})
	snapshots = data.get("snapshots", {})
	_recovering_backup = false
	save_notice = ""
	var info: Dictionary = parsed.info
	info["backup"] = str(backup.path)
	return {"ok": true, "note": "", "info": info}


## 导入前留下可直接导回的 .jyz；盘上有档但都不可读时，不能覆盖原件。
func _backup_before_import() -> Dictionary:
	var previous := {"run": run, "snapshots": snapshots} if not run.is_empty() else {}
	if previous.is_empty() and not no_save:
		for source in [save_path, save_path + SaveFile.BAK]:
			if not FileAccess.file_exists(source): continue
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(source)) != OK: continue
			var candidate = json.data
			if candidate is Dictionary and _import_backup_candidate(candidate):
				previous = candidate
				break
		if previous.is_empty() and has_save():
			return {"ok": false, "path": "", "note": "原存档与备份都读不出来，已保留原文件；请先手动留存后再导入。"}
	if previous.is_empty(): return {"ok": true, "path": "", "note": ""}
	if no_save: return {"ok": false, "path": "", "note": "当前禁止写盘，不能为原来的一卷留档。"}
	var dir := "user://backups"
	var stamp := _stamp_text()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if error != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return {"ok": false, "path": "", "note": "无法创建导入前备份目录，原来的一卷未改动。"}
	var target := dir.path_join("导入前-%s.jyz" % stamp)
	var suffix := 1
	while FileAccess.file_exists(target) or FileAccess.file_exists(target + SaveFile.BAK):
		target = dir.path_join("导入前-%s-%d.jyz" % [stamp, suffix])
		suffix += 1
	var env := SavePack.pack(previous, str(ProjectSettings.get_setting("application/config/version", "?")), stamp)
	var contents := SavePack.to_text(env)
	if not bool(SavePack.parse(contents).ok):
		return {"ok": false, "path": "", "note": "原来的一卷无法打包成可导回的存档，未进行导入。"}
	var result := SaveFile.write_text(target, contents)
	if not bool(result.ok):
		return {"ok": false, "path": "", "note": "无法写入导入前备份（%s，错误 %d），原来的一卷未改动。" % [str(result.step), int(result.error)]}
	return {"ok": true, "path": ProjectSettings.globalize_path(target), "note": ""}


## 过滤语义损坏的主档，再检查信封确实能通过导入解析；失败时继续尝试备档。
func _import_backup_candidate(data: Dictionary) -> bool:
	if not data.get("run") is Dictionary or not data.get("snapshots", {}) is Dictionary: return false
	var old_run: Dictionary = data.run
	if str(old_run.get("role", "")) not in Data.table("roles"): return false
	if str(old_run.get("phase", "")) not in ["pre", "post", "dead", "ending"]: return false
	for snap in data.get("snapshots", {}).values():
		if not snap is Dictionary: return false
	var envelope := SavePack.pack(data, str(ProjectSettings.get_setting("application/config/version", "?")), "backup")
	return bool(SavePack.parse(SavePack.to_text(envelope)).ok)


## 导入完成以后该落在哪一页：进行中就回到宅院，死了就回残页，了结就回结局。
func screen_for_run() -> String:
	return _screen_for_phase()


## 写盘失败（磁盘满、目录没权限）不能只在控制台留一行，玩家得知道这一局可能留不住。
func _warn_save_failed(result: Dictionary) -> void:
	push_error("存档写入失败：%s（错误 %d）" % [result.step, int(result.error)])
	if _save_warned: return
	_save_warned = true
	save_notice = "存档写不进磁盘（%s），关掉游戏这一局会丢。" % result.step
	toast.emit(save_notice)


## 读不出的旧档改名留底，免得被下一次写盘直接盖掉。
func _preserve_broken(path: String) -> void:
	if not FileAccess.file_exists(path): return
	var kept := path + ".bad"
	if FileAccess.file_exists(kept):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(kept))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(kept))


func resolved_memory_path() -> String:
	if memory_path != "": return memory_path
	# Existing scratch-save tests must never write or read the player's root archive.
	if save_path != SAVE_PATH or meta_path != META_PATH: return ""
	return memory_path_for(res_is_readonly())


## 前世档案落在哪：只读（打包后 / 只读盘）就落 user://，否则写项目根（开发时看得见）。
static func memory_path_for(readonly: bool) -> String:
	return "user://Memory.md" if readonly else "res://Memory.md"


## res:// 该不该当档案目录。打包版一律不——它的 res:// 在 pck 里只读；
## 开发时再探一下磁盘上到底能不能写（项目放在只读盘上时同样该退 user://）。
## 两道都留着：OS.has_feature("template") 在真导出件里为真，探针在开发态为真，
## 单靠任何一个都会漏掉另一种情况。
static func res_is_readonly() -> bool:
	if OS.has_feature("template"):
		return true
	return not res_writable()


## res:// 能不能写。结果缓存，一次进程只探一次。
static var _res_writable := -1

static func res_writable() -> bool:
	if _res_writable >= 0:
		return _res_writable == 1
	# Claim a fresh directory atomically before creating anything inside it.
	# A fixed filename could truncate an unrelated existing file.
	for attempt in 4:
		var probe := "res://.write_probe_" + Crypto.new().generate_random_bytes(16).hex_encode()
		if _probe_writable_directory(probe):
			_res_writable = 1
			return true
	_res_writable = 0
	return false


static func _probe_writable_directory(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	# make_dir is the ownership boundary: if anything already exists at this
	# name, never open, replace, or clean it up.
	if DirAccess.make_dir_absolute(absolute) != OK: return false
	var file_path := path.path_join("probe")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	var opened := file != null
	if opened: file.close()
	var file_removed := not opened or DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path)) == OK
	var directory_removed := DirAccess.remove_absolute(absolute) == OK
	return opened and file_removed and directory_removed


func _sync_life_memory() -> void:
	if no_save: return
	var path := resolved_memory_path()
	if path == "": return
	var error := MemoryFile.sync(meta, path)
	if error != OK and memory_status != "write_failed":
		toast.emit("前世档案没能写进文件；这一轮的记录仍留在存档里。")
	memory_status = "updated" if error == OK else "write_failed"


func read_life_memory() -> Dictionary:
	if _rewind_pending(): return {}
	if no_save or resolved_memory_path() == "": return {}
	_sync_life_memory()
	return MemoryFile.read_context(resolved_memory_path())


func _delete_save() -> bool:
	if no_save: return true
	var result := SaveFile.forget(save_path)
	if not bool(result.ok):
		save_notice = "旧卷已结算，但存档清理失败；请检查文件占用和目录权限后重试。"
		toast.emit(save_notice)
		return false
	if save_notice == "旧卷已结算，但存档清理失败；请检查文件占用和目录权限后重试。":
		save_notice = ""
	return true


# ---------- 试玩报告 ----------

## 把这一局打包成一册能发出去的取证：报告 + 存档 + 底稿 + 前世档案。
## 玩家说"有点难"没法下手；有了种子、死因账本和最后几十条记录，就能在本地复现。
## 返回 {"ok": bool, "dir": String, "files": Array, "note": String}；dir 是绝对路径，界面直接显示。
func export_playtest() -> Dictionary:
	if _rewind_pending():
		_ensure_rewind_resolved()
		return {"ok": false, "dir": "", "files": [], "note": "请先处理未完成的回溯，再导出试玩报告。"}
	var created := _create_report_dir(_stamp_text())
	if not bool(created.ok):
		return {"ok": false, "dir": "", "files": [], "note": str(created.note)}
	return _export_playtest_to(str(created.dir))


## 每次导出独占新目录，同秒重复点击也不会覆盖或混入前一份报告。
func _create_report_dir(stamp: String) -> Dictionary:
	var parent := "user://reports"
	var parent_abs := ProjectSettings.globalize_path(parent)
	var error := DirAccess.make_dir_recursive_absolute(parent_abs)
	if error != OK and not DirAccess.dir_exists_absolute(parent_abs):
		return {"ok": false, "dir": "", "note": "建不了报告目录（错误 %d）。" % error}
	for i in range(1000):
		var name := stamp if i == 0 else "%s-%d" % [stamp, i]
		var dir := parent.path_join(name)
		var absolute := ProjectSettings.globalize_path(dir)
		if DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(dir): continue
		error = DirAccess.make_dir_absolute(absolute)
		if error == OK: return {"ok": true, "dir": dir, "note": ""}
		if DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(dir): continue
		return {"ok": false, "dir": "", "note": "建不了报告目录（错误 %d）。" % error}
	return {"ok": false, "dir": "", "note": "报告目录已满，无法创建新报告。"}


## 只写新报告目录，不触碰存档、备份或此前保存失败的提醒。
func _export_playtest_to(dir: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(dir)
	var report_run := run.duplicate(true)
	var report_meta := meta.duplicate(true)
	var report_snapshots := snapshots.duplicate(true)
	var files: Array = []
	var source := "current" if not report_run.is_empty() else ("disk" if FileAccess.file_exists(save_path) else "none")
	var snapshot_note := "附件中的本局存档是导出时的内存快照，含回溯页；原存档未改写。" if source == "current" else ("当前未载入本局，附件是磁盘上已有的主存档，报告没有读取其局面。" if source == "disk" else "当前未载入本局，磁盘上没有主存档；若有备份将单独列为附件。")
	var text := PlaytestReport.build(report_run.duplicate(true), report_meta.duplicate(true), _report_ctx(report_run, report_snapshots))
	text = text.replace("# 劫余录 试玩报告\n", "# 劫余录 试玩报告\n\n" + snapshot_note + "\n")
	var error := _write_text(dir.path_join("report.md"), text)
	if error != OK:
		return {"ok": false, "dir": absolute, "files": [], "note": "报告写不进去（错误 %d）" % error}
	files.append("report.md")
	var save_name := save_path.get_file()
	var meta_name := meta_path.get_file()
	if save_name == "" or meta_name == "" or save_name == meta_name or save_name in ["report.md", "Memory.md"] or meta_name in ["report.md", "Memory.md", save_name + SaveFile.BAK]:
		return {"ok": false, "dir": absolute, "files": files, "note": "报告文件名冲突，无法安全导出。"}
	# 正在玩的局和底稿以同一份内存快照为准，不依赖最近一次自动存档。
	if not report_run.is_empty():
		var saved := SaveFile.write(dir.path_join(save_name), {"run": report_run, "snapshots": report_snapshots})
		if not bool(saved.ok):
			return {"ok": false, "dir": absolute, "files": files, "note": "当前局快照写入失败（%s，错误 %d）。" % [str(saved.step), int(saved.error)]}
		files.append(save_name)
	elif FileAccess.file_exists(save_path):
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(dir.path_join(save_name)))
		if error != OK: return {"ok": false, "dir": absolute, "files": files, "note": "存档复制失败（错误 %d）。" % error}
		files.append(save_name)
	var saved_meta := SaveFile.write(dir.path_join(meta_name), report_meta)
	if not bool(saved_meta.ok):
		return {"ok": false, "dir": absolute, "files": files, "note": "跨轮回底稿写入失败（%s，错误 %d）。" % [str(saved_meta.step), int(saved_meta.error)]}
	files.append(meta_name)
	# 原有备份和前世档案仍附带；只要存在却复制失败，就明确报告失败。
	if FileAccess.file_exists(save_path + SaveFile.BAK):
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path + SaveFile.BAK), ProjectSettings.globalize_path(dir.path_join(save_name + SaveFile.BAK)))
		if error != OK: return {"ok": false, "dir": absolute, "files": files, "note": "存档备份复制失败（错误 %d）。" % error}
		files.append(save_name + SaveFile.BAK)
	var memory := resolved_memory_path()
	if memory != "" and FileAccess.file_exists(memory):
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(memory), ProjectSettings.globalize_path(dir.path_join("Memory.md")))
		if error != OK: return {"ok": false, "dir": absolute, "files": files, "note": "前世档案复制失败（错误 %d）。" % error}
		files.append("Memory.md")
	return {"ok": true, "dir": absolute, "files": files, "note": "", "save_source": source}


func _report_ctx(report_run: Dictionary, report_snapshots: Dictionary) -> Dictionary:
	var changed := {}
	var saved := InputCfg.read()
	for action in saved:
		var names := []
		for key in saved[action]:
			names.append(InputCfg.key_name(int(key)))
		changed[InputCfg.LABELS.get(action, action)] = "、".join(names)
	var size := "无"
	if not report_run.is_empty():
		size = "%.0f KB（当前快照）" % (float(JSON.stringify({"run": report_run, "snapshots": report_snapshots}, "\t").to_utf8_buffer().size()) / 1024.0)
	elif FileAccess.file_exists(save_path):
		size = "%.0f KB" % (float(FileAccess.get_file_as_string(save_path).length()) / 1024.0)
	var director = "unloaded"
	if StoryDirector.offline_build():
		director = "offline"
	elif not report_run.is_empty():
		director = bool(Director.state(report_run.duplicate(true)).enabled)
	var window := DisplayServer.window_get_size()
	return {
		"now": "%s %s" % [State.today_text(), Time.get_time_string_from_system().left(5)],
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"engine": str(Engine.get_version_info().get("string", "?")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"resolution": "%d×%d" % [window.x, window.y],
		"save_bytes": size,
		"bindings": changed,
		"director": director,
	}


func _stamp_text() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [int(d.year), int(d.month), int(d.day), int(d.hour), int(d.minute), int(d.second)]


func _write_text(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	f.store_string(text)
	var error := f.get_error()
	f.close()
	return error


## 只给测试读跨轮回底稿用（真读档走 continue_game，会退备份并告知玩家）。
func _read_json(path: String) -> Dictionary:
	return Data.normalize(SaveFile.read(path).data)
