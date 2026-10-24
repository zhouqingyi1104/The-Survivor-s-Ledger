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
const STAGES := {"waiting": "等待道士线索", "contact": "道士来访", "fallback": "自行打听义庄", "mortuary": "实查义庄", "mortuary_choice": "处置本世运尸簿", "temple": "实查青云观", "routes": "选择最后的活法", "escape_ready": "等待撤离窗口", "ritual_ready": "亲赴青云观封阵", "sealed": "七灯已熄，仍须守过残潮", "hold": "守住这座宅院", "closed": "主线已结案", "failed": "错过窗口，转守宅院", "endless": "劫后继续生活"}

static func _day(run: Dictionary) -> int:
	return maxi(1, int(run.get("t", 0)) / 1440 + 1)

static func state(run: Dictionary) -> Dictionary:
	if not run.get("mainline") is Dictionary or run.mainline.is_empty():
		run["mainline"] = {"schema": 1, "revision": 0, "start_day": maxi(3, _day(run) + 1), "stage": "waiting",
			"evidence": {"mortuary": false, "temple": false}, "route": "", "interventions": {"disrupt_t": -1, "ritual_t": -1},
			"work": {}, "carried": "", "ending": {}, "history": [], "last_result": "本世尚未调查；旧世残卷可读，但不是今世证物。", "serial": 0}
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
	State.note(run, "二十日主线 · " + result)
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
		facts.append(_fact(run, "interrupted", "%s中断，尚未生效；已耗物资与精力不退，原阶段仍可在期限内重试。" % str(work.get("label", "主线工作"))))
	var now := int(run.get("t", 0))
	if s.stage == "waiting" and now >= (int(s.start_day) - 1) * 1440 + 120:
		s.stage = "contact" if now < CONTACT_END else "fallback"
		facts.append(_fact(run, "contact", "游方道士留下义庄与七盏灯的消息；第12日18:00前可接待，拒绝或错过仍能自查。" if s.stage == "contact" else "旧卷从当前日之后开始调查，没有追认旧世证据；道士窗口已过，第5日起的自查路线仍可使用。"))
	if s.stage == "contact" and now >= CONTACT_END:
		s.stage = "fallback"
		facts.append(_fact(run, "contact_timeout", "道士已经离开，没有扣物资，也没有得到赠符或教学；仍可付米1自查义庄路线。"))
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
		facts.append(_fact(run, "deadline", "第19日18:00的最后窗口已过；%s，投入不退，转为守住宅院，仍可活过第二十夜。" % ("先前撤离筹备没有完成实际撤离" if previous == "escape" else ("先前封阵筹备没有完成现场施工" if previous == "ritual" else "尚未完成的本世调查与路线就此收尾"))))
	return "\n".join(facts)

