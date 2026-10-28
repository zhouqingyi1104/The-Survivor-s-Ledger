extends RefCounted
## An opening is a paid decision made before the first errand, never a gift on load.
## Legacy sources are pinned at birth. NPC trust comes from this life's real acts.
const State = preload("res://scripts/core/state.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")

const TAGS := ["sealed_lamps", "escaped_city", "gave_medicine", "returned_evidence", "breach_ning", "breach_zhou", "breach_traveler", "crisis_well_freeze", "crisis_fuel_shortage", "crisis_herb_shortage"]
const NAMES := {"ning": "阿宁", "zhou": "老周", "traveler": "过路客"}
const KINDS := {"well_freeze": "井口冻裂", "fuel_shortage": "运柴中断", "herb_shortage": "药草挤兑"}
const SOURCE_NAMES := {"sealed_lamps": "实际七灯封阵", "escaped_city": "实际离城", "gave_medicine": "实际赠药", "returned_evidence": "义庄交证", "breach_ning": "曾与阿宁真实失约", "breach_zhou": "曾与老周真实失约", "breach_traveler": "曾与过路客真实失约", "crisis_well_freeze": "实际防住或补救井冻", "crisis_fuel_shortage": "实际防住或补救断运", "crisis_herb_shortage": "实际防住或补救药荒"}
const ORDER := ["plain", "scholar_stock", "scholar_neighbors", "scholar_lamps", "escort_stock", "escort_neighbors", "escort_oldroad", "herbalist_stock", "herbalist_neighbors", "herbalist_oldcase", "watchman_stock", "watchman_neighbors", "watchman_oldledger", "cash_account", "old_crisis"]
const ACTIONS := {
	"plain": {"role": "", "name": "照常备劫", "silver": 0, "hours": 0, "spent": {}, "gained": {}, "actor": "", "trust": 0, "favors": 0, "kind": "", "warning_day": 0, "legacy": "", "deed": "保留原有银钱、随身物和备劫时间；放弃今世专属开局筹备，首场风声照常形成。"},
	"scholar_stock": {"role": "scholar", "name": "先备纸砂木料", "silver": 1800, "hours": 0, "spent": {}, "gained": {"talisman_paper": 2, "cinnabar": 1, "wood": 1}, "actor": "zhou", "trust": -1, "favors": 0, "kind": "fuel_shortage", "warning_day": 2, "legacy": "", "deed": "今世拒替老周誊单，把工夫留给自己的纸砂木料。"},
	"scholar_neighbors": {"role": "scholar", "name": "代写药单结邻", "silver": 1200, "hours": 1, "spent": {"flatbread": 1}, "gained": {"water": 3, "rice": 2}, "actor": "ning", "trust": 2, "favors": 0, "kind": "herb_shortage", "warning_day": 2, "legacy": "", "deed": "今世替阿宁整理药单并送饼，她回以米水；占用一时辰采购时间。"},
	"scholar_lamps": {"role": "scholar", "name": "按旧灯图备料", "silver": 2400, "hours": 1, "spent": {}, "gained": {"talisman_paper": 3, "lamp_oil": 1, "wood": 1}, "actor": "zhou", "trust": 1, "favors": 0, "kind": "well_freeze", "warning_day": 3, "legacy": "sealed_lamps", "deed": "自己记得前世灯图，今世付钱并替老周校清材料单；只备料，不自动学符或封阵。"},
	"escort_stock": {"role": "escort", "name": "押货先顾自家", "silver": 1600, "hours": 0, "spent": {}, "gained": {"rice": 3, "firewood": 3, "caltrops": 1}, "actor": "traveler", "trust": -1, "favors": 0, "kind": "fuel_shortage", "warning_day": 2, "legacy": "", "deed": "今世拒替邻人运物，押回自己的粮柴和蒺藜。"},
	"escort_neighbors": {"role": "escort", "name": "替老周运物", "silver": 1400, "hours": 1, "spent": {"flatbread": 1}, "gained": {"wood": 2, "water": 2}, "actor": "zhou", "trust": 1, "favors": 1, "kind": "well_freeze", "warning_day": 2, "legacy": "", "deed": "今世出力送物并留下一张饼，老周回赠木水，欠下一份人情。"},
	"escort_oldroad": {"role": "escort", "name": "循旧路预备行装", "silver": 2300, "hours": 1, "spent": {"flatbread": 1}, "gained": {"wood": 1, "nails": 2, "rice": 2}, "actor": "traveler", "trust": 2, "favors": 0, "kind": "fuel_shortage", "warning_day": 3, "legacy": "escaped_city", "deed": "自己记得前世离城，今世付费探路并分饼给过路客；仍须今世调查和筹备才能撤离。"},
	"herbalist_stock": {"role": "herbalist", "name": "留药先顾自家", "silver": 1000, "hours": 0, "spent": {}, "gained": {"plague_powder": 1, "mugwort": 3, "water": 2}, "actor": "ning", "trust": -1, "favors": 0, "kind": "herb_shortage", "warning_day": 2, "legacy": "", "deed": "今世留药自备，婉拒阿宁代配药材的请求；往后的药荒仍须应对。"},
	"herbalist_neighbors": {"role": "herbalist", "name": "分药换柴水", "silver": 1200, "hours": 1, "spent": {"salve": 1}, "gained": {"firewood": 2, "water": 2}, "actor": "ning", "trust": 2, "favors": 1, "kind": "well_freeze", "warning_day": 2, "legacy": "", "deed": "今世分出一瓶金创药帮阿宁备家，换回柴水与一份人情；自己的应急药减少。"},
	"herbalist_oldcase": {"role": "herbalist", "name": "按旧诊经历备药", "silver": 2000, "hours": 1, "spent": {"plague_powder": 1}, "gained": {"mugwort": 4, "water": 3}, "actor": "ning", "trust": 2, "favors": 1, "kind": "herb_shortage", "warning_day": 3, "legacy": "gave_medicine", "deed": "自己记得前世赠药，今世再分一包避瘟散并整理药篮；不代表阿宁知道前世或已经治愈。"},
	"watchman_stock": {"role": "watchman", "name": "巡柴路备燃料", "silver": 1000, "hours": 0, "spent": {}, "gained": {"firewood": 4, "lamp_oil": 1}, "actor": "zhou", "trust": 1, "favors": 0, "kind": "fuel_shortage", "warning_day": 2, "legacy": "", "deed": "今世巡查柴路并把消息交给老周，先备自家柴与灯油；没有预先排除断运。"},
	"watchman_neighbors": {"role": "watchman", "name": "提灯巡井联防", "silver": 1200, "hours": 1, "spent": {"lamp_oil": 1}, "gained": {"water": 4, "wood": 1}, "actor": "ning", "trust": 1, "favors": 1, "kind": "well_freeze", "warning_day": 2, "legacy": "", "deed": "今世耗灯油替阿宁巡井搬水，得一份人情；巡过井不等于完成防冻施工。"},
	"watchman_oldledger": {"role": "watchman", "name": "循旧更簿备水木", "silver": 2200, "hours": 1, "spent": {"lamp_oil": 1}, "gained": {"wood": 2, "nails": 1, "water": 2}, "actor": "traveler", "trust": 2, "favors": 0, "kind": "well_freeze", "warning_day": 3, "legacy": "returned_evidence", "deed": "自己记得前世运尸更簿，今世提灯核路并和过路客互通路况；不抵今世交证或敌情勘验。"},
	"cash_account": {"role": "", "name": "记取失约，今世先付现款", "silver": 2200, "hours": 1, "spent": {}, "gained": {"rice": 1, "water": 2}, "actor": "", "trust": 2, "favors": 0, "kind": "", "warning_day": 2, "legacy": "breach", "deed": "自己记得前世失约，今世先付款、出力重新结识；旧债不会带入，对方并不知道前世欠账。"},
	"old_crisis": {"role": "", "name": "记取旧灾，另作储备", "silver": 1800, "hours": 1, "spent": {}, "gained": {"wood": 1, "firewood": 1, "mugwort": 1, "water": 1}, "actor": "", "trust": 1, "favors": 0, "kind": "", "warning_day": 3, "legacy": "crisis", "deed": "自己记得曾实际应对的旧患，今世采购并向邻人核问风声；今世真假仍未知，也没有自动防护。"},
}

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _items(value) -> bool:
	if not value is Dictionary or value.size() > 200: return false
	for item in value:
		if not item is String or Data.item(item).is_empty() or not _integer(value[item], 1, 1000000): return false
	return true

