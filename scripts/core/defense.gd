extends RefCounted
## 尸潮夜袭：三面（院门 / 窗 / 院墙）× 三轮。
##
## 一晚分三轮（22:00 / 22:40 / 23:20），每轮僵尸按比例分到三面，三面各自比守力：
##   该面守力 = 装在这一面的守具 + 望楼 / 夜行 / 六丁六甲（三面都沾） + 阿黄（只守门）
##            + 亲守这一面时的自身武力
## 挡不住的漏怪砸这一面的耐久；这一面破了，之后每轮来的全部进院子伤人。
## 玩家在轮与轮之间修缮、布守具、贴符，或者提刀出门迎战（`sortie`）。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Mainline = preload("res://scripts/core/mainline.gd")

## 每漏进一只僵尸，这一面掉多少耐久：越往后尸群越凶（第 2 夜 6，第 20 夜 10）。
const LEAK_BASE := 5
const LEAK_STEP_DAYS := 4
const SURFACES := ["gate", "window", "wall"]
## 每轮之间隔多久（分钟）；尸潮在 22:00（当天第 960 分钟）开始
const WAVE_AT := 960
const ROUND_GAP := 40
const ENDLESS_MODS := [["horde"], ["armored"], ["dark", "pincer"], ["armored", "horde"]]
## 出门迎战的野战效率：武力 × 精力系数 × 1.5，再除以每只消耗。比守在家里低，但能主动削下一轮。
const FIELD_MUL := 1.5
const FIELD_HP_PER_KILL := 0.9
const FIELD_HP_BASE := 2


static func leak_damage(day: int) -> int:
	return LEAK_BASE + int((maxi(0, day) - 1) / LEAK_STEP_DAYS)


## 某一天会不会来尸潮、来多少。mul 是难度乘数（荒年更密、暖冬更稀）。
static func wave_for_day(day: int, mul := 1.0) -> Dictionary:
	var cfg: Dictionary = Data.table("waves")
	for w in cfg.waves:
		if int(w.day) == day:
			return _scaled(w, mul)
	var e: Dictionary = cfg.endless
	if day > State.STORY_DAYS and (day - State.STORY_DAYS) % int(e.every) == 0:
		var n := (day - State.STORY_DAYS) / int(e.every)
		return _scaled({"day": day, "count": int(e.base) + int(e.step) * (n - 1),
			"mods": ENDLESS_MODS[n % ENDLESS_MODS.size()]}, mul)
	return {}


## 本世实际尸潮：先应用难度和已完工主线；开夜后始终读取整夜锁定值。
static func wave_for_run(run: Dictionary, day: int) -> Dictionary:
	# Once a night has started, every caller observes that exact locked wave.
	var night: Dictionary = run.get("night", {})
	if not night.is_empty() and int(night.get("wave", {}).get("day", -1)) == day:
		return night.wave.duplicate(true)
	var base := wave_for_day(day, float(State.diff(run).wave_mul))
	if base.is_empty(): return {}
	var wave: Dictionary = base.duplicate(true)
	var effect := Mainline.wave_effect(run, day)
	for modifier in effect.get("remove_mods", []): wave.mods.erase(modifier)
	wave.count = maxi(1, int(round(float(wave.count) * float(effect.get("count_mul", 1.0)))))
	return wave


## 按难度乘数缩放尸潮数量；mods 里的 count_mul 之后还会再乘一次，别在这里重复算。
static func _scaled(w: Dictionary, mul: float) -> Dictionary:
	if is_equal_approx(mul, 1.0):
		return w
	var out: Dictionary = w.duplicate()
	out["count"] = maxi(1, int(round(float(w.count) * mul)))
	return out


static func mod_names(wave: Dictionary) -> String:
	var names := []
	for m in wave.get("mods", []):
		names.append(Data.table("waves").mods[m].name)
	return "、".join(names)


static func _count(wave: Dictionary) -> int:
	var c := float(wave.count)
	for m in wave.get("mods", []):
		c *= float(Data.table("waves").mods[m].get("count_mul", 1.0))
	return int(round(c))


static func _cost(wave: Dictionary) -> float:
	var c := 1.0
	for m in wave.get("mods", []):
		c *= float(Data.table("waves").mods[m].get("cost", 1.0))
	return c


