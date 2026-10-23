extends RefCounted
## 功过格（日结算）、神龛求签、心愿、生死簿轮回。
## 对应原版 DailySettlement / RogueSelect（生存规划）/ Wish / RebirthChoice / SettleBeliefPoints。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")

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

## 一轮结束时得多少道心。死在第 N 日只算活过 N-1 日。
static func daoxin_gain(run: Dictionary, bonus := 0) -> Dictionary:
	var days := int(run.pday)
	if run.phase == "dead":
		days = maxi(0, days - 1)
	var lines := [["活过 %d 日" % days, days], ["守住 %d 次尸潮" % run.waves_survived, int(run.waves_survived) * 2]]
	if not run.clues_new.is_empty():
		lines.append(["新得残卷 %d 篇" % run.clues_new.size(), run.clues_new.size() * 5])
	if bonus > 0:
		lines.append(["劫满", bonus])
	# 了愿：挑了的都列出来，达成的给分、没达成的标"未成"给 0——
	# 不达成就悄无声息地少了 20 道心，玩家会以为出了 bug
	for g in goal_results(run):
		lines.append([("了愿·" + str(g.name)) if bool(g.met) else ("了愿·%s（未成）" % str(g.name)), int(g.bonus)])
	var total := 0
	for l in lines:
		total += int(l[1])
	return {"lines": lines, "total": total, "days": days}


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


static func end_run(run: Dictionary, meta: Dictionary, bonus := 0) -> Dictionary:
	var gain := daoxin_gain(run, bonus)
	merge_memory(run, meta)
	meta.daoxin = int(meta.daoxin) + int(gain.total)
	meta.runs = int(meta.runs) + 1
	meta.best_day = maxi(int(meta.best_day), int(gain.days))
	if run.phase == "dead":
		meta.deaths = int(meta.deaths) + 1
	return gain


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
