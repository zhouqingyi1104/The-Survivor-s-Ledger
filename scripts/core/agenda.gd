extends RefCounted
## 今日差事：一天醒着能用的十六个钟头里，摆上二十四个钟头值得做的事——做不完，只能挑。
##
## 第一性原理：玩家"发呆"不是因为时间太多，是因为看不见"拿时间能换什么"。
## 所以每天卯时把今天能做的事列成一张单子，每件写清花多久、换什么；
## 单子总时长按 OVERLOAD 倍于醒着的时间来排，于是"做什么"变成"先不做什么"。
##
## 单子里两类：
##   builtin —— 既有行动（打水、做饭、外出……），由 Post.agenda_offers 判断今天做不做得成；
##   chore   —— 只换时间、不靠囤货的活计（data/chores.json），这一批新加的内容。
## 抽签用自己的种子（局种子 + 第几日），不动 run.rng_n：加了差事单，事件、搜寻、夜战的随机结果一个都不变。
## 放在 core 里：总时长、过时、效用这些都要能无界面断言。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Crisis = preload("res://scripts/core/crisis.gd")

const DAY := 1440
## 当天第几分钟算"该收工"：22:00（= Post.WAVE_AT）。尸潮夜这之后要守夜，平常夜里也该睡了。
const DAY_END := 960
## 差事总时长 / 醒着能用的时长。1.5 倍：二十四个钟头的事，十六个钟头里做。
const OVERLOAD := 1.5
const TARGET := int(DAY_END * OVERLOAD)
## 絮了棉衣，夜里体温掉得只剩六成；盘成火炕，睡着时再打六折（Post._tick 里用）
const PADDED_COLD := 0.6
const KANG_COLD := 0.6

## 折进差事单的既有行动。action 是 run.today.actions 里记的行动名（缺省同键名），
## 今天记到第 nth 回就算办了（外出可以跑两趟）。
## minutes 是估计（外出按来回两个钟头 + 翻三处算），deadline 是当天第几分钟前得动身。
const BUILTIN := {
	"water": {"name": "打水", "spot": "well", "minutes": 15, "tag": "水", "why": "井边一天只打一回，两瓢。"},
	"cook": {"name": "生火做饭", "spot": "stove", "minutes": 60, "tag": "粮", "why": "米菜下锅，一锅出两三份。"},
	"garden": {"name": "浇水 · 收成", "spot": "garden", "minutes": 45, "tag": "粮", "why": "隔了一天不浇，菜就不长。"},
	"repair": {"name": "修缮门窗墙", "spot": "bench", "minutes": 60, "tag": "守", "why": "一根木料（或两捆柴）补一面，耐久 +35。"},
	"explore": {"name": "出门搜寻", "spot": "gate", "minutes": 180, "deadline": 660, "tag": "探",
		"why": "来回两个钟头的路，再翻三四处；粮、柴、木料、符纸都靠这一趟。"},
	"explore2": {"name": "再跑一趟", "action": "explore", "nth": 2, "spot": "gate", "minutes": 180, "deadline": 660, "tag": "探",
		"why": "一趟背不回多少；趁天亮换一处没搜空的地方再去。"},
	"craft": {"name": "加工 · 画符", "spot": "bench", "minutes": 60, "tag": "守", "why": "手上的料能加工成炭、符、药或干粮。"},
	"read": {"name": "读书", "spot": "desk", "minutes": 120, "tag": "艺", "why": "还有没读过的书，读完熟练见长。"},
}

const BUFF_TEXT := {
	"padded": "今夜体温少掉四成",
	"guard_plus": "今夜三面守力各 +4",
	"stealth": "今日外出阳气外泄 -40%",
}


# ---------- 状态 ----------

## run.agenda：{day, items: [{id, kind, done}], used: {id: 次数}, planned}
## used 跨日保留（偏厦的椽子拆一根少一根），items 每天重排。老存档没有就现补。
static func state(run: Dictionary) -> Dictionary:
	if not (run.get("agenda") is Dictionary):
		run["agenda"] = {}
	var s: Dictionary = run.agenda
	if not s.has("items"):
		s["items"] = []
	if not s.has("used"):
		s["used"] = {}
	if not s.has("day"):
		s["day"] = 0
	return s


