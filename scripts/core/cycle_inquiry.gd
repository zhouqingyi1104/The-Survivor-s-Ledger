extends RefCounted
## Old choices open questions. Only completed work creates this life's proof.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const KINDS := ["promise", "breach", "rescue"]
const TITLES := {"promise": "隔世旧诺", "breach": "失约的回声", "rescue": "旧日伸出的手"}
const STAGES := {"sealed": "残梦尚未浮现", "lead": "已有旧梦，待今世查访", "interviewed": "查访完成，待对照账页", "verified": "今世已查证，待选择", "working": "正在兑现今世选择", "resolved": "今世已处理", "expired": "已错过查访期限"}
const CUES := ["old_note", "familiar_dream", "folded_page"]
const ROUTES := {
	"renew": {"kind": "promise", "name": "以今世行动续约", "req": {"rice": 1, "wood": 1}, "silver": 0, "minutes": 60, "energy": 6, "trust": 2, "favors": 1, "days": 1, "need": {"water": 2}, "stable": {"firewood": 1}},
	"small_pact": {"kind": "promise", "name": "另订一份小额新约", "req": {"rice": 1}, "silver": 0, "minutes": 30, "energy": 4, "trust": 1, "favors": 0, "days": 2, "need": {"water": 1}, "stable": {"wood": 1}},
	"pay_repair": {"kind": "breach", "name": "以今世赠物修补相处", "req": {"rice": 2, "water": 1}, "silver": 0, "minutes": 60, "energy": 6, "trust": 2, "favors": 1, "days": 2, "need": {"wood": 1}, "stable": {"firewood": 1}},
	"cash_restart": {"kind": "breach", "name": "先付现款，重新认识", "req": {"rice": 1}, "silver": 300, "minutes": 30, "energy": 4, "trust": 1, "favors": 0, "days": 1, "need": {"nails": 1}, "stable": {"water": 1}},
	"help_again": {"kind": "rescue", "name": "再助眼前的人", "req": {"mugwort": 2, "water": 1}, "silver": 0, "minutes": 60, "energy": 6, "trust": 2, "favors": 1, "days": 1, "need": {"rice": 2}, "stable": {"wood": 1}},
	"mutual_help": {"kind": "rescue", "name": "约定彼此互助", "req": {"rice": 1, "firewood": 1}, "silver": 0, "minutes": 45, "energy": 5, "trust": 1, "favors": 1, "days": 2, "need": {"mugwort": 2}, "stable": {"water": 2}},
}

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _day(run: Dictionary) -> int:
	return maxi(1, int(run.get("t", 0)) / 1440 + 1)

static func _source(value, generation: int, life_id: String) -> bool:
	if not value is Dictionary or value.size() != 8 or not value.get("actor", "") in ACTORS or not value.get("kind", "") in KINDS: return false
	if Past._cycle_source(value, generation - 1).is_empty(): return false
	if not _integer(value.get("source_life"), 1, generation - 1) or not _integer(value.get("day"), 1, 100000): return false
	if not value.get("source_id") is String or value.source_id.is_empty() or value.source_id.length() > 80 or value.source_id == life_id: return false
	if not value.get("fact_id") is String or value.fact_id.is_empty() or value.fact_id.length() > 48 or not value.get("fact") is String or value.fact.is_empty() or value.fact.length() > 160: return false
	return value.get("status", "") in {"promise": ["pledged", "kept"], "breach": ["broken"], "rescue": ["helped"]}[value.kind]