static func _access(run: Dictionary, outside := false) -> String:
	if run.get("phase", "") != "post": return "当前不能推进本世主线。"
	if run.get("pending_event", "") != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty(): return "先处理眼前的事件或夜战。"
	if run.get("sleeping", false): return "正睡着。"
	if not run.get("busy", {}).is_empty() or not state(run).work.is_empty(): return "正在忙别的事。"
	if not run.get("fight", {}).is_empty(): return "先结束眼前的战斗。"
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not night.get("done", false): return "尸潮未退，不能另开主线工作。"
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
	if method == "convoy": return ["沿旧世路线提早出城", 180, 14]
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
	if not action in _allowed(str(s.stage), run): return "当前阶段或身份经验不能作这个选择。"
	if now < (int(s.start_day) - 1) * 1440 + 120: return "尚未到本世主线的公开时刻。"
	if action == "refuse": return "" if now < CONTACT_END else "道士来访窗口已过。"
	if action in ["hold", "seal"]: return ""
	if action == "self_route" and _day(run) < 5: return "第5日起才打听得到自查路线。"
	if action.begins_with("prepare_") and _day(run) < 12: return "第12日起才能筹备最后路线。"
	if action in ["prepare_escape", "prepare_light_escape", "prepare_convoy", "escape"] and run.get("endless", false): return "守到死模式不开放撤离结局；仍可调查、断运与封阵。"
	var spec: Array = _escape_spec(run) if action == "escape" else ACTIONS[action]
	var end := now + int(spec[1])
	if action == "host" and end >= CONTACT_END: return "来不及在道士离开前完成接待。"
	if action == "self_route" and end + 140 >= FINAL_END: return "来不及完成义庄往返取证，不能再收这份路线钱。"
	if action in ["disrupt", "copy"] and end + 140 >= FINAL_END: return "来不及完成后续青云观往返取证，请考虑封存守宅。"
	if action in ["prepare_escape", "prepare_light_escape", "prepare_convoy"]:
		var travel := 150 if action == "prepare_light_escape" else (180 if action == "prepare_convoy" else 120)
		if end + travel > FINAL_END: return "筹备后留不够%d分钟实际撤离，不能再扣筹备物资。" % travel
	if action in ["prepare_ritual", "prepare_paper_ritual"] and end + 60 + 90 >= FINAL_END: return "筹备后留不够上山和90分钟现场封阵，不能再扣材料。"
	if action == "escape":
		var method := str(s.get("escape_method", "normal"))
		if method == "convoy" and not _identity_cap(run, "early_convoy"): return "本世没有有效的趟子手旧路经验。"
		if method == "light" and not _identity_cap(run, "light_escape"): return "本世没有勘成轻装更道。"
		var open := ESCAPE_OPEN - (1440 if method == "convoy" else 0)
		if now < open: return "第%d日08:00才到这条路线的实际撤离窗口。" % (17 if method == "convoy" else 18)
		if end > FINAL_END: return "来不及在第19日18:00前完成%d分钟撤离。" % int(spec[1])
	elif action != "host" and end >= FINAL_END: return "主线最后窗口已过，不能再开工。"
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
	return _fact(run, "start_" + action, "开始%s，需要%d分钟，完工才生效；中断不退已耗物资与精力。" % [label, minutes])

static func act(run: Dictionary, action: String, token: String) -> String:
	if token != _token(run): return "这份主线安排已过期，请重新查看。"
	var blocked := _action_block(run, action)
	if blocked != "": return blocked
	var s := state(run)
	if action == "refuse":
		s.stage = "fallback"
		_fact(run, "refuse", "你没有接待道士，不耗物资、没有教学或赠符；第5日起仍可付米1自行打听义庄。")
		return ""
	if action in ["hold", "seal"]:
		s.route = "hold"
		s.stage = "hold"
		_fact(run, action, "你%s；没有额外物资成本，本世放弃后续撤离与封阵，留守宅院直到第二十夜。" % ("封存本世运尸簿" if action == "seal" else "决定保留物资、坚守宅院"))
		return ""
	Inv.take_all(run.home, COSTS[action])
	var spec: Array = _escape_spec(run) if action == "escape" else ACTIONS[action]
	State.add_attr(run, "energy", -int(spec[2]))
	_start(run, action, str(spec[0]), int(spec[1]))
	return ""

