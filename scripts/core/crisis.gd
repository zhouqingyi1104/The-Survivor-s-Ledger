extends RefCounted
## Seeded offline crises. A published warning is an immutable contract.
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const KINDS := ["well_freeze", "fuel_shortage", "herb_shortage"]
const CATALOG := {
	"well_freeze": {"title": "井口冻裂的风声", "sign": "井沿结起薄冰，汲水绳变得发硬。", "effect": "若成真，你和孩子都打不了井水，孩子也没法顺手浇菜；家里存的水不受影响。", "prepare": {"wood": 1, "firewood": 1}, "emergency": {"firewood": 2, "wood": 1}, "real_evidence": "井壁裂缝已渗水结冰，绳结冻紧；冻裂的风险属实。", "false_evidence": "薄冰只在井沿，井壁完好、绳结能解开；这次是虚惊。"},
	"fuel_shortage": {"title": "运柴中断的风声", "sign": "运柴车渐少，便道的积雪越来越厚。", "effect": "若成真，老周和过路客往后的报价都要多收米 1；已经谈好的报价、欠账和回礼不变。", "prepare": {"wood": 1, "nails": 1}, "emergency": {"wood": 2, "nails": 2}, "real_evidence": "便道承重木松动，积雪堵住车轮；运输中断的风险属实。", "false_evidence": "运柴车只是绕道过桥，便道还能通行；这次是虚惊。"},
	"herb_shortage": {"title": "药草挤兑的风声", "sign": "医馆门外排起队，往来的药篮渐空。", "effect": "若成真，阿宁往后不再卖艾草，报价还要多收米 1；已经说定的不变。", "prepare": {"mugwort": 2, "water": 1}, "emergency": {"mugwort": 3, "water": 2}, "real_evidence": "待分装药材赶不上排队的人数，艾草供给确实吃紧。", "false_evidence": "队伍是在分领已经备齐的药包，后院仍有药草；这次是虚惊。"},
}
const ACTIONS := {"investigate": ["核实风声", 30, 4], "prepare": ["提前处置", 60, 6], "aid": ["请线人帮忙", 30, 4], "ignore": ["本次观望", 0, 0], "emergency": ["事后补救", 90, 8]}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("crisis") is Dictionary or run.crisis.is_empty():
		run["crisis"] = {"schema": 1, "revision": 0, "serial": 0, "next_warning_day": maxi(2, int(run.get("pday", 0)) + 1), "pending": {}, "opening_reservation": {}, "active": {}, "history": [], "completed": [], "last_result": ""}
	return run.crisis

## Reserve before any first warning/proposal; never revise a published contract.
## No import of Opening: that module already depends on Trade and Crisis.
static func reserve_opening(run: Dictionary, kind: String, actor: String, warning_day: int) -> bool:
	if not kind in KINDS or not actor in ACTORS or not warning_day in [2, 3] or Past.daily(run): return false
	if run.get("phase", "") != "pre" or int(run.get("day", 0)) != 1 or int(run.get("hour", -1)) != State.OPEN_HOUR or run.get("loc", "") != "home" or int(run.get("t", -1)) != 0: return false
	var opening: Dictionary = run.get("opening", {})
	var birth: Dictionary = opening.get("birth", {})
	if opening.get("applied", false) or birth.get("role", "") != run.get("role", "") or birth.get("seed") != run.get("seed") or birth.get("silver") != run.get("silver") or birth.get("home", {}) != run.get("home", {}): return false
	var trade: Dictionary = run.get("trade", {})
	if not trade.get("quotes", {}).is_empty() or not trade.get("debt", {}).is_empty() or not trade.get("aid", []).is_empty(): return false
	var s := state(run)
	if int(s.serial) != 0 or not s.active.is_empty() or not s.pending.is_empty() or not s.get("opening_reservation", {}).is_empty(): return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("opening-crisis:%s:%s:%s:%s:%d" % [str(run.get("seed", 0)), str(run.get("role", "")), kind, actor, warning_day])
	s["opening_reservation"] = {"kind": kind, "actor": actor, "warning_day": warning_day, "real": rng.randf() < 0.75}
	s.next_warning_day = warning_day
	return true
