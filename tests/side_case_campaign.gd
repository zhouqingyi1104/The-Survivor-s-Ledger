extends "res://tests/hundred_days_journey.gd"
## 同身份同种子，分别把小名写上门牌或留下水鸟。实际赴约、查证、走完返程与合做，比较两卷的去向。

const Cases = preload("res://scripts/core/side_cases.gd")
var second_route := false
var visits := {}
var finished := {}
var bowl_offered := false
var sample_files := false
var detailed := {}
var downstream := {}


func _init() -> void:
	Data.ensure()
	balance_active = true
	bot_max_trips = 2
	bot_chores = true
	sample_files = "--sample-cases" in OS.get_cmdline_user_args()
	for branch in [false, true]:
		second_route = branch
		visits.clear()
		finished.clear()
		detailed.clear()
		downstream.clear()
		bowl_offered = false
		var days := _journey(true, "scholar", CAMPAIGN_SEED)
		check(days == 100, "没有从开局走到百日结局")
		check(visits.get("borrowed_address") == ("city_god" if branch else "school"), "水鸟或小名未改变实访地点")
		check(finished.get("borrowed_address") == ("pair" if branch else "pocket"), "未带回证物并兑现约定")
		check(bowl_offered == (not branch), "无名信袋没有分流后期隐藏案")
		check(detailed.size() == (0 if branch else 3), "两卷的现场细查凭据没有分开")
		check(downstream.size() == (0 if branch else 3), "先前的细查结办没有改变后案的可选做法")
		check(finished.has("last_lodger") == (not branch), "第95日仍可绕过信袋和船位的前约")
		check(finished.size() == (12 if branch else 15), "这条路线没有办齐应能解开的同行案")
		print("同种子 %d / %s：走访 %d 案，合办 %d 案；门牌实访 %s；无名信袋后续 %s。" % [
			CAMPAIGN_SEED, "水鸟" if branch else "小名", visits.size(), finished.size(), visits.get("borrowed_address"), bowl_offered])
		if failures > 0: break
	print("[side_case_campaign] 两卷百日，失败 %d 处" % failures)
	quit(0 if failures == 0 else 1)


func _read_today(run: Dictionary) -> void:
	var day := int(run.pday)
	var letter := ChronicleStory.current_event(run)
	if second_route and letter.get("id") == "blank_name":
		var block := ChronicleStory.decide(run, "blank_name", "mark")
		check(block.is_empty(), block)
		answered.blank_name = day
		chosen_options.blank_name = "mark"
	else:
		super._read_today(run)
	if not Cases.view(run, "bowl_post").is_empty():
		bowl_offered = true
	if sample_files and day in [23, 54, 95]:
		_save_chapter(run, ("水鸟" if second_route else "小名") + "-第%02d日" % day)


func choose_action(run: Dictionary) -> bool:
	var day_minutes := Post.day_minute(run)
	if int(run.pday) >= 23 and day_minutes < 500 and Post.can_act(run, 10) == "" and State.attr(run, "energy") >= 27:
		var page := Cases.active(run)
		if page.is_empty():
			for entry in Cases.list_cases(run):
				if entry.stage == "offered" and Cases.accept_block(run, entry.id) == "":
					check(Cases.accept(run, entry.id) == "", "无法赴约：" + str(entry.id))
					page = Cases.active(run)
					break
		if page.get("stage") == "field":
			return _visit(run, page)
		if page.get("stage") == "returned":
			var options: Array = page.options.duplicate()
			for option in options:
				if option.id in ["balance", "water_berth", "beams"]:
					check(Cases.settle_block(run, page.id, option.id).is_empty(), "有凭据却不能照前案的办法结办")
					downstream[option.id] = true
			if second_route: options.reverse()
			elif page.detail: options.sort_custom(func(a, b): return a.get("when", {}).get("detail", false) and not b.get("when", {}).get("detail", false))
			for option in options:
				if Cases.settle_block(run, page.id, option.id) == "":
					check(Cases.settle(run, page.id, option.id) == "", "无法按约开工")
					return true
	return super.choose_action(run)


func _visit(run: Dictionary, page: Dictionary) -> bool:
	if Post.act_explore(run, page.route.site) != "": return false
	if not _settle_bot_travel(run): return true
	var idx := -1
	for i in run.explore.spots.size():
		if run.explore.spots[i].get("side_case") == page.id:
			idx = i
			break
	check(idx >= 0, "实访地点缺少证物：" + str(page.id))
	if idx < 0: return false
	var start: int = run.t
	var technique := ""
	if not second_route and page.route.has("inspection"):
		technique = "inspect:" + str(page.route.inspection.correct)
	var result := Post.search(run, idx, technique)
	check(result.get("started", false), "调查没开工：" + str(result))
	for tick in 32:
		if not _settle_bot_travel(run) or not Post.is_busy(run): break
		Post.advance(run, maxi(1, int(run.busy.end) - int(run.t)))
	check(run.explore.get("case_cargo") == page.id and int(run.t) - start >= int(page.route.minutes), "现场未做完就取得证物")
	visits[page.id] = str(page.route.site)
	Post.finish_explore(run)
	_settle_bot_travel(run)
	check(Cases.active(run).get("stage") == "returned", "返程没把证物带回")
	if technique != "":
		check(Cases.active(run).get("detail", false), "细查没有把发现带回")
		detailed[page.id] = true
	return true


func play_day(run: Dictionary) -> void:
	super.play_day(run)
	if sample_files and run.phase == "ending":
		_save_chapter(run, ("水鸟" if second_route else "小名") + "-百日卷尾")
	for entry in Cases.list_cases(run):
		if entry.stage == "done":
			finished[entry.id] = entry.choice
