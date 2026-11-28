extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Visitor = preload("res://scripts/world/chronicle_visitor.gd")
const Data = preload("res://scripts/core/data.gd")

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> bool:
	if ok: passed += 1
	else:
		failed += 1
		push_error("百日庭院来客：" + label)
	return ok

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func capture(id: String) -> void:
	var dir := OS.get_environment("CHRONICLE_VISITOR_SHOTS")
	if dir != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(id + ".png"))

func _ready() -> void:
	Game.no_save = true
	Game.memory_path = "user://visitor-test.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 581, "normal", [], [], [], true)
	Pre.start_disaster(Game.run)
	Game.run.t = 360
	Game.screen = "post"
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(30)
	var screen: Control = main._screen
	var info: Dictionary = screen.world.spot_info(Visitor.SPOT)
	if not check(info.get("event") == "well_bucket" and info.get("name") == "桂娘 · 井匠", "首日庭院来访者"):
		get_tree().quit(1)
		return
	await capture("01-courtyard")
	var pos: Vector2 = screen.rig.cam.unproject_position(Visitor.PLACE + Vector3.UP * 0.99)
	check(screen.world.pick(screen.rig.cam, pos).get("spot") == Visitor.SPOT, "井匠的身体可被正常射线拾取")
	var start: Vector3 = screen.player.global_position
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = pos
		mouse.pressed = down
		get_viewport().push_input(mouse)
	var until := Time.get_ticks_msec() + 8000
	while not main.has_modal("hundred_days") and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(main.has_modal("hundred_days") and screen.player.global_position.distance_to(start) > 0.9 and screen.player.global_position.distance_to(Visitor.STAND) < 0.9, "从默认出生点点击后，玩家走近并打开当日故事")
	UI.close_modal("hundred_days")
	await frames(4)
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_E
		key.physical_keycode = KEY_E
		key.pressed = down
		get_viewport().push_input(key)
	await frames(6)
	check(main.has_modal("hundred_days"), "站在来客身边按 E 交谈")
	await capture("02-conversation")
	for b in main.find_children("*", "Button", true, false):
		if b.get_meta("chronicle_choice", "") == "shift":
			b.pressed.emit()
			break
	await frames(8)
	check(Game.run.hundred_days.choices.get("well_bucket") == "shift" and screen.world.spot_info(Visitor.SPOT).is_empty(), "通过窗内选择回应，来访者离场")
	UI.close_modal("hundred_days")
	var seen := {}
	for event in Data.table("hundred_days").events:
		Game.run.pday = int(event.day)
		Game.run.t = (Game.run.pday - 1) * 1440 + 360
		Game.run.hundred_days.choices.erase(event.id)
		var person: String = str(event.person).get_slice("、", 0)
		if not seen.has(person) or event.day == 100:
			screen.world.set_time(Game.run)
			var guest: Dictionary = screen.world.spot_info(Visitor.SPOT)
			check(str(guest.get("name", "")).begins_with(person) and guest.get("event") == event.id, "姓名、角色、信件一致 " + person)
			seen[person] = true
		Game.run.hundred_days.choices[event.id] = event.options[0].id
	check(seen.size() == 9, "九名有名街坊均已现身")
	Game.run.hundred_days.choices.erase("hundredth_register")
	Game.run.t = 99 * 1440 + Post.DUSK_AT
	screen.world.set_time(Game.run)
	check(screen.world.spot_info(Visitor.SPOT).is_empty(), "夜间庭院没有白天访客")
	Game.run.t = 99 * 1440 + 360
	screen.world.set_time(Game.run)
	screen.world.set_floor("cellar")
	screen.world.set_time(Game.run)
	check(screen.world.spot_info(Visitor.SPOT).is_empty() and not screen.world.spot_nodes.has(Visitor.SPOT), "楼内不显示庭院来客或交互")
	screen.world.set_floor("courtyard")
	Game.run.erase("hundred_days")
	screen.world.set_time(Game.run)
	check(screen.world.spot_info(Visitor.SPOT).is_empty(), "短局不出现百日来访者")
	main.queue_free()
	await frames(4)
	print("[HUNDRED_DAYS_VISITOR] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
