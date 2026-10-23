extends SceneTree
## 无界面整局模拟：用一个简单的机器人策略从备劫一路玩到死亡或劫满，检查不变量、打印平衡数据。
## 运行：godot --headless --path . --script res://tests/sim_test.gd

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Home = preload("res://scripts/core/home.gd")
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
## 跑完了的测试名（跟 _test_list() 对账，缺哪个就是中途崩了）
var tested: Array = []
var verbose := false
var lazy := false
## 今夜用哪个守夜方针（稳守 / 亲战 / 亲自调度）。
var policy := "hold"
## 这一局机器人带了哪些誓约（策略要照着守，否则测的是"一开局就破约"）
var vows_picked: Array = []
## 诊断用：灯油白送（不花钱、不占负重，但夜里照样点得上）。
## 用来分开"灯油有用但太贵"和"灯油根本没用"——只比"买/不买"两臂是分不清的。
var free_oil := false
## 无尽模式：劫满之后不结算，接着守下去
var endless_after_win := false
## 诊断用：把每晚的「尸潮数量 / 守力」记下来，看夜里到底有没有悬念
var log_waves := false
var wave_log: Array = []
## 诊断用：天亮时的资源水位（粮/水/体温/柴/炭/银），看经济到底有没有余量
var log_res := false
var res_min: Dictionary = {}
var res_days := 0
## 柴炭同时见底的早晨数——那种早晨晚上就要挨冻
var res_zero := 0
## 诊断用：备劫时买货被拦下的原因（银子 vs 负重 vs 缺货 vs 关门）
var block_reasons: Dictionary = {}
var pre_silver_start := 0
## 誓约对照段每档跑几局。6 局时 2/6 和 3/6 只差一局，噪声有一档，20 局才敢下结论。
const VOW_SAMPLE := 40


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
	print("--- 对照：偷懒策略 × 难度（只做饭睡觉，不打水不修门不种菜） ---")
	for d in Data.table("difficulty"):
		var lw := 0
		var ldays := 0
		var lhp := 0
		var lstarve := 0
		for k in 4:
			var r: Dictionary = play(roles[k], 2000 + k, str(d.id))
			ldays += int(r.days)
			lhp += int(r.hp)
			if r.win:
				lw += 1
			if "饿死" in str(r.line) or "渴死" in str(r.line):
				lstarve += 1
		print("  %-6s 劫满 %d/4　平均存活 %.1f 日　终局气血 %.0f　饿/渴死 %d 局" % [
			str(d.name), lw, ldays / 4.0, lhp / 4.0, lstarve])
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
	print("--- 对照：难度 × 6 局（同一机器人策略，只看难度本身） ---")
	for d in Data.table("difficulty"):
		var dw := 0
		var ddays := 0
		var dhp := 0
		for k in 6:
			var r: Dictionary = play(roles[k % roles.size()], 4000 + k, str(d.id))
			ddays += int(r.days)
			dhp += int(r.hp)
			if r.win:
				dw += 1
		print("  %-6s 劫满 %d/6　平均存活 %.1f 日　终局气血 %.0f" % [str(d.name), dw, ddays / 6.0, dhp / 6.0])
	# 诊断：基准局（无誓约）里每条誓约"若立则违约"几次。
	# 这一步是为了区分两种"测不出"：誓约真的不咬人，还是这个机器人的打法根本不碰它
	# （那就是测量无效，不能拿来给数值定罪）。数据库里早就有 tally，白拿。
	print("--- 诊断：基准局（无誓约）里各誓约的触发次数，%d 局 ---" % VOW_SAMPLE)
	vows_picked = []
	var lamp_games := 0
	var lamp_sum := 0
	var trap_games := 0
	var door_sum := 0
	var door_zero := 0
	var trip_sum := 0
	var trip_ok := 0
	for k in VOW_SAMPLE:
		var br: Dictionary = play(roles[k % roles.size()], 5000 + k)
		var t: Dictionary = br.tally
		var lamp := int(t.get("bought", {}).get("lamp_oil", 0))
		lamp_sum += lamp
		if lamp > 0:
			lamp_games += 1
		if "rat_trap" in br.furniture:
			trap_games += 1
		var dr := int(t.get("repair_door", 0))
		door_sum += dr
		if dr == 0:
			door_zero += 1
		var tr := int(t.get("home_trips", 0))
		trip_sum += tr
		if tr <= 1:
			trip_ok += 1
	var den := float(VOW_SAMPLE)
	print("  不点灯  买过灯油 %d/%d 局，平均 %.1f 壶（不吃灯油 %d 局）" % [lamp_games, VOW_SAMPLE, lamp_sum / den, VOW_SAMPLE - lamp_games])
	print("  不设笼  摆过捕鼠笼 %d/%d 局" % [trap_games, VOW_SAMPLE])
	print("  不修门  平均修门 %.1f 次；一次没修 %d/%d 局" % [door_sum / den, door_zero, VOW_SAMPLE])
	print("  一趟    平均回家 %.1f 次；只回 ≤1 次 %d/%d 局" % [trip_sum / den, trip_ok, VOW_SAMPLE])

	# 再往下追一层：为什么"白送的灯油"也几乎不涨胜率？
	# 如果守力常年远超尸潮数量，那些 ×0.7 / ×1.1 的乘数就没有实际效果，
	# 灯油本来就白买、誓约自然也咬不着人。用一局把这条曲线打出来。
	log_waves = true
	wave_log = []
	vows_picked = []
	play("scholar", 5000)
	log_waves = false
	print("--- 诊断：守力 vs 尸潮（书生 seed 5000，逐夜） ---")
	for w in wave_log:
		print("  第%2d夜  尸潮 %3d  守力 %5.0f  守力/尸潮 %4.1f  %s%s" % [
			int(w.day), int(w.count), float(w.power), float(w.power) / maxf(1.0, float(w.count)),
			"[暗夜·点了灯]" if w.lamp else "", "  [破]" if w.breached else ""])

	# 再追根一层：为什么连"每天都花钱"的取暖也咬不着人？看资源水位有没有余量。
	log_res = true
	res_min = {}
	res_days = 0
	res_zero = 0
	play("scholar", 5000)
	log_res = false
	print("--- 诊断：资源最低水位（书生 seed 5000，%d 个早晨） ---" % res_days)
	print("  粮 %d　水 %d　体温 %d　精力 %d　柴 %d 捆　炭 %d 筐　银 %d 文" % [
		int(res_min.get("food", 0)), int(res_min.get("water", 0)), int(res_min.get("warmth", 0)),
		int(res_min.get("energy", 0)), int(res_min.get("firewood", 0)), int(res_min.get("charcoal", 0)),
		int(res_min.get("silver", 0))])
	print("  柴炭同时见底的早晨：%d / %d" % [res_zero, res_days])

	# 备劫到底卡在哪个约束上：银子、负重、还是缺货？
	# 这决定"降低开局银两"这种调整有没有意义——若玩家本来就买不完（负重先满），降钱等于没改。
	vows_picked = []
	block_reasons = {}
	var bs0 := 0
	var bs1 := 0
	for k in VOW_SAMPLE:
		var br: Dictionary = play(roles[k % roles.size()], 5000 + k)
		bs0 += int(br.silver_start)
		bs1 += int(br.silver_left)
	var bdk := float(VOW_SAMPLE)
	print("--- 诊断：备劫的约束（%d 局） ---" % VOW_SAMPLE)
	print("  开局银两均 %s，备劫后剩 %s（花掉 %.0f%%）" % [
		Pre.money(int(bs0 / bdk)), Pre.money(int(bs1 / bdk)),
		100.0 * (1.0 - float(bs1) / maxf(1.0, float(bs0)))])
	var bkeys := block_reasons.keys()
	bkeys.sort()
	var bparts := []
	for bk in bkeys:
		bparts.append("%s %d 次" % [str(bk), int(block_reasons[bk])])
	print("  买不了的原因：%s" % ("、".join(bparts) if not bparts.is_empty() else "一次没被拦（购物清单本来就买得完）"))

	# 奖励轴：胜局和败局各拿多少道心（现在带上了劫满 10 点，是真实值）
	vows_picked = []
	var win_n := 0
	var win_sum := 0
	var lose_n := 0
	var lose_sum := 0
	for k in VOW_SAMPLE:
		var ar: Dictionary = play(roles[k % roles.size()], 5000 + k)
		if ar.win:
			win_n += 1
			win_sum += int(ar.daoxin)
		else:
			lose_n += 1
			lose_sum += int(ar.daoxin)
	var win_avg := win_sum / float(maxi(1, win_n))
	var lose_avg := lose_sum / float(maxi(1, lose_n))
	print("--- 诊断：道心的胜负差（%d 局，寻常年景、无誓约） ---" % VOW_SAMPLE)
	print("  胜 %d 局均 %.1f　败 %d 局均 %.1f　胜/败 = %.2f" % [
		win_n, win_avg, lose_n, lose_avg, win_avg / maxf(0.01, lose_avg)])

	print("--- 对照：挑战誓约 × %d 局（寻常年景，机器人也守约） ---" % VOW_SAMPLE)
	# 前三档可比：只加"不改备劫打法"的誓约（不点灯去掉灯油、不修门跳过修门、空手清空随身物）。
	var vow_set := ["no_lamp", "no_door", "bare"]
	for n in [0, 1, 2, 3]:
		vows_picked = vow_set.slice(0, n)
		var vw := 0
		var vdays := 0
		var vdaoxin := 0
		var vbroken := 0
		for k in VOW_SAMPLE:
			var vr: Dictionary = play(roles[k % roles.size()], 5000 + k)
			vdays += int(vr.days)
			vdaoxin += int(vr.daoxin)
			vbroken += int(vr.broken)
			if vr.win:
				vw += 1
		print("  %d 条誓约（%s）劫满 %d/%d　平均存活 %.1f 日　平均道心 %.0f　破约 %d 次" % [
			n, "无" if n == 0 else ",".join(vows_picked), vw, VOW_SAMPLE,
			vdays / float(VOW_SAMPLE), vdaoxin / float(VOW_SAMPLE), vbroken])
	# 第三臂：灯油白送。**不买**（省下 300 文和 4 斤负重）**但白给两壶**，
	# 于是和"不买"那一臂只差"有没有油"、和"买"那一臂只差"花没花钱"，成本被钉住。
	# 只比买/不买两臂是分不开"没用"和"太贵"的。
	free_oil = true
	vows_picked = []
	var ow := 0
	var odays := 0
	for k in VOW_SAMPLE:
		var oil_run: Dictionary = play(roles[k % roles.size()], 5000 + k)
		odays += int(oil_run.days)
		if oil_run.win:
			ow += 1
	free_oil = false
	print("  [三臂对照] 灯油白送（不花钱、0 负重）劫满 %d/%d　平均存活 %.1f 日" % [
		ow, VOW_SAMPLE, odays / float(VOW_SAMPLE)])
	# 「一趟」单独测：它会改掉整个备劫打法（装不下就不买、不中途回家卸货），
	# 所以不能和前几档横着比——第一次把它塞进同一张表，4 条誓约反而比 3 条活得久，就是混淆。
	vows_picked = ["one_trip"]
	var tw := 0
	var tdays := 0
	var tdaoxin := 0
	var tbroken := 0
	for k in VOW_SAMPLE:
		var tr: Dictionary = play(roles[k % roles.size()], 5000 + k)
		tdays += int(tr.days)
		tdaoxin += int(tr.daoxin)
		tbroken += int(tr.broken)
		if tr.win:
			tw += 1
	print("  [不可比] 一趟（one_trip）劫满 %d/%d　平均存活 %.1f 日　平均道心 %.0f　破约 %d 次" % [
		tw, VOW_SAMPLE, tdays / float(VOW_SAMPLE), tdaoxin / float(VOW_SAMPLE), tbroken])
	# 候选：不烧炭。跟灯油的区别在于它**每天冷夜都要花钱**，不是只在两个暗夜收。
	# 用来验证"限制核心循环才咬人"这个假设；顺便看木炭和柴到底哪个划算。
	vows_picked = ["no_charcoal"]
	var cw := 0
	var cdays := 0
	var cdaoxin := 0
	var cbroken := 0
	for k in VOW_SAMPLE:
		var cr: Dictionary = play(roles[k % roles.size()], 5000 + k)
		cdays += int(cr.days)
		cdaoxin += int(cr.daoxin)
		cbroken += int(cr.broken)
		if cr.win:
			cw += 1
	print("  [候选] 不烧炭（no_charcoal）劫满 %d/%d　平均存活 %.1f 日　平均道心 %.0f　破约 %d 次" % [
		cw, VOW_SAMPLE, cdays / float(VOW_SAMPLE), cdaoxin / float(VOW_SAMPLE), cbroken])
	# 候选：不雇工。营造坊那四项（门闩 1500 + 水缸 600 + 窗板 800 + 灶台 1000 = 3900 文）
	# 约占备劫开销 26%，而且直接加门窗耐久——量级比灯油/木炭大一个数量级。
	vows_picked = ["no_order"]
	var nw := 0
	var ndays := 0
	var ndaoxin := 0
	var nbroken := 0
	for k in VOW_SAMPLE:
		var nr: Dictionary = play(roles[k % roles.size()], 5000 + k)
		ndays += int(nr.days)
		ndaoxin += int(nr.daoxin)
		nbroken += int(nr.broken)
		if nr.win:
			nw += 1
	print("  [候选] 不雇工（no_order）劫满 %d/%d　平均存活 %.1f 日　平均道心 %.0f　破约 %d 次" % [
		nw, VOW_SAMPLE, ndays / float(VOW_SAMPLE), ndaoxin / float(VOW_SAMPLE), nbroken])
	# 候选：不设防 / 不服药。两条都是"砍掉一整类"，且不是靠省钱变简单——
	# 守具撑的是夜里三面的守力，药撑的是气血和瘟疫，价值远高于价钱。
	for cand in ["no_guard", "no_med"]:
		vows_picked = [cand]
		var kw := 0
		var kdays := 0
		var kdaoxin := 0
		for k in VOW_SAMPLE:
			var kr: Dictionary = play(roles[k % roles.size()], 5000 + k)
			kdays += int(kr.days)
			kdaoxin += int(kr.daoxin)
			if kr.win:
				kw += 1
		print("  [候选] %s 劫满 %d/%d　平均存活 %.1f 日　平均道心 %.0f" % [
			cand, kw, VOW_SAMPLE, kdays / float(VOW_SAMPLE), kdaoxin / float(VOW_SAMPLE)])
	vows_picked = []
	test_rewind()
	test_migrate()
	test_fight()
	test_broken()
	test_furnish()
	test_power()
	test_difficulty()
	test_vehicle()
	test_goals()
	test_boons()
	test_vows()
	test_endless()
	var want: Array = _test_list()
	for w in want:
		if not w in tested:
			failures += 1
			print("断言失败：测试 %s 没有跑完（中途抛错或者被跳过）" % str(w))
	print("测试完成 %d / %d 项" % [tested.size(), want.size()])
	print("不变量失败：%d" % failures)
	quit(1 if failures > 0 else 0)


