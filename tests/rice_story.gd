extends SceneTree
## 燕尾担：备劫可以错过，奖励和账簿回响都按本世纪录。

const Data = preload("res://scripts/core/data.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Post = preload("res://scripts/core/post.gd")
const Pre = preload("res://scripts/core/pre.gd")
const State = preload("res://scripts/core/state.gd")
const Story = preload("res://scripts/core/rice_story.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_discovery()
	test_lesson("carry", "escort")
	test_lesson("marks", "scholar")
	test_legacy_and_time()
	print("[rice_story] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func reload_run(run: Dictionary) -> Dictionary:
	var data: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify({"run": run, "snapshots": {}})))
	return Migrate.save(data).run


func check_refused(run: Dictionary, action: Callable, message: String) -> void:
	var before := run.duplicate(true)
	check(action.call() != "" and run == before, message)


func test_discovery() -> void:
	var run := State.new_run("scholar", State.new_meta(), 208)
	check(Pre.travel(run, "rice_shop") == "" and Pre.buy(run, "rice") == "", "普通购买路线应可到达米行")
	check(not Story.can_inspect(run), "仅采购不能看到藏在粮袋后的短担")
	check_refused(run, Story.inspect.bind(run), "卸粮前不能捡到纸条")
	check(Pre.do_prep_work(run, "rice_shop") == "", "应可卸粮")
	var hour := int(run.hour)
	var cart: Dictionary = run.cart.duplicate()
	check(Story.can_inspect(run) and Story.inspect(run) == "", "卸完粮当场能读线索")
	check(run.hour == hour and run.cart == cart and Story.stage(run) == "paper", "看纸条须免费，不占车位")
	check(str(run.log.back()).contains("书肆"), "遗漏目的地提示")
	check_refused(run, Story.inspect.bind(run), "不能重复领纸条")
	check_refused(run, Story.learn.bind(run, "carry"), "在米行不能直接学到本事")
	var next_life := State.new_run("scholar", State.new_meta(), 208)
	check(Story.stage(next_life) == "" and not Story.heard_echo(next_life), "重开一世该独立记录")


func test_lesson(choice: String, role: String) -> void:
	var run := State.new_run(role, State.new_meta(), 304)
	check(Pre.travel(run, "rice_shop") == "" and Pre.do_prep_work(run, "rice_shop") == "" and Story.inspect(run) == "", "正常出门和卸粮应能查出纸条")
	check(Pre.travel(run, "bookshop") == "", "第一日还能赶到书肆")
	run = reload_run(run)
	run.silver = 0
	run.cart = {"flatbread": Pre.capacity(run)}
	var cart: Dictionary = run.cart.duplicate()
	var home: Dictionary = run.home.duplicate()
	var cap := State.attr_max(run, "hp")
	if choice == "carry":
		State.add_attr(run, "hp", -13.5)
	var hp := float(run.attrs.hp)
	var exposure := Explore.exposure_range(run, "rice_ruin")
	var hour := int(run.hour)
	check(Story.stage(run) == "paper" and Story.lesson_issue(run) == "", "读档后无银、满车也能在书肆学艺")
	check_refused(run, Story.learn.bind(run, "both"), "未知课目不能消耗这次机会")
	check(Story.learn(run, choice) == "" and Story.stage(run) == choice, "应学会所选课目")
	check(run.hour == hour + 1 and run.silver == 0 and run.cart == cart and run.home == home, "一堂课只收一个时辰")
	if choice == "carry":
		check(State.attr_max(run, "hp") == cap + 5 and is_equal_approx(float(run.attrs.hp), hp + 5.0), "受伤时也只加5，保留身份原上限及伤势")
		State.add_attr(run, "hp", 300)
		check(State.attr(run, "hp") == cap + 5 and State.prof_level(run, "search") == 0, "恢复可达到新上限，未选课目不能获益")
	else:
		check(run.prof.search == 10 and State.prof_level(run, "search") == 1, "认记号应点亮搜寻1级")
		check(Explore.exposure_range(run, "rice_ruin").y < exposure.y and State.attr_max(run, "hp") == cap, "搜寻等级应切实降低普通翻找外泄，气血不受影响")
	run = reload_run(run)
	for lesson in ["carry", "marks"]:
		check_refused(run, Story.learn.bind(run, lesson), "续档后不能重学或改修 " + lesson)
	var expected_echo := Story.echo_text(run)
	check(not expected_echo.is_empty() and not Story.can_reveal(run), "劫前不能提前翻到封底")
	for day in State.PRE_DAYS:
		Pre.end_day(run)
	check(run.phase == "post" and Story.stage(run) == choice, "跨灾后当日须保留课目")
	check(State.attr_max(run, "hp") == cap + (5 if choice == "carry" else 0) and run.prof.search == (10 if choice == "marks" else 0), "过夜或读档丢失了学艺收益")
	check(Post.act_explore(run, "rice_ruin") == "", "应能从灾后宅院前往米行")
	check_refused(run, Story.reveal.bind(run), "机关资料尚未初始化时，不能擅开或补写")
	var legacy_field := run.duplicate(true)
	legacy_field.explore.expedition = null
	check_refused(legacy_field, Story.reveal.bind(legacy_field), "旧现场机关资料缺失时不能视为已读账簿")
	check(not Post.expedition_inspect(run, 0).has("blocked") and Story.can_reveal(run), "亲手查完残缺账簿应发现背页")
	for key in ["caught", "curfew_due"]:
		var interrupted := run.duplicate(true)
		interrupted.explore[key] = true
		check_refused(interrupted, Story.reveal.bind(interrupted), "受阻时不得翻封底 " + key)
	var elsewhere := run.duplicate(true)
	elsewhere.explore.point = "school"
	check_refused(elsewhere, Story.reveal.bind(elsewhere), "不能在别处的机关翻到账簿")
	var interrupted := run.duplicate(true)
	interrupted.pending_event = "未处理事件"
	check_refused(interrupted, Story.reveal.bind(interrupted), "事件处理期间不能直接翻封底")
	var other := run.duplicate(true)
	other.flags[Story.STAGE_KEY] = "paper"
	check_refused(other, Story.reveal.bind(other), "只收下纸条也不能认出背页")
	other.flags[Story.STAGE_KEY] = "marks" if choice == "carry" else "carry"
	check(Story.echo_text(other) != expected_echo, "两个课目应读到不同的背页")
	var field: Dictionary = run.explore.duplicate(true)
	var time := int(run.t)
	check(Story.reveal(run) == "" and Story.heard_echo(run), "应当读到本支回响")
	check(run.t == time and run.explore == field and str(run.log.back()).contains(expected_echo), "可选回响不额外耗时或动货物、机关，应写入日志")
	check(not Story.can_reveal(run) and not run.explore.expedition.unlocked, "封底不应代解机关")
	run = reload_run(run)
	check(Story.heard_echo(run) and Story.echo_text(run) == expected_echo, "读档后回响须可复读")
	check_refused(run, Story.reveal.bind(run), "不可重复结算封底")


func test_legacy_and_time() -> void:
	var run := State.new_run("escort", State.new_meta(), 311)
	run.loc = "rice_shop"
	run.erase("flags")
	check_refused(run, Story.inspect.bind(run), "缺整个标记的旧档应从卸粮做起")
	run.flags = {"prep_work_rice_shop": true}
	run = reload_run(run)
	run.hour = State.CURFEW_HOUR
	check(Story.inspect(run) == "", "只在旧版卸过粮，宵禁正点在米行仍可低头翻短担")
	Pre.end_day(run)
	check_refused(run, Story.learn.bind(run, "carry"), "隔天在家不能远程学艺")
	check(Pre.travel(run, "bookshop") == "", "应能隔天去书肆")
	run.hour = State.CURFEW_HOUR
	check_refused(run, Story.learn.bind(run, "carry"), "不足一个时辰不能开课")
	run.hour -= 1
	check(Story.learn(run, "carry") == "" and run.hour == State.CURFEW_HOUR, "最后一个时辰够学艺")
	var late := State.new_run("scholar", State.new_meta(), 315)
	late.flags = {"prep_work_rice_shop": true}
	late.loc = "rice_shop"
	late.day = 3
	late.hour = int(Pre.shop("rice_shop").close.hour)
	check(Pre.status(late, "rice_shop") == "关门" and Story.inspect(late) == "", "第三日米行刚上门板仍够得到门外的短担")
	for bad in ["unknown_stage", null, ["paper"]]:
		late.flags[Story.STAGE_KEY] = bad
		check_refused(late, Story.inspect.bind(late), "陌生的进度不能被抹掉重领")
		late.loc = "bookshop"
		check_refused(late, Story.learn.bind(late, "marks"), "不可凭损坏的纸条记录领经验")
		late.loc = "rice_shop"
