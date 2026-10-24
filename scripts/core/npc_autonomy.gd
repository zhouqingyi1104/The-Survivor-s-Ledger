extends RefCounted
## Finite NPC working stock. Existing trade contracts have a separate reserved cargo.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const FOCAL := {"ning": "mugwort", "zhou": "wood", "traveler": "firewood"}
const MODES := {"gather": "筹措周转", "stockpile": "备货自保", "guard": "收紧往来", "share": "主动回报"}
const STOCK_LIMIT := 20

static func _day(run: Dictionary) -> int:
	return maxi(1, int(run.get("t", 0)) / 1440 + 1)

static func _decision_t(day: int) -> int:
	return (day - 1) * 1440 + 120

static func _normal_policy() -> Dictionary:
	return {"price_add": 0, "credit_allowed": true, "reason": "自主周转照常，已签的报价、欠账和回礼不变。"}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("npcs") is Dictionary or run.npcs.is_empty():
		run["npcs"] = {"schema": 1, "revision": 0, "next_day": maxi(2, _day(run) + 1), "actors": {}, "history": []}
	var s: Dictionary = run.npcs
	for actor in ACTORS:
		if not s.actors.has(actor):
			var stock := {"rice": 3}
			stock[FOCAL[actor]] = 3
			s.actors[actor] = {"stock": stock, "plan": {}, "policy": _normal_policy(), "last_result": "尚未作出自主安排。"}
	return s

## Lazy counterpart of Trade.state, without a preload cycle.
static func _trade_state(run: Dictionary) -> Dictionary:
	if not run.get("trade") is Dictionary or run.trade.is_empty():
		var actors := {}
		for actor in ACTORS:
			var relation := int(run.get("director", {}).get("relations", {}).get(actor, 0))
			actors[actor] = {"trust": clampi(relation, -5, 5), "favors": 0, "breaches": 0, "breach_total": 0, "last_change": "此前往来折算的信任" if relation != 0 else "尚无人情往来"}
		run["trade"] = {"schema": 1, "revision": 0, "actors": actors, "quotes": {}, "debt": {}, "aid": [], "history": [], "observed": [], "last_result": ""}
	return run.trade

static func _memory(run: Dictionary, actor: String) -> Dictionary:
	var out := {}
	for memory in Past.public_memories(run):
		if memory.get("actor", "") == actor:
			var response := str(memory.get("response", ""))
			out = {"fact": str(memory.get("fact", "")).left(160), "response": response if response in ["", "acknowledge", "compensate", "dismiss"] else ""}
	return out

static func _token(run: Dictionary, actor: String) -> String:
	var s := state(run)
	return "npc:%s:%s:%s:%d" % [str(Past.state(run).id), actor, str(s.actors[actor].plan.get("id", "")), int(s.revision)]

static func _adjust(stock: Dictionary, item: String, delta: int) -> void:
	stock[item] = clampi(int(stock.get(item, 0)) + delta, 0, STOCK_LIMIT)

static func _fact(run: Dictionary, actor: String, action: String, result: String, time: int, valence := 0, archive := true) -> String:
	var s := state(run)
	var day := maxi(1, time / 1440 + 1)
	s.history.append({"day": day, "t": time, "actor": actor, "action": action.left(32), "result": result.left(160)})
	while s.history.size() > 12: s.history.pop_front()
	s.actors[actor].last_result = result.left(240)
	s.revision = int(s.revision) + 1
	State.note(run, "邻人与商情 · " + result)
	# Keep actual clock facts even if a direct caller supplied a stale pday.
	if archive:
		Past.state(run)
		var fact_run: Dictionary = run.duplicate()
		fact_run["pday"] = day
		Past.record(fact_run, actor, "npc_autonomy", result, valence)
	return result

static func _relevant_crisis(run: Dictionary, actor: String) -> String:
	var active: Dictionary = Crisis.context(run).active
	if active.is_empty() or not active.get("stage", "") in ["warning", "impact"]: return ""
	match str(active.get("kind", "")):
		"well_freeze": return "crisis_well" if actor == "ning" else ""
		"herb_shortage": return "crisis_herb" if actor == "ning" else ""
		"fuel_shortage": return "crisis_fuel" if actor in ["zhou", "traveler"] else ""
	return ""

