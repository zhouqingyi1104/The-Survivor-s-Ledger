extends Node
## 界面冒烟测试：在 3D 场景里走一遍完整流程——
## 城里点铺子走过去、订制、买东西、熬过三日 → 宅院里打水、做饭、吃饭、歇息、入夜看演出、翻夜报 →
## 出门进废墟翻找、回家 → 存读档 → 死亡翻生死簿 → 合上此录。
## 按钮按文字找，场景交互直接调界面上的方法（interact / search / finish）。存档写到测试专用文件。
## 运行：godot --headless --path . res://tests/ui_smoke.tscn

const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Home = preload("res://scripts/core/home.gd")

var failures := 0
var main: Control


func _ready() -> void:
	Game.save_path = "user://test_save.json"
	Game.meta_path = "user://test_meta.json"
	_cleanup()
	Game.meta = State.new_meta()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames()
	await run_flow()
	print("界面冒烟测试：失败 %d 处" % failures)
	_cleanup()
	get_tree().quit(1 if failures > 0 else 0)


func screen() -> Node:
	var holder: Node = main.get_child(1)
	return holder.get_child(0) if holder.get_child_count() > 0 else null


func run_flow() -> void:
	await press("新开一卷")
	check(Game.screen == "roles", "没进选身份界面")
	await press("就是他了")
	check(Game.screen == "difficulty", "没进选难度界面")
	await press("就这个")
	check(Game.screen == "challenge", "没进立愿界面")
	# 勾选要能重画而不叠层（build() 只往 self 追加，忘了 clear 就会每点一次多一层）
	var rows_before: int = screen().find_children("*", "Label", true, false).size()
	screen()._toggle("slay_200", true, screen()._picked)
	var rows_after: int = screen().find_children("*", "Label", true, false).size()
	check(rows_after == rows_before, "勾选后界面重复叠加了：%d → %d" % [rows_before, rows_after])
	check("slay_200" in screen()._picked, "勾了愿却没记下")
	screen()._toggle("slay_200", false, screen()._picked)
	# 开局模式（守到死 / 每日一局）：勾上要记住、取消要取消、选了才展开说明。
	# 这里不开局验证 endless 有没有带进 run——开了就再也回不到结局，后面整段流程都跑不了，
	# 那条由 sim_test 的 test_mode 用 Game.new_game 直接验。
	var labels_before: int = screen().find_children("*", "Label", true, false).size()
	screen()._toggle_mode(true)
	check(screen()._endless, "守到死没勾上")
	screen()._toggle_mode(false)
	check(screen()._daily, "每日一局没勾上")
	check(screen().find_children("*", "Label", true, false).size() > labels_before, "选了模式却没展开说明")
	screen()._toggle_mode(true)
	screen()._toggle_mode(false)
	check(not screen()._endless and not screen()._daily, "开局模式取消不掉")
	# 同院的人：带上要记住、最多 2 人、能取消
	screen()._toggle_mate("afu")
	screen()._toggle_mate("carpenter")
	check("afu" in screen()._mates and "carpenter" in screen()._mates, "带人没记下")
	screen()._toggle_mate("xiaoman")
	check(screen()._mates.size() == 2, "院里最多住 2 人，塞进第 3 个了")
	screen()._toggle_mate("afu")
	check(not "afu" in screen()._mates, "人取消不掉")
	screen()._toggle_mate("afu")
	# 主流程按"院里没人"跑（带人只在天亮有动静，这里不让它插进后面的断言），
	# 结尾再真开一局验证同伴有没有带进 run
	screen()._toggle_mate("afu")
	screen()._toggle_mate("carpenter")
	check(screen()._mates.is_empty(), "人清不干净")
	await press("普通行囊")
	check(Game.screen == "pre" and Game.run.role == "scholar", "没开局")
	check(str(Game.run.get("difficulty", "")) != "", "开局没带上难度")
	check(State.goals_of(Game.run).is_empty(), "选了不立愿却带着愿开局")
	screen().world.walk_speed = 400.0

	# ---- 备劫：走到营造坊订门闩，到米行买米，到杂货铺买柴，回家 ----
	await press("★ 营造坊")
	await wait_until(func(): return not screen().world.walking and UI_has("订制"), 5.0)
	check(Game.run.loc == "builder", "没走到营造坊")
	await press("订制")
	check("door_bar" in Game.run.orders, "没订上门闩")
	await press("合上")
	await press("米行")
	await wait_until(func(): return UI_has("买一"), 5.0)
	await press("买一")
	await press("买一")
	check(int(Game.run.cart.get("rice", 0)) == 2, "没买到米：%s" % str(Game.run.cart))
	await press("合上")
	await press("杂货铺")
	await wait_until(func(): return UI_has("买一"), 5.0)
	await press("买一")
	check(int(Game.run.cart.get("firewood", 0)) == 1, "没买到柴：%s" % str(Game.run.cart))
	await press("合上")
	await press("家")
	await wait_until(func(): return not screen().world.walking, 5.0)
	check(int(Game.run.home.get("rice", 0)) == 2, "回家没卸货")
	# 第一日时辰用得差不多了，不一定要确认；第二日一早就歇，必须确认
	await press("回家歇息")
	if UI_has("就这样吧"):
		await press("就这样吧")
	check(int(Game.run.day) == 2, "第一日没结束")
	await press("回家歇息")
	check(UI_has("就这样吧"), "还剩六个时辰就歇，没有确认")
	await press("就这样吧")
	check(int(Game.run.day) == 3, "备劫天数不对：%d" % int(Game.run.day))
	await press("熬到天黑")
	await press("就这样吧")
	check(Game.screen == "post" and int(Game.run.pday) == 1, "尸劫没降临")

	# ---- 劫中第一日：走到井边打水 ----
	var home: Node = screen()
	await handle_event()
	home.perform("well", "打水")
	await wait_until(func(): return Post.is_busy(Game.run), 12.0)
	check(Post.is_busy(Game.run) and Game.run.busy.kind == "water", "没走到井边打上水")
	home.advance(20)
	await _frames()
	check(Game.run.well_used and not Post.is_busy(Game.run), "打水没做完")
	# 做饭：灶台菜单 → 下锅 → 等一个时辰
	act_now("stove", "生火")
	await _frames()
	await press("下锅")
	check(Post.is_busy(Game.run) and Game.run.busy.kind == "cook", "没开始做饭")
	check(not UI_has("下锅"), "开工后做饭窗没关")
	home.advance(70)
	await _frames()
	check(int(Game.run.home.get("congee", 0)) > 0, "没做出白粥")
	Dialogs.inventory()
	await _frames()
	await press("吃")
	await press("合上")
	# 添置家具：弹窗 → 选中 → 点地面放下 → 做完出现
	Inv.add(Game.run.home, "wood", 4)
	Inv.add(Game.run.home, "nails", 2)
	Dialogs.furnish()
	await _frames()
	check(UI_has("去摆"), "没打开添置家具")
	Dialogs._pick_furnish("armchair")
	await _frames()
	check(Game.placing == "armchair", "没进摆放模式")
	# 摆放预览：绿=放下，红=放不下
	Game.placing_at = Vector3(-4.5, 0.0, 3.5)
	await _frames()
	check(screen()._ghost != null and screen()._ghost.visible, "摆放预览没显示")
	var green: Color = screen()._ghost_mat.albedo_color
	Game.placing_at = Vector3(0.0, 0.0, 2.0)   # 中路：不许摆
	await _frames()
	var red: Color = screen()._ghost_mat.albedo_color
	check(red.g < green.g, "放不下的位置没变红")
	Game.placing_at = null
	var chairs := Home.count(Game.run, "armchair")
	screen()._place_at(Vector3(-4.5, 0.0, 3.5))
	await _frames()
	check(Post.is_busy(Game.run) and str(Game.run.busy.kind) == "furnish", "摆放没开工：%s" % str(Game.run.busy))
	check(Game.placing == "", "放完了还在摆放模式")
	home.advance(60)
	await _frames()
	check(Home.count(Game.run, "armchair") == chairs + 1, "圈椅没摆出来")
	# 出门搜寻
	act_now("gate", "出门")
	await _frames()
	await press("出发")
	check(Game.screen == "explore", "没进废墟场景")
	screen().search(0)
	await _frames()
	check(Game.run.explore.spots[0].done, "没翻成")
	screen().finish()
	await _frames()
	check(Game.screen == "post" and Game.run.explore.is_empty(), "没回家")
	home = screen()
	# 天黑就寝，一觉到天亮
	await skip_to(Post.DUSK_AT + 30)
	act_now("bed", "就寝")
	await _frames()
	check(Game.run.sleeping, "没睡下")
	await skip_to(Post.DAY)
	await wait_until(func(): return UI_has("翻过这一页"), 3.0)
	check(UI_has("翻过这一页"), "天亮没弹功过格")
	await press("翻过这一页")
	check(int(Game.run.pday) == 2, "没进第二日：%d" % int(Game.run.pday))

	# ---- 第二夜：定方针 → 尸潮演出 → 夜战面板 → 逐轮结算 → 战报 ----
	await skip_to(Post.CURFEW_AT)
	await pass_policy()
	check(Game.run.night_policy != "", "没定下守夜方针")
	await skip_to(Post.WAVE_AT)
	await wait_until(func(): return screen()._show != null, 3.0)
	check(screen()._show != null, "尸潮没有演出")
	await press("跳过")
	await _frames()
	# 夜战面板：三面都在，能修能等
	Dialogs.night_panel()
	await _frames()
	check(UI_has("修缮"), "夜战面板没有修缮")
	check(UI_has("开门迎敌"), "夜战面板没有开门迎敌")
	await press("等下一轮")
	# 开门 / 院门口的活人 / 关门
	check(not bool(Game.run.door_open), "门一开始就是开的")
	Game.act(func(): return Post.toggle_gate(Game.run))
	await _frames()
	check(bool(Game.run.door_open), "门没打开")
	Game.act(func():
		Post.start_fight(Game.run, 2, false)
		return "")
	await _frames()
	check(not Game.run.fight.is_empty(), "院门没起战")
	screen()._swing()
	await _frames()
	# 架刀：抬得起来就进冷却
	screen()._guard()
	await _frames()
	check(float(Game.run.fight.get("block_cd", 0.0)) > 0.0, "架刀没生效")
	# 被啃的东西要在场景里留下痕迹
	screen().world.show_wreck(0, Vector3(3.5, 0.0, 1.4), "crop")
	await _frames()
	check(not screen().world._debris.is_empty(), "破坏没留下碎屑")
	# 家具被砸：塌料摆出来，菜单只剩「重修」（验完立刻复原，后面还要做饭）
	Post.apply_wreck(Game.run, 3)
	screen().sync_world()
	await _frames()
	check("stove" in Game.run.broken, "灶台被砸了没记下来")
	check(screen().world._rubbles.has("stove"), "灶台塌了却没摆出塌料")
	var menu: Array = screen().actions_for("stove")
	check(str(menu[0][0]).begins_with("重修"), "灶台菜单里没有重修：%s" % str(menu[0][0]))
	Game.run.broken.erase("stove")
	screen().sync_world()
	await _frames()
	check(not screen().world._rubbles.has("stove"), "修好了塌料还在")
	var sum: Dictionary = NightFight.finish(Game.run.fight)
	Game.act(func():
		Post.end_fight(Game.run, sum)
		return "")
	await _frames()
	check(Game.run.fight.is_empty(), "院门战没清掉")
	Game.act(func(): return Post.toggle_gate(Game.run))
	await _frames()
	check(not bool(Game.run.door_open), "门没关上")
	# 第一轮之后到第二轮
	screen().advance(Post.WAVE_AT + 40 - Post.day_minute(Game.run) + 1)
	await _frames()
	screen().advance(Post.WAVE_AT + 80 - Post.day_minute(Game.run) + 1)
	await _frames()
	await wait_until(func(): return UI_has("接着守夜"), 3.0)
	check(int(Game.run.wave_day) == 2, "尸潮没结算")
	await press("接着守夜")
	check(Game.run.wave_report.is_empty(), "战报没关")
	check(int(Game.run.waves_survived) >= 1, "守住的场次没记上")

	# ---- 存读档 ----
	Game.go("title")
	await _frames()
	check(Game.screen == "title", "没回标题")
	await press("续写此录")
	check(Game.screen == "post" and int(Game.run.pday) == 2, "读档失败")

	# ---- 劫满 → 结局界面 → 守下去转无尽 ----
	# 真打满 20 日太慢，直接把局面推到第 20 日天亮。测完把状态还回去，
	# 否则后面的死亡 / 翻页断言会撞上"第 21 日、无尽模式"这个不一样的局面。
	var keep: Dictionary = Game.run.duplicate(true)
	Game.run.pday = 20
	# t 要跟 pday 对齐：第 20 夜天亮时 t = pday × 一天分钟数，主线（Mainline.finish_dawn）
	# 按 t 算天数，只改 pday 会被当成"天才第 3 天"，进不了结局
	Game.run.t = int(Game.run.pday) * Post.DAY
	Game.run.dawn_due = true
	Post.ack_dawn(Game.run)
	check(Game.run.phase == "ending", "第 20 日天亮没转结局：%s" % str(Game.run.phase))
	Game.go("ending")
	await _frames()
	check(Game.screen == "ending", "没进结局界面")
	await press("守 下 去")
	check(Game.screen == "post" and bool(Game.run.endless), "守下去没转成无尽")
	check(int(Game.run.pday) == 21, "转无尽后该是第 21 日：%d" % int(Game.run.pday))
	Game.run = keep
	Game.go("post")
	await _frames()
	check(not bool(Game.run.endless), "测完没把无尽状态还原")

	# ---- 死亡 → 翻回昨日 ----
	Game.act(_kill)
	await _frames()
	check(Game.screen == "dead", "没进生死簿界面")
	await press("翻回去")
	check(Game.screen == "post" and int(Game.run.pday) == 1, "翻回昨日失败：第 %d 日" % int(Game.run.pday))
	check(Post.day_minute(Game.run) == 0, "翻回后不在清晨")
	check(int(Game.run.attrs.hp_max) == 90, "寿元没折损")

	# ---- 死亡 → 合上此录 ----
	Game.act(_kill)
	await _frames()
	await press("合上")
	check(Game.screen == "title" and Game.run.is_empty(), "合上此录失败")
	check(int(Game.meta.deaths) >= 1, "死亡次数没记上")

	# ---- 开局模式：守到死 / 每日一局 ----
	# 界面只置 Game.pending_*，很容易忘了往下传给 new_game，所以这里真开一局验一次。
	# 放在最后：开一局会把界面切走，中间插进来后面的流程就断了。
	var keep_save := Game.no_save
	Game.no_save = true
	Game.new_game("scholar", "normal", [], [], [], true, true, ["afu", "carpenter"])
	check(bool(Game.run.endless), "选了守到死，开局却是寻常局")
	check(str(Game.run.flags.get("daily", "")) != "", "每日一局没记进 run.flags")
	check(int(Game.run.seed) == State.daily_seed(), "每日一局的种子不是今天的：%d" % int(Game.run.seed))
	check((Game.run.get("companions", []) as Array) == ["afu", "carpenter"], "同院的人没带进 run")
	check(Game.screen == "pre", "带模式开局没进备劫界面")
	# 守到死：第 20 日天亮不进结局，照常开新的一天（寻常局的对照在上面已经验过）
	Game.run.phase = "post"
	Game.run.pday = 20
	Game.run.dawn_due = true
	Post.ack_dawn(Game.run)
	check(Game.run.phase == "post", "守到死：第 20 日天亮不该进结局（%s）" % str(Game.run.phase))
	check(int(Game.run.pday) == 21, "守到死：天亮后该接着开第 21 日：%d" % int(Game.run.pday))
	# 每日一局的记分板：结局界面先预览一次（这一局还没落盘），合上此录后真记进 meta
	Game.run.phase = "ending"
	Game.go("ending")
	await _frames()
	check(Game.screen == "ending", "每日局没进结局界面")
	var d0 := int(Game.meta.daily.get("runs", 0))
	Game.close_book()
	check(int(Game.meta.daily.get("runs", 0)) == d0 + 1, "每日一局结算后没记进记分板")
	check(str(Game.meta.daily.get("day", "")) == Game.today_text(), "记分板记的日子不对")
	check(int(Game.meta.daily.get("best", {}).get("endless", -1)) >= 0, "守到死的成绩没进自己那一组")
	Game.new_game("scholar", "normal", [], [], [], false, false)
	check(not bool(Game.run.endless), "没挑守到死却带着无尽开局")
	check(str(Game.run.flags.get("daily", "")) == "", "没挑每日一局却记了日期")
	Game.run = {}
	Game.no_save = keep_save
	Game.go("title")


