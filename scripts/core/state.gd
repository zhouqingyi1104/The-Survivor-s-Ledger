extends RefCounted
## 一局的全部状态都放在一个 Dictionary（run）里：存档就是 JSON，翻生死簿就是深拷贝。
## 这里放新开一局和各系统共用的小工具。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")

const ATTR_NAMES := {"hp": "气血", "food": "饱腹", "water": "饮水", "mood": "心神", "energy": "精力", "warmth": "体温"}
const PROF_NAMES := {"farm": "农事", "cook": "庖厨", "search": "搜寻", "guard": "守御", "build": "营造"}
const PROF_XP := [0, 10, 25, 45, 70]
const HOURS := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const SEGS := ["晨", "午", "暮", "夜"]
const OPEN_HOUR := 3     # 卯时开市
const CURFEW_HOUR := 9   # 酉时宵禁
const PRE_DAYS := 3
const STORY_DAYS := 20
const LOG_LIMIT := 300


static func new_meta() -> Dictionary:
	return {"daoxin": 0, "talents": [], "runs": 0, "deaths": 0, "best_day": 0, "clues": [], "endings": 0}


static func new_run(role_id: String, meta: Dictionary, seed_value: int) -> Dictionary:
	var role_data: Dictionary = Data.table("roles")[role_id]
	var talents: Array = meta.get("talents", []).duplicate()
	var hp_max: int = role_data.hp_max + (20 if "jinzhong" in talents else 0)
	var run := {
		"version": 5, "seed": seed_value, "rng_n": 0, "role": role_id, "talents": talents,
		"phase": "pre", "day": 1, "hour": OPEN_HOUR, "loc": "home",
		"pday": 0, "t": 0, "busy": {}, "sleeping": false, "heated": false, "night_lines": [],
		"wave_due": false, "wave_day": 0, "wave_report": {}, "raid_report": {}, "dawn_due": false,
		"guard_spot": "", "plan_due": false, "heat_weak": false, "night": {},
		"fight": {}, "door_open": false, "broken": [],
		"silver": role_data.silver, "cart": {}, "home": role_data.items.duplicate(),
		"orders": [], "facilities": [], "shops": {},
		"attrs": {"hp": hp_max, "hp_max": hp_max, "food": 80, "water": 80, "mood": 60, "energy": 100, "warmth": 80},
		"plague": false,
		"door": {"cur": 100, "max": 100}, "window": {"cur": 60, "max": 60}, "wall": {"cur": 120, "max": 120},
		"devices": [], "plots": [],
		"prof": {"farm": 0, "cook": 0, "search": 0, "guard": 0, "build": 0},
		"points": {}, "buffs": [], "read": [],
		"merit": 0, "omens": {"offer": [], "locked": "", "taken": []},
		"wish": {}, "today": {},
		"flags": {}, "known_clues": meta.get("clues", []).duplicate(), "clues_new": [],
		"pending_event": "", "event_result": "", "seen_events": [], "raid_tonight": false,
		"well_used": false, "explore": {}, "report": {},
		"kills": 0, "waves_survived": 0, "rebirths_left": 3,
		"death_cause": "", "endless": false, "log": [],
	}
	for shop_id in Data.table("shops"):
		run.shops[shop_id] = Data.table("shops")[shop_id].get("stock", {}).duplicate()
	if "talisman" in talents:
		Inv.add(run.home, "talisman", 3)
		run.flags["learned_talisman"] = true
	note(run, "%s，醒在三日之前。手里攥着一张生死簿残页。" % role_data.name)
	return run


static func role(run: Dictionary) -> Dictionary:
	return Data.table("roles")[run.role]


static func has_talent(run: Dictionary, id: String) -> bool:
	return id in run.talents


static func is_role(run: Dictionary, id: String) -> bool:
	return run.role == id


static func flag(run: Dictionary, id: String) -> bool:
	return bool(run.flags.get(id, false))


static func has_buff(run: Dictionary, id: String) -> bool:
	return id in run.buffs


static func has_facility(run: Dictionary, id: String) -> bool:
	return id in run.facilities


## 属性内部按小数累积（连续时间每 10 分钟掉一点），对外取整。
static func attr(run: Dictionary, key: String) -> int:
	return int(round(float(run.attrs[key])))


static func attr_max(run: Dictionary, key: String) -> int:
	return int(run.attrs.hp_max) if key == "hp" else 100


static func add_attr(run: Dictionary, key: String, delta: float) -> void:
	run.attrs[key] = clampf(float(run.attrs[key]) + delta, 0.0, float(attr_max(run, key)))


static func prof_level(run: Dictionary, key: String) -> int:
	var xp := int(run.prof[key])
	var lv := 0
	for k in PROF_XP.size():
		if xp >= PROF_XP[k]:
			lv = k
	return lv


## 返回升级提示，没升级返回空串。
static func add_xp(run: Dictionary, key: String, n: int) -> String:
	var before := prof_level(run, key)
	run.prof[key] = int(run.prof[key]) + n
	var after := prof_level(run, key)
	if after > before:
		var msg := "%s熟练升到了 %d 级。" % [PROF_NAMES[key], after]
		note(run, msg)
		return msg
	return ""


## 自身武力：身份底子 + 兵器 + 守御熟练，心神太差时打折扣。
static func fight(run: Dictionary) -> float:
	var f := float(role(run).fight)
	if Inv.count(run.home, "peach_sword") > 0:
		f += 6
	elif Inv.count(run.home, "chopper") > 0:
		f += 3
	f += prof_level(run, "guard") * 1.5
	if attr(run, "mood") < 20:
		f *= 0.7
	elif attr(run, "mood") >= 80:
		f *= 1.1
	return f


static func weather(run: Dictionary) -> Dictionary:
	for w in Data.table("weather"):
		if run.pday >= w["from"] and run.pday <= w["to"]:
			return w
	return Data.table("weather")[-1]


static func time_label(run: Dictionary) -> String:
	if run.phase == "pre":
		return "备劫第%d日·%s时" % [run.day, HOURS[run.hour % 12]]
	if int(run.pday) == 0:
		return "尸劫之夜"
	var c := (int(run.get("t", 0)) + 360) % 1440
	return "第%d日·%02d:%02d" % [run.pday, c / 60, c % 60]


static func note(run: Dictionary, text: String) -> void:
	run.log.append("【%s】%s" % [time_label(run), text])
	if run.log.size() > LOG_LIMIT:
		run.log = run.log.slice(run.log.size() - LOG_LIMIT)


static func learn_clue(run: Dictionary, clue_id: String) -> bool:
	if clue_id in run.known_clues:
		return false
	run.known_clues.append(clue_id)
	run.clues_new.append(clue_id)
	note(run, "得【%s】：%s" % [Data.table("clues")[clue_id].name, Data.table("clues")[clue_id].text])
	return true


## 菜畦里的作物立刻长 n 日（求签"五谷丰登"，不管浇没浇水）。
static func grow_crops(run: Dictionary, n: int) -> void:
	for plot in run.plots:
		if plot.crop != "":
			plot.days = float(plot.days) + n


static func check_death(run: Dictionary, cause: String) -> bool:
	if attr(run, "hp") > 0 or run.phase == "dead":
		return run.phase == "dead"
	run.phase = "dead"
	run.death_cause = cause
	note(run, "气血已尽。%s" % cause)
	return true