static func _decide(run: Dictionary, actor: String, day: int) -> String:
	var person: Dictionary = state(run).actors[actor]
	var stock: Dictionary = person.stock
	var focal := str(FOCAL[actor])
	_adjust(stock, "rice", -1)
	var trade: Dictionary = _trade_state(run).actors[actor]
	var memory := _memory(run, actor)
	var details := []
	var response := str(memory.get("response", ""))
	var crisis := _relevant_crisis(run, actor)
	var mode := "gather"
	var focus := focal
	var codes := []
	var why := "周转尚可，先补足下一次往来的货物。"
	if int(stock.rice) <= 1:
		focus = "rice"
		codes = ["low_food"]
		why = "今日口粮用过后米粮不足，先外出觅粮，自己的生计排在前面。"
	elif int(stock.get(focal, 0)) <= 1:
		codes = ["low_goods"]
		why = "擅长货物的周转库存不足，先筹措货源。"
	elif crisis != "":
		mode = "stockpile"
		codes = [crisis]
		why = "公开的危机风声与自己的生计有关，先留物自保；尚未核实的真假不作判断。"
	elif int(trade.trust) <= -2 or int(trade.breaches) > 0 or response == "dismiss":
		mode = "guard"
		if int(trade.trust) <= -2:
			codes.append("distrust")
			details.append("当下信任为 %d，缺少信赖" % int(trade.trust))
		if int(trade.breaches) > 0:
			codes.append("breach")
			details.append("还有 %d 笔失约未化解" % int(trade.breaches))
		if response == "dismiss":
			codes.append("memory_dismiss")
			details.append("本人已觉醒的旧梦被你疏远")
		why = "；".join(details) + "，因此收紧下一份往来。"
	elif int(trade.trust) >= 2 or int(trade.favors) > 0 or response in ["acknowledge", "compensate"]:
		mode = "share"
		if int(trade.trust) >= 2:
			codes.append("trust")
			details.append("现世信任已达 %d" % int(trade.trust))
		if int(trade.favors) > 0:
			codes.append("favor")
			details.append("现世还欠你人情 %d 份" % int(trade.favors))
		if response == "acknowledge":
			codes.append("memory_acknowledge")
			details.append("本人已觉醒的旧梦得到你承认")
		if response == "compensate":
			codes.append("memory_compensate")
			details.append("你已用今世赠粮回应其觉醒的旧梦")
		why = "；".join(details) + "，因此愿从自己的周转物资里回报。"
	else:
		codes = ["routine"]
	var req := {"rice": 2} if int(stock.rice) <= 1 else {focal: 1}
	person.plan = {"id": "npc:%s:%s:%d" % [str(Past.state(run).id), actor, day], "day": day,
		"due_t": (day - 1) * 1440 + 600, "mode": mode, "focus": focus, "reason_codes": codes,
		"reason": why, "response": "", "req": req, "reserved": {}, "status": "pending"}
	return _fact(run, actor, "decide", "%s决定%s：%s 第 %d 日 16:00 执行，之前可以支援、凭情改托或由他安排。" % [ACTORS[actor], MODES[mode], why, day], _decision_t(day), 0, false)

static func _gather_gain(stock: Dictionary, plan: Dictionary, supported: bool) -> int:
	return mini(3 if supported else 2, maxi(0, STOCK_LIMIT - int(stock.get(plan.focus, 0))))

