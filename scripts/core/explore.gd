extends RefCounted
## 外出搜寻。对应原版 ExploreManager + Config_MapPoint：
## 每翻一处就涨"阳气外泄"（原版的暴露值），涨满被尸群发现；地点会被搜空、会沦陷。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Expedition = preload("res://scripts/core/expedition.gd")

const EXPOSURE_MAX := 100
const SITE_SPOTS := {"rice_ruin": "米仓", "city_god": "供桌", "school": "藏书阁", "pharmacy_ruin": "药柜", "lumber": "木垛", "mortuary": "前厅棺木", "granary": "东仓", "taoist_temple": "丹房"}
const SITE_BRIEFS := {
	"rice_ruin": "每次到访可细筛一处粮袋，耗时 30 分钟，保证找到米 ×2、杂粮 ×1。",
	"city_god": "每次到访可花 20 分钟留下一处供物，放弃该处物资，心神最多 +3、阳气外泄最多减少 10。",
	"school": "每次到访可花 35 分钟整理一处书架，保证找到《齐民要术》残本 1。",
	"pharmacy_ruin": "每次到访可花 30 分钟辨认一处药格，保证找到金创药 ×1、避瘟散 ×1。",
	"lumber": "每次到访可花 35 分钟拆取一处木垛，得到木料 ×2、柴 ×3，须考虑负重。",
	"mortuary": "每次到访可花 20 分钟，消耗背囊里的镇尸符 1，先降低最多 20 点阳气外泄，再正常翻找一处。",
	"granary": "每次到访可花 20 分钟砸开一处粮栅，保证米 ×3、杂粮 ×2，但额外增加 25 点阳气外泄。",
	"taoist_temple": "每次到访可花 30 分钟辨认符阵，之后本次普通翻找的阳气外泄减少 8。",
}
const SITE_TITLES := {"rice_ruin": "细筛粮袋", "city_god": "留下供物", "school": "整理书架", "pharmacy_ruin": "辨认药格", "lumber": "拆取木料", "mortuary": "消耗符箓护身", "granary": "砸开粮栅", "taoist_temple": "辨认符阵"}
const SITE_MINUTES := {"rice_ruin": 30, "school": 35, "pharmacy_ruin": 30, "lumber": 35, "taoist_temple": 30}
const SITE_ITEMS := {"rice_ruin": {"rice": 2, "millet": 1}, "school": {"book_farm": 1}, "pharmacy_ruin": {"salve": 1, "plague_powder": 1}, "lumber": {"wood": 2, "firewood": 3}, "granary": {"rice": 3, "millet": 2}}
# 只调整既有地点物资的权重；未列出的点位仍使用地点原始物资池。
const SPOT_PREFERENCES := {
	"rice_ruin": {"米仓": ["rice", "millet"], "后院粮袋": ["rice", "millet"], "账房": ["salt", "pickles"]},
	"pharmacy_ruin": {"药柜": ["salve", "plague_powder"], "炮制间": ["mugwort", "cinnabar"]},
	"school": {"藏书阁": ["book_farm", "book_cook", "book_guard", "book_build", "book_daoist"]},
	"lumber": {"木垛": ["wood", "firewood"], "铁匠角": ["nails"]},
	"granary": {"东仓": ["rice"], "西仓": ["millet"], "粮车": ["jerky"]},
}


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
	if not Data.table("map_points").has(pid): return "没有这个可探索的地方。"
	var p: Dictionary = Data.table("map_points")[pid]
	if p.has("unlock_flag") and not State.flag(run, p.unlock_flag): return "还没找到进山的路，先把义庄那边查清。"
	if run.pday < int(p.get("unlock_day", 0)):
		return "第 %d 日后才打听到这里" % p.unlock_day
	if p.has("fall_day") and run.pday >= int(p.fall_day):
		return "已沦陷，尸群占了这里"
	var until := int(run.points.get(pid, {}).get("looted_until", 0))
	if until > run.pday:
		var objective := Mainline.objective(run, pid)
		if objective.is_empty(): return "被搜空了，还要 %d 日才缓得过来" % (until - run.pday)
		if str(objective.get("block", "")) != "": return str(objective.block)
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
	var only_investigate := int(run.points.get(pid, {}).get("looted_until", 0)) > int(run.pday) and not Mainline.objective(run, pid).is_empty()
	if not only_investigate:
		var selected: Array = Rng.shuffled(run, p.spots).slice(0, n)
		var signature := str(SITE_SPOTS.get(pid, ""))
		if signature != "" and signature in p.spots and not signature in selected:
			selected[selected.size() - 1] = signature
		for s in selected:
			spots.append({"name": s, "done": false})
	Neighbor.add_objective(run, pid, spots)
	Mainline.add_objective(run, pid, spots)
	run.explore = {"point": pid, "spots": spots, "exposure": 0, "bag": {}, "caught": false, "notes": [], "only_investigate": only_investigate}
	State.add_attr(run, "energy", -6)
	if not pid in run.points:
		run.points[pid] = {"looted_until": 0, "visits": 0}
	run.points[pid].visits = int(run.points[pid].visits) + 1


