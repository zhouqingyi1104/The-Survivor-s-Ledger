extends RefCounted
## 三条调查线：尸劫来历（主线）、风声与危机、轮回调查。
##
## 从 dialogs.gd 搬出来（工程债第 1 条第四批）。三个入口仍是 Dialogs.mainline() / Dialogs.crisis() /
## Dialogs.cycle_inquiry()，那几个函数只是转发；面板内容与搬之前逐字一致，控件树导出对照过。
##
## 三块放同一个文件，是因为它们本来就是一串：主线的面板里有「身份与前世」和「外出地点」两个跳转，
## 危机的面板与主线共用同一套时刻写法（第几日几点），轮回调查则是前世那一页的第三个入口。
##
## 两处要留意：
##   - `_crisis_when` / `crisis_status` / `crisis_clock_text` 里的时刻与状态文字，原本用 dialogs.gd 的
##     `_trade_clock`；那个小工具现在挪进 kit.gd，两边共用（kit.gd 里叫 clock_text）。
##   - 宅院 HUD（post_screen.gd）直接调 Dialogs.crisis_status / Dialogs.crisis_clock_text，
##     所以 Dialogs 上留了两个一行转发，调用点没改。
## 还有两处跨面板跳转仍指向没搬家的入口：`Dialogs.identity_paths`（身份与前世）、
## `Dialogs.explore_pick`（外出地点）。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const Kit = preload("res://scripts/ui/dialogs/kit.gd")


# ---------- 尸劫来历（主线） ----------

static func open_mainline() -> void:
	Game.act(func(): return Post.trade_refresh(Game.run))
	UI.open_modal("mainline", "尸劫来历 · 调查与出路", _mainline, true, 860)


static func _mainline(body: VBoxContainer) -> void:
	var run := Game.run
	var view := Mainline.view(run)
	var content := UI.vbox(10)
	content.add_child(UI.label(str(view.get("title", "尸劫来历")), 22, UI.GOLD))
	content.add_child(UI.para("当前目标：" + str(view.get("goal", "暂守宅院")), 19))
	content.add_child(UI.para(str(view.get("summary", "")), 17))
	var letter := Mainline.Lane.prompt(Mainline.state(run), int(run.t))
	if letter != "":
		var lane := UI.vbox(5)
		lane.add_child(UI.para(letter, 17, UI.INK))
		for row in Mainline.lane_options(run):
			lane.add_child(UI.para(str(row.hint), 16))
			var reason := str(row.block)
			var choice := UI.button(str(row.label), _mainline_do.bind(str(row.id), str(view.token)), reason != "", reason)
			choice.set_meta("mainline_action", row.id)
			lane.add_child(choice)
			if reason != "": lane.add_child(UI.para(reason, 15, UI.CINNABAR))
		content.add_child(UI.panel(lane))
	var identity_entry := UI.button("身份与前世 · 查看专属解法", Dialogs.identity_paths)
	identity_entry.set_meta("identity_entry", "mainline")
	content.add_child(identity_entry)
	var map_entry := UI.button("外出地点 · 查看路线与封锁", _mainline_map)
	map_entry.set_meta("mainline_map", true)
	content.add_child(map_entry)
	for deadline in view.get("deadlines", []):
		content.add_child(UI.para("期限：" + str(deadline), 17, UI.CINNABAR))
	for cost in view.get("costs", []):
		content.add_child(UI.para("行动与代价：" + str(cost), 16))
	var evidence: Dictionary = view.get("evidence", {})
	content.add_child(UI.para("已带回的证据：义庄运尸簿%s · 七灯及后山图%s\n前世的残卷能读，但证据得这一世亲自去拿回来。" % [" ✓" if bool(evidence.get("mortuary", false)) else " 未取回", " ✓" if bool(evidence.get("temple", false)) else " 未取回"], 16, UI.JADE))
	var routes := {"": "还没定", "hold": "坚守宅院", "escape": "备好撤离", "ritual": "备好破阵"}
	content.add_child(UI.para("这一世的出路：" + str(routes.get(str(view.get("route", "")), "还没定")), 17, UI.GOLD))
	var interventions: Dictionary = view.get("interventions", {})
	content.add_child(UI.para("已做成的事：断运%s；封阵%s。\n完工后才改变尸潮；已经开打的那一夜不变。" % ["（" + _crisis_when(int(interventions.disrupt_t)) + "）" if int(interventions.get("disrupt_t", -1)) >= 0 else " 未做", "（" + _crisis_when(int(interventions.ritual_t)) + "）" if int(interventions.get("ritual_t", -1)) >= 0 else " 未做"], 16))
	var target := str(view.get("target", ""))
	var objective: Dictionary = view.get("objective", {})
	if target != "":
		content.add_child(UI.label("调查地点：" + str(view.get("target_name", target)), 19, UI.GOLD))
		if not objective.is_empty():
			content.add_child(UI.para("要查的：%s\n%s" % [str(objective.get("name", "")), str(objective.get("hint", ""))], 17))
		var block := Post.can_act(run, 10)
		if block == "": block = Explore.point_block(run, target)
		if block == "" and Post.day_minute(run) + 60 >= Post.CURFEW_AT: block = "天快黑了，无法完成出门路程。"
		if block != "": content.add_child(UI.para(block, 15, UI.CINNABAR))
		var depart := UI.button("出门去" + str(view.get("target_name", target)), _mainline_depart.bind(target), block != "", block)
		depart.set_meta("mainline_depart", target)
		content.add_child(depart)
	var work: Dictionary = view.get("work", {})
	if not work.is_empty(): content.add_child(UI.para("正在做：%s · %s 做完。" % [str(run.get("busy", {}).get("label", "调查")), _crisis_when(int(work.get("end_t", 0)))], 17, UI.GOLD))
	if str(view.get("last_result", "")) != "": content.add_child(UI.para("最近结果：" + str(view.last_result), 17, UI.JADE))
	for option in Mainline.options(run):
		var card := UI.vbox(4)
		card.add_child(UI.para(str(option.hint), 16))
		var block := str(option.block)
		if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
		var button := UI.button(str(option.text), _mainline_do.bind(str(option.id), str(view.get("token", ""))), block != "", block)
		button.set_meta("mainline_action", str(option.id))
		card.add_child(button)
		content.add_child(UI.panel(card))
	content.add_child(UI.sep())
	content.add_child(UI.label("调查记录", 19, UI.GOLD))
	var history: Array = view.get("history", [])
	if history.is_empty(): content.add_child(UI.para("还没有调查记录。", 16))
	for k in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 %s · %s" % [int(entry.get("day", 0)), Kit.clock_text(int(entry.get("t", 0))), str(entry.get("result", ""))], 15))
	var scroll := UI.scroll(content, mini(470, maxi(210, int(UI.host.get_viewport().get_visible_rect().size.y) - 210)))
	scroll.name = "MainlineDetailsScroll"
	body.add_child(scroll)


