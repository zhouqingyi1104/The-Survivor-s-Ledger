extends Node
## Actual pointer-driven C3 UI; launch with isolated APPDATA/LOCALAPPDATA and C3_UI_SHOTS.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Director = preload("res://scripts/core/director.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Decoration = preload("res://scripts/core/home_decoration.gd")
const Fight = preload("res://scripts/core/night_fight.gd")
var main: Control
var checks := 0
var failures := 0

func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", detail)
	return ok

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func click(pos: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames()

func press(button: Button) -> bool:
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "按钮不存在或不可点击"): return false
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		for i in range(20):
			var target := button.get_global_rect().get_center()
			var area := (parent as ScrollContainer).get_global_rect()
			if area.grow(-3).has_point(target): break
			var down := target.y > area.end.y
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
				ev.position = area.get_center()
				ev.pressed = pressed
				get_viewport().push_input(ev)
			await frames(3)
		if not check((parent as ScrollContainer).get_global_rect().grow(-3).has_point(button.get_global_rect().get_center()), "滚动后按钮仍不可见：" + button.text): return false
	var viewport_rect := get_viewport().get_visible_rect()
	var point := button.get_global_rect().get_center()
	if not check(viewport_rect.has_point(point), "按钮在窗口之外：%s %s" % [button.text, point]): return false
	await click(point)
	return true

func button_in(node: Node, title: String) -> Button:
	if node == null: return null
	for b in node.find_children("*", "Button", true, false):
		if b.text == title and b.is_visible_in_tree() and not b.is_queued_for_deletion(): return b
	return null

func row_button(modal: Node, choice: String) -> Button:
	if modal == null: return null
	for label in modal.find_children("*", "Label", true, false):
		if label.text.begins_with(choice) and label.get_parent() is HBoxContainer:
			return button_in(label.get_parent(), "选择")
	return null

func shot(name: String) -> void:
	var dir := OS.get_environment("C3_UI_SHOTS")
	if dir == "":
		check(false, "未指定截图目录")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png")) == OK, "截图保存失败：" + name)

func open_workbench() -> bool:
	var screen = main._screen
	var bench := Home.core(Game.run, "bench")
	if not check(not bench.is_empty(), "缺少核心工作台"): return false
	var spot := "f_%d" % int(bench.uid)
	var info: Dictionary = screen._spot_info(spot)
	if not check(not info.is_empty(), "工作台没有真实交互点"): return false
	screen.player.position = info.stand
	screen.rig.snap()
	await frames(20)
	var center: Vector2 = screen.rig.cam.unproject_position(Vector3(float(bench.x), 0.45, float(bench.z)))
	var target := Vector2(-1, -1)
	for dx in range(-36, 37, 4):
		for dy in range(-36, 37, 4):
			var p := center + Vector2(dx, dy)
			if get_viewport().get_visible_rect().grow(-10).has_point(p) and str(screen.world.pick(screen.rig.cam, p).get("spot", "")) == spot:
				target = p
				break
		if target.x >= 0: break
	if not check(target.x >= 0, "无法用鼠标拾取工作台"): return false
	await click(target)
	if not check(screen._menu.visible, "拾取工作台后缺少菜单"): return false
	var b := button_in(screen._menu, "宅院装修…")
	if not await press(b): return false
	for i in range(90):
		if main.has_modal("decoration"): break
		await get_tree().process_frame
	return check(main.has_modal("decoration"), "点击工作台入口后未打开装修")

