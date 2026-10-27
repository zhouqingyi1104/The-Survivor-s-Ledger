extends SceneTree
## 长局稳定性：把日数推到离谱的程度，看状态会不会膨胀、会不会崩、还能不能算。
## 运行：godot --headless --path . --script res://tests/longrun.gd
##
## 为什么要有这一套：无尽模式没有终点，谁也不知道玩家能守到第几日。
## 到那时如果日志无限长、快照无限多、某个函数按日循环，游戏会在"活得好好的时候"卡住。
## 这里用构造出来的极端局面提前把这条路走一遍——不用机器人真跑两千天。
##
## 时间断言一律留大余量（机器差异比代码退化更容易让测试假红），
## 真正钉死的是**体积**和**不崩**：那两条与机器无关。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Brief = preload("res://scripts/core/brief.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")
const Report = preload("res://scripts/core/playtest_report.gd")

var checks := 0
var failures := 0

## 存档体积的硬上限：正常一局 87–91KB，翻倍就说明有东西在无限长
const SIZE_LIMIT_KB := 200.0
## 从第 20 日到第 2000 日，体积允许涨多少（再多就是没封顶）
const SIZE_GROWTH_KB := 20.0


func _initialize() -> void:
	Data.ensure()
	test_no_bloat()
	test_log_and_snapshots_capped()
	test_still_runs()
	test_core_helpers_at_extreme_day()
	print("[longrun] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、体积不许膨胀 ----------

func test_no_bloat() -> void:
	var early := _save_text(20)
	var late := _save_text(2000)
	var early_kb := early.length() / 1024.0
	var late_kb := late.length() / 1024.0
	check(early_kb < SIZE_LIMIT_KB, "第 20 日的存档已经 %.0fKB，超过 %.0fKB 上限" % [early_kb, SIZE_LIMIT_KB])
	check(late_kb < SIZE_LIMIT_KB, "第 2000 日的存档 %.0fKB，超过 %.0fKB 上限" % [late_kb, SIZE_LIMIT_KB])
	check(late_kb - early_kb < SIZE_GROWTH_KB,
		"两千天里体积涨了 %.1fKB（上限 %.0fKB）——有东西没封顶" % [late_kb - early_kb, SIZE_GROWTH_KB])
	check(late.contains("\"run\""), "第 2000 日的存档里没有 run")


# ---------- 二、日志与快照确实封顶 ----------

func test_log_and_snapshots_capped() -> void:
	var run := _run_at(2000)
	# 猛写日志：封顶靠 State.note
	for i in 5000:
		State.note(run, "第 %d 条测试记录。" % i)
	check(run.log.size() <= State.LOG_LIMIT,
		"写了 5000 条日志，还剩 %d 条（上限 %d）" % [run.log.size(), State.LOG_LIMIT])
	check(run.log[run.log.size() - 1].contains("第 4999 条"), "封顶以后保留的不是最新的日志")

	# 快照同理：Ledger.snapshot 自己会裁
	var snaps := {}
	for day in range(1900, 2050):
		var probe := _run_at(day)
		Ledger.snapshot(probe, snaps)
	check(snaps.size() <= Ledger.SNAPSHOT_KEEP,
		"塞了 150 天的快照，还剩 %d 份（上限 %d）" % [snaps.size(), Ledger.SNAPSHOT_KEEP])
	var keys := snaps.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	check(int(keys[keys.size() - 1]) == 2049, "裁快照时没保留最新的：%s" % str(keys))


# ---------- 三、第 2000 日还能正常过一天 ----------

func test_still_runs() -> void:
	var run := _run_at(2000)
	var before_day := int(run.pday)
	var t0 := Time.get_ticks_usec()
	var stop := Post.advance(run, 1440)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 5000.0, "第 2000 日过一天用了 %.0fms（上限 5 秒），已经卡了" % ms)
	check(stop in ["", "blocked", "event", "dead", "ending", "wave", "raid", "dawn", "plan"],
		"过一天返回了意料之外的结果：%s" % stop)
	check(str(run.get("phase", "")) in ["post", "dead", "ending"], "过完一天局面坏了：%s" % str(run.get("phase", "")))
	var hp := int(State.attr(run, "hp"))
	check(hp >= 0 and hp <= int(State.attr_max(run, "hp")), "气血越界：%d / %d" % [hp, int(State.attr_max(run, "hp"))])
	check(int(run.pday) >= before_day, "日子倒着走了：%d → %d" % [before_day, int(run.pday)])


# ---------- 四、核心小工具在超大日数下不崩 ----------

func test_core_helpers_at_extreme_day() -> void:
	var run := _run_at(2000)
	var goal := Brief.goal(run)
	check(goal != "", "第 2000 日算不出目标句")
	check(Brief.countdown(run) != "", "第 2000 日算不出倒计时")
	var lines := Brief.lines(run)
	check(lines.size() >= 1, "第 2000 日一条要务都没有")
	check(lines.size() <= Brief.MAX_LINES, "第 2000 日要务超过 %d 条" % Brief.MAX_LINES)

	# 死了以后死因与报告也得能出（这两条都是玩家在极端局面下最需要的）
	State.hurt(run, 9999.0, "overrun")
	State.check_death(run, DeathReport.verdict(run))
	var rep := DeathReport.report(run)
	check(int(rep.total) > 0, "第 2000 日的死因账本是空的")
	check(str(rep.get("last", "")) != "", "第 2000 日没记下最后一击")
	var text := Report.build(run, State.new_meta(), {"version": "0.10.0"})
	check(text.contains("2000") or text.contains("第 2000 日"), "试玩报告里没写第 2000 日")


# ---------- 小工具 ----------

func _save_text(day: int) -> String:
	var run := _run_at(day)
	var snaps := {}
	for k in 5:
		snaps[str(day - k)] = run.duplicate(true)
	return JSON.stringify({"run": run, "snapshots": snaps})


## 一局"活到第 day 日"的局面：日志写满、无尽模式。
func _run_at(day: int) -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261027)
	Pre.start_disaster(run)
	run.endless = true
	run.pday = day
	run.t = (day - 1) * 1440 + 360
	for i in State.LOG_LIMIT:
		State.note(run, "第 %d 日的第 %d 条记录。" % [day, i])
	run.home = {"rice": 40, "firewood": 20, "charcoal": 10, "water": 20}
	return run


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