## 每个 test_* 跑完都要调一次。中途抛错就不会调，末尾对不上数就判失败——
## 否则脚本错误会让整个测试函数静默跳过，而 harness 照样打印"失败 0"（真的发生过）。
## 应该在 _init 里被调到的测试，顺序无所谓，缺一个就报。
func _test_list() -> Array:
	return ["test_fight", "test_broken", "test_furnish", "test_rewind", "test_power",
		"test_goals", "test_vows", "test_endless", "test_boons", "test_vehicle",
		"test_difficulty", "test_migrate"]


func _ok(name: String) -> void:
	tested.append(name)


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

## 带了某些誓约就不能碰的东西（机器人也得守约，否则测出来的是"誓约立刻被破"而不是难度）
func _skip_by_vow(id: String) -> bool:
	if ("no_lamp" in vows_picked or free_oil) and id == "lamp_oil":
		return true
	if "no_charcoal" in vows_picked and id == "charcoal":
		return true
	# 按类目禁买的誓约（不设防 / 不服药）：数据里带 cat 的，机器人也照着守
	for vw in Data.table("challenge").get("vows", []):
		if str(vw.get("id", "")) in vows_picked and vw.has("cat"):
			if str(Data.item(id).get("cat", "")) == str(vw.cat):
				return true
	return false


