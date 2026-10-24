extends RefCounted
## 功过格（日结算）、神龛求签、心愿、生死簿轮回。
## 对应原版 DailySettlement / RogueSelect（生存规划）/ Wish / RebirthChoice / SettleBeliefPoints。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Companion = preload("res://scripts/core/companion.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Mainline = preload("res://scripts/core/mainline.gd")

const OMEN_SLOTS := 3
const REROLL_COST := 1
const SNAPSHOT_KEEP := 6


# ---------- 求签 ----------

static func draw_omens(run: Dictionary) -> void:
	var offer := []
	if run.omens.locked != "":
		offer.append(run.omens.locked)
	var pool := Rng.shuffled(run, Data.table("omens").keys())
	for id in pool:
		if offer.size() >= OMEN_SLOTS:
			break
		if not id in offer:
			offer.append(id)
	run.omens.offer = offer
	run.omens.taken = []


static func reroll_omens(run: Dictionary) -> String:
	if int(run.merit) < REROLL_COST:
		return "功德不够，摇不动签筒。"
	run.merit -= REROLL_COST
	draw_omens(run)
	return ""


static func toggle_lock(run: Dictionary, id: String) -> void:
	run.omens.locked = "" if run.omens.locked == id else id


## 一天之内求得越多越贵：第二支 +1，第三支 +2（功德不再溢出发霉）。
static func omen_cost(run: Dictionary, id: String) -> int:
	return int(Data.table("omens")[id].cost) + run.omens.taken.size()


static func take_omen(run: Dictionary, id: String) -> String:
	if not id in run.omens.offer or id in run.omens.taken:
		return "这支签已经用过了。"
	var o: Dictionary = Data.table("omens")[id]
	var cost := omen_cost(run, id)
	if int(run.merit) < cost:
		return "功德不够。"
	run.merit -= cost
	run.omens.taken.append(id)
	if run.omens.locked == id:
		run.omens.locked = ""
	var fx: Dictionary = o.effect
	if fx.has("grow"):
		State.grow_crops(run, int(fx.grow))
	if fx.has("door"):
		run.door.cur = mini(int(run.door.max), int(run.door.cur) + int(fx.door))
	if fx.has("window"):
		run.window.cur = mini(int(run.window.max), int(run.window.cur) + int(fx.window))
	for k in ["hp", "mood", "energy"]:
		if fx.has(k):
			State.add_attr(run, k, fx[k])
	if fx.has("cure"):
		run.plague = false
	if fx.has("items"):
		Inv.add_all(run.home, fx.items)
	if fx.has("buff") and not fx.buff in run.buffs:
		run.buffs.append(fx.buff)
	State.note(run, "求得%s·%s：%s" % [o.tier, o.name, o.verse])
	return ""


# ---------- 心愿 ----------

static func pick_wish(run: Dictionary) -> void:
	var id = Rng.pick(run, Data.table("wishes").keys())
	run.wish = {"id": id, "done": false}


static func check_wish(run: Dictionary, kind: String, target: String) -> void:
	if run.wish.is_empty() or run.wish.done:
		return
	var w: Dictionary = Data.table("wishes")[run.wish.id]
	if w.type == kind and w.target == target:
		run.wish.done = true
		State.add_attr(run, "mood", 6)
		State.note(run, "心愿了却：%s" % w.text)


# ---------- 功过格 ----------

static func settle(run: Dictionary) -> Dictionary:
	var lines := []
	lines.append(["活过今日", 5])
	var mood_part := maxi(0, State.attr(run, "mood") - 50) / 10
	if mood_part > 0:
		lines.append(["心神安定（心神 %d）" % State.attr(run, "mood"), mood_part])
	if not run.wish.is_empty() and run.wish.done:
		lines.append(["了却心愿", 2])
	var kills := int(run.today.get("kills", 0))
	if kills >= 5:
		lines.append(["斩尸 %d 只" % kills, kills / 5])
	var ev := int(run.today.get("merit", 0))
	if ev > 0:
		lines.append(["行善积德", ev])
	if State.has_talent(run, "jishan"):
		lines.append(["积善之家", 2])
	if int(run.merit) > 0:
		lines.append(["功德生息", clampi(int(run.merit * 0.05), 1, 10)])
	var total := 0
	for l in lines:
		total += int(l[1])
	run.merit += total
	return {"lines": lines, "total": total, "merit": run.merit}