static func _warning_t(day: int) -> int:
	return (day - 1) * 1440 + 120

static func _token(run: Dictionary) -> String:
	var s := state(run)
	return "crisis:%s:%s:%d" % [str(Past.state(run).id), str(s.active.get("id", "")), int(s.revision)]

static func _fact(run: Dictionary, action: String, result: String, valence := 0) -> String:
	var s := state(run)
	var a: Dictionary = s.active
	s.history.append({"day": int(run.get("pday", 0)), "kind": str(a.kind), "actor": str(a.actor), "action": action, "result": result.left(160)})
	while s.history.size() > 12: s.history.pop_front()
	s.revision = int(s.revision) + 1
	s.last_result = result
	State.note(run, "风声与危机 · " + result)
	Past.record(run, str(a.actor), "crisis_%d_%s" % [int(s.serial), action], result, valence)
	return result

static func _fallback(run: Dictionary) -> Dictionary:
	var s := state(run)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("crisis:%s:%d" % [str(run.get("seed", 0)), int(s.serial) + 1])
	var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	var names := ACTORS.keys()
	return {"kind": kind, "actor": str(names[rng.randi_range(0, names.size() - 1)]), "warning_day": int(s.next_warning_day), "real": rng.randf() < 0.75}

static func _public_active(active: Dictionary) -> Dictionary:
	var out := {}
	for key in ["id", "kind", "actor", "stage", "warning_day", "impact_t", "end_t", "investigated", "confirmed", "response", "protected", "outcome"]: out[key] = active[key]
	return out

static func _resolved(run: Dictionary, active: Dictionary, outcome: String) -> void:
	active.stage = "resolved"
	active.outcome = outcome
	active.work = {}
	var s := state(run)
	var summary := _public_active(active)
	for index in s.completed.size():
		if str(s.completed[index].id) == str(active.id):
			s.completed[index] = summary
			return
	s.completed.append(summary)
	while s.completed.size() > 6: s.completed.pop_front()

