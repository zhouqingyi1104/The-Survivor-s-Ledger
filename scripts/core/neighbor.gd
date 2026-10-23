extends RefCounted
## A preplanned, deterministic story. No network, timers or model calls in play.
const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Director = preload("res://scripts/core/director.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const DEADLINE := 3 * 1440 + 720 # Day 4, 18:00; time begins at day 1, 06:00.
const CABINET := "封存药柜"
const ACCOUNT := "守庄人药账"

static func fresh() -> Dictionary:
	return {"stage": "waiting", "resolution": "", "approach": "", "medicine": false,
		"pry": false, "due": 0, "reward": "", "ending": "", "history": []}

static func state(run: Dictionary) -> Dictionary:
	if not run.has("neighbor") or run.neighbor.is_empty():
		run.neighbor = fresh()
	return run.neighbor

static func record(run: Dictionary, choice: String, result: String) -> void:
	state(run).history.append({"t": int(run.t), "choice": choice, "result": result})
	State.note(run, "隔墙求药：" + result)
	Director.note_choice(run, "隔墙求药 · " + choice, result)
	match choice:
		"donate_home", "deliver": Past.record(run, "ning", "medicine", "你曾把药交给阿宁。", 1)
		"refuse": Past.record(run, "ning", "medicine", "你曾没有答应阿宁的求药。", -1)
		"keep": Past.record(run, "ning", "medicine", "你曾把为邻人取回的药留给自己。", -1)
		"deadline": Past.record(run, "ning", "medicine", "你曾答应取药，却没能按期送到阿宁手中。", -1)
		"share": Past.record(run, "ning", "account", "你曾把守庄人的药账交给阿宁，一同追查线索。", 1)
		"seal": Past.record(run, "ning", "account", "你曾取到药账后选择封存，没有交给阿宁。", -1)

static func ready_for_home(run: Dictionary) -> bool:
	return run.get("explore", {}).is_empty() and not run.get("neighbor_travel", false) and not run.get("sleeping", false) and run.get("busy", {}).is_empty()

## Called at time checkpoints and after return travel, never overwrites another event.
static func poll(run: Dictionary) -> String:
	if run.get("phase", "") != "post":
		return ""
	var q := state(run)
	var now := int(run.t)
	if q.stage in ["fetch", "carrying"] and now >= DEADLINE:
		q.stage = "aftermath"
		q.resolution = "late"
		q.due = 4 * 1440 + 120
		if str(run.get("pending_event", "")) in ["n_cabinet", "n_delivery"]:
			run.pending_event = ""
			run.event_result = "期限已过，邻人已另投医馆。"
		record(run, "deadline", "期限已过，邻人带父亲另投医馆。未送到的药留作自用，承诺未兑现。")
	if q.resolution == "late" and q.medicine and ready_for_home(run):
		Inv.add(run.home, "plague_powder", 1)
		q.medicine = false
	if run.get("pending_event", "") != "" or run.get("dawn_due", false) or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty() or not run.get("fight", {}).is_empty():
		return ""
	var event := ""
	if q.stage == "fetch" and not run.get("neighbor_searching", false) and not run.explore.is_empty() and run.explore.point == "pharmacy_ruin":
		for spot in run.explore.spots:
			if spot.get("neighbor", "") == "cabinet" and spot.done:
				event = "n_cabinet"
	if ready_for_home(run):
		match q.stage:
			"waiting":
				if now >= 1440 + 120:
					if now < DEADLINE:
						event = "n_request"
					else:
						q.stage = "closed"
						q.ending = "未曾相逢"
						record(run, "missed", "未能在求药期限内与邻人相见；本轮求药线结束。")
			"carrying":
				event = "n_delivery"
			"aftermath":
				if now >= int(q.due):
					event = "n_thanks" if q.resolution == "donated" else "n_distance"
			"lead":
				if now >= int(q.due):
					event = "n_lead"
			"report":
				event = "n_evidence"
	if event != "":
		run.pending_event = event
	return event

static func expected_event(run: Dictionary, id: String) -> bool:
	var stages := {"n_request": "waiting", "n_cabinet": "fetch", "n_delivery": "carrying",
		"n_thanks": "aftermath", "n_distance": "aftermath", "n_lead": "lead", "n_evidence": "report"}
	var q := state(run)
	if stages.get(id, "invalid") != q.stage:
		return false
	if id in ["n_request", "n_cabinet", "n_delivery"] and int(run.t) >= DEADLINE:
		return false
	if id == "n_cabinet":
		return not run.explore.is_empty() and run.explore.point == "pharmacy_ruin"
	if id == "n_thanks":
		return q.resolution == "donated"
	if id == "n_distance":
		return q.resolution != "donated"
	return ready_for_home(run)

static func choice_block(run: Dictionary, choice: Dictionary) -> String:
	if not expected_event(run, str(run.get("pending_event", ""))):
		return "这段事情已经处理过了。"
	if choice.get("pry", false) and not state(run).pry:
		return "出门前在劫余录中准备撬杆（木料 1）。"
	if not Inv.has_all(run.home, choice.get("req", {})):
		return "东西不够。"
	return ""

static func choose(run: Dictionary, index: int) -> String:
	var id := str(run.pending_event)
	var event: Dictionary = Data.table("events").get(id, {})
	var choices: Array = event.get("choices", [])
	if index < 0 or index >= choices.size():
		return "无效的选择。"
	var c: Dictionary = choices[index]
	var block := choice_block(run, c)
	if block != "":
		return block
	var q := state(run)
	var action := str(c.id)
	Inv.take_all(run.home, c.get("req", {}))
	match action:
		"promise":
			q.stage = "fetch"
		"donate_home", "deliver":
			q.stage = "aftermath"
			q.resolution = "donated"
			q.medicine = false
			q.due = int(run.t) + 1440
			State.add_attr(run, "mood", 4)
		"refuse", "keep":
			q.stage = "aftermath"
			q.resolution = "refused" if action == "refuse" else "kept"
			q.due = 4 * 1440 + 120
			if action == "keep":
				q.medicine = false
				Inv.add(run.home, "plague_powder", 1)
		"force", "pry":
			q.approach = action
			q.pry = false
			q.medicine = true
			q.stage = "carrying"
			if action == "force":
				run.explore.exposure = mini(100, int(run.explore.exposure) + 24)
				# Shared capture path: breaking the cabinet can trigger the same chase.
				if int(run.explore.exposure) >= 100:
					run.explore["neighbor_capture_due"] = true
		"supplies", "food", "buy_lead":
			q.reward = action
			Inv.add_all(run.home, c.get("reward", {}))
			q.stage = "lead"
			q.due = maxi(5 * 1440 + 120, int(run.t) + 60)
		"stay_apart":
			q.stage = "closed"
			q.ending = "各守门户"
		"investigate":
			q.stage = "investigate"
		"fortify":
			Inv.add(run.home, "wood", 1)
			q.stage = "closed"
			q.ending = "守宅度日"
		"share", "seal":
			State.learn_clue(run, "c_mortuary")
			if action == "share":
				run.flags["temple_open"] = true
				State.add_attr(run, "mood", 3)
			else:
				Inv.add(run.home, "talisman", 1)
			q.stage = "closed"
			q.ending = "共查青云" if action == "share" else "封存药账"
		_:
			return "无效的剧情动作。"
	var result := str(c.result)
	if action in ["supplies", "food", "buy_lead", "investigate", "fortify", "share", "seal", "stay_apart"]:
		result = "此前%s；%s" % [resolution_text(q), result]
	if action == "deliver" and q.approach == "force":
		result += "药柜的碎锁还在提醒你：这趟取药多惊动了 24 点阳气。"
	record(run, action, result)
	run.pending_event = ""
	run.event_result = result
	return ""

static func resolution_text(q: Dictionary) -> String:
	return {"donated": "你把药给了邻人", "refused": "你没有应下求药", "kept": "你把取回的药留给自己", "late": "你没能按期送药"}.get(str(q.resolution), "尚在求药")

static func prepare_pry(run: Dictionary) -> String:
	var q := state(run)
	if run.get("phase", "") != "post" or not ready_for_home(run) or run.get("pending_event", "") != "" or q.stage != "fetch" or q.pry or int(run.t) >= DEADLINE:
		return "现在不能准备撬杆。"
	if Inv.count(run.home, "wood") < 1:
		return "需要木料 1。"
	Inv.add(run.home, "wood", -1)
	q.pry = true
	record(run, "prepare_pry", "用一根木料制成随身撬杆，下次开药柜可免去砸锁的 24 点阳气。")
	return ""

static func add_objective(run: Dictionary, pid: String, spots: Array) -> void:
	var stage: String = state(run).stage
	if pid == "pharmacy_ruin" and stage == "fetch":
		spots.push_front({"name": CABINET, "done": false, "neighbor": "cabinet"})
	elif pid == "mortuary" and stage == "investigate":
		spots.push_front({"name": ACCOUNT, "done": false, "neighbor": "account"})

static func search_objective(run: Dictionary, spot: Dictionary) -> Dictionary:
	spot.done = true
	if spot.neighbor == "account" and state(run).stage == "investigate":
		state(run).stage = "report"
		record(run, "find_account", "取到守庄人药账。回宅决定如何处置，药账独立携带且不会被追赶丢失。")
	var result := {"found": {}, "gain": 0, "caught": false, "clue": "", "full": false, "story": true}
	return result

static func summary(run: Dictionary) -> String:
	var q := state(run)
	match q.stage:
		"waiting": return "邻里动静：第 2 日早间留意墙外求助。"
		"fetch": return "隔墙求药：去药铺翻封存药柜；第 4 日 18:00 前送回。" + ("已带撬杆。" if q.pry else "可用木料 1 准备撬杆。")
		"carrying": return "隔墙求药：药已独立收好，回宅决定去向；第 4 日 18:00 截止。"
		"aftermath": return "隔墙求药：%s，等待后续来信（第 %d 日起）。" % [resolution_text(q), int(q.due) / 1440 + 1]
		"lead": return "邻人消息：第 %d 日起留意义庄药账线索。" % (int(q.due) / 1440 + 1)
		"investigate": return "义庄药账：出门去义庄，翻找守庄人药账。"
		"report": return "义庄药账：已取得，回宅决定公开或封存。"
	return "隔墙求药 · " + str(q.ending)
