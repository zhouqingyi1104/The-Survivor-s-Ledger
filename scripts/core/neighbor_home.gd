extends RefCounted
## One actual neighbor, one bounded request. All effects use this life's stock and ledger.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const DAY := 1440
const COST := {"wood": 2, "nails": 1}
const MINUTES := 60
const ENERGY := 6

static func fresh() -> Dictionary:
	return {"knocked": false, "stage": "unmet", "choice": "", "wall_repaired": false, "settled": false, "deadline_t": 0, "due_t": 0, "result": ""}

## A view is read-only, including for old saves without this field.
static func view(run: Dictionary) -> Dictionary:
	var data = run.get("neighbor_home", {})
	var out := fresh()
	if data is Dictionary:
		for key in out:
			if data.has(key): out[key] = data[key]
	return out

static func _state(run: Dictionary) -> Dictionary:
	if not run.get("neighbor_home") is Dictionary or run.neighbor_home.is_empty():
		run["neighbor_home"] = fresh()
	return run.neighbor_home

static func _access(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return "尸劫之后才能敲邻宅的门。"
	if str(run.get("home_floor", "courtyard")) != "courtyard": return "先返回宅院。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先返回宅院。"
	if str(run.get("pending_event", "")) != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事。"
	if run.get("sleeping", false) or not run.get("busy", {}).is_empty(): return "先结束手头的事。"
	if not run.get("fight", {}).is_empty(): return "战斗中不能串门。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，不能串门。"
	var minute := int(run.get("t", 0)) % DAY
	if minute < 120 or minute >= 720: return "白天 08:00–18:00 才能敲门。"
	return ""

static func knock(run: Dictionary) -> String:
	var block := _access(run)
	if block != "": return block
	var q := _state(run)
	if not bool(q.get("knocked", false)):
		q.knocked = true
		q.stage = "open"
		q.deadline_t = (int(run.t) / DAY + 1) * DAY + 720
		q.result = "西邻应门的是木料场老周。他邀你白天从院门进屋说话；他家墙板松了，请你在明日傍晚前答复。"
		State.note(run, q.result)
	return ""

static func _block(run: Dictionary, action: String) -> String:
	var access := _access(run)
	if access != "": return access
	var q := view(run)
	if not q.knocked: return "先敲门。"
	if q.stage != "open" or int(run.t) >= int(q.deadline_t): return "这次邻宅请求已经结束。"
	if action == "repair":
		if int(run.t) + MINUTES > int(q.deadline_t): return "距答复期限不足 60 分钟，来不及修墙。"
		if State.attr(run, "energy") < ENERGY: return "需要精力 6。"
		if not Inv.has_all(run.home, COST): return "需要木料 2、铁钉 1。"
	elif action == "trade":
		if Inv.count(run.home, "rice") < 1: return "需要米 1。"
		var stock: Dictionary = Npcs.state(run).actors.zhou.stock
		if Inv.count(stock, "wood") < 1: return "老周现有周转木料不足。"
		if Inv.count(stock, "rice") >= Npcs.STOCK_LIMIT: return "老周的周转米已满，不能收下。"
	elif action != "refuse": return "没有这个选择。"
	return ""

static func options(run: Dictionary) -> Array:
	var rows := [
		{"id": "repair", "text": "帮老周修墙", "hint": "木料 2、铁钉 1、精力 6，施工 60 分钟；完成后墙补好，次日信任最多 +2（上限 5）。中断退材料。"},
		{"id": "trade", "text": "用米换木料", "hint": "米 1 换老周周转库存中的木料 1；次日信任最多 +1（上限 5），不修墙。"},
		{"id": "refuse", "text": "说明难处，拒绝", "hint": "不消耗物资；次日信任最多 -1（下限 -5），不算失约。"},
	]
	for row in rows: row["block"] = _block(run, str(row.id))
	return rows

static func _choose(run: Dictionary, action: String, result: String) -> void:
	var q := _state(run)
	q.stage = "waiting"
	q.choice = action
	q.due_t = (int(run.t) / DAY + 1) * DAY + 120
	q.result = result
	State.note(run, result)

static func act(run: Dictionary, action: String) -> String:
	var block := _block(run, action)
	if block != "": return block
	if action == "repair":
		Inv.take_all(run.home, COST)
		State.add_attr(run, "energy", -ENERGY)
		_state(run).stage = "working"
		run.busy = {"kind": "neighbor_wall", "label": "帮老周修墙", "start": int(run.t), "end": int(run.t) + MINUTES, "data": {"paid_cost": COST.duplicate()}}
		State.note(run, "开始修老周家的墙，材料已备好。")
	elif action == "trade":
		var stock: Dictionary = Npcs.state(run).actors.zhou.stock
		Inv.add(run.home, "rice", -1)
		Inv.add(stock, "rice", 1)
		Inv.add(stock, "wood", -1)
		Inv.add(run.home, "wood", 1)
		Npcs._fact(run, "zhou", "neighbor_exchange", "老周用自己的木料 1 换来米 1。", int(run.t), 0, false)
		_choose(run, action, "你用米 1 换了老周周转库存中的木料 1；墙仍待修。")
	else:
		_choose(run, action, "你说明自己的难处，没有答应修墙。")
	return ""

static func complete(run: Dictionary) -> void:
	var q := _state(run)
	if q.get("stage", "") != "working": return
	q.wall_repaired = true
	_choose(run, "repair", "你补好了老周家松动的墙板。")

static func interrupt(run: Dictionary, reason := "夜袭") -> void:
	if str(run.get("busy", {}).get("kind", "")) != "neighbor_wall": return
	var paid: Dictionary = run.busy.get("data", {}).get("paid_cost", {})
	run.busy = {}
	Inv.add_all(run.home, paid)
	var q := _state(run)
	if q.get("stage", "") == "working": q.stage = "open"
	State.note(run, reason + "打断了邻墙施工，材料已退回；消耗的精力不退。")

## Called by the shared clock. Neither a new visit nor loading extends the deadline.
static func poll(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post" or not run.get("neighbor_home") is Dictionary: return ""
	var q := _state(run)
	if str(q.get("stage", "")) == "open" and int(run.t) >= int(q.get("deadline_t", 0)):
		_choose(run, "timeout", "答复期限已过，你没有回应老周的修墙请求。")
		q.due_t = (int(q.deadline_t) / DAY + 1) * DAY + 120
	if str(q.get("stage", "")) != "waiting" or int(run.t) < int(q.get("due_t", 0)): return ""
	var choice := str(q.get("choice", ""))
	if not choice in ["repair", "trade", "refuse", "timeout"]: return ""
	var delta: int = {"repair": 2, "trade": 1, "refuse": -1, "timeout": -1}[choice]
	var trust := int(Trade.contact(run, "zhou").trust)
	var actual := clampi(trust + delta, -5, 5) - trust
	q.stage = "settled"
	q.settled = true
	q.result = {"repair": "次日，老周记着你修好了墙。", "trade": "次日，老周记着你们的实物交换。", "refuse": "次日，老周记着你没有答应修墙。", "timeout": "次日，老周记着你没有回应修墙请求。"}[choice]
	if actual != 0:
		Trade.influence(run, "zhou", actual, q.result)
	else:
		Trade._history(run, "zhou", "neighbor_home", q.result + "（信任已到上下限，本次变化 0）")
	q.result += "信任实际变化 %+d。" % actual
	State.note(run, q.result)
	return q.result
