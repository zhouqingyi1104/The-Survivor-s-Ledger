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
## 正在摆放的家具（空 = 不在摆放）：界面选好家具后置上，点地面放下。
var placing := ""
var placing_rot := 0
## 摆放预览的固定落点（截图和测试用；null 时跟着鼠标）
var placing_at = null
## 选难度界面挂着：刚挑的身份，定了难度就照这个开局
var pending_role := ""
## 已经定好的难度，接着去挑挑战（了愿）
var pending_difficulty := "normal"


func _ready() -> void:
	Data.ensure()
	meta = _read_json(meta_path)
	if meta.is_empty():
		meta = State.new_meta()


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


func new_game(role_id: String, difficulty_id := "normal", goals: Array = []) -> void:
	run = State.new_run(role_id, meta, randi(), difficulty_id, goals)
	snapshots = {}
	last_gain = {}
	_after()


## 选完身份，先去定难度（原版 DifficultySelect / ChallengeSetup）。
func pick_difficulty(role_id: String) -> void:
	pending_role = role_id
	pending_difficulty = "normal"
	go("difficulty")


func has_save() -> bool:
	return not no_save and FileAccess.file_exists(save_path)


func continue_game() -> void:
	var data := _read_json(save_path)
	if data.is_empty():
		toast.emit("存档读不出来。")
		return
	data = Migrate.save(data)
	run = data.get("run", {})
	snapshots = data.get("snapshots", {})
	_after()


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
func end_run(bonus := 0) -> Dictionary:
	last_gain = Ledger.end_run(run, meta, bonus)
	if run.phase == "ending":
		meta.endings = int(meta.endings) + 1
	save_meta()
	return last_gain


## 带着记忆回到三日之前（同一身份重开）。
func restart_from_cover() -> void:
	var role_id: String = run.role
	var d := str(run.get("difficulty", "normal"))
	end_run(10 if run.phase == "ending" else 0)
	new_game(role_id, d)


func close_book() -> void:
	end_run(10 if run.phase == "ending" else 0)
	run = {}
	snapshots = {}
	_delete_save()
	go("title")
	changed.emit()


## 劫满后守宅：转无尽，尸潮继续升级。
func keep_living() -> void:
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
	_write_json(save_path, {"run": run, "snapshots": snapshots})
	save_meta()


func save_meta() -> void:
	if no_save:
		return
	_write_json(meta_path, meta)


func _delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写不了存档：" + path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return Data.normalize(parsed)