static func _is_dark(wave: Dictionary) -> bool:
	for m in wave.get("mods", []):
		if Data.table("waves").mods[m].get("dark", false):
			return true
	return false


## 晨起时的预兆：今夜和明夜（有望楼再看一夜）。
static func forecast(run: Dictionary) -> Array:
	var out := []
	var horizon := 2 if State.has_facility(run, "watchtower") else 1
	for d in range(run.pday, run.pday + horizon + 1):
		var w := wave_for_run(run, d)
		if w.is_empty():
			continue
		var when := "今夜" if d == run.pday else ("明夜" if d == run.pday + 1 else "后夜")
		var omen: String = Data.table("waves").omen_plain
		if not w.mods.is_empty():
			omen = Data.table("waves").mods[w.mods[0]].omen
		var line := "%s尸潮。%s" % [when, omen]
		var intervention := str(Mainline.wave_effect(run, d).get("reason", ""))
		if intervention != "": line += "（%s）" % intervention
		if State.has_talent(run, "lingjue"):
			line += "（灵觉：约 %d 只）" % _count(w)
		out.append(line)
	return out


# ---------- 三面 ----------

static func surface_name(sid: String) -> String:
	return Data.table("waves").surfaces.get(sid, {}).get("name", sid)


static func surface_desc(sid: String) -> String:
	return Data.table("waves").surfaces.get(sid, {}).get("desc", "")


static func part_of(run: Dictionary, sid: String) -> Dictionary:
	match sid:
		"gate":
			return run.door
		"window":
			return run.window
	return run.get("wall", {"cur": 0, "max": 1})


static func is_broken(run: Dictionary, sid: String) -> bool:
	return int(part_of(run, sid).cur) <= 0


static func all_broken(run: Dictionary) -> bool:
	for sid in SURFACES:
		if not is_broken(run, sid):
			return false
	return true


# ---------- 分轮、分面 ----------

static func rounds() -> int:
	return Data.table("waves").rounds.size()


## 三轮各来多少只（按 rounds 比例分，余数给最后一轮）。
static func round_counts(wave: Dictionary) -> Array:
	var total := _count(wave)
	var w: Array = Data.table("waves").rounds
	var out := []
	var acc := 0
	for i in w.size():
		var n := int(round(total * float(w[i])))
		if i == w.size() - 1:
			n = total - acc
		acc += n
		out.append(maxi(0, n))
	return out


static func split_of(wave: Dictionary) -> Dictionary:
	var key := "default"
	for m in wave.get("mods", []):
		var k: String = Data.table("waves").mods[m].get("split", "")
		if k != "" and Data.table("waves").split.has(k):
			key = k
	return Data.table("waves").split[key]


## 第 idx 轮三面各来多少只（按最大余数分配，不会把零头全塞给院门）。
static func round_split(wave: Dictionary, idx: int) -> Dictionary:
	var counts := round_counts(wave)
	var n := int(counts[clampi(idx, 0, counts.size() - 1)])
	var sp := split_of(wave)
	var out := {}
	var rema := []
	var acc := 0
	for sid in SURFACES:
		var exact := float(n) * float(sp.get(sid, 0.0))
		out[sid] = int(floor(exact))
		acc += int(out[sid])
		rema.append([exact - floor(exact), sid])
	var left := n - acc
	rema.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var i := 0
	while left > 0 and rema.size() > 0:
		var sid: String = rema[i % rema.size()][1]
		out[sid] = int(out[sid]) + 1
		left -= 1
		i += 1
	return out


static func round_minute(idx: int) -> int:
	return WAVE_AT + ROUND_GAP * idx


# ---------- 守力 ----------

static func device_power_on(run: Dictionary, sid: String) -> float:
	var p := 0.0
	for d in run.devices:
		var dev: Dictionary = Data.table("devices").devices.get(d.id, {})
		var on: String = dev.get("surface", "*")
		if on == "*" or on == sid:
			p += float(dev.get("power", 0))
	return p


