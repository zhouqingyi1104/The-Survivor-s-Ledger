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
const Expedition = preload("res://scripts/core/expedition.gd")
const SiteJourney = preload("res://scripts/core/site_journey.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
const Home = preload("res://scripts/core/home.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const NeighborHome = preload("res://scripts/core/neighbor_home.gd")
const Director = preload("res://scripts/core/director.gd")
const Companion = preload("res://scripts/core/companion.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")
const Agenda = preload("res://scripts/core/agenda.gd")

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
	"sleep_energy": 7.0, "nap_energy": 10.0, "sleep_hp": 0.8, "warm_up": 2.0, "boiler_up": 3.0,
	"starve_hp": 2.0, "thirst_hp": 2.5, "plague_hp": 1.0, "cold_hp": 0.7, "freezing_hp": 1.4,
	"overrun_hp": 3.0,
}

## 每档流速：游戏分钟 / 现实秒。0 = 暂停。
## 放在 core 而不是界面里：这是节奏数值（一天要花玩家多少真实时间），不是皮肤。
const SPEEDS := [0.0, 4.0, 10.0, 24.0]
## 手头有活在干：不管哪档都至少这么快（做一件事只用等一两秒）
const BUSY_RATE := 40.0
## 睡着：一路滑到天亮
const SLEEP_RATE := 150.0

## 行动：[名称, 分钟, 精力消耗]
const ACTIONS := {
	"cook": ["做饭", 60, 6], "garden": ["打理菜畦", 45, 8], "build": ["营造", 90, 10], "repair": ["修缮", 60, 8],
	"fix_furniture": ["重修家具", 90, 8],
	"furnish": ["安放家具", 45, 6],
	"expansion_clear": ["查勘清理侧院", Expansion.CLEAR_MINUTES, 5],
	"expansion_build": ["施工侧院", Expansion.BUILD_MINUTES, 8],
	"attic_build": ["施工阁楼", Floors.ATTIC_MINUTES, 8],
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


## 这一刻时间该跑多快（游戏分钟/现实秒）。界面只管问，不自己算。
static func rate(run: Dictionary, speed: int) -> float:
	var base: float = float(SPEEDS[clampi(speed, 0, SPEEDS.size() - 1)])
	if base <= 0.0:
		return 0.0
	if bool(run.get("sleeping", false)):
		return SLEEP_RATE
	if is_busy(run):
		return maxf(base, BUSY_RATE)
	return base


## 到下一个"值得停下来"的时刻还有多少分钟：天黑、烧炭、宵禁、尸潮、溃兵、夜战轮次、天亮。
## 「等一刻」用它跳时——只跳到节点，不会跳过夜战轮次和事件检查点。
## 手头正在忙、正在睡、或被事件/夜报卡着时返回 0：那种时候不该跳。
static func minutes_to_next_stop(run: Dictionary) -> int:
	if run.get("phase", "") != "post" or blocked(run) or is_busy(run) or bool(run.get("sleeping", false)):
		return 0
	var now := day_minute(run)
	var next := DAY
	for cp in checkpoints(run):
		if int(cp) > now:
			next = mini(next, int(cp))
	return maxi(0, next - now)


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
			return "ending" if run.phase == "ending" else "dead"
		trade_refresh(run)
		if Neighbor.poll(run) != "":
			return "event"
		if blocked(run):
			return "blocked"
		if Director.poll(run) != "":
			return "event"
		var m := day_minute(run)
		var step := mini(TICK, left)
		# Finish work at its actual minute, even after split advances. Otherwise a
		# valid finish just before a crisis deadline can be rounded into the crisis.
		var work_end := int(run.busy.get("end", 0))
		if work_end > int(run.t) and int(run.t) + step > work_end:
			step = work_end - int(run.t)
		var npc_boundary := Npcs.next_boundary(run)
		if npc_boundary > int(run.t) and int(run.t) + step > npc_boundary:
			step = npc_boundary - int(run.t)
		for cp in checkpoints(run):
			if m < cp and m + step > cp:
				step = cp - m
		_tick(run, step / 60.0)
		run.t = int(run.t) + step
		left -= step
		trade_refresh(run)
		# 死因交给账本算（谁真的把气血打光），不再事后按属性猜
		if (State.attr(run, "hp") <= 0 or run.phase == "dead") and State.check_death(run, DeathReport.verdict(run)):
			_interrupt_targeted_device(run)
			return "dead"
		_check_busy(run)
		if run.phase != "post":
			return "ending" if run.phase == "ending" else "dead"
		var stop := _checkpoint(run, m + step)
		if stop != "":
			return stop
		if Neighbor.poll(run) != "":
			return "event"
	return ""


static func _tick(run: Dictionary, hours: float) -> void:
	var sleeping: bool = run.sleeping
	var resting: bool = run.busy.get("kind", "") == "rest"
	var d: Dictionary = State.diff(run)
	var mul := 0.6 if sleeping else 1.0
	State.add_attr(run, "food", -RATE.food * mul * hours * float(d.food_mul) * (0.75 if State.has_talent(run, "bigu") else 1.0))
	State.add_attr(run, "water", -RATE.water * mul * hours * float(d.water_mul))
	State.add_attr(run, "mood", (0.3 if sleeping else -RATE.mood) * hours)
	var warm: int = State.attr(run, "warmth")
	var boiler: bool = bool(run.get("powered", false)) and State.has_facility(run, "heater")
	if sleeping:
		# 冻着睡不踏实：回暖少，气血也不长；有暖气才睡得沉
		State.add_attr(run, "energy", RATE.sleep_energy * hours * (1.0 if warm >= 30 or boiler else 0.6))
		if State.attr(run, "food") > 20 and State.attr(run, "water") > 20 and (warm >= 30 or boiler):
			State.add_attr(run, "hp", RATE.sleep_hp * hours)
	elif resting:
		State.add_attr(run, "energy", RATE.nap_energy * hours)
	else:
		State.add_attr(run, "energy", -RATE.energy * hours)
	# 体温：白天靠日头回暖（最多到 60，地窖 75）；夜里生火 / 发电机才暖得起来，
	# 发电机带暖气的话整夜往上走，冷天也不掉温
	var cold := cold_of(run)
	if is_night(run) and cold > 0 and not run.heated:
		var loss := cold / 10.0 * (0.5 if State.has_facility(run, "cellar") else 1.0)
		if State.has_buff(run, "padded"):
			loss *= Agenda.PADDED_COLD
		if sleeping and State.flag(run, "kang"):
			loss *= Agenda.KANG_COLD
		State.add_attr(run, "warmth", -loss * hours)
	elif boiler:
		run.attrs.warmth = clampf(float(run.attrs.warmth) + RATE.boiler_up * hours, 0.0, 100.0)
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
		State.hurt(run, RATE.starve_hp * hours, "starve")
		State.add_attr(run, "mood", -1.2 * hours)
	if State.attr(run, "water") <= 0:
		State.hurt(run, RATE.thirst_hp * hours, "thirst")
	if run.plague:
		State.hurt(run, RATE.plague_hp * hours, "plague")
	if State.attr(run, "warmth") < 15:
		State.hurt(run, RATE.freezing_hp * hours, "freeze")
		State.add_attr(run, "mood", -0.8 * hours)
	elif State.attr(run, "warmth") < 30:
		State.hurt(run, RATE.cold_hp * hours, "cold")
		State.add_attr(run, "mood", -0.5 * hours)
	# 三面都被撞破：院子里的东西挡不住了，一直有人扑上来
	if in_night(run) and Defense.all_broken(run):
		State.hurt(run, RATE.overrun_hp * hours, "overrun")
		State.add_attr(run, "mood", -1.0 * hours)
	# 作物：一天之内浇过水才长
	for plot in run.plots:
		if plot.crop != "" and int(run.t) - int(plot.watered_t) <= DAY:
			plot.days = float(plot.days) + hours / 24.0


static func _checkpoint(run: Dictionary, m: int) -> String:
	# 夜战：到点结算下一轮
	if in_night(run) and m == Defense.round_minute(int(run.night.round)):
		return "wave_round"
	match m:
		EVENT_AT:
			if Neighbor.poll(run) == "":
				if Director.poll(run) == "":
					run.pending_event = Events.roll(run)
			if run.pending_event != "":
				return "event"
		DUSK_AT:
			if str(run.get("home_floor", "courtyard")) == "guest_zhou":
				_interrupt_room_work(run)
				Floors.return_to_courtyard(run)
				State.note(run, "天黑前向老周告辞，回到自家院里。")
			State.note(run, "天黑了。")
		HEAT_AT:
			_heat(run)
		CURFEW_AT:
			if not run.explore.is_empty():
				# 翻找和调查会跨时推进；需要记住宵禁，等待药柜选择或现场工作结束后返程。
				run.explore["curfew_due"] = true
				return "curfew"
			# 今夜有尸潮：先让玩家定守夜方针，再放时间走
			if not Defense.wave_for_run(run, int(run.pday)).is_empty() and int(run.wave_day) != int(run.pday) and str(run.get("night_policy", "")) == "":
				run.plan_due = true
				run.sleeping = false
				return "plan"
		WAVE_AT:
			if not Defense.wave_for_run(run, int(run.pday)).is_empty() and int(run.wave_day) != int(run.pday):
				NeighborHome.interrupt(run)
				_interrupt_targeted_device(run)
				_interrupt_room_work(run)
				Floors.return_to_courtyard(run)
				run.wave_due = true
				run.sleeping = false
				_interrupt_furnish(run)
				run.busy = {}
				return "wave"
		RAID_AT:
			# 尸潮还在街上，溃兵不会这时候来
			if run.raid_tonight and not in_night(run):
				NeighborHome.interrupt(run)
				_interrupt_targeted_device(run)
				_interrupt_room_work(run)
				Floors.return_to_courtyard(run)
				if str(run.busy.get("kind", "")) == "attic_build":
					run.busy = {}
					State.note(run, "夜袭打断阁楼施工，已备材料仍在。")
				run.sleeping = false
				run.raid_report = Defense.resolve_raid(run)
				run.raid_tonight = false
				return "raid"
		DAY:
			_interrupt_targeted_device(run)
			if in_night(run):
				_close_night(run)
			_dawn(run)
			return "dawn"
	return ""


## 今夜实际有多冷：天气的冷加上难度的冷加成（暖冬能加到 2 以下，等于不冻）。
static func cold_of(run: Dictionary) -> int:
	var base := int(State.weather(run).cold)
	return base + int(State.diff(run).get("cold_add", 0))


## 20:00 取暖：有发电机就烧柴油（管一整夜，还带动暖气）；不然烧炭 / 柴。
static func _heat(run: Dictionary) -> void:
	if cold_of(run) <= 0:
		return
	# 发电机：冷天才值得开，暖夜白烧一桶油
	if State.has_facility(run, "generator") and Inv.count(run.home, "diesel") > 0:
		Inv.add(run.home, "diesel", -1)
		run.powered = true
		run.heated = true
		run.heat_weak = false
		var extra := "暖气跟着开了，屋里整夜往上回暖。" if State.has_facility(run, "heater") else ""
		run.night_lines.append("发电机轰起来，烧了一桶柴油。%s" % extra)
		State.note(run, "开发电机，烧了一桶柴油。%s" % extra)
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
		var no_gen := "发电机里没有柴油。" if State.has_facility(run, "generator") else ""
		run.night_lines.append("没柴没炭，屋里冷得像冰窖。%s" % no_gen)
		State.note(run, "没柴没炭，夜里冷得睡不着。%s" % no_gen)
		return
	Inv.take_all(run.home, fuel)
	run.heated = true
	run.heat_weak = weak
	run.night_lines.append("烧了%s取暖。%s" % [Data.describe_items(fuel), "柴少，火到后半夜就弱了。" if weak else ""])
	State.note(run, "生起火盆，烧了%s。%s" % [Data.describe_items(fuel), "柴不够，只能烧半夜。" if weak else ""])


## 6:00 天亮：结算功过格，等玩家翻页（ack_dawn）再开新的一天。
static func _dawn(run: Dictionary) -> void:
	run.sleeping = false
	NeighborHome.interrupt(run, "天亮")
	_interrupt_furnish(run, "天亮")
	run.busy = {}
	run.dawn_due = true
	# 同院的人天亮各干一件事（先收口粮），动静放进天亮报告
	var help := Companion.dawn(run)
	for line in help:
		State.note(run, line)
	run.report = {"day": run.pday, "night": run.night_lines.duplicate(), "help": help, "settle": Ledger.settle(run)}


static func ack_dawn(run: Dictionary) -> void:
	if not run.dawn_due:
		return
	run.dawn_due = false
	run.report = {}
	if int(run.pday) >= State.STORY_DAYS and not run.endless:
		Mainline.finish_dawn(run)
		return
	begin_day(run)


## 22:00 尸潮：开夜，先把第一轮算出来给演出用。后两轮在夜战里逐轮结算。
static func resolve_wave(run: Dictionary) -> Dictionary:
	if not run.wave_due:
		return {}
	run.wave_due = false
	var wave := Defense.wave_for_run(run, int(run.pday))
	run.wave_day = run.pday
	Defense.start_night(run, wave)
	var rep := Defense.next_round(run)
	if run.phase == "dead":
		_interrupt_targeted_device(run)
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
	if run.phase == "dead":
		_interrupt_targeted_device(run)
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
	var guard_text := "亲守%s" % Defense.surface_name(run.guard_spot)
	if str(run.guard_spot) == "":
		guard_text = "所选院门不可守" if str(p.get("spot", "gate")) == "gate" else "没有可守面"
	State.note(run, "今夜方针：%s。%s。" % [p.name, guard_text])
	return ""


## 方针里的「亲守哪一面」：gate 固定守门，weak 选今夜最吃紧的一面。
static func _spot_for(run: Dictionary, mode: String) -> String:
	if mode == "gate":
		return "" if Defense.is_broken(run, "gate") or bool(run.get("door_open", false)) else "gate"
	var wave := Defense.wave_for_run(run, int(run.pday))
	# 每次假定亲守一面，比较和无亲守相比的预计漏怪减少；已破面及开门迎战不能受益。
	var neutral := run.duplicate()
	neutral.guard_spot = ""
	var baseline := Defense.preview_night(neutral, wave)
	var best := ""
	var best_saved := -1
	var best_threat := -1
	for sid in Defense.SURFACES:
		if Defense.is_broken(run, sid) or (sid == "gate" and bool(run.get("door_open", false))):
			continue
		var trial := neutral.duplicate()
		trial.guard_spot = sid
		var predicted := Defense.preview_night(trial, wave)
		var saved := int(baseline.left) - int(predicted.left)
		var threat := int(baseline.get(sid, {}).get("left", 0))
		if saved > best_saved or (saved == best_saved and threat > best_threat):
			best_saved = saved
			best_threat = threat
			best = sid
	return best


## 21:00 弹窗用的四档：[id, 名称, 说明, 亲守面, 今夜预计漏几只]
static func policy_options(run: Dictionary) -> Array:
	var wave := Defense.wave_for_run(run, int(run.pday))
	var out := []
	for id in Data.table("waves").policies:
		var p: Dictionary = Data.table("waves").policies[id]
		var spot := _spot_for(run, str(p.get("spot", "gate")))
		var saved: String = str(run.guard_spot)
		run.guard_spot = spot
		var pv := Defense.preview_night(run, wave)
		run.guard_spot = saved
		var leak := int(pv.get("left", 0))
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
	Defense.pay_mend(run, sid)
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
	Defense.pay_mend(run, sid)
	run.night.acted = true
	_start(run, "mend", {"surface": sid})
	return ""


static func night_build(run: Dictionary, did: String) -> String:
	var err := night_block(run, 6)
	if err != "":
		return err
	err = device_block(run, did, true)
	if err != "":
		return err
	var d: Dictionary = Data.table("devices").devices[did]
	Inv.take_all(run.home, d.cost)
	run.night.acted = true
	var data := {"device": did}
	if did in ["armor_hook", "horde_rope"]:
		data["paid_cost"] = d.cost.duplicate(true)
	_start(run, "ward", data)
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
	NeighborHome.interrupt(run)
	_interrupt_targeted_device(run)
	_interrupt_room_work(run)
	Floors.return_to_courtyard(run)
	_interrupt_furnish(run)
	if str(run.busy.get("kind", "")) == "attic_build":
		run.busy = {}
		State.note(run, "夜袭打断阁楼施工，已备材料仍在。")
	if str(run.busy.get("kind", "")) in ["expansion_clear", "expansion_build"]:
		run.busy = {}
		State.note(run, "夜袭打断了侧院施工，已备材料仍在。")
	run.fight = NightFight.begin(count, armored, run)
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
		State.hurt(run, float(sum.hp_loss), "bite")
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
	State.check_death(run, DeathReport.verdict(run))


## 门开着的时候，进院子的那几只开始砸东西。
static func apply_wreck(run: Dictionary, idx: int) -> String:
	var targets := NightFight.fight_targets(run)
	var t: Array = targets[clampi(idx, 0, targets.size() - 1)]
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
			# 家具砸烂了要留在 run.broken 里：塌在当场，等玩家拿材料重做
			if not run.has("broken"):
				run.broken = []
			var want := str(t[4]) if t.size() > 4 else ""
			var target := Home.core(run, want)
			if not target.is_empty() and (t.size() < 6 or int(target.uid) == int(t[5])) and not want in run.broken:
				run.broken.append(want)
				text = "%s被砸烂了，得拿木料和铁钉重做。" % Home.data(want).get("name", "家具")
			else:
				text = "这件家具已经砸坏了。"
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
	run.powered = false
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
	trade_refresh(run)
	Agenda.build(run, agenda_offers(run))


# ---------- 今日差事 ----------

## 今天做得成的既有行动（折进差事单）：只看料和条件，不看此刻忙不忙。
static func agenda_offers(run: Dictionary) -> Array:
	var out := []
	if Crisis.well_block(run) == "" and not bool(run.get("well_used", false)):
		out.append("water")
	for rid in Data.table("recipes"):
		if recipe_block(run, rid) == "":
			out.append("cook")
			break
	for plot in run.plots:
		if plot.crop != "":
			out.append("garden")
			break
	if Inv.count(run.home, "wood") > 0 or Inv.count(run.home, "firewood") >= 2:
		for sid in Defense.SURFACES:
			var part := Defense.part_of(run, sid)
			if int(part.cur) < int(part.max):
				out.append("repair")
				break
	# 能去的地方有两处以上，一天就够跑两趟
	var open_points := 0
	for pid in Explore.visible_points(run):
		if Explore.point_block(run, pid) == "":
			open_points += 1
	if open_points >= 1:
		out.append("explore")
	if open_points >= 2:
		out.append("explore2")
	for cid in Data.table("devices").crafts:
		var c: Dictionary = Data.table("devices").crafts[cid]
		if c.has("identity") and Identity.craft_block(run, cid) != "":
			continue
		if c.has("flag") and not State.flag(run, c.flag):
			continue
		if Inv.has_all(run.home, c["in"]):
			out.append("craft")
			break
	for book in Inv.ids_in_cat(run.home, "书"):
		if not book in run.read:
			out.append("read")
			break
	return out


## 老存档、或者刚读档进来：今天的单子还没排就现排。
static func ensure_agenda(run: Dictionary) -> void:
	if run.get("phase", "") != "post" or int(run.get("pday", 0)) <= 0:
		return
	if int(Agenda.state(run).day) != int(run.pday):
		Agenda.build(run, agenda_offers(run))


## 做单子上的一件差事（既有行动走各自的函数，这里只管 chore）。
static func act_chore(run: Dictionary, idx: int) -> String:
	var it := Agenda.item(run, idx)
	if it.is_empty() or str(it.kind) != "chore":
		return "没有这件差事。"
	var c := Agenda.chore(str(it.id))
	var err := can_act(run, int(c.energy))
	if err != "":
		return err
	err = Agenda.block(run, idx)
	if err != "":
		return err + "。"
	Inv.take_all(run.home, Agenda.inputs(run, str(it.id)))
	State.add_attr(run, "energy", -float(c.energy))
	run.busy = {"kind": "chore", "label": str(c.name), "start": int(run.t), "end": int(run.t) + int(c.minutes),
		"data": {"idx": idx, "id": str(it.id), "day": int(run.pday)}}
	State.note(run, "动手%s。" % c.name)
	return ""


## 纸鹤交易在本地结算；到期事实也会使尚未展示的 AI 规划失效。
static func trade_refresh(run: Dictionary) -> String:
	# Settle world clocks before calculating market terms or honoring payments.
	var home_result := NeighborHome.poll(run)
	if home_result != "": Director.note_world(run, "西邻往来", home_result)
	crisis_refresh(run)
	mainline_refresh(run)
	var identity_result := Identity.poll(run)
	if identity_result != "": Director.note_world(run, "身份与前世 · 工作中断", identity_result)
	var cycle_result := Cycle.poll(run)
	if cycle_result != "": Director.note_world(run, "轮回调查 · 旧诺与今证", cycle_result)
	Trade.state(run)
	var npc_result := Npcs.poll(run)
	if npc_result != "":
		Director.note_world(run, "邻人与商情 · 自主行动", npc_result)
	var result := Trade.poll(run)
	if result != "":
		Director.note_choice(run, "纸鹤往来 · 履约与期限", result)
	return ""


static func mainline_refresh(run: Dictionary) -> String:
	var result := Mainline.poll(run)
	if result != "":
		Director.note_world(run, "尸劫来历 · 调查与出路", result)
	return ""


static func mainline_action(run: Dictionary, action: String, token: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	trade_refresh(run)
	var result := Mainline.act(run, action, token)
	if result == "":
		Director.note_choice(run, "尸劫来历 · 主线选择", str(Mainline.state(run).last_result))
	return result


static func identity_action(run: Dictionary, action: String, token: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	trade_refresh(run)
	var result := Identity.act(run, action, token)
	if result == "":
		Director.note_choice(run, "身份与旧世 · 专属解法", str(Identity.state(run).get("work", {}).get("label", action)))
	return result


static func cycle_action(run: Dictionary, case_id: String, action: String, token: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	trade_refresh(run)
	var result := Cycle.act(run, case_id, action, token)
	if result == "":
		Director.note_choice(run, "轮回调查 · 今世选择", str(Cycle.state(run).get("last_result", action)))
	return result


static func identity_intel(run: Dictionary) -> Array:
	if not Identity.has(run, "wave_intel"): return []
	var lines := []
	for day in [11, 17, 20]:
		var wave := Defense.wave_for_run(run, day)
		if wave.is_empty(): continue
		lines.append("第%d夜：%d只，%s。%s" % [day, Defense._count(wave), Defense.mod_names(wave), "已开夜，按整夜锁定安排" if int(run.get("wave_day", 0)) == day else "今世干预变化后会重新核对"])
	return lines


static func npc_action(run: Dictionary, actor: String, action: String, token: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	trade_refresh(run)
	var result := Npcs.act(run, actor, action, token)
	if result == "":
		Director.note_choice(run, "邻人与商情 · " + str(Trade.contact(run, actor).get("name", actor)), str(Npcs.view(run, actor).get("last_result", "")))
	return result


static func crisis_refresh(run: Dictionary) -> String:
	var result := Crisis.poll(run)
	if result != "":
		Director.note_choice(run, "风声与危机", result)
	return ""


static func crisis_action(run: Dictionary, action: String, token: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	crisis_refresh(run)
	Trade.state(run) # Aid can spend only existing, real favors from this life.
	var result := Crisis.act(run, action, token)
	if result == "":
		Director.note_choice(run, "危机应对", str(Crisis.state(run).last_result))
	return result


static func trade_action(run: Dictionary, actor: String, action: String, quote_id: String) -> String:
	if Floors.current(run) == "guest_zhou": return "先回自家院里再处理。"
	trade_refresh(run)
	var result := Trade.act(run, actor, action, quote_id)
	if result == "":
		Director.note_choice(run, "纸鹤往来 · " + str(Trade.contact(run, actor).name), str(Trade.state(run).last_result))
	return result


## 返回 "" 表示可以做事，否则是原因。
static func can_act(run: Dictionary, energy_needed := 5, allow_guest := false) -> String:
	if run.phase != "post":
		return "现在不能做这个。"
	if not allow_guest and Floors.current(run) == "guest_zhou":
		return "先回自家院里再做这件事。"
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
		"neighbor_wall":
			NeighborHome.complete(run)
		"attic_build":
			if Floors.finish_attic(run):
				State.note(run, "阁楼施工完成。")
		"expansion_clear", "expansion_build":
			var expected := "survey" if kind == "expansion_clear" else "ready"
			if expected == "ready" and _side_passage_blocked(run):
				State.note(run, "侧院通路被家具挡住，先挪开再施工；已备材料仍在。")
			elif Expansion.finish(run, expected):
				State.note(run, "侧院已清理，可以备料。" if expected == "survey" else "东侧小院施工完成。")
		"chore":
			Agenda.complete(run, data)
		"cycle_inquiry":
			var result := Cycle.complete(run, data)
			if result != "": Director.note_choice(run, "轮回调查 · 工作完成", result)
		"identity":
			var result := Identity.complete(run, data)
			if result != "": Director.note_choice(run, "身份解法完成", result)
		"mainline":
			var result := Mainline.complete(run, data)
			if result != "": Director.note_choice(run, "主线行动完成", result)
		"crisis":
			var result := Crisis.complete(run, data)
			if result != "": Director.note_choice(run, "危机行动完成", result)
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
			if Floors.current(run) == str(data.get("floor", "courtyard")):
				_tend_garden(run, str(data.get("floor", "courtyard")))
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
		"fix_furniture":
			var id := str(data.target)
			run.broken.erase(id)
			State.add_xp(run, "build", 6)
			State.note(run, "把%s重新做了起来。" % Home.data(id).get("name", "家具"))
		"furnish":
			var fid := str(data.id)
			Home.add(run, fid, float(data.x), float(data.z), int(data.rot), str(data.get("floor", "courtyard")))
			State.add_xp(run, "build", 3)
			State.note(run, "%s摆好了。" % Home.data(fid).get("name", "家具"))
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
			if c.has("identity") and Identity.craft_block(run, str(data.craft)) != "":
				State.note(run, "身份配方的今世条件已经失效，未得到产物；已投入的材料和精力不退。")
				return
			Inv.add_all(run.home, c.out)
			State.note(run, "%s，得%s。" % [c.name, Data.describe_items(c.out)])
		"rest":
			State.add_attr(run, "mood", 4)
			State.note(run, "小憩醒来，精神好些了。")
		"water":
			var blocked_well := Crisis.well_block(run)
			if blocked_well != "":
				run.well_used = false # An unsuccessful attempt must not consume a successful draw.
				State.note(run, blocked_well + "这次没有打到水；修复后仍可重新打水。")
				return
			var n := 2 + (1 if State.has_facility(run, "water_vat") else 0)
			var frozen := int(State.weather(run).cold) >= 25
			if frozen:
				n = maxi(1, n - 1)
			Inv.add(run.home, "water", n)
			State.note(run, "从井里打上来 %d 瓢水。%s" % [n, "井口结了冰，凿了半天。" if frozen else ""])


# ---------- 行动 ----------

static func act_rest(run: Dictionary) -> String:
	if Floors.current(run) != "courtyard":
		return "先回院里的床榻歇息。"
	var err := can_act(run, 0)
	if err != "":
		return err
	_start(run, "rest")
	State.note(run, "靠在榻上小憩。")
	return ""


## 就寝：一直睡到天亮。天黑以后，或者累坏了才能睡。
static func sleep(run: Dictionary) -> String:
	if Floors.current(run) != "courtyard":
		return "先回院里的床榻就寝。"
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


## 院内菜畦和各层花盆分别可操作；失去家具的孤儿菜槽不归属任何空间。
static func plot_on_floor(run: Dictionary, plot: Dictionary, floor_id := "") -> bool:
	var target: String = Floors.current(run) if floor_id == "" else floor_id
	if not plot.has("pot"):
		return target == "courtyard"
	var furniture := Home.find(run, int(plot.get("pot", -1)))
	return not furniture.is_empty() and str(furniture.get("id", "")) == "planter" and str(furniture.get("floor", "courtyard")) == target


## 种菜不占时间；浇水收成要一阵子。
static func plant(run: Dictionary, plot_idx: int, crop_id: String) -> String:
	var err := can_act(run, 0)
	if err != "":
		return err
	if plot_idx < 0 or plot_idx >= run.plots.size() or not run.plots[plot_idx] is Dictionary:
		return "找不到这块菜地。"
	var plot: Dictionary = run.plots[plot_idx]
	if not plot_on_floor(run, plot):
		return "先进入这块菜地所在空间。"
	if not Data.table("crops").has(crop_id):
		return "没有这种作物。"
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
		if plot_on_floor(run, plot) and plot.crop != "":
			planted = true
	if not planted:
		return "菜畦里什么也没种。"
	_start(run, "garden", {"floor": Floors.current(run)})
	return ""


static func _tend_garden(run: Dictionary, floor_id := "courtyard") -> void:
	var harvest := {}
	for plot in run.plots:
		if not plot_on_floor(run, plot, floor_id) or not crop_ripe(plot):
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
			if plot_on_floor(run, plot, floor_id):
				plot.watered_t = run.t
	State.add_xp(run, "farm", 3)
	var text := "打理完菜畦"
	if not harvest.is_empty():
		text += "，收了%s" % Data.describe_items(harvest)
	text += "。" if watered else "，可惜没有水浇。"
	State.note(run, text)


static func device_block(run: Dictionary, device_id: String, night_action := false) -> String:
	var d: Dictionary = Data.table("devices").devices[device_id]
	var targeted := device_id in ["armor_hook", "horde_rope"]
	if targeted and not run.get("fight", {}).is_empty():
		return "正在迎战，先结束战斗。"
	if targeted and in_night(run) and not night_action:
		return "夜战中请在轮间面板布置。"
	if State.prof_level(run, "build") < int(d.get("lv", 0)):
		return "营造 %d 级才会做" % d.lv
	if not Inv.has_all(run.home, d.cost):
		return "材料不够"
	if int(d.time) > 0:
		return can_act(run, (6 if night_action else 10) if targeted else 5)
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
		var data := {"device": device_id}
		if device_id in ["armor_hook", "horde_rope"]:
			data["paid_cost"] = d.cost.duplicate(true)
		_start(run, "build", data)
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
	if target == "door":
		# 修过几次门（誓约「不修门」要查这个）
		var t: Dictionary = State.tally(run)
		t.repair_door = int(t.get("repair_door", 0)) + 1
	return ""


## 重修一件被砸烂的家具要什么料。
static func furniture_fix_cost(_id: String) -> Dictionary:
	return {"wood": 2, "nails": 1}


## 修这件的拦路理由（没坏 / 正忙 / 缺料）。
static func furniture_block(run: Dictionary, id: String) -> String:
	if not id in run.get("broken", []):
		return "没坏。"
	var err := can_act(run, 8)
	if err != "":
		return err
	var items: Dictionary = Data.table("items")
	var cost := furniture_fix_cost(id)
	for item in cost:
		var need := int(cost[item])
		if Inv.count(run.home, item) < need:
			return "缺%s（要 %d %s）" % [items[item].name, need, items[item].unit]
	return ""


## 重修：木料 2、铁钉 1，一个半时辰。
static func act_fix_furniture(run: Dictionary, id: String) -> String:
	var err := furniture_block(run, id)
	if err != "":
		return err
	Inv.take_all(run.home, furniture_fix_cost(id))
	_start(run, "fix_furniture", {"target": id})
	return ""


## 家具尚未落成就被夜袭打断时，只退回本次投入；先清 busy 防重复结算。
static func _interrupt_furnish(run: Dictionary, reason := "夜袭") -> void:
	if str(run.busy.get("kind", "")) != "furnish":
		return
	var data: Dictionary = run.busy.get("data", {})
	var cost = data.get("paid_cost", Home.data(str(data.get("id", ""))).get("cost", {}))
	run.busy = {}
	if cost is Dictionary:
		Inv.add_all(run.home, cost)
	State.note(run, "%s打断了家具安放，材料已退回。" % reason)


## 只对新增针对守具返还实际投入；先清除 busy，重复中断不能再次退款。
static func _interrupt_targeted_device(run: Dictionary) -> void:
	var busy: Dictionary = run.get("busy", {})
	if str(busy.get("kind", "")) not in ["build", "ward"]:
		return
	var data: Dictionary = busy.get("data", {})
	if str(data.get("device", "")) not in ["armor_hook", "horde_rope"]:
		return
	var paid = data.get("paid_cost", {})
	run.busy = {}
	if paid is Dictionary:
		Inv.add_all(run.home, paid)
	State.note(run, "守具施工被打断，已投入的材料退回；已耗精力不退。")


## 夜袭将人送回院层前，不能让室内工作在返回后跨空间完成。
## 家具安放有付款快照，其余工作沿用原有中断规则，不猜测退款。
static func _interrupt_room_work(run: Dictionary) -> void:
	if str(run.get("home_floor", "courtyard")) == "courtyard" or run.get("busy", {}).is_empty():
		return
	# 恢复室内威胁存档也会走这里；先结清新守具的付款快照。
	_interrupt_targeted_device(run)
	if run.busy.is_empty():
		return
	var kind := str(run.busy.get("kind", ""))
	var label := str(run.busy.get("label", "工作"))
	if kind == "furnish":
		_interrupt_furnish(run)
		return
	run.busy = {}
	State.note(run, "夜袭打断了%s，先返回院里。" % label)
	# 这些系统另存工作令牌，清 busy 后立即走各自的中断对账。
	match kind:
		"identity":
			var result := Identity.poll(run)
			if result != "": Director.note_world(run, "身份与前世 · 工作中断", result)
		"cycle_inquiry":
			var result := Cycle.poll(run)
			if result != "": Director.note_world(run, "轮回调查 · 旧诺与今证", result)
		"mainline":
			var result := Mainline.poll(run)
			if result != "": Director.note_world(run, "尸劫来历 · 调查与出路", result)
		"crisis":
			var result := Crisis.poll(run)
			if result != "": Director.note_choice(run, "风声与危机", result)


## 门洞与其两端通路在旧布局中可能已有家具。
static func _side_passage_blocked(run: Dictionary) -> bool:
	for f in run.get("furniture", []):
		if str(f.get("floor", "courtyard")) != "courtyard":
			continue
		if Home.rect_of(str(f.id), float(f.x), float(f.z), int(f.rot)).intersects(Home.SIDE_PASSAGE):
			return true
	return false


## 侧院每一阶段都经同一个入口：施工中断后保留已备材料，重新投入工时。
static func expansion_block(run: Dictionary) -> String:
	var current := Expansion.stage(run)
	if current == "complete":
		return "侧院已经建好。"
	if not run.get("fight", {}).is_empty() or in_night(run):
		return "夜袭期间不能扩建侧院。"
	var energy := 5 if current == "survey" else (8 if current == "ready" else 0)
	var err := can_act(run, energy)
	if err != "":
		return err
	if current == "ready" and _side_passage_blocked(run):
		return "侧院通路有家具，先挪开再施工。"
	if current == "cleared" and not Inv.has_all(run.home, Expansion.COST):
		return "备料不足（%s）。" % Data.describe_items(Expansion.COST)
	return ""


static func act_expansion(run: Dictionary) -> String:
	var err := expansion_block(run)
	if err != "":
		return err
	match Expansion.stage(run):
		"survey":
			_start(run, "expansion_clear")
			State.note(run, "开始查勘并清理东侧空地。")
		"cleared":
			Inv.take_all(run.home, Expansion.COST)
			run["expansion"] = {"stage": "ready"}
			State.note(run, "侧院备好了%s，尚未施工。" % Data.describe_items(Expansion.COST))
		"ready":
			_start(run, "expansion_build")
			State.note(run, "开始施工东侧小院。")
	return ""


## 空间切换本身不增加设施收益，也不绕开全局时钟。
static func floor_block(run: Dictionary, id: String) -> String:
	if not id in ["courtyard", "cellar", "attic", "guest_zhou"]:
		return "没有这个空间。"
	if not Floors.unlocked(run, id):
		return "这个空间尚未开放。"
	if id == "guest_zhou" and (int(run.t) % DAY < EVENT_AT or int(run.t) % DAY >= DUSK_AT):
		return "老周只在白天 08:00–18:00 邀人进屋。"
	if Floors.current(run) != "courtyard" and id != "courtyard" and id != Floors.current(run):
		return "先回院里再前往另一处。"
	if not run.get("fight", {}).is_empty() or in_night(run):
		return "夜袭期间不能切换空间。"
	return can_act(run, 0, true)

static func change_floor(run: Dictionary, id: String) -> String:
	var err := floor_block(run, id)
	if err != "":
		return err
	run["home_floor"] = id
	return ""

## 已备材料与施工进度分开，打断后从头施工但不重复收费。
static func attic_block(run: Dictionary) -> String:
	if Floors.attic_stage(run) == "complete":
		return "阁楼已经建好。"
	if Floors.current(run) != "courtyard":
		return "先回院里再施工。"
	if not run.get("fight", {}).is_empty() or in_night(run):
		return "夜袭期间不能施工。"
	var err := can_act(run, 8 if Floors.attic_stage(run) == "ready" else 0)
	if err != "":
		return err
	if Floors.attic_stage(run) == "unprepared" and not Inv.has_all(run.home, Floors.ATTIC_COST):
		return "备料不足（%s）。" % Data.describe_items(Floors.ATTIC_COST)
	return ""

static func act_attic(run: Dictionary) -> String:
	var err := attic_block(run)
	if err != "":
		return err
	if Floors.attic_stage(run) == "unprepared":
		Inv.take_all(run.home, Floors.ATTIC_COST)
		run["attic"] = {"stage": "ready"}
		State.note(run, "阁楼已备好%s，尚未施工。" % Data.describe_items(Floors.ATTIC_COST))
	else:
		_start(run, "attic_build")
		State.note(run, "开始施工阁楼。")
	return ""


## 添置一件家具：先扣料，再花时间摆进去（摆在哪儿由界面点地面给）。
static func act_furnish(run: Dictionary, id: String, x: float, z: float, rot: int) -> String:
	var err := can_act(run, 6)
	if err != "":
		return err
	err = Home.place_block(run, id, x, z, rot)
	if err != "":
		return err
	var cost: Dictionary = Home.data(id).get("cost", {}).duplicate(true)
	Inv.take_all(run.home, cost)
	_start(run, "furnish", {"id": id, "x": x, "z": z, "rot": rot, "paid_cost": cost, "floor": Floors.current(run)})
	return ""


## 拆掉一件家具（退一半料，立刻完成）。
static func act_unfurnish(run: Dictionary, uid: int) -> String:
	var err := can_act(run, 4)
	if err != "":
		return err
	var f := Home.find(run, uid)
	if f.is_empty():
		return "找不到这件家具。"
	if Home.is_core(run, f):
		return "核心家具不能拆掉。"
	return Home.remove(run, uid)


static func craft_block(run: Dictionary, craft_id: String) -> String:
	if not Data.table("devices").crafts.has(craft_id): return "没有这项配方。"
	var c: Dictionary = Data.table("devices").crafts[craft_id]
	if c.has("identity"):
		var identity_block := Identity.craft_block(run, craft_id)
		if identity_block != "": return identity_block
		if float(run.get("attrs", {}).get("energy", 0.0)) < int(ACTIONS.craft[2]): return "精力不足，身份配方需要%d。" % int(ACTIONS.craft[2])
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


static func water_block(run: Dictionary) -> String:
	var err := can_act(run, 2)
	if err != "":
		return err
	err = Crisis.well_block(run)
	if err != "": return err
	if run.well_used:
		return "今天已经打过水了。"
	return ""


static func draw_water(run: Dictionary) -> String:
	crisis_refresh(run)
	var err := water_block(run)
	if err != "": return err
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


static func search(run: Dictionary, idx: int, option_id := "") -> Dictionary:
	if run.explore.is_empty() or run.explore.get("curfew_due", false) or blocked(run) or is_busy(run) or run.sleeping or not run.fight.is_empty():
		return {}
	if Expedition.target_locked(run, idx):
		return {"blocked": "道路被机关封住；先查找两处线索，再解开机关。"}
	var prepaid := false
	var reserved_gain := -1
	if option_id == "site":
		if idx < 0 or idx >= run.explore.get("spots", []).size() or run.explore.spots[idx].get("done", false): return {}
		var selected := {}
		for option in Explore.site_options(run, idx):
			if option.id == option_id: selected = option; break
		if selected.is_empty(): return {"blocked": "这里不能使用地点特色。"}
		if str(selected.block) != "": return {"blocked": selected.block}
		var pid := str(run.explore.point)
		var minutes := int(Explore.SITE_MINUTES.get(pid, ACTIONS.search[1]))
		# 先预留按出发时状态计算的危险，再推进时间；事件打断时不产生任何成果。
		if pid != "city_god": reserved_gain = Explore.exposure_gain(run, pid)
		var started := int(run.t)
		run["neighbor_searching"] = true
		var stop := advance(run, minutes)
		run.erase("neighbor_searching")
		if int(run.t) - started < minutes or run.get("phase", "") != "post" or run.explore.is_empty() or run.explore.get("curfew_due", false):
			return {"blocked": "现场行动被%s打断，已耗时%d分钟；未完成，也没有取得物资或效果。" % ["宵禁" if stop == "curfew" else "突发状况", int(run.t) - started]}
		prepaid = true
	var story_revision := int(Mainline.state(run).revision)
	var res := Explore.search(run, idx, option_id, reserved_gain)
	if int(Mainline.state(run).revision) != story_revision:
		Director.note_choice(run, "尸劫来历 · 实地行动", str(Mainline.state(run).last_result))
	if str(res.get("blocked", "")) != "": return res
	if not res.is_empty():
		State.add_attr(run, "energy", -float(ACTIONS.search[2]))
		# 特色行动已经推进完时间，受捕后的伤害不会再经过 advance 的死亡检查。
		if prepaid and res.get("caught", false):
			State.check_death(run, "搜寻时被尸群追上，没能逃回宅院。")
		if res.get("mainline", false):
			# Unlike ordinary searches, work now waits on the live clock. A fatal
			# immediate capture must settle death before yielding back to the UI.
			State.check_death(run, "外出调查时被尸群追上，没能逃回宅院。")
			return res
		if not prepaid:
			run["neighbor_searching"] = true
			advance(run, int(res.get("minutes", ACTIONS.search[1])))
			run.erase("neighbor_searching")
		Neighbor.poll(run)
	return res


## 机关行动先耗时，只有完整完成且仍在现场才结算结果。
static func _expedition_spend(run: Dictionary, minutes: int) -> String:
	var started := int(run.t)
	run["neighbor_searching"] = true
	var stop := advance(run, minutes)
	run.erase("neighbor_searching")
	if int(run.t) - started < minutes or run.get("phase", "") != "post" or run.get("explore", {}).is_empty() or run.explore.get("curfew_due", false) or run.explore.get("caught", false):
		return "行动被%s打断，已耗时%d分钟；未完成，没有取得成果。" % ["宵禁" if stop == "curfew" else "突发状况", int(run.t) - started]
	return ""


static func _expedition_available(run: Dictionary) -> String:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or Expedition.profile(str(ex.get("point", ""))).is_empty(): return "这里没有可调查的机关。"
	if ex.get("curfew_due", false) or ex.get("caught", false) or blocked(run) or is_busy(run) or run.get("sleeping", false) or not run.get("fight", {}).is_empty(): return "现在无法调查机关。"
	return ""


static func expedition_inspect(run: Dictionary, idx: int) -> Dictionary:
	var err := _expedition_available(run)
	if err != "": return {"blocked": err, "text": err}
	var profile := Expedition.profile(str(run.explore.point))
	if idx < 0 or idx >= profile.clues.size(): return {"blocked": "没有这条线索。", "text": "没有这条线索。"}
	var s := Expedition.state(run)
	if bool(s.clues[idx]): return {"text": str(profile.clues[idx].text)}
	err = _expedition_spend(run, int(profile.inspect_minutes))
	if err != "": return {"blocked": err, "text": err}
	s.clues[idx] = true
	return {"text": str(profile.clues[idx].text)}


## 现场行动被事件、宵禁或死亡打断时不提交任何成果。
static func site_journey_action(run: Dictionary, stage_id: String, choice_id: String) -> Dictionary:
	var err := _expedition_available(run)
	if err != "": return {"blocked": err, "text": err}
	var ex: Dictionary = run.explore
	if ex.get("only_investigate", false): return {"blocked": "这一趟只为查访，这里的东西还没缓过来。"}
	var selected := SiteJourney.choice(str(ex.point), stage_id, choice_id)
	if selected.is_empty(): return {"blocked": "没有这个现场行动。"}
	var s := SiteJourney.state(run)
	if s.completed.has(stage_id): return {"blocked": "这处已处理过。"}
	err = _expedition_spend(run, int(selected.minutes))
	if err != "": return {"blocked": err, "text": err}
	var result := SiteJourney.settle(run, stage_id, selected)
	if int(ex.exposure) >= Explore.EXPOSURE_MAX:
		Explore._caught(run, Data.table("map_points")[ex.point])
		State.check_death(run, "现场行动惊动尸群，没能逃回宅院。")
		result["caught"] = true
		result.text += " 尸群已经追来！"
	return result


static func site_journey_take(run: Dictionary, stage_id: String, item: String, amount: int) -> int:
	if blocked(run) or is_busy(run): return 0
	return SiteJourney.transfer(run, stage_id, item, amount, true)


static func site_journey_put_back(run: Dictionary, stage_id: String, item: String, amount: int) -> int:
	if blocked(run) or is_busy(run): return 0
	return SiteJourney.transfer(run, stage_id, item, amount, false)


static func expedition_answer(run: Dictionary, choice_id: String) -> Dictionary:
	var err := _expedition_available(run)
	if err != "": return {"blocked": err, "text": err, "unlocked": false}
	var pid := str(run.explore.point)
	var profile := Expedition.profile(pid)
	var s := Expedition.state(run)
	if bool(s.unlocked): return {"text": "机关已经打开。", "unlocked": true}
	if not bool(s.clues[0]) or not bool(s.clues[1]): return {"blocked": "先在现场找到两条线索。", "text": "先在现场找到两条线索。", "unlocked": false}
	var valid := false
	for choice in profile.choices:
		if str(choice.id) == choice_id: valid = true; break
	if not valid: return {"blocked": "无效的机关选择。", "text": "无效的机关选择。", "unlocked": false}
	err = _expedition_spend(run, int(profile.answer_minutes))
	if err != "": return {"blocked": err, "text": err, "unlocked": false}
	s.attempts = int(s.attempts) + 1
	if Expedition.correct(pid, choice_id):
		s.unlocked = true
		run.explore.notes.append("解开%s，通道打开。" % profile.title)
		return {"text": "机关松开，通道打开了。", "unlocked": true}
	var ex: Dictionary = run.explore
	var exposure_before := int(ex.exposure)
	ex.exposure = mini(Explore.EXPOSURE_MAX, int(ex.exposure) + int(profile.wrong_exposure))
	var exposure_added := int(ex.exposure) - exposure_before
	var caught := int(ex.exposure) >= Explore.EXPOSURE_MAX
	if caught:
		Explore._caught(run, Data.table("map_points")[pid])
		State.check_death(run, "解机关惊动尸群，没能逃回宅院。")
	var text := "机关没有打开，发出的声响让阳气外泄增加%d；%s" % [exposure_added, "尸群已经追来！" if caught else "可以再试。"]
	ex.notes.append(text)
	return {"text": text, "unlocked": false, "caught": caught}


## 回家：也要赶一个时辰的路。
static func finish_explore(run: Dictionary) -> Dictionary:
	if run.get("phase", "") != "post" or run.explore.is_empty():
		return {}
	if is_busy(run):
		return {} # Finish or actually interrupt field work before starting return travel.
	if run.pending_event != "":
		return {} # Resolve the pending event, including the opened cabinet, before leaving.
	var field_state: Dictionary = run.explore.duplicate(true)
	var summary := Explore.finish(run)
	if run.phase == "post":
		if Mainline.begin_return(run, field_state): return summary
		run["neighbor_travel"] = true
		advance(run, int(ACTIONS.travel[1]))
		run.erase("neighbor_travel")
		Neighbor.poll(run)
	return summary


# ---------- 不占时间 ----------

static func use_item(run: Dictionary, id: String) -> String:
	if run.phase != "post":
		return "现在不能用。"
	if Floors.current(run) == "guest_zhou":
		return "先回自家院里取用存货。"
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