static func state(run: Dictionary) -> Dictionary:
	if not run.get("cycle_inquiry") is Dictionary: run["cycle_inquiry"] = {"schema": 1, "sources": [], "legacy": true, "closed": true}
	var s: Dictionary = run.cycle_inquiry
	for key in {"schema": 1, "revision": 0, "sources": [], "cases": [], "work": {}, "history": [], "last_result": "", "serial": 0}:
		if not s.has(key): s[key] = {"schema": 1, "revision": 0, "sources": [], "cases": [], "work": {}, "history": [], "last_result": "", "serial": 0}[key]
	if not s.cases is Array: s.cases = []
	if not s.work is Dictionary: s.work = {}
	if not s.history is Array: s.history = []
	if not _integer(s.revision, 0, 144000000): s.revision = 0
	if not _integer(s.serial, 0, 144000000): s.serial = 0
	while s.history.size() > 12: s.history.pop_front()
	if not s.get("initialized", false):
		s["initialized"] = true
		var p := Past.state(run)
		var seen := []
		if not Past.daily(run) and not s.get("legacy", false) and not s.get("closed", false) and s.sources is Array:
			for source in s.sources:
				if not _source(source, int(p.get("generation", 0)), str(p.id)) or source.actor in seen: continue
				if s.cases.size() >= 2: break
				var index: int = s.cases.size()
				var rng := RandomNumberGenerator.new()
				rng.seed = hash("cycle-inquiry:%s:%s:%s:%s" % [str(run.get("seed", 0)), source.actor, source.kind, source.source_id])
				var day := 3 + index * 3
				s.cases.append({"id": "cycle:%s:%s" % [str(p.id), source.actor], "actor": source.actor, "kind": source.kind, "status": source.status, "source": source.duplicate(true), "stage": "sealed", "publish_day": day, "deadline_t": -1, "cue": "old_note", "private_condition": "need" if rng.randf() < 0.5 else "stable", "evidence": {}, "route": "", "delivery": {}, "last_result": ""})
				seen.append(source.actor)
	return s

static func _enabled(run: Dictionary) -> bool:
	return not Past.daily(run) and not state(run).get("closed", false) and not state(run).get("legacy", false)

static func _token(run: Dictionary) -> String:
	return "cycle:%s:%d" % [str(Past.state(run).id), int(state(run).revision)]

static func _case(run: Dictionary, id: String) -> Dictionary:
	for c in state(run).cases:
		if c.get("id", "") == id: return c
	return {}

static func _fact(run: Dictionary, c: Dictionary, action: String, result: String) -> String:
	var s := state(run)
	s.history.append({"day": _day(run), "actor": str(c.actor), "case_id": str(c.id), "action": action.left(32), "result": result.left(240)})
	while s.history.size() > 12: s.history.pop_front()
	s.revision = int(s.revision) + 1
	s.last_result = result.left(240)
	c.last_result = result.left(240)
	State.note(run, "轮回调查 · " + result)
	return result

static func _same_busy(run: Dictionary, work: Dictionary) -> bool:
	var busy: Dictionary = run.get("busy", {})
	return busy.get("kind", "") == "cycle_inquiry" and busy.get("data", {}).get("id", "") == work.get("id", "") and busy.get("data", {}).get("case_id", "") == work.get("case_id", "") and busy.get("data", {}).get("action", "") == work.get("action", "")

static func _access(run: Dictionary) -> String:
	if not _enabled(run): return "这一世没有可查的旧案（每日一局里不查前世）。"
	if run.get("phase", "") != "post": return "尸劫降临后才能查访。"
	if State.attr(run, "hp") <= 0: return "已经无法继续今世查访。"
	if run.get("pending_event", "") != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前事件或夜战。"
	if run.get("sleeping", false): return "正在休息。"
	if not run.get("busy", {}).is_empty() or not state(run).work.is_empty(): return "正在忙别的事。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先回宅院再查访。"
	if not run.get("fight", {}).is_empty() or not run.get("night", {}).get("done", true): return "先结束眼前的尸潮。"
	var minute := int(run.get("t", 0)) % 1440
	if minute < 120 or minute >= 720: return "查访与账页核对只在 08:00 至 18:00 进行。"
	return ""

static func _quiet(run: Dictionary) -> bool:
	if run.get("phase", "") != "post" or State.attr(run, "hp") <= 0: return false
	if run.get("pending_event", "") != "" or run.get("sleeping", false) or not run.get("busy", {}).is_empty() or not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return false
	if run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty() or not run.get("fight", {}).is_empty() or not run.get("night", {}).get("done", true): return false
	return int(run.get("t", 0)) % 1440 >= 120 and int(run.get("t", 0)) % 1440 < 720

static func _fragment(run: Dictionary, c: Dictionary) -> bool:
	for memory in Past.public_memories(run):
		if memory.get("actor", "") == c.actor and memory.get("life", -1) == c.source.source_life and memory.get("fact_id", "") == c.source.fact_id: return true
	return false

