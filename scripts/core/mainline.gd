extends RefCounted
## Current-life evidence and real work. Recalled clues never stand in for proof.
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const CONTACT_END := 11 * 1440 + 720 # Day12 18:00.
const FINAL_END := 18 * 1440 + 720 # Day19 18:00.
const ESCAPE_OPEN := 17 * 1440 + 120 # Day18 08:00.
const COSTS := {"host": {"water": 1, "firewood": 1}, "self_route": {"rice": 1},
	"disrupt": {"talisman": 1, "lamp_oil": 1}, "copy": {},
	"prepare_escape": {"rice": 3, "water": 3, "wood": 2, "nails": 1},
	"prepare_ritual": {"talisman": 2, "lamp_oil": 1, "dog_blood": 1}, "escape": {},
	"prepare_light_escape": {"rice": 2, "water": 2},
	"prepare_convoy": {"rice": 4, "water": 4, "wood": 1, "nails": 1},
	"prepare_paper_ritual": {"talisman": 1, "talisman_paper": 3, "cinnabar": 2, "lamp_oil": 1}}
const ACTIONS := {"host": ["接待道士", 30, 4], "self_route": ["买下义庄旧路线", 60, 4],
	"disrupt": ["截断运尸支路", 60, 6], "copy": ["抄录运尸簿", 30, 4],
	"prepare_escape": ["筹备撤离行装", 90, 8], "prepare_ritual": ["筹备封阵法具", 120, 10],
	"escape": ["沿后山道撤离", 120, 10],
	"prepare_light_escape": ["筹备轻装更道", 120, 8],
	"prepare_convoy": ["筹备趟子手早行", 120, 12],
	"prepare_paper_ritual": ["筹备纸阵法具", 150, 10]}
const STAGES := {"waiting": "等待道士线索", "contact": "道士来访", "fallback": "自行打听义庄", "mortuary": "查义庄", "mortuary_choice": "处置运尸簿", "temple": "查青云观", "routes": "选择最后的活法", "escape_ready": "等着动身撤离", "ritual_ready": "亲赴青云观封阵", "sealed": "七灯已熄，还要守过残潮", "hold": "守住这座宅院", "closed": "这一世的事已了结", "failed": "错过期限，转守宅院", "endless": "劫后继续生活"}

static func _day(run: Dictionary) -> int:
	return maxi(1, int(run.get("t", 0)) / 1440 + 1)

static func state(run: Dictionary) -> Dictionary:
	if not run.get("mainline") is Dictionary or run.mainline.is_empty():
		run["mainline"] = {"schema": 1, "revision": 0, "start_day": maxi(3, _day(run) + 1), "stage": "waiting",
			"evidence": {"mortuary": false, "temple": false}, "route": "", "interventions": {"disrupt_t": -1, "ritual_t": -1},
			"work": {}, "carried": "", "ending": {}, "history": [], "last_result": "这一世还没去查。前世的残卷能读，但算不得这一世的证物。", "serial": 0}
	return run.mainline

static func _token(run: Dictionary) -> String:
	var s := state(run)
	return "mainline:%s:%d:%s" % [str(Past.state(run).id), int(s.revision), str(s.stage)]

static func _fact(run: Dictionary, action: String, result: String) -> String:
	var s := state(run)
	s.history.append({"day": _day(run), "t": int(run.get("t", 0)), "action": action.left(32), "result": result.left(240)})
	while s.history.size() > 16: s.history.pop_front()
	s.last_result = result.left(240)
	s.revision = int(s.revision) + 1
	State.note(run, "尸劫来历 · " + result)
	return result

static func _same_busy(run: Dictionary, work: Dictionary) -> bool:
	var busy: Dictionary = run.get("busy", {})
	return busy.get("kind", "") == "mainline" and busy.get("data", {}).get("id", "") == work.get("id", "") and busy.get("data", {}).get("action", "") == work.get("action", "")