static func _exposure_multiplier(run: Dictionary) -> float:
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
	return maxf(mul, 0.2)


static func _exposure_amount(run: Dictionary, pid: String, roll: int) -> int:
	var p: Dictionary = Data.table("map_points")[pid]
	var reduction := 8 if run.get("explore", {}).get("point", "") == pid and run.get("explore", {}).get("site_ward", false) else 0
	if run.get("explore", {}).get("point", "") == pid and run.get("explore", {}).get("journey_quiet", false): reduction += 16
	return maxi(0, maxi(3, int(round(float(int(p.danger) * 8 + roll) * _exposure_multiplier(run)))) - reduction)


## 预测普通翻找外泄范围，不消耗随机数。
static func exposure_range(run: Dictionary, pid: String) -> Vector2i:
	return Vector2i(_exposure_amount(run, pid, 0), _exposure_amount(run, pid, 8))


static func exposure_gain(run: Dictionary, pid: String) -> int:
	return _exposure_amount(run, pid, Rng.i(run, 0, 8))


static func loot_pool(pid: String, spot_name: String) -> Array:
	var p: Dictionary = Data.table("map_points")[pid]
	var preferred: Array = SPOT_PREFERENCES.get(pid, {}).get(spot_name, [])
	var pool: Array = p.loot.duplicate(true)
	for entry in pool:
		if entry[0] in preferred:
			entry[1] = int(entry[1]) * 3
	return pool


static func site_brief(pid: String) -> String:
	return str(SITE_BRIEFS.get(pid, ""))


static func site_options(run: Dictionary, idx: int) -> Array:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or idx < 0 or idx >= ex.get("spots", []).size(): return []
	var spot: Dictionary = ex.spots[idx]
	if spot.get("done", false) or spot.has("mainline") or spot.has("neighbor") or ex.get("caught", false) or ex.get("curfew_due", false): return []
	var pid := str(ex.get("point", ""))
	var range := exposure_range(run, pid)
	var normal := {"id": "normal", "title": "翻找", "description": "20 分钟，精力 -4，阳气外泄增加 %d–%d；物资随机留在现场。" % [range.x, range.y], "block": ""}
	if not SITE_BRIEFS.has(pid) or str(spot.get("name", "")) != str(SITE_SPOTS.get(pid, "")): return [normal]
	var block := ""
	if ex.get("site_used", false): block = "本次到访已使用过地点特色。"
	elif pid == "mortuary" and Inv.count(ex.get("bag", {}), "talisman") < 1: block = "需要背囊里有镇尸符 1。"
	var desc := str(SITE_BRIEFS[pid]) + " 精力 -4。"
	if pid in SITE_ITEMS: desc += " 替代该处随机物资，所得留在现场；被追上或宵禁后无法领取。"
	elif pid == "mortuary": desc += " 翻找所得随机留在现场。"
	elif pid == "taoist_temple": desc += " 本次翻找物资随机留在现场，减免从之后的普通翻找生效。"
	if pid != "city_god":
		var bonus := 25 if pid == "granary" else 0
		desc += " 本次阳气外泄增加 %d–%d（最高 100）。" % [range.x + bonus, range.y + bonus]
	return [normal, {"id": "site", "title": SITE_TITLES[pid], "description": desc, "block": block}]