static func _execute(run: Dictionary, actor: String) -> String:
	var person: Dictionary = state(run).actors[actor]
	var plan: Dictionary = person.plan
	var stock: Dictionary = person.stock
	var focal := str(FOCAL[actor])
	var supported: bool = plan.response == "support"
	var result := "%s按先前安排" % ACTORS[actor]
	var policy := _normal_policy()
	var valence := 0
	if plan.response == "favor":
		Inv.add_all(run.home, plan.reserved)
		result += "将已预留的%s送到你家，凭情改托兑现，原行动让位；下一份新报价照常。" % Data.describe_items(plan.reserved)
		plan.reserved = {}
		valence = 1
	else:
		match str(plan.mode):
			"gather":
				var amount := _gather_gain(stock, plan, supported)
				if amount <= 0:
					result += "发现目标周转库存已满，整理现有货物，没有额外耗米，也没有凭空增加物资。"
				elif plan.focus == "rice":
					var before := int(stock.rice)
					_adjust(stock, "rice", amount)
					result += "外出觅粮，自己的米粮增加 %d；这些物资仍属其本人，后续决定会据此变化。" % (int(stock.rice) - before)
				else:
					_adjust(stock, "rice", -1)
					var before := int(stock.get(focal, 0))
					_adjust(stock, focal, amount)
					result += "耗米 1 筹措%s，自己的%s增加 %d，后续决定会据此变化。" % [Data.item(focal).name, Data.item(focal).name, int(stock.get(focal, 0)) - before]
			"stockpile":
				_adjust(stock, focal, -1)
				policy = {"price_add": 0 if supported else 1, "credit_allowed": true,
					"reason": "自主备货得到你的支援，新报价不加价。" if supported else "自主备货耗去周转货物，新报价加收米 1。"}
				result += "耗%s 1 备货自保；%s已展示报价和签约物资不变。" % [Data.item(focal).name, policy.reason]
			"guard":
				policy = {"price_add": 0 if supported else 1, "credit_allowed": supported,
					"reason": "你的支援缓和了这次收紧，新报价不加价且可按原信任条件赊欠。" if supported else "自主收紧往来，新报价加收米 1 且不开放赊欠。"}
				result += "执行往来安排；%s已展示报价和旧欠账不变。" % policy.reason
			"share":
				var amount := mini(2 if supported else 1, int(stock.get(focal, 0)))
				_adjust(stock, focal, -amount)
				Inv.add(run.home, focal, amount)
				result += "从自己的周转物资扣%s %d，送到你家；后续库存与自主决定随之变化。" % [Data.item(focal).name, amount]
				valence = 1
	person.policy = policy
	plan.status = "done"
	var meaningful: bool = plan.mode != "gather" or plan.response in ["support", "favor"]
	return _fact(run, actor, "execute_" + str(plan.mode), result, int(plan.due_t), valence, meaningful)

