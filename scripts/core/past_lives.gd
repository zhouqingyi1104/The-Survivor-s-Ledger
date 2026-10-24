extends RefCounted
## Only executed choices become past-life facts. No State/Director dependency.
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const KEEP_LIVES := 8
const KEEP_FACTS := 12
const MAX_AWAKENINGS := 2
const TRADE_GOODS := ["rice", "firewood", "wood", "water", "nails", "mugwort", "flatbread"]
const CRISIS_KINDS := ["well_freeze", "fuel_shortage", "herb_shortage"]

static func _trade_integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _trade_goods(value) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > 3: return false
	for item in value:
		if not item in TRADE_GOODS or not _trade_integer(value[item], 1, 8): return false
	return true

static func _trade_commitment(value, debt: bool) -> Dictionary:
	if not value is Dictionary or not value.get("actor", "") in ACTORS: return {}
	if not value.get("id") is String or value.id.strip_edges().is_empty() or value.id.length() > 80: return {}
	if not _trade_goods(value.get("req")) or not _trade_goods(value.get("give")): return {}
	if not _trade_integer(value.get("due_day"), 1, 100002) or not _trade_integer(value.get("due_t"), 0, 144003000): return {}
	if int(value.due_t) != (int(value.due_day) - 1) * 1440 + (720 if debt else 120): return {}
	if debt and not value.get("overdue") is bool: return {}
	var out := {"id": value.id, "actor": value.actor, "req": value.req.duplicate(), "give": value.give.duplicate(), "due_day": int(value.due_day), "due_t": int(value.due_t)}
	if debt: out["overdue"] = value.overdue
	return out

## Copy only bounded final facts; never initialize a ledger or depend on Trade/State.
static func trade_snapshot(value) -> Dictionary:
	if not value is Dictionary or value.get("schema") != 1 or not value.get("actors") is Dictionary: return {}
	var actors := {}
	for actor in ACTORS:
		var person = value.actors.get(actor)
		if not person is Dictionary or not _trade_integer(person.get("trust"), -5, 5) or not _trade_integer(person.get("favors"), 0, 3) or not _trade_integer(person.get("breaches"), 0, 3): return {}
		if not _trade_integer(person.get("breach_total"), int(person.breaches), 100000): return {}
		actors[actor] = {"trust": int(person.trust), "favors": int(person.favors), "breaches": int(person.breaches), "breach_total": int(person.breach_total)}
	if not value.get("debt") is Dictionary or not value.get("aid") is Array or value.aid.size() > 3: return {}
	var debt := _trade_commitment(value.debt, true) if not value.debt.is_empty() else {}
	if not value.debt.is_empty() and debt.is_empty(): return {}
	var aid := []
	for promise in value.aid:
		var confirmed := _trade_commitment(promise, false)
		if confirmed.is_empty(): return {}
		aid.append(confirmed)
	return {"schema": 1, "actors": actors, "debt": debt, "aid": aid}

static func _public_crisis(value) -> Dictionary:
	if not value is Dictionary or not value.get("id") is String or value.id.strip_edges().is_empty() or value.id.length() > 80: return {}
	if not value.get("kind", "") in CRISIS_KINDS or not value.get("actor", "") in ACTORS or not value.get("stage", "") in ["warning", "impact", "resolved"]: return {}
	if not _trade_integer(value.get("warning_day"), 2, 100003) or value.get("impact_t") != (int(value.warning_day) + 1) * 1440 + 720 or value.get("end_t") != (int(value.warning_day) + 3) * 1440 + 120: return {}
	if not value.get("investigated") is bool or not value.get("protected") is bool or not value.get("confirmed", "") in ["unknown", "real", "false"]: return {}
	if not value.get("response") in ["", "prepare", "aid", "ignore", "emergency"] or not value.get("outcome") in ["", "averted", "false_alarm", "endured", "repaired"]: return {}
	if value.investigated and value.confirmed == "unknown": return {}
	if value.confirmed == "false" and (value.stage != "resolved" or value.outcome != "false_alarm"): return {}
	var out := {}
	for key in ["id", "kind", "actor", "stage", "warning_day", "impact_t", "end_t", "investigated", "confirmed", "response", "protected", "outcome"]: out[key] = value[key]
	return out

