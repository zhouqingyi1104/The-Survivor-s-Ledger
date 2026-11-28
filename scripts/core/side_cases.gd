extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")

## 存档信封尚未归一化，路线编号可能是 JSON 浮点数。
static func valid_saved(run: Dictionary) -> bool:
	var book = run.get("hundred_days", {}).get("side_cases", {})
	if not book is Dictionary: return false
	if book.is_empty(): return _valid_trip(run, {}, {})
	if not book.get("active") is String or not book.get("records") is Dictionary: return false
	if book.active != "" and not book.records.has(book.active): return false
	for id in book.records:
		var entry = book.records[id]
		if not entry is Dictionary: return false
		var row := _row(str(id))
		var index = entry.get("route")
		if row.is_empty() or typeof(index) not in [TYPE_FLOAT, TYPE_INT]: return false
		if index != int(index) or index < 0 or index >= row.routes.size(): return false
		if not entry.get("evidence", false) is bool or not entry.get("detail", false) is bool: return false
		if entry.get("detail", false) and (not entry.get("evidence", false) or not row.routes[int(index)].has("inspection")): return false
		var choice = entry.get("choice", "")
		if not choice is String or (choice == "") != (id == book.active): return false
		if choice != "":
			var option := _option(row, choice)
			if not entry.get("evidence", false) or option.is_empty(): return false
			if not _matches(run, option.get("when", {}), entry.get("detail", false)): return false
	return _valid_trip(run, _row(book.active), book.records.get(book.active, {}))


## 在途物证和工时都能跨存档；导入时核对目的地、现场索引、同伴与材料。
static func _valid_trip(run: Dictionary, row: Dictionary, record: Dictionary) -> bool:
	var ex: Dictionary = run.get("explore", {})
	var busy: Dictionary = run.get("busy", {})
	var kind = busy.get("kind", "")
	var work = busy.get("data", {})
	var spots = ex.get("spots", [])
	if not spots is Array: return false
	var index := -1
	for i in spots.size():
		if not spots[i] is Dictionary: return false
		if spots[i].has("side_case"):
			if index != -1: return false
			index = i
	var field_cargo := ex.has("case_cargo") or ex.has("case_detail")
	var carrying: bool = work is Dictionary and (work.has("case_cargo") or work.has("case_detail"))
	if index == -1 and not field_cargo and not carrying and kind not in ["case_search", "case_work"]: return true
	if row.is_empty() or record.is_empty() or not work is Dictionary: return false
	var route: Dictionary = row.routes[int(record.route)]
	var person = route.get("person", row.person)
	if index >= 0:
		var spot: Dictionary = spots[index]
		if record.get("evidence", false) or ex.get("point") != route.site or spot.side_case != row.id: return false
		if not spot.get("done") is bool or spot.get("person") != person or spot.get("prop") != route.prop or spot.get("name") != route.spot: return false
	if field_cargo:
		if index == -1 or ex.get("case_cargo") != row.id or not spots[index].done or ex.get("caught", false): return false
		if not _valid_detail(ex.get("case_detail", false), route): return false
	if carrying:
		var returning: bool = (kind == "travel" and work.get("direction") == "return") or (kind == "mainline" and work.get("action") in ["return_mortuary", "return_temple"])
		if not returning or not ex.is_empty() or record.get("evidence", false): return false
		if work.get("case_cargo") != row.id or work.get("point") != route.site or not _valid_detail(work.get("case_detail", false), route): return false
	if kind == "case_search":
		if index == -1 or spots[index].done or field_cargo or ex.get("caught", false) or ex.get("curfew_due", false): return false
		if work.get("id") != row.id or work.get("point") != route.site or work.get("idx") != index: return false
		if not _valid_detail(work.get("detail", false), route): return false
		var minutes := int(route.minutes) + (int(route.inspection.extra_minutes) if work.get("detail", false) else 0)
		return _valid_work_time(busy, minutes)
	if kind == "case_work":
		if not ex.is_empty() or not record.get("evidence", false) or work.get("id") != row.id: return false
		if not work.get("choice") is String: return false
		var option := _option(row, work.choice)
		if option.is_empty() or not _matches(run, option.get("when", {}), record.get("detail", false)): return false
		return work.get("person") == option.get("work_person", person) and work.get("prop") == option.get("work_prop", route.prop) and _valid_work_time(busy, int(option.minutes))
	return true