static func _mainline_do(action: String, token: String) -> void:
	var result = Game.act(func(): return Post.mainline_action(Game.run, action, token))
	if typeof(result) == TYPE_STRING and result == "" and (Post.is_busy(Game.run) or Game.run.get("phase", "") != "post"):
		for key in ["mainline", "journal"]: UI.close_modal(key)


static func _mainline_depart(target: String) -> void:
	UI.close_modal("mainline")
	UI.close_modal("journal")
	Kit.act(func(): return Post.act_explore(Game.run, target))


static func _mainline_map() -> void:
	UI.close_modal("mainline")
	UI.close_modal("journal")
	Dialogs.explore_pick()


# ---------- 风声与危机 ----------

static func open_crisis() -> void:
	Game.act(func(): return Post.crisis_refresh(Game.run))
	UI.open_modal("crisis", "风声与危机 · 查验与筹备", _crisis, true, 850)


static func crisis_status(view: Dictionary) -> String:
	var certainty: String = {"unknown": "尚未核实", "real": "已核实 · 属实", "false": "已核实 · 虚惊"}.get(str(view.get("confirmed", "unknown")), "尚未核实")
	if str(view.get("stage", "")) == "impact": return "危机已发生 · " + certainty
	if str(view.get("stage", "")) == "resolved":
		return {"averted": "已了结 · 提前防住", "false_alarm": "已了结 · 虚惊", "endured": "已了结 · 影响过去", "repaired": "已了结 · 补救完成"}.get(str(view.get("outcome", "")), "已了结")
	return "预兆 · " + certainty


