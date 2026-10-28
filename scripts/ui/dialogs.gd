extends Node
## 各种弹窗（自动加载为 Dialogs）：吃喝用药、灶房、菜畦、营造、读书、外出、事件、夜报、神龛求签、劫余录。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const SiteJourney = preload("res://scripts/core/site_journey.gd")
const Events = preload("res://scripts/core/events.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const NpcDialogue = preload("res://scripts/core/npc_dialogue.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Opening = preload("res://scripts/core/opening.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const InputCfg = preload("res://scripts/core/input_cfg.gd")
const VideoCfg = preload("res://scripts/core/video_cfg.gd")
const Brief = preload("res://scripts/core/brief.gd")
const Manual = preload("res://scripts/core/manual.gd")
const Agenda = preload("res://scripts/core/agenda.gd")
const INVENTORY_PAPER = preload("res://assets/ui/inventory/paper.png")
const INVENTORY_ART := {
	"rice": preload("res://assets/ui/inventory/rice.png"),
	"nails": preload("res://assets/ui/inventory/nails.png"),
}

var _trade_actor := "ning"
var _npc_actor := "ning"
## 当前弹窗里可以被回写的控件（弹窗内容是按需重建的，重建时重新登记）
var _live := {}

## 家具的功用，摆出来能做什么（写给人看的）
const FN_TEXT := {
	"cook": "能做饭", "sleep": "能就寝", "read": "能读书", "craft": "能营造",
	"store": "能存货", "pickle": "能腌菜", "smoke": "能熏肉", "heat": "夜里更暖",
	"trap": "能捕鼠", "plant": "能种菜", "incense": "能上香", "books": "能藏书",
	"water": "能取水",
}
const WHERE_TEXT := {"indoor": "摆屋里", "outdoor": "摆院里"}

static var GRADE_COLORS := {"不足": UI.CINNABAR, "适当": UI.GOLD, "宽裕": UI.JADE}
static var STATUS_COLORS := {"正常": UI.JADE, "拥挤": UI.GOLD, "哄抢": UI.CINNABAR, "关门": UI.INK_FAINT}
const CAT_ORDER := ["食", "菜", "水", "药", "粮", "柴炭", "守具", "材", "种", "器", "书", "杂"]
const FX_NAMES := {"food": "饱腹", "water": "饮水", "hp": "气血", "mood": "心神", "energy": "精力"}


func _run() -> Dictionary:
	return Game.run


func _act(fn: Callable) -> void:
	Game.act(fn)


## 做成了才出声（买卖的钱币声、吃喝声……）。
func _act_sfx(fn: Callable, sound: String) -> void:
	var res = Game.act(fn)
	if typeof(res) != TYPE_STRING or res == "":
		Sfx.play(sound, -4.0)


## 开工类动作：成功了就把弹窗关掉，好看见人在干活。
func _start(key: String, fn: Callable) -> void:
	var res = Game.act(fn)
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal(key)


static func fx_text(fx: Dictionary) -> String:
	var parts := []
	for k in FX_NAMES:
		if fx.has(k):
			parts.append("%s%+d" % [FX_NAMES[k], int(fx[k])])
	if fx.has("cure"):
		parts.append("祛尸瘟" if float(fx.cure) >= 1.0 else "或可祛尸瘟")
	return " ".join(parts)


## 一行末尾的操作按钮；做不了时把原因直接写在按钮左边（只放在 tooltip 里不容易看到）。
func _action(row: HBoxContainer, text: String, cb: Callable, block: String) -> void:
	if block != "":
		row.add_child(UI.label(block, 15, UI.CINNABAR))
	row.add_child(UI.button(text, cb, block != "", block))


static func req_text(store: Dictionary, req: Dictionary) -> String:
	var parts := []
	for id in req:
		parts.append("%s %d（有 %d）" % [Data.item_name(id), int(req[id]), Inv.count(store, id)])
	return "、".join(parts)


# ---------- 劫余录 ----------

func journal() -> void:
	UI.open_modal("journal", "劫余录", _journal, true, 900)


## 要务的分级配色：要命的说朱砂，要紧的用墨，提醒的更淡
func _brief_color(level: int) -> Color:
	return UI.CINNABAR if level >= Brief.ALARM else (UI.INK if level == Brief.WARN else UI.INK_FAINT)


func _journal(body: VBoxContainer) -> void:
	var content := UI.vbox(8)
	# 最上面先回答"我在干什么"：目标一句 + 今天该注意的几件事
	content.add_child(UI.para(Brief.goal(_run()), 18, UI.GOLD))
	var todos := Brief.lines(_run())
	if not todos.is_empty():
		content.add_child(UI.label("今日要务", 15, UI.INK_FAINT))
		for line in todos:
			content.add_child(UI.para("· " + str(line.text), 16, _brief_color(int(line.level))))
	content.add_child(UI.sep())
	var d := Director.state(_run())
	content.add_child(UI.label("人情往来：" + " · ".join(Director.ACTORS.keys().map(func(id): return "%s %+d" % [Director.ACTORS[id], int(d.relations[id])])), 16))
	for promise in d.promises:
		content.add_child(UI.para("第 %d 日 · %s 约定送来 %s" % [promise.day, Director.ACTORS[promise.actor], Director.describe(promise.give)], 16))
	var opening_entry := UI.button("本世开局 · 行囊、人情与危机风声", opening_info)
	opening_entry.set_meta("opening_entry", "journal")
	content.add_child(opening_entry)
	content.add_child(UI.button("尸劫来历 · 调查与出路", mainline))
	var identity_entry := UI.button("身份与旧世 · 专属解法", identity_paths)
	identity_entry.set_meta("identity_entry", "journal")
	content.add_child(identity_entry)
	var cycle_entry := UI.button("轮回调查 · 旧诺与今证", cycle_inquiry)
	cycle_entry.set_meta("cycle_entry", "journal")
	content.add_child(cycle_entry)
	content.add_child(UI.button("前世记忆 · 查看旧世与觉醒", past_lives))
	content.add_child(UI.para(Neighbor.summary(_run()), 17))
	content.add_child(UI.button("邻里事务 · 目标与选择记录", neighbor))
	content.add_child(UI.button("纸鹤往来 · 交易与欠账", social_trade))
	content.add_child(UI.button("邻人与商情 · 目标与行动", npc_autonomy))
	content.add_child(UI.button("风声与危机 · 查验与筹备", crisis))
	var lines: Array = _run().get("log", [])
	var s := UI.scroll(UI.log_view(lines, lines.size(), 17), 180)
	var bar := s.get_v_scroll_bar()
	bar.changed.connect(func(): s.scroll_vertical = int(bar.max_value))
	content.add_child(s)
	var scroll := UI.scroll(content, mini(480, maxi(220, int(get_viewport().get_visible_rect().size.y) - 190)))
	scroll.name = "JournalDetailsScroll"
	body.add_child(scroll)


func opening_info() -> void:
	UI.close_modal("journal")
	UI.open_modal("opening", "本世开局 · 已经发生的筹备", _opening_info, true, 860)


func _opening_info(body: VBoxContainer) -> void:
	var view := Opening.view(_run())
	var content := UI.vbox(10)
	content.add_child(UI.label(str(view.get("title", "普通行囊")), 23, UI.GOLD))
	content.add_child(UI.para(str(view.get("summary", "这世按本职过活。")), 17))
	var effects: Dictionary = view.get("effects", {})
	if not effects.is_empty():
		content.add_child(UI.para("已花银两 %s · 已用 %d 时辰" % [Pre.money(int(effects.get("silver_cost", 0))), int(effects.get("hours", 0))], 17, UI.GOLD))
		var spent: Dictionary = effects.get("spent", {})
		var gained: Dictionary = effects.get("gained", {})
		content.add_child(UI.para("已付物资：" + (Data.describe_items(spent) if not spent.is_empty() else "无") + "\n已得物资：" + (Data.describe_items(gained) if not gained.is_empty() else "无"), 16))
		for actor in effects.get("contacts", {}):
			var contact: Dictionary = effects.contacts[actor]
			content.add_child(UI.para("今世往来 · %s：信任 %+d、人情 %+d" % [Director.ACTORS.get(actor, actor), int(contact.get("trust", 0)), int(contact.get("favors", 0))], 16, UI.JADE))
		var warning: Dictionary = effects.get("first_warning", {})
		if not warning.is_empty():
			var title := str(Crisis.CATALOG.get(str(warning.get("kind", "")), {}).get("title", "危机风声"))
			content.add_child(UI.para("首场预兆：第 %d 日 · %s · 线人 %s。是否成真仍需本世查验。" % [int(warning.get("warning_day", 0)), title, Director.ACTORS.get(str(warning.get("actor", "")), "邻人")], 16, UI.GOLD))
	var source := str(view.get("source_label", ""))
	if source != "": content.add_child(UI.para("筹备依据：" + source, 16, UI.JADE))
	content.add_child(UI.para("这是本世已经支付和得到的开局结果。其后交易、人情和危机查验仍按实际选择推进；下世可另选一项。", 15, UI.INK_SOFT))
	for entry in view.get("history", []):
		if entry is Dictionary:
			content.add_child(UI.para(str(entry.get("text", entry.get("result", ""))), 16))
		elif entry is String:
			content.add_child(UI.para(entry, 16))
	var scroll := UI.scroll(content, mini(400, maxi(220, int(get_viewport().get_visible_rect().size.y) - 190)))
	scroll.name = "OpeningDetailsScroll"
	body.add_child(scroll)


func identity_paths() -> void:
	Game.act(func(): return Post.trade_refresh(Game.run))
	for key in ["journal", "mainline", "past_lives"]: UI.close_modal(key)
	UI.open_modal("identity", "身份与旧世 · 专属解法", _identity_paths, true, 860)


static func _identity_inheritance(sources: Array) -> String:
	var labels := {"sealed_lamps": "曾完成七灯封阵", "escaped_city": "曾实际离城", "gave_medicine": "曾赠药救邻", "returned_evidence": "曾带回义庄证物"}
	var parts := PackedStringArray()
	for source in sources:
		if source is Dictionary and labels.has(str(source.get("tag", ""))):
			parts.append("第 %d 世 · %s" % [int(source.get("source_life", 0)), str(labels[source.tag])])
	return "；".join(parts)


func _identity_paths(body: VBoxContainer) -> void:
	var run := _run()
	var view := Identity.view(run)
	var content := UI.vbox(10)
	content.add_child(UI.label(str(view.get("role_name", "本世身份")) + " · " + str(view.get("title", "专属解法")), 22, UI.GOLD))
	content.add_child(UI.para(str(view.get("summary", "")), 17))
	var sources := _identity_inheritance(view.get("inheritance", []))
	content.add_child(UI.para("本世带入的经验：" + (sources if sources != "" else "尚无符合条件的旧世经历。"), 16, UI.JADE))
	content.add_child(UI.para("旧世经验属于你自己的记忆；邻人仍只知道自己已经觉醒的片段。本世调查和返程不能省略。", 15, UI.INK_SOFT))
	var story := UI.button("查看本世调查目标与出路", _identity_story)
	story.set_meta("identity_story", true)
	content.add_child(story)
	var work: Dictionary = view.get("work", {})
	if not work.is_empty():
		var remaining := maxi(0, int(work.get("end_t", 0)) - int(run.get("t", 0)))
		content.add_child(UI.para("正在执行：%s · 还需 %d 分钟。完工才生效，中断不退材料。" % [str(work.get("label", "身份解法")), remaining], 17, UI.GOLD))
	for option in view.get("options", []):
		var card := UI.vbox(5)
		card.add_child(UI.para(str(option.get("hint", "")), 16))
		card.add_child(UI.para("行动与代价：" + str(option.get("cost_text", "")), 16, UI.GOLD))
		var block := str(option.get("block", ""))
		if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
		var button := UI.button(str(option.get("text", option.id)), _identity_do.bind(str(option.id), str(view.get("token", "")), str(Past.state(run).get("id", ""))), block != "", block)
		button.set_meta("identity_action", str(option.id))
		card.add_child(button)
		content.add_child(UI.panel(card))
	var intel := str(view.get("intel", ""))
	if intel != "":
		var intel_details := UI.vbox(5)
		intel_details.name = "IdentityIntel"
		intel_details.add_child(UI.label("更路情报 · 真实尸潮", 19, UI.GOLD))
		intel_details.add_child(UI.para(intel, 16))
		for line in Post.identity_intel(run): intel_details.add_child(UI.para(str(line), 16, UI.JADE))
		content.add_child(intel_details)
	content.add_child(UI.sep())
	content.add_child(UI.label("本世身份选择记录", 19, UI.GOLD))
	var history: Array = view.get("history", [])
	if history.is_empty(): content.add_child(UI.para("尚未作出身份选择。完成本世义庄取证并返宅后，再决定如何处置；公共断运和抄录仍可选。", 16))
	for k in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 %s · %s" % [int(entry.get("day", 0)), _trade_clock(int(entry.get("t", 0))), str(entry.get("result", ""))], 15))
	var scroll := UI.scroll(content, mini(470, maxi(210, int(get_viewport().get_visible_rect().size.y) - 210)))
	scroll.name = "IdentityDetailsScroll"
	body.add_child(scroll)


func _identity_do(action: String, token: String, life: String) -> void:
	if Game.run.is_empty() or str(Past.state(Game.run).get("id", "")) != life: return
	var result = Game.act(func(): return Post.identity_action(Game.run, action, token))
	if typeof(result) == TYPE_STRING and result == "" and Post.is_busy(Game.run):
		for key in ["identity", "journal", "mainline", "past_lives"]: UI.close_modal(key)


func _identity_story() -> void:
	UI.close_modal("identity")
	mainline()


func mainline() -> void:
	Game.act(func(): return Post.trade_refresh(Game.run))
	UI.open_modal("mainline", "尸劫来历 · 调查与出路", _mainline, true, 860)


func _mainline(body: VBoxContainer) -> void:
	var run := _run()
	var view := Mainline.view(run)
	var content := UI.vbox(10)
	content.add_child(UI.label(str(view.get("title", "尸劫来历")), 22, UI.GOLD))
	content.add_child(UI.para("当前目标：" + str(view.get("goal", "暂守宅院")), 19))
	content.add_child(UI.para(str(view.get("summary", "")), 17))
	var identity_entry := UI.button("身份与旧世 · 查看专属解法", identity_paths)
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
	content.add_child(UI.para("本世已交回证据：义庄运尸簿%s · 七灯及后山图%s\n旧世残卷可供阅读，不能代替这一世亲自调查和完成返程。" % [" ✓" if bool(evidence.get("mortuary", false)) else " 未取回", " ✓" if bool(evidence.get("temple", false)) else " 未取回"], 16, UI.JADE))
	var routes := {"": "尚未锁定", "hold": "坚守宅院", "escape": "备好撤离", "ritual": "备好破阵"}
	content.add_child(UI.para("本世路线：" + str(routes.get(str(view.get("route", "")), "尚未锁定")), 17, UI.GOLD))
	var interventions: Dictionary = view.get("interventions", {})
	content.add_child(UI.para("已完成干预：断运%s；封阵%s。\n尸潮变化只计实际完工，已经开战的整夜安排保持原样。" % ["（" + _crisis_when(int(interventions.disrupt_t)) + "）" if int(interventions.get("disrupt_t", -1)) >= 0 else " 未做", "（" + _crisis_when(int(interventions.ritual_t)) + "）" if int(interventions.get("ritual_t", -1)) >= 0 else " 未做"], 16))
	var target := str(view.get("target", ""))
	var objective: Dictionary = view.get("objective", {})
	if target != "":
		content.add_child(UI.label("调查地点：" + str(view.get("target_name", target)), 19, UI.GOLD))
		if not objective.is_empty():
			content.add_child(UI.para("专属目标：%s\n%s" % [str(objective.get("name", "")), str(objective.get("hint", ""))], 17))
		var block := Post.can_act(run, 10)
		if block == "": block = Explore.point_block(run, target)
		if block == "" and Post.day_minute(run) + 60 >= Post.CURFEW_AT: block = "天快黑了，无法完成出门路程。"
		if block != "": content.add_child(UI.para(block, 15, UI.CINNABAR))
		var depart := UI.button("出门去" + str(view.get("target_name", target)), _mainline_depart.bind(target), block != "", block)
		depart.set_meta("mainline_depart", target)
		content.add_child(depart)
	var work: Dictionary = view.get("work", {})
	if not work.is_empty(): content.add_child(UI.para("正在执行：%s · %s 完工。开始付出的材料不退，完工才生效。" % [str(run.get("busy", {}).get("label", "主线事务")), _crisis_when(int(work.get("end_t", 0)))], 17, UI.GOLD))
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
	content.add_child(UI.label("本世调查记录", 19, UI.GOLD))
	var history: Array = view.get("history", [])
	if history.is_empty(): content.add_child(UI.para("尚无本世调查记录。", 16))
	for k in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 %s · %s" % [int(entry.get("day", 0)), _trade_clock(int(entry.get("t", 0))), str(entry.get("result", ""))], 15))
	var scroll := UI.scroll(content, mini(470, maxi(210, int(get_viewport().get_visible_rect().size.y) - 210)))
	scroll.name = "MainlineDetailsScroll"
	body.add_child(scroll)


func _mainline_do(action: String, token: String) -> void:
	var result = Game.act(func(): return Post.mainline_action(Game.run, action, token))
	if typeof(result) == TYPE_STRING and result == "" and (Post.is_busy(Game.run) or Game.run.get("phase", "") != "post"):
		for key in ["mainline", "journal"]: UI.close_modal(key)


func _mainline_depart(target: String) -> void:
	UI.close_modal("mainline")
	UI.close_modal("journal")
	_act(func(): return Post.act_explore(Game.run, target))


func _mainline_map() -> void:
	UI.close_modal("mainline")
	UI.close_modal("journal")
	explore_pick()


## 只读公开意图；HUD计数不能把未看过的角色对话提前冻结。
func npc_pending_count(run: Dictionary) -> int:
	var count := 0
	for actor in Trade.ACTORS:
		var plan: Dictionary = Npc.view(run, actor).get("plan", {})
		if str(plan.get("status", "")) == "pending" and str(plan.get("response", "")) == "" and int(run.get("t", 0)) < int(plan.get("due_t", 0)):
			count += 1
	return count


func npc_autonomy() -> void:
	Game.act(func(): return Post.trade_refresh(Game.run))
	UI.open_modal("npc_autonomy", "邻人与商情 · 目标与行动", _npc_autonomy, true, 850)


func _npc_pick(actor: String) -> void:
	_npc_actor = actor
	if UI.host != null and UI.host.has_modal("npc_autonomy"):
		UI.host._modals.npc_autonomy._queue()


func _npc_trade() -> void:
	_trade_actor = _npc_actor
	UI.close_modal("npc_autonomy")
	social_trade()


func _trade_npc() -> void:
	_npc_actor = _trade_actor
	UI.close_modal("social_trade")
	npc_autonomy()


func _npc_autonomy(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("他们每天 08:00 公开打算、16:00 自行执行。你可以提前介入；没有回应也会照常行动。", 16))
	var tabs := UI.hbox(8)
	for actor in Trade.ACTORS:
		var tab := UI.button(("● " if actor == _npc_actor else "") + str(Trade.ACTORS[actor]), _npc_pick.bind(actor))
		tab.set_meta("npc_contact", actor)
		tabs.add_child(UI.expand(tab))
	body.add_child(tabs)
	var content := UI.vbox(10)
	var view := Npc.view(run, _npc_actor)
	var person := Trade.contact(run, _npc_actor)
	content.add_child(UI.label("%s · 信任 %+d · 人情 %d" % [str(view.get("name", Trade.ACTORS[_npc_actor])), int(person.trust), int(person.favors)], 20, UI.GOLD))
	var stock := UI.para("自主周转库存：" + Data.describe_items(view.get("stock", {})), 17)
	stock.name = "NpcStockSummary"
	content.add_child(stock)
	content.add_child(UI.para("这是对方用于生活和自主行动的物资；现货报价、赊欠和已约回礼使用独立契约货盘。", 15, UI.INK_SOFT))
	content.add_child(UI.label("当前目标：" + str(view.get("goal", "等待下一日安排")), 19, UI.GOLD))
	content.add_child(UI.para("决定原因：" + str(view.get("reason", "尚未公开今日决定。")), 16))
	var memory: Dictionary = view.get("memory", {})
	if memory.is_empty():
		content.add_child(UI.para("前世片段：本人尚未觉醒；旧世档案不会直接左右他的决定。", 15, UI.INK_SOFT))
	else:
		var reply: String = {"": "尚未回应", "acknowledge": "你承认似曾相识", "compensate": "你用今世行动回应", "dismiss": "你只当作旧梦"}.get(str(memory.get("response", "")), "已回应")
		content.add_child(UI.para("已觉醒片段：%s\n%s。" % [str(memory.get("fact", "")), reply], 16, UI.GOLD))
	var plan: Dictionary = view.get("plan", {})
	if plan.is_empty():
		content.add_child(UI.para("下一次决定：%s。" % _crisis_when(int(view.get("next_decision_t", 0))), 17))
	else:
		var pending := str(plan.get("status", "")) == "pending"
		var left := maxi(0, int(plan.get("due_t", 0)) - int(run.t))
		content.add_child(UI.para("%s：%s · %s%s" % ["下一行动" if pending else "今日行动", str(view.get("title", view.get("goal", "自主安排"))), _crisis_when(int(plan.get("due_t", 0))), "（还有 %d小时%02d分）" % [left / 60, left % 60] if pending else " · 已执行"], 17, UI.GOLD))
		var response: String = {"": "尚未介入", "support": "送物支援", "favor": "凭情改托（已预留送货）" if pending else "凭情改托（已送达）", "decline": "由他安排"}.get(str(plan.get("response", "")), "已记录")
		content.add_child(UI.para("本次回应：" + response, 16))
		if not pending:
			content.add_child(UI.para("下一次决定：%s；将根据届时库存、人情和公开局势重新安排。" % _crisis_when(int(view.get("next_decision_t", 0))), 16))
		if not plan.get("reserved", {}).is_empty():
			content.add_child(UI.para("已约送达：%s；从对方周转物资预留，16:00 到家。" % Data.describe_items(plan.reserved), 16, UI.JADE))
	if str(view.get("effect", "")) != "":
		content.add_child(UI.para("按此计划的实际后果：" + str(view.effect), 17, UI.JADE))
	var spoken: Dictionary = NpcDialogue.render(run, _npc_actor)
	if bool(spoken.get("changed", false)): Game.save_game()
	var speech := UI.para(str(view.get("name", Trade.ACTORS[_npc_actor])) + "说：" + str(spoken.get("text", "")), 17)
	speech.name = "NpcDialogueText"
	content.add_child(UI.panel(speech))
	var policy: Dictionary = view.get("policy", {})
	content.add_child(UI.para("新报价政策：%s；%s。\n%s" % ["加收米 %d" % int(policy.get("price_add", 0)) if int(policy.get("price_add", 0)) > 0 else "无额外加价", "允许按信任赊欠" if bool(policy.get("credit_allowed", true)) else "暂停新报价赊欠", str(policy.get("reason", "尚未调整"))], 16))
	content.add_child(UI.para("已展示的当日报价、已签欠账和回礼继续按原约；今日行动可能改变以后新建的报价和明日决定。", 15, UI.INK_SOFT))
	if str(view.get("last_result", "")) != "":
		content.add_child(UI.para("最近结果：" + str(view.last_result), 17, UI.JADE))
	for option in Npc.options(run, _npc_actor):
		var card := UI.vbox(4)
		card.add_child(UI.para(str(option.hint), 16))
		var block := str(option.block)
		if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
		var button := UI.button(str(option.text), _npc_do.bind(_npc_actor, str(option.id), str(view.get("token", ""))), block != "", block)
		button.set_meta("npc_action", str(option.id))
		button.set_meta("npc_actor", _npc_actor)
		card.add_child(button)
		content.add_child(UI.panel(card))
	var trade_button := UI.button("纸鹤往来 · 查看此人的现货与欠账", _npc_trade)
	trade_button.set_meta("npc_trade_entry", true)
	content.add_child(trade_button)
	content.add_child(UI.sep())
	content.add_child(UI.label("自主行动记录 · 最近十二条", 19, UI.GOLD))
	var history: Array = Npc.state(run).get("history", [])
	var found := false
	for k in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[k]
		if str(entry.get("actor", "")) != _npc_actor: continue
		found = true
		content.add_child(UI.para("第 %d 日 %s · %s" % [int(entry.get("day", 0)), _trade_clock(int(entry.get("t", 0))), str(entry.get("result", ""))], 15))
	if not found: content.add_child(UI.para("尚无此人的公开行动记录。", 16))
	var scroll := UI.scroll(content, mini(430, maxi(190, int(get_viewport().get_visible_rect().size.y) - 270)))
	scroll.name = "NpcDetailsScroll"
	body.add_child(scroll)


func _npc_do(actor: String, action: String, token: String) -> void:
	Game.act(func(): return Post.npc_action(Game.run, actor, action, token))


func crisis() -> void:
	Game.act(func(): return Post.crisis_refresh(Game.run))
	UI.open_modal("crisis", "风声与危机 · 查验与筹备", _crisis, true, 850)


func crisis_status(view: Dictionary) -> String:
	var certainty: String = {"unknown": "尚未核实", "real": "已核实 · 属实", "false": "已核实 · 虚惊"}.get(str(view.get("confirmed", "unknown")), "尚未核实")
	if str(view.get("stage", "")) == "impact": return "危机已发生 · " + certainty
	if str(view.get("stage", "")) == "resolved":
		return {"averted": "已结案 · 提前防住", "false_alarm": "已结案 · 虚惊", "endured": "已结案 · 影响结束", "repaired": "已结案 · 补救完成"}.get(str(view.get("outcome", "")), "已结案")
	return "预兆 · " + certainty


func crisis_clock_text(view: Dictionary) -> String:
	if view.is_empty(): return "暂无公开预兆"
	if str(view.get("stage", "")) == "resolved": return crisis_status(view)
	var target := int(view.get("end_t", 0)) if str(view.get("stage", "")) == "impact" else int(view.get("impact_t", 0))
	var left := maxi(0, target - int(_run().get("t", 0)))
	var duration := "%d天%02d:%02d" % [left / 1440, (left % 1440) / 60, left % 60] if left >= 1440 else "%02d:%02d" % [left / 60, left % 60]
	var prefix := "影响结束还有 " if str(view.get("stage", "")) == "impact" else ("预计发生还有 " if str(view.get("confirmed", "")) == "real" else "可能发生还有 ")
	return prefix + duration


func _crisis_when(t: int) -> String:
	return "第 %d 日 %s" % [t / 1440 + 1, _trade_clock(t)]


func _crisis(body: VBoxContainer) -> void:
	var run := _run()
	var view := Crisis.view(run)
	var content := UI.vbox(10)
	if view.is_empty():
		content.add_child(UI.para("近日尚无公开预兆。新的风声会出现在宅院上方；断网也照常推进，不需要等人回信。", 18))
	else:
		content.add_child(UI.label(str(view.title) + " · " + crisis_status(view), 20, UI.GOLD))
		content.add_child(UI.para("预兆：%s\n线索来源：%s" % [str(view.sign), str(view.source)], 17))
		content.add_child(UI.para(crisis_clock_text(view), 19, UI.CINNABAR if str(view.stage) == "impact" else UI.GOLD))
		content.add_child(UI.para("预告发生：%s\n若成真的自然恢复：%s" % [_crisis_when(int(view.impact_t)), _crisis_when(int(view.end_t))], 16))
		var evidence := str(view.get("evidence", ""))
		content.add_child(UI.para("已知证据：" + (evidence if evidence != "" else "尚未取得证据，不能确定这则风声是否属实。"), 17, UI.JADE if evidence != "" else UI.INK_SOFT))
		if str(view.get("effect", "")) != "":
			content.add_child(UI.para(str(view.effect), 16))
		var responses := {"": "尚未选择", "prepare": "自行筹备", "aid": "请线人帮忙", "ignore": "本次观望（已放弃后续提前处置机会）", "emergency": "事后补救"}
		content.add_child(UI.para("本场应对：%s%s" % [responses.get(str(view.get("response", "")), "已记录"), " · 防护已完成" if bool(view.get("protected", false)) else ""], 16))
		var work: Dictionary = view.get("work", {})
		if not work.is_empty():
			content.add_child(UI.para("正在执行：%s · 预计 %s 完成。材料已经付出，工作完成才生效。" % [{"investigate": "核实风声", "prepare": "提前处置", "aid": "请线人帮忙", "emergency": "事后补救"}.get(str(work.get("action", "")), "危机事务"), _crisis_when(int(work.end_t))], 17, UI.GOLD))
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
	if history.is_empty(): content.add_child(UI.para("尚无公开危机或实际处置记录。", 16))
	var titles := {"well_freeze": "井口冻裂", "fuel_shortage": "运柴中断", "herb_shortage": "药草挤兑"}
	for k in range(history.size() - 1, maxi(-1, history.size() - 13), -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 · %s · %s：%s" % [int(entry.day), titles.get(str(entry.kind), "风声"), Trade.ACTORS.get(str(entry.actor), "线人"), str(entry.result)], 15))
	var scroll := UI.scroll(content, mini(450, maxi(200, int(get_viewport().get_visible_rect().size.y) - 220)))
	scroll.name = "CrisisDetailsScroll"
	body.add_child(scroll)


func _crisis_do(action: String, token: String) -> void:
	var result = Game.act(func(): return Post.crisis_action(Game.run, action, token))
	if typeof(result) == TYPE_STRING and result == "" and Post.is_busy(Game.run):
		# 劫余录也会暂停宅院时钟；两层都合上，才能让实际工作推进。
		UI.close_modal("crisis")
		UI.close_modal("journal")


func social_trade() -> void:
	# 到期事实即使此前没有打开窗口，也先结算再展示，并走统一存档入口。
	Game.act(func(): return Post.trade_refresh(Game.run))
	UI.open_modal("social_trade", "纸鹤往来 · 交易与欠账", _social_trade, true, 850)


func _trade_pick(actor: String) -> void:
	_trade_actor = actor
	# 不发出 Game.changed；切联系人不改变游戏事实或刷新其他窗口。
	if UI.host != null and UI.host.has_modal("social_trade"):
		UI.host._modals.social_trade._queue()


func _social_trade(body: VBoxContainer) -> void:
	var run := _run()
	var ctx := Trade.context(run)
	body.add_child(UI.para("第 2 日起，每日 08:00–18:00 可在家联系。每人每天一份货；婉拒也会放弃当天机会。", 16))
	var autonomy := UI.button("邻人与商情 · 查看此人的目标与行动", _trade_npc)
	autonomy.set_meta("trade_npc_entry", true)
	body.add_child(autonomy)
	var tabs := UI.hbox(8)
	for actor in ["ning", "zhou", "traveler"]:
		var contact := Trade.contact(run, actor)
		var name_text: String = contact.name
		var tab := UI.button(("● " if actor == _trade_actor else "") + name_text, _trade_pick.bind(actor))
		tab.set_meta("trade_contact", actor)
		tabs.add_child(UI.expand(tab))
	body.add_child(tabs)
	var content := UI.vbox(10)
	var who := Trade.contact(run, _trade_actor)
	content.add_child(UI.label("%s · 信任 %+d · 欠你的人情 %d · 未化解失约 %d（累计 %d）" % [who.name, int(who.trust), int(who.favors), int(who.breaches), int(who.breach_total)], 18, UI.GOLD))
	content.add_child(UI.para("最近人情变化：" + str(who.get("last_change", "尚无人情往来")), 15))
	content.add_child(UI.para("信任影响报价与赊欠资格；人情可换当日现货；失约会抬价，清债后仍需补偿才能化解。", 15))
	var trade_state := Trade.state(run)
	var history: Array = trade_state.get("history", [])
	if str(trade_state.get("last_result", "")) != "":
		var last_actor := str(history.back().get("actor", "")) if not history.is_empty() else ""
		var last_name: String = Trade.ACTORS.get(last_actor, "往来记录")
		content.add_child(UI.para("最近结果：%s · %s" % [last_name, str(trade_state.last_result)], 17, UI.JADE))
	var quoted := Trade.quote(run, _trade_actor)
	if not quoted.is_empty():
		content.add_child(UI.label("第 %d 日的现货" % int(quoted.day), 19, UI.GOLD))
		content.add_child(UI.para("交出：%s\n得到：%s\n报价缘由：%s" % [req_text(run.home, quoted.req), Director.describe(quoted.give), quoted.reason], 17))
	else:
		content.add_child(UI.para("暂时没有可领取的当日报价。", 17))
	var options := Trade.options(run, _trade_actor)
	for option in options:
		var card := UI.vbox(4)
		card.add_child(UI.para(str(option.hint), 16))
		var block := str(option.block)
		if block != "":
			card.add_child(UI.para(block, 15, UI.CINNABAR))
		var token := str(quoted.get("id", ""))
		var button := UI.button(str(option.text), _trade_do.bind(_trade_actor, str(option.id), token), block != "", block)
		button.set_meta("trade_action", str(option.id))
		button.set_meta("trade_actor", _trade_actor)
		card.add_child(button)
		content.add_child(UI.panel(card))
	content.add_child(UI.sep())
	var debt_heading := UI.label("欠账与待收回礼", 19, UI.GOLD)
	debt_heading.name = "TradeDebtHeading"
	content.add_child(debt_heading)
	var debt: Dictionary = ctx.debt
	if debt.is_empty():
		content.add_child(UI.para("没有未清欠账。全局同时只能保留一笔借债。", 16))
	else:
		var debt_name: String = Trade.contact(run, str(debt.actor)).name
		var debt_summary := UI.para("欠 %s：%s\n第 %d 日 18:00 前偿还%s。欠账已定，不随以后的报价改变。" % [debt_name, req_text(run.home, debt.req), int(debt.due_day), "；现已逾期，失约已留痕" if bool(debt.overdue) else ""], 16, UI.CINNABAR if bool(debt.overdue) else UI.INK)
		debt_summary.name = "TradeDebtSummary"
		content.add_child(debt_summary)
	if ctx.aid.is_empty():
		content.add_child(UI.para("没有待收回礼。", 16))
	for aid in ctx.aid:
		content.add_child(UI.para("%s · 第 %d 日 %s 回礼：%s（已送出 %s）" % [Trade.contact(run, str(aid.actor)).name, int(aid.due_day), _trade_clock(int(aid.due_t)), Director.describe(aid.give), Director.describe(aid.req)], 16))
	content.add_child(UI.sep())
	content.add_child(UI.label("往来记录 · 最近十二条", 19, UI.GOLD))
	if history.is_empty():
		content.add_child(UI.para("尚无成交、拒绝或失约。实际选择会记在这里。", 16))
	for k in range(history.size() - 1, maxi(-1, history.size() - 13), -1):
		var entry: Dictionary = history[k]
		content.add_child(UI.para("第 %d 日 %s · %s" % [int(entry.get("t", 0)) / 1440 + 1, _trade_clock(int(entry.get("t", 0))), str(entry.get("result", entry.get("text", "")))], 15))
	var scroll := UI.scroll(content, mini(390, maxi(180, int(get_viewport().get_visible_rect().size.y) - 280)))
	scroll.name = "TradeDetailsScroll"
	body.add_child(scroll)


func _trade_clock(t: int) -> String:
	var minute := (t + 360) % 1440
	return "%02d:%02d" % [minute / 60, minute % 60]


func _trade_do(actor: String, action: String, quote_id: String) -> void:
	Game.act(func(): return Post.trade_action(Game.run, actor, action, quote_id))


func cycle_inquiry() -> void:
	if Game.run.is_empty(): return
	Game.act(func(): return Post.trade_refresh(Game.run))
	for key in ["journal", "past_lives"]: UI.close_modal(key)
	UI.open_modal("cycle_inquiry", "轮回调查 · 旧诺与今证", _cycle_inquiry, true, 860)


func _cycle_inquiry(body: VBoxContainer) -> void:
	var run := _run()
	var view := Cycle.view(run)
	var content := UI.vbox(10)
	content.add_child(UI.para(str(view.get("summary", "")), 17))
	content.add_child(UI.para("旧世的承诺和记忆只能提供方向；查访、核账与新的约定，都要在今世实际完成。宅院内即可调查，开始付出材料与精力，完工后才得证或生效。", 15, UI.INK_SOFT))
	var work: Dictionary = view.get("work", {})
	if not work.is_empty():
		var remaining := maxi(0, int(work.get("end_t", 0)) - int(run.get("t", 0)))
		content.add_child(UI.para("正在进行：%s · 还需 %d 分钟。中断不退已付材料，尚未完成的工作不算兑现。" % [str(work.get("label", "轮回调查")), remaining], 17, UI.GOLD))
	for entry in view.get("cases", []):
		if not entry is Dictionary: continue
		var card := UI.vbox(6)
		card.set_meta("cycle_case", str(entry.get("id", "")))
		card.set_meta("cycle_stage", str(entry.get("stage", "")))
		card.add_child(UI.label(str(entry.get("title", "旧世来信")) + " · " + str(entry.get("stage_label", entry.get("stage", ""))), 20, UI.GOLD))
		var source := str(entry.get("source_label", ""))
		if source != "": card.add_child(UI.para("旧世来源：" + source, 16, UI.JADE))
		if str(entry.get("stage", "")) == "sealed":
			card.add_child(UI.para("这是玩家带入的旧梦，尚未在今世查访，也不代表邻人已经觉醒。", 15, UI.INK_SOFT))
		for field in ["publish_text", "clue", "evidence_text"]:
			var line := str(entry.get(field, ""))
			if line != "": card.add_child(UI.para(line, 16, UI.JADE if field == "evidence_text" else UI.INK))
		var deadline := str(entry.get("deadline_text", ""))
		if deadline != "": card.add_child(UI.para("期限：" + deadline, 16, UI.CINNABAR))
		var result := str(entry.get("last_result", ""))
		if result != "": card.add_child(UI.para("本世结果：" + result, 16, UI.JADE))
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
	content.add_child(UI.label("轮回调查 · 本世记录", 19, UI.GOLD))
	var history: Array = view.get("history", [])
	if history.is_empty(): content.add_child(UI.para("尚未进行今世调查。旧梦出现后，可先查访再决定是否续约、补偿或重新救助。", 16))
	for k in range(history.size() - 1, -1, -1):
		var entry = history[k]
		if entry is Dictionary:
			content.add_child(UI.para("第 %d 日 · %s" % [int(entry.get("day", 0)), str(entry.get("result", ""))], 15))
	var scroll := UI.scroll(content, mini(450, maxi(210, int(get_viewport().get_visible_rect().size.y) - 210)))
	scroll.name = "CycleInquiryScroll"
	body.add_child(scroll)


func _cycle_do(case_id: String, action: String, token: String, life: String) -> void:
	if Game.run.is_empty() or str(Past.state(Game.run).get("id", "")) != life: return
	var result = Game.act(func(): return Post.cycle_action(Game.run, case_id, action, token))
	if typeof(result) == TYPE_STRING and result == "" and Post.is_busy(Game.run):
		for key in ["cycle_inquiry", "journal", "past_lives"]: UI.close_modal(key)


func past_lives() -> void:
	UI.open_modal("past_lives", "前世记忆 · 生死簿留痕", _past_lives, true, 820)


func _past_lives(body: VBoxContainer) -> void:
	var run := _run()
	var p := Past.state(run)
	var book := Past.book(Game.meta)
	body.add_child(UI.para("已封存 %d 世，保留最近八世的人物往事。翻回昨日仍属于同一世，未曾发生的事不会成为记忆。" % int(book.count), 17))
	if Past.daily(run):
		body.add_child(UI.para("每日一局不唤醒或归档人物前世记忆，保持同日条件一致。", 16, UI.GOLD))
	var content := UI.vbox(10)
	var cycle_entry := UI.button("轮回调查 · 查访旧诺、失约与救助", cycle_inquiry)
	cycle_entry.set_meta("cycle_entry", "past_lives")
	content.add_child(cycle_entry)
	content.add_child(UI.label("本世带入的身份经验", 21, UI.GOLD))
	var sources := _identity_inheritance(Identity.view(run).get("inheritance", []))
	content.add_child(UI.para(sources if sources != "" else "本世尚未带入符合条件的身份经验。只有真实发生并归档的经历才会解锁新解法。", 16))
	var identity_entry := UI.button("身份与旧世 · 查看经验能解开的选择", identity_paths)
	identity_entry.set_meta("identity_entry", "past_lives")
	content.add_child(identity_entry)
	content.add_child(UI.label("本世觉醒", 21, UI.GOLD))
	var awakened := Past.public_memories(run)
	if awakened.is_empty():
		content.add_child(UI.para("本世尚无人觉醒。片段并非每世出现，也不需要等待 AI；日间往来时偶尔会浮现。", 16))
	for fragment in awakened:
		var when := "上一世" if int(fragment.age) == 1 else "%d 世前" % int(fragment.age)
		content.add_child(UI.para("%s · %s：%s" % [Past.ACTORS[fragment.actor], when, fragment.fact], 17))
		var response: String = {"": "尚未回应", "acknowledge": "承认似曾相识", "compensate": "用今世行动回应", "dismiss": "只当作旧梦"}.get(fragment.response, "已回应")
		content.add_child(UI.para("你的回应：" + response, 15, UI.INK_SOFT))
	content.add_child(UI.sep())
	content.add_child(UI.label("本世留痕 · 结算后归档", 21, UI.GOLD))
	if p.trace.is_empty(): content.add_child(UI.para("尚无可辨认的人物往事。给药、拒绝、药账处置与真实物资往来会留下事实。", 16))
	for fact in p.trace:
		content.add_child(UI.para("%s · 第 %d 日：%s" % [Past.ACTORS[fact.actor], int(fact.day), fact.fact], 16))
	content.add_child(UI.sep())
	content.add_child(UI.label("旧世档案", 21, UI.GOLD))
	if book.lives.is_empty(): content.add_child(UI.para("还没有封存的旧世；从启用本机制后真实经历的这一世开始记。", 16))
	for k in range(book.lives.size() - 1, -1, -1):
		var life: Dictionary = book.lives[k]
		content.add_child(UI.label("第 %d 世留痕" % int(life.life), 18, UI.GOLD))
		if life.facts.is_empty(): content.add_child(UI.para("这一世没有留下可辨认的人物往事。", 16))
		for fact in life.facts:
			content.add_child(UI.para("%s：%s" % [Past.ACTORS[fact.actor], fact.fact], 16))
	body.add_child(UI.scroll(content, mini(440, maxi(180, int(get_viewport().get_visible_rect().size.y) - 230))))


func neighbor() -> void:
	UI.open_modal("neighbor", "邻里事务 · 隔墙求药", _neighbor, true, 740)


func _neighbor(body: VBoxContainer) -> void:
	var run := _run()
	var q := Neighbor.state(run)
	body.add_child(UI.para(Neighbor.summary(run), 19))
	if q.stage == "fetch":
		body.add_child(UI.para("药柜中的药会贴身收好，不占背囊，被追赶也不丢。来回赶路也计入期限。", 16))
		if not q.pry:
			var can_prepare: bool = Neighbor.ready_for_home(run) and run.pending_event == "" and Inv.count(run.home, "wood") >= 1 and int(run.t) < Neighbor.DEADLINE
			body.add_child(UI.button("准备随身撬杆 · 木料 1", func(): _act(func(): return Neighbor.prepare_pry(Game.run)), not can_prepare))
		else:
			body.add_child(UI.label("随身撬杆已备好；开柜后损坏。", 17))
	var target := "pharmacy_ruin" if q.stage == "fetch" else ("mortuary" if q.stage == "investigate" else "")
	if target != "" and Neighbor.ready_for_home(run):
		var block := Post.can_act(run, 10)
		if block == "":
			block = Explore.point_block(run, target)
		body.add_child(UI.button("出门去" + Data.table("map_points")[target].name, func(): _neighbor_depart(target), block != "", block))
	if q.history.is_empty():
		body.add_child(UI.para("还没有选择记录。第 2 日早间开始，留意邻人的求助。", 16))
	else:
		var history := UI.vbox(8)
		for entry in q.history:
			var minute := (int(entry.t) + 360) % 1440
			history.add_child(UI.para("第 %d 日 %02d:%02d · %s" % [int(entry.t) / 1440 + 1, minute / 60, minute % 60, entry.result], 16))
		body.add_child(UI.scroll(history, mini(280, q.history.size() * 60 + 12)))


func _neighbor_depart(target: String) -> void:
	UI.close_modal("neighbor")
	UI.close_modal("journal")
	_act(func(): return Post.act_explore(Game.run, target))


# ---------- 吃喝用药 ----------

var _inventory_filter := "全部"

func inventory() -> void:
	if Floors.current(_run()) == "guest_zhou":
		Game.toast.emit("先回宅院再使用家中存货。")
		return
	_inventory_filter = "全部"
	UI.open_modal("inventory", "家中存货", _inventory, true, 900)


func _inventory(body: VBoxContainer) -> void:
	var run := _run()
	var ledger := UI.vbox(12)
	ledger.add_child(_inventory_label("物资簿  ·  家中收藏", 16, Color("#765044")))
	var categories: Array[String] = ["全部"]
	var all_ids: Array = []
	for cat in CAT_ORDER:
		var ids := Inv.ids_in_cat(run.home, cat)
		if not ids.is_empty():
			categories.append(cat)
			all_ids.append_array(ids)
	if not _inventory_filter in categories:
		_inventory_filter = "全部"
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	for cat in categories:
		var tab := UI.button(cat, func():
			_inventory_filter = cat
			UI.clear(body)
			_inventory(body))
		var chosen: bool = cat == _inventory_filter
		tab.add_theme_stylebox_override("normal", UI._box(Color("#8d4035") if chosen else Color("#e6d8bf"), Color("#9a7962"), 1, 0, 12, 5))
		tab.add_theme_stylebox_override("hover", UI._box(Color("#a25446"), Color("#843e33"), 1, 0, 12, 5))
		tab.add_theme_color_override("font_color", Color("#f2e6cd") if chosen else Color("#44352d"))
		tab.add_theme_color_override("font_hover_color", Color("#fff0d6"))
		tab.button_pressed = chosen
		tabs.add_child(tab)
	ledger.add_child(tabs)
	var grid := UI.grid(4, 9, 9)
	var visible_ids: Array = all_ids if _inventory_filter == "全部" else Inv.ids_in_cat(run.home, _inventory_filter)
	for id in visible_ids:
		grid.add_child(_item_card(run, id))
	ledger.add_child(grid)
	if all_ids.is_empty():
		ledger.add_child(_inventory_label("家中暂无存货。", 17, Color("#675b4d")))
	var paper := PanelContainer.new()
	var paper_style := StyleBoxTexture.new()
	paper_style.texture = INVENTORY_PAPER
	paper_style.content_margin_left = 14
	paper_style.content_margin_right = 14
	paper_style.content_margin_top = 12
	paper_style.content_margin_bottom = 12
	paper.add_theme_stylebox_override("panel", paper_style)
	paper.add_child(ledger)
	body.add_child(UI.scroll(paper, mini(470, maxi(180, int(get_viewport().get_visible_rect().size.y) - 230))))


## 在深色弹窗主题下也保持纸上的墨色，不继承夜色主题的浅色文字与阴影。
func _inventory_label(text: String, size: int, ink: Color, wrap := false) -> Label:
	var label := UI.label(text, size, ink, wrap)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return label


## 物资格仍保留名称、数量、效果和原来的直接使用按钮。
func _item_card(run: Dictionary, id: String) -> Control:
	var it := Data.item(id)
	var n := Inv.count(run.home, id)
	var v := UI.vbox(4)
	UI.expand(v)
	var image_row := CenterContainer.new()
	image_row.custom_minimum_size.y = 72
	if INVENTORY_ART.has(id):
		var illustration := TextureRect.new()
		illustration.texture = INVENTORY_ART[id]
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.custom_minimum_size = Vector2(72, 72)
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image_row.add_child(illustration)
	else:
		image_row.add_child(UI.icon(id, 72))
	v.add_child(image_row)
	var title := UI.hbox(4)
	title.add_child(_inventory_label(it.name, 17, Color("#302921")))
	title.add_child(UI.spacer())
	title.add_child(_inventory_label("×%d" % n, 15, Color("#765b49")))
	v.add_child(title)
	var fx: Dictionary = it.get("eat", it.get("use", {}))
	v.add_child(_inventory_label("%s · %s" % [it.cat, fx_text(fx)] if not fx.is_empty() else it.cat, 13, Color("#675b4d"), true))
	if not fx.is_empty():
		var verb := "喝" if id == "water" else ("吃" if it.has("eat") else "用")
		var action := UI.button(verb, func(): _use(id))
		action.add_theme_stylebox_override("normal", UI._box(Color("#e3d1b6"), Color("#9a7962"), 1, 1, 8, 3))
		action.add_theme_stylebox_override("hover", UI._box(Color("#f0e2cc"), Color("#98483a"), 1, 1, 8, 3))
		action.add_theme_stylebox_override("pressed", UI._box(Color("#d3b99c"), Color("#843e33"), 1, 1, 8, 3))
		action.add_theme_color_override("font_color", Color("#44352d"))
		action.add_theme_color_override("font_hover_color", Color("#8d4035"))
		action.add_theme_color_override("font_pressed_color", Color("#44352d"))
		v.add_child(action)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI._box(Color(0.94, 0.90, 0.82, 0.68), Color("#ab9b80"), 1, 0, 9, 8))
	card.add_child(v)
	card.tooltip_text = it.desc
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	return UI.fixed_width(card, 190)


func _use(id: String) -> void:
	var res = Game.act(func(): return Post.use_item(Game.run, id))
	if typeof(res) == TYPE_STRING and res == "":
		Sfx.use_item(id)


# ---------- 灶房 ----------

func cook() -> void:
	UI.open_modal("cook", "灶房", _cook, true, 860)


func _cook(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("柴 %d 捆 · 木炭 %d 筐（没柴时一筐炭顶两捆）　庖厨 %d 级　每锅另加 %d 份" % [
		Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal"), State.prof_level(run, "cook"),
		Post.cook_servings(run, "congee") - int(Data.table("recipes").congee.out)], 16))
	var recipes: Dictionary = Data.table("recipes")
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var h := UI.hbox(10)
		h.add_child(UI.icon(rid, 44))
		var info := UI.vbox(2)
		UI.expand(info)
		var dish := Data.item(rid)
		info.add_child(UI.label("%s　得 %d 份　%s" % [r.name, Post.cook_servings(run, rid), fx_text(dish.get("eat", {}))], 19))
		info.add_child(UI.para("用料：%s　柴火 %d" % [req_text(run.home, Post.recipe_inputs(run, rid)), r.fuel], 15))
		h.add_child(info)
		var block := Post.recipe_block(run, rid)
		if block == "":
			block = Post.can_act(run)
		_action(h, "下锅（一个时辰）", func(): _start("cook", func(): return Post.act_cook(Game.run, rid)), block)
		body.add_child(h)


# ---------- 菜畦 ----------

func garden() -> void:
	UI.open_modal("garden", "菜畦", _garden, true, 820)


func _garden(body: VBoxContainer) -> void:
	var run := _run()
	var crops: Dictionary = Data.table("crops")
	body.add_child(UI.para("下种随手就行。一天之内浇过水的作物才长；打理一次要四十五分钟、一瓢清水，熟了的顺手收。", 16))
	for k in run.plots.size():
		var plot: Dictionary = run.plots[k]
		if not Post.plot_on_floor(run, plot):
			continue
		var h := UI.hbox(10)
		var plot_name := "第 %d 畦" % (k + 1)
		if plot.has("pot"):
			var pot := Home.find(run, int(plot.pot))
			plot_name = "花盆 #%d" % int(plot.pot)
			if not pot.is_empty():
				plot_name += "（%.1f, %.1f）" % [float(pot.x), float(pot.z)]
		h.add_child(UI.label(plot_name, 18, UI.INK_SOFT))
		if plot.crop == "":
			h.add_child(UI.label("空着", 18, UI.INK_FAINT))
			h.add_child(UI.spacer())
			for cid in crops:
				var n := Inv.count(run.home, crops[cid].seed)
				if n > 0:
					h.add_child(UI.button("种%s（%d）" % [crops[cid].name, n], func(): _act(func(): return Post.plant(Game.run, k, cid))))
		else:
			var c: Dictionary = crops[plot.crop]
			h.add_child(UI.label(c.name, 18))
			h.add_child(UI.bar(minf(float(plot.days), float(c.days)), float(c.days), UI.JADE, 160))
			var ripe := Post.crop_ripe(plot)
			h.add_child(UI.label("可收" if ripe else "%.1f / %d 日" % [float(plot.days), int(c.days)], 16, UI.JADE if ripe else UI.INK_SOFT))
			var dry := Post.plot_dry(run, plot)
			h.add_child(UI.tag("缺水" if dry else "已浇水", UI.CINNABAR if dry else UI.DAI))
		body.add_child(h)
	body.add_child(UI.sep())
	var block := Post.can_act(run)
	body.add_child(UI.seal_button("浇水收成（四十五分钟）", func(): _start("garden", func(): return Post.act_garden(Game.run)), block != "", block))


# ---------- 营造 ----------

func build() -> void:
	UI.open_modal("build", "营造守具", _build, true, 900)


func _build(body: VBoxContainer) -> void:
	var run := _run()
	var v := UI.vbox(6)
	v.add_child(UI.label("守具", 20, UI.CINNABAR))
	var devices: Dictionary = Data.table("devices").devices
	for did in devices:
		var d: Dictionary = devices[did]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var lasts := "一直管用" if int(d.dur) >= 99 else "管 %d 夜" % int(d.dur)
		info.add_child(UI.label("%s　守力 %d · %s　%s" % [d.name, d.power, lasts, "（一个半时辰）" if int(d.time) > 0 else "（随手布下）"], 18))
		info.add_child(UI.para("%s　用料：%s" % [d.desc, req_text(run.home, d.cost)], 15))
		h.add_child(info)
		var block := Post.device_block(run, did)
		if int(d.time) > 0:
			_action(h, "动手做", func(): _start("build", func(): return Post.act_build(Game.run, did)), block)
		else:
			_action(h, "布置", func(): _act(func(): return Post.act_build(Game.run, did)), block)
		v.add_child(h)
	# 加工：画符要先学会，其余几条谁都能做。不会的也列出来（标"还不会"），
	# 省得玩家猜有没有这回事——藏着的选项等于不存在的选项。
	v.add_child(UI.sep())
	v.add_child(UI.label("加工", 20, UI.CINNABAR))
	var crafts: Dictionary = Data.table("devices").crafts
	for cid in crafts:
		var c: Dictionary = crafts[cid]
		var h := UI.hbox(10)
		var info := UI.vbox(3)
		UI.expand(info)
		info.add_child(UI.para("%s：%s\n用料：%s　产出：%s" % [c.name, c.desc, req_text(run.home, c["in"]), Data.describe_items(c.out)], 16, UI.INK))
		var block := Post.craft_block(run, cid)
		if block != "": info.add_child(UI.para(block, 15, UI.CINNABAR))
		h.add_child(info)
		var craft_button := UI.button("%s（60 分钟 · 精力 6）" % str(c.get("verb", "做")), func(): _start("build", func(): return Post.act_craft(Game.run, cid)), block != "", block)
		craft_button.set_meta("identity_craft", str(cid))
		h.add_child(craft_button)
		v.add_child(h)
	v.add_child(UI.sep())
	v.add_child(UI.label("修缮　用木料 1 根（有 %d），没木料时拆 2 捆柴顶上（有 %d），耐久 +%d" % [
		Inv.count(run.home, "wood"), Inv.count(run.home, "firewood"), 35 + 5 * State.prof_level(run, "build")], 20, UI.CINNABAR))
	for part in [["door", "门"], ["window", "窗"], ["wall", "墙"]]:
		var h := UI.hbox(10)
		var p: Dictionary = run[part[0]]
		h.add_child(UI.fixed_width(UI.label(part[1], 18), 40))
		h.add_child(UI.bar(int(p.cur), int(p.max), UI.GOLD))
		h.add_child(UI.label("%d / %d" % [p.cur, p.max], 16, UI.INK_SOFT))
		var key: String = part[0]
		var block := "完好" if int(p.cur) >= int(p.max) else Post.can_act(run)
		_action(h, "修（一个时辰）", func(): _start("build", func(): return Post.act_repair(Game.run, key)), block)
		v.add_child(h)
	body.add_child(UI.scroll(v, 480))


# ---------- 读书 ----------

func read() -> void:
	UI.open_modal("read", "读书", _read, true, 760)


func _read(body: VBoxContainer) -> void:
	var run := _run()
	var books := Inv.ids_in_cat(run.home, "书")
	if books.is_empty():
		body.add_child(UI.para("家里一本书也没有。县学里兴许能翻到。", 17))
	for bid in books:
		var h := UI.hbox(10)
		var it := Data.item(bid)
		var done: bool = bid in run.read
		h.add_child(UI.expand(UI.para("%s　%s" % [it.name, it.desc], 17, UI.INK_FAINT if done else UI.INK)))
		var block := "读熟了" if done else Post.can_act(run)
		_action(h, "读（两个时辰）", func(): _start("read", func(): return Post.act_read(Game.run, bid)), block)
		body.add_child(h)


# ---------- 今日差事 ----------

## 差事的类目配色：跟命相关的偏朱砂，往后受用的偏黛青
const AGENDA_TAGS := {"柴": Color("#a0522d"), "水": Color("#3f6f8f"), "粮": Color("#5d7d4f"), "守": Color("#9b2c2c"),
	"暖": Color("#c06a2a"), "探": Color("#6b5b95"), "艺": Color("#4a6670"), "神": Color("#7a6a3a"),
	"人": Color("#8a5a6a"), "材": Color("#6d5c4a"), "工": Color("#2f5f5a")}


func agenda() -> void:
	if _run().is_empty() or str(_run().get("phase", "")) != "post":
		return
	Post.ensure_agenda(_run())
	UI.open_modal("agenda", "今日差事", _agenda, true, 920)


func _agenda(body: VBoxContainer) -> void:
	var run := _run()
	var s := Agenda.summary(run)
	body.add_child(UI.para("单子上还有 %s 小时的事；到 22:00 只剩 %s 小时。" % [
		Agenda.hours_text(int(s.need)), Agenda.hours_text(int(s.left))], 19, UI.INK))
	if int(s.over) > 0:
		body.add_child(UI.para("做不完——得放下约 %s 小时的事。先挑要命的，再挑往后受用的；没做的明早就换一批。" % Agenda.hours_text(int(s.over)), 16, UI.CINNABAR))
	elif int(s.open) > 0:
		body.add_child(UI.para("剩下的事来得及做完。", 16, UI.JADE))
	else:
		body.add_child(UI.para("今天的差事都办完了。", 16, UI.JADE))
	var list := UI.vbox(8)
	list.name = "AgendaList"
	for row in Agenda.rows(run):
		list.add_child(_agenda_row(run, row))
	body.add_child(UI.scroll(list, mini(470, maxi(220, int(get_viewport().get_visible_rect().size.y) - 250))))


func _agenda_row(run: Dictionary, row: Dictionary) -> Control:
	var h := UI.hbox(10)
	h.set_meta("agenda_id", str(row.id))
	var st := str(row.status)
	var faded := st in ["done", "late", "spent"]
	h.add_child(UI.tag(str(row.tag), AGENDA_TAGS.get(str(row.tag), UI.INK_SOFT) if not faded else UI.INK_FAINT))
	var info := UI.vbox(2)
	UI.expand(info)
	var title := "%s　%s" % [row.name, Agenda.span_text(int(row.minutes))]
	if int(row.energy) > 0:
		title += " · 精力 %d" % int(row.energy)
	if str(row.progress) != "":
		title += "　进度 %s" % row.progress
	if str(row.deadline) != "":
		title += "　%s" % row.deadline
	info.add_child(UI.label(title, 18, UI.INK_FAINT if faded else UI.INK))
	var gets := str(row.effect)
	if str(row.cost) != "":
		gets = ("耗 %s　→　%s" % [row.cost, gets]) if gets != "" else "耗 %s" % row.cost
	if gets != "":
		info.add_child(UI.para(gets, 15, UI.INK_FAINT if faded else UI.JADE))
	info.add_child(UI.para(str(row.why), 15, UI.INK_FAINT if faded else UI.INK_SOFT))
	h.add_child(info)
	match st:
		"done":
			h.add_child(UI.label("✓ 做过了", 16, UI.JADE))
		"busy":
			h.add_child(UI.label("正在做", 16, UI.GOLD))
		"late":
			h.add_child(UI.label("过了时辰", 16, UI.INK_FAINT))
		"spent":
			h.add_child(UI.label("已经用尽", 16, UI.INK_FAINT))
		_:
			var block := str(row.block)
			if block == "":
				block = Post.can_act(run, int(row.energy))
			var idx := int(row.idx)
			_action(h, "去做", func(): _agenda_go(idx), block)
	return h


## 走到地方再做：交给宅院界面（它知道人站在哪、物件在哪）。
func _agenda_go(idx: int) -> void:
	UI.close_modal("agenda")
	var host: Node = get_tree().current_scene
	var screen: Node = host.get("_screen") if host != null else null
	if screen != null and screen.has_method("agenda_do"):
		screen.agenda_do(idx)
	elif str(Agenda.item(_run(), idx).get("kind", "")) == "chore":
		_act(func(): return Post.act_chore(Game.run, idx))


# ---------- 外出 ----------

func explore_pick() -> void:
	UI.open_modal("explore_pick", "出门去哪？", _explore_pick, true, 900)


func _explore_pick(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("去程、返程各 60 分钟；翻找会增加阳气外泄，满 100 会被尸群发现。各地特别行动的代价以现场提示为准；21:00 后处理完当前事务即强制返程。", 16))
	var available := maxi(0, Post.CURFEW_AT - Post.day_minute(run) - int(Post.ACTIONS.travel[1]))
	body.add_child(UI.para("预计完整探索含行走、机关和翻找，不含往返；实际随路线与事件变化。现在出发，抵达后距21:00约 %d 分钟；返程另需60分钟。" % available, 15, UI.GOLD))
	var v := UI.vbox(8)
	var visible := Explore.visible_points(run)
	if not "taoist_temple" in visible: visible.append("taoist_temple")
	for pid in visible:
		var p: Dictionary = Data.table("map_points")[pid]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var head := UI.hbox(8)
		head.add_child(UI.label(p.name, 20))
		head.add_child(UI.label("险 " + "★".repeat(int(p.danger)) + "☆".repeat(4 - int(p.danger)), 16, UI.CINNABAR))
		var warn := Explore.fall_warning(run, pid)
		if warn != "":
			head.add_child(UI.tag(warn, UI.CINNABAR))
		if int(run.points.get(pid, {}).get("visits", 0)) == 0:
			head.add_child(UI.tag("未到访", UI.DAI))
		info.add_child(head)
		info.add_child(UI.para(p.desc, 15))
		var investigation_only := int(run.points.get(pid, {}).get("looted_until", 0)) > int(run.pday) and not Mainline.objective(run, pid).is_empty()
		if not investigation_only:
			var journey: Dictionary = SiteJourney.profile(str(pid))
			var grades := {"easy": "简单", "medium": "中等", "hard": "困难"}
			info.add_child(UI.para("%s · 完整现场约%s（游戏时间）" % [grades.get(str(journey.get("grade", "")), "探索"), str(journey.get("estimated", ""))], 15, UI.GOLD))
		var site_tip := "当前仅开放本世调查，普通物资尚未恢复。" if investigation_only else "现场特色：" + Explore.site_brief(str(pid)) + " 先查找两处线索，解开机关进入后区。"
		info.add_child(UI.para(site_tip, 15, UI.GOLD))
		if not investigation_only:
			var possible := []
			for entry in p.loot:
				possible.append(str(Data.item(str(entry[0])).name))
			info.add_child(UI.para("可能找到：" + "、".join(possible) + "；实际收获随机。", 15, UI.INK_SOFT))
		var main_objective := Mainline.objective(run, pid)
		if not main_objective.is_empty():
			info.add_child(UI.para("本世调查：" + str(main_objective.name) + " · " + str(main_objective.get("hint", "")), 15, UI.GOLD))
		h.add_child(info)
		var block := "尚未找到进山路线，可先在尸劫来历中调查义庄。" if not pid in Explore.visible_points(run) else Explore.point_block(run, pid)
		if block == "":
			block = Post.can_act(run, 10)
		if block == "" and Post.day_minute(run) + 60 >= Post.CURFEW_AT:
			block = "天快黑了"
		_action(h, "出发", func(): _go_explore(pid), block)
		h.get_child(h.get_child_count() - 1).set_meta("explore_depart", pid)
		v.add_child(h)
	body.add_child(UI.scroll(v, 460))


func _go_explore(pid: String) -> void:
	UI.close_modal("explore_pick")
	_act(func(): return Post.act_explore(Game.run, pid))


# ---------- 事件 ----------

func event() -> void:
	var id: String = _run().pending_event
	UI.open_modal("event", Events.entry(_run()).get("title", "邻里来信"), _event, false, 720)


func _event(body: VBoxContainer) -> void:
	var run := _run()
	if run.pending_event == "":
		body.add_child(UI.para(run.event_result, 19, UI.INK))
		var row := UI.hbox()
		row.add_child(UI.spacer())
		row.add_child(UI.seal_button("知道了", func(): UI.close_modal("event")))
		body.add_child(row)
		return
	var e: Dictionary = Events.entry(run)
	if e.get("story", "") == "neighbor" and Neighbor.state(run).resolution != "":
		body.add_child(UI.para("前情：" + Neighbor.resolution_text(Neighbor.state(run)), 16, UI.GOLD))
	body.add_child(UI.para(e.text, 19, UI.INK))
	body.add_child(UI.sep())
	for k in e.choices.size():
		var c: Dictionary = e.choices[k]
		var ok := Events.choice_ok(run, c)
		var text: String = c.text
		if not c.get("req", {}).is_empty():
			text += "　［需：%s］" % _event_req_text(c.req)
		var b := UI.button(text, func(): _act(func(): return Events.choose(Game.run, k)), not ok, "" if ok else "东西不够")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)
		if c.get("hint", "") != "":
			body.add_child(UI.para(c.hint, 15, UI.INK_SOFT))
		if str(run.pending_event).begins_with("world:"):
			body.add_child(UI.para(Director.effect_hint(c), 15, UI.INK_SOFT))
		if c.get("pry", false) and not Neighbor.state(run).pry:
			body.add_child(UI.para("未准备撬杆：须在家中打开劫余录 → 邻里事务，用木料 1 制作。", 15, UI.CINNABAR))