static func _valid_detail(value, route: Dictionary) -> bool:
	return value is bool and (not value or route.has("inspection"))


static func _valid_work_time(busy: Dictionary, minutes: int) -> bool:
	for key in ["start", "end"]:
		var time = busy.get(key)
		if typeof(time) not in [TYPE_FLOAT, TYPE_INT] or time != int(time) or time < 0: return false
	return int(busy.end) - int(busy.start) == minutes


static func _book(run: Dictionary) -> Dictionary:
	return run.get("hundred_days", {}).get("side_cases", {})


static func _record(run: Dictionary, id: String) -> Dictionary:
	return _book(run).get("records", {}).get(id, {})


static func completed_choice(run: Dictionary, id: String) -> String:
	return str(_record(run, id).get("choice", ""))


static func _matches(run: Dictionary, requirements: Dictionary, detail := false) -> bool:
	if requirements.get("detail", false) and not detail: return false
	if requirements.has("flag") and not State.flag(run, str(requirements.flag)): return false
	var letters: Dictionary = run.hundred_days.get("choices", {})
	for id in requirements.get("letters", {}):
		if letters.get(id, "") != requirements.letters[id]:
			return false
	for id in requirements.get("cases", {}):
		var choice := completed_choice(run, id)
		if choice == "" or requirements.cases[id] not in ["*", choice]:
			return false
	return true


static func _row(id: String) -> Dictionary:
	for row in Data.table("side_cases").cases:
		if row.id == id: return row
	return {}


static func _route_index(run: Dictionary, row: Dictionary) -> int:
	for i in row.routes.size():
		if _matches(run, row.routes[i].get("when", {})): return i
	return -1


static func _option(row: Dictionary, id: String) -> Dictionary:
	for option in row.get("options", []):
		if option.id == id: return option
	return {}


static func _view(run: Dictionary, row: Dictionary) -> Dictionary:
	var record := _record(run, row.id)
	var stage := "offered"
	var choice := str(record.get("choice", ""))
	if run.get("phase") != "post" and choice == "": return {}
	if record.is_empty():
		if int(run.pday) < int(row.day) or not _matches(run, row.get("requires", {})): return {}
	elif choice != "":
		stage = "done"
	elif run.get("busy", {}).get("kind") == "case_work" and run.busy.data.get("id") == row.id:
		stage = "working"
	else:
		stage = "returned" if record.get("evidence", false) else "field"
	var index := int(record.route) if record.has("route") else _route_index(run, row)
	if index < 0 or index >= row.routes.size(): return {}
	var route: Dictionary = row.routes[index].duplicate()
	route["person"] = route.get("person", row.person)
	var options := []
	for option in row.options:
		if _matches(run, option.get("when", {}), record.get("detail", false)): options.append(option)
	var selected := _option(row, choice)
	return {"id": row.id, "day": row.day, "title": row.title, "lead": row.lead,
		"person": route.person, "route": route, "options": options, "stage": stage, "detail": record.get("detail", false),
		"finding": str(route.get("inspection", {}).get("finding", "")) if record.get("detail", false) else "",
		"choice": choice, "result": selected.get("result", ""), "epilogue": selected.get("epilogue", selected.get("result", ""))}


static func list_cases(run: Dictionary) -> Array:
	var rows := []
	if not run.get("hundred_days") is Dictionary: return rows
	for row in Data.table("side_cases").cases:
		var page := _view(run, row)
		if not page.is_empty(): rows.append(page)
	return rows