## 把"买不了"的原因归类计数。这是判断"钱还是负重才是约束"的唯一依据。
func _count_block(why: String) -> void:
	var key := why
	if why.begins_with("银子"):
		key = "银子不够"
	elif why.begins_with("车上装不下"):
		key = "车上装不下"
	elif why.begins_with("货不够"):
		key = "货不够"
	elif why.begins_with("已经关门"):
		key = "关了门"
	if key == "":
		return
	block_reasons[key] = int(block_reasons.get(key, 0)) + 1


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
			# 守「不雇工」：营造坊一步都不进，直接跳过整条订单
			if "no_order" not in vows_picked:
				for fac in step[1]:
					Pre.order(run, fac)
			plan.pop_front()
			continue
		var full := false
		for id in step[1]:
			# 带了誓约就要守：不点灯就别买灯油，否则机器人一开局就把自己的愿破了
			if _skip_by_vow(id):
				continue
			var want := int(step[1][id])
			var n := mini(want, Pre.max_buy(run, id))
			if n > 0:
				Pre.buy(run, id, n)
			if n < want:
				_count_block(Pre.buy_block(run, id, 1))
			if n < want and Pre.buy_block(run, id, 1).begins_with("车上"):
				full = true
		if full:
			# 带了「一趟」就不能中途回家卸货：装不下就收手，剩下的不买了。
			# 这也是这条誓约真正的代价——一趟拉不完，就只能少囤。
			if "one_trip" in vows_picked:
				plan.clear()
			else:
				Pre.travel(run, "home")
		else:
			plan.pop_front()
			if not plan.is_empty() and Pre.travel_block(run, plan[0][0]) != "":
				if "one_trip" in vows_picked:
					plan.clear()
				else:
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
	if wave_soon and not "no_door" in vows_picked and int(run.door.cur) < int(run.door.max) - 30 and Inv.count(run.home, "wood") > 0:
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
			if log_waves:
				wave_log.append({
					"day": int(run.pday), "count": int(run.wave_report.get("count", 0)),
					"power": float(run.wave_report.get("power", 0.0)),
					"lamp": bool(run.wave_report.get("lamp", false)),
					"breached": bool(run.wave_report.get("breached", false)),
				})
			Post.ack_wave(run)
			continue
		if run.dawn_due:
			# 资源水位采样：放在天亮（吃饭之前），看这一天起步时手里有多少余量
			if log_res:
				res_days += 1
				var probe := {"food": State.attr(run, "food"), "water": State.attr(run, "water"),
					"warmth": State.attr(run, "warmth"), "energy": State.attr(run, "energy"),
					"firewood": Inv.count(run.home, "firewood"), "charcoal": Inv.count(run.home, "charcoal"),
					"silver": int(run.silver)}
				for k in probe:
					res_min[k] = minf(float(res_min.get(k, 99999.0)), float(probe[k]))
				if int(probe.firewood) == 0 and int(probe.charcoal) == 0:
					res_zero += 1
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


func play(role: String, seed_value: int, difficulty_id := "normal") -> Dictionary:
	var meta := State.new_meta()
	var run := State.new_run(role, meta, seed_value, difficulty_id, [], [], vows_picked)
	pre_silver_start = int(run.silver)
	shop_pre(run)
	# 诊断三臂里的"白送油"：备完劫直接塞两壶，不花钱不占车上负重
	if free_oil:
		Inv.add(run.home, "lamp_oil", 2)
	var silver_left := int(run.silver)
	var guard := 0
	while run.phase == "post" and guard < 40:
		guard += 1
		play_day(run)
	# 劫满后转无尽：走真实路径（Game.keep_living 的三步），再接着打到死
	if endless_after_win and run.phase == "ending":
		run.endless = true
		run.phase = "post"
		Post.begin_day(run)
		while run.phase == "post" and guard < 160:
			guard += 1
			play_day(run)
	check_invariants(run)
	var win: bool = run.phase == "ending"
	# 劫满要带上那 10 点，否则胜局的道心被少算（原来这里漏了，导致"胜负道心一样"的假象）
	var gain := Ledger.end_run(run, meta, Ledger.ENDING_BONUS if win else 0)
	var line := "%-6s seed=%d  %s  第%d日  尸潮守住%d  斩尸%d  功德%d  余银%s  道心+%d  %s" % [
		State.role(run).name, seed_value, "劫满" if win else "身死", run.pday, run.waves_survived,
		run.kills, run.merit, Pre.money(silver_left), gain.total, run.death_cause]
	# 破了几条誓约（0 表示全守住了）
	var broken := 0
	for v in Ledger.vow_results(run):
		if not bool(v.met):
			broken += 1
	return {"line": line, "days": gain.days, "win": win, "hp": State.attr(run, "hp"),
		"daoxin": int(gain.total), "broken": broken,
		"silver_start": pre_silver_start, "silver_left": silver_left,
		"endless": bool(run.get("endless", false)), "pday": int(run.pday),
		"waves_survived": int(run.waves_survived),
		"tally": _tally_copy(run), "furniture": run.furniture.duplicate()}