static func _evidence(c: Dictionary) -> Dictionary:
	var condition: String = c.private_condition
	var text := "%s的账页上有一笔急着补的缺口，新约会先拿去补它。" % ACTORS[c.actor] if condition == "need" else "%s的账页还算稳当，可以照常订一份小约。" % ACTORS[c.actor]
	return {"condition": condition, "text": text}

static func _spec(c: Dictionary, action: String) -> Dictionary:
	if action == "inquire": return {"name": "宅院查访", "req": {}, "silver": 0, "minutes": 30, "energy": 4}
	if action == "verify": return {"name": "对照今世账页", "req": {"rice": 1}, "silver": 0, "minutes": 45, "energy": 5}
	if action == "verify_fragment": return {"name": "与本人碎片互证", "req": {"water": 1}, "silver": 0, "minutes": 30, "energy": 5}
	if ROUTES.has(action) and ROUTES[action].kind == c.kind: return ROUTES[action]
	return {}

static func _allowed(c: Dictionary) -> Array:
	match c.stage:
		"lead": return ["inquire", "decline"]
		"interviewed": return ["verify", "verify_fragment", "decline"]
		"verified":
			return {"promise": ["renew", "small_pact", "decline"], "breach": ["pay_repair", "cash_restart", "decline"], "rescue": ["help_again", "mutual_help", "decline"]}[c.kind]
	return []

static func _block(run: Dictionary, c: Dictionary, action: String) -> String:
	var access := _access(run)
	if access != "": return access
	if not action in _allowed(c): return "眼下还不能这样选。"
	if int(run.get("t", 0)) >= int(c.deadline_t): return "这宗旧案的查访期限已经过了。"
	if action == "decline": return ""
	if action == "verify_fragment" and not _fragment(run, c): return "对方还没记起这一段前世，没法互相印证。"
	var spec := _spec(c, action)
	if spec.is_empty(): return "没有这个调查办法。"
	if int(run.t) + int(spec.minutes) > int(c.deadline_t): return "来不及在截止前做完（正好在截止那一刻做完也算）。"
	if int(run.t) % 1440 + int(spec.minutes) > 720: return "来不及在 18:00 前完成，明早可继续。"
	if State.attr(run, "energy") < int(spec.energy): return "精力不足，需要 %d。" % int(spec.energy)
	if int(run.get("silver", 0)) < int(spec.silver): return "银钱不足，需要 %d 文。" % int(spec.silver)
	if not Inv.has_all(run.home, spec.req): return "需要%s。" % Data.describe_items(spec.req)
	return ""

static func _cost(spec: Dictionary) -> String:
	return ("%d 文，" % int(spec.silver) if int(spec.silver) > 0 else "") + (Data.describe_items(spec.req) + "；" if not spec.req.is_empty() else "无物资消耗；") + "%d 分钟、精力 %d。" % [int(spec.minutes), int(spec.energy)]

static func _hint(c: Dictionary, action: String) -> String:
	if action == "decline": return "放下这宗旧案：不花东西，信任 -1、心神 +2；放下就不能再续了。"
	var spec := _spec(c, action)
	var text := _cost(spec) + "做完才算数，被打断不退。"
	if action == "inquire": return text + "查访一遍，记下线索；还不算查实。"
	if action == "verify": return text + "查清对方这一世的光景，才知道能订什么约、换什么回礼。"
	if action == "verify_fragment": return text + "拿对方自己记起的那一段对一对；对完才算查实。"
	var condition := str(c.evidence.get("condition", ""))
	var give: Dictionary = spec.get(condition, {})
	return text + "信任 +%d（最多 5）、人情 +%d（最多 3）；做完 %d 日后的 08:00 收到%s。" % [int(spec.trust), int(spec.favors), int(spec.days), Data.describe_items(give)]