## Only published facts survive a life; pending proposals and private real never do.
static func crisis_snapshot(value) -> Dictionary:
	if not value is Dictionary or value.get("schema") != 1 or not value.get("active") is Dictionary: return {}
	var completed = value.get("completed", [])
	var history = value.get("history", [])
	if not completed is Array or completed.size() > 6 or not history is Array or history.size() > 12: return {}
	var active := _public_crisis(value.active) if not value.active.is_empty() else {}
	if not value.active.is_empty() and active.is_empty(): return {}
	var settled := []
	var ids := []
	for entry in completed:
		var confirmed := _public_crisis(entry)
		if confirmed.is_empty() or confirmed.stage != "resolved" or confirmed.id in ids: return {}
		settled.append(confirmed)
		ids.append(confirmed.id)
	var facts := []
	for entry in history:
		if not entry is Dictionary or not _trade_integer(entry.get("day"), 0, 100000) or not entry.get("kind", "") in CRISIS_KINDS or not entry.get("actor", "") in ACTORS: return {}
		if not entry.get("action") is String or entry.action.strip_edges().is_empty() or entry.action.length() > 32 or not entry.get("result") is String or entry.result.strip_edges().is_empty() or entry.result.length() > 160: return {}
		facts.append({"day": int(entry.day), "kind": entry.kind, "actor": entry.actor, "action": entry.action, "result": entry.result})
	if active.get("id", "") in ids: active = {}
	if active.is_empty() and settled.is_empty() and facts.is_empty(): return {}
	return {"schema": 1, "active": active, "completed": settled, "history": facts}

static func fresh_book() -> Dictionary:
	return {"version": 1, "count": 0, "lives": [], "sealed_ids": []}

static func book(meta: Dictionary) -> Dictionary:
	if not meta.get("past_lives") is Dictionary:
		meta["past_lives"] = fresh_book()
	var b: Dictionary = meta.past_lives
	if not b.get("lives") is Array: b["lives"] = []
	if not b.get("sealed_ids") is Array: b["sealed_ids"] = []
	if not b.get("count") is int and not b.get("count") is float: b["count"] = 0
	b.count = clampi(int(b.count), 0, 999999)
	while b.lives.size() > KEEP_LIVES: b.lives.pop_front()
	return b

static func fresh_run(id := "") -> Dictionary:
	return {"id": id if id != "" else Crypto.new().generate_random_bytes(16).hex_encode(),
		"generation": 0, "trace": [], "inherited": [], "schedule": [], "awakenings": [], "archived": false}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("past_lives") is Dictionary or run.past_lives.is_empty():
		run["past_lives"] = fresh_run()
	return run.past_lives

static func daily(run: Dictionary) -> bool:
	return str(run.get("flags", {}).get("daily", "")) != ""

static func valid_fact(f) -> bool:
	return f is Dictionary and f.get("actor", "") in ACTORS and f.get("fact_id") is String and not f.fact_id.is_empty() and f.fact_id.length() <= 48 and f.get("fact") is String and not f.fact.strip_edges().is_empty() and f.fact.length() <= 160 and (f.get("valence") is int or f.get("valence") is float) and int(f.valence) in [-1, 0, 1]