## 诊断用：跑完一局后把记账抄一份出来（不然引用会被下一局覆盖）。
## run.tally 只有两层，手抄一遍足够，不用找深拷贝的库函数。
static func _tally_copy(run: Dictionary) -> Dictionary:
	var t: Dictionary = run.get("tally", {})
	var out := {}
	for k in t:
		var v = t[k]
		out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out


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
	_ok("test_fight")


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
	_ok("test_broken")


## 添置家具：占地检查、扣料、要等做完才出现、拆掉退一半（向下取整）。
func test_furnish() -> void:
	var run := State.new_run("escort", State.new_meta(), 93)
	run.phase = "post"
	run.pday = 1
	run.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	Home.ensure_layout(run)
	check(Home.count(run, "bed") == 1 and Home.count(run, "stove") == 1, "开局家具没摆出来")
	# 中路不许摆
	check(Home.spot_block(run, "tea_table", 0.0, 2.0, 0) != "", "中路居然能摆")
	# 料不够就造不了
	check(Home.build_block(run, "armchair") != "", "没料也能造圈椅")
	Inv.add(run.home, "wood", 5)
	Inv.add(run.home, "nails", 2)
	check(Home.build_block(run, "armchair") == "", "有料却造不了圈椅")
	# 开工：料先扣，东西要等做完才出现
	var before := Home.count(run, "armchair")
	check(Post.act_furnish(run, "armchair", -3.2, 1.0, 0) == "", "摆放开不了工")
	check(Home.count(run, "armchair") == before, "没等做完就出现了")
	Post.advance(run, 60)
	check(Home.count(run, "armchair") == before + 1, "做完了没摆出来")
	# 拆掉退一半（3 木料 → 退 1）
	var f: Dictionary = Home.list(run, "armchair")[0]
	var wood_now := Inv.count(run.home, "wood")
	check(Post.act_unfurnish(run, int(f.uid)) == "", "拆不掉")
	check(Home.count(run, "armchair") == before, "拆了还在")
	check(Inv.count(run.home, "wood") == wood_now + 1, "退料不对：%d → %d" % [wood_now, Inv.count(run.home, "wood")])
	print("添置家具：开局 %d 件，圈椅摆上又拆掉，木料退回 1 根" % Home.list(run).size())
	_ok("test_furnish")


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
	_ok("test_rewind")


## 能源链：冷夜里开发动机器烧柴油（带暖气暖得更快），没油就退回烧柴。
func test_power() -> void:
	# 场景一：没发电机，只有一捆柴 → 弱火
	var run := cold_night("escort", 93)
	Inv.add(run.home, "firewood", 1)
	to_heat(run)
	check(run.heated and not bool(run.get("powered", false)), "没发电机却标成开发动机器")
	check(bool(run.get("heat_weak", false)), "一捆柴没标成弱火")
	run.attrs.warmth = 40.0
	Post.advance(run, 120)
	var warm_fire: float = run.attrs.warmth
	# 场景二：发电机 + 暖气 + 柴油 → 烧油，暖得快一截
	var run2 := cold_night("escort", 93)
	run2.facilities = ["generator", "heater"]
	Inv.add(run2.home, "diesel", 2)
	to_heat(run2)
	check(bool(run2.get("powered", false)), "有柴油却没开发动机器")
	check(Inv.count(run2.home, "diesel") == 1, "柴油没扣：剩 %d" % Inv.count(run2.home, "diesel"))
	check(run2.heated and not bool(run2.get("heat_weak", false)), "发电机点火标成了弱火")
	run2.attrs.warmth = 40.0
	Post.advance(run2, 120)
	var warm_gen: float = run2.attrs.warmth
	check(warm_gen > warm_fire + 1.0, "发电机带暖气还没烧柴暖得快：%.1f vs %.1f" % [warm_gen, warm_fire])
	# 场景三：有发电机没油 → 退回烧炭，机器标记要清掉
	var run3 := cold_night("escort", 93)
	run3.facilities = ["generator", "heater"]
	Inv.add(run3.home, "charcoal", 1)
	to_heat(run3)
	check(run3.heated and not bool(run3.get("powered", false)), "没油还开着机器")
	check(Inv.count(run3.home, "charcoal") == 0, "没油的时候炭没烧")
	# 场景四：天亮停机
	Post.begin_day(run2)
	check(not bool(run2.get("powered", false)), "天亮机器还在转")
	check(not run2.heated, "天亮了还生着火")
	print("能源链：一捆柴暖到 %.0f，发电机+暖气暖到 %.0f，天亮停机" % [warm_fire, warm_gen])
	_ok("test_power")


## 冬至（cold 30）的一局，时间停在当天开头，等着走到 20:00。
func cold_night(role_id: String, seed_value: int) -> Dictionary:
	var run := State.new_run(role_id, State.new_meta(), seed_value)
	run.phase = "post"
	run.pday = 12
	run.t = (int(run.pday) - 1) * Post.DAY
	run.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	return run