static func options(run: Dictionary) -> Array:
	var labels := {"host": "接待道士", "refuse": "婉拒来访，自行寻路", "self_route": "付米买下旧路线", "disrupt": "截断运尸支路", "copy": "抄录线索，保留材料", "seal": "封存证据，留守宅院", "hold": "选择坚守", "prepare_escape": "筹备撤离", "prepare_ritual": "筹备破阵", "escape": "实际撤离离城"}
	var hints := {"host": "清水1、柴1；30分钟、精力4。完工后学画符，得镇尸符1、符纸2和道士残卷，开启义庄调查。", "refuse": "零物资，不算失约。第5日起可付米1自查，没有道士赠符与教学。", "self_route": "米1；60分钟、精力4。得到本世义庄路线，没有赠符与画符教学。", "disrupt": "镇尸符1、灯油1；60分钟、精力6。完工后移除尚未开夜的第11/17夜铜甲，开启青云观调查。", "copy": "30分钟、精力4，不耗材料。开启青云观调查，尸潮保持原样。", "seal": "零额外成本，保留材料；锁为坚守，放弃本世后续撤离与破阵。", "hold": "零额外物资与时间；锁定坚守，放弃撤离与破阵，守过20夜可继续无尽。", "prepare_escape": "米3、清水3、木料2、铁钉1；90分钟、精力8。完工锁定撤离，还须在第18日08:00至19日18:00完成120分钟实际撤离；提前离城没有守满20日奖励。", "prepare_ritual": "镇尸符2、灯油1、黑狗血1；120分钟、精力10。完工锁定破阵，还须上青云观施工90分钟；严格在第19日18:00前封阵，才能削弱第20夜。", "escape": "120分钟、精力10；完成才离城，原宅不再可继续，守满20日奖励为0。第19日18:00前必须完成。"}
	var rows := []
	labels.merge({"prepare_light_escape": "轻装更道撤离", "prepare_convoy": "趟子手提早出城", "prepare_paper_ritual": "以纸阵替狗血封阵"})
	hints.merge({"prepare_light_escape": "米2、清水2；120分钟、精力8。省下木钉，但实际撤离要150分钟、精力10，仍在第18日08:00至19日18:00完成。", "prepare_convoy": "米4、清水4、木料1、铁钉1；120分钟、精力12。实际撤离180分钟、精力14，第17日08:00起可走，仍须19日18:00前完成，无守满奖励。", "prepare_paper_ritual": "镇尸符1、符纸3、朱砂2、灯油1；150分钟、精力10。不用黑狗血，但需更多纸砂和时间，仍须亲赴青云观90分钟封阵、守过残潮。"})
	if str(state(run).get("escape_method", "normal")) != "normal":
		var spec := _escape_spec(run)
		hints.escape = "%d分钟、精力%d；%s起可走，第19日18:00前必须完成。完工才离城，不得守满20日奖励，也不能返回原宅续无尽。" % [int(spec[1]), int(spec[2]), "第17日08:00" if state(run).escape_method == "convoy" else "第18日08:00"]
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
	var hints := {"mortuary": "20分钟、精力4、外泄35；完工仅贴身携带，另60分钟返程完成才认本世证据，被追上丢证可重试。", "temple": "20分钟、精力4、外泄35；完工仅贴身携带，另60分钟返程完成才认灯阵与出路证据，被追上丢证可重试。", "ritual": "90分钟、精力10、外泄45；严格第19日18:00前现场完工，熄灯后第20夜移除血月、基础数量×0.8，仍需守残潮。"}
	var blocked := ""
	var return_time := 0 if id == "ritual" else 60
	var outbound := 0 if run.get("explore", {}).get("point", "") == pid else 60
	if int(run.get("t", 0)) + outbound + minutes + return_time >= FINAL_END: blocked = "留不够调查、返程或封阵完工时间，第19日18:00前必须完成。"
	if State.attr(run, "energy") < energy: blocked = "精力不足，需要 %d。" % energy
	if not s.work.is_empty(): blocked = "先完成正在进行的主线工作。"
	if int(run.get("t", 0)) < (int(s.start_day) - 1) * 1440 + 120: blocked = "尚未到本世主线的公开时刻。"
	if id == "ritual" and s.get("ritual_method", "normal") == "paper" and not _identity_cap(run, "paper_ritual"): blocked = "本世没有有效的纸阵解法。"
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
	if blocked == "" and not spot in ex.get("spots", []): blocked = "这不是当前地点实际存在的调查目标。"
	if blocked == "" and (target.is_empty() or id != target.get("id", "") or spot.get("done", false) or ex.get("caught", false)): blocked = "这处专属目标当前不能调查，或已经处理。"
	if blocked == "": blocked = str(target.get("block", ""))
	if blocked != "": return _search_result(blocked, blocked)
	spot.done = true
	var gain := 45 if id == "ritual" else 35
	ex.exposure = mini(100, int(ex.get("exposure", 0)) + gain)
	if id == "ritual": State.add_attr(run, "energy", -6) # Post adds the common search cost4.
	_start(run, "search_" + id, str(target.name), int(target.minutes), {"objective": id, "point": str(ex.point)})
	var out := _search_result("已开始%s；%d分钟完工才生效，外泄增加%d。" % [target.name, int(target.minutes), gain])
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
	return _fact(run, "lost_evidence", "被尸群追上，未交回的贴身证物丢失，正在进行的现场工作也未完成；没有补造今世证据，期限内可重新调查。")

