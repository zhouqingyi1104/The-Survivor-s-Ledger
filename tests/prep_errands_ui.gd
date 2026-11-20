extends Node
## 备劫第一天照常买完最后一斗米，再在店里和家里做杂事。所有行动均用窗口鼠标触发。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Inv = preload("res://scripts/core/inv.gd")

var main: Control
var checks := 0


func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 5103)
	# 最后一斗米正好花光剩余银钱、装满车。已有的柴随回家卸车。
	var run: Dictionary = Game.run
	run.cart = {"firewood": 5}
	run.silver = Pre.price(run, "rice_shop", "rice")
	var original_bread := Inv.count(run.home, "flatbread")
	var original_wood := Inv.count(run.home, "firewood")
	Game.go("pre")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()

	await click(button("备荒杂事", main._screen.hud))
	if not check(main.has_modal("prep_work"), "城内找不到备荒杂事入口"): return
	var work: Control = main._modals.prep_work
	if not check(copy_in(work).contains("炊饼") and copy_in(work).contains("柴"), "出发前看不到两种杂事的报酬"): return
	record_window("errands")
	var hour := int(run.hour)
	await click(tagged("prep_work_travel", "rice_shop", work))
	await arrive()
	if not check(run.loc == "rice_shop" and run.hour == hour + 1 and main.has_modal("prep_work"), "去米行未正常计路程或到店未显示杂事"): return
	if not check(Inv.count(run.home, "flatbread") == original_bread, "去米行途中就发了工钱"): return
	await click(button("合上", main._modals.prep_work))
	await click(button("米行（在此）", main._screen.hud))
	if not check(main.has_modal("shop"), "普通米行入口未打开店铺"): return
	var shop: Control = main._modals.shop
	await click(rice_purchase(shop))
	if not check(run.silver == 0 and Pre.cart_weight(run) == Pre.capacity(run) and Inv.count(run.cart, "rice") == 1, "实际买米后应当无余钱且满载"): return
	record_window("full-cart")
	var cart: Dictionary = run.cart.duplicate()
	hour = int(run.hour)
	await click(tagged("prep_work_action", "rice_shop", shop), 2)
	if not check(run.hour == hour + 1 and Inv.count(run.home, "flatbread") == original_bread + 1, "连续点击卸粮应只耗一时辰、发一张炊饼到家"): return
	if not check(run.cart == cart and run.silver == 0 and main.has_modal("shop"), "卸粮改变了购物所得或关闭了铺子"): return
	if not check(copy_in(shop).contains("已做过"), "米行没告诉玩家已经帮过忙"): return
	await click(button("合上", shop))

	await click(button("备荒杂事", main._screen.hud))
	if not check(main.has_modal("prep_work") and copy_in(main._modals.prep_work).contains("已做过"), "重开杂事没显示米行进度"): return
	hour = int(run.hour)
	await click(tagged("prep_work_travel", "home", main._modals.prep_work))
	await arrive()
	if not check(main.has_modal("prep_work") and run.loc == "home" and run.hour == hour + 1 and run.cart.is_empty(), "回家没有按路程扣时、卸货并打开杂事"): return
	var wood_before := Inv.count(run.home, "firewood")
	if not check(wood_before == original_wood + 5, "原本买来的货未正常入库"): return
	hour = int(run.hour)
	await click(tagged("prep_work_action", "home", main._modals.prep_work), 2)
	if not check(run.hour == hour + 1 and Inv.count(run.home, "firewood") == wood_before + 2 and run.silver == 0, "劈柴未按时入库两捆，或重复发放"): return
	await click(button("合上", main._modals.prep_work))
	await click(button("囤货清单", main._screen.hud))
	if not check(main.has_modal("checklist"), "囤货清单未打开"): return
	var inventory_text := copy_in(main._modals.checklist)
	if not check(inventory_text.contains("炊饼 ×%d" % (original_bread + 1)) and inventory_text.contains("柴 ×%d" % (wood_before + 2)), "清单里看不到实际报酬"): return
	await click(button("合上", main._modals.checklist))
	await click(button("回家歇息，明日再说", main._screen.hud))
	if main.has_modal("confirm"):
		await click(button("就这样吧", main._modals.confirm))
	if not check(run.day == 2 and run.phase == "pre", "做完杂事后不能正常过日"): return
	await click(button("备荒杂事", main._screen.hud))
	if not check(main.has_modal("prep_work") and copy_in(main._modals.prep_work).count("已做过") == 2, "次日应能看到两处均已做过"): return
	main.queue_free()
	await frames()
	print("[prep_errands_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func frames(n := 4) -> void:
	for frame in n:
		await get_tree().process_frame


func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		push_error(detail)
		get_tree().quit(1)
	return ok


func arrive() -> void:
	while main._screen.world.walking:
		await get_tree().process_frame
	await frames()


func record_window(label: String) -> void:
	RenderingServer.force_draw()
	var temp_dir := OS.get_environment("TEMP")
	if not temp_dir.is_empty():
		var path := temp_dir.path_join("prep-errands-" + label + ".png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "杂事窗口截图未写入")


func button(caption: String, scope: Node) -> Button:
	for item in scope.find_children("*", "Button", true, false):
		if item.is_visible_in_tree() and item.text == caption:
			return item
	return null


func tagged(key: String, location: String, scope: Node) -> Button:
	for item in scope.find_children("*", "Button", true, false):
		if item.is_visible_in_tree() and item.get_meta(key, "") == location:
			return item
	return null


func rice_purchase(shop: Control) -> Button:
	for label in shop.find_children("*", "Label", true, false):
		if label.text == "米（斗）":
			for sibling in label.get_parent().get_children().slice(label.get_index() + 1):
				if sibling is Button:
					return sibling if sibling.text == "买一" else null
	return null


func copy_in(scope: Node) -> String:
	var copy := PackedStringArray()
	for node in scope.find_children("*", "Control", true, false):
		if (node is Label or node is Button) and node.is_visible_in_tree():
			copy.append(node.text)
	return "\n".join(copy)


func click(target: Button, times := 1) -> void:
	if not check(target != null and not target.disabled, "目标按钮缺失或不可点击"): return
	var pos := target.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(pos), "按钮在窗口外：" + target.text): return
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion)
	for press in times:
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = pos
			event.pressed = down
			get_viewport().push_input(event)
			await frames(1)
	await frames()