## 了愿：达成给分、没达成标「未成」给 0、没立愿就一分不给；旧存档迁上来当成没立愿。
func test_goals() -> void:
	var meta := State.new_meta()
	# 没立愿：结算里不该出现了愿这一行。基准要和下面那局各项都对齐，只差「有没有立愿」
	var plain := State.new_run("escort", meta, 77)
	plain.phase = "ending"
	plain.pday = 20
	plain.kills = 300
	plain.waves_survived = 7
	var g0: Dictionary = Ledger.daoxin_gain(plain)
	for l in g0.lines:
		check(not "了愿" in str(l[0]), "没立愿却出现了愿行：%s" % str(l[0]))
	# 立三个愿且全部达成：杀满 200、七次全守、活到终局
	var run := State.new_run("escort", meta, 77, "normal", ["slay_200", "hold_all", "survive"])
	check(State.goals_of(run).size() == 3, "立的愿没记进 run.tally")
	run.phase = "ending"
	run.pday = 20
	run.kills = 200
	run.waves_survived = 7
	var all_met: Array = Ledger.goal_results(run)
	check(all_met.size() == 3, "立三个愿只认出 %d 个" % all_met.size())
	for g in all_met:
		check(bool(g.met), "该达成的愿没达成：%s" % str(g.id))
	var g1: Dictionary = Ledger.daoxin_gain(run)
	var goal_part := 0
	for l in g1.lines:
		if "了愿" in str(l[0]):
			goal_part += int(l[1])
	check(goal_part == 30, "三个愿满额应是 30 道心，实得 %d" % goal_part)
	check(int(g1.total) == int(g0.total) + 30, "了愿没加到总分里：%d vs %d" % [int(g1.total), int(g0.total)])
	# 差一点：杀 199、只守 6 次、且是病死（phase=dead）→ 三个都不算
	var near := State.new_run("escort", meta, 77, "normal", ["slay_200", "hold_all", "survive"])
	near.phase = "dead"
	near.pday = 20
	near.kills = 199
	near.waves_survived = 6
	var near_met: Array = Ledger.goal_results(near)
	for g in near_met:
		check(not bool(g.met), "差一点也算达成了：%s" % str(g.id))
	var g2: Dictionary = Ledger.daoxin_gain(near)
	for l in g2.lines:
		if "了愿" in str(l[0]):
			check(int(l[1]) == 0 and "未成" in str(l[0]), "没达成的愿没标未成：%s" % str(l))
	# 病死在第 20 日不算「活到终局」：pday 够但 phase 不是 ending
	var died := State.new_run("escort", meta, 77, "normal", ["survive"])
	died.phase = "dead"
	died.pday = 20
	check(not bool(Ledger.goal_results(died)[0].met), "病死在第 20 日却被算成活到终局")
	# 旧存档（v7）没有 tally：迁上来当成没立愿，且不能崩
	var old := State.new_run("escort", meta, 77)
	old.erase("tally")
	old.version = 7
	var up: Dictionary = Migrate.upgrade(old)
	check(up.has("tally") and State.goals_of(up).is_empty(), "旧存档没补上空的 tally")
	check(Ledger.daoxin_gain(up).lines.size() > 0, "补了 tally 之后结算崩了")
	print("了愿：没立愿 %d 道心；三个愿全达 %d（+%d）；差一点 %d" % [
		int(g0.total), int(g1.total), goal_part, int(g2.total)])
	_ok("test_goals")


## 誓约：五条各自的判定、破了要静默降倍率并在结算里说明、空手要真清空随身物。
## 五条誓约全挑能抬多少（打印用）
func _vow_lift() -> float:
	var lift := 0.0
	for v in Data.table("challenge").vows:
		lift += float(v.mul) - 1.0
	return lift


func test_vows() -> void:
	var meta := State.new_meta()
	# 空手：身份带的随身物一件不留
	var rich := State.new_run("escort", meta, 77)
	check(not rich.home.is_empty(), "镖局趟子手开局本来就该有东西，测试前提不成立")
	var bare := State.new_run("escort", meta, 77, "normal", [], [], ["bare"])
	check(bare.home.is_empty(), "空手没清掉随身物：%s" % str(bare.home))
	check(rich.home.size() > bare.home.size(), "空手和没空手开局一样")
	# 不点灯：买过灯油就算破
	var lamp := State.new_run("escort", meta, 77, "normal", [], [], ["no_lamp"])
	check(is_equal_approx(Ledger.challenge_mul(lamp), 1.10), "不点灯没抬倍率：%.2f" % Ledger.challenge_mul(lamp))
	check(bool(Ledger.vow_results(lamp)[0].met), "还没买就判成破了")
	lamp.loc = "grocery"
	Pre.buy(lamp, "lamp_oil", 1)
	check(not bool(Ledger.vow_results(lamp)[0].met), "买了灯油却没判破")
	check(is_equal_approx(Ledger.challenge_mul(lamp), 1.0), "破了誓约倍率没收回去：%.2f" % Ledger.challenge_mul(lamp))
	# 不烧炭：买过木炭就算破（和"不点灯"共用 bought_none 判定，换个物品再验一遍）
	var coal := State.new_run("escort", meta, 77, "normal", [], [], ["no_charcoal"])
	check(is_equal_approx(Ledger.challenge_mul(coal), 1.05), "不烧炭没抬倍率：%.2f" % Ledger.challenge_mul(coal))
	check(bool(Ledger.vow_results(coal)[0].met), "还没买炭就判成破了")
	coal.loc = "grocery"
	Pre.buy(coal, "charcoal", 1)
	check(not bool(Ledger.vow_results(coal)[0].met), "买了木炭却没判破")
	# 不雇工：在营造坊订过一次活就算破。这是唯一一条实测真有代价的誓约（−35pp 劫满率）
	var hire := State.new_run("escort", meta, 77, "normal", [], [], ["no_order"])
	check(is_equal_approx(Ledger.challenge_mul(hire), 1.35), "不雇工没抬倍率：%.2f" % Ledger.challenge_mul(hire))
	check(bool(Ledger.vow_results(hire)[0].met), "还没下单就判成破了")
	hire.loc = "builder"
	check(Pre.order(hire, "door_bar") == "", "订门闩失败：%s" % Pre.order(hire, "door_bar"))
	check(int(State.tally(hire).orders) == 1, "下单没计数")
	check(not bool(Ledger.vow_results(hire)[0].met), "下了单却没判破")
	# 不设防：买过任何一件守具就算破（按类目判，不是按单个物品）
	var guard := State.new_run("escort", meta, 77, "normal", [], [], ["no_guard"])
	check(is_equal_approx(Ledger.challenge_mul(guard), 1.25), "不设防没抬倍率：%.2f" % Ledger.challenge_mul(guard))
	check(bool(Ledger.vow_results(guard)[0].met), "还没买守具就判成破了")
	guard.loc = "temple"
	Pre.buy(guard, "talisman", 1)
	check(not bool(Ledger.vow_results(guard)[0].met), "买了符咒却没判破")
	# 买别的东西不该误判（钱、米都不是守具）
	var guard2 := State.new_run("escort", meta, 77, "normal", [], [], ["no_guard"])
	guard2.loc = "rice_shop"
	Pre.buy(guard2, "rice", 1)
	check(bool(Ledger.vow_results(guard2)[0].met), "买了米却把不设防判破了")
	# 不修门：修过一次就算破
	var door := State.new_run("escort", meta, 77, "normal", [], [], ["no_door"])
	check(is_equal_approx(Ledger.challenge_mul(door), 1.05), "不修门没抬倍率：%.2f" % Ledger.challenge_mul(door))
	door.phase = "post"
	door.pday = 3
	door.t = 2 * Post.DAY + 60
	door.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	door.door.cur = 40
	Inv.add(door.home, "wood", 1)
	check(Post.act_repair(door, "door") == "", "修缮开不了工：%s" % Post.act_repair(door, "door"))
	check(int(State.tally(door).repair_door) == 1, "修门没计数")
	check(not bool(Ledger.vow_results(door)[0].met), "修了门却没判破")
	# 夜战稳守的自动修缮也要计数——它不走 act_repair，走 Defense.pay_mend，
	# 漏了它「不修门」就会被误判成"守住了"（实测就是这么漏的）
	var auto := State.new_run("escort", meta, 77, "normal", [], [], ["no_door"])
	auto.phase = "post"
	auto.pday = 3
	auto.t = 2 * Post.DAY + 60
	auto.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
	auto.door.cur = 40
	Inv.add(auto.home, "wood", 1)
	check(Post._mend_on(auto, "gate"), "夜间自动修缮没生效")
	check(int(State.tally(auto).repair_door) == 1, "夜间自动修门没计数，誓约会被误判成守住")
	check(not bool(Ledger.vow_results(auto)[0].met), "自动修了门却没判破")
	# 一趟：回家卸货超过一次就算破
	var trip := State.new_run("escort", meta, 77, "normal", [], [], ["one_trip"])
	check(is_equal_approx(Ledger.challenge_mul(trip), 1.00), "一趟的倍率该是 1.00（实测它更容易，不配给奖励）：%.2f" % Ledger.challenge_mul(trip))
	trip.loc = "rice_shop"
	Pre.travel(trip, "home")
	check(bool(Ledger.vow_results(trip)[0].met), "只回一趟就判破了")
	Pre.travel(trip, "rice_shop")
	Pre.travel(trip, "home")
	check(not bool(Ledger.vow_results(trip)[0].met), "回了两趟却没判破")
	# 决定性核对：一趟现在不给倍率，守住了总分必须和基准一模一样
	# （原来是 ×1.15 的核对，40 局实测它反而好赢 3 局，倍率降回 1.00）
	var t_a := State.new_run("escort", meta, 77, "normal", [], [], ["one_trip"])
	var t_b := State.new_run("escort", meta, 77)
	for r in [t_a, t_b]:
		r.phase = "ending"
		r.pday = 20
		r.waves_survived = 7
	var ta_total := int(Ledger.daoxin_gain(t_a).total)
	var tb_total := int(Ledger.daoxin_gain(t_b).total)
	check(ta_total == tb_total, "一趟不抬倍率，总分该和基准相同：%d vs %d" % [ta_total, tb_total])
	# 不设笼：院里摆了捕鼠笼就算破
	var trap := State.new_run("escort", meta, 77, "normal", [], [], ["no_trap"])
	check(bool(Ledger.vow_results(trap)[0].met), "还没摆就判成破了")
	trap.furniture = [{"id": "rat_trap", "uid": 1, "x": 0.0, "z": 0.0, "rot": 0, "job": {}}]
	check(not bool(Ledger.vow_results(trap)[0].met), "摆了捕鼠笼却没判破")
	# 多条同时：1.10 + 0.05 + 0.10 = 1.25，破一条就掉一档
	var three := State.new_run("escort", meta, 77, "normal", [], [], ["no_lamp", "no_door", "bare"])
	check(is_equal_approx(Ledger.challenge_mul(three), 1.25), "三条全守的倍率不对：%.2f" % Ledger.challenge_mul(three))
	Inv.add(three.home, "lamp_oil", 1)   # 直接塞进家不算买过，誓约不该破
	check(is_equal_approx(Ledger.challenge_mul(three), 1.25), "没买只是塞进来，不该判破")
	three.loc = "grocery"
	Pre.buy(three, "lamp_oil", 1)
	check(is_equal_approx(Ledger.challenge_mul(three), 1.15), "破一条后倍率不对：%.2f" % Ledger.challenge_mul(three))
	# 结算里要把破了的誓约写出来（否则玩家以为算错了）
	var g: Dictionary = Ledger.daoxin_gain(three)
	var said := false
	for l in g.lines:
		if "已破" in str(l[0]):
			said = true
	check(said, "破了誓约，结算里却没说明")
	# 誓约和凭仗同时挑：0.05 + 0.10 - 0.10 = 1.05
	var mix := State.new_run("escort", meta, 77, "normal", [], ["extra_silver"], ["no_door", "bare"])
	check(is_equal_approx(Ledger.challenge_mul(mix), 1.05), "誓约+凭仗混算不对：%.2f" % Ledger.challenge_mul(mix))
	var vs := []
	for v in Data.table("challenge").vows:
		vs.append("%s×%.2f" % [str(v.name), float(v.mul)])
	print("誓约（倍率按实测代价定价）：%s；%d 条全挑 ×%.2f" % ["、".join(vs), vs.size(), 1.0 + _vow_lift()])
	_ok("test_vows")