static func act(run: Dictionary, case_id: String, action: String, token: String) -> String:
	if token != _token(run): return "情况已经变了，请重新看一遍。"
	var c := _case(run, case_id)
	if c.is_empty(): return "没有这宗今世旧案。"
	var block := _block(run, c, action)
	if block != "": return block
	if action == "decline":
		c.stage = "resolved"
		c.route = "decline"
		if c.get("attempted", false): Past.record_cycle(run, str(c.actor), "breach", "broken", "cycle_%s_broken" % str(c.kind))
		Trade.influence(run, str(c.actor), -1, "轮回调查：没有续旧约，暂时疏远了")
		State.add_attr(run, "mood", 2)
		_fact(run, c, action, "你选择%s：不花东西，信任 -1、心神 +2。前世的约，不算这一世的账。" % {"promise": "不续旧诺", "breach": "拒背旧债", "rescue": "各顾自家"}[c.kind])
		return ""
	var spec := _spec(c, action)
	Inv.take_all(run.home, spec.req)
	c["contacted"] = true
	run.silver = int(run.get("silver", 0)) - int(spec.silver)
	State.add_attr(run, "energy", -int(spec.energy))
	var s := state(run)
	s.serial = int(s.serial) + 1
	var id := "cycle-work:%s:%d" % [str(Past.state(run).id), int(s.serial)]
	s.work = {"id": id, "case_id": case_id, "action": action, "label": str(spec.name), "start_t": int(run.t), "end_t": int(run.t) + int(spec.minutes), "prior_stage": str(c.stage), "paid": spec.req.duplicate(), "silver": int(spec.silver)}
	if ROUTES.has(action): c.stage = "working"
	if ROUTES.has(action): c["attempted"] = true
	run.busy = {"kind": "cycle_inquiry", "label": str(spec.name), "start": int(run.t), "end": int(s.work.end_t), "data": {"id": id, "case_id": case_id, "action": action}}
	_fact(run, c, "start_" + action, "开始%s：%s 做完才算数。" % [str(spec.name), _cost(spec)])
	return ""

static func poll(run: Dictionary) -> String:
	if not _enabled(run): return ""
	var s := state(run)
	var facts := []
	if not s.work.is_empty() and (run.get("phase", "") != "post" or State.attr(run, "hp") <= 0 or not _same_busy(run, s.work)):
		var work: Dictionary = s.work
		var c := _case(run, str(work.case_id))
		if not c.is_empty():
			if c.stage == "working": c.stage = str(work.prior_stage)
			facts.append(_fact(run, c, "interrupted", "%s被打断，没查到东西，也没有回礼；花掉的不退。" % str(work.label)))
		if _same_busy(run, work): run.busy = {}
		s.work = {}
	if run.get("phase", "") != "post" or State.attr(run, "hp") <= 0: return "\n".join(facts)
	for c in s.cases:
		var delivery: Dictionary = c.delivery
		if not delivery.is_empty() and not delivery.done and int(run.get("t", 0)) >= int(delivery.due_t):
			Inv.add_all(run.home, delivery.give)
			delivery.done = true
			facts.append(_fact(run, c, "delivery", "%s按新约送来了%s。" % [ACTORS[c.actor], Data.describe_items(delivery.give)]))
		if c.stage in ["lead", "interviewed", "verified", "working"] and int(run.get("t", 0)) >= int(c.deadline_t):
			var finishing: bool = not s.work.is_empty() and s.work.case_id == c.id and int(s.work.end_t) == int(run.t) and int(run.t) == int(c.deadline_t) and _same_busy(run, s.work)
			if not finishing:
				if not s.work.is_empty() and s.work.case_id == c.id:
					if _same_busy(run, s.work): run.busy = {}
					s.work = {}
				c.stage = "expired"
				c.route = "expired"
				if c.get("attempted", false): Past.record_cycle(run, str(c.actor), "breach", "broken", "cycle_%s_broken" % str(c.kind))
				if c.get("contacted", false): Trade.influence(run, str(c.actor), -1, "轮回调查期限已过，查访后没有再来往")
				facts.append(_fact(run, c, "expired", "%s的查访期限过了；%s。" % [ACTORS[c.actor], "联系过却没了下文，信任 -1" if c.get("contacted", false) else "只是你自己的旧梦，信任不变"]))
		if c.stage == "sealed" and _day(run) >= int(c.publish_day) and _quiet(run):
			c.stage = "lead"
			c.publish_day = _day(run)
			c.deadline_t = (int(c.publish_day) + 4) * 1440 + 720
			facts.append(_fact(run, c, "publish", "%s浮现一段%s的旧梦，这只是你自己的线索。第 %d 日 18:00 前，可以在宅院里查访、对一对这一世的账。" % [TITLES[c.kind], ACTORS[c.actor], int(c.deadline_t) / 1440 + 1]))
	return "\n".join(facts)