static func crisis_clock_text(view: Dictionary) -> String:
	if view.is_empty(): return "暂时没有风声"
	if str(view.get("stage", "")) == "resolved": return crisis_status(view)
	var target := int(view.get("end_t", 0)) if str(view.get("stage", "")) == "impact" else int(view.get("impact_t", 0))
	var left := maxi(0, target - int(Game.run.get("t", 0)))
	var duration := "%d 天 %02d:%02d" % [left / 1440, (left % 1440) / 60, left % 60] if left >= 1440 else "%02d:%02d" % [left / 60, left % 60]
	var prefix := "影响结束还有 " if str(view.get("stage", "")) == "impact" else ("预计应验还有 " if str(view.get("confirmed", "")) == "real" else "可能应验还有 ")
	return prefix + duration


static func _crisis_when(t: int) -> String:
	return "第 %d 日 %s" % [t / 1440 + 1, Kit.clock_text(t)]


static func _crisis(body: VBoxContainer) -> void:
	var run := Game.run
	var view := Crisis.view(run)
	var content := UI.vbox(10)
	if view.is_empty():
		content.add_child(UI.para("近日没有风声。有新的风声，会挂在宅院上方。", 18))
	else:
		content.add_child(UI.label(str(view.title) + " · " + crisis_status(view), 20, UI.GOLD))
		content.add_child(UI.para("预兆：%s\n线索来源：%s" % [str(view.sign), str(view.source)], 17))
		content.add_child(UI.para(crisis_clock_text(view), 19, UI.CINNABAR if str(view.stage) == "impact" else UI.GOLD))
		content.add_child(UI.para("预告应验：%s\n若成真，自己缓过来：%s" % [_crisis_when(int(view.impact_t)), _crisis_when(int(view.end_t))], 16))
		var evidence := str(view.get("evidence", ""))
		content.add_child(UI.para("已知证据：" + (evidence if evidence != "" else "还没查到证据，说不准是真是假。"), 17, UI.JADE if evidence != "" else UI.INK_SOFT))
		if str(view.get("effect", "")) != "":
			content.add_child(UI.para(str(view.effect), 16))
		var responses := {"": "尚未选择", "prepare": "自己防备", "aid": "请线人帮忙", "ignore": "先看看（不再提前防备）", "emergency": "事后补救"}
		content.add_child(UI.para("本场应对：%s%s" % [responses.get(str(view.get("response", "")), "已记录"), " · 防护已完成" if bool(view.get("protected", false)) else ""], 16))
		var work: Dictionary = view.get("work", {})
		if not work.is_empty():
			content.add_child(UI.para("正在做：%s · 预计 %s 做完。" % [{"investigate": "核实风声", "prepare": "提前处置", "aid": "请线人帮忙", "emergency": "事后补救"}.get(str(work.get("action", "")), "这件事"), _crisis_when(int(work.end_t))], 17, UI.GOLD))
		if str(view.get("last_result", "")) != "":
			content.add_child(UI.para("最新危机记录：" + str(view.last_result), 17, UI.JADE))
		for option in Crisis.options(run):
			var card := UI.vbox(4)
			card.add_child(UI.para(str(option.hint), 16))
			var block := str(option.block)
			if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
			var button := UI.button(str(option.text), _crisis_do.bind(str(option.id), str(view.token)), block != "", block)
			button.set_meta("crisis_action", str(option.id))
			card.add_child(button)
			content.add_child(UI.panel(card))
	content.add_child(UI.sep())
	content.add_child(UI.label("危机记录 · 最近十二条", 19, UI.GOLD))
	var history: Array = Crisis.state(run).get("history", [])
	if history.is_empty(): content.add_child(UI.para("还没有风声和应对的记录。", 16))
	var titles := {"well_freeze": "井口冻裂", "fuel_shortage": "运柴中断", "herb_shortage": "药草挤兑"}
	for k in range(history.size() - 1, maxi(-1, history.size() - 13), -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 · %s · %s：%s" % [int(entry.day), titles.get(str(entry.kind), "风声"), Trade.ACTORS.get(str(entry.actor), "线人"), str(entry.result)], 15))
	var scroll := UI.scroll(content, mini(450, maxi(200, int(UI.host.get_viewport().get_visible_rect().size.y) - 220)))
	scroll.name = "CrisisDetailsScroll"
	body.add_child(scroll)


static func _crisis_do(action: String, token: String) -> void:
	var result = Game.act(func(): return Post.crisis_action(Game.run, action, token))
	if typeof(result) == TYPE_STRING and result == "" and Post.is_busy(Game.run):
		# 劫余录也会暂停宅院时钟；两层都合上，才能让实际工作推进。
		UI.close_modal("crisis")
		UI.close_modal("journal")


# ---------- 轮回调查 ----------

static func open_cycle_inquiry() -> void:
	if Game.run.is_empty(): return
	Game.act(func(): return Post.trade_refresh(Game.run))
	for key in ["journal", "past_lives"]: UI.close_modal(key)
	UI.open_modal("cycle_inquiry", "轮回调查 · 旧诺与今证", _cycle_inquiry, true, 860)


static func _cycle_inquiry(body: VBoxContainer) -> void:
	var run := Game.run
	var view := Cycle.view(run)
	var content := UI.vbox(10)
	content.add_child(UI.para(str(view.get("summary", "")), 17))
	content.add_child(UI.para("前世的约定和记忆只能指个方向；查访、对账、订新约，都得这一世亲自做。在宅院里就能查，做完才算数。", 15, UI.INK_SOFT))
	var work: Dictionary = view.get("work", {})
	if not work.is_empty():
		var remaining := maxi(0, int(work.get("end_t", 0)) - int(run.get("t", 0)))
		content.add_child(UI.para("正在做：%s · 还要 %d 分钟。" % [str(work.get("label", "轮回调查")), remaining], 17, UI.GOLD))
	for entry in view.get("cases", []):
		if not entry is Dictionary: continue
		var card := UI.vbox(6)
		card.set_meta("cycle_case", str(entry.get("id", "")))
		card.set_meta("cycle_stage", str(entry.get("stage", "")))
		card.add_child(UI.label(str(entry.get("title", "前世来信")) + " · " + str(entry.get("stage_label", entry.get("stage", ""))), 20, UI.GOLD))
		var source := str(entry.get("source_label", ""))
		if source != "": card.add_child(UI.para("前世来源：" + source, 16, UI.JADE))
		if str(entry.get("stage", "")) == "sealed":
			card.add_child(UI.para("这是你带来的旧梦，还没在这一世查访过；邻人未必也记得。", 15, UI.INK_SOFT))
		for field in ["publish_text", "clue", "evidence_text"]:
			var line := str(entry.get(field, ""))
			if line != "": card.add_child(UI.para(line, 16, UI.JADE if field == "evidence_text" else UI.INK))
		var deadline := str(entry.get("deadline_text", ""))
		if deadline != "": card.add_child(UI.para("期限：" + deadline, 16, UI.CINNABAR))
		var result := str(entry.get("last_result", ""))
		if result != "": card.add_child(UI.para("今世结果：" + result, 16, UI.JADE))
		for option in entry.get("options", []):
			if not option is Dictionary: continue
			var hint := str(option.get("hint", ""))
			if hint != "": card.add_child(UI.para(hint, 16))
			var block := str(option.get("block", ""))
			if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
			var button := UI.button(str(option.get("text", option.get("id", ""))), _cycle_do.bind(str(entry.get("id", "")), str(option.get("id", "")), str(view.get("token", "")), str(Past.state(run).get("id", ""))), block != "", block)
			button.set_meta("cycle_action", str(option.get("id", "")))
			button.set_meta("cycle_case_id", str(entry.get("id", "")))
			card.add_child(button)
		content.add_child(UI.panel(card))
	content.add_child(UI.sep())
	content.add_child(UI.label("轮回调查 · 今世记录", 19, UI.GOLD))
	var history: Array = view.get("history", [])
	if history.is_empty(): content.add_child(UI.para("还没查访。旧梦浮现后，可以先查访，再决定续约、赔礼还是重新救助。", 16))
	for k in range(history.size() - 1, -1, -1):
		var entry = history[k]
		if entry is Dictionary:
			content.add_child(UI.para("第 %d 日 · %s" % [int(entry.get("day", 0)), str(entry.get("result", ""))], 15))
	var scroll := UI.scroll(content, mini(450, maxi(210, int(UI.host.get_viewport().get_visible_rect().size.y) - 210)))
	scroll.name = "CycleInquiryScroll"
	body.add_child(scroll)


static func _cycle_do(case_id: String, action: String, token: String, life: String) -> void:
	if Game.run.is_empty() or str(Past.state(Game.run).get("id", "")) != life: return
	var result = Game.act(func(): return Post.cycle_action(Game.run, case_id, action, token))
	if typeof(result) == TYPE_STRING and result == "" and Post.is_busy(Game.run):
		for key in ["cycle_inquiry", "journal", "past_lives"]: UI.close_modal(key)