func select(choice: String) -> bool:
	var modal = main._modals.get("decoration")
	if not await press(row_button(modal, choice)): return false
	return check(main.has_modal("decoration_confirm"), "未出现装修确认")

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://c3-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://c3-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://c3-ui-memory-%d.md" % OS.get_process_id()
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.home.wood = 40
	Game.run.home.nails = 10
	Game.snapshots = {}
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(120).timeout.connect(func(): get_tree().quit(1))
	await frames(40)
	if await open_workbench():
		shot("day-menu")
		var before := Game.run.duplicate(true)
		if await select("暖赭院墙"):
			shot("confirm")
			if await press(button_in(main._modals.get("decoration_confirm"), "取消")):
				check(Game.run == before and not main.has_modal("decoration_confirm"), "取消更改局面或材料")
		if await select("暖赭院墙"):
			Game.run.fight = Fight.begin(1, false, Game.run)
			var supplies: Dictionary = Game.run.home.duplicate(true)
			if await press(button_in(main._modals.get("decoration_confirm"), "确认")):
				check(Game.run.home == supplies and Decoration.selected(Game.run, "wall") == "original", "确认前进入战斗仍扣料或改样式")
				check(main.has_modal("decoration_confirm"), "被拒绝后确认面板意外关闭")
				await press(button_in(main._modals.get("decoration_confirm"), "取消"))
			Game.run.fight = {}
		if await select("暖赭院墙"):
			if await press(button_in(main._modals.get("decoration_confirm"), "确认")):
				check(Decoration.selected(Game.run, "wall") == "warm" and int(Game.run.home.wood) == int(before.home.wood) - 2, "确认墙面或扣料不正确")
				check(not main.has_modal("decoration"), "确认后装修面板未关闭")
				await frames(10)
				shot("day-wall")
				var visual = main._screen.world.get_node_or_null("decoration")
				check(visual != null and visual.get_child_count() > 0, "场景未出现实际装修")
				if await open_workbench():
					check(row_button(main._modals.get("decoration"), "暖赭院墙") == null, "当前样式仍可重复收费")
					main.close_modal("decoration")
					for row in [["floor", "brick", "红砖铺地"], ["lamps", "gold", "一对暖金灯"], ["plants", "plum", "一对盆梅"]]:
						if not await open_workbench(): break
						var wood := int(Game.run.home.wood)
						var nails := int(Game.run.home.nails)
						var cost: Dictionary = Decoration.OPTIONS[row[0]].choices[row[1]].cost
						if await select(str(row[2])) and await press(button_in(main._modals.get("decoration_confirm"), "确认")):
							check(Decoration.selected(Game.run, row[0]) == row[1], "装修样式未保存：" + row[0])
							check(int(Game.run.home.wood) == wood - int(cost.get("wood", 0)) and int(Game.run.home.nails) == nails - int(cost.get("nails", 0)), "材料扣除错误：" + row[0])
							var layer = main._screen.world.get_node_or_null("decoration")
							check(layer != null and layer.get_child_count() > 0, "画面未重绘：" + row[0])
							shot("day-" + str(row[0]))
					if await open_workbench():
						Game.run.home.wood = 0
						if await select("深灰石板"):
							check(button_in(main._modals.get("decoration_confirm"), "确认") == null, "材料不足时仍可确认")
							await press(button_in(main._modals.get("decoration_confirm"), "取消"))
						main.close_modal("decoration")
	var saved := SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	if check(bool(saved.get("ok", false)), "存档失败") and check(Game.continue_game(), "读档失败"):
		await frames(10)
		for row in [["wall", "warm"], ["floor", "brick"], ["lamps", "gold"], ["plants", "plum"]]:
			check(Decoration.selected(Game.run, row[0]) == row[1], "读档未恢复装修：" + row[0])
		check(main._screen.world.get_node_or_null("decoration") != null and main._screen.world.get_node("decoration").get_child_count() > 0, "读档未重画")
		Game.run.t = 16 * 60
		Game.run.fight = Fight.begin(3, false, Game.run)
		Game.refresh()
		await frames(12)
		var hud: Control = main._screen.hud
		var combat_lines := []
		for label in hud.find_children("*", "Label", true, false):
			if "门外" in label.text or "架刀" in label.text:
				combat_lines.append(label)
		check(hud.visible and combat_lines.size() >= 2, "夜战状态或架刀提示未显示")
		for label in combat_lines:
			check(label.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(label.get_global_rect()), "夜战 HUD 文字超出窗口")
		shot("night-fight-hud")
		var screen = main._screen
		var bench := Home.core(Game.run, "bench")
		var spot := "f_%d" % int(bench.uid)
		screen.player.position = screen._spot_info(spot).stand
		screen.rig.snap()
		await frames(8)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = KEY_E
			ev.physical_keycode = KEY_E
			ev.pressed = down
			get_viewport().push_input(ev)
		await frames(8)
		check(screen._menu.visible, "夜战交互键未打开工作台菜单")
		var blocked: Button = null
		for b in screen._menu.find_children("*", "Button", true, false):
			if b.text.begins_with("宅院装修…"): blocked = b
		check(blocked != null and blocked.disabled and "夜袭中不能装修" in blocked.text, "夜战装修入口未禁用或原因不明确")
		shot("night-fight-menu")
	Game.new_game("scholar")
	await frames(10)
	for category in ["wall", "floor", "lamps", "plants"]:
		check(Decoration.selected(Game.run, category) == "original", "新局沿用了装修：" + category)
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C3_UI %d checks %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
