extends RefCounted
## 一局的全部状态都放在一个 Dictionary（run）里：存档就是 JSON，翻生死簿就是深拷贝。
## 这里放新开一局和各系统共用的小工具。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Past = preload("res://scripts/core/past_lives.gd")

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
	return {"daoxin": 0, "talents": [], "runs": 0, "deaths": 0, "best_day": 0, "clues": [], "endings": 0,
		"daily": new_daily(), "past_lives": Past.fresh_book()}


## 每日一局的记分板。只记每日局（种子按日期的那种），寻常随机局不往里记。
## best = 当日最好，all = 历来最好，都按模式分组（寻常 / 守到死）。
static func new_daily() -> Dictionary:
	return {"day": "", "runs": 0, "best": {}, "all": {}}


## 今天（本地日期）写成 2026-10-24。
static func today_text() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


## 每日一局的种子：只取日期、不掺时刻，所以同一天开的局拿到的都是同一副牌。
## 放在这里而不是界面里：界面（Game）和测试（sim_test、ui_smoke）都得看到同一个算法。
static func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


static func new_run(role_id: String, meta: Dictionary, seed_value: int, difficulty_id: String = "normal", goals: Array = [], boons: Array = [], vows: Array = []) -> Dictionary:
	var role_data: Dictionary = Data.table("roles")[role_id]
	var talents: Array = meta.get("talents", []).duplicate()
	var d: Dictionary = diff_params(difficulty_id)
	var hp_max: int = int(round(float(role_data.hp_max) * float(d.get("hp_mul", 1.0))))
	var silver: int = int(round(float(role_data.silver) * float(d.get("silver_mul", 1.0))))
	var run := {
		"version": 19, "seed": seed_value, "rng_n": 0, "role": role_id, "talents": talents,
		"opening": {},
		"identity": {},
		"mainline": {},
		"npcs": {"schema": 1, "revision": 0, "next_day": 2, "actors": {}, "history": []},
		"crisis": {},
		"trade": {},
		"director": {},
		"neighbor": {},
		## 同院的人（备劫前带回来的帮手），id 见 data/companions.json
		"companions": [],
		"difficulty": difficulty_id,
		## 挑战自选的记账本：了愿挑了哪几个、备劫买了什么、修过几次门、回过几趟家
		"tally": {"goals": goals.duplicate(), "vows": vows.duplicate(), "boons": boons.duplicate(), "bought": {}, "repair_door": 0, "home_trips": 0, "orders": 0},
		"phase": "pre", "day": 1, "hour": OPEN_HOUR, "loc": "home",
		"pday": 0, "t": 0, "busy": {}, "sleeping": false, "heated": false, "powered": false, "night_lines": [],
		"wave_due": false, "wave_day": 0, "wave_report": {}, "raid_report": {}, "dawn_due": false,
		"guard_spot": "", "plan_due": false, "heat_weak": false, "night": {},
		"fight": {}, "door_open": false, "broken": [],
		"silver": silver, "cart": {}, "home": role_data.items.duplicate(),
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
	# 凭仗：开局该给的银子、东西先发下去（设施类等到尸劫降临再并进 run.facilities）
	for b in boon_tables(boons):
		if b.has("silver"):
			run.silver = int(run.silver) + int(b.silver)
		for id in b.get("items", {}):
			Inv.add(run.home, str(id), int(b.items[id]))
	# 誓约：空手——身份带的随身物一件不留（别的誓约都是靠结算时查，不用这里改）
	if "bare" in vows:
		run.home = {}
	note(run, "%s，醒在三日之前。手里攥着一张生死簿残页。" % role_data.name)
	Past.begin(run, meta)
	return run


## 把挑了的凭仗 id 换成表里的完整数据（顺手把不认识的 id 丢掉，别让存档带脏数据）
static func boon_tables(boons: Array) -> Array:
	var out := []
	for b in Data.table("challenge").get("boons", []):
		if str(b.get("id", "")) in boons:
			out.append(b)
	return out


## 挑了的凭仗各自扣多少倍率（正的数，越小越狠）
static func boon_malus(run: Dictionary) -> float:
	var m := 0.0
	for b in boon_tables(tally(run).get("boons", [])):
		m += float(b.get("malus", 0.0))
	return m


static func role(run: Dictionary) -> Dictionary:
	return Data.table("roles")[run.role]


## 这一局的难度参数（乘数）。没配的就是 1.0，等于寻常年景。
static func diff(run: Dictionary) -> Dictionary:
	return diff_params(str(run.get("difficulty", "normal")))


## 按难度 id 取参数；id 不存在就退回寻常年景，不让它把一局搅坏。
static func diff_params(difficulty_id: String) -> Dictionary:
	var out := {"silver_mul": 1.0, "hp_mul": 1.0, "food_mul": 1.0, "water_mul": 1.0,
		"cold_add": 0, "wave_mul": 1.0}
	var list: Array = Data.table("difficulty")
	for d in list:
		if str(d.get("id", "")) == difficulty_id:
			for k in out:
				if d.get("params", {}).has(k):
					out[k] = d.params[k]
			return out
	return out


## 难度名字（HUD、结算、生死簿上用）。
static func diff_name(run: Dictionary) -> String:
	var id := str(run.get("difficulty", "normal"))
	for d in Data.table("difficulty"):
		if str(d.get("id", "")) == id:
			return str(d.get("name", "寻常年景"))
	return "寻常年景"


## 挑战记账本（老存档没有就现补一个空壳，不让它把结算搅坏）。
static func tally(run: Dictionary) -> Dictionary:
	if not run.has("tally") or typeof(run.tally) != TYPE_DICTIONARY:
		run.tally = {"goals": [], "vows": [], "boons": [], "bought": {}, "repair_door": 0, "home_trips": 0}
	return run.tally


## 挑了哪几个了愿。
static func goals_of(run: Dictionary) -> Array:
	return tally(run).get("goals", [])


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
