extends RefCounted
## 随机事件。对应原版 DynamicEventManager + Config_Event：条件筛选 → 权重抽取 → 选项结算。
##
## 选项条件 req：物品id 数量 / any_food / any_grain / silver。
## 选项效果 fx：items merit mood hp energy flag unlock clue raid plague seeds roll{p, ok, fail}。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Director = preload("res://scripts/core/director.gd")

static func entry(run: Dictionary) -> Dictionary:
	if str(run.pending_event).begins_with("world:"): return Director.entry(run)
	return Data.table("events").get(run.pending_event, {})

const DAILY_CHANCE := 0.6
const SEEDS := ["seed_cabbage", "seed_radish", "seed_chive"]


static func roll(run: Dictionary) -> String:
	if int(run.pday) <= 1 or not Rng.chance(run, DAILY_CHANCE):
		return ""
	var pool := []
	var events: Dictionary = Data.table("events")
	for id in events:
		var e: Dictionary = events[id]
		if e.get("story", "") != "" or id in ["neighbor_girl", "girl_gift"]:
			continue
		if run.pday < int(e.get("min_day", 1)) or run.pday > int(e.get("max_day", 999)):
			continue
		if e.get("once", false) and id in run.seen_events:
			continue
		if e.has("req_flag") and not State.flag(run, e.req_flag):
			continue
		if e.has("not_flag") and State.flag(run, e.not_flag):
			continue
		if id == "deserters" and run.raid_tonight:
			continue
		pool.append([id, int(e.get("weight", 1))])
	if pool.is_empty():
		return ""
	return Rng.weighted(run, pool)[0]


static func choice_ok(run: Dictionary, choice: Dictionary) -> bool:
	if str(run.get("pending_event", "")).begins_with("n_"):
		return Neighbor.choice_block(run, choice) == ""
	var req: Dictionary = choice.get("req", {})
	for k in req:
		var n := int(req[k])
		match k:
			"any_food":
				if Inv.total(run.home, Inv.food_ids(run.home)) < n:
					return false
			"any_grain":
				if Inv.total(run.home, Inv.GRAINS) < n:
					return false
			"silver":
				if int(run.silver) < n:
					return false
			_:
				if Inv.count(run.home, k) < n:
					return false
	return true


static func choose(run: Dictionary, idx: int) -> String:
	var id: String = run.pending_event
	if id == "":
		return ""
	if id.begins_with("world:"): return Director.choose(run, idx)
	var e: Dictionary = entry(run)
	if idx < 0 or idx >= e.choices.size():
		return "无效的选择。"
	if e.get("story", "") == "neighbor":
		var result := Neighbor.choose(run, idx)
		Explore.capture_if_due(run)
		return result
	var choice: Dictionary = e.choices[idx]
	if not choice_ok(run, choice):
		return "做不到。"
	var req: Dictionary = choice.get("req", {})
	for k in req:
		var n := int(req[k])
		match k:
			"any_food":
				Inv.take_any(run.home, Inv.food_ids(run.home), n)
			"any_grain":
				Inv.take_any(run.home, Inv.GRAINS, n)
			"silver":
				run.silver -= n
			_:
				Inv.add(run.home, k, -n)
	var result := _apply(run, choice.get("fx", {}))
	if result == "":
		result = choice.get("result", "")
	if not id in run.seen_events:
		run.seen_events.append(id)
	run.pending_event = ""
	run.event_result = result
	State.note(run, "%s——%s" % [e.title, result])
	Director.note_choice(run, str(e.title), str(result))
	State.check_death(run, "死于%s。" % e.title)
	return ""


## 应用效果，返回覆盖用的结果文案（只有 roll 分支会给）。
static func _apply(run: Dictionary, fx: Dictionary) -> String:
	var text := ""
	if fx.has("items"):
		Inv.add_all(run.home, fx.items)
	if fx.has("merit"):
		run.today["merit"] = int(run.today.get("merit", 0)) + int(fx.merit)
	for k in ["mood", "hp", "energy"]:
		if fx.has(k):
			State.add_attr(run, k, fx[k])
	if fx.has("flag"):
		run.flags[fx.flag] = true
	if fx.has("unlock"):
		run.flags[fx.unlock] = true
	if fx.has("clue"):
		State.learn_clue(run, fx.clue)
	if fx.has("raid"):
		run.raid_tonight = true
	if fx.has("plague"):
		var p := 1.0 if not State.is_role(run, "herbalist") else 0.5
		if Rng.chance(run, p):
			run.plague = true
		else:
			text = "差点染上尸瘟，凭着药铺里学的法子压了下去。"
	if fx.has("seeds"):
		for k in int(fx.seeds):
			Inv.add(run.home, Rng.pick(run, SEEDS), 1)
	if fx.has("roll"):
		var branch: Dictionary = fx.roll.ok if Rng.chance(run, float(fx.roll.p)) else fx.roll.fail
		var sub := _apply(run, branch)
		text = sub if sub != "" else branch.get("result", "")
	return text