static func begin(run: Dictionary, meta: Dictionary) -> void:
	var b := book(meta)
	var p := fresh_run()
	run["past_lives"] = p
	p.generation = int(b.count) + 1
	var candidates := {}
	for life in b.lives:
		if not life is Dictionary or not life.get("facts") is Array: continue
		var ordinal := int(life.get("life", 0))
		if ordinal < 1 or ordinal >= int(p.generation): continue
		for fact in life.facts:
			if not valid_fact(fact): continue
			var copy: Dictionary = fact.duplicate(true)
			copy["life"] = ordinal
			p.inherited.append(copy)
			if not candidates.has(copy.actor): candidates[copy.actor] = []
			candidates[copy.actor].append(copy)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("past-lives:%s:%s" % [run.get("seed", 0), p.id])
	var actors := candidates.keys()
	for k in range(actors.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var temporary = actors[k]
		actors[k] = actors[j]
		actors[j] = temporary
	for actor in actors:
		if p.schedule.size() >= MAX_AWAKENINGS: break
		if rng.randf() >= 0.45: continue
		var facts: Array = candidates[actor]
		p.schedule.append({"day": rng.randi_range(2, 7) + p.schedule.size(), "fact": facts[rng.randi_range(0, facts.size() - 1)].duplicate(true)})

static func record(run: Dictionary, actor: String, fact_id: String, fact: String, valence: int) -> void:
	if daily(run) or not actor in ACTORS or fact_id.is_empty() or fact.strip_edges().is_empty(): return
	var p := state(run)
	if p.archived: return
	var entry := {"actor": actor, "fact_id": fact_id.left(48), "fact": fact.left(160), "valence": clampi(valence, -1, 1), "day": maxi(0, int(run.get("pday", 0)))}
	for k in p.trace.size():
		if p.trace[k].actor == actor and p.trace[k].fact_id == entry.fact_id:
			p.trace[k] = entry
			return
	p.trace.append(entry)
	while p.trace.size() > KEEP_FACTS: p.trace.pop_front()

static func archive(run: Dictionary, meta: Dictionary) -> bool:
	var p := state(run)
	var b := book(meta)
	if p.archived or p.id in b.sealed_ids or (int(p.generation) > 0 and int(p.generation) <= int(b.count)):
		p.archived = true
		return false
	var ordinal := int(b.count) + 1
	var facts := []
	if not daily(run):
		for fact in p.trace:
			if valid_fact(fact): facts.append(fact.duplicate(true))
	var history: Array = run.get("director", {}).get("history", []).duplicate(true)
	var summary := {"role": str(run.get("role", "")), "day": int(run.get("pday", 0)),
		"mode": "每日一局" if daily(run) else ("守到死" if run.get("endless", false) else "寻常轮回"),
		"outcome": "死亡" if run.get("phase") == "dead" else ("劫满" if run.get("phase") == "ending" else "合卷"),
		"cause": str(run.get("death_cause", "")).left(160), "waves": int(run.get("waves_survived", 0)), "kills": int(run.get("kills", 0)),
		"choices": history.slice(maxi(0, history.size() - 8)), "relations": run.get("director", {}).get("relations", {}).duplicate()}
	var trade := trade_snapshot(run.get("trade", {}))
	if not trade.is_empty(): summary["trade"] = trade
	var crisis := crisis_snapshot(run.get("crisis", {}))
	if not crisis.is_empty(): summary["crisis"] = crisis
	b.lives.append({"id": p.id, "life": ordinal, "facts": facts, "summary": summary})
	b.sealed_ids.append(p.id)
	b.count = ordinal
	while b.lives.size() > KEEP_LIVES: b.lives.pop_front()
	p.generation = ordinal
	p.archived = true
	return true

static func public_memories(run: Dictionary) -> Array:
	if daily(run): return []
	return state(run).awakenings.duplicate(true)

static func awakening(run: Dictionary) -> Dictionary:
	var p := state(run)
	if daily(run) or run.get("phase", "") != "post" or int(p.generation) < 1: return {}
	if run.get("pending_event", "") != "" or run.get("sleeping", false) or not run.get("busy", {}).is_empty() or not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false) or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty() or not run.get("fight", {}).is_empty(): return {}
	var minute := int(run.get("t", 0)) % 1440
	if minute < 120 or minute >= 720: return {}
	for planned in p.schedule:
		if int(run.pday) < int(planned.day): continue
		var f: Dictionary = planned.fact
		var already := false
		for seen in p.awakenings:
			if seen.actor == f.actor: already = true
		if already: continue
		var age := int(p.generation) - int(f.life)
		if age < 1: continue
		var public := {"actor": f.actor, "life": int(f.life), "age": age, "fact_id": f.fact_id, "fact": f.fact, "response": ""}
		p.awakenings.append(public)
		var when := "上一世" if age == 1 else "%d 世前" % age
		var scene_text := "%s捎来一段难以解释的梦话。对方认不清那张脸，却说出了你曾做过的事。\n记忆碎片（%s，第 %d 日）：%s\n这是旧世的片段，今世如何相处仍由你决定。" % [ACTORS[f.actor], when, int(f.get("day", 0)), f.fact]
		return {"uid": "world:memory:%s:%s" % [p.id, f.actor], "actor": f.actor, "title": "前尘回响 · " + ACTORS[f.actor], "text": scene_text,
			"past_memory": {"actor": f.actor, "fact_id": f.fact_id, "life": int(f.life)}, "choices": [
				{"id": "acknowledge", "text": "承认这段似曾相识", "result": "你承认自己也有相似的片段，但不把旧世当作今世的债。对方愿意重新认识你。", "req": {}, "give": {}, "relation": 1, "mood": 2 if int(f.valence) > 0 else -1},
				{"id": "compensate", "text": "送出米 1，以今世行动回应", "result": "你送出一份米粮，让今世的善意落到实处。旧世的片段没有替你决定这次行动。", "req": {"rice": 1}, "give": {}, "relation": 2, "mood": 1},
				{"id": "dismiss", "text": "只当作一场旧梦", "result": "你没有追问梦的来处。对方收起这段话，与你暂时疏远了一些。", "req": {}, "give": {}, "relation": -1, "mood": 0}]}
	return {}

static func respond(run: Dictionary, event: Dictionary, choice: Dictionary) -> void:
	var source: Dictionary = event.get("past_memory", {})
	for memory in state(run).awakenings:
		if memory.actor == source.get("actor") and memory.life == source.get("life") and memory.fact_id == source.get("fact_id"):
			memory.response = str(choice.get("id", "")).left(32)
