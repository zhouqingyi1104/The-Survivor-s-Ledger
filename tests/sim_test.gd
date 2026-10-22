extends SceneTree
## 无界面整局模拟：用一个简单的机器人策略从备劫一路玩到死亡或劫满，检查不变量、打印平衡数据。
## 运行：godot --headless --path . --script res://tests/sim_test.gd

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Events = preload("res://scripts/core/events.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")

const SHOPPING := [
	["builder", ["door_bar", "water_vat", "window_board", "stove"]],
	["grocery", {"cart": 1, "firewood": 6, "charcoal": 3, "lamp_oil": 2}],
	["rice_shop", {"rice": 4, "millet": 2, "flatbread": 6}],
	["temple", {"glutinous": 2, "talisman": 3, "ink_line": 1}],
	["pharmacy", {"plague_powder": 2, "salve": 1, "mugwort": 2}],
	["market", {"seed_cabbage": 2, "seed_radish": 1, "seed_chive": 1, "jerky": 1, "egg": 4}],
	["smithy", {"wood": 3, "nails": 2}],
	["rice_shop", {"rice": 4, "millet": 2}],
]

var failures := 0
var verbose := false
var lazy := false
## 今夜用哪个守夜方针（稳守 / 亲战 / 亲自调度）。
var policy := "hold"


