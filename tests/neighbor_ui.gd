extends Node
## Window-rendered integration fixture; never uses the player's save files.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Data = preload("res://scripts/core/data.gd")
var main: Control
var failures := 0
var checks := 0
var out := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for k in count:
		await get_tree().process_frame

func press(prefix: String) -> void:
	var found: Button
	for button in main.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix) and not button.disabled:
			found = button
			break
	check(found != null, "Missing enabled UI button: " + prefix)
	if found != null:
		found.pressed.emit()
	await frames()

func screen() -> Node:
	return main._screen

func snapshot(name: String) -> void:
	await frames(8)
	var viewport := get_viewport().get_visible_rect()
	for modal in main._modals.values():
		for button in modal.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				check(viewport.encloses(button.get_global_rect()), "Modal button clipped: " + button.text)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Neighbor UI frame: ", name)

func set_time(day: int, minute := 180) -> void:
	Game.run.pday = day
	Game.run.t = (day - 1) * 1440 + minute
	Neighbor.poll(Game.run)
	Game.refresh()
	await frames()

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.meta = State.new_meta()
	out = OS.get_environment("TEMP").path_join("unknownGame-neighbor-ui")
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	Game.run = State.new_run("escort", Game.meta, 4242)
	Pre.start_disaster(Game.run)
	Game.run.home = {"wood": 3, "rice": 5}
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Neighbor.poll(Game.run)
	Game.go("post")
	await snapshot("01-request")
	await press("答应去药铺取药")
	await press("知道了")
	await press("查看 / 处理")
	await snapshot("02-task-log")
	await press("准备随身撬杆")
	check(Game.run.neighbor.pry, "Preparation did not update story")
	await press("出门去药铺废墟")
	check(Game.screen == "explore", "UI departure failed")
	check(Game.run.explore.spots[0].name == Neighbor.CABINET, "Cabinet absent in actual screen")
	# Use the same E-key handler used by the player at the task target.
	screen().player.position = screen().world._spots[0].pos
	screen()._near = 0
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	screen()._unhandled_input(key)
	await snapshot("03-cabinet")
	await press("用随身撬杆轻轻撬开")
	await press("知道了")
	await press("回家")
	check(Game.run.pending_event == "n_delivery", "UI arrival lost delivery")
	await snapshot("04-delivery")
	# Persist the actual pending event using only a unique scratch save.
	Game.save_path = "user://neighbor-ui-%d.json" % OS.get_process_id()
	Game.no_save = false
	Game.save_game()
	Game.run = {}
	Game.continue_game()
	Game.no_save = true
	await frames()
	check(Game.run.pending_event == "n_delivery" and Game.run.neighbor.medicine, "Actual save/load lost reserved medicine")
	await press("按约把药送过去")
	await press("知道了")
	await set_time(3, 400)
	await snapshot("05-delayed-thanks")
	await press("收木料和铁钉")
	await press("知道了")
	await set_time(6)
	await press("去义庄查守庄人的药账")
	await press("知道了")
	await press("查看 / 处理")
	await press("出门去义庄")
	check(Game.run.explore.spots[0].name == Neighbor.ACCOUNT, "Mortuary task absent")
	screen().search(0)
	await frames()
	await press("回家")
	await snapshot("06-evidence")
	await press("把药账和符交给阿宁")
	await press("知道了")
	await press("查看 / 处理")
	await snapshot("07-completed-history")
	check(Game.run.neighbor.stage == "closed" and State.flag(Game.run, "temple_open"), "End-to-end ending failed")
	check(Game.run.neighbor.history.size() >= 8, "Choice history missing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	main.queue_free()
	await frames()
	print("Neighbor UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
