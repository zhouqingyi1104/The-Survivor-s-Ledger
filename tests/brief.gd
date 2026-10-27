extends SceneTree
## 今日要务的规则测试：说的事必须成立、不成立就不说、最多四条、要命的排前面。
## 运行：godot --headless --path . --script res://tests/brief.gd
##
## 提示文案错了比没有提示更糟——玩家会按错误的信息去准备，所以每条都要对着状态断言。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Brief = preload("res://scripts/core/brief.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_empty_and_pre()
	test_quiet_day()
	test_broken_surface()
	test_wave_tonight()
	test_cold_without_fuel()
	test_no_food_or_water()
	test_cap_and_order()
	test_countdown()
	print("[brief] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、没有局 / 备劫阶段 ----------

func test_empty_and_pre() -> void:
	check(Brief.goal({}) == "还没有开局。", "空档时的目标文案不对")
	check((Brief.lines({}) as Array).is_empty(), "空档时还给出了要务")

	var pre: Dictionary = State.new_run("scholar", State.new_meta(), 20261027)
	var goal := Brief.goal(pre)
	check(goal.contains("备劫第 1 / 3 日"), "备劫阶段的目标没写天数：%s" % goal)
	check(goal.contains("活过 20 日"), "备劫阶段没说要活过多少天：%s" % goal)
	check((Brief.lines(pre) as Array).is_empty(), "备劫阶段不该有劫中要务")
	check(Brief.countdown(pre).contains("尸劫"), "备劫阶段的倒计时不对：%s" % Brief.countdown(pre))


# ---------- 二、太平的一天只说一句 ----------

func test_quiet_day() -> void:
	var run := _calm_day()
	var lines := Brief.lines(run)
	check(lines.size() == 1, "太平的一天说了 %d 条（应该只一句「没有急事」）" % lines.size())
	check(str(lines[0].text).contains("没有急事"), "太平的一天的句子不对：%s" % str(lines[0].text))


# ---------- 三、砸穿的面 ----------

func test_broken_surface() -> void:
	var run := _calm_day()
	run.door.cur = 0
	var lines := Brief.lines(run)
	var joined := _join(lines)
	check(joined.contains(Defense.surface_name("gate")), "门砸穿了却没点名：%s" % joined)
	check(int(lines[0].level) == Brief.ALARM, "砸穿了却不是最高级：%d" % int(lines[0].level))
	check(joined.contains("砸穿"), "没说清楚已经砸穿：%s" % joined)

	# 三面全破：一句里把三面都点出来，而不是刷三条
	var all := _calm_day()
	for sid in Defense.SURFACES:
		Defense.part_of(all, sid).cur = 0
	var text := _join(Brief.lines(all))
	for sid in Defense.SURFACES:
		check(text.contains(Defense.surface_name(sid)), "三面全破时漏了 %s：%s" % [Defense.surface_name(sid), text])


# ---------- 四、今夜的尸潮 ----------

func test_wave_tonight() -> void:
	var run := _wave_day()
	var joined := _join(Brief.lines(run))
	check(joined.contains("今夜有尸潮"), "今夜有尸潮却没说：%s" % joined)

	# 某面只剩两成：要具体点名并给百分比
	var weak := _wave_day()
	weak.wall.cur = int(round(float(weak.wall.max) * 0.2))
	var text := _join(Brief.lines(weak))
	check(text.contains(Defense.surface_name("wall")), "最弱的一面没点名：%s" % text)
	check(text.contains("20%"), "没给出百分比：%s" % text)
	check(text.contains("只剩"), "措辞不对：%s" % text)


# ---------- 五、冷夜没有柴炭 ----------

func test_cold_without_fuel() -> void:
	var run := _cold_day()
	run.home.erase("firewood")
	run.home.erase("charcoal")
	var joined := _join(Brief.lines(run))
	check(joined.contains("没有柴也没有炭"), "冷夜缺燃料没说：%s" % joined)

	# 还有一捆：从"要命"降成"提醒"，并且说清一捆只够烧半夜
	var few := _cold_day()
	few.home = {"firewood": 1}
	few.heated = false
	var lines := Brief.lines(few)
	var hit := false
	for l in lines:
		if str(l.text).contains("只够烧半夜"):
			hit = true
			check(int(l.level) == Brief.NOTE, "只剩一捆时不该是最高级")
	check(hit, "只剩一捆柴时没提醒：%s" % _join(lines))

	# 柴备够了就不该提（本作的天气表里没有"不冷"的日子，所以用"有柴"来验不啰嗦）
	var stocked := _cold_day()
	stocked.home = {"firewood": 5, "rice": 4, "water": 3}
	check(not _join(Brief.lines(stocked)).contains("柴"), "有柴却还提柴：%s" % _join(Brief.lines(stocked)))


# ---------- 六、断粮断水 ----------

func test_no_food_or_water() -> void:
	var run := _calm_day()
	run.home = {}
	var joined := _join(Brief.lines(run))
	check(joined.contains("没有能下锅"), "断粮没说：%s" % joined)
	check(joined.contains("没有存水"), "缺水没说：%s" % joined)

	# 有水缸就不算"没有存水"
	var vat := _calm_day()
	vat.home = {}
	vat.facilities = ["water_vat"]
	check(not _join(Brief.lines(vat)).contains("没有存水"), "有水缸却还说没有存水")


# ---------- 七、条数与顺序 ----------

func test_cap_and_order() -> void:
	var run := _wave_day()
	run.door.cur = 0
	run.window.cur = 0
	run.home = {}
	var lines := Brief.lines(run)
	check(lines.size() <= Brief.MAX_LINES, "超过 %d 条了：%d" % [Brief.MAX_LINES, lines.size()])
	var prev := 99
	for l in lines:
		check(int(l.level) <= prev, "没有按紧急度排序：%s" % str(lines))
		prev = int(l.level)
	check(int(lines[0].level) == Brief.ALARM, "最要命那条没排第一：%s" % str(lines[0]))


# ---------- 八、倒计时与进度 ----------

func test_countdown() -> void:
	var run := _calm_day()
	run.pday = 13
	check(Brief.countdown(run) == "距劫满 7 日", "倒计时不对：%s" % Brief.countdown(run))
	check(Brief.goal(run).contains("还有 7 日"), "目标句里的天数不对：%s" % Brief.goal(run))
	check(absf(Brief.progress(run) - 13.0 / 20.0) < 0.001, "进度不对：%f" % Brief.progress(run))
	run.pday = 20
	check(Brief.countdown(run) == "劫满", "最后一天没说劫满：%s" % Brief.countdown(run))
	check(Brief.progress(run) == 1.0, "最后一天的进度不是 1")
	run.endless = true
	check(Brief.countdown(run) == "守到死", "守到死模式的倒计时不对：%s" % Brief.countdown(run))
	check(Brief.goal(run).contains("没有终点"), "守到死模式的目标句不对：%s" % Brief.goal(run))
	check(Brief.progress(run) == 0.0, "守到死不该有进度")


# ---------- 小工具 ----------

## 一天里没有尸潮、天气不冷、三面完好、粮水充足。
func _calm_day() -> Dictionary:
	var run := _base()
	for day in range(1, State.STORY_DAYS + 1):
		if Defense.wave_for_run(run, day).is_empty() and int(_weather(day).get("cold", 0)) == 0:
			run.pday = day
			return run
	return run


## 一个有尸潮的夜晚。
func _wave_day() -> Dictionary:
	var run := _base()
	for day in range(1, State.STORY_DAYS + 1):
		if not Defense.wave_for_run(run, day).is_empty():
			run.pday = day
			return run
	return run


## 一个会冷的夜晚（燃料由用例自己摆）。
func _cold_day() -> Dictionary:
	var run := _base()
	for day in range(1, State.STORY_DAYS + 1):
		if int(_weather(day).get("cold", 0)) > 0:
			run.pday = day
			return run
	return run


func _weather(day: int) -> Dictionary:
	for w in Data.table("weather"):
		if day >= int(w["from"]) and day <= int(w["to"]):
			return w
	return {}


func _base() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261027)
	Pre.start_disaster(run)
	run.pday = 1
	run.door = {"cur": 100, "max": 100}
	run.window = {"cur": 60, "max": 60}
	run.wall = {"cur": 120, "max": 120}
	run.home = {"rice": 6, "firewood": 5, "charcoal": 3, "water": 4}
	run.facilities = []
	run.heated = false
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