## 这一面的守力明细（只读，不扣东西）。
static func surface_power(run: Dictionary, sid: String) -> Dictionary:
	var lines := []
	var devices := device_power_on(run, sid)
	if devices > 0:
		lines.append(["守具", devices])
	var extra := 0.0
	if State.has_facility(run, "watchtower"):
		extra += 2
		lines.append(["望楼", 2])
	if State.is_role(run, "watchman"):
		extra += 2
		lines.append(["夜行", 2])
	if State.has_buff(run, "guard_plus"):
		extra += 4
		lines.append(["六丁六甲", 4])
	if sid == "gate" and State.flag(run, "dog"):
		extra += 3
		lines.append(["阿黄", 3])
	var charm := float(run.get("night", {}).get("charm", {}).get(sid, 0))
	if charm > 0:
		extra += charm
		lines.append(["符咒", charm])
	var self_power := 0.0
	if str(run.get("guard_spot", "")) == sid:
		self_power = State.fight(run) * (0.5 + State.attr(run, "energy") / 200.0)
		lines.append(["亲守", snappedf(self_power, 0.1)])
	var total := devices + extra + self_power
	# 手脚冻僵：体温低于 15 时握不稳刀
	if State.attr(run, "warmth") < 15:
		total *= 0.85
		lines.append(["手脚冻僵 ×0.85", 0])
	# 夜里点了灯，三面都看得清。两个乘数写在 data/waves.json 的 dark 里，
	# 调灯油值不值这个价只改数据，不用动代码。
	var moon: Dictionary = Data.table("waves").mods.dark
	if run.get("night", {}).get("lamp", false):
		var lit := float(moon.get("lit_mul", 1.1))
		total *= lit
		lines.append(["点灯 ×%.2f" % lit, 0])
	elif run.get("night", {}).get("dark_unlit", false):
		var unlit := float(moon.get("unlit_mul", 0.7))
		total *= unlit
		lines.append(["月黑无灯 ×%.2f" % unlit, 0])
	return {"total": total, "lines": lines}


## 全场（三面加起来）的守力，给 HUD 一个总览。
static func total_power(run: Dictionary) -> float:
	var t := 0.0
	for sid in SURFACES:
		t += float(surface_power(run, sid).total)
	return t


# ---------- 预测 ----------

## 一整夜三面各来多少、各能斩多少（用当前布防，不扣东西）。
static func preview_night(run: Dictionary, wave: Dictionary) -> Dictionary:
	var out := {}
	var total := _count(wave)
	var cost := _cost(wave)
	var counts := round_counts(wave)
	for sid in SURFACES:
		var n := 0
		for i in counts.size():
			n += int(round(int(counts[i]) * float(split_of(wave).get(sid, 0.0))))
		var p := float(surface_power(run, sid).total)
		var part := part_of(run, sid)
		var killed := mini(n, int(floor(p / cost)) * counts.size()) if n > 0 else 0
		out[sid] = {
			"name": surface_name(sid), "count": n, "power": snappedf(p, 0.1),
			"cur": int(part.cur), "max": int(part.max), "broken": int(part.cur) <= 0,
		}
	out["total"] = total
	return out


## 某一轮的逐面预测（给夜战面板用）。extra 是这一轮已经被迎战砍掉的数。
static func preview_round(run: Dictionary, wave: Dictionary, idx: int, extra := {}) -> Dictionary:
	var counts := round_split(wave, idx)
	var cut: Dictionary = run.get("night", {}).get("sortie", {})
	var cost := _cost(wave)
	var leak := leak_damage(int(run.pday))
	var out := {"surfaces": {}, "killed": 0, "enter": 0, "hp": 0}
	for sid in SURFACES:
		var n := int(counts[sid]) - int(cut.get(sid, 0)) - int(extra.get(sid, 0))
		n = maxi(0, n)
		var p := float(surface_power(run, sid).total)
		var part := part_of(run, sid)
		var broken: bool = int(part.cur) <= 0
		var killed := 0 if broken else mini(n, int(floor(p / cost)))
		var left := n - killed
		var dmg := 0 if broken else left * leak
		var enter := n if broken else 0
		var after := maxi(0, int(part.cur) - dmg)
		if not broken and after <= 0:
			enter = int(ceil(left * 0.5))
		elif not broken and after < int(part.max) * 0.25:
			enter = int(ceil(left * 0.25))
		out.surfaces[sid] = {
			"name": surface_name(sid), "count": n, "power": snappedf(p, 0.1),
			"killed": killed, "left": left, "dmg": dmg, "after": after,
			"enter": enter, "broken": broken,
		}
		out.killed = int(out.killed) + killed
		out.enter = int(out.enter) + enter
	out.hp = _inside_hp(int(out.enter))
	return out