static func view(run: Dictionary, id: String) -> Dictionary:
	if not run.get("hundred_days") is Dictionary or id == "": return {}
	var row := _row(id)
	return {} if row.is_empty() else _view(run, row)


static func active(run: Dictionary) -> Dictionary:
	return view(run, str(_book(run).get("active", "")))


static func at_site(run: Dictionary, pid: String) -> Dictionary:
	var page := active(run)
	if page.get("stage") == "field" and page.route.site == pid: return page
	return {}


static func _home_block(run: Dictionary) -> String:
	if run.get("phase") != "post" or not run.get("hundred_days") is Dictionary: return "这件事须在本卷灾后办理。"
	if not run.get("explore", {}).is_empty() or run.get("neighbor_travel", false) or str(run.get("home_floor", "")).begins_with("guest_"): return "回到自家再同街坊商量。"
	if run.sleeping or not run.busy.is_empty(): return "先忙完手头的事。"
	if run.pending_event != "" or run.dawn_due or run.wave_due or run.plan_due or not run.wave_report.is_empty() or not run.fight.is_empty() or (not run.night.is_empty() and not run.night.get("done", false)): return "先处理眼前的事。"
	return ""


static func accept_block(run: Dictionary, id: String) -> String:
	var blocked := _home_block(run)
	if blocked != "": return blocked
	if str(_book(run).get("active", "")) != "": return "已经约了一位街坊，先办完或放下那件事。"
	if view(run, id).get("stage") != "offered": return "还没有这条线索，或此事已了。"
	return ""


static func accept(run: Dictionary, id: String) -> String:
	var blocked := accept_block(run, id)
	if blocked != "": return blocked
	var row := _row(id)
	if _book(run).is_empty():
		run.hundred_days.side_cases = {"active": "", "records": {}}
	var book := _book(run)
	book.active = id
	book.records[id] = {"route": _route_index(run, row)}
	var page := view(run, id)
	State.note(run, "约下%s，一同到%s查%s。" % [page.person, Data.table("map_points")[page.route.site].name, page.route.spot])
	return ""


static func abandon_block(run: Dictionary, id: String) -> String:
	var blocked := _home_block(run)
	if blocked != "": return blocked
	if _book(run).get("active", "") != id or id == "": return "手头没有这件事。"
	return ""


static func abandon(run: Dictionary, id: String) -> String:
	var blocked := abandon_block(run, id)
	if blocked != "": return blocked
	var book := _book(run)
	book.records.erase(id)
	book.active = ""
	State.note(run, "同街坊放下《%s》，以后可以从头查。" % _row(id).title)
	return ""


static func add_objective(run: Dictionary, pid: String, spots: Array) -> void:
	var page := at_site(run, pid)
	if page.is_empty(): return
	spots.push_front({"side_case": page.id, "name": page.route.spot, "person": page.person,
		"prop": page.route.get("prop", ""), "done": false})


static func search(run: Dictionary, idx: int, method: String) -> Dictionary:
	var ex: Dictionary = run.explore
	var page := at_site(run, str(ex.point))
	if page.is_empty() or ex.spots[idx].get("side_case") != page.id: return {"blocked": "约下的街坊或地点已经不同。"}
	if State.attr(run, "energy") < 4: return {"blocked": "调查需要 4 点精力。"}
	var minutes := int(page.route.minutes)
	var risk := int(page.route.risk)
	var detail := false
	if method.begins_with("inspect:"):
		var inspection: Dictionary = page.route.get("inspection", {})
		var answer := method.trim_prefix("inspect:")
		var reply := "这处物证没有这样的判读方法。"
		for candidate in inspection.get("answers", []):
			if candidate.id == answer:
				reply = str(candidate.reply)
				detail = inspection.get("correct") == answer
				break
		if not detail: return {"side_case": true, "blocked": reply, "text": reply}
		minutes += int(inspection.extra_minutes)
		risk += int(inspection.extra_risk)
	elif method not in ["", "normal"]:
		return {"blocked": "这处只查约好的证物。"}
	State.add_attr(run, "energy", -4)
	ex.exposure = mini(100, int(ex.exposure) + risk)
	run.busy = {"kind": "case_search", "label": "与%s查%s" % [page.person, page.route.spot],
		"start": run.t, "end": int(run.t) + minutes, "data": {"id": page.id, "point": ex.point, "idx": idx, "detail": detail}}
	return {"side_case": true, "started": true, "found": {}, "gain": risk, "caught": false, "full": false, "clue": "",
		"text": "与%s查%s，要花 %d 分钟。查完将证物带回家。" % [page.person, page.route.spot, minutes]}


