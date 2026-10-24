extends RefCounted
## Identity methods spend this-life resources; inherited facts only unlock an option.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Data = preload("res://scripts/core/data.gd")

const TAGS := {"sealed_lamps": "曾完成七灯封阵", "escaped_city": "曾实际撤离离城", "gave_medicine": "曾赠药救邻", "returned_evidence": "曾把义庄证物带回"}
const ACTIONS := {
	"scholar_collate": {"role": "scholar", "name": "校勘七灯旧文", "cost": {"talisman_paper": 2, "cinnabar": 1}, "minutes": 90, "energy": 6, "hp": 0, "cap": "scribe_talisman", "legacy": "", "effect": "开启青云观，学会省纸符方；没有断运，第11/17夜仍有铜甲。"},
	"scholar_diagram": {"role": "scholar", "name": "重绘旧世七灯图", "cost": {"talisman_paper": 2, "lamp_oil": 1}, "minutes": 120, "energy": 8, "hp": 0, "cap": "paper_ritual", "legacy": "sealed_lamps", "effect": "开启青云观，解锁纸阵破阵筹备；放弃省纸符方，仍须今世青云取证与现场封阵。"},
	"escort_intercept": {"role": "escort", "name": "强截运尸车", "cost": {"caltrops": 1}, "minutes": 90, "energy": 12, "hp": 12, "cap": "", "legacy": "", "effect": "开启青云观并截断运尸，移除尚未开夜的第11/17夜铜甲；会受伤，气血不能扣至0。"},
	"escort_convoy": {"role": "escort", "name": "勘明旧世出城路", "cost": {"rice": 1, "water": 1, "wood": 1}, "minutes": 120, "energy": 8, "hp": 0, "cap": "early_convoy", "legacy": "escaped_city", "effect": "开启青云观，解锁提前出城方法；不截断运尸，仍须今世青云取证、备行装和实际离城。"},
	"herbalist_lure": {"role": "herbalist", "name": "辨药导走尸群", "cost": {"plague_powder": 1, "mugwort": 3}, "minutes": 60, "energy": 6, "hp": 0, "cap": "efficient_plague", "legacy": "", "effect": "开启青云观，学会省艾草药方；尚未开夜的第11/17夜基础尸数乘0.9，铜甲保留。"},
	"herbalist_ink": {"role": "herbalist", "name": "调配救邻药墨", "cost": {"mugwort": 2, "water": 1}, "minutes": 90, "energy": 6, "hp": 0, "cap": "medicinal_talisman", "legacy": "gave_medicine", "effect": "开启青云观，学会药墨镇尸符；放弃省艾草药方与导尸减潮，不替代今世取证。"},
	"watchman_lane": {"role": "watchman", "name": "勘明轻装更道", "cost": {"lamp_oil": 1}, "minutes": 60, "energy": 6, "hp": 0, "cap": "light_escape", "legacy": "", "effect": "开启青云观，解锁轻装撤离；少耗木钉但筹备与撤离更久，不减尸潮。"},
	"watchman_intel": {"role": "watchman", "name": "核对旧世运尸更簿", "cost": {"talisman_paper": 1, "water": 1}, "minutes": 90, "energy": 6, "hp": 0, "cap": "wave_intel", "legacy": "returned_evidence", "effect": "开启青云观，解锁真实尸潮情报；放弃轻装更道，不断运，也不把旧世证据当今世成果。"},
}
const ORDER := ["scholar_collate", "scholar_diagram", "escort_intercept", "escort_convoy", "herbalist_lure", "herbalist_ink", "watchman_lane", "watchman_intel"]
const CRAFTS := {"scribe_talisman": "scribe_talisman", "efficient_plague": "efficient_plague", "medicinal_talisman": "medicinal_talisman"}

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _inheritance(value) -> Array:
	var out := []
	if not value is Array: return out
	var seen := []
	for entry in value:
		if not entry is Dictionary or not str(entry.get("tag", "")) in TAGS or entry.get("tag", "") in seen: continue
		if not _integer(entry.get("source_life"), 1, 999999) or not entry.get("source_id") is String or entry.source_id.is_empty() or entry.source_id.length() > 80: continue
		out.append({"tag": entry.tag, "source_life": int(entry.source_life), "source_id": entry.source_id})
		seen.append(entry.tag)
	return out

