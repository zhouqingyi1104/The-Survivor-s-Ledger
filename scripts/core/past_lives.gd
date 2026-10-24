extends RefCounted
## Only executed choices become past-life facts. No State/Director dependency.
const ACTORS := {"ning": "阿宁", "zhou": "木料场老周", "traveler": "过路客"}
const KEEP_LIVES := 8
const KEEP_FACTS := 12
const MAX_AWAKENINGS := 2
const TRADE_GOODS := ["rice", "firewood", "wood", "water", "nails", "mugwort", "flatbread"]
const CRISIS_KINDS := ["well_freeze", "fuel_shortage", "herb_shortage"]
const MAINLINE_STAGES := ["waiting", "contact", "fallback", "mortuary", "mortuary_choice", "temple", "routes", "escape_ready", "ritual_ready", "sealed", "hold", "closed", "failed", "endless"]
const MAINLINE_WORK := ["host", "self_route", "disrupt", "copy", "prepare_escape", "prepare_ritual", "prepare_light_escape", "prepare_convoy", "prepare_paper_ritual", "escape", "search_mortuary", "search_temple", "search_ritual", "return_mortuary", "return_temple"]
const IDENTITY_ROLES := ["scholar", "escort", "herbalist", "watchman"]
const IDENTITY_TAGS := ["sealed_lamps", "escaped_city", "gave_medicine", "returned_evidence"]
const IDENTITY_CAPS := {"scholar_collate": "scribe_talisman", "scholar_diagram": "paper_ritual", "escort_intercept": "", "escort_convoy": "early_convoy", "herbalist_lure": "efficient_plague", "herbalist_ink": "medicinal_talisman", "watchman_lane": "light_escape", "watchman_intel": "wave_intel"}
const IDENTITY_REQUIRED := {"scholar_diagram": "sealed_lamps", "escort_convoy": "escaped_city", "herbalist_ink": "gave_medicine", "watchman_intel": "returned_evidence"}

## Keep a bounded account of this life's actual work, never its private source IDs.
## This module cannot import Identity/State without creating a dependency cycle.
static func identity_snapshot(value) -> Dictionary:
	if not value is Dictionary or value.get("schema") != 1: return {}
	for key in value:
		if not key in ["schema", "revision", "inherited", "chosen", "completed_t", "learned", "work", "history", "serial"]: return {}
	for key in ["revision", "serial"]:
		if value.has(key) and not _trade_integer(value[key], 0, 1000000): return {}
	var inherited = value.get("inherited", [])
	if not inherited is Array or inherited.size() > 4: return {}
	var seen := []
	for source in inherited:
		if not source is Dictionary or source.size() != 3 or not source.get("tag", "") in IDENTITY_TAGS or source.tag in seen or not _trade_integer(source.get("source_life"), 1, 1000000) or not source.get("source_id") is String or source.source_id.is_empty() or source.source_id.length() > 80: return {}
		for key in source:
			if not key in ["tag", "source_life", "source_id"]: return {}
		seen.append(source.tag)
	var chosen = value.get("chosen", "")
	var completed = value.get("completed_t", -1)
	var learned = value.get("learned", [])
	var work = value.get("work", {})
	var history = value.get("history", [])
	if not chosen is String or (chosen != "" and not chosen in IDENTITY_CAPS) or not _trade_integer(completed, -1, 144000000): return {}
	if not learned is Array or learned.size() > 1 or not work is Dictionary or not history is Array or history.size() > 12: return {}
	var expected: String = IDENTITY_CAPS.get(chosen, "")
	if completed < 0 and not learned.is_empty(): return {}
	if completed >= 0 and chosen == "": return {}
	if (expected == "" and not learned.is_empty()) or (expected != "" and learned != ([expected] if completed >= 0 else [])): return {}
	var out := {"schema": 1, "chosen": chosen, "completed_t": int(completed), "learned": learned.duplicate(), "work": {}, "history": []}
	if not work.is_empty():
		if not work.get("action", "") in IDENTITY_CAPS or chosen != "" or completed >= 0 or not _trade_integer(work.get("end_t"), 0, 144000000): return {}
		out.work = {"action": work.action, "end_t": int(work.end_t)}
	for entry in history:
		if not entry is Dictionary or not _trade_integer(entry.get("day"), 1, 100000) or not _trade_integer(entry.get("t"), 0, 144000000): return {}
		if not entry.get("action") is String or entry.action.strip_edges().is_empty() or entry.action.length() > 40 or not entry.get("result") is String or entry.result.strip_edges().is_empty() or entry.result.length() > 240: return {}
		for key in entry:
			if not key in ["day", "t", "action", "result"]: return {}
		out.history.append({"day": int(entry.day), "t": int(entry.t), "action": entry.action, "result": entry.result})
	return out