## 凭仗：开局真的发东西、倍率真的打折、三个凭仗扣到底也不破 0.5 的下限；
## 设施类凭仗要等尸劫降临才落地，不能开局就有。
## 无尽模式：劫满后接着守，每三夜一波、越往后越多。
## 这块以前一行测试都没有，而它是通关之后才会进的模式——真出问题玩家已经打了 20 日。
func test_endless() -> void:
	# 生成规则：第 20 日之后每 3 天一波，首波在第 23 日
	check(Defense.wave_for_day(21).is_empty(), "第 21 日不该有尸潮")
	check(Defense.wave_for_day(22).is_empty(), "第 22 日不该有尸潮")
	var w1: Dictionary = Defense.wave_for_day(23)
	check(not w1.is_empty(), "第 23 日该来第一波无尽的尸潮")
	check(int(w1.count) == 48, "无尽第 1 波数量不对：%d" % int(w1.count))
	var w2: Dictionary = Defense.wave_for_day(26)
	var w3: Dictionary = Defense.wave_for_day(29)
	check(int(w2.count) == 54, "无尽第 2 波该是 54：%d" % int(w2.count))
	check(int(w3.count) == 60, "无尽第 3 波该是 60：%d" % int(w3.count))
	# 修饰按 n 轮换，别四波一模一样
	check(str(w1.mods) != str(w2.mods), "无尽波浪的修饰没轮换：%s / %s" % [str(w1.mods), str(w2.mods)])

	# 真打一遍：机器人打到劫满后转无尽，一直守到死
	endless_after_win = true
	vows_picked = []
	var w := 0
	var days := 0
	var survived := 0
	var n := 0
	for k in 6:
		var r: Dictionary = play("escort", 7000 + k)
		n += 1
		if bool(r.endless):
			# 只统计真进了无尽的局：没劫满的局 waves_survived 不足 7，减出来是负数
			w += 1
			days += int(r.pday)
			survived += int(r.waves_survived) - 7
	endless_after_win = false
	check(w > 0, "6 局里没有一局走到无尽模式，测试没测到东西")
	check(survived > 0, "进了无尽却一波尸潮都没守住")
	print("无尽：6 局里 %d 局劫满，无尽阶段平均活到第 %.1f 日、多守 %.1f 波" % [w, days / float(maxi(1, w)), survived / float(maxi(1, w))])
	_ok("test_endless")


