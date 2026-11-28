extends RefCounted
## 三路旧运单。第一站的去留与第二站剩下的物资都随本世存档。
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")

const TRAILS := {
	"school": {
		"name": "送簿人的书匣", "source_stage": "s0", "dest": "mortuary", "dest_stage": "s3", "landmark": "守庄人柜",
		"clue": "课簿末页夹着一张寄单。教习去义庄替亡人记名，临走把干粮和书匣的取件联拴在了一起。",
		"keep": "拆开纸封，取送簿人的路粮", "small": {"flatbread": 1},
		"mark": "用符纸拓下寄单，留下路粮", "cost": {"talisman_paper": 1}, "mark_time": 15,
		"open": "对上柜中名册，拆开教习书匣", "open_time": 15, "goods": {"book_build": 1, "lamp_oil": 1}},
	"pharmacy_ruin": {
		"name": "义诊药箱", "source_stage": "s0", "dest": "city_god", "dest_stage": "s2", "landmark": "偏殿供品",
		"clue": "水渍下面还有一行蝇头字：庙里行过义诊，余药收在偏殿供品底下。旧药签的青记快褪尽了。",
		"keep": "拆掉药签，取诊台上的药", "small": {"salve": 1},
		"mark": "用艾草揉出青汁，拓下药签", "cost": {"mugwort": 1}, "mark_time": 20,
		"open": "照药签在偏殿取出施药箱", "open_time": 10, "goods": {"salve": 2, "plague_powder": 2}},
	"lumber": {
		"name": "粮车匠的夹箱", "source_stage": "s0", "dest": "granary", "dest_stage": "s2", "landmark": "粮车车底",
		"clue": "工棚还搁着粮车匠的木牌。劈开能当柴烧，侧着看才知道，牌上的凿痕对应官仓粮车的暗销。",
		"keep": "劈了木牌，收起干柴", "small": {"firewood": 1},
		"mark": "用铁钉在木牌上刻下销位", "cost": {"nails": 1}, "mark_time": 25,
		"open": "按木牌拔销，拉出粮车夹箱", "open_time": 20, "goods": {"wood": 2, "nails": 4}},
}

static func record(run: Dictionary, source: String) -> Dictionary:
	return run.get("supply_trails", {}).get(source, {})


static func at_stage(run: Dictionary, stage: String) -> String:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or ex.get("only_investigate", false): return ""
	var pid := str(ex.point)
	if TRAILS.has(pid) and TRAILS[pid].source_stage == stage and ex.get("journey", {}).get("completed", {}).has(stage):
		return pid
	for source: String in TRAILS:
		var trail: Dictionary = TRAILS[source]
		if pid == trail.dest and stage == trail.dest_stage and record(run, source).get("status", "") in ["marked", "open", "empty"]:
			return source
	return ""


static func discover(run: Dictionary, stage: String) -> void:
	var pid := str(run.explore.point)
	if at_stage(run, stage) != pid or not record(run, pid).is_empty(): return
	if not run.has("supply_trails"): run["supply_trails"] = {}
	run.supply_trails[pid] = {"status": "found"}
	State.note(run, "在%s发现了%s，可取现货，也可留下记号另寻旧藏。" % [Data.table("map_points")[pid].name, TRAILS[pid].name])


static func destination(source: String) -> String:
	var trail: Dictionary = TRAILS[source]
	return "%s · %s" % [Data.table("map_points")[trail.dest].name, trail.landmark]


static func map_note(run: Dictionary, pid: String) -> String:
	for source: String in TRAILS:
		var trail: Dictionary = TRAILS[source]
		var rec := record(run, source)
		var status := str(rec.get("status", ""))
		if status == "found" and pid == source: return "%s尚未定夺，可再查原处。" % trail.name
		if status not in ["marked", "open"] or pid != trail.dest: continue
		var fall_day := int(Data.table("map_points")[pid].get("fall_day", 0))
		if fall_day > 0 and int(run.pday) >= fall_day: return "%s留在%s，地点已沦陷。" % [trail.name, trail.landmark]
		return "%s在%s%s。" % [trail.name, trail.landmark, "，箱中还有" + Data.describe_items(rec.remaining) if status == "open" else "，寻到记号便能取物"]
	return ""


static func room_left(run: Dictionary, item: String) -> int:
	var weight := float(Data.item(item).weight)
	return maxi(0, floori((float(State.role(run).carry) - Inv.weight(run.explore.bag) + 0.00001) / weight))


static func block(run: Dictionary, source: String, action: String) -> String:
	var trail: Dictionary = TRAILS[source]
	var status := str(record(run, source).get("status", "found"))
	match action:
		"keep", "mark":
			if run.explore.point != source or status != "found": return "此处的取舍已经记下。"
			if action == "keep":
				for item: String in trail.small:
					if room_left(run, item) < int(trail.small[item]): return "背囊已满，先腾出地方。"
			elif not Inv.has_all(run.explore.bag, trail.cost):
				return "背囊需有%s。可先从这处现场收进背囊。" % Data.describe_items(trail.cost)
		"open":
			if run.explore.point != trail.dest or status != "marked": return "眼下没有可开启的旧藏。"
		_: return "没有这种做法。"
	return ""


static func minutes(source: String, action: String) -> int:
	var trail: Dictionary = TRAILS[source]
	if action == "open": return int(trail.open_time)
	if action == "mark": return int(trail.mark_time)
	return 5


static func settle(run: Dictionary, source: String, action: String) -> String:
	# 旧途中存档可能已经搜过源头，但尚未生成此世的运单记录。
	if action != "open": discover(run, TRAILS[source].source_stage)
	var trail: Dictionary = TRAILS[source]
	var rec := record(run, source)
	var message := ""
	match action:
		"keep":
			rec.status = "kept"
			Inv.add_all(run.explore.bag, trail.small)
			message = "将%s收入背囊，旧运单就此作罢。" % Data.describe_items(trail.small)
		"mark":
			rec.status = "marked"
			Inv.take_all(run.explore.bag, trail.cost)
			message = "留好了记号。下趟去%s，还能找到%s。" % [destination(source), Data.describe_items(trail.goods)]
		"open":
			rec.status = "open"
			rec["remaining"] = trail.goods.duplicate()
			message = "找到了%s，按背囊余量取走。余货仍在此处。" % Data.describe_items(trail.goods)
	var note := "【%s】%s" % [trail.name, message]
	run.explore.notes.append(note)
	State.note(run, note)
	return note


static func take_one(run: Dictionary, stage: String, item: String) -> int:
	var source := at_stage(run, stage)
	if source == "" or run.explore.point == source: return 0
	var rec := record(run, source)
	if rec.get("status") != "open" or Inv.count(rec.remaining, item) < 1 or room_left(run, item) < 1: return 0
	Inv.add(rec.remaining, item, -1)
	Inv.add(run.explore.bag, item, 1)
	if rec.remaining.is_empty():
		rec.status = "empty"
		State.note(run, "【%s】最后一件物资已装进背囊，旧藏取尽。" % TRAILS[source].name)
	return 1
