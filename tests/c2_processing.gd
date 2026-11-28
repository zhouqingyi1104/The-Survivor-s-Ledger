extends Node

const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 3117)
	Home.ensure_layout(run)
	run.t = 200
	Inv.add(run.home, "cabbage", 3)
	Inv.add(run.home, "salt", 1)
	Inv.add(run.home, "rat", 2)
	Inv.add(run.home, "firewood", 1)
	var jar := Home.add(run, "pickle_jar", -4.0, 3.0, 0)
	var rack := Home.add(run, "smoke_rack", 4.0, -1.0, 0)
	var jar_uid := int(jar.uid)
	var rack_uid := int(rack.uid)
	check(Home.pickle(run, jar_uid, "cabbage", 3) == "", "pickle job could not start")
	check(Home.smoke(run, rack_uid, "rat", 2) == "", "smoke job could not start")
	var jar_job: Dictionary = jar.job.duplicate(true)
	var rack_job: Dictionary = rack.job.duplicate(true)
	var inventory := JSON.stringify(run.home)
	check(Home.move(run, jar_uid, -4.5, 1.0, 90) == "", "jar move failed")
	check(Home.move(run, rack_uid, 4.5, 4.5, 90) == "", "rack move failed")
	check(int(Home.find(run, jar_uid).uid) == jar_uid and Home.find(run, jar_uid).job == jar_job, "jar identity or job changed")
	check(int(Home.find(run, rack_uid).uid) == rack_uid and Home.find(run, rack_uid).job == rack_job, "rack identity or job changed")
	check(JSON.stringify(run.home) == inventory, "move changed inventory")
	check(int(jar.job.done_t) == 200 + 2 * Home.DAY and int(rack.job.done_t) == 200 + Home.DAY, "completion time changed")
	var path := "user://c2-processing-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(path, {"run": run, "snapshots": {}})
	check(bool(saved.ok), "save write failed")
	var loaded := SaveFile.read(path)
	check(not loaded.data.is_empty(), "save read failed")
	if loaded.data.is_empty():
		SaveFile.forget(path)
		_finish()
		return
	run = loaded.data.run
	jar = Home.find(run, jar_uid)
	rack = Home.find(run, rack_uid)
	check(not jar.is_empty() and int(jar.uid) == jar_uid and int(jar.job.done_t) == int(jar_job.done_t) and int(jar.job["in"].cabbage) == 3 and int(jar.job.out.pickles) == 3, "jar job did not survive save")
	check(not rack.is_empty() and int(rack.uid) == rack_uid and int(rack.job.done_t) == int(rack_job.done_t) and int(rack.job["in"].rat) == 2 and int(rack.job.out.smoked_rat) == 2, "rack job did not survive save")
	check(int(jar.rot) == 90 and int(rack.rot) == 90 and absf(float(jar.x) + 4.5) < 0.01 and absf(float(rack.x) - 4.5) < 0.01, "position did not survive save")
	var pickles_before := Inv.count(run.home, "pickles")
	var smoked_before := Inv.count(run.home, "smoked_rat")
	run.t = int(rack_job.done_t) - 1
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before and Inv.count(run.home, "smoked_rat") == smoked_before, "early processing payout")
	run.t = int(rack_job.done_t)
	Home.dawn(run)
	check(Inv.count(run.home, "smoked_rat") == smoked_before + 2 and Inv.count(run.home, "pickles") == pickles_before, "smoke completion wrong")
	check(Home.find(run, rack_uid).job.is_empty() and not Home.find(run, jar_uid).job.is_empty(), "completion cleared wrong jobs")
	Home.dawn(run)
	check(Inv.count(run.home, "smoked_rat") == smoked_before + 2, "duplicate smoked payout")
	run.t = int(jar_job.done_t)
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before + 3, "pickle completion wrong")
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before + 3 and Inv.count(run.home, "smoked_rat") == smoked_before + 2, "duplicate processing payout")
	check(Home.find(run, jar_uid).job.is_empty(), "completed jar job not cleared")
	SaveFile.forget(path)
	test_drying()
	_finish()

func test_drying() -> void:
	var run := State.new_run("scholar", State.new_meta(), 3118)
	check(Post.act_drying(run, "start", "grain") != "", "备劫阶段不能提前晒粮")
	Pre.start_disaster(run)
	run.t = 60
	run.home = {"millet": 1, "water": 1, "radish": 3, "salt": 1}
	var before: Dictionary = run.duplicate(true)
	check(Post.Drying.summary(run) == "空匾" and Post.act_drying(run, "start", "grain") != "" and run == before, "旧档空匾且缺燃料不扣粮")
	run.home.charcoal = 1
	check(Post.act_drying(run, "start", "grain") == "" and not run.home.has("charcoal") and not run.home.has("water") and not run.home.has("millet"), "铺匾一次扣清料，没柴时用炭")
	var first := int(run.drying_batch.ready)
	check(first == 60 + Post.DAY and State.attr(run, "energy") == float(before.attrs.energy) - 4, "铺匾时间、精力")
	before = run.duplicate(true)
	check(Post.act_drying(run, "start", "radish") != "" and Post.act_drying(run, "take") != "" and Post.act_drying(run, "turn") != "" and run == before, "满匾与提前收/翻均无副作用")
	var path := "user://drying-%d.json" % OS.get_process_id()
	check(SaveFile.write(path, {"run": run}).ok, "晒匾写档")
	run = SaveFile.read(path).data.run
	SaveFile.forget(path)
	check(int(run.drying_batch.ready) == first and not run.drying_batch.turned, "读档保留成熟时间")
	run.pday = 2
	run.t = first - 1
	check(Post.advance(run, 1) == "" and run.t == first and str(run.log.back()).contains("去收匾"), "正式时钟越过成熟刻，在日志提醒")
	before = run.duplicate(true)
	run.t += 145
	check(not run.home.has("millet_cake") and Post.act_drying(run, "turn") == "" and int(run.drying_batch.ready) == first + 145 + Post.DAY, "延迟领取不自动入库，翻晒从实际操作再等一天")
	check(is_equal_approx(float(run.attrs.energy), float(before.attrs.energy) - 2.0), "翻晒耗两点精力")
	run.t = int(run.drying_batch.ready)
	check(Post.act_drying(run, "turn") != "" and Post.act_drying(run, "take") == "" and Inv.count(run.home, "millet_cake") == 5, "翻晒只可一次，收全得五张")
	check(Post.act_drying(run, "take") != "" and Inv.count(run.home, "millet_cake") == 5 and not run.has("drying_batch"), "清空后不可重复领取")
	var now := int(run.t)
	check(Post.act_drying(run, "start", "radish") == "" and int(run.drying_batch.ready) == now + Post.DAY * 2, "腌萝卜另花两日，不占柴")
	run.t += Post.DAY * 6
	check(Post.act_drying(run, "take") == "" and Inv.count(run.home, "pickles") == 2, "多留几日也只给初晒量")
	run.attrs.food = 25
	run.attrs.mood = 20
	check(Post.use_item(run, "millet_cake") == "" and run.attrs.food == 53 and run.attrs.mood == 20, "饼沿用库存食用，偏饱腹")
	check(Post.use_item(run, "pickles") == "" and run.attrs.food == 61 and run.attrs.mood == 23, "咸菜沿用库存食用，兼顾心神")

func _finish() -> void:
	print("[C2_PROCESSING] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