static func complete(run: Dictionary, data: Dictionary) -> String:
	var s := state(run)
	if not _enabled(run):
		s.work = {}
		return ""
	var work: Dictionary = s.work
	if work.is_empty() or data.get("id", "") != work.id or data.get("case_id", "") != work.case_id or data.get("action", "") != work.action or int(run.get("t", 0)) < int(work.end_t): return ""
	# Post clears its completed busy slot before invoking the module callback.
	if not run.get("busy", {}).is_empty() and not _same_busy(run, work): return ""
	var c := _case(run, str(work.case_id))
	if c.is_empty(): return ""
	s.work = {}
	if run.get("phase", "") != "post" or State.attr(run, "hp") <= 0 or int(run.t) > int(c.deadline_t):
		if c.stage == "working": c.stage = str(work.prior_stage)
		return _fact(run, c, "interrupted", "%s没赶在期限前做完，没查到东西，也没有回礼。" % str(work.label))
	var action := str(work.action)
	if action == "inquire":
		if c.stage != "lead": return ""
		c.stage = "interviewed"
		return _fact(run, c, action, "查访完了，打听到%s这一世的账页在哪；还得亲自对一对，旧梦说明不了眼下。" % ACTORS[c.actor])
	if action in ["verify", "verify_fragment"]:
		if c.stage != "interviewed": return ""
		c.evidence = _evidence(c)
		c.stage = "verified"
		return _fact(run, c, action, "对完了：%s 可以照查明的情形另订新约。" % str(c.evidence.text))
	if not ROUTES.has(action) or c.stage != "working" or work.prior_stage != "verified" or c.evidence.is_empty(): return ""
	var spec: Dictionary = ROUTES[action]
	var condition := str(c.evidence.condition)
	Trade.influence(run, str(c.actor), int(spec.trust), "轮回调查完成：" + str(spec.name))
	var person: Dictionary = Trade.state(run).actors[c.actor]
	person.favors = mini(3, int(person.favors) + int(spec.favors))
	var npc: Dictionary = Npcs.state(run).actors.get(c.actor, {})
	if not npc.is_empty():
		for item in work.paid:
			if npc.stock.has(item): npc.stock[item] = clampi(int(npc.stock[item]) + int(work.paid[item]), 0, Npcs.STOCK_LIMIT)
	var due_day := _day(run) + int(spec.days)
	c.delivery = {"due_t": (due_day - 1) * 1440 + 120, "give": spec[condition].duplicate(), "done": false}
	c.stage = "resolved"
	c.route = action
	var receipt_id: String = {"promise": "cycle_promise_kept", "breach": "cycle_breach_repaired", "rescue": "cycle_rescue_given"}[c.kind]
	Past.record_cycle(run, str(c.actor), "rescue" if c.kind == "rescue" else "promise", "helped" if c.kind == "rescue" else "kept", receipt_id)
	return _fact(run, c, action, "%s办完了：信任 +%d、人情 +%d（最多 3），说好第 %d 日 08:00 收到%s。" % [str(spec.name), int(spec.trust), int(spec.favors), due_day, Data.describe_items(c.delivery.give)])

static func planning(run: Dictionary) -> Dictionary:
	var s := state(run)
	var slots := []
	if _enabled(run):
		for c in s.cases:
			if c.stage != "sealed" or c.get("planned", false): continue
			slots.append({"id": c.id, "actor": c.actor, "kind": c.kind, "earliest_day": _day(run) + 1, "latest_day": _day(run) + 3, "default_day": int(c.publish_day), "cues": CUES.duplicate()})
	return {"schema": 1, "revision": int(s.revision), "slots": slots}

static func valid_rows(run: Dictionary, rows) -> bool:
	if not rows is Array or rows.size() > 2: return false
	if rows.is_empty(): return true
	if not _enabled(run): return false
	var seen := []
	for row in rows:
		if not row is Dictionary or row.size() != 3 or not row.get("case_id") is String or row.case_id in seen or not row.get("cue", "") in CUES or not _integer(row.get("day"), _day(run) + 1, _day(run) + 3): return false
		var c := _case(run, row.case_id)
		if c.is_empty() or c.stage != "sealed" or c.get("planned", false): return false
		seen.append(row.case_id)
	return true

