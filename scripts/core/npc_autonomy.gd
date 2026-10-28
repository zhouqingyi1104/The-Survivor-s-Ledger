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
	return {"price_add": 0, "credit_allowed": true, "reason": "日子照常过，谈好的报价、欠账和回礼都不变。"}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("npcs") is Dictionary or run.npcs.is_empty():
		run["npcs"] = {"schema": 1, "revision": 0, "next_day": maxi(2, _day(run) + 1), "actors": {}, "history": []}
	var s: Dictionary = run.npcs
	for actor in ACTORS:
		if not s.actors.has(actor):
			var stock := {"rice": 3}
			stock[FOCAL[actor]] = 3
			s.actors[actor] = {"stock": stock, "plan": {}, "policy": _normal_policy(), "last_result": "还没有打算。"}
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
	var why := "手头还行，先把下回要换的货备足。"
	if int(stock.rice) <= 1:
		focus = "rice"
		codes = ["low_food"]
		why = "吃过今天的口粮，米就不够了，先想办法弄粮，自家的日子要紧。" if actor == "zhou" else "吃过今天的口粮，米就不够了，先出门找粮，自家的日子要紧。"
	elif int(stock.get(focal, 0)) <= 1:
		codes = ["low_goods"]
		why = "拿手的货不多了，先去张罗。"
	elif crisis != "":
		mode = "stockpile"
		codes = [crisis]
		why = "外头的风声关系到自家生计，先留些东西自保；是真是假还不好说。"
	elif int(trade.trust) <= -2 or int(trade.breaches) > 0 or response == "dismiss":
		mode = "guard"
		if int(trade.trust) <= -2:
			codes.append("distrust")
			details.append("眼下对你的信任只有 %d" % int(trade.trust))
		if int(trade.breaches) > 0:
			codes.append("breach")
			details.append("还有 %d 笔失约没补" % int(trade.breaches))
		if response == "dismiss":
			codes.append("memory_dismiss")
			details.append("他记起的前世旧梦，被你推开了")
		why = "；".join(details) + "，因此收紧下一份往来。"
	elif int(trade.trust) >= 2 or int(trade.favors) > 0 or response in ["acknowledge", "compensate"]:
		mode = "share"
		if int(trade.trust) >= 2:
			codes.append("trust")
			details.append("现世信任已达 %d" % int(trade.trust))
		if int(trade.favors) > 0:
			codes.append("favor")
			details.append("这一世还欠你 %d 份人情" % int(trade.favors))
		if response == "acknowledge":
			codes.append("memory_acknowledge")
			details.append("他记起的前世旧梦，你认了")
		if response == "compensate":
			codes.append("memory_compensate")
			details.append("你送过粮，回应他记起的旧梦")
		why = "；".join(details) + "，所以愿意从自家存货里回报你。"
	else:
		codes = ["routine"]
	var req := {"rice": 2} if int(stock.rice) <= 1 else {focal: 1}
	person.plan = {"id": "npc:%s:%s:%d" % [str(Past.state(run).id), actor, day], "day": day,
		"due_t": (day - 1) * 1440 + 600, "mode": mode, "focus": focus, "reason_codes": codes,
		"reason": why, "response": "", "req": req, "reserved": {}, "status": "pending"}
	return _fact(run, actor, "decide", "%s打算%s：%s 第 %d 日 16:00 动手；在那之前，你可以支援、凭情改托，或由他安排。" % [ACTORS[actor], MODES[mode], why, day], _decision_t(day), 0, false)

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
		result += "把留给你的%s送到你家，原来的打算作罢。" % Data.describe_items(plan.reserved)
		plan.reserved = {}
		valence = 1
	else:
		match str(plan.mode):
			"gather":
				var amount := _gather_gain(stock, plan, supported)
				if amount <= 0:
					result += "存货已经堆满，只把现有的货理了理，没再耗米。"
				elif plan.focus == "rice":
					var before := int(stock.rice)
					_adjust(stock, "rice", amount)
					result += ("筹措口粮" if actor == "zhou" else "外出觅粮") + "，自家的米多了 %d。" % (int(stock.rice) - before)
				else:
					_adjust(stock, "rice", -1)
					var before := int(stock.get(focal, 0))
					_adjust(stock, focal, amount)
					result += "花米 1 张罗%s，自家的%s多了 %d。" % [Data.item(focal).name, Data.item(focal).name, int(stock.get(focal, 0)) - before]
			"stockpile":
				_adjust(stock, focal, -1)
				policy = {"price_add": 0 if supported else 1, "credit_allowed": true,
					"reason": "有你帮衬着备货，往后的报价不涨。" if supported else "备货花了自家的货，往后的报价多收米 1。"}
				result += "花%s 1 备货自保；%s谈好的报价和约定照旧。" % [Data.item(focal).name, policy.reason]
			"guard":
				policy = {"price_add": 0 if supported else 1, "credit_allowed": supported,
					"reason": "有你帮衬，他不再收紧：往后的报价不涨，照旧可以赊欠。" if supported else "他收紧了往来：往后的报价多收米 1，也不赊欠。"}
				result += "照打算办了；%s谈好的报价和欠账照旧。" % policy.reason
			"share":
				var amount := mini(2 if supported else 1, int(stock.get(focal, 0)))
				_adjust(stock, focal, -amount)
				Inv.add(run.home, focal, amount)
				result += "从自家存货里拿出%s %d，送到你家。" % [Data.item(focal).name, amount]
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
	if plan.is_empty(): return "还没说出新的打算。"
	if int(run.get("t", 0)) < _decision_t(int(plan.day)): return "他还没说出打算，没法插手。"
	if plan.status != "pending" or int(run.get("t", 0)) >= int(plan.due_t): return "他已经动手了，插不上手了。"
	if plan.response != "": return "这回你已经回过话了。"
	if not action in ["support", "favor", "decline"]: return "没有这个回应方式。"
	var trade: Dictionary = _trade_state(run).actors[actor]
	if action == "support":
		if int(trade.favors) >= 3: return "对方已经欠你 3 份人情，先用掉一份，再帮也记不上。"
		for item in plan.req:
			if int(person.stock.get(item, 0)) + int(plan.req[item]) > STOCK_LIMIT: return "对方存货已满，收不下了。"
		if plan.mode == "gather":
			var projected: Dictionary = person.stock.duplicate(true)
			for item in plan.req: _adjust(projected, str(item), int(plan.req[item]))
			if _gather_gain(projected, plan, true) <= 0: return "对方这样东西已经堆满，再送也添不进去。"
		if not Inv.has_all(run.home, plan.req): return "需要%s。" % Data.describe_items(plan.req)
	if action == "favor":
		if int(trade.favors) < 1: return "对方还不欠你人情，要 1 份人情。"
		if int(person.stock.get(FOCAL[actor], 0)) < 1: return "对方手头没有拿手的货可以改送给你。"
	return ""

