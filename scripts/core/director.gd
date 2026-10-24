extends RefCounted
## Runtime story contracts. Model output is data, never code or arbitrary effects.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Dialogue = preload("res://scripts/core/npc_dialogue.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const GOODS := ["rice", "firewood", "wood", "water", "nails", "mugwort", "flatbread"]
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}

static func state(run: Dictionary) -> Dictionary:
	if run.get("director", {}).is_empty():
		run.director = {"session": "%s-%s" % [str(run.seed), Crypto.new().generate_random_bytes(8).hex_encode()],
			"enabled": str(run.get("flags", {}).get("daily", "")) == "", "revision": 0, "queue": [], "active": {}, "history": [],
			"promises": [], "relations": {"ning": 0, "zhou": 0, "traveler": 0}, "days": [], "source": ""}
	return run.director

static func note_choice(run: Dictionary, title: String, result: String) -> void:
	var d := state(run)
	d.revision = int(d.revision) + 1
	d.queue = [] # Unseen plans can change. Active scenes and promises cannot.
	d.history.append({"day": int(run.pday), "title": title.left(40), "result": result.left(240)})
	while d.history.size() > 12:
		d.history.pop_front()


## A background NPC update replans the future, without starving today's
## already prepared opportunity at every 08:00 announcement. Its economics
## stay fixed; local wording avoids stale claims about the new NPC decision.
static func note_world(run: Dictionary, title: String, result: String) -> void:
	var d := state(run)
	var today := []
	for event in d.queue:
		if int(event.get("day", -1)) == int(run.pday) and not int(run.pday) in d.days and str(event.get("uid", "")) != str(d.active.get("uid", "")):
			var copy: Dictionary = event.duplicate(true)
			copy["npc_rules_text"] = true
			today.append(copy)
	note_choice(run, title, result)
	d.queue = today

static func snapshot(run: Dictionary, archive: Dictionary = {}) -> Dictionary:
	var d := state(run)
	var n: Dictionary = run.get("neighbor", {})
	var stock := {}
	for id in GOODS:
		stock[id] = Inv.count(run.home, id)
	var result := {"schema": 1, "request_id": "%s-%d-%d" % [d.session, d.revision, int(run.pday)],
		"session": d.session, "revision": int(d.revision), "current_day": int(run.pday), "time": int(run.t),
		"state": {"role": str(run.role), "stock": stock, "mood": State.attr(run, "mood"),
			"neighbor": {"stage": n.get("stage", "waiting"), "resolution": n.get("resolution", ""), "ending": n.get("ending", "")},
			"relations": d.relations.duplicate(), "history": d.history.duplicate(true), "promises": d.promises.duplicate(true),
			"recollections": Past.public_memories(run), "trade": Trade.context(run), "crisis": Crisis.context(run),
			"npcs": Npc.context(run), "npc_dialogue": Dialogue.context(run), "mainline": Mainline.context(run)}}
	if not archive.is_empty() and not Past.daily(run):
		result.state["archive"] = archive.duplicate()
		result.request_id += "-m" + str(archive.get("sha256", "")).left(16)
	return result

static func keys_ok(value: Dictionary, allowed: Array) -> bool:
	for key in value:
		if not key in allowed:
			return false
	return true

