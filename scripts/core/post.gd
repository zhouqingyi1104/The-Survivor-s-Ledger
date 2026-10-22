extends RefCounted
## 劫中：连续时间。对应原版 GameTimeManager（时钟 + 倍速）。
##
## run.t 是从尸劫后第一天卯时（6:00）算起的游戏分钟数。一天从 6:00 到次日 6:00：
##   8:00 可能来事件；18:00 天黑；20:00 烧炭取暖；21:00 外出的要回家；22:00 尸潮；23:00 溃兵；6:00 天亮结算功过格。
## 做事要花时间（run.busy），期间时间照走、属性照掉；做完才见成果。睡觉一直睡到天亮（尸潮会把人吵醒）。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Events = preload("res://scripts/core/events.gd")
const Explore = preload("res://scripts/core/explore.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
const Home = preload("res://scripts/core/home.gd")

const DAY := 1440
const DAWN := 360           # 6:00，一天的开始
const TICK := 10            # 结算粒度（分钟）
# 以下都是"当天第几分钟"（从 6:00 起算）
const EVENT_AT := 120       # 8:00
const DUSK_AT := 720        # 18:00
const HEAT_AT := 840        # 20:00
const CURFEW_AT := 900      # 21:00
const WAVE_AT := 960        # 22:00
const RAID_AT := 1060       # 23:40（原本 23:00，让位给第三轮夜战）

## 每小时的变化
const RATE := {
	"food": 2.0, "water": 2.2, "mood": 0.5, "energy": 1.2,
	"sleep_energy": 7.0, "nap_energy": 10.0, "sleep_hp": 0.8, "warm_up": 2.0,
	"starve_hp": 2.0, "thirst_hp": 2.5, "plague_hp": 1.0, "cold_hp": 0.7, "freezing_hp": 1.4,
	"overrun_hp": 3.0,
}

## 行动：[名称, 分钟, 精力消耗]
const ACTIONS := {
	"cook": ["做饭", 60, 6], "garden": ["打理菜畦", 45, 8], "build": ["营造", 90, 10], "repair": ["修缮", 60, 8],
	"read": ["读书", 120, 4], "craft": ["画符", 60, 6], "rest": ["小憩", 120, 0], "water": ["打水", 15, 2],
	"travel": ["赶路", 60, 8], "search": ["翻找", 20, 4],
	"mend": ["夜修", 25, 4], "ward": ["布守具", 20, 6],
}


# ---------- 时间 ----------

## 当天第几分钟（0 = 6:00）。
static func day_minute(run: Dictionary) -> int:
	return int(run.t) - (int(run.pday) - 1) * DAY


## 钟面上的时刻（0..1439，0 = 子夜）。
static func clock(run: Dictionary) -> int:
	return (int(run.t) + DAWN) % DAY


static func clock_text(run: Dictionary) -> String:
	var c := clock(run)
	return "%02d:%02d" % [c / 60, c % 60]


## 时辰名：子时 23:00-1:00 ……
static func shichen(run: Dictionary) -> String:
	var h := (clock(run) / 60 + 1) % 24
	return State.HOURS[h / 2] + "时"


static func is_night(run: Dictionary) -> bool:
	return day_minute(run) >= DUSK_AT


static func is_busy(run: Dictionary) -> bool:
	return not run.busy.is_empty()


## 有没有卡住时间的事（事件、布防、尸潮、天亮结算、战报没看完）。
## 注意：夜战进行中**不**卡时间——轮与轮之间要给玩家做事。
static func blocked(run: Dictionary) -> bool:
	return run.phase != "post" or run.pending_event != "" or run.plan_due or run.wave_due or run.dawn_due or not run.wave_report.is_empty()


## 今天要停下的时刻（含夜战的每轮结算点）。
static func checkpoints(run: Dictionary) -> Array:
	var out := [EVENT_AT, DUSK_AT, HEAT_AT, CURFEW_AT, WAVE_AT, RAID_AT, DAY]
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and not bool(night.get("done", false)):
		out.append(Defense.round_minute(int(night.round)))
	return out


## 夜战是否正在进行。
static func in_night(run: Dictionary) -> bool:
	var n: Dictionary = run.get("night", {})
	return not n.is_empty() and not bool(n.get("done", false))


## 往前走 minutes 分钟。遇到要玩家处理的事就停下，返回原因：
## "" / "event" / "wave" / "wave_round" / "dawn" / "curfew" / "plan" / "raid" / "dead" / "blocked"
static func advance(run: Dictionary, minutes: int) -> String:
	var left := minutes
	while left > 0:
		if run.phase != "post":
			return "dead"
		if blocked(run):
			return "blocked"
		var m := day_minute(run)
		var step := mini(TICK, left)
		for cp in checkpoints(run):
			if m < cp and m + step > cp:
				step = cp - m
		_tick(run, step / 60.0)
		run.t = int(run.t) + step
		left -= step
		if State.check_death(run, _death_cause(run)):
			return "dead"
		_check_busy(run)
		var stop := _checkpoint(run, m + step)
		if stop != "":
			return stop
	return ""


static func _tick(run: Dictionary, hours: float) -> void:
	var sleeping: bool = run.sleeping
	var resting: bool = run.busy.get("kind", "") == "rest"
	var mul := 0.6 if sleeping else 1.0
	State.add_attr(run, "food", -RATE.food * mul * hours * (0.75 if State.has_talent(run, "bigu") else 1.0))
	State.add_attr(run, "water", -RATE.water * mul * hours)
	State.add_attr(run, "mood", (0.3 if sleeping else -RATE.mood) * hours)
	var warm: int = State.attr(run, "warmth")
	if sleeping:
		# 冻着睡不踏实：回暖少，气血也不长
		State.add_attr(run, "energy", RATE.sleep_energy * hours * (1.0 if warm >= 30 else 0.6))
		if State.attr(run, "food") > 20 and State.attr(run, "water") > 20 and warm >= 30:
			State.add_attr(run, "hp", RATE.sleep_hp * hours)
	elif resting:
		State.add_attr(run, "energy", RATE.nap_energy * hours)
	else:
		State.add_attr(run, "energy", -RATE.energy * hours)
	# 体温：白天靠日头回暖（最多到 60，地窖 75）；夜里只有生火才暖得起来
	var cold := int(State.weather(run).cold)
	if is_night(run) and cold > 0 and not run.heated:
		var loss := cold / 10.0 * (0.5 if State.has_facility(run, "cellar") else 1.0)
		State.add_attr(run, "warmth", -loss * hours)
	else:
		var gain := RATE.warm_up
		var cap := 60.0 if not State.has_facility(run, "cellar") else 75.0
		if run.heated:
			if bool(run.get("heat_weak", false)):
				gain = RATE.warm_up * 0.5   # 一捆柴只烧半夜
				cap = 70.0
			else:
				cap = 100.0
		run.attrs.warmth = clampf(float(run.attrs.warmth) + gain * hours, 0.0, cap)
	if State.attr(run, "food") <= 0:
		State.add_attr(run, "hp", -RATE.starve_hp * hours)
		State.add_attr(run, "mood", -1.2 * hours)
	if State.attr(run, "water") <= 0:
		State.add_attr(run, "hp", -RATE.thirst_hp * hours)
	if run.plague:
		State.add_attr(run, "hp", -RATE.plague_hp * hours)
	if State.attr(run, "warmth") < 15:
		State.add_attr(run, "hp", -RATE.freezing_hp * hours)
		State.add_attr(run, "mood", -0.8 * hours)
	elif State.attr(run, "warmth") < 30:
		State.add_attr(run, "hp", -RATE.cold_hp * hours)
		State.add_attr(run, "mood", -0.5 * hours)
	# 三面都被撞破：院子里的东西挡不住了，一直有人扑上来
	if in_night(run) and Defense.all_broken(run):
		State.add_attr(run, "hp", -RATE.overrun_hp * hours)
		State.add_attr(run, "mood", -1.0 * hours)
	# 作物：一天之内浇过水才长
	for plot in run.plots:
		if plot.crop != "" and int(run.t) - int(plot.watered_t) <= DAY:
			plot.days = float(plot.days) + hours / 24.0


static func _death_cause(run: Dictionary) -> String:
	if State.attr(run, "water") <= 0:
		return "渴死在第 %d 日。" % run.pday
	if State.attr(run, "food") <= 0:
		return "饿死在第 %d 日。" % run.pday
	if run.plague:
		return "尸瘟入骨，死在第 %d 日。" % run.pday
	if State.attr(run, "warmth") < 30:
		return "冻死在第 %d 日的夜里。" % run.pday
	return "力竭而亡。"


static func _checkpoint(run: Dictionary, m: int) -> String:
	# 夜战：到点结算下一轮
	if in_night(run) and m == Defense.round_minute(int(run.night.round)):
		return "wave_round"
	match m:
		EVENT_AT:
			run.pending_event = Events.roll(run)
			if run.pending_event != "":
				return "event"
		DUSK_AT:
			State.note(run, "天黑了。")
		HEAT_AT:
			_heat(run)
		CURFEW_AT:
			if not run.explore.is_empty():
				return "curfew"
			# 今夜有尸潮：先让玩家定守夜方针，再放时间走
			if not Defense.wave_for_day(run.pday).is_empty() and int(run.wave_day) != int(run.pday) and str(run.get("night_policy", "")) == "":
				run.plan_due = true
				run.sleeping = false
				return "plan"
		WAVE_AT:
			if not Defense.wave_for_day(run.pday).is_empty() and int(run.wave_day) != int(run.pday):
				run.wave_due = true
				run.sleeping = false
				run.busy = {}
				return "wave"
		RAID_AT:
			# 尸潮还在街上，溃兵不会这时候来
			if run.raid_tonight and not in_night(run):
				run.sleeping = false
				run.raid_report = Defense.resolve_raid(run)
				run.raid_tonight = false
				return "raid"
		DAY:
			if in_night(run):
				_close_night(run)
			_dawn(run)
			return "dawn"
	return ""


## 20:00 烧炭取暖：一筐炭，或两捆柴，管一夜；只有一捆柴也能烧半夜。
static func _heat(run: Dictionary) -> void:
	if int(State.weather(run).cold) <= 0:
		return
	var fuel := {}
	var weak := false
	if Inv.count(run.home, "charcoal") > 0:
		fuel = {"charcoal": 1}
	elif Inv.count(run.home, "firewood") >= 2:
		fuel = {"firewood": 2}
	elif Inv.count(run.home, "firewood") == 1:
		fuel = {"firewood": 1}
		weak = true
	if fuel.is_empty():
		run.night_lines.append("没柴没炭，屋里冷得像冰窖。")
		State.note(run, "没柴没炭，夜里冷得睡不着。")
		return
	Inv.take_all(run.home, fuel)
	run.heated = true
	run.heat_weak = weak
	run.night_lines.append("烧了%s取暖。%s" % [Data.describe_items(fuel), "柴少，火到后半夜就弱了。" if weak else ""])
	State.note(run, "生起火盆，烧了%s。%s" % [Data.describe_items(fuel), "柴不够，只能烧半夜。" if weak else ""])


## 6:00 天亮：结算功过格，等玩家翻页（ack_dawn）再开新的一天。
static func _dawn(run: Dictionary) -> void:
	run.sleeping = false
	run.busy = {}
	run.dawn_due = true
	run.report = {"day": run.pday, "night": run.night_lines.duplicate(), "settle": Ledger.settle(run)}


static func ack_dawn(run: Dictionary) -> void:
	if not run.dawn_due:
		return
	run.dawn_due = false
	run.report = {}
	if int(run.pday) >= State.STORY_DAYS and not run.endless:
		run.phase = "ending"
		State.note(run, "天亮了。第二十一日的太阳照进院子——劫，满了。")
		return
	begin_day(run)


## 22:00 尸潮：开夜，先把第一轮算出来给演出用。后两轮在夜战里逐轮结算。
static func resolve_wave(run: Dictionary) -> Dictionary:
	if not run.wave_due:
		return {}
	run.wave_due = false
	run.wave_day = run.pday
	var wave := Defense.wave_for_day(int(run.pday))
	Defense.start_night(run, wave)
	var rep := Defense.next_round(run)
	if run.phase == "post":
		State.add_attr(run, "energy", -8)
		State.add_attr(run, "mood", -2)
	run.night_lines.append("第一轮：斩 %d 只。" % int(rep.get("killed", 0)))
	if int(rep.get("live_gate", 0)) > 0:
		start_fight(run, int(rep.live_gate), "armored" in wave.get("mods", []))
	_open_gap(run)
	return rep


## 夜战里到了下一轮：结算，返回这一轮的战报。
static func nod_round(run: Dictionary) -> Dictionary:
	if not in_night(run):
		return {}
	var rep := Defense.next_round(run)
	if int(rep.get("live_gate", 0)) > 0:
		start_fight(run, int(rep.live_gate), "armored" in run.night.wave.get("mods", []))
	_open_gap(run)
	return rep


## 一轮打完，给玩家一个间隙：按方针自动做一件事（手动方针就留给他自己）。
static func _open_gap(run: Dictionary) -> void:
	if run.night.is_empty():
		return
	if bool(run.night.get("done", false)):
		_close_night(run)
		return
	run.night.acted = false
	apply_policy(run)


## 收夜：汇总战报，交给界面弹窗。
static func _close_night(run: Dictionary) -> void:
	var rep := Defense.finish_night(run)
	if rep.is_empty():
		return
	rep["day"] = run.pday
	run.wave_report = rep
	if run.phase == "post":
		State.add_attr(run, "mood", -2)


static func ack_wave(run: Dictionary) -> void:
	run.wave_report = {}


# ---------- 守夜方针 ----------

## 21:00 选方针。选完时间才继续走。
static func choose_policy(run: Dictionary, id: String) -> String:
	if not run.plan_due:
		return "现在不用定方针。"
	var p: Dictionary = Data.table("waves").policies.get(id, {})
	if p.is_empty():
		return "没有这个方针。"
	run.night_policy = id
	run.guard_spot = _spot_for(run, str(p.get("spot", "gate")))
	run.plan_due = false
	State.note(run, "今夜方针：%s。亲守%s。" % [p.name, Defense.surface_name(run.guard_spot)])
	return ""


## 方针里的「亲守哪一面」：gate 固定守门，weak 选今夜最吃紧的一面。
static func _spot_for(run: Dictionary, mode: String) -> String:
	if mode == "gate":
		return "gate"
	var wave := Defense.wave_for_day(int(run.pday))
	var best := "gate"
	var worst := -999.0
	for sid in Defense.SURFACES:
		var pv := Defense.preview_night(run, wave)
		var s: Dictionary = pv.get(sid, {})
		var deficit := float(s.get("count", 0)) * Defense._cost(wave) - float(s.get("power", 0))
		if deficit > worst:
			worst = deficit
			best = sid
	return best


## 21:00 弹窗用的四档：[id, 名称, 说明, 亲守面, 今夜预计漏几只]
static func policy_options(run: Dictionary) -> Array:
	var wave := Defense.wave_for_day(int(run.pday))
	var out := []
	for id in Data.table("waves").policies:
		var p: Dictionary = Data.table("waves").policies[id]
		var spot := _spot_for(run, str(p.get("spot", "gate")))
		var saved: String = str(run.guard_spot)
		run.guard_spot = spot
		var pv := Defense.preview_night(run, wave)
		run.guard_spot = saved
		var leak := 0
		for sid in Defense.SURFACES:
			var s: Dictionary = pv.get(sid, {})
			leak += maxi(0, int(s.get("count", 0)) - int(floor(float(s.get("power", 0)) / Defense._cost(wave))) * Defense.rounds())
		out.append([id, p.name, p.desc, spot, leak])
	return out


## 按方针替玩家做这一轮间隙该做的事（手动方针什么都不做）。
static func apply_policy(run: Dictionary) -> void:
	if not in_night(run) or bool(run.night.get("acted", false)):
		return
	var policy: String = str(run.get("night_policy", "manual"))
	if policy == "manual" or policy == "":
		return
	match policy:
		"hold":
			_auto_mend(run, false)
		"fight":
			_auto_sortie(run)
	run.night.acted = true


## 修最破的一面（need_bad 时只修快破的那面）。
static func _auto_mend(run: Dictionary, need_bad: bool) -> bool:
	var target := ""
	var worst := 1.0
	for sid in Defense.SURFACES:
		if Defense.mend_block(run, sid) != "":
			continue
		var part := Defense.part_of(run, sid)
		var ratio := float(part.cur) / float(part.max)
		if ratio < worst:
			worst = ratio
			target = sid
	if target == "":
		return false
	if need_bad and worst > 0.45:
		return false
	return _mend_on(run, target)


static func _mend_on(run: Dictionary, sid: String) -> bool:
	if Defense.mend_block(run, sid) != "":
		return false
	Defense.pay_mend(run)
	_tend_surface(run, sid)
	return true


static func _tend_surface(run: Dictionary, sid: String) -> void:
	var part := Defense.part_of(run, sid)
	part.cur = mini(int(part.max), int(part.cur) + Defense.mend_amount(run))
	State.note(run, "借着间隙把%s补了补，耐久 +%d。" % [Defense.surface_name(sid), Defense.mend_amount(run)])


static func _auto_sortie(run: Dictionary) -> bool:
	var wave: Dictionary = run.night.wave
	var pv := Defense.preview_round(run, wave, int(run.night.round))
	# 只去真的会漏的那一面砍；都挡得住就别白挨咬
	var target := ""
	var most := 0
	for sid in Defense.SURFACES:
		var left := int(pv.surfaces.get(sid, {}).get("left", 0))
		if left > most:
			most = left
			target = sid
	if target == "":
		return _auto_mend(run, false)
	if State.attr(run, "hp") < 50:
		return false
	Defense.sortie(run, target)
	return true


# ---------- 夜里玩家自己动手 ----------

## 夜战间隙能不能做事（一轮只给一次机会）。
static func night_block(run: Dictionary, energy_needed := 3) -> String:
	if not in_night(run):
		return "现在不是守夜的时候。"
	if run.phase != "post":
		return "现在不能做这个。"
	if is_busy(run):
		return "正在%s。" % run.busy.label
	if bool(run.night.get("acted", false)):
		return "这一轮间隙已经忙过了。"
	if State.attr(run, "energy") < energy_needed:
		return "精力不济。"
	return ""


static func night_mend(run: Dictionary, sid: String) -> String:
	var err := night_block(run, 4)
	if err != "":
		return err
	err = Defense.mend_block(run, sid)
	if err != "":
		return err
	Defense.pay_mend(run)
	run.night.acted = true
	_start(run, "mend", {"surface": sid})
	return ""


static func night_build(run: Dictionary, did: String) -> String:
	var err := night_block(run, 6)
	if err != "":
		return err
	err = device_block(run, did)
	if err != "":
		return err
	var d: Dictionary = Data.table("devices").devices[did]
	Inv.take_all(run.home, d.cost)
	run.night.acted = true
	_start(run, "ward", {"device": did})
	return ""


## 贴符不占时间，但一样算这一轮的动作。
static func night_charm(run: Dictionary, sid: String, id: String) -> String:
	var err := night_block(run, 0)
	if err != "":
		return err
	err = Defense.add_charm(run, sid, id)
	if err == "":
		run.night.acted = true
	return err


## 开关院门。开门才出得去、也才挡不住；关门只能挨撞。
static func toggle_gate(run: Dictionary) -> String:
	if run.phase != "post":
		return "现在不能动门。"
	if run.sleeping:
		return "正睡着。"
	run.door_open = not bool(run.door_open)
	if bool(run.door_open):
		State.note(run, "抽了门闩，把大门拉开。")
	else:
		State.note(run, "退回院里，把大门闩上。")
	return ""


## 这一轮院门本该来的那几只，改成场上的活人（门开着的时候）。
static func start_fight(run: Dictionary, count: int, armored: bool) -> void:
	if not run.fight.is_empty():
		return
	run.fight = NightFight.begin(count, armored)
	State.note(run, "%d 只摸到了街上——门没关。" % int(run.fight.total))


## 架刀格挡。抬得起来返回 true（刀在收的时候 false）。
static func guard(run: Dictionary) -> bool:
	if run.fight.is_empty():
		return false
	return NightFight.guard(run.fight)


## 场上清干净了（或者天亮）：结算这一场的伤和尸毒。
static func end_fight(run: Dictionary, sum: Dictionary) -> void:
	if run.fight.is_empty():
		return
	run.fight = {}
	var kills := int(sum.get("kills", 0))
	if int(sum.get("hp_loss", 0)) > 0:
		State.add_attr(run, "hp", -float(sum.hp_loss))
	if bool(sum.get("plague", false)) and not run.plague:
		run.plague = true
	if kills > 0:
		run.today["merit"] = int(run.today.get("merit", 0)) + 1
		run.kills += kills
		run.today["kills"] = int(run.today.get("kills", 0)) + kills
		State.add_xp(run, "guard", int(kills / 3.0) + 1)
	var text := "院门口清干净了：斩 %d 只" % kills
	if int(sum.get("parries", 0)) > 0:
		text += "，架住 %d 下" % int(sum.parries)
	if int(sum.get("hp_loss", 0)) > 0:
		text += "，气血 -%d" % int(sum.hp_loss)
	if bool(sum.get("plague", false)):
		text += "，胳膊上多了几道黑紫的抓痕"
	State.note(run, text + "。")
	State.check_death(run, "死在院门口。")


## 门开着的时候，进院子的那几只开始砸东西。
static func apply_wreck(run: Dictionary, idx: int) -> String:
	var t: Array = NightFight.TARGETS[clampi(idx, 0, NightFight.TARGETS.size() - 1)]
	var text := ""
	match str(t[3]):
		"crop":
			for plot in run.plots:
				if plot.crop != "":
					text = "菜畦被啃光了，%s全没了。" % Data.table("crops")[plot.crop].name
					plot.crop = ""
					plot.days = 0.0
					break
			if text == "":
				text = "僵尸在菜畦里踩了一圈，好在没种东西。"
		"grain":
			var lost := Inv.take_any(run.home, Inv.GRAINS, 2)
			text = "米袋被扯开了，%s撒了一地。" % Data.describe_items(lost) if not lost.is_empty() else "僵尸扒开米袋，里面已经空了。"
		"fuel":
			if Inv.count(run.home, "firewood") > 0:
				Inv.add(run.home, "firewood", -1)
				text = "柴垛被踢散了，少了一捆柴。"
			else:
				text = "僵尸在柴垛边打了个转。"
		_:
			var gone := ""
			if not run.get("furniture", []).is_empty():
				var f: Dictionary = run.furniture[run.furniture.size() - 1]
				gone = Home.data(f.id).get("name", "")
				run.furniture.erase(f)
			text = ("%s被砸烂了。" % gone) if gone != "" else "僵尸在屋里翻了一通，没剩下什么可砸的。"
	if text != "":
		State.note(run, text)
	return text


# ---------- 一天的开始 ----------

static func begin_day(run: Dictionary) -> void:
	run.pday = int(run.pday) + 1
	run.t = (int(run.pday) - 1) * DAY
	run.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	run.buffs = []
	run.well_used = false
	run.heated = false
	run.heat_weak = false
	run.night_policy = ""
	run.guard_spot = ""
	run.plan_due = false
	run.night = {}
	run.fight = {}
	run.door_open = false
	run.night_lines = []
	run.event_result = ""
	Ledger.draw_omens(run)
	Ledger.pick_wish(run)
	var w := State.weather(run)
	State.note(run, "%s。%s" % [w.name, w.desc])
	for line in Defense.forecast(run):
		State.note(run, line)


## 返回 "" 表示可以做事，否则是原因。
static func can_act(run: Dictionary, energy_needed := 5) -> String:
	if run.phase != "post":
		return "现在不能做这个。"
	if run.pending_event != "" or run.dawn_due or run.wave_due or run.plan_due or not run.wave_report.is_empty():
		return "先处理眼前的事。"
	if not run.explore.is_empty():
		return "人还在外面。"
	if run.sleeping:
		return "正睡着。"
	if is_busy(run):
		return "正在%s。" % run.busy.label
	if State.attr(run, "energy") < energy_needed:
		return "精力不济，先歇一歇。"
	return ""


static func _start(run: Dictionary, kind: String, data := {}) -> void:
	var a: Array = ACTIONS[kind]
	State.add_attr(run, "energy", -float(a[2]))
	run.busy = {"kind": kind, "label": a[0], "start": run.t, "end": int(run.t) + int(a[1]), "data": data}


## 做事做到一半的进度（0..1）。
static func busy_progress(run: Dictionary) -> float:
	if run.busy.is_empty():
		return 0.0
	var span := maxf(1.0, float(run.busy.end) - float(run.busy.start))
	return clampf((float(run.t) - float(run.busy.start)) / span, 0.0, 1.0)


static func _check_busy(run: Dictionary) -> void:
	if run.busy.is_empty() or int(run.t) < int(run.busy.end):
		return
	var b: Dictionary = run.busy
	run.busy = {}
	_complete(run, b.kind, b.data)
	run.today.actions.append(b.kind)
	Ledger.check_wish(run, "action", b.kind)


## 做完了，见成果。
static func _complete(run: Dictionary, kind: String, data: Dictionary) -> void:
	match kind:
		"cook":
			var rid: String = data.recipe
			var n := cook_servings(run, rid)
			var dish := rid
			if State.attr(run, "mood") < 20 and Rng.chance(run, 0.35):
				dish = "burnt"
			Inv.add(run.home, dish, n)
			var first: bool = not ("cooked_" + rid) in run.flags
			run.flags["cooked_" + rid] = true
			State.add_xp(run, "cook", 3 + (3 if first else 0))
			State.note(run, "%s出锅，得 %d 份。" % [Data.item_name(dish), n])
		"garden":
			_tend_garden(run)
		"build":
			var d: Dictionary = Data.table("devices").devices[data.device]
			var dur := int(d.dur) + (1 if State.prof_level(run, "build") >= 2 else 0)
			run.devices.append({"id": data.device, "dur": dur})
			State.add_xp(run, "build", 3)
			State.note(run, "%s做好了。" % d.name)
		"repair":
			var part: Dictionary = run[data.target]
			var amount := 35 + 5 * State.prof_level(run, "build")
			part.cur = mini(int(part.max), int(part.cur) + amount)
			State.add_xp(run, "build", 2)
			var label := "门" if data.target == "door" else ("窗" if data.target == "window" else "院墙")
			State.note(run, "修补了%s，耐久 +%d。" % [label, amount])
		"mend":
			_tend_surface(run, str(data.surface))
			State.add_xp(run, "build", 2)
		"ward":
			var wd: Dictionary = Data.table("devices").devices[data.device]
			run.devices.append({"id": data.device, "dur": int(wd.dur)})
			State.add_xp(run, "build", 2)
			State.note(run, "趁着间隙布下了%s。" % wd.name)
		"read":
			var r: Dictionary = Data.item(data.book).read
			if r.has("prof"):
				State.add_xp(run, r.prof, int(r.xp) * (2 if State.is_role(run, "scholar") else 1))
			if r.has("merit"):
				run.today["merit"] = int(run.today.merit) + int(r.merit)
			if r.has("mood"):
				State.add_attr(run, "mood", r.mood)
			State.add_attr(run, "mood", 3)
			State.note(run, "读完了%s。" % Data.item_name(data.book))
		"craft":
			var c: Dictionary = Data.table("devices").crafts[data.craft]
			Inv.add_all(run.home, c.out)
			State.note(run, "%s，得%s。" % [c.name, Data.describe_items(c.out)])
		"rest":
			State.add_attr(run, "mood", 4)
			State.note(run, "小憩醒来，精神好些了。")
		"water":
			var n := 2 + (1 if State.has_facility(run, "water_vat") else 0)
			var frozen := int(State.weather(run).cold) >= 25
			if frozen:
				n = maxi(1, n - 1)
			Inv.add(run.home, "water", n)
			State.note(run, "从井里打上来 %d 瓢水。%s" % [n, "井口结了冰，凿了半天。" if frozen else ""])


# ---------- 行动 ----------

static func act_rest(run: Dictionary) -> String:
	var err := can_act(run, 0)
	if err != "":
		return err
	_start(run, "rest")
	State.note(run, "靠在榻上小憩。")
	return ""


## 就寝：一直睡到天亮。天黑以后，或者累坏了才能睡。
static func sleep(run: Dictionary) -> String:
	var err := can_act(run, 0)
	if err != "":
		return err
	if in_night(run):
		return "尸潮还在街上，这时候躺下就再也起不来了。"
	if not is_night(run) and State.attr(run, "energy") >= 30:
		return "天还亮着，睡不着。（可以小憩）"
	run.sleeping = true
	State.note(run, "吹了灯，躺下了。")
	return ""


static func act_read(run: Dictionary, book_id: String) -> String:
	var err := can_act(run)
	if err != "":
		return err
	if Inv.count(run.home, book_id) <= 0:
		return "没有这本书。"
	if book_id in run.read:
		return "这本已经读熟了。"
	run.read.append(book_id)
	_start(run, "read", {"book": book_id})
	return ""


## 做菜：配方食材（有替代料就用替代料）+ 柴火。没柴时一筐炭顶两捆柴。
static func recipe_inputs(run: Dictionary, recipe_id: String) -> Dictionary:
	var r: Dictionary = Data.table("recipes")[recipe_id]
	var need: Dictionary = r["in"].duplicate()
	for orig in r.get("alt", {}):
		var sub: String = r.alt[orig]
		if Inv.count(run.home, orig) < int(need[orig]) and Inv.count(run.home, sub) >= int(need[orig]):
			need[sub] = need[orig]
			need.erase(orig)
	return need


static func fuel_plan(run: Dictionary, units: int) -> Dictionary:
	var wood := Inv.count(run.home, "firewood")
	if wood >= units:
		return {"firewood": units}
	var coal_needed := int(ceil((units - wood) / 2.0))
	if Inv.count(run.home, "charcoal") >= coal_needed:
		var plan := {"charcoal": coal_needed}
		if wood > 0:
			plan["firewood"] = wood
		return plan
	return {}


static func cook_servings(run: Dictionary, recipe_id: String) -> int:
	var r: Dictionary = Data.table("recipes")[recipe_id]
	var n := int(r.out)
	if State.has_facility(run, "stove"):
		n += 1
	if State.has_talent(run, "paoding"):
		n += 1
	if State.has_buff(run, "cook_plus"):
		n += 2
	if State.prof_level(run, "cook") >= 3:
		n += 1
	return n


static func recipe_block(run: Dictionary, recipe_id: String) -> String:
	var r: Dictionary = Data.table("recipes")[recipe_id]
	if State.prof_level(run, "cook") < int(r.lv):
		return "庖厨 %d 级才会做" % r.lv
	if not Inv.has_all(run.home, recipe_inputs(run, recipe_id)):
		return "食材不够"
	if fuel_plan(run, int(r.fuel)).is_empty():
		return "柴火不够"
	return ""


static func act_cook(run: Dictionary, recipe_id: String) -> String:
	var err := can_act(run)
	if err != "":
		return err
	err = recipe_block(run, recipe_id)
	if err != "":
		return err
	var r: Dictionary = Data.table("recipes")[recipe_id]
	Inv.take_all(run.home, recipe_inputs(run, recipe_id))
	Inv.take_all(run.home, fuel_plan(run, int(r.fuel)))
	_start(run, "cook", {"recipe": recipe_id})
	State.note(run, "生火做%s。" % r.name)
	return ""


## 种菜不占时间；浇水收成要一阵子。
static func plant(run: Dictionary, plot_idx: int, crop_id: String) -> String:
	var plot: Dictionary = run.plots[plot_idx]
	if plot.crop != "":
		return "这块地已经种上了。"
	var c: Dictionary = Data.table("crops")[crop_id]
	if Inv.count(run.home, c.seed) <= 0:
		return "没有%s。" % Data.item_name(c.seed)
	Inv.add(run.home, c.seed, -1)
	plot.crop = crop_id
	plot.days = 0.0
	plot.watered_t = run.t
	State.note(run, "种下了%s。" % c.name)
	return ""


static func crop_ripe(plot: Dictionary) -> bool:
	return plot.crop != "" and float(plot.days) >= float(Data.table("crops")[plot.crop].days)


static func plot_dry(run: Dictionary, plot: Dictionary) -> bool:
	return plot.crop != "" and int(run.t) - int(plot.watered_t) > DAY


static func act_garden(run: Dictionary) -> String:
	var err := can_act(run)
	if err != "":
		return err
	var planted := false
	for plot in run.plots:
		if plot.crop != "":
			planted = true
	if not planted:
		return "菜畦里什么也没种。"
	_start(run, "garden")
	return ""


static func _tend_garden(run: Dictionary) -> void:
	var harvest := {}
	for plot in run.plots:
		if not crop_ripe(plot):
			continue
		var c: Dictionary = Data.table("crops")[plot.crop]
		var n := Rng.i(run, int(c["yield"][0]), int(c["yield"][1]))
		n += State.prof_level(run, "farm") / 2
		if State.has_talent(run, "shennong"):
			n += 1
		Inv.add(run.home, c.item, n)
		harvest[c.item] = int(harvest.get(c.item, 0)) + n
		State.add_xp(run, "farm", 2)
		plot.days = 0.0
		if not c.get("regrow", false):
			plot.crop = ""
	var watered := Inv.count(run.home, "water") > 0
	if watered:
		Inv.add(run.home, "water", -1)
		for plot in run.plots:
			plot.watered_t = run.t
	State.add_xp(run, "farm", 3)
	var text := "打理完菜畦"
	if not harvest.is_empty():
		text += "，收了%s" % Data.describe_items(harvest)
	text += "。" if watered else "，可惜没有水浇。"
	State.note(run, text)


static func device_block(run: Dictionary, device_id: String) -> String:
	var d: Dictionary = Data.table("devices").devices[device_id]
	if State.prof_level(run, "build") < int(d.get("lv", 0)):
		return "营造 %d 级才会做" % d.lv
	if not Inv.has_all(run.home, d.cost):
		return "材料不够"
	if int(d.time) > 0:
		return can_act(run)
	if run.phase != "post" or not run.explore.is_empty():
		return "现在不能做这个。"
	return ""


static func act_build(run: Dictionary, device_id: String) -> String:
	var err := device_block(run, device_id)
	if err != "":
		return err
	var d: Dictionary = Data.table("devices").devices[device_id]
	Inv.take_all(run.home, d.cost)
	if int(d.time) > 0:
		_start(run, "build", {"device": device_id})
		State.note(run, "动手做%s。" % d.name)
	else:
		run.devices.append({"id": device_id, "dur": int(d.dur)})
		State.note(run, "布下了%s。" % d.name)
	return ""


static func act_repair(run: Dictionary, target: String) -> String:
	var err := can_act(run)
	if err != "":
		return err
	var part: Dictionary = run[target]
	if int(part.cur) >= int(part.max):
		return "完好无损，不用修。"
	if Inv.count(run.home, "wood") > 0:
		Inv.add(run.home, "wood", -1)
	elif Inv.count(run.home, "firewood") >= 2:
		# 没木料就拆柴垛：两捆柴顶一根木料
		Inv.add(run.home, "firewood", -2)
	else:
		return "没有木料（两捆柴也能拆着补门板）。"
	_start(run, "repair", {"target": target})
	return ""


static func craft_block(run: Dictionary, craft_id: String) -> String:
	var c: Dictionary = Data.table("devices").crafts[craft_id]
	if c.has("flag") and not State.flag(run, c.flag):
		return "还不会"
	if not Inv.has_all(run.home, c["in"]):
		return "材料不够"
	return can_act(run)


static func act_craft(run: Dictionary, craft_id: String) -> String:
	var err := craft_block(run, craft_id)
	if err != "":
		return err
	var c: Dictionary = Data.table("devices").crafts[craft_id]
	Inv.take_all(run.home, c["in"])
	_start(run, "craft", {"craft": craft_id})
	return ""


static func draw_water(run: Dictionary) -> String:
	var err := can_act(run, 2)
	if err != "":
		return err
	if run.well_used:
		return "今天已经打过水了。"
	run.well_used = true
	_start(run, "water")
	return ""


# ---------- 外出 ----------

## 出门：赶路一个时辰。天黑以后不敢出门。
static func act_explore(run: Dictionary, pid: String) -> String:
	var err := can_act(run, 10)
	if err != "":
		return err
	err = Explore.point_block(run, pid)
	if err != "":
		return err
	if day_minute(run) + 60 >= CURFEW_AT:
		return "天快黑了，这时候出门是送死。"
	Explore.begin(run, pid)
	State.add_attr(run, "energy", -float(ACTIONS.travel[2]))
	run.today.actions.append("explore")
	Ledger.check_wish(run, "action", "explore")
	State.note(run, "出门去%s。" % Data.table("map_points")[pid].name)
	advance(run, int(ACTIONS.travel[1]))
	return ""


static func search(run: Dictionary, idx: int) -> Dictionary:
	if run.explore.is_empty() or blocked(run):
		return {}
	var res := Explore.search(run, idx)
	if not res.is_empty():
		State.add_attr(run, "energy", -float(ACTIONS.search[2]))
		advance(run, int(ACTIONS.search[1]))
	return res


## 回家：也要赶一个时辰的路。
static func finish_explore(run: Dictionary) -> Dictionary:
	if run.explore.is_empty():
		return {}
	var summary := Explore.finish(run)
	if run.phase == "post":
		advance(run, int(ACTIONS.travel[1]))
	return summary


# ---------- 不占时间 ----------

static func use_item(run: Dictionary, id: String) -> String:
	if run.phase != "post":
		return "现在不能用。"
	if Inv.count(run.home, id) <= 0:
		return "没有了。"
	var it := Data.item(id)
	var fx: Dictionary = it.get("eat", it.get("use", {}))
	if fx.is_empty():
		return "这东西不能吃也不能用。"
	var mul := 1.5 if it.cat == "药" and State.is_role(run, "herbalist") else 1.0
	Inv.add(run.home, id, -1)
	for k in ["food", "water", "hp", "mood", "energy"]:
		if fx.has(k):
			var v := float(fx[k])
			State.add_attr(run, k, v * mul if v > 0 else v)
	var text := "%s了%s。" % ["吃" if it.has("eat") else "用", it.name]
	if fx.has("cure") and run.plague:
		if Rng.chance(run, minf(1.0, float(fx.cure) * mul)):
			run.plague = false
			text += "尸瘟退了。"
		else:
			text += "尸瘟没压下去。"
	if it.has("eat"):
		run.today.ate.append(id)
		Ledger.check_wish(run, "eat", id)
	State.note(run, text)
	return ""