func test_boons() -> void:
	var meta := State.new_meta()
	var plain := State.new_run("escort", meta, 77)
	var silver0 := int(plain.silver)
	check(is_equal_approx(Ledger.challenge_mul(plain), 1.0), "没挑凭仗却改了倍率")
	# 多带盘缠：+800 文；倍率 1.0 - 0.10 = 0.90
	var money := State.new_run("escort", meta, 77, "normal", [], ["extra_silver"])
	check(int(money.silver) == silver0 + 800, "盘缠没发：%d vs %d" % [int(money.silver), silver0])
	check(is_equal_approx(Ledger.challenge_mul(money), 0.90), "盘缠的倍率不对：%.2f" % Ledger.challenge_mul(money))
	# 多带油：+2 桶柴油
	var oil := State.new_run("escort", meta, 77, "normal", [], ["extra_oil"])
	check(Inv.count(oil.home, "diesel") == 2, "柴油没发：%d" % Inv.count(oil.home, "diesel"))
	# 现成屋：开局不该有设施，尸劫降临后才并进来
	var room := State.new_run("escort", meta, 77, "normal", [], ["free_room"])
	check(room.facilities.is_empty(), "设施凭仗开局就生效了")
	check(is_equal_approx(Ledger.challenge_mul(room), 0.85), "现成屋的倍率不对：%.2f" % Ledger.challenge_mul(room))
	Pre.start_disaster(room)
	check("water_vat" in room.facilities and "garden_bed" in room.facilities,
		"尸劫降临后没并进设施：%s" % str(room.facilities))
	check(int(room.plots.size()) == 4, "扩建菜畦没多两块：%d" % room.plots.size())
	# 三个凭仗全挑：0.10+0.10+0.15 = 0.35 → 0.65，没到下限
	var all := State.new_run("escort", meta, 77, "normal", [], ["extra_silver", "extra_oil", "free_room"])
	check(is_equal_approx(Ledger.challenge_mul(all), 0.65), "三个凭仗的倍率不对：%.2f" % Ledger.challenge_mul(all))
	# 倍率真的乘到结算上：同一局表现，挑了凭仗道心变少，但了愿的固定分不参与乘法
	var both := State.new_run("escort", meta, 77, "normal", ["slay_200"], ["extra_silver"])
	for r in [plain, money, both]:
		r.phase = "ending"
		r.pday = 20
		r.kills = 200
		r.waves_survived = 7
	var g_plain: Dictionary = Ledger.daoxin_gain(plain)
	var g_money: Dictionary = Ledger.daoxin_gain(money)
	var g_both: Dictionary = Ledger.daoxin_gain(both)
	check(int(g_money.total) < int(g_plain.total), "挑了凭仗道心没变少")
	check(int(g_money.total) == int(round(int(g_plain.total) * 0.90)), "倍率没乘对：%d vs %d" % [
		int(g_money.total), int(round(int(g_plain.total) * 0.90))])
	check(int(g_both.total) - int(g_money.total) == 10, "了愿的 10 点应该全额加、不参与乘法：%d vs %d" % [
		int(g_both.total), int(g_money.total)])
	print("凭仗：盘缠 +800（×0.90）、多带油 +2 桶、现成屋 ×0.85 且灾后落地；三个全挑 ×0.65")
	_ok("test_boons")


## 载具：负重和赶路时辰都按 data/items.json 的 vehicle 块算；几辆同时有取载重最大的一辆，不叠加。
func test_vehicle() -> void:
	var meta := State.new_meta()
	var r := State.new_run("escort", meta, 77)
	var walk_cap := int(State.role(r).carry)
	var walk_cost := Pre.travel_cost(r, "rice_shop")
	check(Pre.vehicle_id(r) == "", "开局就有载具：%s" % Pre.vehicle_id(r))
	check(Pre.capacity(r) == walk_cap, "徒步负重不该有加成：%d" % Pre.capacity(r))
	# 板车：+20 斤、路程不变（板车不提速，只便宜）
	Inv.add(r.home, "barrow", 1)
	check(Pre.vehicle_id(r) == "barrow", "板车没被认出来")
	check(Pre.capacity(r) == walk_cap + 20, "板车负重不对：%d" % Pre.capacity(r))
	check(Pre.travel_cost(r, "rice_shop") == walk_cost, "板车不该改路程")
	# 独轮车：+40 斤，载重更大，所以盖过板车（不是叠加）
	Inv.add(r.home, "cart", 1)
	check(Pre.vehicle_id(r) == "cart", "独轮车没盖过板车：%s" % Pre.vehicle_id(r))
	check(Pre.capacity(r) == walk_cap + 40, "独轮车负重不对：%d" % Pre.capacity(r))
	check(Pre.travel_cost(r, "rice_shop") == walk_cost, "独轮车不该改路程")
	# 驴车：+70 斤、路程 ×0.6；三辆同时在也只按载重最大的那辆算
	Inv.add(r.home, "donkey_cart", 1)
	check(Pre.vehicle_id(r) == "donkey_cart", "驴车没被认出来")
	check(Pre.capacity(r) == walk_cap + 70, "几辆载具的负重被叠加了：%d" % Pre.capacity(r))
	# 提速只在远路上兑现：营造坊 2 时辰 × 0.6 = 1.2 → 1 个时辰，近处 1 × 0.6 还是 1（不能低于一个时辰）
	var far := maxi(1, int(round(2 * 0.6)))
	check(Pre.travel_cost(r, "builder") == far, "驴车去营造坊不对：%d，应为 %d" % [Pre.travel_cost(r, "builder"), far])
	check(far < 2, "驴车没把营造坊的路程压下来")
	check(Pre.travel_cost(r, "rice_shop") == walk_cost, "驴车不该把近路压到 0：%d" % Pre.travel_cost(r, "rice_shop"))
	# 车上带着也算：把驴车挪到车上，仍然生效
	Inv.add(r.home, "donkey_cart", -1)
	Inv.add(r.cart, "donkey_cart", 1)
	check(Pre.vehicle_id(r) == "donkey_cart", "车上的驴车不算数")
	check(Pre.capacity(r) == walk_cap + 70, "车上的载具没加负重")
	# 打折后不能低于一个时辰：近路 1 × 0.6 仍是 1
	check(Pre.travel_cost(r, "rice_shop") >= 1, "路程被折到 0 个时辰了")
	# 灾后清空所有载具（原来只清独轮车）
	Pre.start_disaster(r)
	check(Pre.vehicle_id(r) == "", "灾后还留着载具：%s" % Pre.vehicle_id(r))
	check(Inv.count(r.home, "donkey_cart") + Inv.count(r.cart, "donkey_cart") == 0, "灾后驴车没清掉")
	check(Inv.count(r.home, "cart") + Inv.count(r.cart, "cart") == 0, "灾后独轮车没清掉")
	print("载具：徒步 %d 斤 / 近处 %d 时辰 / 营造坊 %d 时辰；板车 +20、独轮车 +40、驴车 +70 且远路 %d 时辰" % [
		walk_cap, walk_cost, int(Pre.shop("builder").travel), far])
	_ok("test_vehicle")


