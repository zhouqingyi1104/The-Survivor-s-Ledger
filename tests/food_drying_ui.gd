extends Node
## 从灶台的互动菜单进晒匾、翻晒、收货。测试把时钟移至成熟前一分钟，最后一分钟走实际时钟。
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
var main: Control
var checks := 0


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 4184)
	Pre.start_disaster(Game.run)
	Post.Neighbor.state(Game.run).stage = "closed"
	Post.Director.state(Game.run).enabled = false
	Game.run.t = 60
	Game.run.home = {"millet": 1, "water": 1, "firewood": 1}
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(25)
	var screen: Control = main._screen
	var stove: Dictionary = screen._spot_info("stove")
	if not check(not stove.is_empty(), "灶台没有互动位置"): return
	screen.player.global_position = stove.stand
	await frames(15)
	for down in [true, false]:
		var input := InputEventKey.new()
		input.keycode = KEY_E
		input.physical_keycode = KEY_E
		input.pressed = down
		get_viewport().push_input(input)
	await frames()
	if not await click_button(screen._menu, "生火做饭"): return
	if not check(main.has_modal("cook"), "灶房未打开"): return
	if not await click_button(main._modals.cook, "晒匾 · 空匾"): return
	if not check(main.has_modal("drying") and copy(main._modals.drying).contains("盐晒萝卜"), "两种晒方未出现"): return
	screen_shot("recipes")
	if not await click_button(main._modals.drying, "铺匾"): return
	if not check(Game.run.has("drying_batch") and button(main._modals.drying, "收进存货", false).disabled, "初晒未锁住提前领取"): return
	if not await advance_to_ready(): return
	screen_shot("choice")
	if not await click_button(main._modals.drying, "翻晒一天"): return
	if not check(Game.run.drying_batch.turned and button(main._modals.drying, "收进存货", false).disabled, "翻晒未再占一天"): return
	if not await advance_to_ready(): return
	screen_shot("ready")
	if not await click_button(main._modals.drying, "收进存货"): return
	if not check(Game.run.home.get("millet_cake") == 5 and not Game.run.has("drying_batch"), "领货未入真实存货或未腾匾"): return
	if not await click_button(main._modals.drying, "合上"): return
	if not check(button(main._modals.cook, "晒匾 · 空匾") != null, "灶房状态未恢复空匾"): return
	print("[food_drying_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func advance_to_ready() -> bool:
	var ready := int(Game.run.drying_batch.ready)
	Game.run.t = ready - 1
	Game.run.pday = 1 + int(Game.run.t / Post.DAY)
	var result := Post.advance(Game.run, 1)
	Game.refresh()
	await frames()
	return check(result.is_empty() and Game.run.t == ready and button(main._modals.drying, "收进存货") != null,
		"时钟未推进到可领取状态：%s，%d/%d，%s" % [result, Game.run.t, ready, copy(main._modals.drying)])


func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		push_error(detail)
		get_tree().quit(1)
	return ok


func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame


func button(scope: Node, prefix: String, enabled_only := true) -> Button:
	for item in scope.find_children("*", "Button", true, false):
		if item.is_visible_in_tree() and item.text.begins_with(prefix) and (not enabled_only or not item.disabled):
			return item
	return null


func copy(scope: Node) -> String:
	var words := PackedStringArray()
	for item in scope.find_children("*", "Label", true, false): words.append(item.text)
	return " ".join(words)


func click_button(scope: Node, prefix: String) -> bool:
	var b := button(scope, prefix)
	if not check(b != null, "找不到可点按钮：" + prefix): return false
	var position := b.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(position), "按钮在画面以外：" + prefix): return false
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = position
		ev.pressed = down
		get_viewport().push_input(ev)
		await frames(1)
	await frames()
	return true


func screen_shot(label: String) -> void:
	var dst := OS.get_environment("FOOD_DRYING_CAPTURES")
	if not dst.is_empty():
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(dst.path_join(label + ".png"))