static func finish_search(run: Dictionary, data: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	var page := at_site(run, str(data.get("point", "")))
	var idx := int(data.get("idx", -1))
	if run.get("phase") != "post" or page.is_empty() or page.id != data.get("id") or ex.get("point") != page.route.site: return
	if ex.get("caught", false) or ex.get("curfew_due", false) or int(run.t) % 1440 >= 900: return
	if idx < 0 or idx >= ex.spots.size() or ex.spots[idx].get("side_case") != page.id or ex.spots[idx].done: return
	ex.spots[idx].done = true
	ex["case_cargo"] = page.id
	if data.get("detail", false) and page.route.has("inspection"):
		ex["case_detail"] = true
		ex.notes.append(str(page.route.inspection.finding))
		State.note(run, str(page.route.inspection.finding))
	ex.notes.append(str(page.route.clue))
	State.note(run, "%s：%s（随身证物，待返家。）" % [page.person, page.route.clue])


static func finish_return(run: Dictionary, data: Dictionary) -> void:
	var id := str(data.get("case_cargo", ""))
	if id == "" or run.get("phase") != "post" or not run.explore.is_empty(): return
	var page := at_site(run, str(data.get("point", "")))
	if page.get("id") != id: return
	var record := _record(run, id)
	record["evidence"] = true
	if data.get("case_detail", false) and page.route.has("inspection"): record["detail"] = true
	State.note(run, "%s和你把%s带回家，可以商定如何处置。" % [page.person, page.route.spot])


static func settle_block(run: Dictionary, id: String, choice: String) -> String:
	var blocked := _home_block(run)
	if blocked != "": return blocked
	var page := active(run)
	if page.get("id") != id or page.get("stage") != "returned": return "先与同行人从现场带回证物。"
	var option := _option(page, choice)
	if option.is_empty(): return "这一世没有约成这个办法。"
	if State.attr(run, "energy") < 5: return "合做这件事需要 5 点精力。"
	if not Inv.has_all(run.home, option.cost): return "家中缺料，需要%s。" % Data.describe_items(option.cost)
	if int(run.t) % 1440 + int(option.minutes) > 720: return "街坊赶在天黑前收工，等明早再动手。"
	return ""


static func settle(run: Dictionary, id: String, choice: String) -> String:
	var blocked := settle_block(run, id, choice)
	if blocked != "": return blocked
	var page := active(run)
	var option := _option(page, choice)
	Inv.take_all(run.home, option.cost)
	State.add_attr(run, "energy", -5)
	run.busy = {"kind": "case_work", "label": str(option.label), "start": run.t,
		"end": int(run.t) + int(option.minutes), "data": {"id": id, "choice": choice,
			"person": option.get("work_person", page.person), "prop": option.get("work_prop", page.route.get("prop", ""))}}
	State.note(run, "同%s开工：%s。" % [run.busy.data.person, option.label])
	return ""


static func finish_work(run: Dictionary, data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var page := active(run)
	if run.get("phase") != "post" or page.get("id") != id or page.get("stage") != "returned": return
	var option := _option(page, str(data.get("choice", "")))
	if option.is_empty(): return
	_record(run, id)["choice"] = option.id
	_book(run)["active"] = ""
	Inv.add_all(run.home, option.gain)
	State.note(run, "%s · %s" % [page.title, option.result])
