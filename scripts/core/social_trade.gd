extends RefCounted
## Local, finite daily offers. Signed debts and aid never depend on generated story.
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const GOODS := ["rice", "firewood", "wood", "water", "nails", "mugwort", "flatbread"]
const OFFERS := {
	"ning": {"price": 2, "give": {"water": 2, "mugwort": 1}, "aid_req": {"mugwort": 2}, "aid_give": {"water": 3}},
	"zhou": {"price": 3, "give": {"wood": 2, "nails": 1}, "aid_req": {"wood": 1}, "aid_give": {"firewood": 3, "nails": 1}},
	"traveler": {"price": 2, "give": {"firewood": 3}, "aid_req": {"flatbread": 2}, "aid_give": {"rice": 2}},
}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("trade") is Dictionary or run.trade.is_empty():
		var actors := {}
		for actor in ACTORS:
			var relation := int(run.get("director", {}).get("relations", {}).get(actor, 0))
			actors[actor] = {"trust": clampi(relation, -5, 5), "favors": 0, "breaches": 0, "breach_total": 0, "last_change": "此前往来折算的信任" if relation != 0 else "尚无人情往来"}
		run["trade"] = {"schema": 1, "revision": 0, "actors": actors, "quotes": {}, "debt": {}, "aid": [], "history": [], "observed": [], "last_result": ""}
	return run.trade

static func contact(run: Dictionary, actor: String) -> Dictionary:
	if not actor in ACTORS: return {}
	var out: Dictionary = state(run).actors[actor].duplicate(true)
	out["name"] = ACTORS[actor]
	return out

static func _token(run: Dictionary, actor: String) -> String:
	return "trade:%s:%s:%d:%d" % [str(Past.state(run).id), actor, int(run.get("pday", 0)), int(state(run).revision)]

static func quote(run: Dictionary, actor: String) -> Dictionary:
	if not actor in ACTORS: return {}
	var s := state(run)
	var existing: Dictionary = s.quotes.get(actor, {})
	var day := int(run.get("pday", 0))
	if existing.is_empty() or int(existing.day) != day:
		var person: Dictionary = s.actors[actor]
		var price := int(OFFERS[actor].price)
		var reasons := ["平价米 %d" % price]
		if int(person.trust) >= 3:
			price -= 1
			reasons.append("信任较深，少收米 1")
		elif int(person.trust) <= -2:
			price += 1
			reasons.append("信任不足，加收米 1")
		if int(person.breaches) > 0:
			price += int(person.breaches)
			reasons.append("未化解失约 %d 笔，加收米 %d" % [int(person.breaches), int(person.breaches)])
		var market := Crisis.market_effect(run, actor)
		price += int(market.get("price_add", 0))
		var npc_market := Npcs.market_effect(run, actor)
		price = maxi(1, price + int(npc_market.get("price_add", 0)))
		var give: Dictionary = OFFERS[actor].give.duplicate()
		for item in market.get("omit", []): give.erase(item)
		if str(market.get("reason", "")) != "": reasons.append(str(market.reason))
		if str(npc_market.get("reason", "")) != "": reasons.append(str(npc_market.reason))
		existing = {"actor": actor, "day": day, "req": {"rice": price}, "give": give, "reason": "；".join(reasons) + "。当日报价固定。", "credit_allowed": bool(npc_market.get("credit_allowed", true)), "used": false}
		s.quotes[actor] = existing
	existing["id"] = _token(run, actor)
	return existing.duplicate(true)