static func search(run: Dictionary, idx: int, option_id := "", reserved_gain := -1) -> Dictionary:
	var ex: Dictionary = run.explore
	if ex.is_empty() or idx < 0 or idx >= ex.spots.size():
		return {}
	var spot: Dictionary = ex.spots[idx]
	if spot.done or ex.caught:
		return {}
	if Expedition.target_locked(run, idx):
		return {"blocked": "道路被机关封住；先查找两处线索，再解开机关。"}
	if spot.has("mainline"):
		if option_id not in ["", "normal"]: return {"blocked": "要查的地方不能用这里的特别做法。"}
		var result := Mainline.search_objective(run, spot)
		if not result.is_empty() and int(ex.exposure) >= EXPOSURE_MAX and str(result.get("blocked", "")) == "":
			result["caught"] = true
			_caught(run, Data.table("map_points")[ex.point])
		return result
	if spot.has("neighbor"):
		if option_id not in ["", "normal"]: return {"blocked": "要查的地方不能用这里的特别做法。"}
		return Neighbor.search_objective(run, spot)
	if option_id == "": option_id = "normal"
	var selected := {}
	for option in site_options(run, idx):
		if option.id == option_id: selected = option; break
	if selected.is_empty(): return {"blocked": "无效的搜寻方式。"}
	if str(selected.block) != "": return {"blocked": selected.block}
	spot.done = true
	var pid: String = ex.point
	var p: Dictionary = Data.table("map_points")[pid]
	var special := option_id == "site"
	if special:
		ex["site_used"] = true
		if pid == "city_god":
			ex.exposure = maxi(0, int(ex.exposure) - 10)
			State.add_attr(run, "mood", 3)
			spot["loot"] = {}
			State.add_xp(run, "search", 2)
			ex.notes.append("留下供物，心神回暖，阳气外泄减少。")
			return {"found": {}, "gain": 0, "caught": false, "clue": "", "full": false, "minutes": 20}
		if pid == "mortuary":
			Inv.add(ex.bag, "talisman", -1)
			ex.exposure = maxi(0, int(ex.exposure) - 20)
	var gain := reserved_gain if reserved_gain >= 0 else exposure_gain(run, pid)
	if special and pid == "granary": gain += 25
	ex.exposure = mini(EXPOSURE_MAX, int(ex.exposure) + gain)
	var found := {}
	if special and SITE_ITEMS.has(pid):
		found = SITE_ITEMS[pid].duplicate(true)
	else:
		var rolls := 1 + (1 if Rng.chance(run, 0.45) else 0)
		if pid == "school" and State.is_role(run, "scholar"): rolls += 1
		var pool := loot_pool(pid, str(spot.name))
		for k in rolls:
			var e = Rng.weighted(run, pool)
			var qty := Rng.i(run, int(e[2]), int(e[3]))
			found[e[0]] = int(found.get(e[0], 0)) + qty
		if Rng.chance(run, 0.35): found["firewood"] = int(found.get("firewood", 0)) + 1
	if special and pid == "taoist_temple": ex["site_ward"] = true
	spot["loot"] = found.duplicate()
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
	var note := "翻了%s，发现：%s" % [spot.name, Data.describe_items(found) if not found.is_empty() else "一无所获"]
	ex.notes.append(note)
	var result := {"found": found, "gain": gain, "caught": false, "clue": clue, "full": false, "minutes": int(SITE_MINUTES.get(pid, 20)) if special else 20}
	if int(ex.exposure) >= EXPOSURE_MAX:
		result.caught = true
		_caught(run, p)
	return result