static func chore(id: String) -> Dictionary:
	return Data.table("chores").get(id, {})


## 单子上一行的规格（名称、去哪、多久、说明）：既有行动查 BUILTIN，差事查表。
static func spec(item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) == "builtin":
		return BUILTIN.get(str(item.get("id", "")), {})
	return chore(str(item.get("id", "")))


static func item(run: Dictionary, idx: int) -> Dictionary:
	var items: Array = state(run).items
	if idx < 0 or idx >= items.size():
		return {}
	return items[idx]


static func used(run: Dictionary, id: String) -> int:
	return int(state(run).used.get(id, 0))


## 一局里最多做几回：limit（拆完就没了）或 steps（工程分几回做完）；0 = 不限。
static func cap(id: String) -> int:
	var c := chore(id)
	return int(c.get("steps", c.get("limit", 0)))


static func day_minute(run: Dictionary) -> int:
	return int(run.get("t", 0)) - (int(run.get("pday", 1)) - 1) * DAY


## 离收工（22:00）还剩几分钟。
static func left_minutes(run: Dictionary) -> int:
	return maxi(0, DAY_END - day_minute(run))


## 今夜多冷（与 Post.cold_of 同一算法：天气 + 难度加冷）。
static func cold(run: Dictionary) -> int:
	return int(State.weather(run).get("cold", 0)) + int(State.diff(run).get("cold_add", 0))


static func wave_tonight(run: Dictionary) -> bool:
	return not Defense.wave_for_run(run, int(run.pday)).is_empty() and int(run.get("wave_day", 0)) != int(run.pday)


## 最破的一面（按剩余比例）；都完好返回 ""。
static func weakest(run: Dictionary) -> String:
	var best := ""
	var worst := 1.0
	for sid in Defense.SURFACES:
		var part: Dictionary = Defense.part_of(run, sid)
		var ratio := float(part.cur) / maxf(1.0, float(part.max))
		if ratio < worst:
			worst = ratio
			best = sid
	return best


static func _planted(run: Dictionary) -> bool:
	for plot in run.get("plots", []):
		if str(plot.crop) != "":
			return true
	return false


## 实际要扣的料（有替代料就用替代料，跟做菜的 alt 一个规矩）。
static func inputs(run: Dictionary, id: String) -> Dictionary:
	var c := chore(id)
	var need: Dictionary = c.get("cost", {}).duplicate()
	for orig in c.get("alt", {}):
		var sub: String = c.alt[orig]
		if Inv.count(run.home, orig) < int(need.get(orig, 0)) and Inv.count(run.home, sub) >= int(need.get(orig, 0)):
			need[sub] = need[orig]
			need.erase(orig)
	return need


# ---------- 排单 ----------

## 卯时排今天的单子。offers：今天做得成的既有行动（Post.agenda_offers 给）。
## 先放既有行动，再放"跟眼前处境挂钩"的差事（有 need 的：今夜有尸潮、门破了、天冷），
## 最后按权重抽日常差事，直到总时长够 TARGET。
static func build(run: Dictionary, offers: Array) -> void:
	var s := state(run)
	s.day = int(run.pday)
	var items := []
	var total := 0
	for key in BUILTIN:
		if key in offers:
			items.append({"id": key, "kind": "builtin", "done": false})
			total += int(BUILTIN[key].minutes)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("agenda:%d:%d" % [int(run.get("seed", 0)), int(run.pday)])
	var urgent := []
	var routine := []
	for id in Data.table("chores"):
		# 每条都抽一次，抽签次数不随资格变：同一种子同一天，单子只差在资格上
		var c := chore(str(id))
		var key := pow(rng.randf(), 1.0 / maxf(0.01, float(c.get("weight", 1))))
		if not eligible(run, str(id)):
			continue
		(urgent if c.has("need") else routine).append([key, str(id)])
	urgent.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	routine.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for pair in urgent + routine:
		if total >= TARGET:
			break
		items.append({"id": pair[1], "kind": "chore", "done": false})
		total += int(chore(pair[1]).minutes)
	s.items = items
	s.planned = total