static func _access_block(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return "尸劫开始后才能联系。"
	if int(run.get("pday", 0)) < 2: return "第 2 日起才有纸鹤往来。"
	var minute := int(run.get("t", 0)) % 1440
	if minute < 120 or minute >= 720: return "纸鹤往来只在 08:00–18:00 间接应。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先回到宅院再联系。"
	if str(run.get("pending_event", "")) != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty(): return "正在忙别的事。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，无法联系。"
	return ""

static func _need_block(run: Dictionary, req: Dictionary) -> String:
	return "需要%s。" % Data.describe_items(req) if not Inv.has_all(run.home, req) else ""

static func _action_block(run: Dictionary, actor: String, action: String, q: Dictionary) -> String:
	var access := _access_block(run)
	if access != "": return access
	var s := state(run)
	var person: Dictionary = s.actors[actor]
	var debt: Dictionary = s.debt
	if action == "repay":
		if debt.is_empty() or str(debt.actor) != actor: return "没有欠这位联系人的账。"
		return _need_block(run, debt.req)
	if action == "compensate":
		if int(person.breaches) <= 0: return "没有需要补救的失约。"
		if not debt.is_empty() and str(debt.actor) == actor: return "先还清欠账，再补偿失约。"
		return _need_block(run, {"rice": 1})
	if not action in ["cash", "favor", "credit", "aid", "decline"]: return "没有这个往来方式。"
	if bool(q.used): return "今天这份机会已经用过，明日再来。"
	match action:
		"cash": return _need_block(run, q.req)
		"favor":
			if int(person.favors) < 1: return "对方还没有欠你的人情。"
		"credit":
			if not q.get("credit_allowed", true): return "这份报价形成时对方收紧往来，只接受现货或已有的人情；新报价条件可随之后行动改变。"
			if not debt.is_empty(): return "先清偿已有欠账，不能借新还旧。"
			if int(person.breaches) > 0: return "失约尚未补救，暂不赊欠。"
			if int(person.trust) < 2: return "信任达到 2 才愿意赊欠。"
		"aid":
			if int(person.favors) >= 3: return "人情已满 3 份，先用掉一份再互助。"
			if s.aid.size() >= 3: return "已有 3 份回礼待送，先等它们兑现。"
			return _need_block(run, OFFERS[actor].aid_req)
	return ""

static func options(run: Dictionary, actor: String) -> Array:
	if not actor in ACTORS: return []
	var q := quote(run, actor)
	var s := state(run)
	var repay_req: Dictionary = s.debt.get("req", {}) if s.debt.get("actor", "") == actor else {}
	var due := int(run.get("pday", 0)) + 2
	var rows := [
		{"id": "cash", "text": "现货交换", "hint": "交出%s，得到%s；信任 +1，耗用今日机会。" % [Data.describe_items(q.req), Data.describe_items(q.give)]},
		{"id": "favor", "text": "凭情取货", "hint": "消耗人情 1，得到%s；信任不变，耗用今日机会。" % Data.describe_items(q.give)},
		{"id": "credit", "text": "赊欠取货", "hint": "先得%s；第 %d 日 18:00 前还米 %d；逾期信任 -2、失约 +1。耗用今日机会。" % [Data.describe_items(q.give), due, int(q.req.rice) + 1]},
		{"id": "aid", "text": "送物互助", "hint": "现在交出%s，立即信任 +1、人情 +1；明日 08:00 收到%s。耗用今日机会。" % [Data.describe_items(OFFERS[actor].aid_req), Data.describe_items(OFFERS[actor].aid_give)]},
		{"id": "decline", "text": "今日婉拒", "hint": "不扣物资，信任不变；放弃这位联系人今日全部机会，明日可再联系。"},
		{"id": "repay", "text": "清偿欠账", "hint": "交出%s，清除此笔欠账；按时还款信任 +1，逾期还款不自动化解失约，不耗用今日机会。" % (Data.describe_items(repay_req) if not repay_req.is_empty() else "欠账约定的物资")},
		{"id": "compensate", "text": "补偿失约", "hint": "交出米 1，未化解失约 -1、信任 +1；累计失约保留，不耗用今日机会。"},
	]
	for row in rows: row["block"] = _action_block(run, actor, str(row.id), q)
	return rows

static func _history(run: Dictionary, actor: String, action: String, result: String) -> void:
	var s := state(run)
	s.history.append({"day": int(run.get("pday", 0)), "t": int(run.get("t", 0)), "actor": actor, "action": action, "result": result})
	while s.history.size() > 24: s.history.pop_front()
	s.last_result = result
	s.revision = int(s.revision) + 1

static func _trust(person: Dictionary, delta: int, why: String) -> void:
	person.trust = clampi(int(person.trust) + delta, -5, 5)
	person.last_change = why

static func act(run: Dictionary, actor: String, action: String, quote_id: String) -> String:
	if not actor in ACTORS: return "没有这位联系人。"
	var s := state(run)
	var q: Dictionary = s.quotes.get(actor, {})
	if q.is_empty() or int(q.day) != int(run.get("pday", 0)) or quote_id != _token(run, actor): return "这份报价已过期，请重新查看。"
	var block := _action_block(run, actor, action, q)
	if block != "": return block
	var person: Dictionary = s.actors[actor]
	var result := ""
	var valence := 1
	match action:
		"cash":
			Inv.take_all(run.home, q.req)
			Inv.add_all(run.home, q.give)
			_trust(person, 1, "现货成交，信任 +1")
			result = "交出%s，收到%s；信任 +1。今日机会已用。" % [Data.describe_items(q.req), Data.describe_items(q.give)]
		"favor":
			person.favors = int(person.favors) - 1
			Inv.add_all(run.home, q.give)
			result = "用去人情 1，收到%s；信任不变。今日机会已用。" % Data.describe_items(q.give)
		"credit":
			var due := int(run.pday) + 2
			s.debt = {"id": quote_id + ":debt", "actor": actor, "req": {"rice": int(q.req.rice) + 1}, "give": q.give.duplicate(), "due_day": due, "due_t": (due - 1) * 1440 + 720, "overdue": false}
			Inv.add_all(run.home, q.give)
			Past.record_cycle(run, actor, "promise", "pledged", "trade_%d_credit" % int(run.pday))
			result = "赊得%s，约定第 %d 日 18:00 前交还%s；约定物资固定，逾期信任 -2、失约 +1。今日机会已用。" % [Data.describe_items(q.give), due, Data.describe_items(s.debt.req)]
		"aid":
			var req: Dictionary = OFFERS[actor].aid_req
			var give: Dictionary = OFFERS[actor].aid_give
			Inv.take_all(run.home, req)
			var due := int(run.pday) + 1
			s.aid.append({"id": quote_id + ":aid", "actor": actor, "req": req.duplicate(), "give": give.duplicate(), "due_day": due, "due_t": (due - 1) * 1440 + 120})
			_trust(person, 1, "送物互助，信任 +1、人情 +1")
			person.favors = mini(3, int(person.favors) + 1)
			result = "交出%s；第 %d 日 08:00 收到%s；信任 +1、人情 +1。今日机会已用。" % [Data.describe_items(req), due, Data.describe_items(give)]
		"decline":
			result = "婉拒了%s今日的往来。不扣物资，信任不变；今日机会关闭，明日可再联系。" % ACTORS[actor]
			valence = 0
		"repay":
			var debt: Dictionary = s.debt
			var late := bool(debt.overdue) or int(run.t) >= int(debt.due_t)
			# A direct core caller cannot erase a deadline by repaying before poll.
			if late and not debt.overdue: _overdue(run)
			Inv.take_all(run.home, debt.req)
			result = "交还%s，欠账已清。" % Data.describe_items(debt.req)
			if late:
				result += "逾期失约仍在；另付补偿才可化解。"
				valence = 0
			else:
				_trust(person, 1, "按时清偿，信任 +1")
				Past.record_cycle(run, actor, "promise", "kept", "trade_%d_repay" % int(run.pday))
				result += "按时还款，信任 +1。"
			s.debt = {}
		"compensate":
			Inv.add(run.home, "rice", -1)
			person.breaches = int(person.breaches) - 1
			_trust(person, 1, "付出补偿，信任 +1、未化解失约 -1")
			result = "交出米 1，化解一笔失约，信任 +1；累计失约 %d 次仍保留。" % int(person.breach_total)
	if action in ["cash", "favor", "credit", "aid", "decline"]: q.used = true
	_history(run, actor, action, result)
	State.note(run, "纸鹤往来 · %s：%s" % [ACTORS[actor], result])
	Past.record(run, actor, "trade_%d_%s" % [int(run.pday), action], "你曾与%s往来：%s" % [ACTORS[actor], result], valence)
	return ""

static func _overdue(run: Dictionary) -> String:
	var s := state(run)
	var debt: Dictionary = s.debt
	if debt.is_empty() or debt.overdue: return ""
	debt.overdue = true
	var person: Dictionary = s.actors[debt.actor]
	person.breaches = mini(3, int(person.breaches) + 1)
	person.breach_total = mini(100000, int(person.breach_total) + 1)
	_trust(person, -2, "欠账到期未还，信任 -2、失约 +1")
	var result := "对%s的%s欠账已过第 %d 日 18:00 期限；没有自动扣库存。信任 -2、失约 +1，清偿后仍需补偿。" % [ACTORS[debt.actor], Data.describe_items(debt.req), int(debt.due_day)]
	_history(run, str(debt.actor), "overdue", result)
	State.note(run, "纸鹤往来 · " + result)
	Past.record(run, str(debt.actor), "trade_overdue_%d" % int(debt.due_day), "你曾未能按期向%s清偿%s。" % [ACTORS[debt.actor], Data.describe_items(debt.req)], -1)
	Past.record_cycle(run, str(debt.actor), "breach", "broken", "trade_overdue_%d" % int(debt.due_day))
	return result

static func poll(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return ""
	var s := state(run)
	var facts := []
	var remaining := []
	for aid in s.aid:
		if int(run.get("t", 0)) < int(aid.due_t):
			remaining.append(aid)
			continue
		Inv.add_all(run.home, aid.give)
		var result := "%s按约送来%s，互助回礼已兑现。" % [ACTORS[aid.actor], Data.describe_items(aid.give)]
		_history(run, str(aid.actor), "aid_delivered", result)
		State.note(run, "纸鹤往来 · " + result)
		Past.record(run, str(aid.actor), "trade_delivery_%d" % int(aid.due_day), "你曾收到%s按约送来的%s。" % [ACTORS[aid.actor], Data.describe_items(aid.give)], 1)
		facts.append(result)
	s.aid = remaining
	if not s.debt.is_empty() and not s.debt.overdue and int(run.get("t", 0)) >= int(s.debt.due_t):
		facts.append(_overdue(run))
	return "\n".join(facts)

static func influence(run: Dictionary, actor: String, delta: int, source: String) -> void:
	if not actor in ACTORS or delta == 0: return
	var person: Dictionary = state(run).actors[actor]
	_trust(person, delta, source.left(100))
	_history(run, actor, "influence", source.left(100) + "（信任 %+d）" % delta)

static func observe_neighbor(run: Dictionary, choice: String) -> void:
	var effects := {"donate_home": [3, 1, 0], "deliver": [3, 1, 0], "refuse": [-1, 0, 0], "keep": [-2, 0, 1], "deadline": [-2, 0, 1], "share": [1, 1, 0], "seal": [-1, 0, 0]}
	if not effects.has(choice): return
	var s := state(run)
	if choice in s.observed: return
	s.observed.append(choice)
	var person: Dictionary = s.actors.ning
	var effect: Array = effects[choice]
	var labels := {"donate_home": "把家中药交给阿宁", "deliver": "按约把取回的药送到阿宁手中", "refuse": "没有应下阿宁的求药", "keep": "把答应送给阿宁的药留给自己", "deadline": "答应取药却没能按期送到", "share": "把守庄人药账交给阿宁共同追查", "seal": "封存药账，没有交给阿宁"}
	_trust(person, int(effect[0]), "隔墙求药：" + str(labels[choice]))
	person.favors = mini(3, int(person.favors) + int(effect[1]))
	person.breaches = mini(3, int(person.breaches) + int(effect[2]))
	person.breach_total = mini(100000, int(person.breach_total) + int(effect[2]))
	_history(run, "ning", "neighbor_" + choice, "隔墙求药的实际选择影响往来：信任 %+d、人情 %+d、失约 %+d。" % [int(effect[0]), int(effect[1]), int(effect[2])])

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var actors := {}
	for actor in ACTORS:
		var p: Dictionary = s.actors[actor]
		var q: Dictionary = s.quotes.get(actor, {})
		actors[actor] = {"trust": int(p.trust), "favors": int(p.favors), "breaches": int(p.breaches), "breach_total": int(p.breach_total), "available": int(run.get("pday", 0)) >= 2 and (int(q.get("day", -1)) != int(run.get("pday", 0)) or not q.get("used", false))}
	return {"schema": 1, "actors": actors, "debt": s.debt.duplicate(true), "aid": s.aid.duplicate(true)}