static func _event_req_text(req: Dictionary) -> String:
	var parts := []
	for k in req:
		match k:
			"any_food":
				parts.append("吃食 %d 份" % req[k])
			"any_grain":
				parts.append("粮 %d 斗" % req[k])
			"silver":
				parts.append("银 %d 两" % (int(req[k]) / 1000))
			_:
				parts.append("%s %d" % [Data.item_name(k), req[k]])
	return "、".join(parts)


# ---------- 守夜方针（21:00） ----------

func night_plan() -> void:
	UI.open_modal("night_plan", "第 %d 夜 · 定守夜方针" % int(_run().pday), _night_plan, false, 980)


func _night_plan(body: VBoxContainer) -> void:
	var run := _run()
	if not run.plan_due:
		UI.close_modal("night_plan")
		return
	var wave := Defense.wave_for_run(run, int(run.pday))
	var total := Defense._count(wave)
	var mods := Defense.mod_names(wave)
	body.add_child(UI.para("更鼓敲过二更。街那头铜锣响了，门缝里透进一片火把的光——今夜要来 %d 只%s，分三轮撞门、窗、院墙。" % [
		total, ("（%s）" % mods) if mods != "" else ""], 18, UI.INK))
	body.add_child(UI.para("每漏进来一只，那一面就掉 %d 点耐久。选个方针：想安稳过日子就选前三档，交给它自己守；想自己拿主意就选「亲自调度」。" % Defense.leak_damage(int(run.pday)), 16))
	body.add_child(UI.sep())
	var row := UI.hbox(10)
	for opt in Post.policy_options(run):
		var id: String = opt[0]
		var v := UI.vbox(5)
		UI.expand(v)
		v.add_child(UI.heading(opt[1], 21))
		v.add_child(UI.para(opt[2], 14))
		v.add_child(UI.label("亲守：%s" % Defense.surface_name(str(opt[3])), 15, UI.INK_SOFT))
		var leak := int(opt[4])
		v.add_child(UI.label(("整夜约漏 %d 只" % leak) if leak > 0 else "整夜挡得住", 16, UI.CINNABAR if leak > 0 else UI.JADE))
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(gap)
		v.add_child(UI.seal_button(opt[1], func(): _pick_policy(id)))
		var card := UI.panel(v, UI.PAPER)
		UI.expand(card)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(card)
	body.add_child(row)