static func poll(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return ""
	var s := state(run)
	var facts := []
	var a: Dictionary = s.active
	if not a.is_empty() and not a.get("work", {}).is_empty():
		var work: Dictionary = a.work
		var busy: Dictionary = run.get("busy", {})
		if str(busy.get("kind", "")) != "crisis" or busy.get("data", {}).get("id", "") != a.id or busy.get("data", {}).get("action", "") != work.action:
			a.work = {}
			facts.append(_fact(run, "interrupted", "%s的%s被打断，没做成；花掉的料、精力和人情不退，期限前还能再安排。" % [CATALOG[a.kind].title, ACTIONS[work.action][0]]))
	if not a.is_empty() and a.stage == "warning" and int(run.t) >= int(a.impact_t):
		if bool(a.real):
			a.confirmed = "real"
			if a.protected:
				_resolved(run, a, "averted")
				facts.append(_fact(run, "averted", "%s如期来了，好在先前已经备好，没受影响。" % CATALOG[a.kind].title, 1))
			else:
				a.stage = "impact"
				facts.append(_fact(run, "impact", "%s如期来了。%s 可以事后补救，或等到第 %d 日 08:00 自己缓过来。" % [CATALOG[a.kind].title, CATALOG[a.kind].effect, int(a.warning_day) + 4], -1))
		else:
			a.confirmed = "false"
			_resolved(run, a, "false_alarm")
			facts.append(_fact(run, "false_alarm", "%s没有来，是虚惊一场。" % CATALOG[a.kind].title))
	if not a.is_empty() and a.stage == "impact" and int(run.t) >= int(a.end_t):
		_resolved(run, a, "endured")
		facts.append(_fact(run, "endured", "%s的影响过去了，该做的事和往后的报价都恢复如常；已经谈好的报价照原价。" % CATALOG[a.kind].title))
	if (a.is_empty() or a.stage == "resolved") and int(run.t) >= _warning_t(int(s.next_warning_day)):
		var reservation: Dictionary = s.get("opening_reservation", {})
		var proposal: Dictionary = reservation if not reservation.is_empty() else (s.pending if not s.pending.is_empty() else _fallback(run))
		s.serial = int(s.serial) + 1
		var day := int(s.next_warning_day)
		s.active = {"id": "crisis-%d" % int(s.serial), "kind": str(proposal.kind), "actor": str(proposal.actor), "warning_day": day, "impact_t": (day + 1) * 1440 + 720, "end_t": (day + 3) * 1440 + 120, "real": bool(proposal.real), "stage": "warning", "confirmed": "unknown", "investigated": false, "response": "", "protected": false, "outcome": "", "work": {}}
		s.next_warning_day = day + 7
		s.pending = {}
		s["opening_reservation"] = {}
		facts.append(_fact(run, "warning", "%s传来%s：%s 第 %d 日 18:00 可能应验。可以去核实、提前防备、请人帮忙，或者先看看。" % [ACTORS[s.active.actor], CATALOG[s.active.kind].title, CATALOG[s.active.kind].sign, day + 2]))
	return "\n".join(facts)

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var a: Dictionary = s.active
	if a.is_empty(): return {}
	var out := {}
	for key in ["id", "kind", "actor", "stage", "confirmed", "investigated", "response", "protected", "outcome", "warning_day", "impact_t", "end_t"]: out[key] = a[key]
	var catalog: Dictionary = CATALOG[a.kind]
	out["title"] = catalog.title
	out["sign"] = catalog.sign
	out["source"] = ACTORS[a.actor]
	out["token"] = _token(run)
	out["evidence"] = "" if a.confirmed == "unknown" else str(catalog.real_evidence if a.confirmed == "real" else catalog.false_evidence)
	out["effect"] = catalog.effect
	out["remaining_minutes"] = maxi(0, int(a.impact_t if a.stage == "warning" else a.end_t) - int(run.get("t", 0))) if a.stage != "resolved" else 0
	out["work"] = a.work.duplicate(true)
	out["last_result"] = str(s.last_result)
	return out

static func _access_block(run: Dictionary) -> String:
	if str(run.get("phase", "")) != "post": return "尸劫开始后才能应对风声。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先回到宅院再安排。"
	if str(run.get("pending_event", "")) != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty(): return "正在忙别的事。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，无法安排。"
	return ""

static func _req(active: Dictionary, action: String) -> Dictionary:
	if action == "aid": return {"rice": 1}
	if action in ["prepare", "emergency"]: return CATALOG[active.kind][action].duplicate()
	return {}

static func _block(run: Dictionary, action: String) -> String:
	var access := _access_block(run)
	if access != "": return access
	var a: Dictionary = state(run).active
	if a.is_empty() or a.stage == "resolved": return "当前没有需要处置的危机。"
	if not ACTIONS.has(action): return "没有这个应对方式。"
	if not a.work.is_empty(): return "先前的安排还没做完。"
	if action == "emergency":
		if a.stage != "impact": return "等它真来了才能补救。"
		if int(run.t) + 90 >= int(a.end_t): return "来不及在它自己缓过来之前做完，不必再花料了。"
	else:
		if a.stage != "warning" or int(run.t) >= int(a.impact_t): return "预告的日子已过，只能事后补救。"
		if a.response == "ignore": return "你已经决定先看看，不能再核实、防备或求助了。"
		if action in ["prepare", "aid", "ignore"] and a.protected: return "这一场已经备好了，不用再备。"
		if action == "investigate" and a.investigated: return "这条风声已经核实。"
		if int(run.t) + int(ACTIONS[action][1]) >= int(a.impact_t): return "来不及在它应验前做完，另想办法吧。"
	if State.attr(run, "energy") < int(ACTIONS[action][2]): return "精力不足，需要 %d。" % int(ACTIONS[action][2])
	var req := _req(a, action)
	if not Inv.has_all(run.home, req): return "需要%s。" % Data.describe_items(req)
	if action == "aid":
		var person: Dictionary = run.get("trade", {}).get("actors", {}).get(a.actor, {})
		if int(person.get("favors", 0)) < 1: return "对方还不欠你人情，求助要 1 份人情。"
	return ""

static func options(run: Dictionary) -> Array:
	var a: Dictionary = state(run).active
	if a.is_empty(): return []
	var rows := [
		{"id": "investigate", "text": "核实风声", "hint": "30 分钟、精力 4。查完才知道真假；若是虚惊，这事就了了。"},
		{"id": "prepare", "text": "提前处置", "hint": "交出%s，60 分钟、精力 6。要在应验前做完，做完就防住了；就算是虚惊，东西也不退。" % Data.describe_items(_req(a, "prepare"))},
		{"id": "aid", "text": "请线人帮忙", "hint": "交出米 1，用掉%s的 1 份人情；30 分钟、精力 4，做完就防住了。这份人情就不能再拿来换货。" % ACTORS[a.actor]},
		{"id": "ignore", "text": "本次观望", "hint": "不花东西，但这一场不再核实、防备或求助；真来了就受着，事后还能补救。"},
		{"id": "emergency", "text": "事后补救", "hint": "交出%s，90 分钟、精力 8。要赶在它自己缓过来之前做完，做完就提前恢复。" % Data.describe_items(_req(a, "emergency"))},
	]
	for row in rows: row["block"] = _block(run, str(row.id))
	return rows

static func _spend_favor(run: Dictionary, active: Dictionary) -> void:
	var trade: Dictionary = run.trade
	var person: Dictionary = trade.actors[active.actor]
	person.favors = int(person.favors) - 1
	person.last_change = "用于请线人帮忙处理" + str(CATALOG[active.kind].title) + "，人情 -1"
	trade.revision = int(trade.revision) + 1
	var result := "用掉%s的 1 份人情求助，米 1 已交；这份人情不能再换货了。" % ACTORS[active.actor]
	trade.history.append({"day": int(run.pday), "t": int(run.t), "actor": str(active.actor), "action": "crisis_aid", "result": result})
	while trade.history.size() > 24: trade.history.pop_front()
	trade.last_result = result

static func act(run: Dictionary, action: String, token: String) -> String:
	var a: Dictionary = state(run).active
	if a.is_empty() or token != _token(run): return "情况已经变了，请重新看一遍。"
	var blocked := _block(run, action)
	if blocked != "": return blocked
	Inv.take_all(run.home, _req(a, action))
	State.add_attr(run, "energy", -int(ACTIONS[action][2]))
	if action == "aid": _spend_favor(run, a)
	if action == "ignore":
		a.response = "ignore"
		_fact(run, "ignore", "对%s，你决定先看看：没花东西，也不算失约。这一场不再核实、防备或求助；真来了，事后还能补救。" % CATALOG[a.kind].title)
		return ""
	var end := int(run.t) + int(ACTIONS[action][1])
	a.work = {"action": action, "end_t": end}
	run.busy = {"kind": "crisis", "label": str(ACTIONS[action][0]), "start": int(run.t), "end": end, "data": {"id": str(a.id), "action": action}}
	var paid := _req(a, action)
	_fact(run, "start_" + action, "你开始%s：%s，要 %d 分钟、精力 %d。%s做完才算数，被打断不退。" % [ACTIONS[action][0], CATALOG[a.kind].title, int(ACTIONS[action][1]), int(ACTIONS[action][2]), "交出%s；" % Data.describe_items(paid) if not paid.is_empty() else ""])
	return ""

static func complete(run: Dictionary, data: Dictionary) -> String:
	var a: Dictionary = state(run).active
	if a.is_empty() or str(data.get("id", "")) != a.id or a.work.is_empty() or data.get("action", "") != a.work.action or int(run.get("t", 0)) < int(a.work.end_t): return ""
	var action := str(a.work.action)
	a.work = {}
	if str(run.get("phase", "")) != "post" or a.stage == "resolved": return ""
	if action != "emergency" and (a.stage != "warning" or int(run.t) >= int(a.impact_t)):
		return _fact(run, "interrupted", "%s没能赶在应验前做完，没防住。" % ACTIONS[action][0])
	if action == "emergency" and (a.stage != "impact" or int(run.t) >= int(a.end_t)):
		return _fact(run, "interrupted", "补救没赶在它缓过来之前做完。")
	match action:
		"investigate":
			a.investigated = true
			a.confirmed = "real" if a.real else "false"
			var evidence := str(CATALOG[a.kind].real_evidence if a.real else CATALOG[a.kind].false_evidence)
			if not a.real: _resolved(run, a, "false_alarm")
			return _fact(run, "investigate", "你核实了%s：%s%s" % [CATALOG[a.kind].title, evidence, "尚有时间提前处置。" if a.real else "这事提前了了。"])
		"prepare", "aid":
			a.response = action
			a.protected = true
			return _fact(run, action, "%s做好了；%s要是真来，也伤不着你。" % [ACTIONS[action][0], CATALOG[a.kind].title], 1)
		"emergency":
			a.response = "emergency"
			_resolved(run, a, "repaired")
			return _fact(run, "emergency", "%s补救做完，影响提前过去了；已经谈好的报价和约定照旧。" % CATALOG[a.kind].title, 1)
	return ""

static func well_block(run: Dictionary) -> String:
	var a: Dictionary = state(run).active
	return "井口冻裂还没凿通，暂时打不了水，也没法顺手浇菜。" if not a.is_empty() and a.kind == "well_freeze" and a.stage == "impact" else ""

static func market_effect(run: Dictionary, actor: String) -> Dictionary:
	var a: Dictionary = state(run).active
	var out := {"price_add": 0, "omit": [], "reason": ""}
	if a.is_empty() or a.stage != "impact": return out
	if a.kind == "fuel_shortage" and actor in ["zhou", "traveler"]:
		return {"price_add": 1, "omit": [], "reason": "运柴断了，往后报价多收米 1"}
	if a.kind == "herb_shortage" and actor == "ning":
		return {"price_add": 1, "omit": ["mugwort"], "reason": "药草挤兑，往后不卖艾草、报价多收米 1"}
	return out

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var active := {}
	if not s.active.is_empty():
		active = _public_active(s.active)
	var day := int(run.get("pday", 0))
	var slot := int(s.next_warning_day)
	var can_plan: bool = str(run.get("phase", "")) in ["pre", "post"] and not Past.daily(run) and s.get("opening_reservation", {}).is_empty() and (s.active.is_empty() or s.active.stage == "resolved") and int(run.get("t", 0)) < _warning_t(slot) and slot >= maxi(2, day + 1) and slot <= day + 3
	return {"schema": 1, "next_warning_day": slot, "can_plan": can_plan, "active": active, "history": s.history.duplicate(true)}

static func valid_proposal(proposal, base_day: int) -> bool:
	if not proposal is Dictionary or proposal.size() != 4: return false
	for key in proposal:
		if not key in ["kind", "actor", "warning_day", "real"]: return false
	var day = proposal.get("warning_day")
	return proposal.get("kind", "") in KINDS and proposal.get("actor", "") in ACTORS and proposal.get("real") is bool and (day is int or day is float) and is_finite(float(day)) and float(day) == floorf(float(day)) and int(day) >= maxi(2, base_day + 1) and int(day) <= base_day + 3

static func propose(run: Dictionary, proposal, base_day: int) -> bool:
	if not valid_proposal(proposal, base_day) or not str(run.get("phase", "")) in ["pre", "post"]: return false
	var s := state(run)
	if not context(run).can_plan or int(proposal.warning_day) != int(s.next_warning_day): return false
	s.pending = proposal.duplicate(true)
	return true
