extends Node
## Real window, isolated user://, deterministic boundary fixtures; not a full playthrough.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Director = preload("res://scripts/core/director.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Home = preload("res://scripts/core/home.gd")
const Mainline = preload("res://scripts/core/mainline.gd")

var main: Control
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("M2 UI: " + description)
	return ok

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func click(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = pos
		e.pressed = down
		get_viewport().push_input(e)
	await frames()

func by_meta(root: Node, key: String, value: String = "") -> Control:
	for c in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and not c.is_queued_for_deletion() and c.has_meta(key) and (value == "" or str(c.get_meta(key)) == value): return c
	return null

func text_in(root: Node) -> String:
	var s := ""
	for c in root.find_children("*", "Label", true, false):
		if c.is_visible_in_tree() and not c.is_queued_for_deletion(): s += c.text + "\n"
	return s

func reveal(c: Control) -> bool:
	var a := c.get_parent()
	while a != null and not a is ScrollContainer: a = a.get_parent()
	if a != null:
		(a as ScrollContainer).ensure_control_visible(c)
		await frames()
	return get_viewport().get_visible_rect().has_point(c.get_global_rect().get_center()) and (a == null or (a as ScrollContainer).get_global_rect().has_point(c.get_global_rect().get_center()))

func close_modals() -> void:
	for id in main._modals.keys(): main.close_modal(str(id))
	await frames()

func fixture(day: int) -> void:
	await close_modals()
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 8020)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.pday = day
	Game.run.t = (day - 1) * Post.DAY + 240
	Game.run.pending_event = ""
	Game.run.home.wood = 20
	Game.run.home.nails = 20
	Game.run.home.caltrops = 20
	Game.run.attrs.energy = 100
	Game.run.rebirths_left = 2
	Game.snapshots = {}
	Game.refresh()
	await frames(15)

func device_count(id: String) -> int:
	var n := 0
	for d in Game.run.devices:
		if str(d.id) == id: n += 1
	return n