func _pick_policy(id: String) -> void:
	var res = Game.act(func(): return Post.choose_policy(Game.run, id))
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("night_plan")
		Sfx.play("bangzi", -6.0)


# ---------- 夜战面板（轮间） ----------

func night_panel() -> void:
	UI.open_modal("night", "夜战 · 第 %d 轮" % (int(_run().night.get("round", 0)) + 1), _night_panel, true, 940)


func _night_panel(body: VBoxContainer) -> void:
	var run := _run()
	var night: Dictionary = run.get("night", {})
	if night.is_empty() or bool(night.get("done", false)):
		UI.close_modal("night")
		return
	var wave: Dictionary = night.wave
	var idx := int(night.round)
	var pv := Defense.preview_round(run, wave, idx)
	body.add_child(UI.para("第 %d / %d 轮。这一轮要来 %d 只。离下一轮还有 %d 分钟——只够做一件事。" % [
		idx + 1, int(night.rounds), int(pv.surfaces.gate.count) + int(pv.surfaces.window.count) + int(pv.surfaces.wall.count),
		maxi(0, Defense.round_minute(idx) - Post.day_minute(run))], 17))
	body.add_child(UI.para("院门%s。开着的时候，这一轮本该撞门的那些会直接走进来，砸菜畦、米袋和家具；关着就只能挨撞。" % (
		"开着" if bool(run.door_open) else "闩着"), 15, UI.CINNABAR if bool(run.door_open) else UI.INK_SOFT))
	body.add_child(UI.sep())
	for sid in Defense.SURFACES:
		var s: Dictionary = pv.surfaces[sid]
		var part := Defense.part_of(run, sid)
		var h := UI.hbox(8)
		var name_label := UI.label(Defense.surface_name(sid), 19, UI.CINNABAR if bool(s.broken) else UI.INK)
		h.add_child(UI.fixed_width(name_label, 52))
		h.add_child(UI.bar(int(part.cur), int(part.max), UI.GOLD, 150))
		h.add_child(UI.fixed_width(UI.label("%d/%d" % [part.cur, part.max], 15, UI.INK_SOFT), 72))
		h.add_child(UI.fixed_width(UI.label("守力 %.1f" % float(s.power), 15, UI.INK_SOFT), 92))
		h.add_child(UI.fixed_width(UI.label("来 %d · 漏 %d" % [int(s.count), int(s.left)], 15, UI.CINNABAR if int(s.left) > 0 else UI.JADE), 112))
		if bool(s.broken):
			h.add_child(UI.label("已破，来的全进院子", 15, UI.CINNABAR))
		else:
			h.add_child(UI.button("修缮", func(): _night_do(func(): return Post.night_mend(Game.run, sid), Defense.mend_block(run, sid))))
			h.add_child(UI.button("贴符", func(): _charm_menu(sid)))
			if sid == "gate":
				h.add_child(UI.button("关门" if bool(run.door_open) else "开门迎敌",
					func(): _night_do(func(): return Post.toggle_gate(Game.run), "")))
		body.add_child(h)
	body.add_child(UI.sep())
	var foot := UI.hbox(10)
	var block := Post.night_block(run, 0)
	if block != "":
		foot.add_child(UI.label(block, 15, UI.CINNABAR))
	# 布守具：只列还做得起的
	var devices: Dictionary = Data.table("devices").devices
	for did in devices:
		if Post.device_block(run, did) != "":
			continue
		if String(devices[did].get("surface", "*")) == "*":
			continue
		foot.add_child(UI.button("布 %s → %s" % [devices[did].name, Defense.surface_name(str(devices[did].surface))],
			func(): _night_do(func(): return Post.night_build(Game.run, did), "")))
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("等下一轮", func(): UI.close_modal("night")))
	body.add_child(foot)


