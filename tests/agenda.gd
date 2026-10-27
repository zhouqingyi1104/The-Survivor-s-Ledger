extends SceneTree
## 今日差事的无界面测试：单子够不够满、做不做得完、做了有没有用、空闲有没有真的少。
## 运行：godot --headless --path . --script res://tests/agenda.gd
##   AGENDA_GAMES=24 每臂多跑几局看噪声；AGENDA_VERBOSE=1 打印每局收局时的余粮余柴与失血构成。
##
## 这批的出发点：玩家一天里大半时间在发呆（docs/27 量过：醒着 850 分钟里 600 多分钟干等）。
## 验收的三件事都在这里断言：
##   一、每天卯时排出的差事 ≥ 醒着可用时间的 1.5 倍（二十四个钟头的事，十六个钟头做）——穷的时候也一样；
##   二、做了真有用（柴、水、守、暖、工程都落到状态里），做不了时说清为什么；
##   三、同一个机器人带不带差事单各跑整局：带了以后白天干等大幅减少，而且单子做不完（真的要取舍）。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Agenda = preload("res://scripts/core/agenda.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Events = preload("res://scripts/core/events.gd")

## 机器人开局的家当：照 sim_test 的购物单折算，省掉备劫三日的走店。
const KIT := {"rice": 6, "millet": 3, "flatbread": 8, "firewood": 8, "charcoal": 3, "lamp_oil": 1,
	"glutinous": 2, "talisman": 3, "ink_line": 1, "plague_powder": 2, "salve": 1, "mugwort": 2,
	"seed_cabbage": 2, "seed_radish": 1, "seed_chive": 1, "jerky": 1, "egg": 4, "wood": 3, "nails": 2, "water": 4}
const ROLES := ["scholar", "escort", "herbalist", "watchman"]

