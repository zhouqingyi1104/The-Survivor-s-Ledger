extends Node
## 真实窗口定向检查字体度量、鼠标滚动和中文键事件；不代表真实输入法或玩家验收。
const Fonts = preload("res://scripts/ui/fonts.gd")
const Demo = preload("res://scripts/dev/demo.gd")
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const SHOTS := "res://build/fonts-qa/shots"
var main: Control
var checks := 0
var failures := 0
var finished := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func frames(count := 8) -> void:
	for index in count: await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func():
		push_error("bundled_fonts_ui 超时")
		get_tree().quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("bundled_fonts_ui 需要真实 1280×720 窗口")
		get_tree().quit(1)
		return
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.save_path = "user://fonts-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://fonts-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = ""
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = {}
	Game.snapshots = {}
	Game.go("title")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(12)
	check(get_viewport().get_visible_rect().size == Vector2(1280, 720), "字体窗口不是 1280×720")
	var only := ""
	var first := ""
	var start := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		elif arg.begins_with("--from="):
			first = arg.trim_prefix("--from=")
			start = false
	var selected := 0
	for test in [test_title, test_title_saved, test_pre, test_post, test_night_panel, test_inventory, test_settings, test_feedback]:
		if str(test.get_method()) == first: start = true
		if not start or (only != "" and str(test.get_method()) != only): continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and selected == finished, "字体窗口检查未完成所选场景")
	await close_modals()
	main.queue_free()
	await frames(4)
	print("[bundled_fonts_ui] %d 项检查，完成 %d/%d，失败 %d" % [checks, finished, selected, failures])
	get_tree().quit(1 if failures > 0 else 0)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames(3)

func fixture(scene: String) -> void:
	await close_modals()
	if scene == "title":
		Game.run = {}
		Game.go("title")
	else:
		Demo.setup(scene)
		Game.run.director.enabled = false
		Game.run.pending_event = ""
	Game.speed = 0
	await frames(16)
	if scene != "night_panel": await close_modals()

func modal(key: String) -> Control:
	return main._modals.get(key)

func button(root: Node, text: String) -> Button:
	if root == null: return null
	for candidate in root.find_children("*", "Button", true, false):
		if candidate.text == text and candidate.is_visible_in_tree(): return candidate
	return null

func tagged(root: Node, key: String) -> Control:
	if root == null: return null
	for candidate in root.find_children("*", "Control", true, false):
		if candidate.has_meta(key): return candidate
	return null

func scroll(root: Node) -> ScrollContainer:
	if root == null: return null
	var list := root.find_children("*", "ScrollContainer", true, false)
	return list[0] if not list.is_empty() else null

func reveal(target: Control) -> void:
	var ancestor := target.get_parent()
	while ancestor != null and ancestor != main:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
		ancestor = ancestor.get_parent()
	await frames(3)

func click(target: Control) -> void:
	if not check(target != null, "找不到字体交互目标"): return
	await reveal(target)
	var point := target.get_global_rect().get_center()
	if not check(target.is_visible_in_tree() and get_viewport().get_visible_rect().has_point(point), "字体交互目标不在窗口内"): return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await frames(1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		get_viewport().push_input(event)
		await frames(2)
	await frames()

func wheel_down(container: ScrollContainer) -> void:
	if not check(container != null, "缺少字体滚动容器"): return
	var point := container.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		get_viewport().push_input(event)
		await frames(2)
	await frames()

func visible_area(control: Control) -> Rect2:
	var bounds := control.get_global_rect().intersection(get_viewport().get_visible_rect())
	var ancestor := control.get_parent()
	while ancestor != null and ancestor != main:
		if ancestor is Control and ancestor.clip_contents: bounds = bounds.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return bounds

func text_bounds(root: Node, context: String) -> void:
	var inspected := 0
	for control in root.find_children("*", "Control", true, false):
		if not (control is Label or control is Button or control is TextEdit): continue
		if not control.is_visible_in_tree() or not visible_area(control).has_area(): continue
		var text: String = control.text
		if text.is_empty(): continue
		inspected += 1
		var font: Font = control.get_theme_font("font")
		check(is_same(font, Fonts.book()) or is_same(font, Fonts.body()) or is_same(font, Fonts.bold()), "%s 控件未使用统一内置字体：%s" % [context, text])
		for character in text:
			var code: int = character.unicode_at(0)
			if code >= 32: check(font.has_char(code), "%s 可见字形缺失：%s U+%04X" % [context, character, code])
		if control is TextEdit: continue
		var size: int = control.get_theme_font_size("font_size")
		var width := -1.0
		if control is Label and control.autowrap_mode != TextServer.AUTOWRAP_OFF: width = control.size.x
		var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size)
		if control is Label:
			if not control.clip_text and control.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				check(text_size.x <= control.size.x + 2.0, "%s 文字横向超出：%s（%.1f > %.1f）" % [context, text, text_size.x, control.size.x])
			check(text_size.y <= control.size.y + 2.0, "%s 文字纵向裁切：%s（%.1f > %.1f）" % [context, text, text_size.y, control.size.y])
		else:
			check(text_size.x <= control.size.x + 2.0 and text_size.y <= control.size.y + 2.0, "%s 按钮文字超出可点击区域：%s" % [context, text])
	check(inspected > 0, context + " 没有检查到可见文字")