func _night_do(cb: Callable, tip: String) -> void:
	if tip != "":
		Game.toast.emit(tip)
		return
	var res = Game.act(cb)
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("night")


func _charm_menu(sid: String) -> void:
	UI.open_modal("charm", "在%s上贴什么" % Defense.surface_name(sid), func(body: VBoxContainer): _charm_list(body, sid), true, 560)


func _charm_list(body: VBoxContainer, sid: String) -> void:
	var run := _run()
	for id in ["talisman", "dog_blood", "glutinous"]:
		var h := UI.hbox(10)
		h.add_child(UI.expand(UI.label("%s（有 %d）　守力 +%d" % [Data.item_name(id), Inv.count(run.home, id), int(Defense.charm_power(id))], 17)))
		var block := Defense.charm_block(run, sid, id)
		h.add_child(UI.button("贴上", func(): _charm_do(sid, id), block != "", block))
		body.add_child(h)


func _charm_do(sid: String, id: String) -> void:
	var res = Game.act(func(): return Post.night_charm(Game.run, sid, id))
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("charm")
		UI.close_modal("night")


# ---------- 添置家具 ----------

func furnish() -> void:
	UI.open_modal("furnish", "添置家具", _furnish, true, 960)


func _furnish(body: VBoxContainer) -> void:
	var run := _run()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = clampf(UI.host.get_viewport_rect().size.y - 180.0, 220.0, 540.0)
	UI.expand(scroll)
	body.add_child(scroll)
	var content := UI.vbox(8)
	UI.expand(content)
	scroll.add_child(content)
	content.add_child(UI.para("挑一件，在当前空间点地面放下。R 转方向，Esc 取消；不能堵通路，也不能和别的东西挤在一起。", 16))
	if Floors.current(run) != "courtyard":
		content.add_child(UI.para("家具原有的全宅效果仍会生效；做饭、睡觉等工作请回院内对应工作站。", 14))
	content.add_child(UI.sep())
	var items: Dictionary = Data.table("furniture")
	var keys := items.keys()
	var row: HBoxContainer = null
	for i in keys.size():
		if i % 2 == 0:
			row = UI.hbox(10)
			content.add_child(row)
		row.add_child(_furn_card(run, str(keys[i])))
	var floor_id := Floors.current(run)
	var placed := Home.list(run).filter(func(f): return str(f.get("floor", "courtyard")) == floor_id)
	if not placed.is_empty():
		content.add_child(UI.sep())
		content.add_child(UI.label("已经摆着的（可挪位，拆掉退一半料）", 18, UI.CINNABAR))
		for f in placed:
			var uid := int(f.uid)
			var h := UI.hbox(10)
			UI.expand(h)
			var line := "%s　(%d, %d)" % [Home.data(str(f.id)).get("name", ""), int(f.x), int(f.z)]
			if Home.is_core(run, f):
				line += "　·　核心家具"
			h.add_child(UI.expand(UI.label(line, 16)))
			h.add_child(UI.button("挪位", func(): _move_furn(uid)))
			if not Home.is_core(run, f):
				h.add_child(UI.button("拆掉", func(): _remove_furn(uid)))
			content.add_child(h)