static func _inheritance(value) -> Array:
	var out := []
	if not value is Array: return out
	var seen := []
	for entry in value:
		if not entry is Dictionary or entry.size() != 3 or not entry.get("tag", "") in TAGS or entry.tag in seen: continue
		if not _integer(entry.get("source_life"), 1, 999999) or not entry.get("source_id") is String or entry.source_id.strip_edges().is_empty() or entry.source_id.length() > 80: continue
		out.append({"tag": entry.tag, "source_life": int(entry.source_life), "source_id": entry.source_id})
		seen.append(entry.tag)
	return out

static func _neutral() -> Dictionary:
	return {"silver_cost": 0, "hours": 0, "spent": {}, "gained": {}, "contacts": {}, "first_warning": {}}

static func state(run: Dictionary) -> Dictionary:
	if not run.get("opening") is Dictionary or run.opening.get("schema", 1) != 1: run["opening"] = {}
	var s: Dictionary = run.opening
	var defaults := {"schema": 1, "revision": 0, "inherited": [], "birth": {}, "choice": "", "applied": false, "effects": {}, "history": []}
	for key in defaults:
		if not s.has(key): s[key] = defaults[key]
	s.inherited = _inheritance(s.inherited)
	if not s.birth is Dictionary: s.birth = {}
	if not s.history is Array: s.history = []
	while s.history.size() > 8: s.history.pop_front()
	if not s.effects is Dictionary: s.effects = {}
	if not _integer(s.revision, 0, 144000000): s.revision = 0
	return s