static func options(run: Dictionary, actor: String) -> Array:
	if not actor in ACTORS: return []
	var plan: Dictionary = state(run).actors[actor].plan
	var req: Dictionary = plan.get("req", {})
	var mode := str(plan.get("mode", ""))
	var extra := {"stockpile": "16:00 照样花拿手的货 1 备货，但往后的报价不涨。", "guard": "16:00 不再收紧，往后的报价不涨，照旧可以赊欠。", "share": "16:00 从自家拿出拿手的货 2，送到你家；你帮衬的那 1 份也留在他家。"}
	if mode == "gather":
		var projected: Dictionary = state(run).actors[actor].stock.duplicate(true)
		if plan.response == "":
			for item in req: _adjust(projected, str(item), int(req[item]))
		var amount := _gather_gain(projected, plan, true)
		extra["gather"] = "16:00 添%s %d（这回最多 3）；%s" % [Data.item(str(plan.focus)).name, amount, "自己耗米 1。" if plan.focus != "rice" and amount > 0 else ("不额外耗米。" if amount > 0 else "已经堆满，再帮也添不进去。")]
	var rows := [
		{"id": "support", "text": "送物支援", "hint": "交出%s给对方，信任 +1、人情 +1（最多 3）；%s这回就这么定了。" % [Data.describe_items(req), str(extra.get(mode, "等待下一份安排。"))]},
		{"id": "favor", "text": "凭情改托", "hint": "用掉 1 份人情，请他留出%s 1；16:00 送到你家，原来的打算作罢。这回就这么定了。" % Data.item(FOCAL[actor]).name},
		{"id": "decline", "text": "由他安排", "hint": "不花东西，信任不变，不算失约；16:00 他照原来的打算办。"},
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
	if token != _token(run, actor): return "情况已经变了，请重新看一遍。"
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
			trade.last_change = "帮衬了他的打算，信任 +1、人情 +1"
			result = "你交出%s帮衬%s；信任 +1、人情 +1，16:00 他办得会更好些。" % [Data.describe_items(plan.req), ACTORS[actor]]
			valence = 1
		"favor":
			trade.favors = int(trade.favors) - 1
			trade.last_change = "凭情改托，人情 -1"
			_adjust(person.stock, FOCAL[actor], -1)
			plan.reserved = {FOCAL[actor]: 1}
			result = "你用掉%s的 1 份人情，他留出%s 1，16:00 送到你家，原来的打算作罢。" % [ACTORS[actor], Data.item(FOCAL[actor]).name]
			valence = 1
		"decline":
			result = "你让%s照原来的打算办。没花东西，信任不变，也不算失约；16:00 他会照办。" % ACTORS[actor]
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
		"reason": str(plan.get("reason", "第 2 日起，每天 08:00 会说出新的打算。")), "effect": _effect(actor, plan, person.stock), "memory": _memory(run, actor),
		"plan": plan.duplicate(true), "policy": person.policy.duplicate(true), "token": _token(run, actor),
		"last_result": str(person.last_result), "next_decision_t": _decision_t(int(s.next_day))}

static func _effect(actor: String, plan: Dictionary, stock: Dictionary) -> String:
	if plan.is_empty(): return "还没打算；每天 08:00 说出打算，16:00 动手。"
	if plan.status == "done": return "这回已经办了，结果记在下面。"
	var focal := str(Data.item(FOCAL[actor]).name)
	if plan.response == "favor": return "16:00 把留给你的%s 1 送到你家，原来的打算作罢。" % focal
	var supported: bool = plan.response == "support"
	match str(plan.mode):
		"gather":
			var amount := _gather_gain(stock, plan, supported)
			if amount <= 0: return "16:00 存货已满，只理一理现有的货，不再花米。"
			return "16:00 自己出门找粮，米多 %d；这是他自家的口粮，不会送给你。" % amount if plan.focus == "rice" else "16:00 花米 1 张罗%s %d，留在他自家。" % [focal, amount]
		"stockpile": return "16:00 花%s 1 备货；往后的报价%s。" % [focal, "不加价" if supported else "加收米 1"]
		"guard": return "16:00 往后的报价%s。" % ("不涨，照旧可以赊欠" if supported else "加收米 1，暂停赊欠")
		"share": return "16:00 从自家拿出%s %d，送到你家 %d。" % [focal, 2 if supported else 1, 2 if supported else 1]
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