func _furn_card(run: Dictionary, id: String) -> Control:
	var d := Home.data(id)
	var v := UI.vbox(4)
	UI.expand(v)
	var top := UI.hbox(8)
	top.add_child(UI.icon(id, 52, true))
	var name_col := UI.vbox(2)
	name_col.add_child(UI.label(d.get("name", id), 19))
	var where := str(WHERE_TEXT.get(str(d.get("where", "any")), "屋里屋外都行"))
	name_col.add_child(UI.label("%s　%s" % [where, str(FN_TEXT.get(str(d.get("fn", "")), ""))], 13, UI.DAI))
	top.add_child(name_col)
	v.add_child(top)
	var sz := Home.size_of(id, 0)
	# 用料也用图标：木料 3、铁钉 2 一眼看得出来
	var cost_row := UI.hbox(10)
	cost_row.add_child(UI.label("用料", 14, UI.INK_SOFT))
	var cost: Dictionary = d.get("cost", {})
	for item in cost:
		var unit := UI.hbox(2)
		unit.add_child(UI.icon(str(item), 22))
		var have := Inv.count(run.home, item)
		unit.add_child(UI.label("×%d（有 %d）" % [int(cost[item]), have], 14,
			UI.INK_SOFT if have >= int(cost[item]) else UI.CINNABAR))
		cost_row.add_child(unit)
	cost_row.add_child(UI.label("占 %.1f×%.1f" % [sz.x, sz.y], 14, UI.INK_FAINT))
	v.add_child(cost_row)
	var block := Home.build_block(run, id)
	if block == "":
		v.add_child(UI.button("去摆", func(): _pick_furnish(id)))
	else:
		v.add_child(UI.label(block, 13, UI.INK_FAINT))
	var card := UI.panel(v, UI.PAPER)
	UI.expand(card)
	return card


