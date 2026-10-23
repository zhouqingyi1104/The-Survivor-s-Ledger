extends RefCounted
## 同院的人：备劫前带回来的帮手。每天天亮各干一件事，代价是多一张嘴。
## 对应原版 SelectPeople 的"选择带走谁"那一层。人选和工种全在 data/companions.json。
## 不改道心倍率——他们不是誓约也不是凭仗，代价走的是粮和水（每天天亮实收）。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")

## 一天的口粮：多少点饱腹的吃食 + 几瓢清水。吃得上才干活。
const FOOD_PER_DAY := 12.0
const WATER_PER_DAY := 1
## 木匠每天修多少耐久
const MEND_AMOUNT := 25


static func list(run: Dictionary) -> Array:
	return run.get("companions", [])


static func data(id: String) -> Dictionary:
	return Data.table("companions").get(id, {})


## 每人每天：先收口粮（吃不上就饿一天、掉心情、不干活），再干各人的活。
## 返回这天的动静，给天亮报告用。
static func dawn(run: Dictionary) -> Array:
	var out := []
	for id in list(run):
		var c := data(id)
		if c.is_empty():
			continue
		var who := str(c.get("name", id))
		var need: Dictionary = c.get("upkeep", {})
		if not _feed(run, float(need.get("food", FOOD_PER_DAY)), int(need.get("water", WATER_PER_DAY))):
			out.append("%s饿着肚子，今天什么也没干。" % who)
			State.add_attr(run, "mood", -3)
			continue
		var line := _job(run, str(c.get("job", "")), who)
		if line != "":
			out.append(line)
	return out


## 收口粮：先吃饱腹低的（坏菜别浪费）。吃食不够或水不够都算没喂饱。
static func _feed(run: Dictionary, food: float, water: int) -> bool:
	if int(Inv.count(run.home, "water")) < water:
		return false
	var got := 0.0
	for id in Inv.food_ids(run.home):
		var v := float(Data.item(id).get("eat", {}).get("food", 0))
		while Inv.count(run.home, id) > 0 and got < food:
			Inv.add(run.home, id, -1)
			got += v
		if got >= food:
			break
	if got < food:
		# 没喂饱：吃掉的不退（已经在肚子里了），这一天他不干活
		return false
	Inv.add(run.home, "water", -water)
	return true


static func _job(run: Dictionary, job: String, who: String) -> String:
	match job:
		"cook":
			for gid in ["rice", "millet"]:
				if Inv.count(run.home, gid) > 0 and Inv.count(run.home, "water") > 0 and Inv.count(run.home, "firewood") > 0:
					Inv.add(run.home, gid, -1)
					Inv.add(run.home, "water", -1)
					Inv.add(run.home, "firewood", -1)
					var dish := "flatbread" if gid == "rice" else "millet_cake"
					Inv.add(run.home, dish, 3)
					return "%s蒸了一锅%s，得 3 份。" % [who, Data.item_name(dish)]
			return "%s没凑齐粮、水、柴，灶没生起来。" % who
		"mend":
			var worst := ""
			var low := 1 << 30
			for part in ["door", "window", "wall"]:
				var p: Dictionary = run[part]
				if int(p.cur) < int(p.max) and int(p.cur) < low:
					low = int(p.cur)
					worst = part
			if worst == "":
				return ""
			if Inv.count(run.home, "wood") <= 0:
				return "%s想修%s，可家里没木料。" % [who, _part_name(worst)]
			Inv.add(run.home, "wood", -1)
			var part2: Dictionary = run[worst]
			part2.cur = mini(int(part2.max), int(part2.cur) + MEND_AMOUNT)
			# 他修的门也记在你账上：誓约「不修门」查的是修过几次，不管是谁挥的锤子
			if worst == "door":
				run.tally["repair_door"] = int(run.tally.get("repair_door", 0)) + 1
			return "%s修了%s，耐久 +%d。" % [who, _part_name(worst), MEND_AMOUNT]
		"water":
			Inv.add(run.home, "water", 2)
			var plots: Array = run.get("plots", [])
			for plot in plots:
				plot["watered_t"] = int(run.t)
			var extra := "，顺手把菜畦都浇了" if not plots.is_empty() else ""
			return "%s打了两瓢水%s。" % [who, extra]
	return ""


static func _part_name(part: String) -> String:
	match part:
		"door":
			return "院门"
		"window":
			return "窗"
	return "院墙"