## 不走路，直接做物件上的某个动作。
func act_now(id: String, prefix: String) -> void:
	for a in screen().actions_for(id):
		if String(a[0]).begins_with(prefix):
			check(a[2] == "", "%s·%s 做不了：%s" % [id, prefix, a[2]])
			a[1].call()
			return
	check(false, "没有这个动作：%s %s" % [id, prefix])


## 快进到当天第 m 分钟（中途的事件随手处理掉）。
func skip_to(m: int) -> void:
	var guard := 0
	while Post.day_minute(Game.run) < m and guard < 50 and Game.run.phase == "post":
		guard += 1
		if Game.run.pending_event != "":
			await handle_event()
			continue
		if Post.blocked(Game.run) or screen()._show != null:
			break
		screen().advance(mini(120, m - Post.day_minute(Game.run)))
		await _frames()


func _kill() -> String:
	Game.run.attrs.hp = 0
	State.check_death(Game.run, "测试身死")
	return ""


func handle_event() -> void:
	if Game.run.pending_event == "":
		return
	for b in _buttons(""):
		if b.get_parent() is VBoxContainer and b.alignment == HORIZONTAL_ALIGNMENT_LEFT and not b.disabled:
			b.pressed.emit()
			await _frames()
			break
	await press("知道了")


## 尸潮夜的守夜方针弹窗：选「亲自调度」，好让下面的手动操作能用。
func pass_policy() -> void:
	if UI_has("亲自调度"):
		await press("亲自调度")


# ---------- 工具 ----------

func press(prefix: String) -> void:
	for b in _buttons(prefix):
		if not b.disabled:
			b.pressed.emit()
			await _frames()
			return
	check(false, "找不到可按的按钮：" + prefix)


func UI_has(prefix: String) -> bool:
	return not _buttons(prefix).is_empty()


## 弹窗在最上层，先找弹窗里的（后弹出的优先），再找界面上的。
func _buttons(prefix: String) -> Array:
	var modals := main.get_child(2).get_children()
	modals.reverse()
	var out := []
	for m in modals:
		_walk(m, prefix, out)
	if out.is_empty():
		_walk(main.get_child(1), prefix, out)
	return out


func _walk(node: Node, prefix: String, out: Array) -> void:
	if node is Button and node.is_visible_in_tree() and not node.is_queued_for_deletion() and node.text.begins_with(prefix):
		out.append(node)
	for c in node.get_children():
		_walk(c, prefix, out)


func wait_until(cond: Callable, timeout: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < timeout and not cond.call():
		await get_tree().process_frame
	await _frames()


func _frames() -> void:
	for k in 3:
		await get_tree().process_frame


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("断言失败：" + msg)


func _cleanup() -> void:
	for f in ["user://test_save.json", "user://test_meta.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
