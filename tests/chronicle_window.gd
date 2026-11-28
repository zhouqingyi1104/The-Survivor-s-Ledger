extends Node

const Story = preload("res://scripts/core/chronicle_story.gd")
const Pre = preload("res://scripts/core/pre.gd")
var main: Control
var checks := 0


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	if not await click(main._screen, "新开一卷"): return
	if not check(Game.screen == "pre" and Story.enabled(Game.run), "标题没有开启百日卷"): return
	while Game.run.phase == "pre":
		Game.act(func(): return Pre.end_day(Game.run))
	await frames()
	if not await click(main._screen.hud, "百日街坊 · 有来信"): return
	var event := Story.current_event(Game.run)
	capture("01-桂娘的井绳")
	var choice: Dictionary
	for option in event.options:
		if option.cost.is_empty():
			choice = option
			break
	if not check(not choice.is_empty(), "首日没有免费回信"): return
	if not await click(main._modals.hundred_days, str(choice.label)): return
	if not check(Game.run.hundred_days.choices[event.id] == choice.id, "点击后选择未记账"): return
	if not await click(main._modals.hundred_days, "翻看旧信（1）"): return
	var result_visible := false
	for entry in main._modals.chronicle_archive.find_children("*", "Label", true, false):
		if entry.text == choice.result and entry.is_visible_in_tree(): result_visible = true
	if not check(result_visible, "旧信里缺少自己选下的结果"): return
	capture("02-街坊旧信")
	main.queue_free()
	await frames()
	print("[chronicle_window] %d checks, 0 failures" % checks)
	get_tree().quit()


func frames() -> void:
	for i in 5:
		await get_tree().process_frame


func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		push_error(detail)
		get_tree().quit(1)
	return ok


func click(scope: Node, caption: String) -> bool:
	var target: Button
	for button in scope.find_children("*", "Button", true, false):
		if button.text == caption and button.is_visible_in_tree():
			target = button
			break
	if not check(is_instance_valid(target) and not target.disabled, "找不到可用按钮：" + caption): return false
	var center := target.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(center), "按钮在可视区域外：" + caption): return false
	var motion := InputEventMouseMotion.new()
	motion.position = center
	get_viewport().push_input(motion)
	for down in [true, false]:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = center
		press.pressed = down
		get_viewport().push_input(press)
		await get_tree().process_frame
	await frames()
	return true


func capture(label: String) -> void:
	var path := OS.get_environment("CHRONICLE_SCREENSHOTS")
	if not path.is_empty():
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(path.path_join(label + ".png")) == OK, "截图未写入")
