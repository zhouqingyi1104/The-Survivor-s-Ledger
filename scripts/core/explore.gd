extends RefCounted
## 外出搜寻。对应原版 ExploreManager + Config_MapPoint：
## 每翻一处就涨"阳气外泄"（原版的暴露值），涨满被尸群发现；地点会被搜空、会沦陷。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")

const EXPOSURE_MAX := 100


static func visible_points(run: Dictionary) -> Array:
	var out := []
	var points: Dictionary = Data.table("map_points")
	for id in points:
		var p: Dictionary = points[id]
		if p.has("unlock_flag") and not State.flag(run, p.unlock_flag):
			continue
		out.append(id)
	return out


## 返回 ""（可去）或者不能去的原因。
static func point_block(run: Dictionary, pid: String) -> String:
	var p: Dictionary = Data.table("map_points")[pid]
	if run.pday < int(p.get("unlock_day", 0)):
		return "第 %d 日后才打听到这里" % p.unlock_day
	if p.has("fall_day") and run.pday >= int(p.fall_day):
		return "已沦陷，尸群占了这里"
	var until := int(run.points.get(pid, {}).get("looted_until", 0))
	if until > run.pday:
		return "被搜空了，还要 %d 日才缓得过来" % (until - run.pday)
	return ""


static func fall_warning(run: Dictionary, pid: String) -> String:
	var p: Dictionary = Data.table("map_points")[pid]
	if p.has("fall_day"):
		var left := int(p.fall_day) - int(run.pday)
		if left > 0 and left <= 3:
			return "%d 日后沦陷" % left
	return ""


static func carry(run: Dictionary) -> float:
	return float(State.role(run).carry)


## 开始外出：花掉一个时段。由 Post.act_explore 调用（它负责时段推进）。
static func begin(run: Dictionary, pid: String) -> void:
	var p: Dictionary = Data.table("map_points")[pid]
	var n := mini(p.spots.size(), 3 + (1 if State.prof_level(run, "search") >= 2 else 0))
	var spots := []
	for s in Rng.shuffled(run, p.spots).slice(0, n):
		spots.append({"name": s, "done": false})
	run.explore = {"point": pid, "spots": spots, "exposure": 0, "bag": {}, "caught": false, "notes": []}
	State.add_attr(run, "energy", -6)
	if not pid in run.points:
		run.points[pid] = {"looted_until": 0, "visits": 0}
	run.points[pid].visits = int(run.points[pid].visits) + 1


static func exposure_gain(run: Dictionary, pid: String) -> int:
	var p: Dictionary = Data.table("map_points")[pid]
	var base := float(int(p.danger) * 8 + Rng.i(run, 0, 8))
	var mul := 1.0 - 0.04 * State.prof_level(run, "search")
	if State.has_talent(run, "tuna"):
		mul -= 0.2
	if State.is_role(run, "watchman"):
		mul -= 0.2
	if State.has_buff(run, "stealth"):
		mul -= 0.4
	if State.attr(run, "energy") < 20:
		mul += 0.25
	if State.attr(run, "mood") < 20:
		mul += 0.2
	return maxi(3, int(round(base * maxf(mul, 0.2))))


static func search(run: Dictionary, idx: int) -> Dictionary:
	var ex: Dictionary = run.explore
	var spot: Dictionary = ex.spots[idx]
	if spot.done or ex.caught:
		return {}
	spot.done = true
	var pid: String = ex.point
	var p: Dictionary = Data.table("map_points")[pid]
	var gain := exposure_gain(run, pid)
	ex.exposure = mini(EXPOSURE_MAX, int(ex.exposure) + gain)
	var found := {}
	var dropped := {}
	var rolls := 1 + (1 if Rng.chance(run, 0.45) else 0)
	if pid == "school" and State.is_role(run, "scholar"):
		rolls += 1
	for k in rolls:
		var e = Rng.weighted(run, p.loot)
		var qty := Rng.i(run, int(e[2]), int(e[3]))
		var room := carry(run) - Inv.weight(ex.bag)
		var w := float(Data.item(e[0]).get("weight", 0))
		if w > 0:
			qty = mini(qty, int(floor(room / w)))
		if qty <= 0:
			dropped[e[0]] = 1
			continue
		Inv.add(ex.bag, e[0], qty)
		found[e[0]] = int(found.get(e[0], 0)) + qty
	# 废墟里的破门窗、烂桌椅：顺手拆一捆柴（背得下才拿）
	if Rng.chance(run, 0.35):
		var room2 := carry(run) - Inv.weight(ex.bag)
		if room2 >= float(Data.item("firewood").get("weight", 5)):
			Inv.add(ex.bag, "firewood", 1)
			found["firewood"] = int(found.get("firewood", 0)) + 1
	var clue := ""
	if p.has("clue") and not p.clue in run.known_clues:
		var left := 0
		for s in ex.spots:
			if not s.done:
				left += 1
		if left == 0 or Rng.chance(run, 0.35):
			State.learn_clue(run, p.clue)
			clue = Data.table("clues")[p.clue].text
	State.add_xp(run, "search", 2)
	var note := "翻了%s：%s" % [spot.name, Data.describe_items(found) if not found.is_empty() else "一无所获"]
	if not dropped.is_empty():
		note += "（背不下了）"
	ex.notes.append(note)
	var result := {"found": found, "gain": gain, "caught": false, "clue": clue, "full": not dropped.is_empty()}
	if int(ex.exposure) >= EXPOSURE_MAX:
		result.caught = true
		_caught(run, p)
	return result


static func _caught(run: Dictionary, p: Dictionary) -> void:
	var ex: Dictionary = run.explore
	ex.caught = true
	var dmg := 8 + int(p.danger) * 4
	State.add_attr(run, "hp", -dmg)
	var chance := 0.2 + 0.05 * int(p.danger)
	if State.is_role(run, "herbalist"):
		chance *= 0.5
	var text := "阳气外泄，被尸群嗅到了！拼命逃回家，气血 -%d，丢了一半东西。" % dmg
	if not run.plague and Rng.chance(run, chance):
		run.plague = true
		text += "胳膊上多了几道黑紫的抓痕——染上尸毒了。"
	for id in ex.bag.keys():
		var n := Inv.count(ex.bag, id)
		Inv.add(ex.bag, id, -int(ceil(n / 2.0)))
	ex.notes.append(text)
	State.note(run, text)


## 回家：背囊入库，记下地点搜空的日子。
static func finish(run: Dictionary) -> Dictionary:
	var ex: Dictionary = run.explore
	var pid: String = ex.point
	var p: Dictionary = Data.table("map_points")[pid]
	var searched := 0
	for s in ex.spots:
		if s.done:
			searched += 1
	var all_done: bool = searched == ex.spots.size()
	if searched > 0:
		run.points[pid].looted_until = run.pday + (int(p.restock) if all_done else int(ceil(p.restock / 2.0)))
	Inv.add_all(run.home, ex.bag)
	var summary := {"point": p.name, "bag": ex.bag.duplicate(), "caught": ex.caught}
	State.note(run, "从%s回来，带回%s。" % [p.name, Data.describe_items(ex.bag) if not ex.bag.is_empty() else "一身冷汗"])
	run.explore = {}
	State.check_death(run, "死在从%s逃回来的路上。" % p.name)
	return summary
