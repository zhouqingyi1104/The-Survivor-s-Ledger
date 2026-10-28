extends RefCounted
## AI may select reviewed phrasing IDs. Facts and consequences stay local.
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const ACTORS := ["ning", "zhou", "traveler"]
static var _catalogue := {}

static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		_catalogue = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://data/npc_dialogue.json"))).actors
	return _catalogue

static func state(run: Dictionary) -> Dictionary:
	if not run.get("npc_dialogue") is Dictionary or run.npc_dialogue.get("schema") != 1 or not run.npc_dialogue.get("actors") is Dictionary:
		run["npc_dialogue"] = {"schema": 1, "actors": {}}
	for actor in run.npc_dialogue.actors.keys():
		if not actor in ACTORS or not run.npc_dialogue.actors[actor] is Dictionary: run.npc_dialogue.actors.erase(actor)
	return run.npc_dialogue

static func _tone(view: Dictionary) -> String:
	var codes: Array = view.get("plan", {}).get("reason_codes", [])
	for code in ["distrust", "breach", "memory_dismiss"]:
		if code in codes: return "guarded"
	for code in ["trust", "favor", "memory_acknowledge", "memory_compensate"]:
		if code in codes: return "warm"
	return "plain"

static func _allowed(actor: String, group: String, tone: String) -> Array:
	var out := []
	for id in catalogue()[actor][group]:
		var row: Dictionary = catalogue()[actor][group][id]
		if row.tone == "all" or row.tone == tone: out.append(id)
	return out

static func _slot(view: Dictionary) -> Dictionary:
	var plan: Dictionary = view.get("plan", {})
	if plan.is_empty() or plan.get("status", "") != "pending": return {}
	var actor: String = view.actor
	var tone := _tone(view)
	return {"actor": actor, "decision_id": str(plan.id), "tone": tone,
		"openers": _allowed(actor, "openers", tone), "closers": _allowed(actor, "closers", tone)}

## Reading model context never freezes player-visible speech.
static func context(run: Dictionary) -> Dictionary:
	var out := {"schema": 1, "slots": []}
	var saved: Dictionary = state(run).actors
	for actor in ACTORS:
		var slot := _slot(Npc.view(run, actor))
		if slot.is_empty(): continue
		var old: Dictionary = saved.get(actor, {})
		if old.get("decision_id", "") == slot.decision_id and old.get("frozen", false): continue
		out.slots.append(slot)
	return out

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key in value:
		if not key in allowed: return false
	return true

static func valid_rows(rows, candidates = null) -> bool:
	if not rows is Array or rows.size() > 3: return false
	var seen := []
	for row in rows:
		if not row is Dictionary or not _keys(row, ["actor", "decision_id", "opener", "closer"]): return false
		if not row.get("actor", "") in ACTORS or row.actor in seen: return false
		seen.append(row.actor)
		if not row.get("decision_id") is String or row.decision_id.strip_edges().is_empty() or row.decision_id.length() > 120: return false
		var phrases: Dictionary = catalogue()[row.actor]
		if not row.get("opener") is String or not phrases.openers.has(row.opener) or not row.get("closer") is String or not phrases.closers.has(row.closer): return false
		if candidates != null:
			if not candidates is Dictionary or not candidates.get("slots") is Array: return false
			var found := false
			for slot in candidates.slots:
				if not slot is Dictionary or not slot.get("openers") is Array or not slot.get("closers") is Array: continue
				if slot.get("actor", "") == row.actor and slot.get("decision_id", "") == row.decision_id and row.opener in slot.openers and row.closer in slot.closers: found = true
			if not found: return false
	return true

static func current_rows(run: Dictionary, rows: Array) -> bool:
	if Past.daily(run): return rows.is_empty()
	for row in rows:
		var slot := _slot(Npc.view(run, str(row.actor)))
		if slot.is_empty() or slot.decision_id != row.decision_id or not row.opener in slot.openers or not row.closer in slot.closers: return false
	return true

