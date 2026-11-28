extends Node
## 从城内地图走进药铺，灾后从宅院的劫余录翻到人页，用真实按钮往返信件。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Story = preload("res://scripts/core/apothecary_story.gd")
const Inv = preload("res://scripts/core/inv.gd")
var main: Control
var checks := 0


func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 331)
	Game.speed = 0
	Game.go("pre")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	if not await click(main._screen.hud, "药铺"): return
	while main._screen.world.walking:
		await frames()
	await frames()
	if not await click(modal("shop"), "翻看药包"): return
	var hour: int = Game.run.hour
	if not await click(modal("apothecary_ticket"), "等药师辨方 · 1 时辰"): return
	if not check(Story.stage(Game.run) == "signed" and Game.run.hour == hour + 1, "普通身份没有用一个时辰换签"): return
	if not await click(modal("apothecary_ticket"), "合上"): return
	if not await click(modal("shop"), "合上"): return
	var run := Game.run
	while run.phase == "pre":
		Pre.end_day(run)
	# 此项只测药签；日程移到第二天开门，跳过首夜和无关的晨报。
	run.t = 1440 + 120
	run.pday = 2
	run.dawn_due = false
	run.plan_due = false
	Game.go("post")
	await frames()
	if not await click(main._screen.hud, "劫余录"): return
	if not await click(modal("journal"), "人"): return
	if not await click(modal("journal"), "纸鹤往来 · 交易与欠账"): return
	if not await click(modal("social_trade"), "过路客"): return
	if not await click(modal("social_trade"), "回春堂的七号药签"): return
	var stash := Inv.count(run.home, "salve")
	var oil := Inv.count(run.home, "lamp_oil")
	if not check(find_button(modal("apothecary_ticket"), "把金创药收回家 · 1 瓶") != null, "自留药品的路线没有展示"): return
	capture("choice")
	if not await click(modal("apothecary_ticket"), "把这瓶药留给渡口"): return
	var reply := find_button(modal("apothecary_ticket"), "接过回信与灯油")
	if not check(is_instance_valid(reply) and reply.disabled and Inv.count(run.home, "salve") == stash, "送药后同日能提前取回礼，或重复得到药"): return
	if not await click(modal("apothecary_ticket"), "合上"): return
	# 跨到次日同一时刻，再从原来的过路客入口取件。
	run.t += 1440
	run.pday += 1
	if not await click(modal("social_trade"), "回春堂的七号药签"): return
	if not await click(modal("apothecary_ticket"), "接过回信与灯油"): return
	if not check(Inv.count(run.home, "lamp_oil") == oil + 1 and Story.stage(run) == "replied", "渡灯油未从真实入口入库"): return
	if not check(find_button(modal("apothecary_ticket"), "接过回信与灯油") == null, "回信仍可重复取"): return
	capture("reply")
	main.queue_free()
	await frames()
	print("[apothecary_story_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func modal(key: String) -> Control:
	return main._modals.get(key)


func frames() -> void:
	for frame in 5:
		await get_tree().process_frame


func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		push_error(detail)
		get_tree().quit(1)
	return ok


func find_button(scope: Node, caption: String) -> Button:
	if not is_instance_valid(scope):
		return null
	for button in scope.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and (button.text == caption or button.tooltip_text == caption):
			return button
	return null


func click(scope: Node, caption: String) -> bool:
	var button := find_button(scope, caption)
	if not check(is_instance_valid(button) and not button.disabled, "找不到可用按钮：" + caption): return false
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await frames()
		parent = parent.get_parent()
	var center := button.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(center), "按钮在窗外：" + caption): return false
	var motion := InputEventMouseMotion.new()
	motion.position = center
	get_viewport().push_input(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.pressed = down
		event.button_index = MOUSE_BUTTON_LEFT
		get_viewport().push_input(event)
		await get_tree().process_frame
	await frames()
	return true


func capture(label: String) -> void:
	var temp := OS.get_environment("TEMP")
	if not temp.is_empty():
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(temp.path_join("apothecary-" + label + ".png")) == OK, "药签窗口截图写入失败")