# ---------- 道心与轮回 ----------

## 劫满（熬过第二十夜）额外加多少道心。
## 放在这里而不是界面里：结算逻辑和测试工具都得看到它，
## 否则「赢一局」和「输一局」的道心差会被少算 10 点（之前就少算了，见 docs/09 第 16 节）。
const ENDING_BONUS := 10

## Leaving early is a completed story, but is not surviving the twentieth night.
static func ending_bonus(run: Dictionary) -> int:
	if run.is_empty() or run.get("phase", "") != "ending" or int(run.get("pday", 0)) < State.STORY_DAYS: return 0
	var ending := Mainline.ending(run)
	return ENDING_BONUS if ending.get("kind", "") in ["hold", "ritual"] else 0


## 一轮结束时得多少道心。死在第 N 日只算活过 N-1 日。
static func daoxin_gain(run: Dictionary, bonus := 0) -> Dictionary:
	if run.is_empty(): return {"lines": [], "total": 0, "days": 0}
	bonus = mini(maxi(0, int(bonus)), ending_bonus(run))
	var days := int(run.pday)
	if run.phase == "dead":
		days = maxi(0, days - 1)
	var lines := [["活过 %d 日" % days, days], ["守住 %d 次尸潮" % run.waves_survived, int(run.waves_survived) * 2]]
	if not run.clues_new.is_empty():
		lines.append(["新得残卷 %d 篇" % run.clues_new.size(), run.clues_new.size() * 5])
	if bonus > 0:
		lines.append(["劫满", bonus])
	# 挑战倍率先乘在这一局的表现上（誓约抬、凭仗压），了愿是固定加分、不参与乘法
	var base := 0
	for l in lines:
		base += int(l[1])
	var mul := challenge_mul(run)
	var total := int(round(base * mul))
	if not is_equal_approx(mul, 1.0):
		lines.append(["挑战 ×%.2f" % mul, total - base])
	# 破了誓约要说一声：倍率里少了它，但不写出来玩家会以为是算错了
	for v in vow_results(run):
		if not bool(v.met):
			lines.append(["誓约·%s（已破，不算倍数）" % str(v.name), 0])
	# 了愿：挑了的都列出来，达成的给分、没达成的标"未成"给 0——
	# 不达成就悄无声息地少了 20 道心，玩家会以为出了 bug
	for g in goal_results(run):
		lines.append([("了愿·" + str(g.name)) if bool(g.met) else ("了愿·%s（未成）" % str(g.name)), int(g.bonus)])
		total += int(g.bonus)
	return {"lines": lines, "total": total, "days": days}


## 挑战倍率：誓约抬、凭仗压，夹在 0.5–1.5。
## 上下限是为了两头都不失控——三个誓约叠满不能变 3 倍，三个凭仗叠满也不该只剩三成。
## 誓约是"到结算那一刻还没破"才算数：中途破了就静默作废（不提示、不清零），
## 因为当场清零惩罚太重，玩家会直接弃局。
static func challenge_mul(run: Dictionary) -> float:
	var m := 1.0
	for v in Data.table("challenge").get("vows", []):
		if str(v.get("id", "")) in State.tally(run).get("vows", []) and vow_met(run, v):
			m += float(v.get("mul", 1.0)) - 1.0
	m -= State.boon_malus(run)
	# 同院的人：开局多帮手，道心打折（一人 −5%，见 companion.MATE_MALUS 的实测依据）
	m -= Companion.MATE_MALUS * float(run.get("companions", []).size())
	return clampf(m, 0.5, 1.5)