static func poll(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return ""
	var s := state(run)
	var facts := []
	var now := int(run.get("t", 0))
	while true:
		var due := -1
		for actor in ACTORS:
			var plan: Dictionary = s.actors[actor].plan
			if plan.get("status", "") == "pending" and (due < 0 or int(plan.due_t) < due): due = int(plan.due_t)
		var decide := _decision_t(int(s.next_day))
		if due >= 0 and due <= now and due <= decide:
			for actor in ACTORS:
				var plan: Dictionary = s.actors[actor].plan
				if plan.get("status", "") == "pending" and int(plan.due_t) == due: facts.append(_execute(run, actor))
		elif decide <= now:
			var day := int(s.next_day)
			for actor in ACTORS: facts.append(_decide(run, actor, day))
			s.next_day = day + 1
		else:
			break
	return "\n".join(facts)

static func next_boundary(run: Dictionary) -> int:
	if str(run.get("phase", "")) != "post": return -1
	var s := state(run)
	var now := int(run.get("t", 0))
	var out := _decision_t(int(s.next_day))
	if out <= now: return now
	for actor in ACTORS:
		var plan: Dictionary = s.actors[actor].plan
		if plan.get("status", "") == "pending":
			var due := int(plan.due_t)
			if due <= now: return now
			out = mini(out, due)
	return out

static func _access_block(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return "尸劫开始后才能联系。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先回到宅院再联系。"
	if str(run.get("pending_event", "")) != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty(): return "正在忙别的事。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，无法联系。"
	return ""

static func _block(run: Dictionary, actor: String, action: String) -> String:
	var access := _access_block(run)
	if access != "": return access
	var person: Dictionary = state(run).actors[actor]
	var plan: Dictionary = person.plan
	if plan.is_empty(): return "尚未公开新的自主安排。"
	if int(run.get("t", 0)) < _decision_t(int(plan.day)): return "尚未到这份安排的公开时刻，不能提前介入。"
	if plan.status != "pending" or int(run.get("t", 0)) >= int(plan.due_t): return "这份安排已到执行时间，不能再介入。"
	if plan.response != "": return "本次已经作出回应，不能重复改动。"
	if not action in ["support", "favor", "decline"]: return "没有这个回应方式。"
	var trade: Dictionary = _trade_state(run).actors[actor]
	if action == "support":
		if int(trade.favors) >= 3: return "对方已欠你人情 3 份，先用掉一份，避免支援浪费。"
		for item in plan.req:
			if int(person.stock.get(item, 0)) + int(plan.req[item]) > STOCK_LIMIT: return "对方周转库存已满，不能再接受这份支援。"
		if plan.mode == "gather":
			var projected: Dictionary = person.stock.duplicate(true)
			for item in plan.req: _adjust(projected, str(item), int(plan.req[item]))
			if _gather_gain(projected, plan, true) <= 0: return "这份支援会填满筹措目标的库存，已没有增长余量；不能收物资承诺空的改善。"
		if not Inv.has_all(run.home, plan.req): return "需要%s。" % Data.describe_items(plan.req)
	if action == "favor":
		if int(trade.favors) < 1: return "对方还没有欠你的人情，需要人情 1。"
		if int(person.stock.get(FOCAL[actor], 0)) < 1: return "对方没有可供改托的擅长货物。"
	return ""

static func options(run: Dictionary, actor: String) -> Array:
	if not actor in ACTORS: return []
	var plan: Dictionary = state(run).actors[actor].plan
	var req: Dictionary = plan.get("req", {})
	var mode := str(plan.get("mode", ""))
	var extra := {"stockpile": "16:00 备货仍耗擅长货物 1，但下一份新报价不加价。", "guard": "16:00 缓和收紧，新报价不加价且恢复原信任条件下的赊欠。", "share": "16:00 从对方库存扣擅长货物 2，送到你家 2；支援已交的 1 也归其库存。"}
	if mode == "gather":
		var projected: Dictionary = state(run).actors[actor].stock.duplicate(true)
		if plan.response == "":
			for item in req: _adjust(projected, str(item), int(req[item]))
		var amount := _gather_gain(projected, plan, true)
		extra["gather"] = "16:00 按库存余量实际增加%s %d（本次最多3）；%s" % [Data.item(str(plan.focus)).name, amount, "自己耗米 1。" if plan.focus != "rice" and amount > 0 else ("不额外耗米。" if amount > 0 else "已无增长余量，这份支援不可用。")]
	var rows := [
		{"id": "support", "text": "送物支援", "hint": "交出%s加入对方周转库存，立即信任 +1、人情 +1（最多3）；%s本次回应锁定。" % [Data.describe_items(req), str(extra.get(mode, "等待下一份安排。"))]},
		{"id": "favor", "text": "凭情改托", "hint": "立即消耗人情 1，并从对方库存预留%s 1；16:00 送到你家，原行动取消，新报价照常。本次回应锁定。" % Data.item(FOCAL[actor]).name},
		{"id": "decline", "text": "由他安排", "hint": "零物资成本，不改变信任、不算失约；关闭本次介入，16:00 照原计划执行。"},
	]
	for row in rows: row["block"] = _block(run, actor, str(row.id))
	return rows

static func _trade_fact(run: Dictionary, actor: String, action: String, result: String) -> void:
	var trade := _trade_state(run)
	trade.revision = int(trade.revision) + 1
	trade.last_result = result
	trade.history.append({"day": _day(run), "t": int(run.get("t", 0)), "actor": actor, "action": "npc_" + action, "result": result})
	while trade.history.size() > 24: trade.history.pop_front()

static func act(run: Dictionary, actor: String, action: String, token: String) -> String:
	if not actor in ACTORS: return "没有这位邻人。"
	if token != _token(run, actor): return "这份自主安排已过期，请重新查看。"
	var blocked := _block(run, actor, action)
	if blocked != "": return blocked
	var person: Dictionary = state(run).actors[actor]
	var plan: Dictionary = person.plan
	var trade: Dictionary = _trade_state(run).actors[actor]
	var result := ""
	var valence := 0
	match action:
		"support":
			Inv.take_all(run.home, plan.req)
			for item in plan.req: _adjust(person.stock, str(item), int(plan.req[item]))
			trade.trust = clampi(int(trade.trust) + 1, -5, 5)
			trade.favors = int(trade.favors) + 1
			trade.last_change = "支援自主安排，信任 +1、人情 +1"
			result = "你交出%s支援%s，加入其周转库存；信任 +1、人情 +1，16:00 改善已公开的执行结果。" % [Data.describe_items(plan.req), ACTORS[actor]]
			valence = 1
		"favor":
			trade.favors = int(trade.favors) - 1
			trade.last_change = "用于自主安排凭情改托，人情 -1"
			_adjust(person.stock, FOCAL[actor], -1)
			plan.reserved = {FOCAL[actor]: 1}
			result = "你用去%s人情 1，已从其周转库存预留%s 1；16:00 按约送到你家，原行动让位。" % [ACTORS[actor], Data.item(FOCAL[actor]).name]
			valence = 1
		"decline":
			result = "你让%s照原计划安排。没有扣物资、没有信任或失约处罚；本次介入关闭，16:00 仍会执行。" % ACTORS[actor]
	plan.response = action
	if action != "decline": _trade_fact(run, actor, action, result)
	_fact(run, actor, action, result, int(run.get("t", 0)), valence)
	return ""

static func view(run: Dictionary, actor: String) -> Dictionary:
	if not actor in ACTORS: return {}
	var s := state(run)
	var person: Dictionary = s.actors[actor]
	var plan: Dictionary = person.plan
	var mode := str(plan.get("mode", ""))
	return {"actor": actor, "name": ACTORS[actor], "stock": person.stock.duplicate(true),
		"goal": str(MODES.get(mode, "等待下一次安排")), "title": "%s · %s" % [ACTORS[actor], MODES.get(mode, "周转近况")],
		"reason": str(plan.get("reason", "第 2 日起每天 08:00 公布新的自主安排。")), "effect": _effect(actor, plan, person.stock), "memory": _memory(run, actor),
		"plan": plan.duplicate(true), "policy": person.policy.duplicate(true), "token": _token(run, actor),
		"last_result": str(person.last_result), "next_decision_t": _decision_t(int(s.next_day))}

static func _effect(actor: String, plan: Dictionary, stock: Dictionary) -> String:
	if plan.is_empty(): return "尚未安排；每天 08:00 公布意图，16:00 执行。"
	if plan.status == "done": return "本次已执行，实际结算见下方记录；下一次决定会参考新库存与往来。"
	var focal := str(Data.item(FOCAL[actor]).name)
	if plan.response == "favor": return "16:00 将已预留的%s 1 送到你家，原自主行动取消，后续新报价照常。" % focal
	var supported: bool = plan.response == "support"
	match str(plan.mode):
		"gather":
			var amount := _gather_gain(stock, plan, supported)
			if amount <= 0: return "16:00 目标库存已满，只整理现有货物，不再耗米或增加物资；没有可承诺的额外筹措收益。"
			return "16:00 自己觅粮，按库存余量米粮实际增加 %d；物资属于对方，改变以后决定，不直接送给玩家。" % amount if plan.focus == "rice" else "16:00 自己耗米 1，按库存余量筹措%s %d；物资属于对方，改变以后决定。" % [focal, amount]
		"stockpile": return "16:00 自己耗%s 1 备货；下一份新报价%s，旧报价与承诺不变。" % [focal, "不加价" if supported else "加收米 1"]
		"guard": return "16:00 下一份新报价%s；旧报价与承诺不变。" % ("不加价，按原信任条件开放赊欠" if supported else "加收米 1，暂停赊欠")
		"share": return "16:00 从自己库存扣%s %d，送到你家 %d；后续库存与决定随之改变。" % [focal, 2 if supported else 1, 2 if supported else 1]
	return ""

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var actors := {}
	for actor in ACTORS:
		var current := view(run, actor)
		var out := {}
		for key in ["actor", "name", "stock", "goal", "plan", "policy", "memory"]: out[key] = current[key]
		actors[actor] = out
	return {"schema": 1, "revision": int(s.revision), "next_day": int(s.next_day), "actors": actors, "history": s.history.duplicate(true)}

static func market_effect(run: Dictionary, actor: String) -> Dictionary:
	if not actor in ACTORS: return _normal_policy()
	return state(run).actors[actor].policy.duplicate(true)
