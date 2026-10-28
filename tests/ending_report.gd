extends SceneTree
## 结局复盘的规则测试：只写真发生过的事、条目有上限、没数据时不编。
## 运行：godot --headless --path . --script res://tests/ending_report.gd

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Ending = preload("res://scripts/core/ending_report.gd")
const Mainline = preload("res://scripts/core/mainline.gd")

## 脚本错误只中止当前函数、_initialize 照样往下跑：每个测试跑到底才记一次，最后对账
const TESTS := 6

var checks := 0
var failures := 0
var finished := 0


func _initialize() -> void:
	Data.ensure()
	test_empty()
	test_calm_win()
	test_damage()
	test_deeds_and_costs()
	test_escape()
	test_cap()
	check(finished == TESTS, "只跑完 %d / %d 个测试，有测试中途崩了" % [finished, TESTS])
	print("[ending_report] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


func test_empty() -> void:
	check((Ending.lines({}) as Array).is_empty(), "空局却给了复盘")

	# 什么都没发生的一局：只有"三面"那一条，伤害/手段/代价都不该出现
	var calm := _win()
	var lines := Ending.lines(calm)
	var text := _join(lines)
	check(text.contains("撑到最后"), "连三面都没写")
	check(not text.contains("气血"), "没受过伤却写了气血：%s" % text)
	check(not text.contains("修补"), "没修过门却写了修补：%s" % text)
	check(not text.contains("残页"), "没用过残页却写了残页：%s" % text)
	check(not text.contains("斩尸"), "没杀过却写了斩尸：%s" % text)
	finished += 1


func test_calm_win() -> void:
	var calm := _win()
	calm.door.cur = 100
	calm.window.cur = 60
	calm.wall.cur = 120
	var text := _join(Ending.lines(calm))
	for sid in ["院门", "窗", "墙"]:
		check(text.contains(sid), "三面里漏了 %s：%s" % [sid, text])
	check(text.contains("100/100"), "没写门的数值：%s" % text)
	check(text.contains("撑到最后"), "守宅结局没写撑到最后：%s" % text)
	finished += 1


func test_damage() -> void:
	var run := _win()
	State.hurt(run, 40.0, "starve")
	State.hurt(run, 25.0, "freeze")
	var text := _join(Ending.lines(run))
	check(text.contains("65"), "失血总量不对：%s" % text)
	check(text.contains("受饿"), "没点出最狠的那一路：%s" % text)
	check(text.contains("40"), "没给出最狠那一路的数值：%s" % text)
	finished += 1


func test_deeds_and_costs() -> void:
	var run := _win()
	run.tally.repair_door = 3
	run.kills = 12
	run.tally.home_trips = 2
	run.rebirths_left = 1
	run.companions = ["afu", "xiaoman"]
	var text := _join(Ending.lines(run))
	check(text.contains("修补门窗墙 3 次"), "没写修了几次：%s" % text)
	# 斩尸在结局页标题下已经写过，复盘里再写就重复了
	check(not text.contains("斩尸"), "复盘重复写了斩尸：%s" % text)
	# home_trips 是备劫回家卸货的次数，不能说成劫后出门
	check(not text.contains("出门") and not text.contains("趟"), "把备劫卸货写成了出门：%s" % text)
	check(text.contains("残页 2 张"), "没写用掉几张残页：%s" % text)
	check(text.contains("同院 2 人"), "没写同伴：%s" % text)
	finished += 1


func test_escape() -> void:
	# 撤离的人第20夜前已经离城：三面写离城时的样子，不说撑到最后
	var run := _win()
	Mainline.state(run).ending = Mainline._ending_data("escape")
	var text := _join(Ending.lines(run))
	check(text.contains("离城时"), "撤离结局没写离城时：%s" % text)
	check(not text.contains("撑到最后"), "撤离了还写撑到最后：%s" % text)
	finished += 1


func test_cap() -> void:
	var run := _win()
	State.hurt(run, 30.0, "starve")
	run.tally.repair_door = 5
	run.kills = 8
	run.tally.home_trips = 3
	run.rebirths_left = 0
	run.companions = ["afu"]
	var lines := Ending.lines(run)
	check(lines.size() <= Ending.MAX_LINES, "超过 %d 条：%d" % [Ending.MAX_LINES, lines.size()])
	for line in lines:
		check(str(line.get("label", "")) != "", "有一条没有标签：%s" % str(line))
		check(str(line.get("text", "")).length() > 2, "有一条没内容：%s" % str(line))
	finished += 1


# ---------- 小工具 ----------

## 一局活到第 20 日的干净局面。
func _win() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261027)
	Pre.start_disaster(run)
	run.pday = State.STORY_DAYS
	run.phase = "ending"
	run.tally = {"goals": [], "vows": [], "boons": [], "bought": {}, "repair_door": 0, "home_trips": 0}
	run.rebirths_left = 3
	run.companions = []
	return run


func _join(lines: Array) -> String:
	var parts := []
	for l in lines:
		parts.append(str(l.text))
	return " / ".join(parts)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