func shot(name: String) -> void:
	if Game.screen == "title" and main._screen.modulate.a < 0.999:
		await get_tree().create_timer(1.25).timeout
		check(main._screen.modulate.a >= 0.999, "标题截图早于完整淡入")
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(SHOTS.path_join(name + ".png")) == OK, "字体截图写入失败：" + name)

func test_title() -> void:
	await fixture("title")
	check(is_same(main.theme.default_font, Fonts.book()), "标题页根主题未使用内置楷书")
	text_bounds(main._screen, "标题")
	await shot("title")
	await click(button(main._screen, "设置"))
	check(main.has_modal("settings"), "标题设置按钮未响应")
	await click(button(modal("settings"), "合上"))
	check(not main.has_modal("settings"), "标题设置合上按钮未响应")
	finished += 1

func test_title_saved() -> void:
	await close_modals()
	Game.run = State.new_run("scholar", Game.meta, 10505)
	Game.run.director.enabled = false
	Game.snapshots = {}
	# 仅写本测试 PID 对应的隔离路径；has_save() 在 no_save=true 时特意返回 false。
	Game.no_save = false
	Game.save_game()
	check(FileAccess.file_exists(Game.save_path) and Game.save_status().main, "未写出可续写的隔离旧存档")
	Game.go("title")
	await frames(12)
	var menu: Array = []
	var decorations: Array[Rect2] = []
	for label in main._screen.find_children("*", "Label", true, false):
		if label.text == "尸 劫": decorations.append(label.get_parent().get_global_rect())
		elif label.text == "劫余录": decorations.append(label.get_global_rect())
	check(decorations.size() == 2, "旧卷标题没有找到题名与印章区域")
	for candidate in main._screen.find_children("*", "Button", true, false):
		if candidate.is_visible_in_tree(): menu.append(candidate)
	check(menu.size() == 10 and button(main._screen, "续写此录") != null, "有旧卷时没有展示完整 10 项标题菜单")
	var viewport_bounds := get_viewport().get_visible_rect()
	for index in menu.size():
		var candidate: Button = menu[index]
		var bounds := candidate.get_global_rect()
		check(viewport_bounds.encloses(bounds), "旧卷标题按钮超出视口：" + candidate.text)
		for decoration in decorations:
			check(not bounds.intersects(decoration), "旧卷标题菜单与题名/印章相交：" + candidate.text)
		for earlier in range(index):
			check(not bounds.intersects(menu[earlier].get_global_rect()), "旧卷标题按钮区域相互覆盖：%s / %s" % [candidate.text, menu[earlier].text])
		# 全部按钮都验真实 GUI 命中，退出项只悬停，不触发退出回调。
		for fraction in [0.2, 0.5, 0.8]:
			bounds = candidate.get_global_rect()
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(bounds.position.x + bounds.size.x * fraction, bounds.get_center().y)
			get_viewport().push_input(motion)
			await frames(2)
			check(get_viewport().gui_get_hovered_control() == candidate, "旧卷标题按钮真实 GUI 命中被遮挡：" + candidate.text)
	text_bounds(main._screen, "旧卷标题")
	await shot("title-saved")
	await click(button(main._screen, "设置"))
	check(main.has_modal("settings"), "旧卷标题最下方可操作菜单「设置」未响应")
	await click(button(modal("settings"), "合上"))
	await click(button(main._screen, "导出试玩报告"))
	check(main.has_modal("playtest_feedback"), "旧卷标题「导出试玩报告」未响应")
	await click(tagged(modal("playtest_feedback"), "feedback_cancel"))
	check(not main.has_modal("playtest_feedback"), "旧卷标题反馈取消未响应")
	Game.no_save = true
	for path in [Game.save_path, Game.save_path + ".bak", Game.meta_path, Game.meta_path + ".bak"]:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(path) == OK, "隔离字体旧存档清理失败：" + path)
	finished += 1

func test_pre() -> void:
	await fixture("pre")
	check(Game.screen == "pre", "街市夹具未进入备劫")
	var signs: Array = main._screen.world.find_children("*", "Label3D", true, false)
	check(signs.size() >= 6, "街市没有足够的真实 3D 招牌")
	for sign_label in signs:
		check(is_same(sign_label.font, Fonts.book()), "真实街市招牌未使用内置楷书：" + sign_label.text)
		for character in sign_label.text:
			if character.unicode_at(0) >= 32: check(sign_label.font.has_char(character.unicode_at(0)), "街市招牌缺字：" + character)
	text_bounds(main._screen.hud, "备劫街市")
	await shot("pre-signs")
	finished += 1

