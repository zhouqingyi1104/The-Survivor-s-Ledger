extends Node
## 真实 1280×720 窗口：57 张插画逐类截图、鼠标吃喝用药和既有边界。
## 隔离 APPDATA/LOCALAPPDATA 运行；截图与像素检查不代表玩家辨识验收。
const Demo = preload("res://scripts/dev/demo.gd")
const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const CATEGORIES := ["食", "菜", "水", "药", "粮", "柴炭", "守具", "材", "种", "器", "书", "杂"]
const SHOTS := "res://build/inventory-art-qa/shots"
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

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func modal() -> Control:
	return main._modals.get("inventory")

func labels() -> Array:
	var result := []
	if modal() == null: return result
	for label in modal().find_children("*", "Label", true, false): result.append(label.text)
	return result

func button(text: String) -> Button:
	if modal() == null: return null
	for candidate in modal().find_children("*", "Button", true, false):
		if candidate.text == text and candidate.is_visible_in_tree(): return candidate
	return null

func cards() -> Dictionary:
	var result := {}
	if modal() == null: return result
	for control in modal().find_children("*", "Control", true, false):
		if control.has_meta("inventory_item"): result[str(control.get_meta("inventory_item"))] = control
	return result

func illustrations() -> Dictionary:
	var result := {}
	if modal() == null: return result
	for control in modal().find_children("*", "TextureRect", true, false):
		if control.has_meta("inventory_art"): result[str(control.get_meta("inventory_art"))] = control
	return result

func icon_views(root: Node) -> Array:
	var result := []
	for control in root.find_children("*", "Control", true, false):
		if control.get_script() != null and control.get_script().resource_path == "res://scripts/ui/icon_view.gd": result.append(control)
	return result

func scroll() -> ScrollContainer:
	if modal() == null: return null
	var containers := modal().find_children("*", "ScrollContainer", true, false)
	return containers[0] if not containers.is_empty() else null

func reveal(target: Control) -> void:
	var ancestor := target.get_parent() if target != null else null
	while ancestor != null and ancestor != main:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
		ancestor = ancestor.get_parent()
	await frames(3)

func click(target: Control) -> void:
	if not check(target != null, "找不到点击目标"): return
	await reveal(target)
	var point := target.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(point), "点击目标不在窗口内"): return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	get_viewport().push_input(press)
	await frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	get_viewport().push_input(release)
	await frames()

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames(3)

func wheel_down(container: ScrollContainer) -> void:
	var point := container.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await frames(2)
	var wheel := InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	get_viewport().push_input(wheel)
	await frames(2)
	wheel.pressed = false
	get_viewport().push_input(wheel)
	await frames()

func fixture(stock: Dictionary) -> void:
	await close_modals()
	Demo._to_post()
	Game.run.director.enabled = false
	Game.run.busy = {}
	Game.run.pending_event = ""
	Game.run.home = stock.duplicate(true)
	Game.run.home_floor = "courtyard"
	Game.refresh()
	await frames(10)
	Dialogs.inventory()
	await frames()
	check(main.has_modal("inventory"), "存货弹窗没有打开")

func stock_all() -> Dictionary:
	var stock := {}
	for id in Data.table("items"): stock[id] = 2
	return stock

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := SHOTS.path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "无法保存窗口截图：" + path)

func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func():
		push_error("inventory_ui 超时")
		get_tree().quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("inventory_ui 需要真实窗口；headless 不能验证鼠标和截图。")
		get_tree().quit(1)
		return
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.save_path = "user://inventory-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://inventory-ui-meta-%d.json" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = {}
	Game.go("title")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(8)
	var only := ""
	var first := ""
	var start := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		elif arg.begins_with("--from="):
			first = arg.trim_prefix("--from=")
			start = false
	var selected := 0
	for test in [test_gallery, test_use_refresh, test_empty_escape, test_guest, test_unknown_fallback]:
		if str(test.get_method()) == first: start = true
		if not start or (only != "" and str(test.get_method()) != only): continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and finished == selected, "测试未完成所选场景")
	await close_modals()
	main.queue_free()
	await frames()
	print("[inventory_ui] %d 项检查，完成 %d/%d，失败 %d 处" % [checks, finished, selected, failures])
	get_tree().quit(1 if failures > 0 else 0)