static func _sources(run: Dictionary) -> Array:
	if Past.daily(run): return []
	var out := []
	var p := Past.state(run)
	for entry in state(run).inherited:
		if int(entry.source_life) < int(p.get("generation", 0)) and entry.source_id != p.get("id", ""): out.append(entry.duplicate())
	return out

static func _source(inherited: Array, wanted: String) -> Dictionary:
	if wanted == "": return {}
	var source := {}
	# TAGS order is the tie-breaker, independent of Dictionary or archive order.
	for tag in TAGS:
		if wanted == "breach" and not str(tag).begins_with("breach_"): continue
		if wanted == "crisis" and not str(tag).begins_with("crisis_"): continue
		if wanted not in ["breach", "crisis"] and wanted != tag: continue
		for candidate in inherited:
			if candidate.tag == tag and int(candidate.source_life) > int(source.get("source_life", 0)): source = candidate.duplicate()
	return source

static func _definition(id: String, inherited: Array) -> Dictionary:
	if not id in ACTIONS: return {}
	var a: Dictionary = ACTIONS[id].duplicate(true)
	var source := _source(inherited, str(a.legacy))
	a["source"] = source
	if id == "cash_account" and not source.is_empty():
		a.actor = str(source.tag).trim_prefix("breach_")
		a.kind = {"ning": "herb_shortage", "zhou": "fuel_shortage", "traveler": "well_freeze"}[a.actor]
	elif id == "old_crisis" and not source.is_empty():
		a.kind = str(source.tag).trim_prefix("crisis_")
		a.actor = "zhou" if a.kind == "fuel_shortage" else "ning"
	return a

static func _source_text(a: Dictionary) -> String:
	var source: Dictionary = a.get("source", {})
	if source.is_empty(): return ""
	return "第%d世 · %s" % [int(source.source_life), str(SOURCE_NAMES.get(source.tag, source.tag))]

static func _hint(a: Dictionary) -> String:
	if a.name == ACTIONS.plain.name: return str(a.deed) + "今世选择即固定，不能再领其他筹备。"
	var money := "银%d文" % int(a.silver)
	var spent := "；交出%s" % Data.describe_items(a.spent) if not a.spent.is_empty() else ""
	var contact := ""
	if str(a.actor) in NAMES:
		contact = "%s信任%+d" % [str(NAMES[a.actor]), int(a.trust)]
		if int(a.favors) > 0: contact += "、人情+%d" % int(a.favors)
	var warning := "第%d日08:00出现%s风声，仍须核实与处置" % [int(a.warning_day), str(KINDS.get(a.kind, "相应危机"))]
	if str(a.kind) == "": warning = "依据确证前世选择首场风声，仍须核实与处置"
	var source := _source_text(a)
	var source_hint := "依据%s。" % source if source != "" else ""
	return "%s；耗%d时辰%s，获得%s。%s%s；%s。%s今世只能选一种，放弃其他筹备。" % [money, int(a.hours), spent, Data.describe_items(a.gained), str(a.deed), contact, warning, source_hint]