## 难度预设：参数乘数要真的落到开局数值、消耗、寒冷和尸潮上；乱写的 id 要能退回寻常。
func test_difficulty() -> void:
	var meta := State.new_meta()
	var base := State.new_run("scholar", meta, 77)
	var doom := State.new_run("scholar", meta, 77, "doom")
	var mild := State.new_run("scholar", meta, 77, "mild")
	check(str(base.get("difficulty", "")) == "normal", "默认难度没记进存档")
	# 银两 / 气血：doom 是 0.6 / 0.9，mild 是 1.25 / 1.10
	check(int(doom.silver) == int(round(22000 * 0.6)), "荒年银两不对：%d" % int(doom.silver))
	check(int(mild.silver) == int(round(22000 * 1.25)), "暖冬银两不对：%d" % int(mild.silver))
	check(int(doom.attrs.hp_max) == int(round(100 * 0.9)), "荒年气血上限不对：%d" % int(doom.attrs.hp_max))
	check(int(mild.attrs.hp_max) == int(round(100 * 1.1)), "暖冬气血上限不对：%d" % int(mild.attrs.hp_max))
	# 食量 / 水量：同一段时间，doom 掉得更多、mild 掉得更少。
	# RATE.food = 2.0/小时，90 分钟 = 9 个 10 分钟刻度：寻常 3.0、荒年 4.05、暖冬 2.55
	var a := State.new_run("escort", meta, 77)
	var b := State.new_run("escort", meta, 77, "doom")
	var c := State.new_run("escort", meta, 77, "mild")
	for r in [a, b, c]:
		r.phase = "post"
		r.pday = 12
		r.t = (int(r.pday) - 1) * Post.DAY
		r.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
		r.attrs.food = 80.0
	for r in [a, b, c]:
		Post.advance(r, 90)
	check(absf(80.0 - float(a.attrs.food) - 3.0) < 0.05, "寻常年景 90 分钟没掉 3.0 饱腹：%.2f" % (80.0 - float(a.attrs.food)))
	check(absf(80.0 - float(b.attrs.food) - 4.05) < 0.05, "荒年 90 分钟没掉 4.05 饱腹：%.2f" % (80.0 - float(b.attrs.food)))
	check(absf(80.0 - float(c.attrs.food) - 2.55) < 0.05, "暖冬 90 分钟没掉 2.55 饱腹：%.2f" % (80.0 - float(c.attrs.food)))
	# 寒冷：冬至 cold 30，doom +14 = 44，mild -8 = 22；暖冬仍 > 0 所以还是会取暖
	for r in [doom, mild]:
		r.pday = 12
	check(Post.cold_of(doom) == 44, "荒年寒冷没加上去：%d" % Post.cold_of(doom))
	check(Post.cold_of(mild) == 22, "暖冬寒冷没减下来：%d" % Post.cold_of(mild))
	check(Post.cold_of(a) == 30, "寻常年景的寒冷被改了：%d" % Post.cold_of(a))
	# 尸潮：第 11 夜 24 只，doom 1.35 → 32，mild 0.85 → 20
	check(int(Defense.wave_for_day(11, 1.0).count) == 24, "第 11 夜基数不对")
	check(int(Defense.wave_for_day(11, 1.35).count) == 32, "荒年尸潮没放大：%d" % int(Defense.wave_for_day(11, 1.35).count))
	check(int(Defense.wave_for_day(11, 0.85).count) == 20, "暖冬尸潮没缩小：%d" % int(Defense.wave_for_day(11, 0.85).count))
	# 难度名字
	check(State.diff_name(doom) == "永夜", "难度名字不对：%s" % State.diff_name(doom))
	# 乱写的 id：数值全部退回 1.0，不把一局搅坏
	var junk := State.new_run("scholar", meta, 77, "不存在的难度")
	var d: Dictionary = State.diff(junk)
	for k in ["silver_mul", "hp_mul", "food_mul", "water_mul", "wave_mul"]:
		check(is_equal_approx(float(d[k]), 1.0), "乱 id 的 %s 没退回 1.0" % k)
	check(int(junk.silver) == 22000, "乱 id 把开局银两改了")
	# 旧存档没有 difficulty 字段：迁上来要补 normal
	var old := State.new_run("scholar", meta, 77)
	old.erase("difficulty")
	old.version = 6
	var up: Dictionary = Migrate.upgrade(old)
	check(str(up.get("difficulty", "")) == "normal" and int(up.version) == Migrate.VERSION, "旧存档没补上 difficulty")
	# cold_add 单点注入：整局跑不到「粮水不断但没柴」的局面，所以直接摆一个
	# 冬至冷夜、不生火、体温从 100 起跑，测前 3 小时的掉温速度（掉不到 0，也不触发冻死）。
	# 掉温 = cold/10 每小时：暖冬 2.2、寻常 3.0、荒年 3.6、永夜 4.4
	var cold_rows := []
	for diff_row in Data.table("difficulty"):
		var r := State.new_run("escort", meta, 77, str(diff_row.id))
		r.phase = "post"
		r.pday = 12
		r.t = (int(r.pday) - 1) * Post.DAY + Post.DUSK_AT
		r.today = {"ate": [], "actions": [], "kills": 0, "merit": 0}
		r.attrs.warmth = 100.0
		r.attrs.hp = 100.0
		var w0: float = r.attrs.warmth
		Post.advance(r, 180)
		cold_rows.append([str(diff_row.name), w0 - float(r.attrs.warmth)])
		print("  %-6s 冷夜 3 小时掉温 %.1f（%.2f/小时）" % [cold_rows[-1][0], float(cold_rows[-1][1]), float(cold_rows[-1][1]) / 3.0])
	# 四档单调，且暖冬的掉速必须明显低于寻常（否则 cold_add 是摆设）
	check(float(cold_rows[0][1]) < float(cold_rows[1][1]) and float(cold_rows[1][1]) < float(cold_rows[2][1]) and float(cold_rows[2][1]) < float(cold_rows[3][1]),
		"cold_add 不单调：%s" % str(cold_rows))
	check(float(cold_rows[0][1]) < 7.0 and float(cold_rows[1][1]) > 8.0,
		"暖冬和寻常的掉速没拉开：%s" % str(cold_rows))
	# 对得上理论值：cold/10 × 小时
	check(absf(float(cold_rows[1][1]) - 9.0) < 0.1, "寻常年景掉温不是 9.0：%.2f" % float(cold_rows[1][1]))
	check(absf(float(cold_rows[3][1]) - 13.2) < 0.1, "永夜掉温不是 13.2：%.2f" % float(cold_rows[3][1]))
	print("难度预设：永夜 银%d 血%d 冷%d° 第11夜%d只；暖冬 银%d 冷%d° 第11夜%d只；冷夜掉温 %.1f/%.1f/%.1f/%.1f" % [
		int(doom.silver), int(doom.attrs.hp_max), Post.cold_of(doom), int(Defense.wave_for_day(11, 1.35).count),
		int(mild.silver), Post.cold_of(mild), int(Defense.wave_for_day(11, 0.85).count),
		float(cold_rows[0][1]), float(cold_rows[1][1]), float(cold_rows[2][1]), float(cold_rows[3][1])])
	_ok("test_difficulty")


## 走到当天 20:00（生火那一刻）。8:00 可能撞上随机事件，弹出来就接着走。
func to_heat(run: Dictionary) -> void:
	var target := (int(run.pday) - 1) * Post.DAY + Post.HEAT_AT
	for k in 40:
		if int(run.t) >= target:
			return
		run.pending_event = ""
		var stop: String = Post.advance(run, target - int(run.t))
		if stop == "dead":
			return



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
	_ok("test_migrate")