## 这件差事今天上不上单（资源、天气、处境都对得上）。
static func eligible(run: Dictionary, id: String) -> bool:
	var c := chore(id)
	if c.is_empty():
		return false
	if cap(id) > 0 and used(run, id) >= cap(id):
		return false
	if not Inv.has_all(run.home, inputs(run, id)):
		return false
	if bool(c.get("well", false)) and Crisis.well_block(run) != "":
		return false
	if c.has("buff") and State.has_buff(run, str(c.buff)):
		return false
	var need: Dictionary = c.get("need", {})
	if need.has("cold") and cold(run) < int(need.cold):
		return false
	if bool(need.get("damaged", false)) and weakest(run) == "":
		return false
	if bool(need.get("wave", false)) and not wave_tonight(run):
		return false
	if bool(need.get("planted", false)) and not _planted(run):
		return false
	if bool(need.get("mates", false)) and run.get("companions", []).is_empty():
		return false
	if bool(need.get("hurt", false)) and State.attr(run, "hp") >= State.attr_max(run, "hp"):
		return false
	return true


# ---------- 进度 ----------

## 一行的状态：open 可做 / busy 正在做 / done 做过了 / late 过了时辰 / spent 用尽了
static func status(run: Dictionary, idx: int) -> String:
	var it := item(run, idx)
	if it.is_empty():
		return ""
	var id := str(it.id)
	var busy: Dictionary = run.get("busy", {})
	if str(it.kind) == "builtin":
		var sp: Dictionary = BUILTIN.get(id, {})
		var action := str(sp.get("action", id))
		var nth := int(sp.get("nth", 1))
		var times: int = run.get("today", {}).get("actions", []).count(action)
		if times >= nth:
			return "done"
		if str(busy.get("kind", "")) == action and times == nth - 1:
			return "busy"
	else:
		if bool(it.get("done", false)):
			return "done"
		if str(busy.get("kind", "")) == "chore" and int(busy.get("data", {}).get("idx", -1)) == idx:
			return "busy"
		if cap(id) > 0 and used(run, id) >= cap(id):
			return "spent"
	var deadline := int(spec(it).get("deadline", 0))
	if deadline > 0 and day_minute(run) > deadline:
		return "late"
	return "open"


## 还要多少分钟才能把单子上剩下的事做完（正在做的按剩余算）。
static func open_minutes(run: Dictionary) -> int:
	var need := 0
	var busy: Dictionary = run.get("busy", {})
	for idx in state(run).items.size():
		match status(run, idx):
			"open":
				need += int(spec(item(run, idx)).get("minutes", 0))
			"busy":
				need += maxi(0, int(busy.get("end", 0)) - int(run.get("t", 0)))
	return need


## HUD 和弹窗用的账：差事还剩多少、离收工还剩多少、得放下多少。
static func summary(run: Dictionary) -> Dictionary:
	var s := state(run)
	var done := 0
	var open := 0
	for idx in s.items.size():
		match status(run, idx):
			"done":
				done += 1
			"open", "busy":
				open += 1
	var need := open_minutes(run)
	var left := left_minutes(run)
	return {"need": need, "left": left, "over": maxi(0, need - left), "done": done, "open": open,
		"count": s.items.size(), "planned": int(s.get("planned", 0))}


# ---------- 做 ----------