## A response can enrich unread speech, never replace words already read.
static func accept(run: Dictionary, candidates: Dictionary, rows: Array) -> bool:
	if not valid_rows(rows, candidates) or not current_rows(run, rows): return false
	var saved: Dictionary = state(run).actors
	for row in rows:
		var old: Dictionary = saved.get(row.actor, {})
		if old.get("decision_id", "") == row.decision_id and old.get("frozen", false): continue
		saved[row.actor] = {"decision_id": row.decision_id, "opener": row.opener, "closer": row.closer, "frozen": false, "source": "ark-plan"}
	return true

static func _body(view: Dictionary) -> String:
	var plan: Dictionary = view.get("plan", {})
	if plan.is_empty(): return "我还没有定下下一步打算。"
	if plan.get("status", "") == "done":
		return "本次已经执行：%s\n下一次打算会参考如今的库存和往来。" % str(view.get("last_result", ""))
	var text: String = "我的打算：%s。\n缘由：%s" % [str(view.get("goal", "自行周转")), str(view.get("reason", ""))]
	if plan.get("response", "") == "favor": text = "你已经凭情改托，原自主行动取消；将按已经预留的物资交付。"
	if str(view.get("effect", "")) != "": text += "\n安排：" + str(view.effect)
	var memory: Dictionary = view.get("memory", {})
	if not memory.is_empty():
		text += "\n我记起的前世碎片：" + str(memory.fact)
	var response := str(plan.get("response", ""))
	if response == "support": text += "\n你已经送来支援，我会照已经说明的安排做。"
	elif response == "favor": text += "\n你已经凭情改托，我会按锁定的物资交付。"
	elif response == "decline": text += "\n你让我自行安排，我会照自己的打算行动。"
	return text

static func _text(row: Dictionary, view: Dictionary) -> String:
	var phrases: Dictionary = catalogue()[view.actor]
	return "%s\n%s\n%s" % [phrases.openers[row.opener].text, _body(view), phrases.closers[row.closer].text]

static func _cached(row: Dictionary, actor: String, decision_id: String) -> bool:
	return row.get("decision_id", "") == decision_id and catalogue()[actor].openers.has(row.get("opener", "")) and catalogue()[actor].closers.has(row.get("closer", "")) and row.get("source", "") in ["local", "ark-plan"]

static func render(run: Dictionary, actor: String) -> Dictionary:
	if not actor in ACTORS: return {"text": "", "source": "local", "decision_id": "", "changed": false}
	var view := Npc.view(run, actor)
	var plan: Dictionary = view.get("plan", {})
	if plan.is_empty(): return {"text": _body(view), "source": "local", "decision_id": "", "changed": false}
	var saved: Dictionary = state(run).actors
	var old: Dictionary = saved.get(actor, {})
	if _cached(old, actor, str(plan.id)) and old.get("frozen", false):
		return {"text": _text(old, view), "source": old.source, "decision_id": old.decision_id, "changed": false}
	var slot := _slot(view)
	if slot.is_empty():
		# Old saves may first inspect a completed decision; it stays offline.
		var tone := _tone(view)
		slot = {"actor": actor, "decision_id": plan.id, "openers": _allowed(actor, "openers", tone), "closers": _allowed(actor, "closers", tone)}
	var row := old if _cached(old, actor, str(plan.id)) and old.get("opener", "") in slot.openers and old.get("closer", "") in slot.closers and not Past.daily(run) else {}
	if row.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("npc-dialogue:%s:%s:%s" % [str(run.get("seed", 0)), actor, str(plan.day)])
		row = {"decision_id": plan.id, "opener": slot.openers[rng.randi_range(0, slot.openers.size() - 1)], "closer": slot.closers[rng.randi_range(0, slot.closers.size() - 1)], "source": "local"}
	row["frozen"] = true
	saved[actor] = row
	return {"text": _text(row, view), "source": row.source, "decision_id": row.decision_id, "changed": true}