static func state(run: Dictionary) -> Dictionary:
	if not run.get("identity") is Dictionary or run.identity.get("schema", 1) != 1: run["identity"] = {}
	var s: Dictionary = run.identity
	var defaults := {"schema": 1, "revision": 0, "inherited": [], "chosen": "", "completed_t": -1, "learned": [], "work": {}, "history": [], "serial": 0}
	for key in defaults:
		if not s.has(key): s[key] = defaults[key]
	s.inherited = _inheritance(s.inherited)
	if not s.history is Array: s.history = []
	while s.history.size() > 12: s.history.pop_front()
	if not s.work is Dictionary: s.work = {}
	if not s.learned is Array: s.learned = []
	if not _integer(s.revision, 0, 144000000): s.revision = 0
	if not _integer(s.serial, 0, 144000000): s.serial = 0
	return s

static func _day(run: Dictionary) -> int:
	return maxi(1, int(run.get("t", 0)) / 1440 + 1)

static func _token(run: Dictionary) -> String:
	return "identity:%s:%s:%d" % [str(Past.state(run).id), str(run.get("role", "")), int(state(run).revision)]

static func _fact(run: Dictionary, action: String, result: String) -> String:
	var s := state(run)
	s.history.append({"day": _day(run), "t": int(run.get("t", 0)), "action": action.left(40), "result": result.left(240)})
	while s.history.size() > 12: s.history.pop_front()
	s.revision = int(s.revision) + 1
	State.note(run, "身份解法 · " + result)
	return result

static func _legacy(run: Dictionary, tag: String) -> bool:
	if tag == "": return true
	if Past.daily(run): return false
	var p := Past.state(run)
	for entry in state(run).inherited:
		if entry.tag == tag and int(entry.source_life) < int(p.get("generation", 0)) and entry.source_id != p.id: return true
	return false

static func _active(run: Dictionary) -> String:
	var s := state(run)
	var id := str(s.chosen)
	if not id in ACTIONS or str(run.get("role", "")) != str(ACTIONS[id].role): return ""
	if not _integer(s.completed_t, 0, 144000000) or int(s.completed_t) > int(run.get("t", 0)): return ""
	if not _legacy(run, str(ACTIONS[id].legacy)): return ""
	var cap := str(ACTIONS[id].cap)
	if s.learned != ([] if cap == "" else [cap]): return ""
	return id

static func has(run: Dictionary, cap: String) -> bool:
	var id := _active(run)
	return id != "" and cap != "" and ACTIONS[id].cap == cap

static func _same_busy(run: Dictionary, work: Dictionary) -> bool:
	var busy: Dictionary = run.get("busy", {})
	return busy.get("kind", "") == "identity" and busy.get("data", {}).get("id", "") == work.get("id", "") and busy.get("data", {}).get("action", "") == work.get("action", "")

static func poll(run: Dictionary) -> String:
	var s := state(run)
	if s.work.is_empty() or _same_busy(run, s.work): return ""
	var label := str(s.work.get("label", "身份工作"))
	s.work = {}
	return _fact(run, "interrupted", label + "已中断，未解锁能力、配方或减潮；已花材料、精力与气血不退，期限内仍可重新选择。")

static func _access(run: Dictionary) -> String:
	if run.get("phase", "") != "post": return "尸劫开始后才能安排身份解法。"
	if State.attr(run, "hp") <= 0: return "气血已经耗尽，不能开工。"
	if run.get("pending_event", "") != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事件或夜战。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty() or not state(run).work.is_empty() or not Mainline.state(run).work.is_empty(): return "正在忙别的事。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false): return "先回到宅院再安排身份解法。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，不能另开身份工作。"
	return ""