## 这件差事现在做得了吗（只查差事自己的条件；忙不忙、精力够不够由 Post.can_act 管）。
## 既有行动只查状态，做不做得成交给各自的行动函数说。
static func block(run: Dictionary, idx: int) -> String:
	match status(run, idx):
		"":
			return "没有这件差事。"
		"done":
			return "今天做过了"
		"busy":
			return "正在做"
		"late":
			return "过了时辰"
		"spent":
			return "已经用尽了"
	var it := item(run, idx)
	if str(it.kind) == "builtin":
		return ""
	var id := str(it.id)
	var c := chore(id)
	var cost := inputs(run, id)
	if not Inv.has_all(run.home, cost):
		var lack := []
		for k in cost:
			if Inv.count(run.home, k) < int(cost[k]):
				lack.append(Data.item_name(k))
		return "缺" + "、".join(lack)
	if bool(c.get("well", false)) and Crisis.well_block(run) != "":
		return "井口冻住了"
	if c.has("buff") and State.has_buff(run, str(c.buff)):
		return "今天已有这份效用"
	var need: Dictionary = c.get("need", {})
	if bool(need.get("damaged", false)) and weakest(run) == "":
		return "门窗墙都完好"
	if bool(need.get("planted", false)) and not _planted(run):
		return "菜畦里没种东西"
	if bool(need.get("hurt", false)) and State.attr(run, "hp") >= State.attr_max(run, "hp"):
		return "气血是满的"
	# 尸潮夜 22:00、天亮 6:00 都会把手上的活打断（料白扣），做不完就别开工
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not bool(night.get("done", false)):
		return "尸潮还在街上"
	if wave_tonight(run) and day_minute(run) + int(c.minutes) > DAY_END:
		return "亥时尸潮前做不完"
	if day_minute(run) + int(c.minutes) > DAY:
		return "天亮前做不完"
	return ""


## 做完了，见成果。data 来自 run.busy.data：{idx, id, day}
static func complete(run: Dictionary, data: Dictionary) -> String:
	var id := str(data.get("id", ""))
	var c := chore(id)
	if c.is_empty():
		return ""
	var parts := []
	var gain: Dictionary = c.get("gain", {}).duplicate()
	if bool(c.get("well", false)):
		var blocked := Crisis.well_block(run)
		if blocked != "":
			_mark(run, data)
			State.note(run, blocked + "这一趟没挑上水。")
			return blocked
		# 跟打水同一个规矩：有水缸多存一瓢，井口结冰少一瓢
		if State.has_facility(run, "water_vat"):
			gain["water"] = int(gain.get("water", 0)) + 1
		if int(State.weather(run).get("cold", 0)) >= 25:
			gain["water"] = maxi(1, int(gain.get("water", 0)) - 1)
	if not gain.is_empty():
		Inv.add_all(run.home, gain)
		parts.append(Data.describe_items(gain))
	var attrs: Dictionary = c.get("attrs", {})
	for k in attrs:
		State.add_attr(run, str(k), float(attrs[k]))
		parts.append("%s %+d" % [State.ATTR_NAMES.get(k, k), int(attrs[k])])
	var xp: Dictionary = c.get("xp", {})
	for k in xp:
		State.add_xp(run, str(k), int(xp[k]))
		parts.append("%s熟练 +%d" % [State.PROF_NAMES.get(k, k), int(xp[k])])
	if int(c.get("merit", 0)) > 0:
		run.today["merit"] = int(run.today.get("merit", 0)) + int(c.merit)
		parts.append("功德 +%d" % int(c.merit))
	if int(c.get("shore", 0)) > 0:
		var sid := weakest(run)
		if sid != "":
			var part: Dictionary = Defense.part_of(run, sid)
			var before := int(part.cur)
			part.cur = mini(int(part.max), before + int(c.shore))
			parts.append("%s +%d" % [Defense.surface_name(sid), int(part.cur) - before])
	if float(c.get("grow", 0.0)) > 0.0:
		for plot in run.plots:
			if str(plot.crop) != "":
				plot.days = float(plot.days) + float(c.grow)
		parts.append("菜多长半日")
	if c.has("buff"):
		if not str(c.buff) in run.buffs:
			run.buffs.append(str(c.buff))
		parts.append(BUFF_TEXT.get(str(c.buff), str(c.buff)))
	_mark(run, data)
	if c.has("steps"):
		var n := used(run, id)
		if n == int(c.steps):
			parts.append(_finish(run, c.get("finish", {})))
		else:
			parts.append("进度 %d/%d" % [n, int(c.steps)])
	var text := "%s做完了%s。" % [c.name, ("：" + "，".join(parts)) if not parts.is_empty() else ""]
	State.note(run, text)
	return text


## 工程做完的那一回：落下永久的好处。返回给记录用的一句。
static func _finish(run: Dictionary, fx: Dictionary) -> String:
	if fx.has("flag"):
		run.flags[str(fx.flag)] = true
	var raise: Dictionary = fx.get("raise", {})
	for key in raise:
		var part: Dictionary = run[key]
		part.max = int(part.max) + int(raise[key])
		part.cur = int(part.cur) + int(raise[key])
	return "完工：" + finish_text(fx)


