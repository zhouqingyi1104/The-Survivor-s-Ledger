extends Node
## Real socket + delayed mock provider. No personal ARK calls or player save writes.
const Core = preload("res://scripts/core/director.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Events = preload("res://scripts/core/events.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
var failures := 0
var frames := 0
var main: Control

func _process(_delta: float) -> void:
	frames += 1

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.speed = 0
	Game.save_path = "user://director-fixture-%d.json" % OS.get_process_id()
	Game.meta_path = "user://director-fixture-meta-%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.run = State.new_run("escort", Game.meta, 654321)
	Pre.start_disaster(Game.run)
	Game.run.home = {"wood": 1, "rice": 5}
	Neighbor.state(Game.run).stage = "closed"
	Game.run.neighbor.ending = "fixture"
	Game.go("post")
	for k in 12: await get_tree().process_frame
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("TEMP").path_join("ledger-director-fixture.json")))
	var sent := Core.snapshot(Game.run)
	Game.no_save = false
	var start := Time.get_ticks_msec()
	var initial_frames := frames
	var initial_position: Vector3 = main._screen.player.position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var err := StoryDirector.request_plan(sent, config)
	check(err == OK, "Fixture request could not start")
	while not StoryDirector._sent.is_empty() and Time.get_ticks_msec() - start < 10000:
		await get_tree().process_frame
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(frames - initial_frames > 10, "Slow planning blocked frame processing")
	check(main._screen.player.position.distance_to(initial_position) > 0.5, "Slow planning blocked physical movement")
	check(StoryDirector.last_status == "prepared" and Core.state(Game.run).queue.size() == 3, "Asynchronous plan was not buffered")
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Core.poll(Game.run)
	Game.refresh()
	for k in 6: await get_tree().process_frame
	check(main.has_modal("event"), "Prepared event did not reach actual UI")
	var viewport := get_viewport().get_visible_rect()
	for button in main._modals.event.find_children("*", "Button", true, false):
		check(viewport.encloses(button.get_global_rect()), "Dynamic choice clipped")
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("ledger-director-dynamic-event.png")
	get_viewport().get_texture().get_image().save_png(path)
	check(Events.choose(Game.run, 0) == "", "Dynamic UI event could not resolve")
	check(Inv.count(Game.run.home, "wood") == 0 and Core.state(Game.run).promises.size() == 1, "Cost/promise missing")
	Game.save_game()
	Game.run = {}
	Game.continue_game()
	check(Core.state(Game.run).promises.size() == 1, "Save/load lost dynamic promise")
	Game.run.pday = 3
	Game.run.t = 2880 + 120
	Core.poll(Game.run)
	Core.poll(Game.run)
	check(Inv.count(Game.run.home, "firewood") == 2, "Delayed consequence duplicated or disappeared")
	# An identical restored save has the same session/revision/time but a new run object.
	# A pre-load HTTP response must still be discarded.
	var before_load := Core.snapshot(Game.run)
	StoryDirector._sent = before_load
	StoryDirector._sent_run = Game.run
	Game.run = Game.run.duplicate(true)
	var stale_plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for event in stale_plan.days: event.day += int(before_load.current_day)
	StoryDirector._completed(HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify({"source": "ark-plan", "plan": stale_plan}).to_utf8_buffer())
	check(StoryDirector.last_status == "discarded" and Core.state(Game.run).queue.is_empty(), "Pre-load response crossed into identical restored save")
	Game.no_save = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.meta_path))
	main.queue_free()
	for k in 3: await get_tree().process_frame
	print("Director async UI: %d frames during delayed planning, %d failures" % [frames - initial_frames, failures])
	get_tree().quit(0 if failures == 0 else 1)
