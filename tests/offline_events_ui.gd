extends Node
## Real window: every new offline decision has an affordable exit and fits 1280x720.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Data = preload("res://scripts/core/data.gd")
const Events = preload("res://scripts/core/events.gd")
var checks := 0
var failures := 0
var finished := 0
var main: Control

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func frames(count := 4) -> void:
	for index in count: await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func():
		push_error("offline_events_ui timed out")
		get_tree().quit(1))
	if not check(DisplayServer.get_name() != "headless", "Real rendered window required"):
		get_tree().quit(1)
		return
	Game.no_save = true
	Game.speed = 0
	Game.save_path = "user://offline-events-ui.json"
	Game.meta_path = "user://offline-events-ui-meta.json"
	StoryDirector.set_process(false)
	StoryDirector.offline_override = 1
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = State.new_run("scholar", Game.meta, 5151)
	Pre.start_disaster(Game.run)
	Game.go("post")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(12)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var selected := 0
	for test in [test_money, test_decisions, test_exhausted]:
		if only != "" and only != str(test.get_method()): continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and selected == finished, "Incomplete selected window checks")
	StoryDirector.offline_override = -1
	main.queue_free()
	await frames()
	print("[offline_events_ui] checks=%d completed=%d/%d failures=%d" % [checks, finished, selected, failures])
	get_tree().quit(1 if failures else 0)

func test_money() -> void:
	for pair in [[30, "30 文"], [150, "150 文"], [1000, "1 两"], [1250, "1 两 250 文"]]:
		if not check(Dialogs._event_req_text({"silver": pair[0]}) == pair[1], "Event money cost lost its exact denomination: " + str(pair[0])): return
	finished += 1

func test_exhausted() -> void:
	for id in Data.table("events"):
		if not (str(id).begins_with("oe_") or str(id).begins_with("os_")): continue
		if main.has_modal("event"): main.close_modal("event")
		var event: Dictionary = Data.table("events")[id]
		Game.run = State.new_run("scholar", Game.meta, 5151)
		Pre.start_disaster(Game.run)
		Game.run.pday = int(event.min_day)
		Game.run.t = (int(Game.run.pday) - 1) * 1440 + 120
		for item in Data.table("items"): Game.run.home[item] = 100
		Game.run.silver = 100000
		Game.run.attrs.energy = 0.0
		Game.run.pending_event = id
		Game.run.event_result = ""
		Game.refresh()
		await frames(5)
		if not check(main.has_modal("event"), "Exhausted event did not open: " + id): return
		var fallback: Button = null
		for choice in event.choices:
			var target: Button = null
			for button in main._modals.event.find_children("*", "Button", true, false):
				if button.text.begins_with(str(choice.text)):
					target = button
					break
			if not check(target != null, "Exhausted choice missing: " + id): return
			var cost := -float(choice.get("fx", {}).get("energy", 0))
			if cost > 0:
				if not check(target.disabled and target.tooltip_text.begins_with("精力不足"), "Unfunded effort is enabled or has a wrong reason: " + id): return
			elif choice.get("req", {}).is_empty():
				if not check(not target.disabled, "Zero-effort fallback was disabled: " + id): return
				fallback = target
		if not check(fallback != null, "Exhausted household has no free visible fallback: " + id): return
		var point := fallback.get_global_rect().get_center()
		for down in [true, false]:
			var event_click := InputEventMouseButton.new()
			event_click.position = point
			event_click.button_index = MOUSE_BUTTON_LEFT
			event_click.pressed = down
			get_viewport().push_input(event_click)
			await frames(2)
		await frames(3)
		if not check(Game.run.pending_event == "", "Exhausted player cannot leave event with actual mouse: " + id): return
	finished += 1

func test_decisions() -> void:
	var entries: Dictionary = Data.table("events")
	var ids: Array = []
	for id in entries:
		if str(id).begins_with("oe_") or str(id).begins_with("os_"): ids.append(id)
	ids.sort()
	if not check(ids.size() == 49, "Expected all 49 new window decisions"): return
	var longest := ""
	var longest_length := -1
	for id in ids:
		var length := JSON.stringify(entries[id]).length()
		if length > longest_length:
			longest = id
			longest_length = length
	var shots := {ids[0]: true, ids[-1]: true, longest: true}
	for id in ids:
		if main.has_modal("event"): main.close_modal("event")
		var event: Dictionary = entries[id]
		Game.run = State.new_run("scholar", Game.meta, 5151)
		Pre.start_disaster(Game.run)
		Game.run.pday = int(event.min_day)
		Game.run.t = (int(Game.run.pday) - 1) * 1440 + 120
		Game.run.home = {}
		Game.run.silver = 0
		Game.run.pending_event = id
		Game.run.event_result = ""
		Game.refresh()
		await frames(5)
		if not check(main.has_modal("event"), "New event modal did not open: " + id): return
		var modal = main._modals.event
		var free: Button = null
		var choices := 0
		for choice in event.choices:
			var found: Button = null
			for button in modal.find_children("*", "Button", true, false):
				if button.text.begins_with(str(choice.text)):
					found = button
					break
			if not check(found != null, "Missing event choice: " + id + "/" + str(choice.text)): return
			choices += 1
			if not check(found.disabled == (not Events.choice_ok(Game.run, choice)), "Button affordability differs from rules: " + id): return
			var rect: Rect2 = found.get_global_rect()
			if not check(rect.position.y >= 0 and rect.end.y <= 720 and rect.position.x >= 0 and rect.end.x <= 1280, "Event choice leaves viewport: " + id): return
			if choice.get("req", {}).is_empty() and free == null: free = found
		if not check(choices == event.choices.size() and free != null and not free.disabled, "Empty pantry has no enabled exit: " + id): return
		for label in modal.find_children("*", "Label", true, false):
			if not label.is_visible_in_tree(): continue
			var rect: Rect2 = label.get_global_rect()
			if not check(rect.position.y >= 0 and rect.end.y <= 720, "Event text is clipped vertically: " + id): return
		if shots.has(id):
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("user://screenshots")
			var path := "user://screenshots/offline-event-%s.png" % id
			if not check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot failed: " + id): return
		var point := free.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		get_viewport().push_input(motion)
		await frames(1)
		for down in [true, false]:
			var click := InputEventMouseButton.new()
			click.position = point
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			get_viewport().push_input(click)
			await frames(2)
		await frames(3)
		if not check(Game.run.pending_event == "" and not str(Game.run.event_result).is_empty(), "Real mouse choice did not resolve: " + id): return
		if not check(id in Game.run.seen_events, "Resolved event was not remembered: " + id): return
	finished += 1
