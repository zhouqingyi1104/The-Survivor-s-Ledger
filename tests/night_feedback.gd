extends Node
## B3：真实视口中的夜战 HUD、逐轮反馈与释放边界；受控战斗夹具，不代表真人整局。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Director = preload("res://scripts/core/director.gd")

var main: Control
var checks := 0
var failures := 0
var finished := 0


func _ready() -> void:
	get_tree().create_timer(90).timeout.connect(func():
		push_error("night_feedback 超时")
		get_tree().quit(1))
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = {}
	Game.go("title")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(8)
	var start := true
	var first := ""
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			first = arg.trim_prefix("--from=")
			start = false
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var selected := 0
	for test in [test_hud, test_second_round, test_third_round, test_live_gate, test_death, test_first_round_skip, test_leave_during_show]:
		if str(test.get_method()) == first: start = true
		if not start: continue
		if only != "" and str(test.get_method()) != only: continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0:
		check(selected > 0 and finished == selected, "测试中途退出：只完成 %d/%d" % [finished, selected])
	main.queue_free()
	await frames(4)
	print("[night_feedback] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames(count := 6) -> void:
	for k in count:
		await get_tree().process_frame


func close_modals() -> void:
	for key in main._modals.keys():
		main.close_modal(key)
	await frames(2)


func fixture() -> void:
	await close_modals()
	Game.run = State.new_run("scholar", Game.meta, 9031)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.pending_event = ""
	Game.run.pday = 4
	Game.run.t = 3 * Post.DAY + 240
	Game.run.night_policy = "manual"
	Game.snapshots = {}
	Game.refresh()
	await frames(12)


func prepare_round(index: int, open_gate := false, fatal := false) -> void:
	await fixture()
	var run: Dictionary = Game.run
	for key in ["door", "window", "wall"]:
		run[key] = {"cur": 1000, "max": 1000}
	run.attrs.hp = 100
	Defense.start_night(run, {"day": 4, "count": 48, "mods": []})
	for k in index:
		Defense.next_round(run)
	# 第二轮特意撞破窗，其余面完好；第三轮用已破院墙验证焦点来自实际漏入。
	if fatal:
		for key in ["door", "window", "wall"]:
			run[key].cur = 0
		run.attrs.hp = 1
	elif index == 1 and not open_gate:
		run.window.cur = 1
	elif not open_gate:
		run.wall.cur = 0
	run.door_open = open_gate
	if open_gate:
		# 窗墙有足够守力，没有漏怪和损伤；镜头应面对开着的院门。
		run.night.charm = {"window": 100, "wall": 100}
	run.t = 3 * Post.DAY + Defense.round_minute(index) - 1
	Game.refresh()
	await frames(8)


func combat_facts(run: Dictionary) -> Array:
	var out := []
	for key in ["t", "phase", "rng", "attrs", "door", "window", "wall", "night", "wave_report", "kills", "devices", "fight"]:
		out.append(run.get(key))
	return out.duplicate(true)


func expected_round() -> Dictionary:
	var expected: Dictionary = Game.run.duplicate(true)
	check(Post.advance(expected, 1) == "wave_round", "夹具未触发下一轮")
	Post.nod_round(expected)
	return expected


func test_hud() -> void:
	await fixture()
	var screen: Control = main._screen
	var garden: Control = screen.hud.find_child("GardenHUDCard", true, false)
	var quest: Control = screen.hud.find_child("QuestHUDCard", true, false)
	var agenda: Control = screen.hud.find_child("DayAgendaHUDRow", true, false)
	if garden == null or quest == null or agenda == null:
		check(false, "缺少菜畦、任务或差事行")
		return
	check(garden.is_visible_in_tree() and quest.is_visible_in_tree() and agenda.is_visible_in_tree(), "白天内容没有显示")
	# 不重建 HUD：恰好跨过 18:00 时也须收起。
	Game.run.t = 3 * Post.DAY + Post.DUSK_AT
	await frames()
	check(not garden.is_visible_in_tree() and not quest.is_visible_in_tree() and not agenda.is_visible_in_tree(), "天黑后菜畦/任务/差事仍露出")
	Game.run.t = 3 * Post.DAY + Post.WAVE_AT
	screen.world.set_time(Game.run)
	await frames()
	await shot("night-hud")
	Game.run.t = 3 * Post.DAY + 240
	await frames()
	check(garden.is_visible_in_tree() and quest.is_visible_in_tree() and agenda.is_visible_in_tree(), "天亮后内容未恢复")
	Post.start_fight(Game.run, 2, false)
	await frames()
	check(not garden.is_visible_in_tree() and not quest.is_visible_in_tree() and not agenda.is_visible_in_tree(), "实时迎敌仍显示任务")
	Game.run.fight = {}
	await frames()
	check(garden.is_visible_in_tree() and quest.is_visible_in_tree() and agenda.is_visible_in_tree(), "战斗结束后白天内容未恢复")
	finished += 1


func test_second_round() -> void:
	await prepare_round(1)
	var expected := expected_round()
	var screen: Control = main._screen
	var bars_before: int = screen.world._window.get_node("bars").get_child_count()
	screen.advance(1)
	check(screen._show != null and Game.hold_screen, "第二轮没有反馈/场景锁")
	if screen._show == null: return
	check(screen._show.focus_surface == "window", "第二轮没聚焦新撞破的窗")
	check(screen.world._window.get_node("bars").get_child_count() < bars_before, "破窗反馈仍显示上轮完整窗棂")
	check(screen.rig._override, "第二轮镜头没有聚焦")
	check(not main.has_modal("night"), "轮间面板遮住了反馈")
	var facts := combat_facts(Game.run)
	check(facts == combat_facts(expected), "反馈前规则结算与核心结果不一致")
	await get_tree().create_timer(0.8).timeout
	check(screen._show != null and not screen.player.enabled, "反馈过早结束或人物仍可操控")
	check(combat_facts(Game.run) == facts, "反馈播放中推进了时间/战斗/RNG")
	await shot("second-round-window")
	await click_skip(screen)
	check(screen._show == null and not Game.hold_screen and not screen.rig._override, "跳过反馈没有释放镜头/场景")
	check(main.has_modal("night"), "第二轮反馈后没恢复轮间操作")
	check(combat_facts(Game.run) == facts, "跳过反馈重复结算")
	finished += 1


func test_third_round() -> void:
	await prepare_round(2)
	var expected := expected_round()
	var screen: Control = main._screen
	screen.advance(1)
	check(screen._show != null, "第三轮没有反馈")
	if screen._show == null: return
	check(screen._show.focus_surface == "wall", "已破院墙漏入没有成为焦点")
	check(not main.has_modal("wave_report"), "整夜战报遮住了第三轮反馈")
	await shot("third-round-wall")
	await get_tree().create_timer(2.6).timeout
	check(screen._show == null and not Game.hold_screen and not screen.rig._override, "第三轮自然结束未释放")
	check(main.has_modal("wave_report"), "第三轮反馈后缺整夜战报")
	check(combat_facts(Game.run) == combat_facts(expected), "第三轮反馈改变战果/随机状态")
	finished += 1


func test_live_gate() -> void:
	await prepare_round(1, true)
	var expected := expected_round()
	var screen: Control = main._screen
	screen.advance(1)
	check(screen._show != null and not Game.run.fight.is_empty(), "开门第二轮未生成反馈和即时迎敌")
	if screen._show == null: return
	check(screen._show.focus_surface == "gate" and int(screen._show.report.get("live_gate", 0)) > 0, "完好窗墙的开门战斗没聚焦院门")
	check(not screen._show.banner.contains("守住") and screen._show.banner.contains("门前来"), "即时迎敌误报成守住了")
	var facts := combat_facts(Game.run)
	await get_tree().create_timer(0.3).timeout
	check(combat_facts(Game.run) == facts and facts == combat_facts(expected), "反馈中即时迎敌先走了一步")
	await click_skip(screen)
	await close_modals()
	check(not screen.rig._override and not Game.hold_screen and screen.player.enabled, "反馈结束未交还即时战斗控制")
	var fight_time := float(Game.run.fight.get("t", 0.0))
	await get_tree().create_timer(0.15).timeout
	check(float(Game.run.fight.get("t", 0.0)) > fight_time, "反馈结束即时战斗未恢复")
	# 同一帧多只抵达入口：事件经过真实 NightFight.step → Game.toast → 提示层。
	var entering: int = Game.run.fight.foes.size()
	for foe in Game.run.fight.foes:
		foe.x = 0.0
		foe.z = 6.5
	screen._step_fight(Game.run, 0.01)
	var notices := []
	for label in main._toasts.find_children("*", "Label", true, false):
		if label.text.begins_with("有东西挤进院子了！"):
			notices.append(label)
	check(notices.size() == 1 and notices[0].text.ends_with("×%d" % entering), "同帧多只进院没有合成一条带次数提示")
	await shot("gate-fight-toast")
	finished += 1


func test_death() -> void:
	await prepare_round(2, false, true)
	var expected := expected_round()
	var screen: Control = main._screen
	screen.advance(1)
	check(Game.run.phase == "dead" and Game.screen == "post", "致命第三轮未暂留反馈")
	check(screen._show != null and Game.hold_screen, "致命第三轮没有播放反馈")
	if screen._show == null: return
	check(combat_facts(Game.run) == combat_facts(expected), "致命第三轮战果改变")
	await click_skip(screen)
	check(Game.screen == "dead" and not Game.hold_screen, "致命反馈结束没转到残页/没有解锁")
	finished += 1


func test_first_round_skip() -> void:
	await fixture()
	Game.run.pday = 2
	Game.run.t = Post.DAY + Post.WAVE_AT
	Game.run.wave_due = true
	Game.refresh()
	await frames(12)
	var screen: Control = main._screen
	check(screen._show != null and Game.hold_screen, "首轮演出不再出现")
	if screen._show == null: return
	await click_skip(screen)
	check(screen._show == null and not Game.hold_screen and not screen.rig._override, "首轮跳过遗留锁")
	check(int(Game.run.night.round) == 1, "首轮重复结算")
	finished += 1


func test_leave_during_show() -> void:
	await prepare_round(1)
	var screen: Control = main._screen
	screen.advance(1)
	check(screen._show != null and Game.hold_screen, "换场夹具缺反馈")
	Game.go("title")
	await frames(10)
	check(Game.screen == "title" and not Game.hold_screen, "演出中离开仍遗留全局场景锁")
	finished += 1


func click_skip(screen: Control) -> void:
	var skip: Button
	for button in screen._show_layer.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text == "跳过":
			skip = button
	if skip == null:
		check(false, "反馈缺少可点击的跳过按钮")
		return
	await frames(3)
	var pos := skip.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(pos), "跳过按钮不在视口内")
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame
	await frames(8)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var dir := "res://build/b3-qa/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(dir.path_join(name + ".png")) == OK, "截图失败：" + name)