## 机器人对照每臂几局（环境变量 AGENDA_GAMES 可以加大，看噪声）
var bot_games := 8

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	if OS.get_environment("AGENDA_GAMES") != "":
		bot_games = maxi(4, int(OS.get_environment("AGENDA_GAMES")))
	test_constants()
	test_overload()
	test_deterministic()
	test_chore_flow()
	test_blocks()
	test_projects()
	test_warmth()
	test_shore()
	test_old_save()
	test_bot()
	print("[agenda] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、常量跟 Post 对得上 ----------

func test_constants() -> void:
	check(Agenda.DAY_END == Post.WAVE_AT, "收工时刻 %d 不等于尸潮 22:00（%d）" % [Agenda.DAY_END, Post.WAVE_AT])
	check(Agenda.TARGET == 1440, "1.5 倍的十六个钟头应是 1440 分钟，算出 %d" % Agenda.TARGET)
	var run := _day()
	for d in [1, 6, 12, 18]:
		run.pday = d
		check(Agenda.cold(run) == Post.cold_of(run), "第 %d 日差事算的冷（%d）和 Post（%d）不一致" % [d, Agenda.cold(run), Post.cold_of(run)])
	for id in Data.table("chores"):
		var c: Dictionary = Data.table("chores")[id]
		check(int(c.get("minutes", 0)) > 0, "差事 %s 不花时间" % id)
		check(str(c.get("why", "")) != "", "差事 %s 没写为什么值得做" % id)
		check(Agenda.effect_text(str(id)) != "", "差事 %s 做了换不来任何东西" % id)
		check(c.get("spot", "") in ["shrine", "bed", "desk", "stove", "storage", "bench", "well", "garden", "gate"], "差事 %s 的去处不在院子里" % id)
		for k in c.get("cost", {}):
			check(not Data.item(str(k)).is_empty(), "差事 %s 扣的 %s 不是物品" % [id, k])
		for k in c.get("gain", {}):
			check(not Data.item(str(k)).is_empty(), "差事 %s 给的 %s 不是物品" % [id, k])


# ---------- 二、单子一定排满 1.5 倍 ----------

## 富的、穷的、穷到偏厦拆光工程做完的，二十天里每天都要排满。
## 穷的时候最容易发呆，所以穷的情形是这条断言的重点。
func test_overload() -> void:
	var worst := 99.0
	var worst_case := ""
	var cases := 0
	for role in ROLES:
		for kind in ["kit", "bare", "bare_spent"]:
			var run := _day(role, 7100 + ROLES.find(role))
			if kind == "kit":
				Inv.add_all(run.home, KIT)
			else:
				run.home = {}
			if kind == "bare_spent":
				for id in Data.table("chores"):
					if Agenda.cap(str(id)) > 0:
						Agenda.state(run).used[str(id)] = Agenda.cap(str(id))
			for d in range(1, State.STORY_DAYS + 1):
				run.pday = d
				run.t = (d - 1) * Post.DAY
				run.well_used = false
				run.buffs = []
				run.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
				Agenda.build(run, Post.agenda_offers(run))
				var planned := int(Agenda.state(run).planned)
				var ratio := float(planned) / float(Agenda.DAY_END)
				cases += 1
				if ratio < worst:
					worst = ratio
					worst_case = "%s/%s/第%d日" % [role, kind, d]
				check(planned >= Agenda.TARGET, "%s %s 第 %d 日只排了 %d 分钟（< %d）" % [role, kind, d, planned, Agenda.TARGET])
				var s := Agenda.summary(run)
				check(int(s.need) == planned, "%s %s 第 %d 日卯时待办 %d 不等于排单 %d" % [role, kind, d, int(s.need), planned])
				check(int(s.over) >= planned - Agenda.DAY_END, "卯时算出的要放下的时长不对：%d" % int(s.over))
	print("[agenda] 排单 %d 种情形，最紧的一天也有 %.2f 倍（%s）" % [cases, worst, worst_case])


func test_deterministic() -> void:
	var a := _day("escort", 8800)
	var b := _day("escort", 8800)
	var rng_before := int(a.rng_n)
	Agenda.build(a, Post.agenda_offers(a))
	Agenda.build(b, Post.agenda_offers(b))
	check(int(a.rng_n) == rng_before, "排差事动了局里的随机数计数（%d → %d），会改掉事件和搜寻的结果" % [rng_before, int(a.rng_n)])
	check(_ids(a) == _ids(b), "同种子同一天排出的单子不一样")
	var c := _day("escort", 8801)
	Agenda.build(c, Post.agenda_offers(c))
	a.pday = 2
	a.t = Post.DAY
	Agenda.build(a, Post.agenda_offers(a))
	check(_ids(a) != _ids(b) or _ids(c) != _ids(b), "换种子、换日子，单子一模一样——等于没有抽签")


# ---------- 三、做一件差事 ----------

func test_chore_flow() -> void:
	var run := _day()
	var idx := _force(run, "gather_twigs")
	var wood0 := Inv.count(run.home, "firewood")
	var energy0 := float(run.attrs.energy)
	var need0 := int(Agenda.summary(run).need)
	var span := int(Agenda.chore("gather_twigs").minutes)
	check(Post.act_chore(run, idx) == "", "扫拾枯枝开不了工")
	check(Post.is_busy(run) and str(run.busy.kind) == "chore", "开工后没有在忙")
	check(float(run.attrs.energy) < energy0, "开工没扣精力")
	check(Agenda.status(run, idx) == "busy", "开工后单子上不是「正在做」：%s" % Agenda.status(run, idx))
	check(Post.act_chore(run, idx) != "", "正在做的差事还能再开一次")
	_finish(run)
	check(Inv.count(run.home, "firewood") == wood0 + 1, "枯枝拾完柴没多：%d → %d" % [wood0, Inv.count(run.home, "firewood")])
	check(Agenda.status(run, idx) == "done", "做完了单子上没勾掉：%s" % Agenda.status(run, idx))
	check(Post.act_chore(run, idx) != "", "做过的差事还能再做")
	check(int(Agenda.summary(run).need) == need0 - span, "做完 %d 分钟的事，待办没少这么多：%d → %d" % [span, need0, int(Agenda.summary(run).need)])
	check(Agenda.summary(run).done == 1, "做完一件，账上没记")
	# 既有行动：打了水，单子上的「打水」也算办了
	var w := _force_builtin(run, "water")
	check(Agenda.status(run, w) == "open", "打水还没做就算办了")
	Post.draw_water(run)
	_finish(run)
	check(Agenda.status(run, w) == "done", "打过水了，单子上的打水没勾掉")
	# 外出两趟：跑一趟只勾第一趟
	var e1 := _force_builtin(run, "explore")
	var e2 := _force_builtin(run, "explore2")
	run.today.actions.append("explore")
	check(Agenda.status(run, e1) == "done" and Agenda.status(run, e2) == "open", "只跑了一趟，第二趟却也勾掉了")
	run.today.actions.append("explore")
	check(Agenda.status(run, e2) == "done", "跑了两趟，第二趟没勾掉")


func test_blocks() -> void:
	var run := _day()
	run.home = {}
	var chop := _force(run, "chop_wood")
	check(Agenda.block(run, chop).begins_with("缺"), "没木料还能劈柴：%s" % Agenda.block(run, chop))
	check(Post.act_chore(run, chop) != "", "没木料却开了工")
	# 过了时辰：上墙望风要午时前
	var watch := _force(run, "watch_street")
	run.t = 361
	check(Agenda.status(run, watch) == "late", "12:01 还能上墙望风：%s" % Agenda.status(run, watch))
	check(int(Agenda.summary(run).need) < int(Agenda.state(run).planned), "过了时辰的事还算在待办里")
	# 尸潮夜：22:00 会打断手上的活，做不完就不让开工
	var night := _day()
	night.pday = 2
	night.t = Post.DAY + 900
	check(Agenda.wave_tonight(night), "第 2 夜应有尸潮（测试前提）")
	var kang := _force(night, "build_kang")
	check(Agenda.block(night, kang) == "亥时尸潮前做不完", "21:00 开两个钟头的工没拦住：%s" % Agenda.block(night, kang))
	night.t = Post.DAY + 600
	check(Agenda.block(night, kang) == "", "16:00 开两个钟头的工被拦了：%s" % Agenda.block(night, kang))
	# 夜战还没打完：不许开工（会把夜里的动作卡死）
	night.t = Post.DAY + 980
	night.night = {"wave": {}, "round": 0, "rounds": 3, "sortie": {}, "done": false}
	check(Agenda.block(night, kang) == "尸潮还在街上", "夜战中还能开工：%s" % Agenda.block(night, kang))
	night.night = {}
	# 天亮会把活打断：05:00 开两个钟头的工要拦
	var dawn := _day()
	dawn.t = 1380
	var dk := _force(dawn, "build_kang")
	check(Agenda.block(dawn, dk) == "天亮前做不完", "05:00 开两个钟头的工没拦住：%s" % Agenda.block(dawn, dk))
	night.t = Post.DAY + 600
	# 已经有了的效用不重复给
	var sharp := _force(night, "sharpen")
	night.buffs.append("guard_plus")
	check(Agenda.block(night, sharp) != "", "已有六丁六甲还能再磨刀叠守力")
	# 精力不够由 Post.can_act 拦
	var tired := _day()
	tired.attrs.energy = 2.0
	var practice := _force(tired, "practice_blade")
	check(Post.act_chore(tired, practice) != "", "精力 2 还能练刀")


# ---------- 四、工程：分几回做完，落下永久的好处 ----------

func test_projects() -> void:
	var run := _day()
	var wall_max := int(run.wall.max)
	for k in 4:
		var idx := _force(run, "raise_wall")
		run.attrs.energy = 100.0
		check(Post.act_chore(run, idx) == "", "加高院墙第 %d 回开不了工" % (k + 1))
		_finish(run)
		if k < 3:
			check(int(run.wall.max) == wall_max, "院墙第 %d 回就加高了" % (k + 1))
	check(int(run.wall.max) == wall_max + 30, "四回码完院墙上限没 +30：%d → %d" % [wall_max, int(run.wall.max)])
	check(not Agenda.eligible(run, "raise_wall"), "院墙加完了还排进单子")
	var spent := _force(run, "raise_wall")
	check(Agenda.status(run, spent) == "spent", "完工的工程还能接着做：%s" % Agenda.status(run, spent))
	# 火炕盘成后睡着时少掉体温
	var a := _cold_night()
	var b := _cold_night()
	b.flags["kang"] = true
	a.sleeping = true
	b.sleeping = true
	Post.advance(a, 120)
	Post.advance(b, 120)
	check(float(b.attrs.warmth) > float(a.attrs.warmth), "盘了火炕睡着时体温没掉得更慢：%.1f vs %.1f" % [float(b.attrs.warmth), float(a.attrs.warmth)])


# ---------- 五、絮棉衣：今夜体温少掉四成 ----------

func test_warmth() -> void:
	var a := _cold_night()
	var b := _cold_night()
	b.buffs.append("padded")
	var w0 := float(a.attrs.warmth)
	Post.advance(a, 120)
	Post.advance(b, 120)
	var lost_a := w0 - float(a.attrs.warmth)
	var lost_b := w0 - float(b.attrs.warmth)
	check(lost_a > 0.0, "冷夜没生火体温却没掉（测试前提）")
	check(absf(lost_b - lost_a * Agenda.PADDED_COLD) < 0.5, "絮棉衣后掉温 %.1f，应为不絮的 %.0f%%（%.1f）" % [lost_b, Agenda.PADDED_COLD * 100, lost_a * Agenda.PADDED_COLD])


func test_shore() -> void:
	var run := _day()
	run.window.cur = 10
	var idx := _force(run, "shore_up")
	check(Post.act_chore(run, idx) == "", "窗破了却顶不了门")
	_finish(run)
	check(int(run.window.cur) == 30, "拆杂物没顶到最破的窗上：%d" % int(run.window.cur))


## 老存档没有 agenda：进宅院时现排，不报错。
func test_old_save() -> void:
	var run := _day()
	run.erase("agenda")
	Post.ensure_agenda(run)
	check(int(Agenda.state(run).day) == int(run.pday), "老存档进宅院没现排今天的单子")
	check(int(Agenda.state(run).planned) >= Agenda.TARGET, "老存档现排的单子不够满")
	var pre := State.new_run("scholar", State.new_meta(), 1)
	Post.ensure_agenda(pre)
	check(Agenda.state(pre).items.is_empty(), "备劫阶段不该排差事")


# ---------- 六、机器人对照：带不带差事单 ----------

## 同一个机器人（照 sim_test 的打法）、同种子各跑整局。只看 6:00–22:00 的干等。
func test_bot() -> void:
	# 三臂：原打法 / 原打法但一天跑两趟（既有内容用足）/ 再加差事单。
	# 中间那臂把"跑两趟"和"差事"分开：胜率要是只靠多跑一趟涨的，就不该算到差事头上。
	var arms := {}
	for arm in ["base", "trips", "agenda"]:
		var agg := {"idle": 0, "days": 0, "wins": 0, "games": 0, "planned": 0, "done": 0, "full_days": 0, "agenda_days": 0,
			"chores": 0, "firewood": 0, "water": 0, "hp": 0}
		for k in bot_games:
			var r := play(ROLES[k % ROLES.size()], 9100 + k, arm)
			for key in ["idle", "days", "planned", "done", "full_days", "agenda_days", "chores", "firewood", "water", "hp"]:
				agg[key] = int(agg[key]) + int(r[key])
			agg.games = int(agg.games) + 1
			if bool(r.win):
				agg.wins = int(agg.wins) + 1
		arms[arm] = agg
		var n := float(maxi(1, int(agg.days)))
		var g := float(maxi(1, int(agg.games)))
		print("[agenda] %s：%d 局劫满 %d，共 %d 天；白天干等 %.0f 分/天；差事 %.1f 件/天；排单 %.0f 分/天，做掉 %.0f 分/天（%.0f%%）；做完整张单 %d/%d 天；收局均余 柴 %.1f 水 %.1f 气血 %.0f" % [
			{"base": "原打法", "trips": "原打法+跑两趟", "agenda": "带差事单"}[arm], int(agg.games), int(agg.wins), int(agg.days),
			float(agg.idle) / n, float(agg.chores) / n, float(agg.planned) / maxf(1.0, float(agg.agenda_days)),
			float(agg.done) / maxf(1.0, float(agg.agenda_days)),
			100.0 * float(agg.done) / maxf(1.0, float(agg.planned)), int(agg.full_days), int(agg.agenda_days),
			float(agg.firewood) / g, float(agg.water) / g, float(agg.hp) / g])
	var base: Dictionary = arms["base"]
	var with: Dictionary = arms["agenda"]
	var idle0 := float(base.idle) / maxf(1.0, float(base.days))
	var idle1 := float(with.idle) / maxf(1.0, float(with.days))
	check(idle0 > 300.0, "原打法白天干等只有 %.0f 分/天——对照前提不成立（docs/27 量的是 600 左右）" % idle0)
	check(idle1 <= idle0 * 0.35, "带了差事单白天干等 %.0f 分/天，没降到原来（%.0f）的三成五以下" % [idle1, idle0])
	check(int(with.chores) > 0, "机器人一件差事都没做——单子做不了")
	check(int(with.full_days) * 5 <= int(with.agenda_days), "做完整张单的日子 %d/%d 太多：单子没有逼人取舍" % [int(with.full_days), int(with.agenda_days)])
	check(float(with.done) < float(with.planned) * 0.85, "一天能做掉单子的 %.0f%%：做得完就不用挑" % (100.0 * float(with.done) / maxf(1.0, float(with.planned))))
	check(int(with.wins) >= int(base.wins) - 1, "带差事单反而死得多：劫满 %d vs %d" % [int(with.wins), int(base.wins)])


func play(role: String, seed_value: int, arm: String) -> Dictionary:
	var use_agenda := arm == "agenda"
	var two_trips := arm != "base"
	var run := State.new_run(role, State.new_meta(), seed_value)
	Inv.add_all(run.home, KIT)
	Pre.start_disaster(run)
	var out := {"idle": 0, "days": 0, "planned": 0, "done": 0, "full_days": 0, "agenda_days": 0, "chores": 0, "win": false,
		"firewood": 0, "water": 0, "hp": 0}
	var guard := 0
	while run.phase == "post" and guard < 8000:
		guard += 1
		if run.pending_event != "":
			var e: Dictionary = Events.entry(run)
			var pick: int = e.choices.size() - 1
			for idx in e.choices.size():
				if Events.choice_ok(run, e.choices[idx]):
					pick = idx
					break
			Events.choose(run, pick)
			continue
		if run.plan_due:
			Post.choose_policy(run, "hold")
			continue
		if Post.in_night(run) and Post.day_minute(run) >= Defense.round_minute(int(run.night.round)):
			Post.nod_round(run)
			continue
		if run.wave_due:
			Post.resolve_wave(run)
			continue
		if not run.wave_report.is_empty():
			Post.ack_wave(run)
			continue
		if run.dawn_due:
			_tally(run, out)
			Post.ack_dawn(run)
			continue
		run.raid_report = {}
		if not run.explore.is_empty():
			Post.finish_explore(run)
			continue
		_eat(run)
		var started := false
		if Post.can_act(run, 0) == "":
			started = _choose(run, use_agenda, two_trips, out)
		if Post.is_busy(run):
			Post.advance(run, maxi(10, int(run.busy.end) - int(run.t)))
		elif run.sleeping:
			Post.advance(run, 60)
		elif not started:
			if Post.day_minute(run) < Agenda.DAY_END:
				out.idle = int(out.idle) + 10
			Post.advance(run, 10)
	out.win = run.phase == "ending"
	out.firewood = Inv.count(run.home, "firewood") + 2 * Inv.count(run.home, "charcoal")
	out.water = Inv.count(run.home, "water")
	out.hp = State.attr(run, "hp")
	if OS.get_environment("AGENDA_VERBOSE") != "":
		print("  %s %s seed=%d 第%d日 %s 气血%d 柴%d 炭%d 水%d 粮%d 门%d/%d 窗%d/%d 墙%d/%d 失血%s" % [
			arm, role, seed_value, int(run.pday), str(run.death_cause),
			State.attr(run, "hp"), Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal"), Inv.count(run.home, "water"),
			Inv.total(run.home, Inv.GRAINS), int(run.door.cur), int(run.door.max), int(run.window.cur), int(run.window.max),
			int(run.wall.cur), int(run.wall.max), str(run.get("hp_log", {}))])
	return out


## 天亮结算前，把刚过去这一天的单子记进账。
func _tally(run: Dictionary, out: Dictionary) -> void:
	out.days = int(out.days) + 1
	var s := Agenda.state(run)
	if int(s.day) != int(run.pday) or s.items.is_empty():
		return
	var done := 0
	for idx in s.items.size():
		if Agenda.status(run, idx) == "done":
			done += int(Agenda.spec(Agenda.item(run, idx)).get("minutes", 0))
	out.agenda_days = int(out.agenda_days) + 1
	out.planned = int(out.planned) + int(s.planned)
	out.done = int(out.done) + done
	if done >= int(s.planned):
		out.full_days = int(out.full_days) + 1


func _eat(run: Dictionary) -> void:
	var guard := 0
	while State.attr(run, "water") < 60 and Inv.count(run.home, "water") > 0 and guard < 5:
		Post.use_item(run, "water")
		guard += 1
	guard = 0
	while State.attr(run, "food") < 60 and guard < 5:
		var foods := Inv.food_ids(run.home)
		if foods.is_empty():
			for raw in ["cabbage", "radish", "chive"]:
				if Inv.count(run.home, raw) > 0:
					foods = [raw]
					break
		if foods.is_empty():
			break
		Post.use_item(run, foods[-1])
		guard += 1
	if run.plague and Inv.count(run.home, "plague_powder") > 0:
		Post.use_item(run, "plague_powder")
	if State.attr(run, "hp") < 50 and Inv.count(run.home, "salve") > 0:
		Post.use_item(run, "salve")


## sim_test 的白天打法，原样搬过来；带差事单时，原打法没事做了才去单子上挑。
func _choose(run: Dictionary, use_agenda: bool, two_trips: bool, out: Dictionary) -> bool:
	var m := Post.day_minute(run)
	var wave_tonight := Agenda.wave_tonight(run)
	if Post.is_night(run):
		if wave_tonight:
			for dev in ["talisman_wall", "blood_sill", "caltrop_field", "rice_scatter", "bagua_mirror"]:
				if Post.device_block(run, dev) == "":
					Post.act_build(run, dev)
			return use_agenda and _chore(run, out)
		if use_agenda and m < Agenda.DAY_END and _chore(run, out):
			return true
		return Post.sleep(run) == ""
	if State.attr(run, "energy") < 25:
		return Post.act_rest(run) == ""
	if not run.well_used and Post.draw_water(run) == "":
		return true
	var wave_soon := wave_tonight or not Defense.wave_for_day(run.pday + 1).is_empty()
	if wave_soon and int(run.door.cur) < int(run.door.max) - 30 and Inv.count(run.home, "wood") > 0:
		return Post.act_repair(run, "door") == ""
	if wave_soon and run.devices.size() < 3:
		for dev in ["peach_stake", "ink_line", "barricade"]:
			if Post.device_block(run, dev) == "":
				return Post.act_build(run, dev) == ""
	if Inv.total(run.home, Inv.food_ids(run.home)) < 4:
		for rid in ["fried_rice", "eight_treasure", "congee", "millet_cake", "egg_soup", "veg_soup", "rice_cake"]:
			if Post.recipe_block(run, rid) == "":
				return Post.act_cook(run, rid) == ""
	for idx in run.plots.size():
		if run.plots[idx].crop == "":
			for crop in ["radish", "cabbage", "chive"]:
				if Inv.count(run.home, Data.table("crops")[crop].seed) > 0:
					Post.plant(run, idx, crop)
					break
	var need_tend := false
	for plot in run.plots:
		if plot.crop != "" and (Post.crop_ripe(plot) or int(run.t) - int(plot.watered_t) > 600):
			need_tend = true
	if need_tend and "garden" not in run.today.actions:
		return Post.act_garden(run) == ""
	if Post.craft_block(run, "draw_talisman") == "":
		return Post.act_craft(run, "draw_talisman") == ""
	var trips: int = run.today.actions.count("explore")
	if (trips == 0 and m < 480) or (two_trips and trips == 1 and m < 600):
		if _explore(run):
			return true
	for book in Inv.ids_in_cat(run.home, "书"):
		if book not in run.read:
			return Post.act_read(run, book) == ""
	return use_agenda and _chore(run, out)


func _explore(run: Dictionary) -> bool:
	var best := ""
	for pid in Explore.visible_points(run):
		if Explore.point_block(run, pid) != "":
			continue
		if int(Data.table("map_points")[pid].danger) >= 4 and State.attr(run, "hp") < 70:
			continue
		best = pid
		break
	if best == "" or Post.act_explore(run, best) != "":
		return false
	for idx in run.explore.spots.size():
		if run.explore.is_empty() or run.explore.caught or int(run.explore.exposure) > 65 or Post.blocked(run):
			break
		Post.search(run, idx)
		if run.pending_event != "":
			return true
	if not run.explore.is_empty():
		Post.finish_explore(run)
	return true


## 单子上挑一件能做的差事（留 20 点精力垫底）。
func _chore(run: Dictionary, out: Dictionary) -> bool:
	for row in Agenda.rows(run):
		if str(row.kind) != "chore" or str(row.status) != "open" or str(row.block) != "":
			continue
		if State.attr(run, "energy") - int(row.energy) < 20:
			continue
		if Post.act_chore(run, int(row.idx)) == "":
			out.chores = int(out.chores) + 1
			return true
	return false


# ---------- 小工具 ----------

## 第一日 06:00 的干净局面。
func _day(role := "scholar", seed_value := 20261027) -> Dictionary:
	var run: Dictionary = State.new_run(role, State.new_meta(), seed_value)
	Pre.start_disaster(run)
	run.pday = maxi(1, int(run.pday))
	run.t = (int(run.pday) - 1) * Post.DAY
	run.pending_event = ""
	run.busy = {}
	run.night = {}
	run.fight = {}
	run.wave_due = false
	run.dawn_due = false
	run.wave_report = {}
	run.plan_due = false
	run.attrs.energy = 100.0
	return run


## 冷天（第 12 日冬至）的 20:00、没生火、醒着的局面。
func _cold_night() -> Dictionary:
	var run := _day()
	run.pday = 12
	run.t = 11 * Post.DAY + Post.HEAT_AT + 10
	run.heated = false
	run.attrs.warmth = 80.0
	run.home = {}
	return run


## 把手上的活做完：路上冒出的闲话、事件一律先搁下（这里只测差事本身）。
func _finish(run: Dictionary) -> void:
	var guard := 0
	while Post.is_busy(run) and guard < 20:
		guard += 1
		run.pending_event = ""
		Post.advance(run, maxi(1, int(run.busy.end) - int(run.t)))
	run.pending_event = ""


## 把某件差事放进今天的单子（不管抽没抽到），返回它的行号。
func _force(run: Dictionary, id: String) -> int:
	var s := Agenda.state(run)
	s.day = int(run.pday)
	s.items.append({"id": id, "kind": "chore", "done": false})
	return s.items.size() - 1


func _force_builtin(run: Dictionary, id: String) -> int:
	var s := Agenda.state(run)
	s.day = int(run.pday)
	s.items.append({"id": id, "kind": "builtin", "done": false})
	return s.items.size() - 1


func _ids(run: Dictionary) -> Array:
	return Agenda.state(run).items.map(func(it): return str(it.id))


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		return
	failures += 1
	push_error("断言失败：" + msg)
