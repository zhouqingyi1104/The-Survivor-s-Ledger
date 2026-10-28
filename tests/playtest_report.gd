extends SceneTree
## 试玩报告的规则测试：写的是不是事实、有没有编、该截的截没截、缺数据时会不会崩。
## 运行：godot --headless --path . --script res://tests/playtest_report.gd
##
## 报告的唯一用途是"别人照着他发来的东西能复现那一局"，所以每条断言都对着这一条来。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")
const Report = preload("res://scripts/core/playtest_report.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_empty_run()
	test_dead_run()
	test_log_tail()
	test_legacy_no_ledger()
	test_ending_run()
	test_missing_ctx()
	test_no_local_paths()
	print("[playtest_report] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、没有在进行的局 ----------

func test_empty_run() -> void:
	var text := Report.build({}, State.new_meta(), {"version": "0.10.0", "engine": "4.7.2"})
	check(text.contains("没有在进行的局"), "空档时没说清楚没有局")
	check(not text.contains("**身死**"), "空档时凭空写了身死")
	check(not text.contains("本世共失血"), "空档时凭空写了失血")
	check(text.contains("0.10.0"), "版本没写进报告")
	check(text.contains("跨轮回底稿"), "空档时少了底稿段")
	check(text.contains("请顺手回答三句"), "空档时少了问题段")


# ---------- 二、一局死掉的 ----------

func test_dead_run() -> void:
	var run := _dead_run()
	var text := Report.build(run, State.new_meta(), {"version": "0.10.0", "engine": "4.7.2", "os": "Windows", "resolution": "1600×900"})
	check(text.contains("落第书生"), "没写身份")
	check(text.contains(State.diff_name(run)), "没写难度")
	check(text.contains(str(run.seed)), "没写种子——这条不写就没法复现")
	check(text.contains("**身死**"), "死局没写身死")
	check(text.contains(str(run.death_cause)), "没写死因判词")
	check(text.contains("本世共失血"), "有账本却没写失血构成")
	check(text.contains("最后一击"), "没写最后一击")
	check(text.contains("1600×900"), "没写分辨率")
	check(text.contains("战果"), "没写战果")


# ---------- 三、日志只留末尾 ----------

func test_log_tail() -> void:
	var run := _dead_run()
	run.log = []
	for i in 220:
		run.log.append("【第1日·06:00】第 %d 条记录" % i)
	var text := Report.build(run, State.new_meta())
	var count := 0
	for line in text.split("\n"):
		if line.begins_with("- 【第1日"):
			count += 1
	check(count == Report.LOG_TAIL, "日志没截到 %d 条：%d" % [Report.LOG_TAIL, count])
	check(text.contains("第 219 条记录"), "最后一条日志没带上")
	check(not text.contains("第 0 条记录"), "最前面的日志也带上了（截断没生效）")


# ---------- 四、没有账本的老存档不编死因 ----------

func test_legacy_no_ledger() -> void:
	var run := _dead_run()
	run.erase("hp_log")
	run.erase("last_hurt")
	var text := Report.build(run, State.new_meta())
	check(text.contains("没有掉血记录"), "老存档没说明没有掉血记录")
	check(not text.contains("本世共失血"), "老存档凭空写了失血构成")
	check(not text.contains("最后一击"), "老存档凭空写了最后一击")


# ---------- 五、结局局 ----------

func test_ending_run() -> void:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261026)
	Pre.start_disaster(run)
	run.pday = 20
	run.phase = "ending"
	var text := Report.build(run, State.new_meta())
	var end: Dictionary = Mainline.ending(run)
	check(not end.is_empty(), "造不出结局数据，用例前提不成立")
	check(text.contains("**结局**"), "结局局没写结局")
	check(text.contains(str(end.get("title", ""))), "没写结局标题")
	check(not text.contains("**身死**"), "结局局也写成了身死")


# ---------- 六、ctx 缺失也不崩 ----------

func test_missing_ctx() -> void:
	var text := Report.build(_dead_run(), State.new_meta(), {})
	check(text.contains("版本：?"), "缺版本时没有占位符")
	check(text.contains("按键：全部默认"), "缺改键信息时没兜底成默认")
	check(text.contains("动态世情：未知"), "缺动态世情信息时应如实显示未知")
	var enabled := Report.build(_dead_run(), State.new_meta(), {"director": true})
	check(enabled.contains("已启用（不代表服务已连接）"), "启用意愿不能被当成连接成功")
	var disabled := Report.build(_dead_run(), State.new_meta(), {"director": false})
	check(disabled.contains("动态世情：关闭"), "关闭状态未正确展示")
	var offline := Report.build(_dead_run(), State.new_meta(), {"director": "offline"})
	check(offline.contains("动态世情：本包离线（不连接服务）"), "打包版的报告没写明离线")
	check(not offline.contains("已启用") and not offline.contains("动态世情：关闭"), "离线包的报告混进了开关状态")


# ---------- 七、不要把本机路径带出去 ----------

func test_no_local_paths() -> void:
	var run := _dead_run()
	var text := Report.build(run, State.new_meta(), {"os": "Windows", "engine": "4.7.2"})
	check(not text.contains("C:\\"), "报告里带上了本机绝对路径")
	check(not text.contains("res://"), "报告里带上了 res:// 路径")
	check(not text.contains(OS.get_environment("USERNAME")), "报告里带上了本机用户名")


# ---------- 小工具 ----------

## 一局玩到第 3 日、被院破扑死的局面（带真账本）。
func _dead_run() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261026)
	Pre.start_disaster(run)
	run.pday = 3
	run.t = 2 * 1440 + 900
	State.hurt(run, 30.0, "starve")
	State.hurt(run, 70.0, "overrun")
	State.note(run, "院墙被撞破。")
	State.check_death(run, DeathReport.verdict(run))
	return run


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