static func _identity_archive(run: Dictionary) -> Dictionary:
	var raw = run.get("identity", {})
	var safe := identity_snapshot(raw)
	if safe.is_empty(): return {}
	var action: String = safe.chosen if safe.chosen != "" else str(safe.work.get("action", ""))
	if action == "": return safe
	if not action.begins_with(str(run.get("role", "")) + "_") or int(safe.completed_t) > int(run.get("t", 0)): return {}
	var story := mainline_snapshot(run.get("mainline", {}))
	if story.is_empty() or not story.evidence.mortuary: return {}
	if IDENTITY_REQUIRED.has(action):
		if daily(run): return {}
		var found := false
		var p := state(run)
		for source in raw.get("inherited", []):
			if source.tag == IDENTITY_REQUIRED[action] and int(source.source_life) < int(p.get("generation", 0)) and source.source_id != p.id: found = true
		if not found: return {}
	return safe

## Unlock from sealed structured outcomes. Markdown and free narrative are not proof.
static func identity_inheritance(meta: Dictionary) -> Array:
	var b := book(meta)
	var id_counts := {}
	var ordinal_counts := {}
	for life in b.lives:
		if not life is Dictionary: continue
		var id = life.get("id", "")
		var ordinal = life.get("life", -1)
		if id is String: id_counts[id] = int(id_counts.get(id, 0)) + 1
		if _trade_integer(ordinal, 1, int(b.count)): ordinal_counts[int(ordinal)] = int(ordinal_counts.get(int(ordinal), 0)) + 1
	var latest := {}
	for life in b.lives:
		if not life is Dictionary: continue
		var id = life.get("id", "")
		var ordinal = life.get("life", -1)
		if not id is String or id.is_empty() or id.length() > 80 or not id in b.sealed_ids or int(id_counts.get(id, 0)) != 1: continue
		if not _trade_integer(ordinal, 1, int(b.count)) or int(ordinal_counts.get(int(ordinal), 0)) != 1: continue
		var summary = life.get("summary", {})
		if not summary is Dictionary or not summary.get("role", "") in IDENTITY_ROLES or not summary.get("mode", "") in ["寻常轮回", "守到死"] or not _trade_integer(summary.get("day"), 0, 100000): continue
		var tags := []
		var story := mainline_snapshot(summary.get("mainline", {}))
		if not story.is_empty():
			if story.evidence.mortuary: tags.append("returned_evidence")
			var sealed_at := int(story.interventions.ritual_t)
			if story.evidence.mortuary and story.evidence.temple and sealed_at >= 0 and sealed_at < mini(18 * 1440 + 720, int(summary.day) * 1440): tags.append("sealed_lamps")
			if story.evidence.mortuary and story.evidence.temple and story.stage == "closed" and story.route == "escape" and story.ending.get("kind", "") == "escape" and story.ending.get("title", "") == "离城余生" and summary.get("outcome", "") == "离城余生" and (int(summary.day) in [18, 19] or (int(summary.day) == 17 and story.get("escape_method", "") == "convoy")): tags.append("escaped_city")
		var facts = life.get("facts", [])
		if facts is Array and facts.size() <= KEEP_FACTS:
			for fact in facts:
				if valid_fact(fact) and fact.actor == "ning" and fact.fact_id == "medicine" and _trade_integer(fact.valence, 1, 1) and _trade_integer(fact.get("day"), 1, int(summary.day)):
					tags.append("gave_medicine")
					break
		for tag in tags:
			if int(latest.get(tag, {}).get("source_life", 0)) < int(ordinal): latest[tag] = {"tag": tag, "source_life": int(ordinal), "source_id": id}
	var result := []
	for tag in IDENTITY_TAGS:
		if latest.has(tag): result.append(latest[tag])
	return result

