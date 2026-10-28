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
const Post = preload("res://scripts/core/post.gd")
const Crisis = preload("res://scripts/core/crisis.gd")

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

	# 水缸只让打水多一瓢，不凭空补水。
	var vat := _calm_day()
	vat.home = {}
	vat.facilities = ["water_vat"]
	check(_join(Brief.lines(vat)).contains("没有存水"), "水缸空了仍应提醒没有存水")
	check(_join(Brief.lines(vat)).contains("井边打水"), "井可用时应提示去井边打水")
	vat.well_used = true
	check(_join(Brief.lines(vat)).contains("今天已经打过水"), "当日已经打水时不该提示仍可打水")
	vat.well_used = false
	vat.crisis = {"active": {"kind": "well_freeze", "stage": "impact"}}
	check(Crisis.well_block(vat) != "", "夹具必须真的封井")
	check(_join(Brief.lines(vat)).contains("井口冻裂"), "封井时应说明无法打水")
	vat.home.water = 1
	check(not _join(Brief.lines(vat)).contains("没有存水"), "仓中有水不该说没有存水")
	var pristine := _calm_day()
	pristine.home.erase("water")
	var before: Dictionary = pristine.duplicate(true)
	Brief.lines(pristine)
	check(pristine == before, "查看缺水提示不应修改局面")

	# 核对与 20:00 实际燃料优先顺序一致。
	var oil := _cold_day()
	oil.home = {"rice": 1, "water": 1, "diesel": 1}
	oil.facilities = ["generator"]
	check(not _join(Brief.lines(oil)).contains("没有柴也没有炭"), "有发电机与柴油时不能暗示无取暖材料")
	Post._heat(oil)
	check(oil.heated and Inv.count(oil.home, "diesel") == 0, "发电机应消耗柴油并取暖")
	oil.t = (int(oil.pday) - 1) * Post.DAY + Post.HEAT_AT
	check(not _join(Brief.lines(oil)).contains("没有生火"), "已经启动发电机不能说未生火")
	var empty_oil := _cold_day()
	empty_oil.home = {"rice": 1, "water": 1}
	empty_oil.facilities = ["generator"]
	check(_join(Brief.lines(empty_oil)).contains("没有柴也没有炭"), "发电机无油且无柴炭应提醒")
	var coal := _cold_day()
	coal.home = {"rice": 1, "water": 1, "charcoal": 1}
	check(not _join(Brief.lines(coal)).contains("只够烧半夜"), "一块炭足够整夜，不能说一捆柴")
	Post._heat(coal)
	check(coal.heated and not coal.heat_weak, "实际烧炭应是整夜的强火")
	var one_wood := _cold_day()
	one_wood.home = {"rice": 1, "water": 1, "firewood": 1}
	check(_join(Brief.lines(one_wood)).contains("只够烧半夜"), "只有一捆柴应提示弱火")
	Post._heat(one_wood)
	check(one_wood.heated and one_wood.heat_weak, "实际烧一捆柴应是弱火")
	one_wood.t = (int(one_wood.pday) - 1) * Post.DAY + Post.HEAT_AT
	check(_join(Brief.lines(one_wood)).contains("火势较弱"), "弱火已经烧起时应报告现状")
	var missed := _cold_day()
	missed.t = (int(missed.pday) - 1) * Post.DAY + Post.HEAT_AT
	check(_join(Brief.lines(missed)).contains("取暖时刻已过"), "错过20:00后不能暗示库存会自动用于今晚取暖")


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
	run.t = 19 * Post.DAY
	check(Brief.countdown(run) == "守过第 20 夜", "第20日清晨不能提前说劫满：%s" % Brief.countdown(run))
	check(Brief.goal(run).contains("到天亮才算劫满"), "第20日目标应说明还要守夜")
	check(Brief.progress(run) < 1.0, "第20日尚未结局，进度不能满")
	run.t = 20 * Post.DAY
	run.dawn_due = true
	check(Brief.countdown(run) == "待天亮结算", "第二十夜结束尚须翻阅天亮报告")
	check(Brief.goal(run).contains("翻阅天亮结算"), "应说明天亮结算")
	Post.ack_dawn(run)
	check(run.phase == "ending", "翻阅第二十夜后的天亮报告才进入结局")
	check(Brief.countdown(run) == "劫满", "实际劫满应显示劫满")
	check(Brief.progress(run) == 1.0, "实际劫满后进度应为1")
	var died := _base()
	died.pday = 20
	died.phase = "dead"
	check(Brief.countdown(died) == "这一世结束" and Brief.progress(died) < 1.0, "第20日身死不能显示劫满或满进度")
	var escape := _base()
	escape.pday = 18
	escape.phase = "ending"
	escape.mainline = {"ending": {"kind": "escape"}}
	check(Brief.goal(escape).contains("撤离") and Brief.countdown(escape) == "已撤离", "提前撤离不能说守满20夜")
	run.phase = "post"
	run.dawn_due = false
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
			run.t = (day - 1) * Post.DAY
			return run
	return run


## 一个有尸潮的夜晚。
func _wave_day() -> Dictionary:
	var run := _base()
	for day in range(1, State.STORY_DAYS + 1):
		if not Defense.wave_for_run(run, day).is_empty():
			run.pday = day
			run.t = (day - 1) * Post.DAY
			return run
	return run


## 一个会冷的夜晚（燃料由用例自己摆）。
func _cold_day() -> Dictionary:
	var run := _base()
	for day in range(1, State.STORY_DAYS + 1):
		if int(_weather(day).get("cold", 0)) > 0:
			run.pday = day
			run.t = (day - 1) * Post.DAY
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