static func _inside_hp(enter: int) -> int:
	return enter * 5 if enter > 0 else 0


# ---------- 夜里开打 ----------

## 22:00：点灯、记下今夜的波次，等第一轮结算。
static func start_night(run: Dictionary, wave: Dictionary) -> void:
	var dark := _is_dark(wave)
	var lamp := false
	if dark and not State.is_role(run, "watchman") and Inv.count(run.home, "lamp_oil") > 0:
		Inv.add(run.home, "lamp_oil", -1)
		lamp = true
		State.note(run, "点起灯油，院子里亮了一片。")
	run.night = {
		"round": 0, "rounds": rounds(), "wave": wave.duplicate(true), "lamp": lamp,
		"dark_unlit": dark and not lamp and not State.is_role(run, "watchman"),
		"reports": [], "total": _count(wave), "sortie": {}, "charm": {}, "acted": false, "done": false,
	}


## 结算下一轮，返回这一轮的战报。
static func next_round(run: Dictionary) -> Dictionary:
	if run.night.is_empty() or bool(run.night.done):
		return {}
	var idx := int(run.night.round)
	var rep := resolve_round(run, idx)
	run.night.reports.append(rep)
	run.night.round = idx + 1
	if int(run.night.round) >= int(run.night.rounds):
		run.night.done = true
	return rep


static func resolve_round(run: Dictionary, idx: int) -> Dictionary:
	var wave: Dictionary = run.night.wave
	var counts := round_split(wave, idx)
	var cost := _cost(wave)
	var leak := leak_damage(int(run.pday))
	var rep := {
		"round": idx, "name": mod_names(wave), "count": 0, "killed": 0, "left": 0,
		"enter": 0, "hp_loss": 0, "poisoned": false, "broke": [], "breached": false,
		"surfaces": {}, "live_gate": 0,
	}
	for sid in SURFACES:
		var n: int = maxi(0, int(counts[sid]) - int(run.night.sortie.get(sid, 0)))
		var p := surface_power(run, sid)
		var part := part_of(run, sid)
		var s := {"name": surface_name(sid), "count": n, "power": snappedf(float(p.total), 0.1),
			"killed": 0, "left": n, "dmg": 0, "enter": 0, "broken": int(part.cur) <= 0}
		if sid == "gate" and bool(run.get("door_open", false)):
			# 门开着：这一面不结算，人直接进来（由 NightFight 在场上处理）
			s.left = n
			rep.live_gate = int(rep.live_gate) + n
		elif int(part.cur) <= 0:
			# 这一面昨夜就破了：今夜来的全进院子
			s.enter = n
		else:
			var killed := mini(n, int(floor(float(p.total) / cost)))
			var left := n - killed
			var dmg := left * leak
			s.killed = killed
			s.left = left
			s.dmg = dmg
			part.cur = maxi(0, int(part.cur) - dmg)
			if int(part.cur) <= 0:
				s.broken = true
				s.enter = int(ceil(left * 0.5))
				rep.broke.append(sid)
			elif int(part.cur) < int(part.max) * 0.25:
				s.enter = int(ceil(left * 0.25))
		rep.surfaces[sid] = s
		rep.count = int(rep.count) + n
		rep.killed = int(rep.killed) + int(s.killed)
		rep.left = int(rep.left) + int(s.left)
		rep.enter = int(rep.enter) + int(s.enter)
	rep.breached = not rep.broke.is_empty()
	# 进院子的咬人
	if int(rep.enter) > 0:
		var hp := _inside_hp(int(rep.enter))
		if State.has_buff(run, "ward"):
			hp = int(hp / 2.0)
		State.add_attr(run, "hp", -hp)
		rep.hp_loss = hp
		var chance := 0.10 + 0.015 * int(rep.enter)
		if State.is_role(run, "herbalist"):
			chance *= 0.5
		if not run.plague and Rng.chance(run, chance):
			run.plague = true
			rep.poisoned = true
	run.kills += int(rep.killed)
	run.today["kills"] = int(run.today.get("kills", 0)) + int(rep.killed)
	if int(rep.killed) > 0:
		State.add_xp(run, "guard", int(int(rep.killed) / 4.0) + 1)
	State.note(run, _round_text(rep))
	State.check_death(run, "尸潮破门，死在第 %d 夜。" % run.pday)
	run.night.sortie = {}
	return rep


