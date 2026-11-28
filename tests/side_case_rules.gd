extends SceneTree

const Cases = preload("res://scripts/core/side_cases.gd")
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Pack = preload("res://scripts/core/save_pack.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Chronicle = preload("res://scripts/core/chronicle_story.gd")

var checks := 0
var failures := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)


func sample(day: int, letter: String) -> Dictionary:
	var run := State.new_run("scholar", State.new_meta(), 5000, "normal", [], [], [], true)
	Pre.start_disaster(run)
	run.hundred_days.choices["blank_name"] = letter
	run.pday = day
	run.t = (day - 1) * Post.DAY + 240
	return run


func packed(run: Dictionary) -> Dictionary:
	var parsed := Pack.parse(Pack.to_text(Pack.pack({"run": run, "snapshots": {}}, "侧卷", "测试")))
	check(parsed.ok, str(parsed.note))
	return parsed.data.run if parsed.ok else {}


func _initialize() -> void:
	var old := sample(23, "write")
	old.version = 22
	var imported := packed(old)
	check(imported.version == 23 and not imported.hundred_days.has("side_cases"), "v22百日旧卷无需新开即可接案")
	check(Cases.view(imported, "borrowed_address").route.site == "school", "旧信选择让县学可查")
	var early := sample(22, "mark")
	check(Cases.view(early, "borrowed_address").is_empty(), "提前泄露来访")
	var short_run := imported.duplicate(true)
	short_run.erase("hundred_days")
	check(Cases.list_cases(short_run).is_empty() and Cases.accept(short_run, "borrowed_address") != "", "短篇不应开启百日支线")
	check(Explore.point_block(short_run, "school") != "", "短篇沦陷地点未封闭")
	work_path(imported, "school", "许墨生", "pocket")
	work_path(sample(23, "mark"), "city_god", "石榴", "pair")
	interrupted_search()
	inspect_raft_measure()
	damaged_progress()
	public_shares("raft_measure", "mark_tare", "witness", "millet")
	public_shares("mixed_seed", "keep_seed", "lift", "radish")
	public_shares("rain_spout", "catch", "bed", "water")
	print("[side_case_rules] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func work_path(run: Dictionary, site: String, person: String, choice: String) -> void:
	const ID := "borrowed_address"
	var page := Cases.view(run, ID)
	check(page.stage == "offered" and page.person == person, "招呼你的人应随旧选择变化")
	check(Explore.point_block(run, site) != "", "原入口在荒废后保持封闭")
	check(Cases.accept(run, ID) == "" and Cases.accept(run, ID) != "", "只应约下一个街坊")
	check(Cases.view(run, ID).route.site == site and Explore.investigation_only(run, site), "旧信锁定独立的现场")
	var start := int(run.t)
	check(Post.act_explore(run, site) == "" and int(run.t) == start + 60, "应实际赶路一小时")
	check(run.explore.only_investigate and run.explore.spots.size() == 1, "外围不能刷新普通物资")
	check(run.explore.spots[0].side_case == ID and run.explore.spots[0].person == person, "人物/物证位点不一致")
	check(not Post.site_journey_action(run, "s0", "quick").get("blocked", "").is_empty(), "从专程调查不能采普通物资")
	check(not Post.expedition_inspect(run, 0).get("blocked", "").is_empty(), "从外围不能顺手打开遗迹机关")
	var found := Post.search(run, 0)
	check(found.get("started", false) and run.busy.kind == "case_search" and not run.explore.has("case_cargo"), "调查尚未结束不得获得证据")
	check(Cases.abandon(run, ID) != "" and Post.finish_explore(run).is_empty(), "外出工作不能用撤案来取消路程")
	var mid := packed(run)
	Post.advance(mid, int(page.route.minutes) - 1)
	check(not mid.explore.has("case_cargo") and Cases.settle(mid, ID, choice) != "", "带回前不能收件")
	Post.advance(mid, 1)
	check(mid.explore.get("case_cargo") == ID and mid.explore.spots[0].done, "最后一分钟才找到证物")
	check(Post.search(mid, 0).is_empty(), "重复搜同一证物")
	var captured := mid.duplicate(true)
	Explore._caught(captured, Data.table("map_points")[site])
	Post.finish_explore(captured)
	check(Cases.view(captured, ID).stage == "field" and not captured.explore.has("case_cargo"), "被追上后凭空到货")
	# 20:40 携证回程，遇第26日的布防钟停下，真实走完剩余四十分钟才算回家。
	mid.pday = 26
	mid.t = 25 * 1440 + Post.CURFEW_AT - 20
	Post.finish_explore(mid)
	check(mid.plan_due and mid.busy.get("kind") == "travel" and Cases.view(mid, ID).stage == "field" and mid.busy.data.case_cargo == ID, "返程路上被提前结算")
	mid = packed(mid)
	var policy: String = Data.table("waves").policies.keys()[0]
	check(Post.choose_policy(mid, policy) == "", "正常处理布防仍可续走返程")
	Post.advance(mid, int(mid.busy.end) - int(mid.t))
	check(Cases.view(mid, ID).stage == "returned", "60 分钟返程后证物未归档")
	check(int(mid.points[site].looted_until) == 0, "调查专程不应制造搜空期")
	mid.pday = 27
	mid.t = 26 * 1440 + 360
	var supply: Dictionary = mid.home.duplicate()
	check(Cases.settle(mid, ID, choice) == "", "有证物且物资足时应可开工")
	check(Cases.completed_choice(mid, ID) == "" and mid.home == supply, "免费方案完工前不奖物")
	var option: Dictionary = Cases._option(page, choice)
	check(Cases.settle(mid, ID, choice) != "" and Cases.abandon(mid, ID) != "", "合作进行中不得重复扣费或撤案")
	mid = packed(mid)
	Post.advance(mid, int(option.minutes))
	Inv.add_all(supply, option.gain)
	check(mid.home == supply and Cases.completed_choice(mid, ID) == choice, "工时走满才完成入库")
	check(Cases.view(mid, ID).epilogue == option.epilogue and Cases.active(mid).is_empty(), "收尾没有对应此世解法")
	check(Cases.settle(mid, ID, choice) != "" and Cases.accept(mid, ID) != "" and mid.home == supply, "完工不得反复领奖")
	mid.pday = 54
	mid.t = 53 * 1440 + 360
	check(Cases.view(mid, "bowl_post").is_empty() == (choice != "pocket"), "后半程隐线应由首案的实际结案决定")
	mid.phase = "ending"
	check(Cases.list_cases(mid).size() == 1 and Cases.view(mid, ID).stage == "done", "结局只能翻看已办成的支线")


func interrupted_search() -> void:
	var run := sample(23, "mark")
	Cases.accept(run, "borrowed_address")
	Post.act_explore(run, "city_god")
	run.explore.exposure = 99
	var res := Post.search(run, 0)
	check(res.get("caught", false) and run.busy.is_empty() and not run.explore.has("case_cargo"), "满外泄立即失去证物与调查进度")
	var second := sample(23, "mark")
	Cases.accept(second, "borrowed_address")
	Post.act_explore(second, "city_god")
	second.t = (22 * 1440) + Post.CURFEW_AT - 10
	Post.search(second, 0)
	check(Post.advance(second, 20) == "curfew" and second.busy.is_empty() and not second.explore.has("case_cargo"), "调查中遇宵禁应中止")
	Post.finish_explore(second)
	check(Cases.view(second, "borrowed_address").stage == "field", "中断后仍可重查")


func inspect_raft_measure() -> void:
	const ID := "raft_measure"
	var run := sample(38, "write")
	var page := Cases.view(run, ID)
	var survey: Dictionary = page.route.get("inspection", {})
	check(not survey.is_empty(), "码头运筐案应有实物细查")
	if survey.is_empty(): return
	check(Cases.accept(run, ID) == "", "能约人去核筐")
	var site := str(page.route.site)
	check(Post.act_explore(run, site) == "", "能走到筐梁现场")
	var idx := -1
	for i in run.explore.spots.size():
		if run.explore.spots[i].get("side_case") == ID: idx = i
	check(idx >= 0, "现场有可查的木筐")
	if idx < 0: return
	var alternate := run.duplicate(true)
	var wrong := ""
	for answer in survey.answers:
		if answer.id != survey.correct:
			wrong = str(answer.id)
			break
	var before := run.duplicate(true)
	var miss := Post.search(run, idx, "inspect:" + wrong)
	check(wrong != "" and miss.get("blocked", "") != "" and run == before, "读错实物不能耗费工时或凭空取得发现")
	var res := Post.search(run, idx, "inspect:" + str(survey.correct))
	check(res.get("started", false) and int(run.busy.end) - int(run.t) == int(page.route.minutes) + int(survey.extra_minutes), "多做一步必须用足额外时间")
	check(int(run.explore.exposure) == int(page.route.risk) + int(survey.extra_risk), "细查需要承受额外外泄")
	Post.advance(run, int(run.busy.end) - int(run.t))
	check(run.explore.get("case_detail", false) and not Cases.view(run, ID).detail, "实物细节没到家不得算作可用证据")
	var caught := packed(run)
	Explore._caught(caught, Data.table("map_points")[site])
	Post.finish_explore(caught)
	check(not Cases.view(caught, ID).detail and Cases.view(caught, ID).stage == "field", "逃离时详细取证也应丢失")
	Post.finish_explore(run)
	run = packed(run)
	var detailed := Cases.view(run, ID)
	check(detailed.detail and detailed.finding == survey.finding, "正确判读完好带回后可以查看详细线索")
	Post.search(alternate, idx)
	Post.advance(alternate, int(page.route.minutes))
	Post.finish_explore(alternate)
	var normal := Cases.view(alternate, ID)
	check(not normal.detail and normal.options.size() < detailed.options.size(), "普通勘查仍能结案但不能动用细查解法")
	var optional: Dictionary
	for option in detailed.options:
		if option.get("when", {}).get("detail", false): optional = option
	check(not optional.is_empty() and Cases.settle_block(alternate, ID, optional.id) != "", "旧页面不能绕过实物条件")
	run.home.erase("nails")
	var before_stock := run.duplicate(true)
	check(Cases.settle(run, ID, "mark_tare") != "" and run == before_stock, "材料不齐时不能开工或改账")
	Inv.add(run.home, "nails", 1)
	check(Cases.settle(run, ID, "mark_tare") == "" and Inv.count(run.home, "nails") == 0, "开工当天交一次钉")
	check(Cases.completed_choice(run, ID) == "" and Cases.settle(run, ID, "mark_tare") != "", "未完工不能解锁公灶或重复接活")
	run = packed(run)
	Post.advance(run, int(run.busy.end) - int(run.t))
	check(Cases.completed_choice(run, ID) == "mark_tare", "完工后才有长期约定依据")


func rejects(run: Dictionary, reason: String) -> void:
	var envelope := Pack.pack({"run": run, "snapshots": {}}, "旧卷", "测试")
	var result := Pack.parse(Pack.to_text(envelope))
	check(not result.ok and not str(result.note).is_empty(), "存档导入必须拒绝：" + reason)


func damaged_progress() -> void:
	var run := sample(23, "write")
	Cases.accept(run, "borrowed_address")
	for index in [-1, 999, 0.5, "0"]:
		var invalid := run.duplicate(true)
		invalid.version = 22
		invalid.hundred_days.side_cases.records.borrowed_address.route = index
		rejects(invalid, "无效路线编号")
	var forged := run.duplicate(true)
	forged.hundred_days.side_cases.records.borrowed_address.merge({"evidence": true, "detail": true})
	rejects(forged, "无附加物证的案件被写入细查记录")
	Post.act_explore(run, "school")
	Post.search(run, 0)
	for key in ["id", "point", "idx", "detail"]:
		var bad_work := run.duplicate(true)
		bad_work.busy.data[key] = 100 if key == "idx" else "假"
		rejects(bad_work, "在途取证的 " + key)
	var missing := run.duplicate(true)
	missing.explore.spots = []
	rejects(missing, "在途工时找不到对应物证")
	var partial := run.duplicate(true)
	partial.phase = "ending"
	check(Cases.list_cases(partial).is_empty(), "合卷只记已做完的调查")
	var instant := run.duplicate(true)
	instant.busy.end = instant.busy.start
	rejects(instant, "存档把现场工时改成零")
	var short_run := run.duplicate(true)
	short_run.erase("hundred_days")
	rejects(short_run, "短卷伪造调查工时")
	Post.advance(run, int(run.busy.end) - int(run.t))
	var loose := run.duplicate(true)
	loose.explore["case_detail"] = true
	rejects(loose, "未细查的证物被写入新发现")
	Post.finish_explore(run)
	Cases.settle(run, "borrowed_address", "pocket")
	for key in ["id", "person", "prop", "choice"]:
		var joint := run.duplicate(true)
		joint.busy.data[key] = "假"
		rejects(joint, "合做工时的 " + key)
	var unpaid := run.duplicate(true)
	unpaid.hundred_days.side_cases.records.borrowed_address.erase("evidence")
	rejects(unpaid, "约好的伙伴开工时并没有收回证物")


func public_shares(id: String, contribute: String, other: String, item: String) -> void:
	var run := sample(79, "write")
	for letter in Data.table("hundred_days").events:
		if int(letter.day) <= 79:
			run.hundred_days.choices[letter.id] = letter.options[0].id
	check(Cases.accept(run, id) == "", "能在第79日补接 " + id)
	var page := Cases.active(run)
	check(Post.act_explore(run, page.route.site) == "" and Post.search(run, 0).get("started", false), "能实走现场 " + id)
	Post.advance(run, int(page.route.minutes))
	Post.finish_explore(run)
	check(Cases.active(run).get("stage") == "returned", "补接案件的证物已归档 " + id)
	for choice in [contribute, other]:
		var branch := run.duplicate(true)
		var option := Cases._option(page, choice)
		Inv.add_all(branch.home, option.cost)
		check(Cases.settle(branch, id, choice) == "", "玩家能实际选下 " + str(choice))
		Post.advance(branch, int(option.minutes))
		check(Cases.completed_choice(branch, id) == choice, "完成对应工作 " + str(choice))
		branch = packed(branch)
		# 分别从每夜05:59跨过天亮，按真实晨报回信与翻页入口发放，覆盖两次轮值及中间四天。
		for morning in range(80, 87):
			branch.t = (morning - 1) * Post.DAY - 1
			check(Post.advance(branch, 1) == "dawn" and branch.dawn_due, "抵达晨报 " + str(morning))
			var letter := Chronicle.current_event(branch)
			if not letter.is_empty():
				for answer in letter.options:
					if Chronicle.reply_block(branch, answer) == "":
						Chronicle.decide(branch, letter.id, answer.id)
						break
			var before := Inv.count(branch.home, item)
			Post.ack_dawn(branch)
			var expected := 1 if item == "water" else 0
			if choice == contribute and morning in [81, 86]: expected += 1
			check(int(branch.pday) == morning and Inv.count(branch.home, item) - before == expected,
				"公灶轮值 · %s · 第%d日 %s 应增加%d" % [choice, morning, item, expected])
			var stock: Dictionary = branch.home.duplicate()
			Post.ack_dawn(branch)
			check(branch.home == stock, "重翻晨报不应重复入库")
