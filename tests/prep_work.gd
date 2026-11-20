extends SceneTree
## 备劫非采购行动：实际结算、三日限次与路程边界。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Migrate = preload("res://scripts/core/migrate.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_work_and_supplies()
	test_hours_and_travel()
	test_legacy_flags()
	print("[prep_work] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func check_blocked(run: Dictionary, place: String, reason: String) -> void:
	var before := run.duplicate(true)
	check(Pre.do_prep_work(run, place).contains(reason), "应当拦下：%s / %s" % [place, reason])
	check(run == before, "拒绝行动时改动了局面：" + place)


func test_work_and_supplies() -> void:
	var run := State.new_run("scholar", State.new_meta(), 1201)
	run.silver = 0
	run.cart = {"flatbread": Pre.capacity(run)}
	var starting_home: Dictionary = run.home.duplicate()
	var starting_tally: Dictionary = run.tally.duplicate(true)
	check(Pre.cart_weight(run) == Pre.capacity(run), "夹具必须满载")
	check(not Pre.prep_work_done(run, "home") and not Pre.prep_work_done(run, "rice_shop"), "旧局未记杂事时应当都能做")
	check_blocked(run, "rice_shop", "米行")
	check_blocked(run, "market", "没有")
	check(Pre.travel(run, "rice_shop") == "", "第一日走不到米行")
	var hour := int(run.hour)
	var cart: Dictionary = run.cart.duplicate()
	check(Pre.do_prep_work(run, "rice_shop") == "", "身无分文、车满仍能帮卸粮")
	check(run.hour == hour + 1 and run.loc == "rice_shop" and run.silver == 0, "卸粮应只占一个时辰")
	check(Inv.count(run.home, "flatbread") == Inv.count(starting_home, "flatbread") + 1 and run.cart == cart, "一张炊饼应送回家，不能挤上车")
	check(str(run.log.back()).contains("炊饼"), "实际所得须记入日志")
	check(run.tally == starting_tally, "务工误算作买货或回家")
	check_blocked(run, "rice_shop", "做过")
	Pre.end_day(run)
	check(run.day == 2 and run.loc == "home" and run.cart.is_empty(), "歇息未正常卸货进第二日")
	# 使用续档的 JSON 数值归一化和迁移入口，确认标记不会重置。
	run = Migrate.save(Data.normalize(JSON.parse_string(JSON.stringify({"run": run, "snapshots": {}})))).run
	check_blocked(run, "rice_shop", "做过")
	check(Pre.prep_work_block(run, "home") == "", "两桩活应当各有一次机会")
	hour = int(run.hour)
	var wood := Inv.count(run.home, "wood")
	check(Pre.do_prep_work(run, "home") == "", "零银也应能劈院中枯枝")
	check(run.hour == hour + 1 and run.silver == 0 and Inv.count(run.home, "wood") == wood, "劈柴多扣了时辰、银钱或木料")
	var fuel := Inv.count(starting_home, "firewood") + 2
	check(Inv.count(run.home, "firewood") == fuel and str(run.log.back()).contains("两捆柴"), "两捆柴应入库并记账")
	Pre.end_day(run)
	check_blocked(run, "home", "做过")
	var bread := Inv.count(starting_home, "flatbread") + Inv.count(cart, "flatbread") + 1
	Pre.end_day(run)
	check(run.phase == "post" and Inv.count(run.home, "flatbread") == bread and Inv.count(run.home, "firewood") == fuel, "进灾后宅院时杂事所得丢失或重复")
	check_blocked(run, "home", "备劫")


func test_hours_and_travel() -> void:
	var run := State.new_run("scholar", State.new_meta(), 1202)
	run.day = 3
	var closing := int(Pre.shop("rice_shop").close.hour)
	run.hour = closing - 1
	var before := run.duplicate(true)
	check(Pre.prep_work_trip_block(run, "rice_shop").contains("关门"), "预估到米行时刚好打烊，不该提示可做")
	check(run == before, "预估路程改变了时辰、地点或随机数")
	run.hour = closing - 2
	check(Pre.prep_work_trip_block(run, "rice_shop") == "", "到店后还剩一时辰，应可前往")
	run.loc = "rice_shop"
	run.hour = closing
	check_blocked(run, "rice_shop", "关门")
	run.hour -= 1
	check(Pre.do_prep_work(run, "rice_shop") == "" and run.hour == closing, "打烊前最后一时辰可以做完")
	run.hour = State.CURFEW_HOUR - 1
	check(Pre.prep_work_trip_block(run, "home").contains("宵禁"), "回家时已宵禁，不该提示还可劈柴")
	run.loc = "home"
	run.hour = State.CURFEW_HOUR
	check_blocked(run, "home", "宵禁")
	run.hour -= 1
	check(Pre.do_prep_work(run, "home") == "" and run.hour == State.CURFEW_HOUR, "最后一个时辰应能恰好完工")


func test_legacy_flags() -> void:
	var run := State.new_run("scholar", State.new_meta(), 1203)
	run.erase("flags")
	var before := run.duplicate(true)
	check(not Pre.prep_work_done(run, "home") and Pre.prep_work_block(run, "home") == "", "缺整个旧标记字典时应看到未完成的家务")
	check(Pre.prep_work_trip_block(run, "rice_shop") == "" and run == before, "查看旧档的杂事或路程不应补写标记")
	var hour := int(run.hour)
	var fuel := Inv.count(run.home, "firewood")
	check(Pre.do_prep_work(run, "home") == "" and Pre.prep_work_done(run, "home"), "办完杂事后应创建旧档缺少的字典")
	check(run.hour == hour + 1 and Inv.count(run.home, "firewood") == fuel + 2, "补写旧标记时应恰好结算一次")
	check_blocked(run, "home", "做过")
	for invalid in [null, 4, ["旧资料"]]:
		run.flags = invalid
		before = run.duplicate(true)
		check(not Pre.prep_work_done(run, "home") and Pre.prep_work_trip_block(run, "rice_shop").contains("记录有误") and before == run, "读取损坏的杂事记录不能改写存档")
		check_blocked(run, "home", "记录有误")