static func _eligibility(role: String, a: Dictionary, inherited: Array, daily: bool, vows: Array, silver: int, home: Dictionary) -> String:
	if str(a.role) != "" and a.role != role: return "这个开局筹备只适合%s。" % str(Data.table("roles").get(a.role, {}).get("name", a.role))
	if a.name == ACTIONS.plain.name: return ""
	if daily: return "每日一局沿用普通开局，不使用身份筹备和前世经验。"
	if "bare" in vows: return "空手誓约只能照常备劫，不能领取开局筹备。"
	if str(a.legacy) != "" and _source(inherited, str(a.legacy)).is_empty():
		return "前世没有真正做成这件事；听来的、没做完的都不算。"
	if silver < int(a.silver): return "银钱不足，需要%d文。" % int(a.silver)
	if not Inv.has_all(home, a.spent): return "随身物不足，需要%s。" % Data.describe_items(a.spent)
	return ""

static func options(role: String, meta: Dictionary, daily := false, vows: Array = [], difficulty := "normal") -> Array:
	var out := []
	var role_data: Dictionary = Data.table("roles").get(role, {})
	if role_data.is_empty(): return out
	var inherited := [] if daily else _inheritance(Past.opening_inheritance(meta))
	var silver := int(round(float(role_data.silver) * float(State.diff_params(difficulty).get("silver_mul", 1.0))))
	var home: Dictionary = {} if "bare" in vows else role_data.items.duplicate(true)
	for id in ORDER:
		var a := _definition(id, inherited)
		if str(a.role) != "" and a.role != role: continue
		out.append({"id": id, "text": a.name, "hint": _hint(a), "block": _eligibility(role, a, inherited, daily, vows, silver, home)})
	return out

static func _token(run: Dictionary) -> String:
	return "opening:%s:%s:%d" % [str(Past.state(run).id), str(run.get("role", "")), int(state(run).revision)]

static func _birth_valid(run: Dictionary, birth: Dictionary) -> bool:
	if birth.size() != 4 or not _integer(birth.get("silver"), 0, 1000000000) or not _items(birth.get("home")): return false
	if birth.get("role", "") != run.get("role", "") or not birth.get("role", "") in Data.table("roles") or birth.get("seed") != run.get("seed"): return false
	return true

static func _access(run: Dictionary, id: String) -> String:
	var s := state(run)
	if bool(s.get("applied", false)) or str(s.get("choice", "")) != "": return "今世开局筹备已经选定，不能改选或重复领取。"
	if run.get("phase", "") != "pre" or not _integer(run.get("day"), 1, 1) or not _integer(run.get("hour"), State.OPEN_HOUR, State.OPEN_HOUR) or run.get("loc", "") != "home" or not _integer(run.get("t"), 0, 0): return "只能在第一日卯时、尚未出门时决定开局筹备。"
	if State.attr(run, "hp") <= 0: return "气血已经耗尽，不能再安排开局筹备。"
	if not run.get("cart", {}).is_empty() or not run.get("orders", []).is_empty(): return "已经搬运或订货，开局筹备已关闭。"
	var tally: Dictionary = run.get("tally", {})
	if not tally.get("bought", {}).is_empty() or int(tally.get("home_trips", 0)) != 0 or int(tally.get("orders", 0)) != 0 or int(tally.get("repair_door", 0)) != 0: return "已经开始备劫行动，不能再改开局筹备。"
	if not run.get("busy", {}).is_empty() or run.get("sleeping", false) or str(run.get("pending_event", "")) != "": return "先前已有安排，不能再领取开局筹备。"
	var trade: Dictionary = run.get("trade", {})
	if not trade.get("quotes", {}).is_empty() or not trade.get("debt", {}).is_empty() or not trade.get("aid", []).is_empty(): return "已经形成报价或往来约定，不能改开局筹备。"
	var crisis: Dictionary = run.get("crisis", {})
	if not crisis.get("active", {}).is_empty() or not crisis.get("pending", {}).is_empty() or int(crisis.get("serial", 0)) != 0 or not crisis.get("opening_reservation", {}).is_empty(): return "首场风声已有安排，不能改开局筹备。"
	var birth: Dictionary = s.birth
	if birth.is_empty() and id == "plain": return ""
	if not _birth_valid(run, birth): return "这份旧卷没有可核实的出生筹备凭据，只能照常备劫。"
	if birth.silver != run.get("silver") or birth.home != run.get("home", {}): return "出生物资已经改变，开局筹备已关闭。"
	return ""

