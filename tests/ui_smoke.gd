extends Node
## 界面冒烟测试：在 3D 场景里走一遍完整流程——
## 城里点铺子走过去、订制、买东西、熬过三日 → 宅院里打水、做饭、吃饭、歇息、入夜看演出、翻夜报 →
## 出门进废墟翻找、回家 → 存读档 → 死亡翻生死簿 → 合上此录。
## 按钮按文字找，场景交互直接调界面上的方法（interact / search / finish）。存档写到测试专用文件。
## 运行：godot --headless --path . res://tests/ui_smoke.tscn

const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")

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
	check(Game.screen == "pre" and Game.run.role == "scholar", "没开局")
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