static func begin_return(run: Dictionary, ex: Dictionary) -> bool:
	var s := state(run)
	var cargo := str(ex.get("mainline_cargo", ""))
	var expected := "mortuary" if s.stage == "mortuary" else ("temple" if s.stage == "temple" else "")
	var point := "mortuary" if cargo == "mortuary" else "taoist_temple"
	if cargo == "" or cargo != expected or s.get("carried", "") != cargo or ex.get("point", "") != point or ex.get("caught", false) or not s.work.is_empty(): return false
	if run.get("phase", "") != "post" or not run.get("explore", {}).is_empty() or not run.get("busy", {}).is_empty(): return false
	if int(run.get("t", 0)) + 60 >= FINAL_END:
		_fact(run, "late_return", "已经来不及在最后窗口前返程交证；这次未交回的证物不算本世证据，原投入不退。")
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
		return _fact(run, "late_completion", "%s没有在期限内完成，没有生效；已耗物资与精力不退。" % work.label)
	match action:
		"host":
			if s.stage != "contact": return ""
			run.flags["learned_talisman"] = true
			Inv.add_all(run.home, {"talisman": 1, "talisman_paper": 2})
			State.learn_clue(run, "c_taoist")
			s.stage = "mortuary"
			return _fact(run, action, "接待完工，道士教你画符，留下镇尸符1、符纸2及义庄线索；仍须亲自调查并返程取证。")
		"self_route":
			if s.stage != "fallback": return ""
			s.stage = "mortuary"
			return _fact(run, action, "付米买路的打听已经完成，今世义庄调查开放；没有道士赠符或画符教学，也不要求先救邻居。")
		"disrupt", "copy":
			if s.stage != "mortuary_choice" or not s.evidence.mortuary: return ""
			if action == "disrupt": s.interventions.disrupt_t = now
			run.flags["temple_open"] = true
			s.stage = "temple"
			return _fact(run, action, "本世运尸簿%s；青云观路线已经打开，仍须上山取回七灯图与后山道图。" % ("断运施工完成，尚未开夜的第11/17夜铜甲将被移除" if action == "disrupt" else "抄录完成，没有截断运尸，尸潮保持原样"))
		"prepare_escape", "prepare_light_escape", "prepare_convoy":
			if s.stage != "routes" or not s.evidence.temple: return ""
			if action == "prepare_light_escape" and not _identity_cap(run, "light_escape"): return _fact(run, "invalid_method", "轻装更道尚未有效勘成，筹备没有生效。")
			if action == "prepare_convoy" and not _identity_cap(run, "early_convoy"): return _fact(run, "invalid_method", "旧路经验在当前模式无效，筹备没有生效。")
			s["escape_method"] = "light" if action == "prepare_light_escape" else ("convoy" if action == "prepare_convoy" else "normal")
			s.route = "escape"
			s.stage = "escape_ready"
			var travel := _escape_spec(run)
			return _fact(run, action, "撤离行装筹备完成，路线锁为撤离（%s）；第%d日08:00起可走，第19日18:00前还须完成%d分钟实际撤离，精力%d，不能同时破阵。" % [travel[0], 17 if s.escape_method == "convoy" else 18, int(travel[1]), int(travel[2])])
		"prepare_ritual", "prepare_paper_ritual":
			if s.stage != "routes" or not s.evidence.temple: return ""
			if action == "prepare_paper_ritual" and not _identity_cap(run, "paper_ritual"): return _fact(run, "invalid_method", "旧世灯图经验在当前模式无效，纸阵筹备没有生效。")
			s["ritual_method"] = "paper" if action == "prepare_paper_ritual" else "normal"
			s.route = "ritual"
			s.stage = "ritual_ready"
			return _fact(run, action, "封阵法具筹备完成，路线锁为破阵；尚未熄灯，必须亲赴青云观阵眼施工90分钟，严格在第19日18:00前完工。")
		"escape":
			if s.stage != "escape_ready" or s.route != "escape": return ""
			if s.get("escape_method", "normal") == "convoy" and not _identity_cap(run, "early_convoy"): return _fact(run, "invalid_method", "当前没有有效旧路经验，不能免费完成提早出城。")
			if s.get("escape_method", "normal") == "light" and not _identity_cap(run, "light_escape"): return _fact(run, "invalid_method", "当前没有有效轻装更道，不能免费完成撤离。")
			s.stage = "closed"
			s.ending = _ending_data("escape")
			run.phase = "ending"
			return _fact(run, action, "%d分钟撤离完成，你沿今世确认的出路离开这座城。离城余生：不再守第20夜，没有守满20日奖励，也不能直接返回原宅继续生活。" % int(work.end_t - work.start_t))
		"search_mortuary", "search_temple", "search_ritual":
			var id := str(work.data.get("objective", ""))
			var ex: Dictionary = run.get("explore", {})
			if ex.is_empty() or ex.get("point", "") != work.data.get("point", "") or ex.get("caught", false): return _fact(run, "lost_work", "现场已经离开或被追上，未完成取证或封阵，没有免费生效。")
			if id == "ritual":
				if s.stage != "ritual_ready" or not s.evidence.temple or s.route != "ritual": return ""
				if s.get("ritual_method", "normal") == "paper" and not _identity_cap(run, "paper_ritual"): return _fact(run, "invalid_method", "当前没有有效纸阵解法，现场封阵没有免费生效。")
				s.interventions.ritual_t = now
				s.stage = "sealed"
				return _fact(run, "ritual", "90分钟现场封阵已经完成，七星灯俱熄；第20夜移除血月、基础尸数乘0.8。仍有残潮，须活到第21日天亮才得破阵结局。")
			if (id == "mortuary" and s.stage != "mortuary") or (id == "temple" and s.stage != "temple"): return ""
			ex["mainline_cargo"] = id
			s["carried"] = id
			return _fact(run, action, "本世%s已经贴身收好，但尚未算交证；仍须完成60分钟返程，被追上会丢失，不能用旧世残卷替代。" % ("运尸簿" if id == "mortuary" else "七灯图与后山道图"))
		"return_mortuary", "return_temple":
			var cargo := str(work.data.get("cargo", ""))
			if (cargo == "mortuary" and s.stage != "mortuary") or (cargo == "temple" and s.stage != "temple"): return ""
			if not cargo in ["mortuary", "temple"]: return ""
			s.evidence[cargo] = true
			State.learn_clue(run, "c_mortuary" if cargo == "mortuary" else "c_temple")
			s.stage = "mortuary_choice" if cargo == "mortuary" else "routes"
			return _fact(run, action, "60分钟返程完成，本世%s证据正式交回；%s。" % ["义庄" if cargo == "mortuary" else "青云观", "现在可以断运、抄录或封存" if cargo == "mortuary" else "现在可以在坚守、撤离与破阵之间作真实取舍"])
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
	return _fact(run, action, "本世身份解法已实际完成（%s），青云观路线开放；仍须上山调查并交回今世证据。%s" % [str(work.get("label", "专属处置")), "已截运，尚未开夜的第11/17夜铜甲移除。" if action == "escort_intercept" else "没有公共断运效果，专属配方、路线或情报按已学解法生效。"])