static func _block(run: Dictionary, id: String) -> String:
	if not id in ACTIONS: return "没有这条身份解法。"
	var a: Dictionary = ACTIONS[id]
	if str(run.get("role", "")) != str(a.role): return "只有%s能用这条解法。" % str(Data.table("roles")[a.role].name)
	if not _legacy(run, str(a.legacy)):
		return "每日一局不使用前世专属解法。" if Past.daily(run) else "缺少确证前世经历：%s；未完工作与旧世传闻不算。" % str(TAGS.get(a.legacy, ""))
	var s := state(run)
	if str(s.chosen) != "": return "本世已经选定一种身份解法，不能兼得另一条。"
	var access := _access(run)
	if access != "": return access
	var main := Mainline.state(run)
	if main.stage != "mortuary_choice" or not main.evidence.get("mortuary", false): return "先把本世义庄运尸簿带回；公共处置或身份解法一经完成，就不能再选另一种。"
	if int(run.get("t", 0)) + int(a.minutes) + 140 >= Mainline.FINAL_END: return "留不够身份工作及青云观往返取证的140分钟，第19日18:00前必须完成。"
	if float(run.get("attrs", {}).get("energy", 0.0)) < float(a.energy): return "精力不足，需要%d。" % int(a.energy)
	if int(a.hp) > 0 and State.attr(run, "hp") <= int(a.hp): return "气血不足，强截要耗%d气血且必须活着回来。" % int(a.hp)
	if not Inv.has_all(run.get("home", {}), a.cost): return "材料不足，需要%s。" % Data.describe_items(a.cost)
	return ""

static func options(run: Dictionary) -> Array:
	var out := []
	for id in ORDER:
		var a: Dictionary = ACTIONS[id]
		if str(run.get("role", "")) != a.role: continue
		var cost_text := "%s；%d分钟，精力%d%s。" % [Data.describe_items(a.cost), int(a.minutes), int(a.energy), "，气血%d" % int(a.hp) if int(a.hp) > 0 else ""]
		out.append({"id": id, "text": a.name, "hint": a.effect + "本世只能选一法；完工才生效，中断不退款。", "cost_text": cost_text, "block": _block(run, id)})
	return out

static func act(run: Dictionary, id: String, token: String) -> String:
	if token != _token(run): return "身份安排已过期，请重新查看。"
	var blocked := _block(run, id)
	if blocked != "": return blocked
	var a: Dictionary = ACTIONS[id]
	var s := state(run)
	Inv.take_all(run.home, a.cost)
	State.add_attr(run, "energy", -int(a.energy))
	if int(a.hp) > 0: State.add_attr(run, "hp", -int(a.hp))
	s.serial = int(s.serial) + 1
	var work_id := "identity:%s:%d" % [str(Past.state(run).id), int(s.serial)]
	var end := int(run.t) + int(a.minutes)
	s.work = {"id": work_id, "action": id, "label": str(a.name), "start_t": int(run.t), "end_t": end}
	run.busy = {"kind": "identity", "label": str(a.name), "start": int(run.t), "end": end, "data": {"id": work_id, "action": id}}
	_fact(run, "start_" + id, "开始%s；%d分钟完工才生效，已付材料、精力%s，中断不退。" % [a.name, int(a.minutes), "与气血" if int(a.hp) > 0 else ""])
	return ""

static func complete(run: Dictionary, data: Dictionary) -> String:
	var s := state(run)
	var work: Dictionary = s.work
	if work.is_empty() or data.get("id", "") != work.get("id", "") or data.get("action", "") != work.get("action", "") or int(run.get("t", 0)) < int(work.get("end_t", 0)): return ""
	var id := str(work.get("action", ""))
	if not str(work.get("id", "")).begins_with("identity:%s:" % str(Past.state(run).id)): return ""
	if run.get("phase", "") != "post" or State.attr(run, "hp") <= 0:
		s.work = {}
		return ""
	if not id in ACTIONS or str(s.chosen) != "" or str(run.get("role", "")) != str(ACTIONS[id].role) or not _legacy(run, str(ACTIONS[id].legacy)):
		s.work = {}
		return _fact(run, "invalid_completion", "身份工作条件已经改变，没有解锁任何能力；已付材料不退。")
	if int(run.get("t", 0)) + 140 >= Mainline.FINAL_END:
		s.work = {}
		return _fact(run, "late_completion", "身份工作完工太晚，留不够本世青云观取证时间，没有生效；投入不退。")
	var result := Mainline.identity_resolution(run, id)
	s.work = {}
	if result == "": return _fact(run, "invalid_completion", "本世取证或阶段已改变，这项身份处置没有生效；不能补领能力，投入不退。")
	s.chosen = id
	s.completed_t = int(run.t)
	s.learned = [] if str(ACTIONS[id].cap) == "" else [str(ACTIONS[id].cap)]
	return _fact(run, id, "%s完成。%s" % [str(ACTIONS[id].name), str(ACTIONS[id].effect)])