func test_post() -> void:
	await fixture("post")
	check(Game.screen == "post", "白天夹具未进入宅院")
	var dial: Control = main._screen._live.get("dial")
	check(dial != null and is_same(dial._font, Fonts.book()), "真实宅院时钟未使用内置楷书")
	var bold_count := 0
	for label in main._screen.hud.find_children("*", "Label", true, false):
		if is_same(label.get_theme_font("font"), Fonts.bold()): bold_count += 1
	check(bold_count > 0, "真实白天 HUD 没有使用内置 700 字重")
	var pause_text: String = main._screen.SPEED_LABELS[0]
	check(pause_text == "Ⅱ", "暂停按钮没有使用内置字体覆盖的双竖线")
	var pause := button(main._screen.hud, pause_text)
	check(pause != null and is_same(pause.get_theme_font("font"), Fonts.body()), "真实 HUD 暂停按钮文字或字体错误")
	for character in pause_text: check(Fonts.body().has_char(character.unicode_at(0)), "内置正文不能显示暂停符号：" + character)
	text_bounds(main._screen.hud, "白天 HUD")
	await shot("post-clock-hud")
	finished += 1

func test_night_panel() -> void:
	await fixture("night_panel")
	if not check(main.has_modal("night"), "真实夜战面板未打开"): return
	check(is_same(modal("night").theme.default_font, Fonts.body()), "夜战面板未使用内置黑体")
	text_bounds(modal("night"), "夜战面板")
	text_bounds(main._screen.hud, "夜战 HUD")
	await shot("night-panel")
	await click(button(modal("night"), "合上"))
	check(not main.has_modal("night"), "夜战面板合上按钮未响应")
	finished += 1

func test_inventory() -> void:
	await fixture("post")
	Game.run.busy = {}
	Game.run.home = {}
	for id in Data.table("items"): Game.run.home[id] = 2
	Game.refresh()
	await frames()
	Dialogs.inventory()
	await frames()
	if not check(main.has_modal("inventory"), "真实存货未打开"): return
	text_bounds(modal("inventory"), "存货顶部")
	await shot("inventory-top")
	var container := scroll(modal("inventory"))
	if not check(container != null, "存货字体列表缺少滚动容器"): return
	var before := container.scroll_vertical
	await wheel_down(container)
	check(container.scroll_vertical > before, "字体更换后存货滚轮未响应")
	container.scroll_vertical = int(container.get_v_scroll_bar().max_value)
	await frames()
	text_bounds(modal("inventory"), "存货底部")
	await shot("inventory-bottom")
	await click(button(modal("inventory"), "书"))
	check(Dialogs._inventory_filter == "书", "存货分类按钮未响应")
	text_bounds(modal("inventory"), "存货书籍")
	await shot("inventory-books")
	finished += 1

func test_settings() -> void:
	await fixture("post")
	Dialogs.settings(true)
	await frames()
	if not check(main.has_modal("settings"), "真实设置未打开"): return
	text_bounds(modal("settings"), "设置顶部")
	await shot("settings-top")
	var container := scroll(modal("settings"))
	if not check(container != null, "设置缺少滚动容器"): return
	var before := container.scroll_vertical
	await wheel_down(container)
	check(container.scroll_vertical > before, "字体更换后设置滚轮未响应")
	container.scroll_vertical = int(container.get_v_scroll_bar().max_value)
	await frames()
	text_bounds(modal("settings"), "设置底部")
	await shot("settings-bottom")
	await click(button(modal("settings"), "合上"))
	check(not main.has_modal("settings"), "设置合上按钮未响应")
	finished += 1

func test_feedback() -> void:
	await fixture("post")
	Dialogs.settings(true)
	await frames()
	await click(tagged(modal("settings"), "feedback_entry"))
	if not check(main.has_modal("playtest_feedback"), "设置的试玩反馈入口未响应"): return
	var editor := tagged(modal("playtest_feedback"), "feedback_key") as TextEdit
	if not check(editor != null, "缺少试玩反馈中文输入框"): return
	await click(editor)
	var value := "字体检查：劫余录，子丑寅卯。\n箭头→与数字 19:30"
	for character in value:
		var event := InputEventKey.new()
		event.pressed = true
		if character == "\n":
			event.keycode = KEY_ENTER
			event.physical_keycode = KEY_ENTER
		else: event.unicode = character.unicode_at(0)
		get_viewport().push_input(event)
		event = event.duplicate()
		event.pressed = false
		get_viewport().push_input(event)
		await frames(1)
	await frames()
	check(editor.text == value, "字体更换后中文键事件输入内容不一致")
	text_bounds(modal("playtest_feedback"), "反馈输入")
	await shot("feedback-input")
	await click(tagged(modal("playtest_feedback"), "feedback_cancel"))
	check(not main.has_modal("playtest_feedback") and main.has_modal("settings"), "取消反馈没有正确返回设置")
	finished += 1