## 从已搜索的普通点领取物资，返回实际取得的数量。
## 老存档没有 loot 时视为空；同一物资多次领取只会转移剩余数量。
static func take(run: Dictionary, idx: int, item_id: String, amount: int) -> int:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or run.get("pending_event", "") != "" or idx < 0 or idx >= ex.spots.size() or amount <= 0:
		return 0
	var spot: Dictionary = ex.spots[idx]
	if not spot.get("done", false) or spot.has("mainline") or spot.has("neighbor"):
		return 0
	var loot: Dictionary = spot.get("loot", {})
	var qty := mini(amount, Inv.count(loot, item_id))
	if qty <= 0:
		return 0
	var weight := float(Data.item(item_id).get("weight", 0))
	if weight > 0:
		var room := maxf(0.0, carry(run) - Inv.weight(ex.bag))
		qty = mini(qty, maxi(0, int(floor(room / weight))))
	if qty <= 0:
		return 0
	Inv.add(loot, item_id, -qty)
	Inv.add(ex.bag, item_id, qty)
	return qty


## 把背囊中的物资放回已搜索的普通点；以后可以再次领取。
static func put_back(run: Dictionary, idx: int, item_id: String, amount: int) -> int:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or run.get("pending_event", "") != "" or idx < 0 or idx >= ex.spots.size() or amount <= 0:
		return 0
	var spot: Dictionary = ex.spots[idx]
	if not spot.get("done", false) or spot.has("mainline") or spot.has("neighbor"):
		return 0
	var qty := mini(amount, Inv.count(ex.bag, item_id))
	if qty <= 0:
		return 0
	if not spot.has("loot"):
		spot["loot"] = {}
	Inv.add(ex.bag, item_id, -qty)
	Inv.add(spot.loot, item_id, qty)
	return qty


static func _caught(run: Dictionary, p: Dictionary) -> void:
	var ex: Dictionary = run.explore
	ex.caught = true
	# 受捕时现场尚未装包的物资无法带走，避免自动撤离前再领取。
	for spot in ex.spots:
		spot.erase("loot")
	if ex.get("journey", null) is Dictionary: ex.journey["caches"] = {}
	if str(run.get("busy", {}).get("kind", "")) == "mainline": run.busy = {}
	Mainline.lost_cargo(run)
	ex.erase("mainline_cargo")
	var dmg := 8 + int(p.danger) * 4
	State.hurt(run, float(dmg), "wound")
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


static func capture_if_due(run: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	if ex.get("neighbor_capture_due", false):
		ex.erase("neighbor_capture_due")
		if not ex.get("caught", false):
			_caught(run, Data.table("map_points")[ex.point])
			State.check_death(run, "砸锁惊动尸群，没能逃出药铺。")


## 回家：背囊入库，记下地点搜空的日子。
static func finish(run: Dictionary) -> Dictionary:
	var ex: Dictionary = run.explore
	var pid: String = ex.point
	var p: Dictionary = Data.table("map_points")[pid]
	var searched := 0
	for s in ex.spots:
		if s.has("mainline") or s.has("neighbor"): continue
		if s.done:
			searched += 1
	var ordinary: int = ex.spots.filter(func(s): return not s.has("mainline") and not s.has("neighbor")).size()
	var all_done: bool = searched == ordinary
	var journey_done: bool = ex.get("journey", {}).get("completed", {}).size() > 0
	if searched > 0 or journey_done:
		run.points[pid].looted_until = run.pday + (int(p.restock) if all_done else int(ceil(p.restock / 2.0)))
	Inv.add_all(run.home, ex.bag)
	var summary := {"point": p.name, "bag": ex.bag.duplicate(), "caught": ex.caught}
	State.note(run, "从%s回来，带回%s。" % [p.name, Data.describe_items(ex.bag) if not ex.bag.is_empty() else "一身冷汗"])
	run.explore = {}
	State.check_death(run, "死在从%s逃回来的路上。" % p.name)
	return summary