static func wave_effect(run: Dictionary, day: int) -> Dictionary:
	var s := state(run)
	var out := {"remove_mods": [], "count_mul": 1.0, "reason": ""}
	var start := (day - 1) * 1440 + 960
	var active: Dictionary = run.get("night", {})
	if int(run.get("wave_day", 0)) == day or (not active.is_empty() and int(active.get("wave", {}).get("day", -1)) == day): return out
	if day in [11, 17] and int(s.interventions.disrupt_t) >= 0 and int(s.interventions.disrupt_t) < start:
		out.remove_mods.append("armored")
		out.reason = "本世断运已经完成，尚未开夜的铜甲运送被截断。"
	if day == 20 and int(s.interventions.ritual_t) >= 0 and int(s.interventions.ritual_t) < start:
		out.remove_mods.append("blood_moon")
		out.count_mul = 0.8
		out.reason = "本世七星灯已封，血月效应消失，基础尸数乘0.8；仍须守过残潮。"
	return out

static func _ending_data(kind: String) -> Dictionary:
	if kind == "escape": return {"kind": kind, "title": "离城余生", "text": "你带着今世调查到的后山出路，实际完成行装与撤离。第20夜还未到来，这座宅院留在身后；你得到的是离城后的余生。", "bonus": 0, "can_continue": false}
	if kind == "ritual": return {"kind": kind, "title": "七灯俱熄", "text": "你亲赴义庄与青云观取回今世证据，完成现场封阵，又守过失去血月加持的残潮。第21日天亮，七灯已经熄灭，这一轮不再回到旧宅继续尸劫。", "bonus": 10, "can_continue": false}
	return {"kind": "hold", "title": "守宅劫满", "text": "你没有离开这座宅院，守过了第二十夜。第21日的太阳照进院子；可带着这份生计继续守下去，也可合卷或重走。", "bonus": 10, "can_continue": true}

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
	if run.get("phase", "") != "ending": return "尚未到可以继续生活的结局。"
	return "" if bool(ending(run).get("can_continue", false)) else "这个结局不能直接回到原宅继续；可以合卷或再入轮回。"