static func _round_text(rep: Dictionary) -> String:
	var text := "第 %d 轮：来 %d 只，斩 %d 只。" % [int(rep.round) + 1, int(rep.count), int(rep.killed)]
	if not rep.broke.is_empty():
		var names := []
		for sid in rep.broke:
			names.append(surface_name(sid))
		text += "%s被撞破了！" % "、".join(names)
	if int(rep.enter) > 0:
		text += "进院 %d 只，气血 -%d。" % [int(rep.enter), int(rep.hp_loss)]
	elif int(rep.left) > 0:
		text += "剩下的砸在墙上。"
	else:
		text += "一只也没放进来。"
	if rep.poisoned:
		text += "被抓伤，染上尸毒。"
	return text


## 天亮前收尾：守具磨损、汇总成一份总战报（给战报弹窗）。
static func finish_night(run: Dictionary) -> Dictionary:
	if run.night.is_empty():
		return {}
	var kept := []
	var worn := []
	for d in run.devices:
		d.dur = int(d.dur) - 1
		if int(d.dur) > 0:
			kept.append(d)
		else:
			worn.append(Data.table("devices").devices[d.id].name)
	run.devices = kept
	var killed := 0
	var enter := 0
	var hp := 0
	var rounds := []
	var broke := []
	var poisoned := false
	for rep in run.night.reports:
		killed += int(rep.killed)
		enter += int(rep.enter)
		hp += int(rep.hp_loss)
		rounds.append(rep)
		poisoned = poisoned or bool(rep.poisoned)
		for sid in rep.broke:
			if not sid in broke:
				broke.append(sid)
	var total := int(run.night.get("total", 0))
	var report := {
		"name": mod_names(run.night.wave), "count": total, "killed": killed,
		"left": total - killed, "enter": enter, "hp_loss": hp, "poisoned": poisoned,
		"breached": not broke.is_empty(), "broke": broke, "rounds": rounds,
		"worn": worn, "posture": "三面守夜" if not broke.is_empty() else "三面守夜·未破",
		"lamp": bool(run.night.get("lamp", false)), "cost": _cost(run.night.wave),
		"power": snappedf(total_power(run), 0.1), "lines": [],
		"leak": leak_damage(int(run.pday)), "door_dmg": 0, "win_dmg": 0,
		"cracked": false, "broken": worn, "level_up": "",
	}
	run.night = {}
	if not State.check_death(run, "死在第 %d 夜。" % run.pday):
		run.waves_survived += 1
	return report


# ---------- 轮间操作 ----------

static func mend_minutes(run: Dictionary) -> int:
	return maxi(12, 25 - 2 * State.prof_level(run, "build"))


static func mend_amount(run: Dictionary) -> int:
	return 40 + 5 * State.prof_level(run, "build")


static func mend_block(run: Dictionary, sid: String) -> String:
	var part := part_of(run, sid)
	if int(part.cur) >= int(part.max):
		return "完好的"
	if Inv.count(run.home, "wood") <= 0 and Inv.count(run.home, "firewood") < 2:
		return "没有木料"
	return ""


## 扣修缮的材料。sid 是"哪一面"（gate / window / wall），要用来记院门修过几次——
## 誓约「不修门」查的就是这个数，所以**所有修门的路子都必须走这里**，
## 否则夜战稳守的自动修缮会绕过计数，誓约被误判成"守住了"。
static func pay_mend(run: Dictionary, sid := "") -> void:
	if Inv.count(run.home, "wood") > 0:
		Inv.add(run.home, "wood", -1)
	else:
		Inv.add(run.home, "firewood", -2)
	if sid == "gate":
		var t: Dictionary = State.tally(run)
		t.repair_door = int(t.get("repair_door", 0)) + 1


## 贴符 / 撒糯米：不占时间，立刻给这一面加守力，只算今夜。
static func charm_cost(id: String) -> Dictionary:
	match id:
		"talisman":
			return {"talisman": 1}
		"glutinous":
			return {"glutinous": 1}
		"dog_blood":
			return {"dog_blood": 1}
	return {}