static func _reset_spot(run: Dictionary, work: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	var objective_id := str(work.get("data", {}).get("objective", ""))
	for spot in ex.get("spots", []):
		if spot.get("mainline", "") == objective_id: spot.done = false

static func poll(run: Dictionary) -> String:
	if run.get("phase", "") != "post": return ""
	var s := state(run)
	var facts := []
	if not s.work.is_empty() and not _same_busy(run, s.work):
		var work: Dictionary = s.work
		_reset_spot(run, work)
		s.work = {}
		facts.append(_fact(run, "interrupted", "%s被打断，没做成；花掉的东西和精力不退，期限前还能再来。" % str(work.get("label", "调查"))))
	var now := int(run.get("t", 0))
	if s.stage == "waiting" and now >= (int(s.start_day) - 1) * 1440 + 120:
		s.stage = "contact" if now < CONTACT_END else "fallback"
		facts.append(_fact(run, "contact", "游方道士带来义庄和七盏灯的消息。第 12 日 18:00 前可以接待他；拒绝或错过了，也能自己去查。" if s.stage == "contact" else "道士已经离开；第 5 日起可付米 1 自行打听义庄的路。"))
	if s.stage == "contact" and now >= CONTACT_END:
		s.stage = "fallback"
		facts.append(_fact(run, "contact_timeout", "道士走了。没花东西，也没得到他的符和画符的法子；还可以付米 1 自己打听义庄的路。"))
	var finishing_escape: bool = not s.work.is_empty() and s.work.action == "escape" and int(s.work.end_t) == now and now == FINAL_END and _same_busy(run, s.work)
	if now >= FINAL_END and not finishing_escape and s.stage in ["contact", "fallback", "mortuary", "mortuary_choice", "temple", "routes", "escape_ready", "ritual_ready"]:
		var previous := str(s.route)
		if not s.work.is_empty():
			_reset_spot(run, s.work)
			if _same_busy(run, s.work): run.busy = {}
			s.work = {}
		s.stage = "failed"
		s.route = "hold"
		s["carried"] = ""
		run.get("explore", {}).erase("mainline_cargo")
		facts.append(_fact(run, "deadline", "第 19 日 18:00 的最后期限过了：%s。只能守在宅院里，熬过第二十夜。" % ("备好的行装没能用上" if previous == "escape" else ("备好的法具没能上山用上" if previous == "ritual" else "没查完的事就此放下"))))
	return "\n".join(facts)

static func _access(run: Dictionary, outside := false) -> String:
	if run.get("phase", "") != "post": return "眼下没法接着查尸劫来历。"
	if run.get("pending_event", "") != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事件或夜战。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty() or not state(run).work.is_empty(): return "正在忙别的事。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，这会儿不能动身去查。"
	if run.get("neighbor_travel", false): return "仍在返程，先回到宅院。"
	if not outside and not run.get("explore", {}).is_empty(): return "先回到宅院再安排。"
	return ""

## Read only the completed rule state; Identity imports Mainline, so no reverse import.
static func _identity_cap(run: Dictionary, cap: String) -> bool:
	var defs := {"light_escape": ["watchman_lane", "watchman", ""], "early_convoy": ["escort_convoy", "escort", "escaped_city"], "paper_ritual": ["scholar_diagram", "scholar", "sealed_lamps"]}
	if not defs.has(cap): return false
	var s: Dictionary = run.get("identity", {})
	var def: Array = defs[cap]
	if s.get("schema") != 1 or s.get("chosen", "") != def[0] or run.get("role", "") != def[1] or s.get("learned", []) != [cap] or not Past._trade_integer(s.get("completed_t"), 0, int(run.get("t", 0))): return false
	if def[2] == "": return true
	if Past.daily(run): return false
	var p := Past.state(run)
	for source in s.get("inherited", []):
		if source is Dictionary and source.get("tag", "") == def[2] and Past._trade_integer(source.get("source_life"), 1, int(p.get("generation", 0)) - 1) and source.get("source_id") is String and not source.source_id.is_empty() and source.source_id.length() <= 80 and source.source_id != p.id: return true
	return false

static func _escape_spec(run: Dictionary, method := "") -> Array:
	if method == "": method = str(state(run).get("escape_method", "normal"))
	if method == "light": return ["沿轻装更道撤离", 150, 10]
	if method == "convoy": return ["沿前世路线提早出城", 180, 14]
	return ACTIONS.escape

static func _allowed(stage: String, run: Dictionary = {}) -> Array:
	match stage:
		"contact": return ["host", "refuse"]
		"fallback": return ["self_route"]
		"mortuary_choice": return ["disrupt", "copy", "seal"]
		"routes":
			var out := ["hold", "prepare_escape", "prepare_ritual"]
			for pair in [["light_escape", "prepare_light_escape"], ["early_convoy", "prepare_convoy"], ["paper_ritual", "prepare_paper_ritual"]]:
				if _identity_cap(run, pair[0]): out.append(pair[1])
			return out
		"escape_ready": return ["escape"]
	return []

static func _action_block(run: Dictionary, action: String) -> String:
	var access := _access(run)
	if access != "": return access
	var s := state(run)
	var now := int(run.get("t", 0))
	if not action in _allowed(str(s.stage), run): return "眼下还不能这样选。"
	if now < (int(s.start_day) - 1) * 1440 + 120: return "道士的消息还没传来。"
	if action == "refuse": return "" if now < CONTACT_END else "道士已经走了。"
	if action in ["hold", "seal"]: return ""
	if action == "self_route" and _day(run) < 5: return "第 5 日起才打听得到去义庄的路。"
	if action.begins_with("prepare_") and _day(run) < 12: return "第 12 日起才能为最后的出路做准备。"
	if action in ["prepare_escape", "prepare_light_escape", "prepare_convoy", "escape"] and run.get("endless", false): return "「守到死」里不能撤离；调查、断运和封阵照样能做。"
	var spec: Array = _escape_spec(run) if action == "escape" else ACTIONS[action]
	var end := now + int(spec[1])
	if action == "host" and end >= CONTACT_END: return "来不及在道士离开前完成接待。"
	if action == "self_route" and end + 140 >= FINAL_END: return "来不及去义庄一趟再回来了，这份路钱就不收了。"
	if action in ["disrupt", "copy"] and end + 140 >= FINAL_END: return "来不及再上一趟青云观了，不如封存证物、守住宅院。"
	if action in ["prepare_escape", "prepare_light_escape", "prepare_convoy"]:
		var travel := 150 if action == "prepare_light_escape" else (180 if action == "prepare_convoy" else 120)
		if end + travel > FINAL_END: return "备完行装就剩不下撤离要的 %d 分钟了，不必再花这份料。" % travel
	if action in ["prepare_ritual", "prepare_paper_ritual"] and end + 60 + 90 >= FINAL_END: return "备完法具就来不及上山封阵（要 90 分钟）了，不必再花这份料。"
	if action == "escape":
		var method := str(s.get("escape_method", "normal"))
		if method == "convoy" and not _identity_cap(run, "early_convoy"): return "这一世用不上趟子手的旧路经验。"
		if method == "light" and not _identity_cap(run, "light_escape"): return "这一世还没探好轻装走的更道。"
		var open := ESCAPE_OPEN - (1440 if method == "convoy" else 0)
		if now < open: return "第 %d 日 08:00 起才能动身撤离。" % (17 if method == "convoy" else 18)
		if end > FINAL_END: return "来不及在第 19 日 18:00 前完成 %d 分钟撤离。" % int(spec[1])
	elif action != "host" and end >= FINAL_END: return "最后的期限已过，不能再开工。"
	if float(run.get("attrs", {}).get("energy", 0.0)) < int(spec[2]): return "精力不足，需要 %d。" % int(spec[2])
	if not Inv.has_all(run.home, COSTS[action]): return "需要%s。" % Data.describe_items(COSTS[action])
	return ""

static func _start(run: Dictionary, action: String, label: String, minutes: int, data: Dictionary = {}) -> String:
	var s := state(run)
	s.serial = int(s.serial) + 1
	var id := "mainline:%s:%d" % [str(Past.state(run).id), int(s.serial)]
	var end := int(run.t) + minutes
	s.work = {"id": id, "action": action, "label": label, "start_t": int(run.t), "end_t": end, "data": data.duplicate(true)}
	run.busy = {"kind": "mainline", "label": label, "start": int(run.t), "end": end, "data": {"id": id, "action": action}}
	return _fact(run, "start_" + action, "开始%s，要 %d 分钟。做完才算数，被打断不退。" % [label, minutes])

static func act(run: Dictionary, action: String, token: String) -> String:
	if token != _token(run): return "情况已经变了，请重新看一遍。"
	var blocked := _action_block(run, action)
	if blocked != "": return blocked
	var s := state(run)
	if action == "refuse":
		s.stage = "fallback"
		_fact(run, "refuse", "你没有接待道士。没花东西，也没学画符、没得到符；第 5 日起还能付米 1 自己打听义庄。")
		return ""
	if action in ["hold", "seal"]:
		s.route = "hold"
		s.stage = "hold"
		_fact(run, action, "你%s：不再花东西，也不再撤离或封阵，就守在宅院里直到第二十夜。" % ("封存今世运尸簿" if action == "seal" else "决定保留物资、坚守宅院"))
		return ""
	Inv.take_all(run.home, COSTS[action])
	var spec: Array = _escape_spec(run) if action == "escape" else ACTIONS[action]
	State.add_attr(run, "energy", -int(spec[2]))
	_start(run, action, str(spec[0]), int(spec[1]))
	return ""

static func options(run: Dictionary) -> Array:
	var labels := {"host": "接待道士", "refuse": "婉拒来访，自行寻路", "self_route": "付米买下旧路线", "disrupt": "截断运尸支路", "copy": "抄录线索，保留材料", "seal": "封存证据，留守宅院", "hold": "选择坚守", "prepare_escape": "筹备撤离", "prepare_ritual": "筹备破阵", "escape": "动身离城"}
	var hints := {"host": "清水 ×1、柴 ×1，30 分钟、精力 4。招待完他会教你画符，留下镇尸符 ×1、符纸 ×2 和一页残卷，告诉你义庄在哪。", "refuse": "不花东西，不算失约。第 5 日起可付米 1 自己打听，但没有道士的符和画符的法子。", "self_route": "米 ×1，60 分钟、精力 4。打听到去义庄的路，但没有道士的符和画符的法子。", "disrupt": "镇尸符 ×1、灯油 ×1，60 分钟、精力 6。断了运尸的路，第 11、17 夜不会再有铜甲；也能去查青云观了。", "copy": "30 分钟、精力 4，不花料。能去查青云观，尸潮照旧。", "seal": "不花东西。定下坚守，不再撤离或破阵。", "hold": "不花东西也不花时间。定下坚守，不再撤离或破阵；守过第 20 夜还能接着过下去。", "prepare_escape": "米 ×3、清水 ×3、木料 ×2、铁钉 ×1，90 分钟、精力 8。备好就定下撤离：第 18 日 08:00 至第 19 日 18:00 之间动身，撤离要 120 分钟。提前离城，拿不到守满二十日的奖励。", "prepare_ritual": "镇尸符 ×2、灯油 ×1、黑狗血 ×1，120 分钟、精力 10。备好就定下破阵：还要上青云观封阵 90 分钟，第 19 日 18:00 前封好，第 20 夜才会变弱。", "escape": "120 分钟、精力 10，第 19 日 18:00 前走完。走了就回不来这座宅院，也拿不到守满二十日的奖励。"}
	var rows := []
	labels.merge({"prepare_light_escape": "轻装更道撤离", "prepare_convoy": "趟子手提早出城", "prepare_paper_ritual": "以纸阵替狗血封阵"})
	hints.merge({"prepare_light_escape": "米 ×2、清水 ×2，120 分钟、精力 8。省下木料铁钉，但撤离要 150 分钟、精力 10，同样在第 18 日 08:00 至第 19 日 18:00 之间。", "prepare_convoy": "米 ×4、清水 ×4、木料 ×1、铁钉 ×1，120 分钟、精力 12。撤离要 180 分钟、精力 14，第 17 日 08:00 就能走，第 19 日 18:00 前走完；拿不到守满的奖励。", "prepare_paper_ritual": "镇尸符 ×1、符纸 ×3、朱砂 ×2、灯油 ×1，150 分钟、精力 10。不用黑狗血，但费纸砂和时间；之后还要上青云观封阵 90 分钟，再守过残潮。"})
	if str(state(run).get("escape_method", "normal")) != "normal":
		var spec := _escape_spec(run)
		hints.escape = "%d 分钟、精力 %d；%s起可以动身，第 19 日 18:00 前走完。走了就回不来这座宅院，也拿不到守满二十日的奖励。" % [int(spec[1]), int(spec[2]), "第 17 日 08:00" if state(run).escape_method == "convoy" else "第 18 日 08:00"]
	for action in _allowed(str(state(run).stage), run):
		rows.append({"id": action, "text": labels[action], "hint": hints[action], "block": _action_block(run, action)})
	return rows

static func objective(run: Dictionary, pid: String) -> Dictionary:
	var s := state(run)
	var id := ""
	if s.stage == "mortuary" and pid == "mortuary": id = "mortuary"
	elif s.stage == "temple" and pid == "taoist_temple": id = "temple"
	elif s.stage == "ritual_ready" and pid == "taoist_temple": id = "ritual"
	if id == "": return {}
	var minutes := 90 if id == "ritual" else 20
	var energy := 10 if id == "ritual" else 4
	var names := {"mortuary": "炼尸阵的运尸簿", "temple": "观主七灯图与后山道图", "ritual": "七星灯阵眼 · 按图封阵"}
	var hints := {"mortuary": "20 分钟、精力 4、外泄 35。查到的先贴身带着，再走 60 分钟回到家才算数；路上被追上就丢了，可以再去。", "temple": "20 分钟、精力 4、外泄 35。灯图和道图先贴身带着，再走 60 分钟回到家才算数；路上被追上就丢了，可以再去。", "ritual": "90 分钟、精力 10、外泄 45，第 19 日 18:00 前在阵眼做完。灯一熄，第 20 夜没有血月，来的也少两成；残潮还得守。"}
	var blocked := ""
	var return_time := 0 if id == "ritual" else 60
	var outbound := 0 if run.get("explore", {}).get("point", "") == pid else 60
	if int(run.get("t", 0)) + outbound + minutes + return_time >= FINAL_END: blocked = "来不及了：调查、回家或封阵，都得在第 19 日 18:00 前做完。"
	if State.attr(run, "energy") < energy: blocked = "精力不足，需要 %d。" % energy
	if not s.work.is_empty(): blocked = "先把手头的调查做完。"
	if int(run.get("t", 0)) < (int(s.start_day) - 1) * 1440 + 120: blocked = "道士的消息还没传来。"
	if id == "ritual" and s.get("ritual_method", "normal") == "paper" and not _identity_cap(run, "paper_ritual"): blocked = "这一世还没学会纸阵。"
	return {"id": id, "name": names[id], "hint": hints[id], "block": blocked, "minutes": minutes, "energy": energy}

static func add_objective(run: Dictionary, pid: String, spots: Array) -> void:
	var target := objective(run, pid)
	if target.is_empty(): return
	for spot in spots:
		if spot.get("mainline", "") == target.id: return
	spots.push_front({"name": target.name, "done": false, "mainline": target.id, "hint": target.hint})

static func _search_result(text: String, blocked := "") -> Dictionary:
	var out := {"found": {}, "gain": 0, "caught": false, "clue": "", "full": false, "mainline": true, "text": text}
	if blocked != "": out["blocked"] = blocked
	return out

static func search_objective(run: Dictionary, spot: Dictionary) -> Dictionary:
	var id := str(spot.get("mainline", ""))
	var ex: Dictionary = run.get("explore", {})
	var blocked := _access(run, true)
	var target := objective(run, str(ex.get("point", "")))
	if blocked == "" and not spot in ex.get("spots", []): blocked = "这里没有要查的东西。"
	if blocked == "" and (target.is_empty() or id != target.get("id", "") or spot.get("done", false) or ex.get("caught", false)): blocked = "这里现在查不了，或者已经查过。"
	if blocked == "": blocked = str(target.get("block", ""))
	if blocked != "": return _search_result(blocked, blocked)
	spot.done = true
	var gain := 45 if id == "ritual" else 35
	ex.exposure = mini(100, int(ex.get("exposure", 0)) + gain)
	if id == "ritual": State.add_attr(run, "energy", -6) # Post adds the common search cost4.
	_start(run, "search_" + id, str(target.name), int(target.minutes), {"objective": id, "point": str(ex.point)})
	var out := _search_result("开始%s，要 %d 分钟；阳气外泄多了 %d。" % [target.name, int(target.minutes), gain])
	out.gain = gain
	out["started"] = true
	return out

static func lost_cargo(run: Dictionary) -> String:
	var s := state(run)
	var ex: Dictionary = run.get("explore", {})
	if ex.get("mainline_lost", false): return ""
	var had: bool = not str(ex.get("mainline_cargo", "")).is_empty()
	if not s.work.is_empty() and str(s.work.action).begins_with("search_"):
		had = true
		_reset_spot(run, s.work)
		if _same_busy(run, s.work): run.busy = {}
		s.work = {}
	if not had:
		for spot in ex.get("spots", []):
			if spot.get("mainline", "") in ["mortuary", "temple"] and spot.get("done", false): had = true
	if not had: return ""
	ex.erase("mainline_cargo")
	s["carried"] = ""
	ex["mainline_lost"] = true
	return _fact(run, "lost_evidence", "被尸群追上，贴身带着的证物丢了，手上的活也没做完。期限前还能再去查。")

static func begin_return(run: Dictionary, ex: Dictionary) -> bool:
	var s := state(run)
	var cargo := str(ex.get("mainline_cargo", ""))
	var expected := "mortuary" if s.stage == "mortuary" else ("temple" if s.stage == "temple" else "")
	var point := "mortuary" if cargo == "mortuary" else "taoist_temple"
	if cargo == "" or cargo != expected or s.get("carried", "") != cargo or ex.get("point", "") != point or ex.get("caught", false) or not s.work.is_empty(): return false
	if run.get("phase", "") != "post" or not run.get("explore", {}).is_empty() or not run.get("busy", {}).is_empty(): return false
	if int(run.get("t", 0)) + 60 >= FINAL_END:
		_fact(run, "late_return", "来不及在最后期限前把证物带回家了，这一趟不算数。")
		return false
	s["carried"] = ""
	_start(run, "return_" + cargo, "带证物返程", 60, {"cargo": cargo})
	return true

static func complete(run: Dictionary, data: Dictionary) -> String:
	var s := state(run)
	var work: Dictionary = s.work
	if work.is_empty() or data.get("id", "") != work.id or data.get("action", "") != work.action or int(run.get("t", 0)) < int(work.end_t): return ""
	s.work = {}
	if run.get("phase", "") != "post": return ""
	var action := str(work.action)
	var now := int(run.get("t", 0))
	if (action == "host" and now >= CONTACT_END) or (action != "host" and now >= FINAL_END and not (action == "escape" and now == FINAL_END)):
		_reset_spot(run, work)
		return _fact(run, "late_completion", "%s没赶在期限前做完。" % work.label)
	match action:
		"host":
			if s.stage != "contact": return ""
			run.flags["learned_talisman"] = true
			Inv.add_all(run.home, {"talisman": 1, "talisman_paper": 2})
			State.learn_clue(run, "c_taoist")
			s.stage = "mortuary"
			return _fact(run, action, "招待完道士，他教你画符，留下镇尸符 ×1、符纸 ×2 和义庄的线索。证据还得你自己去义庄拿回来。")
		"self_route":
			if s.stage != "fallback": return ""
			s.stage = "mortuary"
			return _fact(run, action, "打听到了去义庄的路，可以去调查了；走这条路没有道士的赠符和画符教学。")
		"disrupt", "copy":
			if s.stage != "mortuary_choice" or not s.evidence.mortuary: return ""
			if action == "disrupt": s.interventions.disrupt_t = now
			run.flags["temple_open"] = true
			s.stage = "temple"
			return _fact(run, action, "运尸簿%s；去青云观的路打开了，还要上山取回七灯图和后山道图。" % ("运尸的路断了，第 11、17 夜不会再有铜甲" if action == "disrupt" else "抄录完了；运尸的路没断，尸潮照旧"))
		"prepare_escape", "prepare_light_escape", "prepare_convoy":
			if s.stage != "routes" or not s.evidence.temple: return ""
			if action == "prepare_light_escape" and not _identity_cap(run, "light_escape"): return _fact(run, "invalid_method", "轻装走的更道还没探好，这份准备没用上。")
			if action == "prepare_convoy" and not _identity_cap(run, "early_convoy"): return _fact(run, "invalid_method", "这种玩法里用不上旧路经验，这份准备没用上。")
			s["escape_method"] = "light" if action == "prepare_light_escape" else ("convoy" if action == "prepare_convoy" else "normal")
			s.route = "escape"
			s.stage = "escape_ready"
			var travel := _escape_spec(run)
			return _fact(run, action, "行装备好了，定下撤离（%s）。第 %d 日 08:00 起可以动身，第 19 日 18:00 前走完（要 %d 分钟、精力 %d）；不能再破阵。" % [travel[0], 17 if s.escape_method == "convoy" else 18, int(travel[1]), int(travel[2])])
		"prepare_ritual", "prepare_paper_ritual":
			if s.stage != "routes" or not s.evidence.temple: return ""
			if action == "prepare_paper_ritual" and not _identity_cap(run, "paper_ritual"): return _fact(run, "invalid_method", "这种玩法里用不上前世的灯图经验，纸阵没备成。")
			s["ritual_method"] = "paper" if action == "prepare_paper_ritual" else "normal"
			s.route = "ritual"
			s.stage = "ritual_ready"
			return _fact(run, action, "法具备好了，定下破阵。灯还亮着，要亲自上青云观，在阵眼做 90 分钟，第 19 日 18:00 前做完。")
		"escape":
			if s.stage != "escape_ready" or s.route != "escape": return ""
			if s.get("escape_method", "normal") == "convoy" and not _identity_cap(run, "early_convoy"): return _fact(run, "invalid_method", "用不上旧路经验，没法提早出城。")
			if s.get("escape_method", "normal") == "light" and not _identity_cap(run, "light_escape"): return _fact(run, "invalid_method", "轻装更道没探好，没法这样撤离。")
			s.stage = "closed"
			s.ending = _ending_data("escape")
			run.phase = "ending"
			return _fact(run, action, "走了 %d 分钟，你沿着查到的出路离开了这座城。第 20 夜不用再守，守满二十日的奖励也就没有了，这座宅院也回不去了。" % int(work.end_t - work.start_t))
		"search_mortuary", "search_temple", "search_ritual":
			var id := str(work.data.get("objective", ""))
			var ex: Dictionary = run.get("explore", {})
			if ex.is_empty() or ex.get("point", "") != work.data.get("point", "") or ex.get("caught", false): return _fact(run, "lost_work", "人已经离开或被追上，取证、封阵都没做成。")
			if id == "ritual":
				if s.stage != "ritual_ready" or not s.evidence.temple or s.route != "ritual": return ""
				if s.get("ritual_method", "normal") == "paper" and not _identity_cap(run, "paper_ritual"): return _fact(run, "invalid_method", "还没学会纸阵，封阵没做成。")
				s.interventions.ritual_t = now
				s.stage = "sealed"
				return _fact(run, "ritual", "在阵眼做了 90 分钟，七星灯都熄了。第 20 夜没有血月，来的也少两成；残潮还在，活到第 21 日天亮才算破阵。")
			if (id == "mortuary" and s.stage != "mortuary") or (id == "temple" and s.stage != "temple"): return ""
			ex["mainline_cargo"] = id
			s["carried"] = id
			return _fact(run, action, "%s已经贴身收好，还要走 60 分钟回到家才算数；路上被追上就会丢。" % ("运尸簿" if id == "mortuary" else "七灯图与后山道图"))
		"return_mortuary", "return_temple":
			var cargo := str(work.data.get("cargo", ""))
			if (cargo == "mortuary" and s.stage != "mortuary") or (cargo == "temple" and s.stage != "temple"): return ""
			if not cargo in ["mortuary", "temple"]: return ""
			s.evidence[cargo] = true
			State.learn_clue(run, "c_mortuary" if cargo == "mortuary" else "c_temple")
			s.stage = "mortuary_choice" if cargo == "mortuary" else "routes"
			return _fact(run, action, "走了 60 分钟回到家，%s交到手里了；%s。" % ["义庄" if cargo == "mortuary" else "青云观", "现在可以断运、抄录或封存" if cargo == "mortuary" else "现在可以在坚守、撤离和破阵之间作选择"])
	return ""

## Called only by the completed identity work, with its unconsumed work token.
static func identity_resolution(run: Dictionary, action: String) -> String:
	var defs := {"scholar_collate": ["scholar", ""], "scholar_diagram": ["scholar", "sealed_lamps"], "escort_intercept": ["escort", ""], "escort_convoy": ["escort", "escaped_city"], "herbalist_lure": ["herbalist", ""], "herbalist_ink": ["herbalist", "gave_medicine"], "watchman_lane": ["watchman", ""], "watchman_intel": ["watchman", "returned_evidence"]}
	if not defs.has(action) or run.get("phase", "") != "post" or State.attr(run, "hp") <= 0: return ""
	var identity: Dictionary = run.get("identity", {})
	var work: Dictionary = identity.get("work", {})
	var now := int(run.get("t", 0))
	if identity.get("chosen", "") != "" or work.get("action", "") != action or not str(work.get("id", "")).begins_with("identity:%s:" % str(Past.state(run).id)) or int(work.get("end_t", 0)) > now or int(work.get("end_t", 0)) <= int(work.get("start_t", -1)): return ""
	if run.get("role", "") != defs[action][0] or now + 140 >= FINAL_END: return ""
	if defs[action][1] != "":
		if Past.daily(run): return ""
		var inherited := false
		var p := Past.state(run)
		for source in identity.get("inherited", []):
			if source is Dictionary and source.get("tag", "") == defs[action][1] and Past._trade_integer(source.get("source_life"), 1, int(p.get("generation", 0)) - 1) and source.get("source_id") is String and not source.source_id.is_empty() and source.source_id.length() <= 80 and source.source_id != p.id: inherited = true
		if not inherited: return ""
	var s := state(run)
	if s.stage != "mortuary_choice" or not s.evidence.mortuary or not run.get("explore", {}).is_empty() or not s.work.is_empty(): return ""
	if action == "escort_intercept": s.interventions.disrupt_t = now
	run.flags["temple_open"] = true
	s.stage = "temple"
	return _fact(run, action, "你用自己的法子办成了（%s），去青云观的路打开了；还要上山把证据带回来。%s" % [str(work.get("label", "专属处置")), "运尸被截断，第 11、17 夜不会再有铜甲。" if action == "escort_intercept" else "没有断运；学到的配方、路线或消息照常管用。"])

static func wave_effect(run: Dictionary, day: int) -> Dictionary:
	var s := state(run)
	var out := {"remove_mods": [], "count_mul": 1.0, "reason": ""}
	var start := (day - 1) * 1440 + 960
	var active: Dictionary = run.get("night", {})
	if int(run.get("wave_day", 0)) == day or (not active.is_empty() and int(active.get("wave", {}).get("day", -1)) == day): return out
	if day in [11, 17] and int(s.interventions.disrupt_t) >= 0 and int(s.interventions.disrupt_t) < start:
		out.remove_mods.append("armored")
		out.reason = "运尸的路已经断了，往后的夜里不会再有铜甲。"
	if day == 20 and int(s.interventions.ritual_t) >= 0 and int(s.interventions.ritual_t) < start:
		out.remove_mods.append("blood_moon")
		out.count_mul = 0.8
		out.reason = "七星灯已封，血月没了，来的也少两成；残潮还得守。"
	return out

static func _ending_data(kind: String) -> Dictionary:
	if kind == "escape": return {"kind": kind, "title": "离城余生", "text": "你带着查到的后山出路，收拾行装离开了。第 20 夜还没来，这座宅院留在身后；你得到的是离城后的余生。", "bonus": 0, "can_continue": false}
	if kind == "ritual": return {"kind": kind, "title": "七灯俱熄", "text": "你亲自去义庄和青云观取回证据，封了阵，又守过没了血月的残潮。第 21 日天亮，七灯已熄，这一轮的尸劫到此为止。", "bonus": 10, "can_continue": false}
	return {"kind": "hold", "title": "守宅劫满", "text": "你没有离开这座宅院，守过了第二十夜。第 21 日的太阳照进院子；可带着这份生计继续守下去，也可合卷或重走。", "bonus": 10, "can_continue": true}

static func finish_dawn(run: Dictionary) -> bool:
	if run.get("phase", "") != "post" or run.get("endless", false) or _day(run) < 21: return false
	var s := state(run)
	var ritual: bool = s.stage == "sealed" and s.route == "ritual" and int(s.interventions.ritual_t) >= 0 and int(s.interventions.ritual_t) < FINAL_END
	s.ending = _ending_data("ritual" if ritual else "hold")
	if not ritual: s.route = "hold"
	s.stage = "closed"
	run.phase = "ending"
	_fact(run, "ending", str(s.ending.title) + "：" + str(s.ending.text))
	return true

static func ending(run: Dictionary) -> Dictionary:
	var s := state(run)
	if not s.ending.is_empty(): return s.ending.duplicate(true)
	return _ending_data("hold") if run.get("phase", "") == "ending" else {}

static func continue_block(run: Dictionary) -> String:
	if run.get("phase", "") != "ending": return "还没到能接着过下去的时候。"
	return "" if bool(ending(run).get("can_continue", false)) else "这个结局回不到原来的宅院了；可以合卷，或再入轮回。"

static func continued(run: Dictionary) -> String:
	var blocked := continue_block(run)
	if blocked != "": return blocked
	var s := state(run)
	s.ending = {}
	s.stage = "endless"
	s.route = "hold"
	_fact(run, "continued", "你留在宅院里，劫后的日子接着过；这一卷还没合上。")
	return ""

static func summary(run: Dictionary) -> String:
	var s := state(run)
	return str(STAGES.get(str(s.stage), "尸劫来历")) + " · " + ("已取今世义庄证据" if s.evidence.mortuary else "义庄尚待取证") + " · " + ("已取今世青云证据" if s.evidence.temple else "青云尚待取证")

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var target := "mortuary" if s.stage == "mortuary" else ("taoist_temple" if s.stage in ["temple", "ritual_ready"] else "")
	var goals := {"waiting": "第 3 日 08:00 起留意道士的消息。", "contact": "接待道士，或拒绝后自己寻路。", "fallback": "第 5 日起付米 1 自行打听义庄的路。", "mortuary": "去义庄查运尸簿，查完还要走 60 分钟回家。", "mortuary_choice": "断运能让往后的夜里没有铜甲；抄录省料；封存就定下坚守。", "temple": "亲自去青云观取回七灯图和后山道图，带回家才能定出路。", "routes": "第 12 日起，在坚守、撤离、破阵里定一条；备好就改不了。", "escape_ready": "第 18 日 08:00 至第 19 日 18:00 之间动身，撤离要 120 分钟。", "ritual_ready": "亲自上青云观，在阵眼做 90 分钟，第 19 日 18:00 前做完。", "sealed": "灯已熄，第 20 夜的残潮弱了些；活到第 21 日天亮。", "hold": "保留物资，守过第 20 夜，第 21 日天亮进入坚守结局。", "failed": "错过最后期限，转守宅院；日子照样能过下去。", "closed": "这一世的事已了结，可查看结局与调查、施工的记录。", "endless": "日子还在过下去，结局不会让这一轮停下。"}
	var costs := []
	for row in options(run): costs.append(str(row.hint))
	var escape_spec := _escape_spec(run)
	var escape_day := 17 if s.get("escape_method", "normal") == "convoy" else 18
	if s.stage == "escape_ready": goals.escape_ready = "第 %d 日 08:00 起、第 19 日 18:00 前动身，撤离要 %d 分钟、精力 %d；走完才算离城。" % [escape_day, int(escape_spec[1]), int(escape_spec[2])]
	return {"title": "尸劫来历 · " + str(STAGES.get(str(s.stage), "调查")), "summary": summary(run), "goal": str(goals.get(str(s.stage), "")),
		"target": target, "target_name": str(Data.table("map_points").get(target, {}).get("name", "")), "objective": objective(run, target),
		"costs": costs, "deadlines": ["接待道士：第 12 日 18:00 前。", "撤离：第 %d 日 08:00 至第 19 日 18:00，这条路要走 %d 分钟。" % [escape_day, int(escape_spec[1])], "封阵：第 19 日 18:00 前在阵眼做完；取证回家还要 60 分钟。"],
		"evidence": s.evidence.duplicate(), "route": str(s.route), "interventions": s.interventions.duplicate(), "token": _token(run), "stage": str(s.stage),
		"work": s.work.duplicate(true), "escape_method": str(s.get("escape_method", "normal")), "ritual_method": str(s.get("ritual_method", "normal")), "ending": ending(run), "last_result": str(s.last_result), "history": s.history.duplicate(true)}

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	return {"schema": 1, "published": s.stage != "waiting" or run.get("phase", "") == "ending", "start_day": int(s.start_day), "stage": str(s.stage),
		"evidence": s.evidence.duplicate(), "route": str(s.route), "interventions": s.interventions.duplicate(), "ending": ending(run), "history": s.history.duplicate(true)}
