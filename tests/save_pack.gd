extends SceneTree
## 存档信封（.jyz）的规则测试：能原样往返、坏文件说人话、老版本会升级、文件名安全。
## 运行：godot --headless --path . --script res://tests/save_pack.gd
##
## 这一层是玩家的长期备份，坏掉的代价比游戏崩一次大得多，所以"拒绝"也要说清楚为什么。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_round_trip()
	test_envelope_fields()
	test_rejects()
	test_old_version_upgraded()
	test_snapshots_travel()
	test_suggest_name()
	print("[save_pack] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、往返 ----------

func test_round_trip() -> void:
	var save := {"run": _run(), "snapshots": {"1": _run()}}
	var text := SavePack.to_text(SavePack.pack(save, "0.10.0", "2026-10-27-1245"))
	check(text.contains("\n"), "导出的文本没有缩进（出问题没法用记事本看）")
	var got := SavePack.parse(text)
	check(bool(got.ok), "自家人打的包自己读不出来：%s" % str(got.note))
	var run: Dictionary = got.data.get("run", {})
	check(int(run.get("seed", 0)) == int(save.run.seed), "种子在往返里变了")
	check(int(run.get("pday", 0)) == int(save.run.pday), "天数在往返里变了")
	check(str(run.get("role", "")) == "scholar", "身份在往返里变了")


# ---------- 二、信封字段 ----------

func test_envelope_fields() -> void:
	var save := {"run": _run(), "snapshots": {}}
	var env := SavePack.pack(save, "0.10.0", "2026-10-27-1245")
	check(str(env.format) == SavePack.FORMAT, "格式标记不对")
	check(int(env.format_version) == SavePack.FORMAT_VERSION, "信封版本不对")
	check(str(env.game_version) == "0.10.0", "游戏版本没记进去")
	check(int(env.run_version) == int(save.run.version), "里面那局的存档版本没记进去")
	check(str(env.exported_at) == "2026-10-27-1245", "导出时间没记进去")


# ---------- 三、坏文件 ----------

func test_rejects() -> void:
	var cases := [
		["", "空文件"],
		["{不是 json", "半截 JSON"],
		["{\"hello\": 1}", "别的 json"],
		[JSON.stringify({"format": "other-game", "format_version": 1, "data": {}}), "别人的格式标记"],
		[JSON.stringify({"format": SavePack.FORMAT, "format_version": 99, "data": {}}), "未来版本的信封"],
		[JSON.stringify({"format": SavePack.FORMAT, "format_version": 1, "data": {}}), "没有 data"],
		[JSON.stringify({"format": SavePack.FORMAT, "format_version": 1, "data": {"run": {}}}), "空的 run"],
	]
	for c in cases:
		var got := SavePack.parse(str(c[0]))
		check(not bool(got.ok), "%s 竟然被接受了" % str(c[1]))
		check(str(got.note) != "", "%s 拒绝时没给玩家一句人话" % str(c[1]))
	# 拒绝的话术要能区分"这不是存档"和"版本太新"
	var not_save := SavePack.parse("{\"hello\": 1}")
	check(str(not_save.note).contains("格式标记"), "认不出存档时的话术不对：%s" % str(not_save.note))
	var too_new := SavePack.parse(JSON.stringify({"format": SavePack.FORMAT, "format_version": 99, "data": {"run": {"version": 21}}}))
	check(str(too_new.note).contains("更新"), "版本太新时的话术不对：%s" % str(too_new.note))


# ---------- 四、老版本存档在导入时升级 ----------

func test_old_version_upgraded() -> void:
	var old_run := _run()
	old_run.version = 20
	old_run.pday = 7
	old_run.attrs.hp = 60
	old_run.attrs.hp_max = 90
	old_run.seed = 42
	var text := SavePack.to_text(SavePack.pack({"run": old_run, "snapshots": {}}, "0.9.0", "2026-10-01-0900"))
	var got := SavePack.parse(text)
	check(bool(got.ok), "老版本存档被拒了：%s" % str(got.note))
	check(int(got.data.get("run", {}).get("version", 0)) == Migrate.VERSION, "老存档没升到当前版本")
	check(bool(got.info.get("upgraded", false)), "没标出「这份存档被升级过」")
	check(int(got.data.get("run", {}).get("pday", 0)) == 7, "升级把天数弄丢了")


# ---------- 五、快照要跟着走 ----------

func test_snapshots_travel() -> void:
	var run := _run()
	var snap1 := run.duplicate(true)
	var snap2 := run.duplicate(true)
	snap2.pday = 2
	var save := {"run": run, "snapshots": {"1": snap1, "2": snap2}}
	var got := SavePack.parse(SavePack.to_text(SavePack.pack(save, "0.10.0", "x")))
	var snaps: Dictionary = got.data.get("snapshots", {})
	check(snaps.size() == 2, "快照没跟着走：%d 份（没有快照就翻不回昨日）" % snaps.size())
	check(snaps.has("1") and snaps.has("2"), "快照的键变了：%s" % str(snaps.keys()))


# ---------- 六、默认文件名 ----------

func test_suggest_name() -> void:
	var run := _run()
	var name := SavePack.suggest_name(run, "落第书生", "20261027-1245")
	check(name.ends_with(".jyz"), "默认名没有 .jyz 后缀：%s" % name)
	check(name.contains("第 1 日"), "默认名里没有天数：%s" % name)
	check(name.contains("落第书生"), "默认名里没有身份：%s" % name)
	check(not name.contains("/") and not name.contains("\\") and not name.contains(":"), "默认名里有非法字符：%s" % name)
	var weird := SavePack.suggest_name(run, "a/b:c*d?e", "20261027-1245")
	check(not weird.contains("/") and not weird.contains(":") and not weird.contains("*"), "身份名里的非法字符没被替换：%s" % weird)
	var pre := _run()
	pre.pday = 0
	check(SavePack.suggest_name(pre, "落第书生", "x").contains("备劫"), "备劫阶段的默认名不对")


# ---------- 小工具 ----------

func _run() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261027)
	Pre.start_disaster(run)
	run.seed = 20261027
	run.pday = 1
	return run


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