func same_devices(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if str(a[i].get("id", "")) != str(b[i].get("id", "")) or int(a[i].get("dur", -1)) != int(b[i].get("dur", -2)): return false
	return true

func open_build_via_workbench() -> bool:
	var screen: Control = main._screen
	var bench := Home.core(Game.run, "bench")
	var spot := "f_%d" % int(bench.get("uid", -1))
	var info: Dictionary = screen._spot_info(spot)
	if not check(not info.is_empty(), "工作台入口不存在"): return false
	screen.player.stop()
	screen.player.global_position = info.stand
	screen.rig.snap()
	await frames(10)
	var center: Vector2 = screen.rig.cam.unproject_position(Vector3(float(bench.x), 0.5, float(bench.z)))
	var p := Vector2(-1, -1)
	for dx in range(-60, 61, 4):
		if p.x >= 0: break
		for dy in range(-60, 61, 4):
			var q := center + Vector2(dx, dy)
			if get_viewport().get_visible_rect().grow(-10).has_point(q) and str(screen.world.pick(screen.rig.cam, q).get("spot", "")) == spot:
				p = q
				break
	if not check(p.x >= 0, "工作台无法拾取"): return false
	await click(p)
	if not check(screen._menu.visible, "点击工作台未打开菜单"): return false
	var b: Button
	for node in screen._menu.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text.begins_with("营造守具"): b = node; break
	if not check(b != null and not b.disabled, "工作台缺少营造入口"): return false
	await click(b.get_global_rect().get_center())
	var until := Time.get_ticks_msec() + 12000
	while screen.player.is_walking() and Time.get_ticks_msec() < until: await get_tree().process_frame
	await frames(10)
	return check(main.has_modal("build"), "点击工作台营造未打开界面")

func build_device(id: String) -> bool:
	var b := by_meta(main._modals.build, "defense_device", id) as Button
	if not check(b != null and not b.disabled, "缺少可用守具按钮 " + id): return false
	if not check(await reveal(b), "守具按钮无法滚动到可点区域 " + id): return false
	await click(b.get_global_rect().get_center())
	return check(str(Game.run.busy.get("kind", "")) == "build" and str(Game.run.busy.get("data", {}).get("device", "")) == id, "点击未开启施工 " + id)

func shot(name: String) -> void:
	var dir := OS.get_environment("M2_SHOT_DIR")
	if dir == "": return
	await get_tree().create_timer(0.4).timeout
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://m2-ui-save.json"
	Game.meta_path = "user://m2-ui-meta.json"
	Game.memory_path = "user://m2-ui-memory.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 8020)
	Pre.start_disaster(Game.run)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(240).timeout.connect(func(): get_tree().quit(1))
	await frames(40)
	if not check(main._screen != null, "宅院场景加载失败"): _finish(); return

	await fixture(8)
	if not await open_build_via_workbench(): _finish(); return
	var target := by_meta(main._modals.build, "defense_target", "horde_rope")
	check(target != null and text_in(target.get_parent()).contains("尸海"), "拦尸绳阵未展示针对敌情")
	if target != null: await reveal(target)
	await shot("build")
	var before_wood := Inv.count(Game.run.home, "wood")
	var before_nails := Inv.count(Game.run.home, "nails")
	if not await build_device("horde_rope"): _finish(); return
	check(Inv.count(Game.run.home, "wood") == before_wood - 2 and Inv.count(Game.run.home, "nails") == before_nails - 1, "布设材料扣除不对")
	var start := int(Game.run.t)
	Post.advance(Game.run, 89)
	check(device_count("horde_rope") == 0, "施工尚未完成却已生效")
	Post.advance(Game.run, 1)
	check(int(Game.run.t) == start + 90 and device_count("horde_rope") == 1, "90 分钟后未完成")
	Game.refresh()
	await frames(10)
	main._screen.player.global_position = Vector3(4.0, 0, 4.6)
	main._screen.rig.snap()
	await frames(10)
	await shot("rope_courtyard")

	Game.refresh()
	await frames(10)
	if not await open_build_via_workbench(): _finish(); return
	Game.run.home.caltrops = 0
	Game.refresh()
	await frames(10)
	var blocked := by_meta(main._modals.build, "defense_device", "armor_hook") as Button
	check(blocked != null and blocked.disabled, "材料不足仍允许施工")
	await close_modals()
	Game.run.home.caltrops = 1
	if not await open_build_via_workbench(): _finish(); return
	if not await build_device("armor_hook"): _finish(); return
	check(device_count("armor_hook") == 0, "施工中守具提前存在")
	Post.advance(Game.run, 90)
	check(device_count("armor_hook") == 1, "破甲钩未按时间完工")
	Game.refresh()
	await frames(10)
	main._screen.player.global_position = Vector3(1.0, 0, 4.6)
	main._screen.rig.snap()
	await frames(10)
	await shot("hook_courtyard")

	await fixture(8)
	Game.run.devices = [{"id": "horde_rope", "dur": 2}, {"id": "armor_hook", "dur": 2}]
	Game.refresh()
	await frames(10)
	check(text_in(main._screen).contains("今夜守力预估") and text_in(main._screen).contains("窗 6"), "今夜 HUD 未使用尸海对应守力")
	Game.run.t = (8 - 1) * Post.DAY + 900
	Game.run.plan_due = true
	Game.refresh()
	await frames(15)
	if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
	var fc := by_meta(main._modals.night_plan, "defense_forecast")
	check(fc != null and text_in(fc.get_parent()).contains("尸海"), "预战敌情缺少尸海布防说明")
	check(fc != null and (fc as Label).text.contains("窗 +4"), "预战面板与今夜 HUD 的针对守力不一致")
	await shot("forecast")
	await close_modals()
	Game.run.plan_due = false
	Game.run.night_policy = "manual"
	var wave := Defense.wave_for_run(Game.run, 8)
	Defense.start_night(Game.run, wave)
	Game.run.t = (8 - 1) * Post.DAY + Defense.WAVE_AT + 1
	for i in range(3):
		var preview := Defense.preview_round(Game.run, wave, i)
		var rep := Defense.next_round(Game.run)
		check(int(preview.surfaces.window.get("bonus", -1)) == int(rep.surfaces.window.get("bonus", -2)), "第 %d 轮窗面预告与战报加成不一致" % (i + 1))
		check(int(preview.surfaces.gate.get("bonus", -1)) == int(rep.surfaces.gate.get("bonus", -2)), "第 %d 轮门面预告与战报加成不一致" % (i + 1))
		if i == 0:
			for material in ["ink_line", "talisman", "glutinous", "dog_blood", "caltrops", "bagua"]: Game.run.home[material] = 20
			Dialogs.build()
			await frames(10)
			var night_build := by_meta(main._modals.build, "defense_device", "armor_hook") as Button
			check(night_build != null and night_build.disabled, "夜战期间工作台仍可施工")
			await close_modals()
			Dialogs.night_panel()
			await frames(10)
			check(main.has_modal("night") and by_meta(main._modals.night, "defense_round_bonus") != null, "轮间面板缺少针对守具说明")
			await shot("night")
			for visible_button in main._modals.night.find_children("*", "Button", true, false):
				if visible_button.is_visible_in_tree(): check(get_viewport().get_visible_rect().encloses(visible_button.get_global_rect()), "全部守具材料充足时按钮挤出窗口：" + visible_button.text)
			var b := by_meta(main._modals.night, "defense_night_device", "armor_hook") as Button
			if check(b != null and not b.disabled and await reveal(b), "夜战轮间守具按钮不可点击"):
				var wood_before := Inv.count(Game.run.home, "wood")
				var traps_before := Inv.count(Game.run.home, "caltrops")
				var energy_before := State.attr(Game.run, "energy")
				await click(b.get_global_rect().get_center())
				check(str(Game.run.busy.get("kind", "")) == "ward" and bool(Game.run.night.acted), "夜间点击未实际启动布置并消耗轮间动作")
				check(Inv.count(Game.run.home, "wood") == wood_before - 2 and Inv.count(Game.run.home, "caltrops") == traps_before - 1, "夜间布置扣料不对")
				Post.start_fight(Game.run, 1, false)
				check(Game.run.busy.is_empty() and Inv.count(Game.run.home, "wood") == wood_before and Inv.count(Game.run.home, "caltrops") == traps_before, "战斗打断未退还材料")
				check(is_equal_approx(State.attr(Game.run, "energy"), energy_before - 6), "中断错误返还精力")
				Post.start_fight(Game.run, 1, false)
				check(Inv.count(Game.run.home, "wood") == wood_before and Inv.count(Game.run.home, "caltrops") == traps_before, "重复战斗产生重复退款")
				Game.run.fight = {}
			await close_modals()
	var report := Defense.finish_night(Game.run)
	Game.run.wave_report = report
	Dialogs.wave_report()
	await frames(10)
	check(main.has_modal("wave_report") and by_meta(main._modals.wave_report, "defense_report_bonus") != null, "战报缺少实际加成说明")
	await shot("report")

	await close_modals()
	var saved := SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	var loaded := SaveFile.read(Game.save_path)
	check(bool(saved.ok) and not loaded.data.is_empty() and same_devices(loaded.data.run.devices, Game.run.devices), "守具 ID 或耐久未随存档恢复")
	for material in ["wood", "nails", "caltrops"]:
		check(Inv.count(loaded.data.run.home, material) == Inv.count(Game.run.home, material), "材料未随存档恢复 " + material)
	Game.run.pday = 9
	Game.snapshots = {"8": loaded.data.run.duplicate(true)}
	Game.run.devices.clear()
	var restored := Ledger.rewind(Game.run, Game.snapshots, Game.meta)
	check(not restored.is_empty() and same_devices(restored.devices, loaded.data.run.devices), "回溯未恢复原有守具与耐久")
	for material in ["wood", "nails", "caltrops"]:
		check(Inv.count(restored.home, material) == Inv.count(loaded.data.run.home, material), "材料未随回溯恢复 " + material)
	SaveFile.forget(Game.save_path)
	await fixture(7)
	Game.run.devices = [{"id": "horde_rope", "dur": 2}]
	Game.refresh()
	await frames(15)
	check(not text_in(main._screen).contains("今夜守力预估") and not text_in(main._screen).contains("尸海"), "非尸潮日 HUD 过早展示后日敌情")

	await fixture(11)
	Game.run.devices = [{"id": "armor_hook", "dur": 2}]
	Game.run.plan_due = true
	Game.refresh()
	await frames(10)
	if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
	fc = by_meta(main._modals.night_plan, "defense_forecast")
	check(fc != null and (fc as Label).text.contains("门 +4"), "铜甲敌情未显示破甲钩加成")
	await close_modals()
	Mainline.state(Game.run).interventions.disrupt_t = int(Game.run.t) - 1
	Game.refresh()
	await frames(10)
	Dialogs.night_plan()
	await frames(10)
	fc = by_meta(main._modals.night_plan, "defense_forecast")
	check(fc != null and not (fc as Label).text.contains("门 +4") and not Defense.wave_for_run(Game.run, 11).mods.has("armored"), "断运后仍显示铜甲针对加成")
	await close_modals()

	await fixture(11)
	Game.run.devices = [{"id": "armor_hook", "dur": 2}]
	Game.run.door_open = true
	wave = Defense.wave_for_run(Game.run, 11)
	Defense.start_night(Game.run, wave)
	var open_preview := Defense.preview_round(Game.run, wave, 0)
	var open_report := Defense.next_round(Game.run)
	check(int(open_preview.surfaces.gate.get("bonus", -1)) == 0 and int(open_report.surfaces.gate.get("bonus", -1)) == 0 and int(open_report.live_gate) > 0, "开门亲战仍获得破甲钩加成或未产生实时敌人")
	Dialogs.night_panel()
	await frames(10)
	check(main.has_modal("night") and text_in(main._modals.night).contains("无效"), "开门后轮间面板未标记门面守力无效")
	await shot("gate_open")

	await fixture(5)
	Game.run.home.lamp_oil = 1
	Game.run.plan_due = true
	Game.refresh()
	await frames(10)
	check(text_in(main._screen).contains("月黑预估") and text_in(main._screen).contains("更夫免油"), "月黑 HUD 未说明自动点灯和更夫例外")
	if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
	check(text_in(main._modals.night_plan).contains("自动点上一份") and text_in(main._modals.night_plan).contains("没油"), "月黑方针面板未说明有油/无油")
	await shot("dark_forecast")
	await close_modals()

	await fixture(8)
	Game.run.devices = [{"id": "horde_rope", "dur": 2}]
	Game.run.night_policy = "manual"
	wave = Defense.wave_for_run(Game.run, 8)
	Defense.start_night(Game.run, wave)
	Defense.next_round(Game.run)
	Game.run.t = (8 - 1) * Post.DAY + Defense.WAVE_AT + 1
	Game.run.home.wood = 0
	Dialogs.night_panel()
	await frames(10)
	var blocked_night := by_meta(main._modals.night, "defense_night_device", "horde_rope") as Button
	check(blocked_night != null and blocked_night.disabled and text_in(blocked_night.get_parent()).contains("材料不够"), "轮间缺材料未明确禁用原因")
	await close_modals()
	Game.run.home.wood = 20
	Game.run.attrs.energy = 5
	Game.run.window.cur = 0
	Dialogs.night_panel()
	await frames(10)
	blocked_night = by_meta(main._modals.night, "defense_night_device", "horde_rope") as Button
	check(blocked_night != null and blocked_night.disabled and text_in(blocked_night.get_parent()).contains("精力不济"), "轮间精力不足未明确禁用原因")
	check(text_in(main._modals.night).contains("守力无效") and int(Defense.preview_round(Game.run, wave, 1).surfaces.window.get("bonus", -1)) == 0, "窗已破仍显示守力有效或计算针对加成")

	await fixture(11)
	Game.run.door_open = true
	Game.run.window.cur = 0
	Game.run.plan_due = true
	Game.refresh()
	await frames(10)
	if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
	check(text_in(main._modals.night_plan).contains("院门开着就不守门"), "方针说明缺少开门避让提示")
	var manual: Button
	for b in main._modals.night_plan.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == "亲自调度": manual = b; break
	if check(manual != null and get_viewport().get_visible_rect().encloses(manual.get_global_rect()), "方针按钮缺失或无法点击"):
		await shot("policy_broken_open")
		await click(manual.get_global_rect().get_center())
		check(str(Game.run.night_policy) == "manual" and str(Game.run.guard_spot) == "wall", "自动选守选择了已破窗面或打开的门")

	for spec in [["all_broken", "稳守"], ["all_broken", "亲战"], ["all_broken", "亲自调度"], ["open_gate", "稳守"], ["open_gate", "亲战"], ["open_gate", "亲自调度"]]:
		var case := str(spec[0])
		await fixture(11)
		Game.run.door.cur = 0 if case == "all_broken" else 100
		Game.run.door_open = case == "open_gate"
		Game.run.window.cur = 0
		Game.run.wall.cur = 0
		Game.run.plan_due = true
		Game.refresh()
		await frames(10)
		if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
		check(text_in(main._modals.night_plan).count("亲守：三面都守不了") >= 2, "弱面方针未如实显示无可守面 " + case)
		var choice := str(spec[1])
		var selected: Button
		for b in main._modals.night_plan.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and b.text == choice: selected = b; break
		if check(selected != null and get_viewport().get_visible_rect().encloses(selected.get_global_rect()), "无可守面方针无法点击 " + case):
			await shot("policy_none_" + case)
			await click(selected.get_global_rect().get_center())
			check(str(Game.run.guard_spot) == "" and not Game.run.plan_due, "无可守面时仍虚假亲守或无法提交 " + case)
			for sid in Defense.SURFACES:
				var power := Defense.surface_power(Game.run, sid)
				check(not str(power.lines).contains("亲守"), "无可守面仍增加亲守力量 " + case + "/" + sid)

	await fixture(11)
	Game.run.door_open = true
	Game.run.plan_due = true
	Game.refresh()
	await frames(10)
	if not main.has_modal("night_plan"): Dialogs.night_plan(); await frames(10)
	var hold: Button
	for b in main._modals.night_plan.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == "稳守": hold = b; break
	if check(hold != null, "稳守选项不存在"):
		check(text_in(hold.get_parent()).contains("院门守不了"), "稳守门打开时未说明只是不守门")
		await click(hold.get_global_rect().get_center())
		check(str(Game.run.guard_spot) == "" and not Game.run.plan_due, "稳守开门后仍错误亲守院门")
	_finish()

func _finish() -> void:
	print("[M2_TARGETED_UI] ", checks - failures, "/", checks, " failed=", failures)
	get_tree().quit(1 if failures else 0)