static func finish_text(fx: Dictionary) -> String:
	var parts := []
	if str(fx.get("flag", "")) == "kang":
		parts.append("往后睡着时体温少掉四成")
	var names := {"door": "门", "window": "窗", "wall": "院墙"}
	var raise: Dictionary = fx.get("raise", {})
	for key in raise:
		parts.append("%s上限 +%d" % [names.get(key, key), int(raise[key])])
	return "，".join(parts)


static func _mark(run: Dictionary, data: Dictionary) -> void:
	var s := state(run)
	var id := str(data.get("id", ""))
	s.used[id] = used(run, id) + 1
	var idx := int(data.get("idx", -1))
	if int(data.get("day", -1)) == int(s.day) and idx >= 0 and idx < s.items.size() and str(s.items[idx].id) == id:
		s.items[idx].done = true


# ---------- 给界面看的 ----------

## "1 小时 30 分"、"45 分"、"2 小时"
static func span_text(minutes: int) -> String:
	var m := maxi(0, minutes)
	if m < 60:
		return "%d 分" % m
	if m % 60 == 0:
		return "%d 小时" % (m / 60)
	return "%d 小时 %d 分" % [m / 60, m % 60]


## 账面上用的钟头数："24"、"15.5"
static func hours_text(minutes: int) -> String:
	var h := roundf(maxf(0.0, float(minutes)) / 30.0) / 2.0
	return ("%d" % int(h)) if h == floorf(h) else ("%.1f" % h)


## 这件差事换来什么（一行字）。既有行动换来什么写在 why 里。
static func effect_text(id: String) -> String:
	var c := chore(id)
	var parts := []
	for k in c.get("gain", {}):
		parts.append("%s +%d" % [Data.item_name(k), int(c.gain[k])])
	for k in c.get("attrs", {}):
		parts.append("%s %+d" % [State.ATTR_NAMES.get(k, k), int(c.attrs[k])])
	for k in c.get("xp", {}):
		parts.append("%s熟练 +%d" % [State.PROF_NAMES.get(k, k), int(c.xp[k])])
	if int(c.get("merit", 0)) > 0:
		parts.append("功德 +%d" % int(c.merit))
	if int(c.get("shore", 0)) > 0:
		parts.append("最破的一面 +%d" % int(c.shore))
	if float(c.get("grow", 0.0)) > 0.0:
		parts.append("菜多长半日")
	if c.has("buff"):
		parts.append(BUFF_TEXT.get(str(c.buff), str(c.buff)))
	if c.has("steps"):
		parts.append("%d 回完工后%s" % [int(c.steps), finish_text(c.get("finish", {}))])
	return "，".join(parts)


## 单子逐行：界面只管照着画。
static func rows(run: Dictionary) -> Array:
	var out := []
	for idx in state(run).items.size():
		var it := item(run, idx)
		var sp := spec(it)
		var builtin := str(it.kind) == "builtin"
		var cost := {} if builtin else inputs(run, str(it.id))
		var deadline := int(sp.get("deadline", 0))
		var c := (deadline + 360) % DAY
		out.append({
			"idx": idx, "id": str(it.id), "kind": str(it.kind), "name": str(sp.get("name", it.id)),
			"tag": str(sp.get("tag", "")), "spot": str(sp.get("spot", "")), "minutes": int(sp.get("minutes", 0)),
			"energy": int(sp.get("energy", 0)), "why": str(sp.get("why", "")),
			"effect": "" if builtin else effect_text(str(it.id)),
			"cost": Data.describe_items(cost) if not cost.is_empty() else "",
			"deadline": ("%02d:%02d 前动身" % [c / 60, c % 60]) if deadline > 0 else "",
			"progress": ("%d/%d" % [used(run, str(it.id)), cap(str(it.id))]) if not builtin and chore(str(it.id)).has("steps") else "",
			"status": status(run, idx), "block": block(run, idx),
		})
	return out