static func charm_power(id: String) -> float:
	match id:
		"talisman":
			return 8.0
		"glutinous":
			return 4.0
		"dog_blood":
			return 6.0
	return 0.0


static func charm_block(run: Dictionary, sid: String, id: String) -> String:
	var c := charm_cost(id)
	if c.is_empty():
		return "贴不了"
	if run.night.is_empty():
		return "现在不是夜里"
	if not Inv.has_all(run.home, c):
		return "没有%s" % Data.item_name(id)
	return ""


## 贴在某一面上：加的是「今夜这一面」的守力。
static func add_charm(run: Dictionary, sid: String, id: String) -> String:
	var err := charm_block(run, sid, id)
	if err != "":
		return err
	Inv.take_all(run.home, charm_cost(id))
	var ch: Dictionary = run.night.get("charm", {})
	ch[sid] = float(ch.get(sid, 0.0)) + charm_power(id)
	run.night.charm = ch
	State.note(run, "在%s上贴了%s，这一面守力 +%d。" % [surface_name(sid), Data.item_name(id), int(charm_power(id))])
	return ""


## 出门迎战：砍下一轮某面的几只，代价是气血和尸毒。
static func sortie(run: Dictionary, sid: String) -> Dictionary:
	var wave: Dictionary = run.night.wave
	var idx := int(run.night.round)
	if idx >= int(run.night.rounds):
		return {}
	var counts := round_split(wave, idx)
	var n := int(counts.get(sid, 0))
	if n <= 0:
		return {"kills": 0, "hp": 0, "plague": false, "text": "%s那边今夜没人来。" % surface_name(sid)}
	var power := State.fight(run) * (0.5 + State.attr(run, "energy") / 200.0) * FIELD_MUL
	var cost := _cost(wave) * 1.2
	var kills := mini(n, maxi(0, int(floor(power / cost))))
	run.night.sortie[sid] = int(run.night.sortie.get(sid, 0)) + kills
	var hp := int(ceil(kills * FIELD_HP_PER_KILL)) + FIELD_HP_BASE
	State.add_attr(run, "hp", -hp)
	State.add_attr(run, "energy", -8)
	var chance := 0.06 + 0.02 * kills
	if State.is_role(run, "herbalist"):
		chance *= 0.5
	var got := false
	if not run.plague and kills > 0 and Rng.chance(run, chance):
		run.plague = true
		got = true
	if kills > 0:
		run.today["merit"] = int(run.today.get("merit", 0)) + 1
	var text := "提刀出了院门，在%s外头砍翻 %d 只，气血 -%d。" % [surface_name(sid), kills, hp]
	if kills == 0:
		text = "提刀出去转了一圈，一只也没撞上，倒是冻得够呛，气血 -%d。" % hp
	if got:
		text += "被溅了一身黑血——染上尸毒了。"
	State.note(run, text)
	State.check_death(run, "出门迎战，死在第 %d 夜。" % run.pday)
	return {"kills": kills, "hp": hp, "plague": got, "text": text}


## 溃兵夜袭：人不怕符和糯米，只看门结不结实、你能不能打。
static func resolve_raid(run: Dictionary) -> Dictionary:
	var repelled: bool = int(run.door.cur) >= 60 or State.fight(run) >= 12
	var stolen := {}
	if repelled:
		run.door.cur = maxi(0, int(run.door.cur) - 20)
		State.add_attr(run, "hp", -4)
		State.note(run, "溃兵砸了半夜的门，没砸开，骂骂咧咧地走了。")
	else:
		run.door.cur = maxi(0, int(run.door.cur) - 15)
		State.add_attr(run, "hp", -10)
		var ratio := 0.15 if State.has_facility(run, "cellar") else 0.3
		for id in Inv.GRAINS + Inv.food_ids(run.home):
			var n := int(floor(Inv.count(run.home, id) * ratio))
			if n > 0:
				Inv.add(run.home, id, -n)
				stolen[id] = n
		State.note(run, "溃兵破门而入，抢走了%s。" % (Data.describe_items(stolen) if not stolen.is_empty() else "一些零碎"))
	State.check_death(run, "死于溃兵刀下。")
	return {"repelled": repelled, "stolen": stolen}