## Raw rule state only; no imports that would form State/Director dependency cycles.
static func mainline_snapshot(value) -> Dictionary:
	if not value is Dictionary or value.get("schema") != 1 or not value.get("stage", "") in MAINLINE_STAGES: return {}
	if not _trade_integer(value.get("start_day"), 1, 100001) or not value.get("route", "") in ["", "hold", "escape", "ritual"]: return {}
	var evidence = value.get("evidence")
	var interventions = value.get("interventions")
	if not evidence is Dictionary or not evidence.get("mortuary") is bool or not evidence.get("temple") is bool: return {}
	if not interventions is Dictionary or not _trade_integer(interventions.get("disrupt_t"), -1, 144000000) or not _trade_integer(interventions.get("ritual_t"), -1, 144000000): return {}
	var result := {"schema": 1, "start_day": int(value.start_day), "stage": value.stage, "evidence": {"mortuary": evidence.mortuary, "temple": evidence.temple},
		"route": value.route, "interventions": {"disrupt_t": int(interventions.disrupt_t), "ritual_t": int(interventions.ritual_t)}, "ending": {}, "work": {}, "history": []}
	if value.has("escape_method"):
		if not value.escape_method in ["normal", "light", "convoy"]: return {}
		result["escape_method"] = value.escape_method
	if value.has("ritual_method"):
		if not value.ritual_method in ["normal", "paper"]: return {}
		result["ritual_method"] = value.ritual_method
	var ending = value.get("ending", {})
	if not ending is Dictionary: return {}
	if not ending.is_empty():
		if not ending.get("kind", "") in ["hold", "escape", "ritual"] or not ending.get("title") is String or ending.title.is_empty() or ending.title.length() > 40 or not ending.get("text") is String or ending.text.is_empty() or ending.text.length() > 240: return {}
		if not _trade_integer(ending.get("bonus"), 0, 10) or not ending.get("can_continue") is bool or ending.bonus != (0 if ending.kind == "escape" else 10) or ending.can_continue != (ending.kind == "hold"): return {}
		result.ending = {"kind": ending.kind, "title": ending.title, "text": ending.text, "bonus": int(ending.bonus), "can_continue": ending.can_continue}
	var work = value.get("work", {})
	if not work is Dictionary: return {}
	if not work.is_empty():
		if not work.get("action", "") in MAINLINE_WORK or not _trade_integer(work.get("end_t"), 0, 144000000): return {}
		result.work = {"action": work.action, "end_t": int(work.end_t)}
	var history = value.get("history", [])
	if not history is Array or history.size() > 16: return {}
	for entry in history:
		if not entry is Dictionary or not _trade_integer(entry.get("day"), 1, 100000) or not _trade_integer(entry.get("t"), 0, 144000000): return {}
		if not entry.get("action") is String or entry.action.is_empty() or entry.action.length() > 32 or not entry.get("result") is String or entry.result.is_empty() or entry.result.length() > 240: return {}
		result.history.append({"day": int(entry.day), "t": int(entry.t), "action": entry.action, "result": entry.result})
	return result

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


## Final public NPC facts only. Dialogue caches and unawakened memories are not
## evidence of an encounter, and old-life reservations are not new-life gifts.
static func npc_snapshot(value) -> Dictionary:
	if not value is Dictionary or value.get("schema") != 1 or not value.get("actors") is Dictionary: return {}
	var focal := {"ning": "mugwort", "zhou": "wood", "traveler": "firewood"}
	var actors := {}
	for actor in ACTORS:
		var person = value.actors.get(actor)
		if not person is Dictionary or not person.get("stock") is Dictionary or person.stock.size() != 2: return {}
		var stock := {}
		for item in ["rice", focal[actor]]:
			if not _trade_integer(person.stock.get(item), 0, 20): return {}
			stock[item] = int(person.stock[item])
		var policy = person.get("policy")
		if not policy is Dictionary or not _trade_integer(policy.get("price_add"), 0, 1) or not policy.get("credit_allowed") is bool or not policy.get("reason") is String or policy.reason.length() > 240: return {}
		var plan = person.get("plan", {})
		if not plan is Dictionary: return {}
		var public_plan := {}
		if not plan.is_empty():
			if not _trade_integer(plan.get("day"), 2, 100000) or plan.get("due_t") != (int(plan.day) - 1) * 1440 + 600: return {}
			if not plan.get("mode", "") in ["gather", "stockpile", "guard", "share"] or not plan.get("response", "") in ["", "support", "favor", "decline"] or not plan.get("status", "") in ["pending", "done"]: return {}
			for key in ["day", "due_t", "mode", "response", "status"]: public_plan[key] = plan[key]
		actors[actor] = {"stock": stock, "plan": public_plan, "policy": {"price_add": int(policy.price_add), "credit_allowed": policy.credit_allowed, "reason": policy.reason}}
	var history = value.get("history", [])
	if not history is Array or history.size() > 12: return {}
	var facts := []
	for entry in history:
		if not entry is Dictionary or not entry.get("actor", "") in ACTORS or not _trade_integer(entry.get("day"), 0, 100000) or not _trade_integer(entry.get("t"), 0, 144000000): return {}
		if not entry.get("action") is String or entry.action.is_empty() or entry.action.length() > 40 or not entry.get("result") is String or entry.result.is_empty() or entry.result.length() > 240: return {}
		facts.append({"day": int(entry.day), "t": int(entry.t), "actor": entry.actor, "action": entry.action, "result": entry.result})
	return {"schema": 1, "actors": actors, "history": facts}

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
	# Fixed at birth; an old save never learns from lives sealed after its start.
	run["identity"] = {"schema": 1, "inherited": identity_inheritance(meta)}
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
	var npcs := npc_snapshot(run.get("npcs", {}))
	if not npcs.is_empty(): summary["npcs"] = npcs
	var mainline := mainline_snapshot(run.get("mainline", {}))
	if not mainline.is_empty():
		summary["mainline"] = mainline
		if run.get("phase", "") == "ending" and not mainline.ending.is_empty(): summary.outcome = mainline.ending.title
	var identity := _identity_archive(run)
	if not identity.is_empty(): summary["identity"] = identity
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
