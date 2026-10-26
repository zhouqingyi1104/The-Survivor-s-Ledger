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
## 空值为项目根 Memory.md；隔离存档的测试必须显式指定独立路径。
var memory_path := ""
var memory_status := "local"
## 正在摆放的家具（空 = 不在摆放）：界面选好家具后置上，点地面放下。
var placing := ""
var placing_rot := 0
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
	Data.ensure()
	var got := SaveFile.read(meta_path)
	var data: Dictionary = Data.normalize(got.data)
	meta = data if not data.is_empty() else State.new_meta()
	# 主档坏了通常是上次写盘中途断掉：已经退回备份就读回来，两份都坏才另起，
	# 并把读不出的那份另存留底（不直接覆盖），玩家至少还有东西可以发给别人看。
	if got.note in ["main_bad", "main_missing"]:
		save_notice = "跨轮回的底稿没能完整读回，已改用上一份备份。"
		_preserve_broken(meta_path)
	elif got.note == "none" and FileAccess.file_exists(meta_path):
		save_notice = "跨轮回的底稿读不出来，已另存留底并重新起账。"
		_preserve_broken(meta_path)


# ---------- 界面切换 ----------

func go(target: String) -> void:
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
	var res = fn.call()
	if typeof(res) == TYPE_STRING and res != "":
		toast.emit(res)
		Sfx.play("ui_error", -9.0, 0.0)
	_after()
	return res


func _after() -> void:
	if run.is_empty():
		changed.emit()
		return
	# 每天卯时开始时记一页快照，翻生死簿时翻回这里
	if run.phase == "post" and int(run.pday) > 0 and not snapshots.has(str(run.pday)):
		Ledger.snapshot(run, snapshots)
	save_game()
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
	run = candidate
	snapshots = {}
	last_gain = {}
	pending_opening_setup = {}
	_after()
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
	# 备份也算——主档写坏时玩家仍然能续上，别在标题界面把入口藏掉
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + SaveFile.BAK)


## 主档和备份各自还能不能用：标题界面用它决定「续写此录」后面跟不跟一句实话。
func save_status() -> Dictionary:
	return SaveFile.status(save_path)


## 续上一卷。返回 false 表示主档和备份都读不出来（此时不静默新开，交给调用方决定）。
func continue_game() -> bool:
	var got := SaveFile.read(save_path)
	if got.data.is_empty():
		save_notice = "这一卷的主档和备份都读不出来。原文件留在存档目录里，没有删。"
		toast.emit("存档读不出来。")
		return false
	var data: Dictionary = Data.normalize(got.data)
	data = Migrate.save(data)
	run = data.get("run", {})
	snapshots = data.get("snapshots", {})
	if got.note != "main_ok":
		save_notice = ("主存档不在了，已经接着上一份备份往下写（可能退回一步）。" if got.note == "main_missing"
			else "主存档写坏了，已经接着上一份备份往下写（可能退回一步）。")
		toast.emit(save_notice)
	else:
		save_notice = ""
	_after()
	return true


## 翻回昨日。
func rewind() -> void:
	var back := Ledger.rewind(run, snapshots, meta)
	if back.is_empty():
		toast.emit("翻不回去了。")
		return
	run = back
	save_meta()
	_after()


## 这一轮结束（翻回扉页 / 合上 / 劫满），结算道心。
func ending_bonus(value: Dictionary = {}) -> int:
	return Ledger.ending_bonus(run if value.is_empty() else value)


func _same_life(expected_life: String) -> bool:
	return not run.is_empty() and (expected_life == "" or str(Past.state(run).id) == expected_life)


func end_run(bonus := -1) -> Dictionary:
	if run.is_empty(): return {"lines": [], "total": 0, "days": 0, "settled": false}
	last_gain = Ledger.end_run(run, meta, bonus)
	if last_gain.get("settled", false) and run.phase == "ending":
		meta.endings = int(meta.endings) + 1
	save_meta()
	return last_gain


## 带着记忆回到三日之前（同一身份重开）。
func restart_from_cover(expected_life := "") -> void:
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
	end_run(Ledger.ending_bonus(run))
	var result := new_game(role_id, d, [], [], [], endless, daily, mates, opening_id)
	if result != "":
		new_game(role_id, d, [], [], [], endless, daily, mates, "plain")
		toast.emit("先前开局已不适用，这一世使用普通行囊；可在结局页另选开局。")


## Settle this life once, then explicitly choose how to prepare the next one.
func choose_next_opening(expected_life := "") -> void:
	if not _same_life(expected_life) or not run.get("phase", "") in ["dead", "ending"]: return
	var role_id := str(run.role)
	var difficulty_id := str(run.get("difficulty", "normal"))
	var setup := {"endless": bool(run.get("endless", false)), "daily": Past.daily(run), "mates": (run.get("companions", []) as Array).duplicate()}
	end_run(Ledger.ending_bonus(run))
	run = {}
	snapshots = {}
	_delete_save()
	pending_role = role_id
	pending_difficulty = difficulty_id
	pending_opening_setup = setup
	go("challenge")


func close_book(expected_life := "") -> void:
	if not _same_life(expected_life): return
	end_run(Ledger.ending_bonus(run))
	run = {}
	snapshots = {}
	_delete_save()
	go("title")
	changed.emit()


## 劫满后守宅：转无尽，尸潮继续升级。
func keep_living(expected_life := "") -> void:
	if not _same_life(expected_life): return
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
	if run.is_empty() or no_save:
		return
	var result := SaveFile.write(save_path, {"run": run, "snapshots": snapshots})
	if not result.ok:
		_warn_save_failed(result)
	save_meta()


func save_meta() -> void:
	if no_save:
		return
	var result := SaveFile.write(meta_path, meta)
	if not result.ok:
		_warn_save_failed(result)
		return
	_sync_life_memory()


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
	return "res://Memory.md"


func _sync_life_memory() -> void:
	if no_save: return
	var path := resolved_memory_path()
	if path == "": return
	var error := MemoryFile.sync(meta, path)
	if error != OK and memory_status != "write_failed":
		toast.emit("前世档案 Memory.md 未能写入，本轮记录仍保存在跨轮回存档中。")
	memory_status = "updated" if error == OK else "write_failed"


func read_life_memory() -> Dictionary:
	if no_save or resolved_memory_path() == "": return {}
	_sync_life_memory()
	return MemoryFile.read_context(resolved_memory_path())


func _delete_save() -> void:
	# 主档、备份、临时档一起删；只删主档的话，旧局会从 .bak 里活过来
	SaveFile.forget(save_path)


## 只给测试读跨轮回底稿用（真读档走 continue_game，会退备份并告知玩家）。
func _read_json(path: String) -> Dictionary:
	return Data.normalize(SaveFile.read(path).data)