func _pick_furnish(id: String) -> void:
	UI.close_modal("furnish")
	Game.placing = id
	Game.moving_uid = -1
	Game.placing_rot = 0
	Game.toast.emit("点地面放下%s（R 转方向，Esc 取消）" % Home.data(id).get("name", "家具"))


func _move_furn(uid: int) -> void:
	var f := Home.find(Game.run, uid)
	var block := Home.move_block(Game.run, uid)
	if block == "":
		block = Post.can_act(Game.run)
	if block != "":
		Game.toast.emit(block)
		return
	UI.close_modal("furnish")
	Game.placing = str(f.id)
	Game.moving_uid = uid
	Game.placing_rot = int(f.rot)
	Game.toast.emit("点地面挪动%s（R 转方向，Esc 取消）" % Home.data(str(f.id)).get("name", "家具"))


func _remove_furn(uid: int) -> void:
	UI.close_modal("furnish")
	_act_sfx(func(): return Post.act_unfurnish(Game.run, uid), "hit_plank")


# ---------- 战报 / 天亮结算 ----------

func wave_report() -> void:
	UI.open_modal("wave_report", "第 %d 夜 · 战报" % int(_run().pday), _wave_report, false, 760)


func _wave_report(body: VBoxContainer) -> void:
	var run := _run()
	var w: Dictionary = run.wave_report
	if w.is_empty():
		UI.close_modal("wave_report")
		return
	body.add_child(UI.label("尸潮%s" % ("·" + w.name if w.name != "" else ""), 22, UI.CINNABAR))
	body.add_child(UI.label("整夜来 %d 只　斩 %d 只　进院 %d 只" % [w.count, w.killed, w.get("enter", 0)], 18))
	body.add_child(UI.sep())
	body.add_child(UI.label("三轮战况", 19, UI.CINNABAR))
	var g := UI.grid(8, 10, 4)
	for head in ["轮", "来", "斩", "漏", "门", "窗", "墙", "进院"]:
		g.add_child(UI.label(head, 14, UI.INK_FAINT))
	for rep in w.get("rounds", []):
		g.add_child(UI.label("第 %d 轮" % (int(rep.round) + 1), 15))
		g.add_child(UI.label(str(rep.count), 15))
		g.add_child(UI.label(str(rep.killed), 15, UI.JADE))
		g.add_child(UI.label(str(rep.left), 15, UI.INK_SOFT))
		for sid in Defense.SURFACES:
			var s: Dictionary = rep.surfaces.get(sid, {})
			var cur := int(s.get("dmg", 0))
			g.add_child(UI.label("-%d" % cur if cur > 0 else "—", 15, UI.CINNABAR if cur > 0 else UI.INK_FAINT))
		g.add_child(UI.label(str(rep.get("enter", 0)), 15, UI.CINNABAR if int(rep.get("enter", 0)) > 0 else UI.INK_SOFT))
	body.add_child(g)
	if not w.get("broke", []).is_empty():
		var names := []
		for sid in w.broke:
			names.append(Defense.surface_name(sid))
		body.add_child(UI.label("%s被撞破了，来不及修的话，明晚会直接从那儿进来。" % "、".join(names), 17, UI.CINNABAR))
	if int(w.get("hp_loss", 0)) > 0:
		body.add_child(UI.label("被进院的咬伤：气血 -%d" % int(w.hp_loss), 17, UI.CINNABAR))
	if w.get("poisoned", false):
		body.add_child(UI.label("被抓伤，染上了尸毒。", 17, UI.CINNABAR))
	if not w.get("broken", []).is_empty():
		body.add_child(UI.para("用尽的守具：" + "、".join(w.broken), 15))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.seal_button("接着守夜", func(): _act(_ack_wave)))
	body.add_child(row)