static func accept(run: Dictionary, rows) -> bool:
	if not valid_rows(run, rows): return false
	for row in rows:
		var c := _case(run, row.case_id)
		c.publish_day = int(row.day)
		c.cue = str(row.cue)
		c["planned"] = true
	if not rows.is_empty(): state(run).revision = int(state(run).revision) + 1
	return true

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var published := []
	var work := {}
	var history := []
	if _enabled(run):
		for c in s.cases:
			if c.stage == "sealed": continue
			var item := {}
			for key in ["id", "actor", "kind", "status", "stage", "publish_day", "deadline_t", "evidence", "route", "delivery", "last_result"]: item[key] = c[key].duplicate(true) if c[key] is Dictionary else c[key]
			item["source_life"] = int(c.source.source_life)
			published.append(item)
		if not s.work.is_empty():
			for key in ["case_id", "action", "end_t", "label"]: work[key] = s.work[key]
		history = s.history.duplicate(true)
	return {"schema": 1, "revision": int(s.revision), "published": published, "work": work, "history": history, "planning": planning(run), "last_result": str(s.last_result) if _enabled(run) else ""}

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var cases := []
	if _enabled(run):
		for c in s.cases:
			var rows := []
			for action in _allowed(c):
				var text := "暂且放下，不续旧诺" if c.kind == "promise" else ("拒背旧债，放下本案" if c.kind == "breach" else "各顾自家，放下本案")
				if action != "decline": text = str(_spec(c, action).name)
				rows.append({"id": action, "text": text, "hint": _hint(c, action), "block": _block(run, c, action)})
			var evidence_text := str(c.evidence.get("text", "还没查实；你的旧梦，不会让对方也记起来。"))
			var fragment_text := "对方自己也记起了这一段，查访后可以花水 1、30 分钟互相印证。" if _fragment(run, c) else "眼下只有你的旧梦，对方还没记起这一段。"
			var clue := str(c.source.fact) + "\n" + fragment_text if c.stage != "sealed" else "旧梦还没浮现；浮现了才知道是哪一世的事。"
			var cue_text: String = {"old_note": "残页上似曾相识的字迹", "familiar_dream": "夜里再度浮现的旧梦", "folded_page": "夹在账页里的折角"}[c.cue]
			var last_result := str(c.last_result)
			if not c.delivery.is_empty(): last_result += "\n回礼：第 %d 日 08:00，%s，%s。" % [int(c.delivery.due_t) / 1440 + 1, Data.describe_items(c.delivery.give), "已送达" if c.delivery.done else "尚未送达"]
			cases.append({"id": c.id, "actor": c.actor, "kind": c.kind, "title": TITLES[c.kind] + " · " + ACTORS[c.actor], "source_label": "第 %d 世 · 记录日第 %d 日 · %s" % [int(c.source.source_life), int(c.source.day), ACTORS[c.actor]] if c.stage != "sealed" else "待残梦浮现后核对来源", "clue": clue, "evidence": c.evidence.duplicate(true), "evidence_text": evidence_text, "stage": c.stage, "stage_label": STAGES[c.stage], "deadline_text": "第 %d 日 18:00 截止（正好在那一刻做完也算）。" % (int(c.deadline_t) / 1440 + 1) if int(c.deadline_t) >= 0 else "旧梦会在第 %d 日 08:00 后清静时浮现；查访的期限到时才开始算。" % int(c.publish_day), "publish_text": cue_text, "last_result": last_result, "options": rows})
	var work: Dictionary = s.work.duplicate(true)
	if not work.is_empty(): work["remaining"] = maxi(0, int(work.end_t) - int(run.get("t", 0)))
	var summary := "还没有能查的前世约定、失约或救助；这一世做的事，会留给后来的世。"
	if not cases.is_empty():
		var active := 0
		for c in s.cases:
			if not c.stage in ["resolved", "expired"]: active += 1
		summary = "%d 宗旧案，%d 宗待处理。前世只是线索，这一世怎么相处，看你查访和新订的约。" % [cases.size(), active]
	if Past.daily(run): summary = "每日一局里不查前世旧案。"
	return {"title": "轮回调查 · 旧诺与今证", "summary": summary, "token": _token(run), "cases": cases, "history": s.history.duplicate(true) if _enabled(run) else [], "work": work, "last_result": str(s.last_result) if _enabled(run) else ""}