func test_gallery() -> void:
	await fixture(stock_all())
	if not check(illustrations().size() == 57 and cards().size() == 57, "全部库存未显示 57 张插画卡片"): return
	var art := illustrations()
	check(art.rice.texture.resource_path == "res://assets/ui/inventory/rice.png", "米袋原插画路径改变")
	check(art.nails.texture.resource_path == "res://assets/ui/inventory/nails.png", "铁钉原插画路径改变")
	for id in Data.table("items"):
		if not check(art.has(id), "当前物品回退到代码图标：" + id): return
		check(art[id].texture != null, "插画纹理为空：" + id)
		check(art[id].custom_minimum_size == Vector2(72, 72) and art[id].size == Vector2(72, 72), "插画尺寸不为 72×72：" + id)
		check(cards()[id].custom_minimum_size.x == 190, "卡片宽度合同改变：" + id)
		check(icon_views(cards()[id]).is_empty(), "当前物品卡仍混入代码图标：" + id)
	var grids := modal().find_children("*", "GridContainer", true, false)
	if not check(grids.size() == 1 and grids[0].columns == 4, "存货不再是四列布局"): return
	var captured := {}
	for category_index in CATEGORIES.size():
		var category: String = CATEGORIES[category_index]
		await click(button(category))
		if failures > 0: return
		var expected := []
		for id in Data.table("items"):
			if str(Data.item(id).cat) == category: expected.append(id)
		var actual := cards().keys()
		expected.sort()
		actual.sort()
		if not check(expected == actual, "分类有漏项或混入其它分类：" + category): return
		var container := scroll()
		if not check(container != null, "存货滚动容器缺失"): return
		container.scroll_vertical = 0
		await frames()
		var page := 0
		while true:
			var bounds := container.get_global_rect().intersection(get_viewport().get_visible_rect())
			for id in illustrations():
				if bounds.encloses(illustrations()[id].get_global_rect()): captured[id] = true
			await shot("category-%02d-page-%02d" % [category_index + 1, page])
			var bar := container.get_v_scroll_bar()
			var maximum := maxi(0, floori(bar.max_value - bar.page))
			if container.scroll_vertical >= maximum: break
			if category_index == 0 and page == 0:
				var before := container.scroll_vertical
				await wheel_down(container)
				if not check(container.scroll_vertical > before, "真实鼠标滚轮未滚动存货列表"): return
			else:
				container.scroll_vertical = mini(maximum, container.scroll_vertical + maxi(72, int(container.size.y) - 100))
			await frames()
			page += 1
			if not check(page < 12, "分类滚动无法到达底部：" + category): return
	check(captured.size() == 57, "逐类截图仅完整覆盖 %d/57 张插画" % captured.size())
	await click(button("全部"))
	check(cards().size() == 57, "返回全部未恢复完整物品列表")
	finished += 1

func test_use_refresh() -> void:
	await fixture({"flatbread": 2, "water": 1, "salve": 2, "wood": 3, "rice": 4, "nails": 2})
	Game.run.attrs.food = 20
	Game.run.attrs.water = 20
	Game.run.attrs.hp = 20
	Game.refresh()
	await frames()
	await click(button("食"))
	await click(button("吃"))
	check(int(Game.run.home.get("flatbread", 0)) == 1 and int(Game.run.attrs.food) > 20, "点击未消耗炊饼并恢复饱食")
	check("炊饼" in labels() and "×1" in labels() and illustrations().has("flatbread"), "吃后数量或插画未刷新")
	await click(button("吃"))
	check(not Game.run.home.has("flatbread"), "第二次点击未消耗最后一份")
	check(not "炊饼" in labels() and button("食") == null, "耗尽后物品或空分类仍存在")
	check("清水" in labels(), "分类耗尽后没有返回全部")
	await click(button("水"))
	await click(button("喝"))
	check(not Game.run.home.has("water") and int(Game.run.attrs.water) > 20, "喝水未消耗并恢复口渴")
	check(button("水") == null and not illustrations().has("water"), "喝完后空分类或插画未移除")
	await click(button("药"))
	await click(button("用"))
	check(int(Game.run.home.get("salve", 0)) == 1 and int(Game.run.attrs.hp) > 20, "用药未消耗并恢复气血")
	check("×1" in labels() and illustrations().has("salve"), "用药后数量或插画未刷新")
	await shot("use-refresh")
	finished += 1

func test_empty_escape() -> void:
	await fixture({})
	check("家中暂无存货。" in labels() and cards().is_empty() and illustrations().is_empty(), "空库存提示或空列表错误")
	await shot("empty")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	await frames()
	check(not main.has_modal("inventory"), "Esc 未关闭存货弹窗")
	finished += 1

func test_guest() -> void:
	await fixture({"flatbread": 2})
	await close_modals()
	Game.run.t = 240
	Game.run.home_floor = "guest_zhou"
	Game.run.neighbor_home = {"knocked": true}
	var before: Dictionary = Game.run.home.duplicate(true)
	var notices := []
	var listener := func(text: String): notices.append(text)
	Game.toast.connect(listener)
	Dialogs.inventory()
	await frames()
	Game.toast.disconnect(listener)
	check(not main.has_modal("inventory"), "客宅限制失效")
	check("先回宅院再使用家中存货。" in notices, "客宅没有说明返回自宅取用")
	check(Post.use_item(Game.run, "flatbread") != "" and Game.run.home == before, "客宅可以消耗自家存货")
	finished += 1

func test_unknown_fallback() -> void:
	await fixture({"rice": 1})
	var id := "inventory_future_fixture"
	var items: Dictionary = Data.table("items")
	if not check(not items.has(id), "未知物品测试 ID 冲突"): return
	items[id] = {"name": "未来物资测试夹具", "unit": "份", "cat": "杂", "desc": "只在测试内存中存在。"}
	var future := Dialogs._item_card({"home": {id: 1}}, id)
	var fallbacks := icon_views(future)
	check(fallbacks.size() == 1 and fallbacks[0].id == id, "未知物品未保留代码图标兜底")
	check(future.find_children("*", "TextureRect", true, false).is_empty(), "未知物品误用已知插画")
	future.free()
	items.erase(id)
	finished += 1