func _ack_wave() -> String:
	Post.ack_wave(Game.run)
	return ""


func dawn_report() -> void:
	UI.open_modal("dawn", "天亮了 · 第 %d 日" % int(_run().pday), _dawn_report, false, 720)
	# 青云观的晨钟
	Sfx.strikes(["bell", "bell", "bell"], 1.6, -9.0)


func _dawn_report(body: VBoxContainer) -> void:
	var run := _run()
	var rep: Dictionary = run.report
	if not run.dawn_due or rep.is_empty():
		UI.close_modal("dawn")
		return
	for l in rep.get("night", []):
		body.add_child(UI.para(l, 17, UI.INK))
	if rep.get("night", []).is_empty():
		body.add_child(UI.para("一夜无事。", 17, UI.INK))
	# 同院的人一早干的活（没带人就没有这一段）
	if not rep.get("help", []).is_empty():
		body.add_child(UI.sep())
		body.add_child(UI.label("院里的人", 22, UI.CINNABAR))
		for l in rep.help:
			body.add_child(UI.para(l, 17, UI.INK))
	body.add_child(UI.sep())
	body.add_child(UI.label("功过格", 22, UI.CINNABAR))
	var g := UI.grid(2, 30, 2)
	for l in rep.settle.lines:
		g.add_child(UI.label(l[0], 17))
		g.add_child(UI.label("+%d" % l[1], 17, UI.JADE))
	body.add_child(g)
	body.add_child(UI.label("今日积功德 %d，共 %d" % [rep.settle.total, rep.settle.merit], 18))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.seal_button("翻过这一页", func(): _act(_ack_dawn)))
	body.add_child(row)


func _ack_dawn() -> String:
	Post.ack_dawn(Game.run)
	# 一睁眼先知道今天有多少事、只有多少工夫：不弹窗，免得和事件抢注意力
	if str(Game.run.get("phase", "")) == "post":
		var s := Agenda.summary(Game.run)
		Game.toast.emit("今日差事 %d 件、共 %s 小时，醒着只有 %s 小时——按 %s 挑着做。" % [
			int(s.count), Agenda.hours_text(int(s.need)), Agenda.hours_text(int(s.left)), InputCfg.first_key_name("agenda")])
	return ""


# ---------- 神龛求签 ----------

func omens() -> void:
	UI.open_modal("omens", "神龛求签", _omens, true, 900)


func _omens(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("功德 %d。签筒里每日三支签，可以花功德求，也可以留一支到明日；同一天求得越多越贵。" % int(run.merit), 17))
	var row := UI.hbox(12)
	for id in run.omens.offer:
		var o: Dictionary = Data.table("omens")[id]
		var v := UI.vbox(6)
		var taken: bool = id in run.omens.taken
		var cost := Ledger.omen_cost(run, id)
		v.add_child(UI.tag(o.tier, UI.CINNABAR if o.tier.begins_with("上") else UI.GOLD))
		v.add_child(UI.heading(o.name, 24, UI.INK_FAINT if taken else UI.INK))
		v.add_child(UI.para("「%s」" % o.verse, 16, UI.DAI))
		v.add_child(UI.para(o.desc, 16))
		v.add_child(UI.label("功德 %d" % cost, 17, UI.CINNABAR))
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(gap)
		if taken:
			v.add_child(UI.tag("已求得", UI.JADE))
		else:
			v.add_child(UI.seal_button("求此签", func(): _act(func(): return Ledger.take_omen(Game.run, id)), int(run.merit) < cost))
			var locked: bool = run.omens.locked == id
			v.add_child(UI.button("不留了" if locked else "留到明日", func(): _act(func(): return _toggle_lock(id))))
		var p := UI.panel(v, UI.PAPER)
		UI.expand(p)
		row.add_child(p)
	body.add_child(row)
	var foot := UI.hbox()
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("摇签筒（%d 功德）" % Ledger.REROLL_COST, func(): _act(func(): return Ledger.reroll_omens(Game.run)), int(run.merit) < Ledger.REROLL_COST))
	body.add_child(foot)


func _toggle_lock(id: String) -> String:
	Ledger.toggle_lock(Game.run, id)
	return ""


# ---------- 通用确认 ----------

func confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	UI.open_modal("confirm", title, func(body: VBoxContainer): _confirm(body, text, ok_text, on_ok), true, 560)


func _confirm(body: VBoxContainer, text: String, ok_text: String, on_ok: Callable) -> void:
	body.add_child(UI.para(text, 18, UI.INK))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.button("再想想", func(): UI.close_modal("confirm")))
	row.add_child(UI.seal_button(ok_text, func(): _confirm_ok(on_ok)))
	body.add_child(row)


func _confirm_ok(on_ok: Callable) -> void:
	UI.close_modal("confirm")
	on_ok.call()


# ---------- 备劫：铺子 ----------

func shop() -> void:
	var id: String = _run().loc
	if id == "home":
		return
	UI.open_modal("shop", Pre.shop(id).name, _shop, true, 880)


func _shop(body: VBoxContainer) -> void:
	var run := _run()
	var id: String = run.loc
	if run.phase != "pre" or id == "home":
		UI.close_modal("shop")
		return
	var s: Dictionary = Pre.shop(id)
	var head := UI.hbox(10)
	head.add_child(UI.tag(Pre.status(run, id), STATUS_COLORS.get(Pre.status(run, id), UI.INK_SOFT)))
	head.add_child(UI.label("银两 %s　车上 %.0f / %d 斤" % [Pre.money(int(run.silver)), Pre.cart_weight(run), Pre.capacity(run)], 17, UI.INK_SOFT))
	body.add_child(head)
	body.add_child(UI.para(s.desc, 16))
	body.add_child(UI.sep())
	match s.kind:
		"goods":
			_goods(body, run, id)
		"facility":
			_facilities(body, run)
		"pawn":
			_pawn(body, run)


func _goods(v: VBoxContainer, run: Dictionary, shop_id: String) -> void:
	if Pre.status(run, shop_id) == "关门":
		v.add_child(UI.para(Pre.shop(shop_id).get("close", {}).get("text", "已经关门了。"), 18, UI.CINNABAR))
		return
	var g := UI.grid(6, 10, 6)
	for col in ["货品", "价钱", "斤两", "余货", "", ""]:
		g.add_child(UI.label(col, 15, UI.INK_FAINT))
	for item_id in run.shops[shop_id]:
		var it := Data.item(item_id)
		var left := int(run.shops[shop_id][item_id])
		var name_label := UI.label("%s（%s）" % [it.name, it.unit], 18)
		name_label.tooltip_text = it.desc
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		UI.expand(name_label)
		g.add_child(name_label)
		var p := Pre.price(run, shop_id, item_id)
		g.add_child(UI.label(Pre.money(p), 18, UI.CINNABAR if p > int(it.price) else UI.INK))
		g.add_child(UI.label(str(it.weight), 16, UI.INK_SOFT))
		g.add_child(UI.label("余 %d" % left, 16, UI.INK_SOFT if left > 0 else UI.INK_FAINT))
		var block := Pre.buy_block(run, item_id, 1)
		g.add_child(UI.button("买一", func(): _act_sfx(func(): return Pre.buy(Game.run, item_id, 1), "coins"), block != "", block))
		var most := Pre.max_buy(run, item_id)
		g.add_child(UI.button("买 %d" % most if most > 1 else "买尽", func(): _act_sfx(func(): return Pre.buy(Game.run, item_id, Pre.max_buy(Game.run, item_id)), "coins"), most <= 1))
	v.add_child(g)


func _facilities(v: VBoxContainer, run: Dictionary) -> void:
	var facs: Dictionary = Data.table("facilities")
	for fac_id in facs:
		var f: Dictionary = facs[fac_id]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		info.add_child(UI.label("%s　%s" % [f.name, Pre.money(int(f.price))], 19))
		info.add_child(UI.para(f.desc, 15))
		h.add_child(info)
		if fac_id in run.orders:
			h.add_child(UI.tag("已订", UI.JADE))
		else:
			_action(h, "订制", func(): _act_sfx(func(): return Pre.order(Game.run, fac_id), "book_place"), Pre.order_block(run, fac_id))
		v.add_child(h)


func _pawn(v: VBoxContainer, run: Dictionary) -> void:
	var items := Pre.pawnable(run)
	if items.is_empty():
		v.add_child(UI.para("身上没有值钱的东西。", 17))
		return
	for item_id in items:
		var h := UI.hbox(10)
		var n := Inv.count(run.cart, item_id) + Inv.count(run.home, item_id)
		h.add_child(UI.expand(UI.label("%s ×%d" % [Data.item_name(item_id), n], 18)))
		h.add_child(UI.label("当得 %s" % Pre.money(Pre.pawn_value(item_id)), 17, UI.CINNABAR))
		h.add_child(UI.button("当了", func(): _act_sfx(func(): return Pre.pawn(Game.run, item_id), "coins")))
		v.add_child(h)


# ---------- 备劫：囤货清单 ----------

func checklist() -> void:
	UI.open_modal("checklist", "囤货清单", _checklist, true, 620)


func _checklist(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("按二十日的用度估算。家里的和车上的都算。", 15))
	var g := UI.grid(3, 16, 4)
	for row in Pre.checklist(run):
		g.add_child(UI.label(row.name, 18))
		g.add_child(UI.label("%d %s" % [row.value, row.unit], 16, UI.INK_SOFT))
		g.add_child(UI.tag(row.grade, GRADE_COLORS[row.grade]))
	body.add_child(g)
	body.add_child(UI.sep())
	var orders := []
	for fac_id in run.orders:
		orders.append(Data.table("facilities")[fac_id].name)
	body.add_child(UI.para("已订营造：" + ("、".join(orders) if not orders.is_empty() else "还没去营造坊（第二日后就来不及了）"), 16, UI.INK if not orders.is_empty() else UI.CINNABAR))
	body.add_child(UI.para("家中存货：" + (Data.describe_items(run.home) if not run.home.is_empty() else "（空）"), 15))
	body.add_child(UI.para("车上：" + (Data.describe_items(run.cart) if not run.cart.is_empty() else "空着"), 15))