static func continued(run: Dictionary) -> String:
	var blocked := continue_block(run)
	if blocked != "": return blocked
	var s := state(run)
	s.ending = {}
	s.stage = "endless"
	s.route = "hold"
	_fact(run, "continued", "你选择劫后继续守宅，转入无尽生活；这一轮仍未合卷。")
	return ""

static func summary(run: Dictionary) -> String:
	var s := state(run)
	return str(STAGES.get(str(s.stage), "本世主线")) + " · " + ("已取本世义庄证据" if s.evidence.mortuary else "义庄尚待取证") + " · " + ("已取本世青云证据" if s.evidence.temple else "青云尚待取证")

static func view(run: Dictionary) -> Dictionary:
	var s := state(run)
	var target := "mortuary" if s.stage == "mortuary" else ("taoist_temple" if s.stage in ["temple", "ritual_ready"] else "")
	var goals := {"waiting": "第3日08:00起留意道士线索，旧卷从当前日之后起步。", "contact": "接待道士或拒绝后自行寻路；来访不靠随机抽取。", "fallback": "第5日起付米1自行打听，无需先救邻居。", "mortuary": "到义庄专点调查运尸簿，完工再完成60分钟返程。", "mortuary_choice": "断运会改变未来铜甲尸潮；抄录保材料；封存锁为坚守。", "temple": "亲赴青云观取回七灯图与后山道图，完成返程才解锁路线。", "routes": "第12日起决定坚守、备撤离或备破阵；筹备完工后锁定。", "escape_ready": "第18日08:00至第19日18:00完成120分钟实际撤离。", "ritual_ready": "亲赴青云观阵眼施工90分钟，严格第19日18:00前完工。", "sealed": "现场已熄灯，仍需对付第20夜削弱后的残潮，活到21晨。", "hold": "保留物资，守过第20夜，21晨进入坚守结局。", "failed": "错过最后窗口后转守宅院，已投入不退，生存仍可继续。", "closed": "本世已结案，查看结局与真实调查、施工记录。", "endless": "无尽生活继续，主线结局不强制结束这一轮。"}
	var costs := []
	for row in options(run): costs.append(str(row.hint))
	var escape_spec := _escape_spec(run)
	var escape_day := 17 if s.get("escape_method", "normal") == "convoy" else 18
	if s.stage == "escape_ready": goals.escape_ready = "第%d日08:00起、第19日18:00前完成%d分钟实际撤离，精力%d；只有完工才离城。" % [escape_day, int(escape_spec[1]), int(escape_spec[2])]
	return {"title": "二十日主线 · " + str(STAGES.get(str(s.stage), "调查")), "summary": summary(run), "goal": str(goals.get(str(s.stage), "")),
		"target": target, "target_name": str(Data.table("map_points").get(target, {}).get("name", "")), "objective": objective(run, target),
		"costs": costs, "deadlines": ["道士接待：第12日18:00前完工。", "撤离窗口：第%d日08:00至第19日18:00，当前方法需%d分钟。" % [escape_day, int(escape_spec[1])], "封阵：严格第19日18:00前现场完工；取证需额外60分钟返程。"],
		"evidence": s.evidence.duplicate(), "route": str(s.route), "interventions": s.interventions.duplicate(), "token": _token(run), "stage": str(s.stage),
		"work": s.work.duplicate(true), "escape_method": str(s.get("escape_method", "normal")), "ritual_method": str(s.get("ritual_method", "normal")), "ending": ending(run), "last_result": str(s.last_result), "history": s.history.duplicate(true)}

static func context(run: Dictionary) -> Dictionary:
	var s := state(run)
	return {"schema": 1, "published": s.stage != "waiting" or run.get("phase", "") == "ending", "start_day": int(s.start_day), "stage": str(s.stage),
		"evidence": s.evidence.duplicate(), "route": str(s.route), "interventions": s.interventions.duplicate(), "ending": ending(run), "history": s.history.duplicate(true)}