## 这条誓约到结算时破了没有。条件写在 data/challenge.json 的 check 字段里：
##   bought_none     一样东西整局没买过（看 tally.bought）
##   furniture_none  院里没摆这件家具
##   counter_zero    某个计数器还是 0（repair_door）
##   counter_max     某个计数器没超过上限（home_trips ≤ max）
##   always          开局一瞬就生效，没有可破的（空手）
static func vow_met(run: Dictionary, vow: Dictionary) -> bool:
	var t: Dictionary = State.tally(run)
	match str(vow.get("check", "")):
		"bought_none":
			return int(t.get("bought", {}).get(str(vow.get("item", "")), 0)) <= 0
		"bought_none_cat":
			# 整类都不许买（守具、药……）。bought 里只记真买过的，没买过就是没破。
			var cat := str(vow.get("cat", ""))
			for id in t.get("bought", {}):
				if int(t.bought[id]) > 0 and str(Data.item(id).get("cat", "")) == cat:
					return false
			return true
		"furniture_none":
			for f in run.get("furniture", []):
				if str(f.get("id", "")) == str(vow.get("furniture", "")):
					return false
			return true
		"counter_zero":
			return int(t.get(str(vow.get("counter", "")), 0)) <= 0
		"counter_max":
			return int(t.get(str(vow.get("counter", "")), 0)) <= int(vow.get("max", 0))
		_:
			return true


## 挑了的誓约，各自破没破。给结算界面用。
static func vow_results(run: Dictionary) -> Array:
	var picked: Array = State.tally(run).get("vows", [])
	var out := []
	if picked.is_empty():
		return out
	for v in Data.table("challenge").get("vows", []):
		var id := str(v.get("id", ""))
		if not id in picked:
			continue
		out.append({"id": id, "name": str(v.get("name", id)), "met": vow_met(run, v),
			"mul": float(v.get("mul", 1.0))})
	return out


## 这一局挑了的愿，各自达成没有。返回 [{id, name, met, bonus}]。
## 条件全写在 data/challenge.json 里：stat 取 run 上的字段，at_least 是门槛；
## 带 phase 的还要求局面停在那个阶段（比如"活到终局"必须 phase == ending，病死在第 20 日不算）。
static func goal_results(run: Dictionary) -> Array:
	var picked: Array = State.goals_of(run)
	var out := []
	if picked.is_empty():
		return out
	for g in Data.table("challenge").get("goals", []):
		var id := str(g.get("id", ""))
		if not id in picked:
			continue
		var met := true
		if g.has("phase") and str(run.get("phase", "")) != str(g.phase):
			met = false
		if g.get("phase", "") == "ending" and ending_bonus(run) == 0:
			met = false
		if met and float(run.get(g.get("stat", ""), 0.0)) < float(g.get("at_least", 0.0)):
			met = false
		out.append({"id": id, "name": str(g.get("name", id)), "met": met,
			"bonus": int(g.get("bonus", 0)) if met else 0})
	return out


## 把这一轮学到的东西记进 meta（残卷是记忆，翻回去也不会忘）。
static func merge_memory(run: Dictionary, meta: Dictionary) -> void:
	for c in run.clues_new:
		if not c in meta.clues:
			meta.clues.append(c)


static func end_run(run: Dictionary, meta: Dictionary, bonus := -1) -> Dictionary:
	if run.is_empty(): return {"lines": [], "total": 0, "days": 0, "settled": false}
	var gain := daoxin_gain(run, ending_bonus(run) if bonus < 0 else bonus)
	# The archive's stable life identity also fences every other settlement effect.
	# A rewind or a duplicate UI callback must not award currency/daily scores again.
	if not Past.archive(run, meta): return {"lines": [], "total": 0, "days": gain.days, "settled": false}
	merge_memory(run, meta)
	record_daily(run, meta, int(gain.total))
	meta.daoxin = int(meta.daoxin) + int(gain.total)
	meta.runs = int(meta.runs) + 1
	meta.best_day = maxi(int(meta.best_day), int(gain.days))
	if run.phase == "dead":
		meta.deaths = int(meta.deaths) + 1
	gain["settled"] = true
	return gain