# ---------- 设置 ----------

const VOLUME_ROWS := [["music", "配乐"], ["sfx", "音效"], ["amb", "风声环境"]]

## 改键捕获节点（常驻，active 时才收键）、正在改的那一行、各行动作当前键名标签。
var _capture: Control
var _rebinding: Dictionary = {}
var _key_labels: Dictionary = {}


func _ready() -> void:
	_capture = preload("res://scripts/ui/key_capture.gd").new()
	_capture.captured.connect(_on_key_captured)
	add_child(_capture)


## 玩法说明：规则讲清楚，但不给"该买什么"这种建议（那是策略，因人而异）。
func manual() -> void:
	UI.open_modal("manual", "玩法说明", _manual, true, 760)


func _manual(body: VBoxContainer) -> void:
	var content := UI.vbox(10)
	for section in Manual.sections():
		content.add_child(UI.heading(str(section.title), 20, UI.CINNABAR))
		for row in section.rows:
			content.add_child(UI.para(Manual.render_row(row), 16))
		content.add_child(UI.sep())
	body.add_child(UI.scroll(content, 520))


## 存档备份：把这一局导出成 .jyz，或从 .jyz 导入一局。
## 导入前会自动把手上这一卷另存到 user://backups/，所以这里不再加一层"确定要覆盖吗"。
func save_pack() -> void:
	UI.open_modal("save_pack", "存档备份", _save_pack, true, 640)


func _save_pack(body: VBoxContainer) -> void:
	var has_run := not Game.run.is_empty()
	body.add_child(UI.para("导出的文件能拷到别处、发给别人，或者在新开一卷之前给自己留个存档点。带的是这一局本身（含「翻回昨日」的快照），不含道心与残卷。", 16))
	body.add_child(UI.sep())
	var row := UI.hbox(10)
	row.add_child(UI.button("导出这一局", _pick_save_path, not has_run,
		"现在没有进行中的局。" if not has_run else "选个位置存成 .jyz。"))
	row.add_child(UI.button("导入一局", _pick_load_path, false,
		"选一份 .jyz 打开。导入前会把现在这一卷另存到存档目录的 backups/ 里，不会凭空丢掉。"))
	body.add_child(row)
	var status := UI.para("", 15, UI.INK_SOFT)
	_live["save_pack_status"] = status
	body.add_child(status)


func _pick_save_path() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "导出存档"
	fd.add_filter("*.jyz", "劫余录存档")
	fd.current_file = Game.suggested_save_name()
	fd.file_selected.connect(_do_export_save.bind(fd))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(760, 520))


func _pick_load_path() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "导入存档"
	fd.add_filter("*.jyz,*.json", "劫余录存档")
	fd.file_selected.connect(_do_import_save.bind(fd))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(760, 520))


func _do_export_save(path: String, fd: FileDialog) -> void:
	fd.queue_free()
	var result := Game.export_save_to(path)
	_set_pack_status("已导出：%s" % path if bool(result.ok) else str(result.note), bool(result.ok))


func _do_import_save(path: String, fd: FileDialog) -> void:
	fd.queue_free()
	var result := Game.import_save_from(path)
	if not bool(result.ok):
		_set_pack_status(str(result.note), false)
		return
	var info: Dictionary = result.info
	var line := "已导入：第 %d 日%s" % [int(Game.run.get("pday", 0)),
		"（存档来自更新的结构，已自动升级）" if bool(info.get("upgraded", false)) else ""]
	var backup := str(info.get("backup", ""))
	if backup != "":
		line += "\n原来那一卷留在这里：%s" % backup
	_set_pack_status(line, true)
	UI.close_modal("save_pack")
	Game.go(Game.screen_for_run())


func _set_pack_status(text: String, ok: bool) -> void:
	var label = _live.get("save_pack_status")
	if label == null or not is_instance_valid(label):
		Game.toast.emit(text)
		return
	(label as Label).text = text
	(label as Label).add_theme_color_override("font_color", UI.INK if ok else UI.CINNABAR)


## 试玩报告导出的结果：路径 + 附了哪些文件 + 怎么发过来。
## 路径不能只用一个 toast——它长、会消失，玩家还要去文件管理器里找。
func playtest_exported(result: Dictionary) -> void:
	UI.open_modal("playtest_report", "试玩报告", _playtest_report.bind(result), true, 700)


func _playtest_report(body: VBoxContainer, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		body.add_child(UI.para("没导出来：%s" % str(result.get("note", "原因不明")), 17, UI.CINNABAR))
		body.add_child(UI.para("可以先把存档目录里的 save.json 手动发过来：%s" % ProjectSettings.globalize_path("user://"), 15, UI.INK_SOFT))
		return
	body.add_child(UI.para("这一局的事实已经打包好了。把整个文件夹压一下发过来就行——里面有种子、死因构成、最后几十条记录和存档本身。", 17))
	body.add_child(UI.sep())
	body.add_child(UI.label("文件夹", 15, UI.DAI))
	var path := UI.para(str(result.get("dir", "")), 16, UI.CINNABAR)
	body.add_child(path)
	body.add_child(UI.label("里面的文件", 15, UI.DAI))
	var files: Array = result.get("files", [])
	body.add_child(UI.para("、".join(files) if not files.is_empty() else "（只有报告）", 16, UI.INK_SOFT))
	body.add_child(UI.sep())
	body.add_child(UI.para("报告末尾留了三个空，想写就写：最烦的三件事、最看不懂的三处、二十天是长了还是短了。不写也不影响上面的数据。", 15, UI.INK_FAINT))


## 设置：画面、按键、音量；在游戏里打开时还能回标题（进度已自动存档）。
func settings(in_game := false) -> void:
	UI.open_modal("settings", "设置", _settings.bind(in_game), true, 560)


func _settings(body: VBoxContainer, in_game: bool) -> void:
	# 十八行按键加音量，720 高放不下：内容进滚动容器，底部按钮露在外面
	var content := UI.vbox(8)
	if in_game and not Game.run.is_empty():
		var enabled: bool = Director.state(Game.run).enabled
		content.add_child(UI.button("动态世情：" + ("开启" if enabled else "关闭"), func(): StoryDirector.set_enabled(not enabled)))
		content.add_child(UI.para("根据往来与处境在后台准备后续事件；关闭后，已许下的约定仍会兑现。", 15))
	content.add_child(UI.sep())
	content.add_child(UI.heading("画面", 20))
	var video := VideoCfg.read()
	# 按钮装在行里、回调 bind 整行：GDScript 的 lambda 不能引用正在初始化的变量，
	# 循环变量也不能直接捕获（十八行按键会全变成最后一行），一律 bind 快照 + 从行里取按钮
	var fs_row := UI.hbox(8)
	fs_row.add_child(UI.button("全屏：" + ("开" if bool(video.fullscreen) else "关"),
		_toggle_video.bind("fullscreen", video, fs_row)))
	content.add_child(fs_row)
	var res_row := UI.hbox(8)
	res_row.add_child(UI.button("分辨率：" + _res_text(int(video.resolution)),
		_cycle_resolution.bind(video, res_row)))
	content.add_child(res_row)
	var vs_row := UI.hbox(8)
	vs_row.add_child(UI.button("垂直同步：" + ("开" if bool(video.vsync) else "关"),
		_toggle_video.bind("vsync", video, vs_row)))
	content.add_child(vs_row)
	content.add_child(UI.para("分辨率只改窗口大小，画面随之缩放；三项重启后仍然算数。", 14, UI.INK_FAINT))
	content.add_child(UI.sep())
	content.add_child(UI.heading("按键", 20))
	content.add_child(UI.para("点「改键」后按新键即成；Esc 取消。一个键只归一个动作，冲突会提示给了谁。", 15))
	_key_labels.clear()
	for action in InputCfg.ORDER:
		var row := UI.hbox(8)
		row.add_child(UI.fixed_width(UI.label(InputCfg.LABELS[action], 16), 108))
		var keys_label := UI.fixed_width(UI.label(_keys_text(action), 15, UI.INK_SOFT), 110)
		_key_labels[action] = keys_label
		row.add_child(keys_label)
		row.add_child(UI.expand(UI.label("", 14)))
		row.add_child(UI.button("改键", _start_rebind.bind(action, keys_label, row)))
		content.add_child(row)
	content.add_child(UI.sep())
	content.add_child(UI.button("按键全部恢复默认", _restore_default_keys))
	content.add_child(UI.sep())
	for row in VOLUME_ROWS:
		var key: String = row[0]
		var h := UI.hbox(12)
		h.add_child(UI.fixed_width(UI.label(row[1], 18), 96))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Sfx.volume(key)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y = 24
		var pct := UI.fixed_width(UI.label("%d%%" % roundi(slider.value * 100), 16, UI.INK_SOFT), 52)
		slider.value_changed.connect(_on_volume.bind(key, pct))
		# 松手时试听一下、存起来
		slider.drag_ended.connect(_on_volume_done.bind(key))
		h.add_child(slider)
		h.add_child(pct)
		content.add_child(h)
	content.add_child(UI.para("声音素材：Kenney、OpenGameArt、BiteMe Games（CC0）；梆子、更鼓、赶尸铃、铜锣为程序合成。", 14, UI.INK_FAINT))
	if in_game:
		content.add_child(UI.sep())
		var row := UI.hbox()
		row.add_child(UI.para("进度已自动存档，回到标题后可以续写。", 15))
		row.add_child(UI.button("回到标题", func(): Game.go("title")))
		content.add_child(row)
	body.add_child(UI.scroll(content, mini(460, maxi(240, int(get_viewport().get_visible_rect().size.y) - 170))))


func _res_text(index: int) -> String:
	var size: Array = VideoCfg.SIZES[clampi(index, 0, VideoCfg.SIZES.size() - 1)]
	return "%d × %d" % [int(size[0]), int(size[1])]


func _keys_text(action: String) -> String:
	var names: Array = []
	for key in InputCfg.keys_of(action):
		names.append(InputCfg.key_name(key))
	return " / ".join(names) if not names.is_empty() else "（无）"


## 开关类画面选项：翻值、存、套窗口，再把自己按钮上的文字翻过来。
func _toggle_video(key: String, video: Dictionary, row: HBoxContainer) -> void:
	video[key] = not bool(video[key])
	VideoCfg.save(video)
	VideoCfg.apply(video)
	var btn: Button = row.get_child(row.get_child_count() - 1)
	var on := bool(video[key])
	btn.text = ("全屏：" if key == "fullscreen" else "垂直同步：") + ("开" if on else "关")


## 分辨率在三档里循环（点一下换一档，比下拉少一次点击）。
func _cycle_resolution(video: Dictionary, row: HBoxContainer) -> void:
	video["resolution"] = (int(video["resolution"]) + 1) % VideoCfg.SIZES.size()
	VideoCfg.save(video)
	VideoCfg.apply(video)
	var btn: Button = row.get_child(row.get_child_count() - 1)
	btn.text = "分辨率：" + _res_text(int(video["resolution"]))


## 点「改键」：松开焦点（不然空格/回车会顺带触发按钮），等捕获节点送键来。
func _start_rebind(action: String, keys_label: Label, row: HBoxContainer) -> void:
	var btn: Button = row.get_child(row.get_child_count() - 1)
	_rebinding = {"action": action, "label": keys_label, "button": btn}
	btn.text = "按下新键…"
	btn.disabled = true
	get_viewport().gui_release_focus()
	_capture.active = true


func _on_key_captured(key: int) -> void:
	if _rebinding.is_empty():
		return
	var r: Dictionary = _rebinding
	_rebinding = {}
	var btn: Button = r["button"]
	var keys_label: Label = r["label"]
	var action: String = r["action"]
	btn.disabled = false
	btn.text = "改键"
	if key == KEY_ESCAPE:
		Game.toast.emit("没改，还是原来的键。")
		return
	var owner := InputCfg.owner_of(key)
	if owner != "" and owner != action:
		Game.toast.emit("这个键已经给了「%s」，没改。" % InputCfg.LABELS.get(owner, owner))
		return
	if InputCfg.rebind(action, key):
		keys_label.text = _keys_text(action)
		_refresh_key_hints()


## 改键后宅院 HUD 上的快捷键提示要跟着变（不然提示骗人）。
func _refresh_key_hints() -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		return
	var screen: Node = host.get("_screen")
	if screen != null and screen.has_method("refresh_key_hints"):
		screen.refresh_key_hints()


func _restore_default_keys() -> void:
	InputCfg.restore()
	for action in _key_labels:
		(_key_labels[action] as Label).text = _keys_text(action)
	_refresh_key_hints()
	Game.toast.emit("按键都恢复默认了。")


func _on_volume(value: float, key: String, pct: Label) -> void:
	Sfx.set_volume(key, value)
	pct.text = "%d%%" % roundi(value * 100)


func _on_volume_done(_changed: bool, key: String) -> void:
	Game.save_meta()
	match key:
		"music":
			pass
		"sfx":
			Sfx.play("bangzi", -4.0, 0.0)
		"amb":
			Sfx.play("gust", -6.0)