func _init() -> void:
	Data.ensure()
	var results := []
	var roles := ["scholar", "escort", "herbalist", "watchman"]
	verbose = true
	policy = "hold"
	play("scholar", 999)
	verbose = false
	for k in 12:
		results.append(play(roles[k % roles.size()], 1000 + k))
	print("\n===== 汇总（方针：稳守）=====")
	var total_days := 0
	var wins := 0
	for r in results:
		print(r.line)
		total_days += int(r.days)
		if r.win:
			wins += 1
	print("平均存活 %.1f 日，劫满 %d / %d" % [total_days / float(results.size()), wins, results.size()])
	lazy = true
	print("--- 对照：偷懒策略（只吃喝做饭睡觉，不定方针） ---")
	for k in 4:
		print(play(roles[k], 2000 + k).line)
	lazy = false
	print("--- 对照：守夜方针 × 6 局 ---")
	for pol in ["hold", "fight", "manual"]:
		policy = pol
		var w := 0
		var days := 0
		var hp_left := 0
		for k in 6:
			var r: Dictionary = play(roles[k % roles.size()], 3000 + k)
			days += int(r.days)
			hp_left += int(r.hp)
			if r.win:
				w += 1
		print("  方针 %-6s 劫满 %d/6　平均存活 %.1f 日　终局气血 %.0f" % [pol, w, days / 6.0, hp_left / 6.0])
	policy = "hold"
	test_rewind()
	test_migrate()
	test_fight()
	test_broken()
	print("不变量失败：%d" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("断言失败：" + msg)


func check_invariants(run: Dictionary) -> void:
	for k in State.ATTR_NAMES:
		var v := State.attr(run, k)
		check(v >= 0 and v <= State.attr_max(run, k), "属性越界 %s=%d" % [k, v])
	for store in [run.home, run.cart]:
		for id in store:
			check(typeof(store[id]) == TYPE_INT and int(store[id]) > 0, "库存异常 %s=%s" % [id, str(store[id])])
			check(not Data.item(id).is_empty(), "未知物品 " + id)
	check(int(run.silver) >= 0, "银两为负")
	check(int(run.door.cur) >= 0 and int(run.door.cur) <= int(run.door.max), "门耐久越界")


# ---------- 备劫 ----------

func shop_pre(run: Dictionary) -> void:
	var plan := SHOPPING.duplicate(true)
	var guard := 0
	while run.phase == "pre" and guard < 200:
		guard += 1
		check_invariants(run)
		if plan.is_empty():
			Pre.end_day(run)
			continue
		var step = plan[0]
		var dest: String = step[0]
		if Pre.status(run, dest) == "关门" or (dest == "builder" and run.day > 2):
			plan.pop_front()
			continue
		if run.loc != dest:
			if Pre.travel_block(run, dest) != "":
				Pre.end_day(run)
				continue
			if Pre.travel(run, dest) != "":
				plan.pop_front()
				continue
		if dest == "builder":
			for fac in step[1]:
				Pre.order(run, fac)
			plan.pop_front()
			continue
		var full := false
		for id in step[1]:
			var want := int(step[1][id])
			var n := mini(want, Pre.max_buy(run, id))
			if n > 0:
				Pre.buy(run, id, n)
			if n < want and Pre.buy_block(run, id, 1).begins_with("车上"):
				full = true
		if full:
			Pre.travel(run, "home")
		else:
			plan.pop_front()
			if not plan.is_empty() and Pre.travel_block(run, plan[0][0]) != "":
				Pre.travel(run, "home")
	if run.phase == "pre":
		check(false, "备劫阶段没结束")


# ---------- 劫中 ----------

func eat_and_drink(run: Dictionary) -> void:
	var guard := 0
	while State.attr(run, "water") < 60 and Inv.count(run.home, "water") > 0 and guard < 5:
		Post.use_item(run, "water")
		guard += 1
	guard = 0
	while State.attr(run, "food") < 60 and guard < 5:
		var foods := Inv.food_ids(run.home)
		if foods.is_empty():
			for raw in ["cabbage", "radish", "chive", "lingzhi"]:
				if Inv.count(run.home, raw) > 0:
					foods = [raw]
					break
		if foods.is_empty():
			break
		Post.use_item(run, foods[-1])
		guard += 1
	if run.plague:
		for med in ["plague_powder", "mugwort"]:
			if run.plague and Inv.count(run.home, med) > 0:
				Post.use_item(run, med)
	if State.attr(run, "hp") < 50 and Inv.count(run.home, "salve") > 0:
		Post.use_item(run, "salve")
	if State.attr(run, "mood") < 30 and Inv.count(run.home, "calm_soup") > 0:
		Post.use_item(run, "calm_soup")


func dishes(run: Dictionary) -> int:
	return Inv.total(run.home, Inv.food_ids(run.home))


## 21:00 定方针；模拟一个「按说明选」的玩家。
func choose_policy(run: Dictionary) -> void:
	Post.choose_policy(run, policy)


## 白天挑一件事做。返回 true 表示开始做事（或睡下）了。
func choose_action(run: Dictionary) -> bool:
	var m := Post.day_minute(run)
	var wave_tonight := not Defense.wave_for_day(run.pday).is_empty() and int(run.wave_day) != int(run.pday)
	if lazy:
		for rid in ["congee", "millet_cake", "rice_cake", "veg_soup"]:
			if dishes(run) < 3 and Post.recipe_block(run, rid) == "":
				return Post.act_cook(run, rid) == ""
		if Post.is_night(run) and not wave_tonight:
			return Post.sleep(run) == ""
		return Post.act_rest(run) == "" if State.attr(run, "energy") < 60 else false
	# 入夜：布好一夜用的守具，等尸潮；没有尸潮或者打完了就睡
	if Post.is_night(run):
		if wave_tonight:
			for dev in ["talisman_wall", "blood_sill", "caltrop_field", "rice_scatter", "bagua_mirror"]:
				if Post.device_block(run, dev) == "":
					Post.act_build(run, dev)
			return false
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
	if dishes(run) < 4:
		for rid in ["fried_rice", "eight_treasure", "congee", "millet_cake", "egg_soup", "veg_soup", "rice_cake", "lingzhi_soup"]:
			if Post.recipe_block(run, rid) == "":
				return Post.act_cook(run, rid) == ""
	for idx in run.plots.size():
		if run.plots[idx].crop == "":
			for crop in ["lingzhi", "radish", "cabbage", "chive"]:
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
	if "explore" not in run.today.actions and m < 480:
		var low_food := Inv.total(run.home, Inv.GRAINS) + dishes(run) / 3 < 6
		var low_fuel := Inv.count(run.home, "firewood") + Inv.count(run.home, "charcoal") * 2 < 4
		var best := ""
		for pid in Explore.visible_points(run):
			if Explore.point_block(run, pid) != "":
				continue
			var danger := int(Data.table("map_points")[pid].danger)
			if danger >= 4 and State.attr(run, "hp") < 70:
				continue
			if low_fuel and pid in ["lumber", "city_god", "school"]:
				best = pid
				break
			if best == "" or (low_food and pid in ["rice_ruin", "granary"]):
				best = pid
		if best != "" and Post.act_explore(run, best) == "":
			do_explore(run)
			return true
	for book in Inv.ids_in_cat(run.home, "书"):
		if book not in run.read:
			return Post.act_read(run, book) == ""
	return false


func do_explore(run: Dictionary) -> void:
	for idx in run.explore.spots.size():
		if run.explore.is_empty() or run.explore.caught or int(run.explore.exposure) > 65 or Post.blocked(run):
			break
		Post.search(run, idx)
	if not run.explore.is_empty():
		Post.finish_explore(run)


func handle_event(run: Dictionary) -> void:
	var e: Dictionary = Data.table("events")[run.pending_event]
	var pick: int = e.choices.size() - 1
	for idx in e.choices.size():
		if Events.choice_ok(run, e.choices[idx]):
			pick = idx
			break
	Events.choose(run, pick)


## 玩一整天：从卯时到次日天亮。
func play_day(run: Dictionary) -> void:
	for id in run.omens.offer.duplicate():
		var o: Dictionary = Data.table("omens")[id]
		if int(run.merit) >= int(o.cost) + 6:
			Ledger.take_omen(run, id)
	var guard := 0
	while run.phase == "post" and guard < 900:
		guard += 1
		check_invariants(run)
		if run.pending_event != "":
			handle_event(run)
			continue
		if run.plan_due:
			choose_policy(run)
			continue
		# 夜战：到了下一轮的点就结算
		if Post.in_night(run) and Post.day_minute(run) >= Defense.round_minute(int(run.night.round)):
			var rep := Post.nod_round(run)
			if verbose and not rep.is_empty():
				var sur := []
				for sid in Defense.SURFACES:
					var s: Dictionary = rep.surfaces[sid]
					sur.append("%s来%d斩%d漏%d(%d/%d)" % [Defense.surface_name(sid), s.count, s.killed, s.left,
						Defense.part_of(run, sid).cur, Defense.part_of(run, sid).max])
				print("  第%d夜 第%d轮 斩%d 进院%d 气血%d [%s]" % [run.pday, int(rep.round) + 1, rep.killed, rep.get("enter", 0), State.attr(run, "hp"), " ".join(sur)])
			continue
		if run.wave_due:
			var w := Post.resolve_wave(run)
			if verbose and not w.is_empty():
				print("  第%d夜 第一轮 斩%d 进院%d 气血%d" % [run.pday, w.killed, w.get("enter", 0), State.attr(run, "hp")])
			continue
		if not run.wave_report.is_empty():
			Post.ack_wave(run)
			continue
		if run.dawn_due:
			if verbose:
				print("  第%d日天亮 饱%d 水%d 心%d 精%d 温%d 气血%d 粮%d 菜%d 水%d 柴%d 炭%d 木%d 门%d 窗%d 墙%d 守具%d 行事%s" % [run.pday, State.attr(run,"food"), State.attr(run,"water"), State.attr(run,"mood"), State.attr(run,"energy"), State.attr(run,"warmth"), State.attr(run,"hp"), Inv.total(run.home, Inv.GRAINS), dishes(run), Inv.count(run.home,"water"), Inv.count(run.home,"firewood"), Inv.count(run.home,"charcoal"), Inv.count(run.home,"wood"), run.door.cur, run.window.cur, run.wall.cur, run.devices.size(), str(run.today.actions)])
			Post.ack_dawn(run)
			return
		run.raid_report = {}
		if not run.explore.is_empty():
			Post.finish_explore(run)
			continue
		eat_and_drink(run)
		var started := false
		if Post.can_act(run, 0) == "":
			started = choose_action(run)
		if Post.is_busy(run):
			Post.advance(run, maxi(10, int(run.busy.end) - int(run.t)))
		elif run.sleeping:
			Post.advance(run, 60)
		elif not started:
			Post.advance(run, 30)


func play(role: String, seed_value: int) -> Dictionary:
	var meta := State.new_meta()
	var run := State.new_run(role, meta, seed_value)
	shop_pre(run)
	var silver_left := int(run.silver)
	var guard := 0
	while run.phase == "post" and guard < 40:
		guard += 1
		play_day(run)
	check_invariants(run)
	var win: bool = run.phase == "ending"
	var gain := Ledger.end_run(run, meta)
	var line := "%-6s seed=%d  %s  第%d日  尸潮守住%d  斩尸%d  功德%d  余银%s  道心+%d  %s" % [
		State.role(run).name, seed_value, "劫满" if win else "身死", run.pday, run.waves_survived,
		run.kills, run.merit, Pre.money(silver_left), gain.total, run.death_cause]
	return {"line": line, "days": gain.days, "win": win, "hp": State.attr(run, "hp")}


# ---------- 院门攻防 ----------

## 关门只能挨撞、开门会进屋砸东西、铜甲两刀。
func test_fight() -> void:
	var s := NightFight.begin(3, false)
	check(s.foes.size() == 3, "院门的活人数量不对：%d" % s.foes.size())
	var guard := 0
	var bashed := false
	while guard < 500 and not bashed:
		guard += 1
		for e in NightFight.step(s, 0.05, 0.0, 3.0, false):
			if str(e[0]) == "bash":
				bashed = true
	check(bashed, "门关着的时候没有撞门")
	# 门开着：进院子砸东西
	var s2 := NightFight.begin(3, false)
	guard = 0
	var entered := false
	var wrecked := false
	while guard < 900 and not wrecked:
		guard += 1
		for e in NightFight.step(s2, 0.05, 0.0, -6.5, true):
			if str(e[0]) == "enter":
				entered = true
			if str(e[0]) == "wreck":
				wrecked = true
	check(entered, "门开着却没进院子")
	check(wrecked, "进了院子却没砸东西")
	# 贴身一刀一个；铜甲两刀
	var s3 := NightFight.begin(1, false)
	var foe: Dictionary = s3.foes[0]
	var r := NightFight.strike(s3, float(foe.x), float(foe.z))
	check(bool(r.get("kill", false)), "贴身一刀没砍死")
	check(int(s3.kills) == 1, "斩获没记上")
	var a := NightFight.begin(1, true)
	var f2: Dictionary = a.foes[0]
	NightFight.strike(a, float(f2.x), float(f2.z))
	check(not bool(f2.dead), "铜甲一刀就死了")
	NightFight.step(a, 0.6, float(f2.x), float(f2.z), false)
	NightFight.strike(a, float(f2.x), float(f2.z))
	check(bool(f2.dead), "铜甲第二刀没砍死")
	var sum := NightFight.finish(a)
	check(int(sum.kills) == 1, "收场时斩获不对")
	# 架刀：抬起来的那一下能挡下一口，咬人的被推开；抬不起来时照咬
	# （人站在院子中间，别让僵尸先去撞门——撞门会把它的出手间隔占掉）
	var b := NightFight.begin(1, false)
	var pz := 4.0
	var biter: Dictionary = b.foes[0]
	biter.x = 0.0
	biter.z = 4.6
	biter.cd = 0.0
	NightFight.step(b, 0.05, 0.0, pz, false)
	check(int(b.hp_loss) == NightFight.HIT_DMG, "没架住却没挨咬：%d" % int(b.hp_loss))
	biter.cd = 0.0
	check(NightFight.guard(b), "刀抬不起来")
	check(not NightFight.guard(b), "冷却中还能再架一次")
	NightFight.step(b, 0.05, 0.0, pz, false)
	check(int(b.hp_loss) == NightFight.HIT_DMG, "架住了还在掉血")
	check(int(b.parries) == 1, "架住没记上：%d" % int(b.parries))
	var pushed := Vector2(float(biter.x), float(biter.z) - pz).length()
	check(pushed > 0.5, "架住之后没把它推开：%.2f" % pushed)
	check(not NightFight.can_guard(b), "架住之后立刻又能架")
	NightFight.step(b, 0.7, 0.0, pz, false)
	check(NightFight.can_guard(b), "架住之后收刀太久")
	var sum2 := NightFight.finish(b)
	check(int(sum2.parries) == 1, "收场时架住次数没带上")
	print("院门攻防：撞门 %d 次、进院啃了 %d 次、斩 %d、架住 %d" % [
		int(s.bashes), s2.wrecked.size(), int(sum.kills), int(sum2.parries)])


## 被砸烂的家具：记进 run.broken、存档带走、要材料才修得回来。
func test_broken() -> void:
	var run := State.new_run("escort", State.new_meta(), 91)
	run.phase = "post"
	run.pday = 3
	run.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	var t: String = Post.apply_wreck(run, 3)
	check("stove" in run.broken, "灶台被砸了却没记下来：%s" % t)
	var t2: String = Post.apply_wreck(run, 4)
	check("bench" in run.broken, "工作台被砸了却没记下来：%s" % t2)
	Post.apply_wreck(run, 3)
	check(run.broken.size() == 2, "砸烂的家具记重复了：%s" % str(run.broken))
	var saved := Migrate.save({"run": run.duplicate(true), "snapshots": {}})
	check("stove" in saved.run.broken, "存档里丢了被砸的家具")
	# 没料修不了
	run.home.erase("wood")
	run.home.erase("nails")
	check(Post.furniture_block(run, "stove") != "", "没料也能修")
	Inv.add(run.home, "wood", 2)
	Inv.add(run.home, "nails", 1)
	check(Post.furniture_block(run, "stove") == "", "有料却修不了：%s" % Post.furniture_block(run, "stove"))
	check(Post.act_fix_furniture(run, "stove") == "", "重修开不了工")
	Post.advance(run, 100)
	check(not "stove" in run.broken, "修完了灶台还是烂的")
	check(Inv.count(run.home, "wood") == 0, "修完了木料没扣")
	print("家具重修：砸 2 件，修好 1 件，还剩 %s" % str(run.broken))


func test_rewind() -> void:
	var meta := State.new_meta()
	var run := State.new_run("scholar", meta, 77)
	var snaps := {}
	shop_pre(run)
	Ledger.snapshot(run, snaps)
	play_day(run)
	Ledger.snapshot(run, snaps)
	var day_before := int(run.pday)
	run.attrs.hp = 0
	State.check_death(run, "测试")
	var back := Ledger.rewind(run, snaps, meta)
	check(not back.is_empty(), "翻回昨日失败")
	check(int(back.pday) == day_before - 1, "翻回的日子不对：%d" % int(back.pday))
	check(int(back.attrs.hp_max) == int(run.attrs.hp_max) - 10, "寿元没折损")
	check(int(back.rebirths_left) == 2, "残页次数没扣")
	check(back.phase == "post", "翻回后状态不对")
	var json := JSON.stringify({"run": back, "snapshots": snaps})
	var parsed: Dictionary = Data.normalize(JSON.parse_string(json))
	check(typeof(parsed.run.pday) == TYPE_INT, "存档读回后整数类型丢失")
	print("翻生死簿测试：回到第 %d 日，气血上限 %d，残页剩 %d" % [back.pday, back.attrs.hp_max, back.rebirths_left])


## v0.2 的旧存档（回合制劫中）读进来要能接着玩。
func test_migrate() -> void:
	var run := State.new_run("escort", State.new_meta(), 77)
	run.phase = "post"
	run.pday = 1
	run.plots = [{"crop": "radish", "days": 1, "watered": 0}, {"crop": "", "days": 0, "watered": 0}]
	for key in Migrate.ADDED:
		run.erase(key)
	run.version = 1
	run.seg = 2
	run.night_done = false
	var data := Migrate.save({"run": run, "snapshots": {"1": run.duplicate(true)}})
	var up: Dictionary = data.run
	for key in Migrate.ADDED:
		check(up.has(key), "旧存档迁移后缺 %s" % key)
	check(int(up.version) == Migrate.VERSION and not up.has("seg"), "旧存档版本没升上去")
	check(up.has("broken") and up.broken is Array, "v5 的 broken 没补上")
	check(int(up.t) == 600 and Post.clock_text(up) == "16:00", "旧存档时段换算不对：t=%s" % str(up.get("t")))
	check(up.plots[0].has("watered_t") and not up.plots[0].has("watered"), "菜畦字段没迁移")
	check(data.snapshots["1"].has("busy"), "生死簿快照没迁移")
	Post.advance(up, 60)
	check(int(up.t) >= 660, "迁移后时间走不动")
	print("旧存档迁移测试：%s %s，菜畦 %s" % [Post.shichen(up), Post.clock_text(up), str(up.plots[0])])