## 每日一局记一次分。只有每日局（run.flags.daily 写着开局那天的日期）才记——
## 寻常随机局能无限重开，让它们进榜会把"今日最好"顶成一条刷出来的数。
## 记的是**开局那天**的成绩，不是结算这天：跨零点打完的局归它自己那副牌。
## 分两组记：守到死拿不到劫满那 10 点也没有终局，和寻常局放一起比不公平。
static func record_daily(run: Dictionary, meta: Dictionary, total: int) -> void:
	var day := str(run.get("flags", {}).get("daily", ""))
	if day == "":
		return
	if not meta.has("daily") or typeof(meta.get("daily")) != TYPE_DICTIONARY:
		meta.daily = State.new_daily()
	var d: Dictionary = meta.daily
	if str(d.get("day", "")) != day:
		# 换了一天：当日这一栏从头算，历来最好留着
		d.day = day
		d.runs = 0
		d.best = {}
	d.runs = int(d.get("runs", 0)) + 1
	var key := "endless" if bool(run.get("endless", false)) else "normal"
	var best: Dictionary = d.get("best", {})
	var all: Dictionary = d.get("all", {})
	if total > int(best.get(key, -1)):
		best[key] = total
	if total > int(all.get(key, -1)):
		all[key] = total
	d.best = best
	d.all = all


## 记分板的一行字。day 传要看的那天；endless 决定看哪一组（寻常 / 守到死）。
## pending >= 0：按"这一局已经记进去"算——结局界面上这一局还没落盘，得先预览出来。
static func daily_line(meta: Dictionary, day: String, endless: bool, pending := -1) -> String:
	var d: Dictionary = meta.get("daily", {})
	var key := "endless" if endless else "normal"
	var all: Dictionary = d.get("all", {})
	var ever := int(all.get(key, 0))
	var head := ""
	if pending >= 0:
		head = "这一局 %d 点 · " % pending
		ever = maxi(ever, pending)
	var tail := "历来最好 %d" % ever if ever > 0 else "历来还没打过"
	var today: bool = day != "" and str(d.get("day", "")) == day
	if not today and pending < 0:
		return tail
	# 跨天打完的局归它自己那天（record_daily 用开局日期），所以不是今天就从零起算
	var runs := int(d.get("runs", 0)) if today else 0
	var bestv := int(d.get("best", {}).get(key, 0)) if today else 0
	if pending >= 0:
		runs += 1
		bestv = maxi(bestv, pending)
	return "%s今日第 %d 局 · 今日最好 %d · %s" % [head, runs, bestv, tail]


static func snapshot(run: Dictionary, snapshots: Dictionary) -> void:
	snapshots[str(run.pday)] = run.duplicate(true)
	var days := snapshots.keys()
	days.sort_custom(func(a, b): return int(a) < int(b))
	while days.size() > SNAPSHOT_KEEP:
		snapshots.erase(days.pop_front())


## 翻回昨日那一页：恢复昨晨的快照，折寿元（气血上限 -10），残页 -1。
## 返回新的 run；不能翻时返回空字典。
static func rewind(run: Dictionary, snapshots: Dictionary, meta: Dictionary) -> Dictionary:
	if int(run.rebirths_left) <= 0:
		return {}
	var target := str(int(run.pday) - 1)
	if not snapshots.has(target):
		target = str(run.pday)
	if not snapshots.has(target):
		return {}
	merge_memory(run, meta)
	meta.deaths = int(meta.deaths) + 1
	var restored: Dictionary = snapshots[target].duplicate(true)
	restored.rebirths_left = int(run.rebirths_left) - 1
	restored.known_clues = run.known_clues.duplicate()
	restored.clues_new = run.clues_new.duplicate()
	restored.attrs.hp_max = maxi(50, int(run.attrs.hp_max) - 10)
	restored.attrs.hp = mini(int(restored.attrs.hp), int(restored.attrs.hp_max))
	restored.log = run.log.duplicate()
	for key in snapshots.keys():
		if int(key) > int(target):
			snapshots.erase(key)
	State.note(restored, "生死簿残页翻回了这一页。寿元折损，气血上限降为 %d。" % restored.attrs.hp_max)
	return restored