static func text_ok(value, limit: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit

static func integer_ok(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func goods_ok(value, limit := 3) -> bool:
	if not value is Dictionary or value.size() > 3:
		return false
	for id in value:
		if not id in GOODS or not integer_ok(value[id], 1, limit):
			return false
	return true

static func validate(plan, base_day: int, dialogue_candidates = null) -> bool:
	if not plan is Dictionary or not keys_ok(plan, ["schema", "days", "crisis", "npc_dialogue"]) or plan.get("schema") != 1 or not plan.get("days") is Array or plan.days.size() != 3:
		return false
	if plan.has("crisis") and not Crisis.valid_proposal(plan.crisis, base_day): return false
	if plan.has("npc_dialogue") and not Dialogue.valid_rows(plan.npc_dialogue, dialogue_candidates): return false
	var used := []
	for e in plan.days:
		if not e is Dictionary or not keys_ok(e, ["day", "actor", "title", "text", "choices"]): return false
		if not integer_ok(e.get("day"), base_day + 1, base_day + 3) or e.day in used: return false
		used.append(e.day)
		if not e.get("actor", "") in ACTORS or not text_ok(e.get("title"), 24) or not text_ok(e.get("text"), 240): return false
		if not e.get("choices") is Array or e.choices.size() < 2 or e.choices.size() > 3: return false
		var exit_available := false
		var ids := []
		for c in e.choices:
			if not c is Dictionary or not keys_ok(c, ["id", "text", "result", "req", "give", "mood", "relation", "after"]): return false
			if not text_ok(c.get("id"), 24) or c.id in ids: return false
			ids.append(c.id)
			if not text_ok(c.get("text"), 32) or not text_ok(c.get("result"), 150): return false
			if not goods_ok(c.get("req", {}), 3) or not goods_ok(c.get("give", {})): return false
			if not integer_ok(c.get("mood", 0), -6, 6) or not integer_ok(c.get("relation", 0), -2, 2): return false
			var a = c.get("after", {})
			if not a is Dictionary or not keys_ok(a, ["days", "give", "text"]): return false
			if not a.is_empty() and (not integer_ok(a.get("days"), 1, 2) or not goods_ok(a.get("give")) or a.give.is_empty() or not text_ok(a.get("text"), 100)): return false
			if c.get("req", {}).is_empty(): exit_available = true
			if c.get("req", {}).is_empty() and c.get("give", {}).is_empty() and c.get("mood", 0) == 0 and c.get("relation", 0) == 0 and a.is_empty(): return false
		if not exit_available: return false
	return true

static func accept(run: Dictionary, sent: Dictionary, plan) -> bool:
	var d := state(run)
	if not run.get("phase", "") in ["pre", "post"] or not d.enabled or Past.daily(run) or sent.session != d.session or int(sent.revision) != int(d.revision) or int(run.t) < int(sent.time) or int(run.pday) > int(sent.current_day) + 3 or not validate(plan, int(sent.current_day), sent.get("state", {}).get("npc_dialogue", {})):
		return false
	if plan.has("npc_dialogue") and not Dialogue.current_rows(run, plan.npc_dialogue): return false
	if plan.has("npc_dialogue"): Dialogue.accept(run, sent.state.npc_dialogue, plan.npc_dialogue)
	d.queue = []
	if plan.has("crisis"): Crisis.propose(run, plan.crisis, int(sent.current_day))
	for e in plan.days:
		if int(e.day) >= int(run.pday) and not int(e.day) in d.days:
			var copy: Dictionary = e.duplicate(true)
			# The same generation can know a private proposal. Keep its free prose
			# out of gameplay while retaining every validated economic choice.
			if plan.has("crisis"): copy["crisis_rules_text"] = true
			copy["uid"] = "world:%s:%d" % [sent.request_id, e.day]
			d.queue.append(copy)
	d.source = "ark-plan"
	return true

static func poll(run: Dictionary) -> String:
	if run.get("phase", "") != "post": return ""
	var d := state(run)
	# Deliveries are irrevocable, including when dynamic generation is disabled.
	for p in d.promises:
		if not p.done and int(run.pday) >= int(p.day):
			Inv.add_all(run.home, p.give)
			p.done = true
			var delivery_text := "按原约送来物资" if _crisis_text_guard(run) or _mainline_text_guard(run) else str(p.text)
			State.note(run, "约定兑现 · %s：%s（%s）" % [ACTORS[p.actor], delivery_text, describe(p.give)])
			Past.record(run, str(p.actor), "delivery_%d" % int(p.day), "你曾收到%s按约送来的%s。" % [ACTORS[p.actor], describe(p.give)], 1)
	d.promises = d.promises.filter(func(p): return not p.done)
	if run.pending_event != "" or run.sleeping or not run.busy.is_empty() or not run.explore.is_empty() or run.get("neighbor_travel", false) or run.dawn_due or run.plan_due or run.wave_due or not run.wave_report.is_empty() or not run.get("fight", {}).is_empty(): return ""
	var minute := int(run.t) % 1440
	if minute < 120 or minute >= 720 or int(run.pday) in d.days: return ""
	var memory := Past.awakening(run)
	if not memory.is_empty():
		d.active = memory
		d.days.append(int(run.pday))
		while d.days.size() > 7: d.days.pop_front()
		run.pending_event = memory.uid
		note_choice(run, memory.title, memory.text)
		State.note(run, memory.title + "：" + memory.text)
		return memory.uid
	if not d.enabled: return ""
	for e in d.queue:
		if int(e.day) == int(run.pday):
			d.active = e.duplicate(true)
			d.days.append(int(run.pday))
			while d.days.size() > 7: d.days.pop_front()
			run.pending_event = e.uid
			return e.uid
	return ""

static func describe(items: Dictionary) -> String:
	return Data.describe_items(items)

static func entry(run: Dictionary) -> Dictionary:
	var event: Dictionary = state(run).active
	if event.is_empty() or event.has("past_memory") or not (event.get("crisis_rules_text", false) or event.get("npc_rules_text", false) or _crisis_text_guard(run) or _mainline_text_guard(run)):
		return event
	return _rules_text(event)


static func _crisis_text_guard(run: Dictionary) -> bool:
	var c := Crisis.state(run)
	return not c.pending.is_empty() or (not c.active.is_empty() and c.active.stage != "resolved")

static func _mainline_text_guard(run: Dictionary) -> bool:
	return bool(Mainline.context(run).get("published", false))


## Crisis evidence is authored by the rules. A model cannot disclose its private
## proposal or claim to have investigated/repaired it through unrelated prose.
static func _rules_text(event: Dictionary) -> Dictionary:
	var safe: Dictionary = event.duplicate(true)
	safe.title = "第%d日 · %s的来信" % [int(event.get("day", 0)), ACTORS[event.actor]]
	safe.text = "纸鹤捎来几种物资与人情往来的办法。交出、获得和已许下的回礼均写在选项下方，你可以自行决定。"
	for choice in safe.choices:
		var req: Dictionary = choice.get("req", {})
		var give: Dictionary = choice.get("give", {})
		var after: Dictionary = choice.get("after", {})
		choice.text = "以物相换" if not req.is_empty() and not give.is_empty() else ("交付物资，约定回礼" if not req.is_empty() and not after.is_empty() else ("交出物资" if not req.is_empty() else ("收下物资" if not give.is_empty() else "回应对方的来信")))
		choice.result = ("交出%s；" % describe(req) if not req.is_empty() else "") + effect_hint(choice)
		if not after.is_empty(): after.text = "按原约送来物资"
	return safe

static func choose(run: Dictionary, index: int) -> String:
	var d := state(run)
	var e: Dictionary = entry(run)
	if e.is_empty() or run.pending_event != e.get("uid") or index < 0 or index >= e.choices.size(): return "这件事已经处理过了。"
	var c: Dictionary = e.choices[index]
	if not Inv.has_all(run.home, c.get("req", {})): return "东西不够。"
	Inv.take_all(run.home, c.get("req", {}))
	Inv.add_all(run.home, c.get("give", {}))
	State.add_attr(run, "mood", int(c.get("mood", 0)))
	Trade.influence(run, str(e.actor), int(c.get("relation", 0)), "世情 · " + str(e.title))
	d.relations[e.actor] = clampi(int(d.relations[e.actor]) + int(c.get("relation", 0)), -10, 10)
	var result: String = c.result
	var a: Dictionary = c.get("after", {})
	if not a.is_empty():
		var due := int(run.pday) + int(a.days)
		d.promises.append({"day": due, "actor": e.actor, "give": a.give.duplicate(), "text": a.text, "done": false})
		result += "\n约定：第 %d 日收到%s。" % [due, describe(a.give)]
	if e.has("past_memory"):
		Past.respond(run, e, c)
	else:
		var facts := []
		if not c.get("req", {}).is_empty(): facts.append("你交出" + describe(c.req))
		if not c.get("give", {}).is_empty(): facts.append("对方交给你" + describe(c.give))
		if not a.is_empty(): facts.append("对方约定 %d 日后送来%s" % [int(a.days), describe(a.give)])
		if int(c.get("relation", 0)) != 0: facts.append("当时你们的关系" + ("亲近了一些" if int(c.relation) > 0 else "疏远了一些"))
		if not facts.is_empty(): Past.record(run, str(e.actor), "world_" + str(e.title).sha256_text().left(16), "你曾与%s有过一次往来：%s。" % [ACTORS[e.actor], "；".join(facts)], signi(int(c.get("relation", 0))))
	note_choice(run, str(e.title), result)
	State.note(run, "%s · %s：%s" % [ACTORS[e.actor], e.title, result])
	d.active = {}
	run.pending_event = ""
	run.event_result = result
	return ""

static func effect_hint(c: Dictionary) -> String:
	var text := ""
	if not c.get("give", {}).is_empty(): text += "获得 " + describe(c.give) + "；"
	if c.get("mood", 0) != 0: text += "心神 %+d；" % int(c.mood)
	if c.get("relation", 0) != 0: text += "关系 %+d；" % int(c.relation)
	if not c.get("after", {}).is_empty(): text += "%d 日后收到 %s。" % [c.after.days, describe(c.after.give)]
	return text
