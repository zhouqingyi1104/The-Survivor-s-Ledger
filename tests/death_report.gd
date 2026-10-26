extends SceneTree
## 死因与复盘的规则测试：扣血记账、判词由账本生成、老存档兜底、复盘只引用真实数据。
## 运行：godot --headless --path . --script res://tests/death_report.gd
##
## 重点盯一条回归：改前死因是"先看渴、再看饿、再看瘟、再看冻，都不对上就写力竭而亡"，
## 于是被尸群扑死的人会被写成「饿死」（饱腹刚好为 0）。这里专门钉住这个反例。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_hurt_ledger()
	test_verdict_from_ledger()
	test_guess_fallback()
	test_report()
	test_hints()
	test_migrate()
	test_end_to_end_starve()
	print("[death_report] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、账本 ----------

func test_hurt_ledger() -> void:
	var run := _run()
	var hp0 := State.attr(run, "hp")
	State.hurt(run, 10.0, "starve")
	State.hurt(run, 6.0, "starve")
	State.hurt(run, 4.0, "overrun")
	check(State.attr(run, "hp") == hp0 - 20, "扣血没真的扣：%d → %d" % [hp0, State.attr(run, "hp")])
	check(int(run.hp_log.starve) == 16, "starve 累计不对：%s" % str(run.hp_log.starve))
	check(int(run.hp_log.overrun) == 4, "overrun 累计不对：%s" % str(run.hp_log.overrun))
	check(str(run.last_hurt.tag) == "overrun", "最后一笔没记成 overrun：%s" % str(run.last_hurt.tag))
	check(int(run.last_hurt.before) == hp0 - 16, "最后一笔的扣前气血不对：%d" % int(run.last_hurt.before))

	# 0 和负数不记账（回血、白扣都不该污染死因）
	var before: Dictionary = run.hp_log.duplicate(true)
	State.hurt(run, 0.0, "plague")
	State.hurt(run, -5.0, "plague")
	check(run.hp_log == before, "0 或负数被记进了账本：%s" % str(run.hp_log))
	# 回血走 add_attr，不进账本
	State.add_attr(run, "hp", 30)
	check(run.hp_log == before, "睡觉回血被记成了失血：%s" % str(run.hp_log))

	# 只剩 3 点血时挨 40：账本只记 3，不把溢出灌进死因
	var spill := _run()
	spill.attrs.hp = 3
	State.hurt(spill, 40.0, "bite")
	check(int(spill.hp_log.bite) == 3, "账本把溢出的伤害也记了：%s" % str(spill.hp_log.bite))
	check(int(spill.last_hurt.amount) == 3, "最后一击记成了溢出后的数：%s" % str(spill.last_hurt.amount))

	# 老存档 / 手改过的 run 没有账本字段也不能崩
	var bare := _run()
	bare.erase("hp_log")
	bare.erase("last_hurt")
	State.hurt(bare, 3.0, "cold")
	check(int(bare.hp_log.cold) == 3, "没有账本字段时没建起来：%s" % str(bare.hp_log))


# ---------- 二、判词 ----------

func test_verdict_from_ledger() -> void:
	# 饿死
	var starve := _run()
	starve.attrs.food = 0
	State.hurt(starve, 99.0, "starve")
	var said := DeathReport.verdict(starve)
	check(said.contains("饿死"), "饿死的判词不对：%s" % said)
	check(said.contains("第1日"), "判词里没有日子：%s" % said)

	# 冻死（酷寒与受冻都算冻死，但构成里分开记）
	var freeze := _run()
	State.hurt(freeze, 50.0, "freeze")
	check(DeathReport.verdict(freeze).contains("冻死"), "酷寒的判词不对：%s" % DeathReport.verdict(freeze))

	# 回归：饱腹和体温都见底，但真正打死人的是院破——不能再写成饿死
	var overrun := _run()
	overrun.attrs.food = 0
	overrun.attrs.water = 0
	overrun.attrs.warmth = 8
	State.hurt(overrun, 80.0, "overrun")
	var overrun_said := DeathReport.verdict(overrun)
	check(overrun_said.contains("院门被撞破"), "院破而死的判词不对：%s" % overrun_said)
	check(not overrun_said.contains("饿死"), "属性见底就把死因抢去写成饿死了（改前的错法）：%s" % overrun_said)
	check(not overrun_said.contains("渴死"), "属性见底就把死因抢去写成渴死了（改前的错法）：%s" % overrun_said)
	# 同一份局面，老办法（属性猜测）确实会说错——这就是这条回归的意义
	check(DeathReport.guess(overrun).contains("渴死"), "兜底猜测的对照值变了，回归前提不成立：%s" % DeathReport.guess(overrun))

	# 现场写好的判词优先（尸潮破门这种带场景的句子不该被账本顶掉）
	var explicit := _run()
	State.hurt(explicit, 30.0, "overrun")
	check(DeathReport.verdict(explicit, "尸潮破门，死在第 3 夜。") == "尸潮破门，死在第 3 夜。",
		"现场判词被账本顶掉了")

	# 主因取量最大的那项，不受记账先后影响
	var multi := _run()
	State.hurt(multi, 5.0, "cold")
	State.hurt(multi, 40.0, "bite")
	State.hurt(multi, 12.0, "starve")
	check(str(DeathReport.main_source(multi).tag) == "bite", "主因没取最大项：%s" % str(DeathReport.main_source(multi).tag))

	# 两项打平：算最后落下的那一下（它才是真正把气血打光的）
	var tie := _run()
	State.hurt(tie, 40.0, "starve")
	State.hurt(tie, 40.0, "freeze")
	check(str(DeathReport.main_source(tie).tag) == "freeze", "平手时没取最后一击：%s" % str(DeathReport.main_source(tie).tag))
	check(DeathReport.verdict(tie).contains("冻死"), "平手时的判词与最后一击不一致：%s" % DeathReport.verdict(tie))


# ---------- 三、没有账本的老档 ----------

func test_guess_fallback() -> void:
	var bare := _run()
	var said := DeathReport.verdict(bare)
	check(said.contains("第1日"), "兜底判词也没有日子（改前是「力竭而亡。」）：%s" % said)
	check(not said.contains("力竭而亡"), "还在用旧的力竭而亡：%s" % said)

	var thirsty := _run()
	thirsty.attrs.water = 0
	check(DeathReport.guess(thirsty).contains("渴死"), "兜底没认出渴：%s" % DeathReport.guess(thirsty))
	var frozen := _run()
	frozen.attrs.warmth = 5
	check(DeathReport.guess(frozen).contains("冻死"), "兜底没认出冻：%s" % DeathReport.guess(frozen))


# ---------- 四、复盘 ----------

func test_report() -> void:
	var run := _run()
	State.hurt(run, 30.0, "starve")
	State.hurt(run, 12.0, "overrun")
	State.hurt(run, 70.0, "freeze")   # 只剩 58，账本这条只记 58
	run.log = [
		"【第1日·07:00】天亮了。",
		"【第1日·08:00】隔壁来讨水。",
		"【第1日·18:00】天黑了。",
		"【第1日·23:00】院墙被撞破。",
		"【第1日·23:30】气血已尽。冻死。",
	]
	var reps: Dictionary = DeathReport.report(run)
	# 账本记的是实际掉掉的血：30 + 12 + 58 = 100（第三下超出剩余的部分不算）
	check(int(reps.total) == 100, "总失血不对：%d" % int(reps.total))
	var shares: Array = reps.shares
	check(shares.size() == 3, "构成项数不对：%d" % shares.size())
	check(str(shares[0].tag) == "freeze" and int(shares[0].amount) == 58, "构成没按量降序：%s" % str(shares))
	check(str(shares[0].name) == "酷寒", "构成名不对：%s" % str(shares[0].name))
	# 最后一击带扣前扣后
	check(str(reps.last).contains("酷寒") and str(reps.last).contains("气血"), "最后一击的说明不全：%s" % str(reps.last))
	check(str(reps.last).contains("→ 0"), "最后一击没写扣到几点：%s" % str(reps.last))
	# 此前两条（残页版面只放两条）：跳过「气血已尽」那句
	var steps: Array = reps.steps
	check(steps.size() == 2, "此前记录条数不对：%d" % steps.size())
	for line in steps:
		check(not str(line).contains("气血已尽"), "把死亡那句也当成了此前记录：%s" % str(line))
	check(str(steps[1]).contains("院墙被撞破"), "此前两条不是最新的两条：%s" % str(steps))

	# 总数从整本账算：来源多于四项时也不能少算
	var many := _run()
	for tag in ["starve", "thirst", "plague", "freeze", "cold", "wound"]:
		State.hurt(many, 4.0, tag)
	var many_reps: Dictionary = DeathReport.report(many)
	check((many_reps.shares as Array).size() == 4, "构成没截成四项：%d" % (many_reps.shares as Array).size())
	check(int(many_reps.total) == 24, "只显示四项就少算了总数：%d" % int(many_reps.total))

	# 只列 >1 的来源：零星 0.4 的擦伤不该占一行
	var small := _run()
	State.hurt(small, 20.0, "cold")
	State.hurt(small, 0.4, "plague")
	check(DeathReport.report(small).shares.size() == 1, "零星失血被列进了构成：%s" % str(DeathReport.report(small).shares))

	# 没有账本的老档：报告不崩、构成空、不编
	var bare := _run()
	var bare_reps: Dictionary = DeathReport.report(bare)
	check(int(bare_reps.total) == 0 and (bare_reps.shares as Array).is_empty(), "老档复盘不该有构成")
	check(str(bare_reps.last) == "", "老档不该编出最后一击：%s" % str(bare_reps.last))


# ---------- 五、提示只引用真实数据 ----------

func test_hints() -> void:
	# 冻死：没生火 + 仓里有柴 → 说出还剩几根
	var freeze := _run()
	freeze.heated = false
	Inv.add(freeze.home, "firewood", 4)
	Inv.add(freeze.home, "charcoal", 2)
	var hints := DeathReport.hints(freeze, "freeze")
	var joined := " / ".join(hints)
	check(joined.contains("没生火"), "没提醒生火：%s" % joined)
	check(joined.contains("4 根柴"), "没说出还剩几根柴：%s" % joined)
	check(joined.contains("地窖"), "没修地窖该提一句：%s" % joined)
	check(hints.size() <= 2, "提醒超过两条，会把残页撑破：%s" % str(hints))

	# 生了火但只烧半夜：不说"没生火"，改说一捆柴不够
	var half := _run()
	half.heated = true
	half.heat_weak = true
	check(" / ".join(DeathReport.hints(half, "freeze")).contains("只够烧半夜"), "一捆柴只烧半夜没说出来")

	# 主因与提醒必须同源：判词说冻死，提醒就不该讲饿
	var tie := _run()
	State.hurt(tie, 40.0, "starve")
	State.hurt(tie, 40.0, "freeze")
	check(str(DeathReport.report(tie).shares[0].tag) == "freeze", "平手时构成首位与判词不一致")
	check(" / ".join(DeathReport.report(tie).hints).contains("没生火"), "平手时提醒讲的不是判词那件事")

	# 饿死：仓里有米时说"还有 N 份"，没有时说"没有了"，不能都说一样
	var starve := _run()
	starve.home = {}
	Inv.add(starve.home, "rice", 3)
	var with_food := " / ".join(DeathReport.hints(starve, "starve"))
	check(with_food.contains("3 份吃的"), "没说出还剩几份吃的：%s" % with_food)
	var empty := _run()
	empty.home = {}
	var no_food := " / ".join(DeathReport.hints(empty, "starve"))
	check(no_food.contains("没有吃的"), "仓空时没说清楚：%s" % no_food)
	check(not no_food.contains("份吃的没做成饭"), "仓空时还编了个剩余量：%s" % no_food)

	# 院破：只有真的砸穿到 0 才提
	var broken := _run()
	broken.door.cur = 0
	broken.wall.cur = 0
	var hit := " / ".join(DeathReport.hints(broken, "overrun"))
	check(hit.contains("院门") and hit.contains("院墙"), "没说清哪里被砸穿：%s" % hit)
	var intact := _run()
	check((DeathReport.hints(intact, "overrun") as Array).is_empty(), "院子完好却编了句破院的提醒")

	# 没有对应建议的来源不硬凑
	check((DeathReport.hints(_run(), "") as Array).is_empty(), "主因未知时不该给建议")
	check((DeathReport.hints(_run(), "unknown_tag") as Array).is_empty(), "未知来源不该给建议")


# ---------- 六、迁移 ----------

func test_migrate() -> void:
	var old := {"version": 20,
		"run": {"version": 20, "pday": 3, "death_cause": "旧卷写下的死因", "attrs": {"hp": 0, "hp_max": 90}},
		"snapshots": {"1": {"version": 20, "pday": 1, "attrs": {"hp": 90, "hp_max": 90}}}}
	var up := Migrate.save(old)
	check(int(up.run.version) == Migrate.VERSION, "主档版本没升到 %d：%d" % [Migrate.VERSION, int(up.run.version)])
	check(up.run.hp_log is Dictionary and (up.run.hp_log as Dictionary).is_empty(), "老档被补出了假账本：%s" % str(up.run.hp_log))
	check(up.run.last_hurt is Dictionary, "老档缺 last_hurt")
	check(str(up.run.death_cause) == "旧卷写下的死因", "迁移把旧死因改掉了：%s" % str(up.run.death_cause))
	check(int(up.snapshots["1"].version) == Migrate.VERSION, "快照版本没升级")


# ---------- 七、真跑一次饿死 ----------

func test_end_to_end_starve() -> void:
	var run := _run()
	Pre.start_disaster(run)
	Post.begin_day(run)
	run.attrs.food = 0
	run.attrs.water = 90
	run.attrs.warmth = 90
	run.attrs.hp = 2
	var guard := 0
	while run.phase == "post" and guard < 40:
		guard += 1
		Post.advance(run, 10)
	check(run.phase == "dead", "饿死没发生（第 %d 日，气血 %d）" % [int(run.pday), State.attr(run, "hp")])
	check(not str(run.death_cause).is_empty(), "死了却没有死因")
	check(str(run.death_cause).contains("饿死"), "死因不是饿死：%s" % str(run.death_cause))
	check(not str(run.death_cause).contains("力竭而亡"), "还在用旧的力竭而亡：%s" % str(run.death_cause))
	check(float(run.hp_log.get("starve", 0.0)) > 0.0, "饿死却没有受饿记录：%s" % str(run.hp_log))
	var reps: Dictionary = DeathReport.report(run)
	check(int(reps.total) > 0, "复盘总失血为 0")
	check(str(reps.last).contains("受饿"), "最后一击不是受饿：%s" % str(reps.last))


# ---------- 小工具 ----------

func _run() -> Dictionary:
	return State.new_run("scholar", State.new_meta(), 20261026)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