static func craft_block(run: Dictionary, id: String) -> String:
	if not id in CRAFTS: return ""
	if has(run, str(CRAFTS[id])): return ""
	return "尚未完成本世对应身份解法，不能使用%s配方。" % {"scribe_talisman": "书生省纸符", "efficient_plague": "药徒省艾草", "medicinal_talisman": "救邻药墨符"}[id]

static func wave_effect(run: Dictionary, day: int) -> Dictionary:
	var out := {"remove_mods": [], "count_mul": 1.0, "reason": ""}
	if day not in [11, 17] or _active(run) != "herbalist_lure": return out
	var start := (day - 1) * 1440 + 960
	var active: Dictionary = run.get("night", {})
	if int(run.get("wave_day", 0)) == day or (not active.is_empty() and int(active.get("wave", {}).get("day", -1)) == day): return out
	if int(state(run).completed_t) >= start: return out
	out.count_mul = 0.9
	out.reason = "本世辨药导尸已完成，第%d夜基础尸数乘0.9；铜甲仍在。" % day
	return out

static func preview(role: String, meta: Dictionary) -> Dictionary:
	var inherited := _inheritance(Past.identity_inheritance(meta))
	var base_name := ""
	var legacy_name := ""
	var legacy_tag := ""
	var unlocked := false
	for id in ORDER:
		if ACTIONS[id].role != role: continue
		if str(ACTIONS[id].legacy) == "":
			base_name = str(ACTIONS[id].name)
			continue
		legacy_name = str(ACTIONS[id].name)
		legacy_tag = str(ACTIONS[id].legacy)
		for entry in inherited:
			if entry.tag == legacy_tag: unlocked = true
	return {"headline": "可选「%s」；%s「%s」。两法均须今世取证。" % [base_name, "亦可改选" if unlocked else "旧世确证后可选", legacy_name], "inheritance": inherited}

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var role := str(run.get("role", ""))
	var active := _active(run)
	var summary := "先交回本世义庄证据，再在公共处置与身份专法间作一个选择。"
	if not s.work.is_empty(): summary = "%s正在进行，尚未解锁能力；中断不退款。" % str(s.work.get("label", "身份工作"))
	elif active != "": summary = "本世已选「%s」。%s" % [str(ACTIONS[active].name), str(ACTIONS[active].effect)]
	elif str(s.chosen) != "": summary = "这份身份能力当前无效，不能领取跨身份、未完成或每日局旧世成果。"
	var inherited := []
	if not Past.daily(run):
		for entry in s.inherited:
			if _legacy(run, str(entry.tag)): inherited.append(entry.duplicate())
	return {"title": "身份专属解法", "role_name": str(Data.table("roles").get(role, {}).get("name", role)), "summary": summary,
		"token": _token(run), "options": options(run), "history": s.history.duplicate(true), "inheritance": inherited, "work": s.work.duplicate(true),
		"intel": "已获得更路情报；详情读取真实尸潮预报，已开夜不再改写。" if has(run, "wave_intel") else ""}

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var active := _active(run)
	var tags := []
	if not Past.daily(run):
		for entry in s.inherited:
			if _legacy(run, str(entry.tag)): tags.append(str(entry.tag))
	return {"schema": 1, "role": str(run.get("role", "")), "chosen": active, "completed_t": int(s.completed_t) if active != "" else -1,
		"learned": s.learned.duplicate() if active != "" else [], "legacy_tags": tags, "history": s.history.duplicate(true)}