static func _block(run: Dictionary, id: String) -> String:
	if not id in ACTIONS: return "没有这个开局筹备。"
	var a := _definition(id, _sources(run))
	var eligible := _eligibility(str(run.get("role", "")), a, _sources(run), Past.daily(run), run.get("tally", {}).get("vows", []), int(run.get("silver", 0)), run.get("home", {}))
	if eligible != "": return eligible
	return _access(run, id)

static func apply(run: Dictionary, id: String, token: String) -> String:
	if token != _token(run): return "这份开局安排已经过期，请重新查看。"
	var blocked := _block(run, id)
	if blocked != "": return blocked
	var s := state(run)
	var a := _definition(id, _sources(run))
	# Reserve only after every preflight. A failed reservation spends nothing.
	if id != "plain" and not Crisis.reserve_opening(run, str(a.kind), str(a.actor), int(a.warning_day)): return "首场风声已经形成，开局筹备未扣除任何钱物。"
	var effects := _neutral()
	if id != "plain":
		effects.silver_cost = int(a.silver)
		effects.hours = int(a.hours)
		effects.spent = a.spent.duplicate(true)
		effects.gained = a.gained.duplicate(true)
		run.silver = int(run.silver) - int(a.silver)
		Inv.take_all(run.home, a.spent)
		Inv.add_all(run.home, a.gained)
		run.hour = int(run.hour) + int(a.hours)
		var person: Dictionary = Trade.state(run).actors[a.actor]
		var before_trust := int(person.trust)
		var before_favors := int(person.favors)
		Trade.influence(run, str(a.actor), int(a.trust), "开局筹备：" + str(a.deed))
		person.favors = mini(3, int(person.favors) + int(a.favors))
		effects.contacts[a.actor] = {"trust": int(person.trust) - before_trust, "favors": int(person.favors) - before_favors}
		effects.first_warning = {"kind": a.kind, "actor": a.actor, "warning_day": int(a.warning_day)}
	s.choice = id
	s.applied = true
	s.effects = effects
	s.revision = int(s.revision) + 1
	var result := ("选择「%s」。" % a.name) + _hint(a)
	s.history.append({"day": int(run.day), "action": id, "result": result.left(240)})
	while s.history.size() > 8: s.history.pop_front()
	State.note(run, "开局筹备 · " + result)
	return ""

static func _effects(run: Dictionary) -> Dictionary:
	var s := state(run)
	if not s.get("applied", false) or str(s.get("choice", "")) in ["", "plain"]: return _neutral()
	# Do not forward unknown/corrupt saved fields to the director as public facts.
	var safe := Past.opening_snapshot({"schema": 1, "choice": str(s.choice), "applied": true, "effects": s.effects, "history": []})
	return safe.effects.duplicate(true) if not safe.is_empty() else _neutral()

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var inherited := _sources(run)
	var rows := []
	for id in ORDER:
		var a := _definition(id, inherited)
		if str(a.role) != "" and a.role != run.get("role", ""): continue
		rows.append({"id": id, "text": a.name, "hint": _hint(a), "block": _block(run, id)})
	var summary := "出门前从一种筹备开始；钱物、今世交情和首场风声都会变化，选择后不能兼得另一种。"
	if s.get("legacy", false): summary = "旧卷沿用原开局，没有补发物资、关系或危机安排。"
	elif s.get("applied", false): summary = "今世已选「%s」，开局的物资与交情已经入账，首场风声仍须核实和应对。" % str(ACTIONS.get(str(s.choice), {}).get("name", s.choice))
	var source_label := "今世没有可用的确证前世经历。"
	if Past.daily(run): source_label = "每日一局不使用前世经验，只能照常备劫。"
	elif not inherited.is_empty():
		var labels := []
		for source in inherited: labels.append("第%d世 %s" % [int(source.source_life), str(SOURCE_NAMES.get(source.tag, source.tag))])
		source_label = "出生时固定的经历：" + "；".join(labels) + "。邻人要自己记起来，才知道前世的事。"
	return {"title": "开局筹备", "summary": summary, "token": _token(run), "options": rows, "history": s.history.duplicate(true), "effects": _effects(run), "source_label": source_label}

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	var tags := []
	for source in _sources(run): tags.append(str(source.tag))
	return {"schema": 1, "role": str(run.get("role", "")), "choice": str(s.get("choice", "")), "applied": bool(s.get("applied", false)), "effects": _effects(run), "legacy_tags": tags}
