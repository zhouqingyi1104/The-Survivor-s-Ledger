extends Node
## Rendered fixture: real event/return clicks and E interaction, with an explicit clock.
## Positioning at a reachable spot is fixture setup, not a complete walked journey.

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Events = preload("res://scripts/core/events.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Inv = preload("res://scripts/core/inv.gd")

var checks := 0
var failures := 0
var finished := 0
var main: Control
var messages: Array[String] = []
var active_group := "startup"

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func frames(count := 5) -> void:
	for index in count: await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(210).timeout.connect(func():
		push_error("field_time_ui timed out group=" + active_group)
		get_tree().quit(1))
	if not check(DisplayServer.get_name() != "headless", "Real rendered window required"):
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Game.no_save = true
	Game.speed = 0
	Game.save_path = "user://field-time-ui.json"
	Game.meta_path = "user://field-time-ui-meta.json"
	Game.memory_path = "user://field-time-ui-Memory.md"
	StoryDirector.set_process(false)
	StoryDirector.offline_override = 1
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.toast.connect(func(message: String): messages.append(message))
	Game.run = State.new_run("escort", Game.meta, 5371)
	Pre.start_disaster(Game.run)
	Game.go("post")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(12)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var groups := {"outbound": test_outbound, "return": test_return, "rates": test_rates}
	var selected := 0
	for group in groups:
		if only != "" and only != group: continue
		selected += 1
		active_group = str(group)
		print("[field_time_ui] start=" + active_group)
		await groups[group].call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and selected == finished, "Unknown or incomplete selected window groups")
	Game.speed = 0
	StoryDirector.offline_override = -1
	main.queue_free()
	await frames()
	print("[field_time_ui] checks=%d completed=%d/%d failures=%d" % [checks, finished, selected, failures])
	get_tree().quit(1 if failures else 0)

func fixture(field := false) -> void:
	for id in main._modals.keys(): main.close_modal(id)
	Game.speed = 0
	Game.run = State.new_run("escort", Game.meta, 5371)
	Pre.start_disaster(Game.run)
	Game.run.t = 90 # Day one 07:30; the actual daily event interrupts at 08:00.
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	if field: Explore.begin(Game.run, "rice_ruin")
	Game.refresh()
	await frames(10)
	messages.clear()

func click(button: Button, enabled := true) -> void:
	if not check(is_instance_valid(button) and button.is_visible_in_tree(), "Missing visible mouse target"): return
	if not check(button.disabled != enabled, "Unexpected button availability: " + button.text): return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await frames(2)
		parent = parent.get_parent()
	var position := button.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(position), "Mouse target outside viewport: " + button.text): return
	var motion := InputEventMouseMotion.new()
	motion.position = position
	get_viewport().push_input(motion)
	await frames(1)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event)
		await frames(2)
	await frames(4)

func interact() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)
	await frames(4)

func answer_event() -> void:
	if not check(main.has_modal("event") and Game.run.pending_event != "", "Expected interrupted-travel event modal"): return
	var choices: Array = Events.entry(Game.run).get("choices", [])
	var selected: Button = null
	for choice in choices:
		if not choice.get("req", {}).is_empty() or not Events.choice_ok(Game.run, choice): continue
		for button in main._modals.event.find_children("*", "Button", true, false):
			if button.text.begins_with(str(choice.text)):
				selected = button
				break
		if selected != null: break
	if not check(selected != null, "Daily event lacks a usable mouse choice"): return
	await click(selected)
	if failures: return
	if not check(Game.run.pending_event == "" and main.has_modal("event"), "Mouse answer did not reach receipt"): return
	var acknowledge: Button = null
	for button in main._modals.event.find_children("*", "Button", true, false):
		if button.text == "知道了": acknowledge = button; break
	await click(acknowledge)
	check(not main.has_modal("event"), "Mouse acknowledgement failed to close event")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	check(get_viewport().get_texture().get_image().save_png("user://screenshots/field-time-%s.png" % name) == OK, "Screenshot failed: " + name)

func travel_ui(left: int) -> bool:
	var screen = main._screen
	if not check(Game.screen == "explore" and Post.is_busy(Game.run) and Game.run.busy.get("kind", "") == "travel", "Travel must keep the field screen busy"): return false
	if not check(is_instance_valid(screen._work_label) and screen._work_label.is_visible_in_tree() and screen._work_label.text.contains("赶路") and screen._work_label.text.contains("%d 分钟" % left), "Missing accurate visible remaining-travel label"): return false
	if not check(screen._hint.visible and screen._hint_label.text.contains("仍在赶路") and screen._hint_label.text.contains("%d 分钟" % left), "Nearby action hint hides remaining travel"): return false
	if not check(screen._return_button.disabled, "Return button enabled during travel"): return false
	for label in [screen._work_label, screen._hint_label]:
		var rect: Rect2 = label.get_global_rect()
		if not check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(rect), "Travel text clipped at 1280x720"): return false
	return true

func return_ui(left: int) -> bool:
	if not check(Game.screen == "post" and Game.run.explore.is_empty() and Post.is_busy(Game.run) and Game.run.busy.get("kind", "") == "travel", "Return must keep remaining travel busy on the home screen"): return false
	var screen = main._screen
	if not check(screen._tags.has("busy"), "Return travel lacks its existing visible busy tag"): return false
	var tag: Dictionary = screen._tags.busy
	return check(tag.panel.is_visible_in_tree() and tag.label.text.contains("赶路") and tag.label.text.contains("00:%02d" % left), "Home busy tag lost remaining return minutes")

## Place the fixture on free ground near an ordinary, unlocked container.
func position_at_container() -> int:
	var screen = main._screen
	var world = screen.world
	var player: CharacterBody3D = screen.player
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	for index in Game.run.explore.spots.size():
		var spot: Dictionary = Game.run.explore.spots[index]
		if spot.has("mainline") or spot.has("neighbor") or Explore.site_options(Game.run, index).size() != 1: continue
		for radius in [0.8, 1.1, 1.4]:
			for angle in range(0, 360, 30):
				var target: Vector3 = world._spots[index].pos + Vector3(cos(deg_to_rad(angle)) * radius, 0, sin(deg_to_rad(angle)) * radius)
				if world.nearest(target) != index or world.nearest_feature(target) != "" or world.nearest_journey(target) != "": continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.transform = Transform3D(Basis.IDENTITY, target + Vector3(0, 0.86, 0))
				query.exclude = [player.get_rid()]
				if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
				player.position = target
				player.velocity = Vector3.ZERO
				await frames(6)
				if screen._near == index and screen._near_feature == "" and screen._near_journey == "": return index
	check(false, "No reachable ordinary container fixture")
	return -1

func test_outbound() -> void:
	await fixture()
	if not check(Game.act(func(): return Post.act_explore(Game.run, "rice_ruin")) == "", "Real outbound action failed"): return
	await frames(10)
	if not check(int(Game.run.t) == 120 and int(Game.run.busy.get("end", 0)) == 150, "07:30 departure lost its remaining 30 minutes at 08:00"): return
	await answer_event()
	if failures or not travel_ui(30): return
	await shot("outbound-30")
	var index: int = await position_at_container()
	if failures: return
	var before: Dictionary = Game.run.duplicate(true)
	await click(main._screen._return_button, false)
	await interact()
	if not check(Game.run == before and not main.has_modal("explore_loot") and not main.has_modal("explore_options"), "Travel allowed early return or container search"): return
	main._screen.finish()
	if not check(not messages.is_empty() and messages[-1].contains("赶路") and not messages[-1].contains("调查"), "Early finish reported unfinished investigation instead of travel"): return
	await frames(12)
	if not check(int(Game.run.t) == 120, "Paused field screen advanced travel"): return
	Game.act(func(): return Post.advance(Game.run, 29))
	await frames(5)
	if not travel_ui(1): return
	await interact()
	if not check(int(Game.run.t) == 149 and not Game.run.explore.spots[index].done, "08:29 allowed early search"): return
	Game.act(func(): return Post.advance(Game.run, 1))
	await frames(5)
	if not check(int(Game.run.t) == 150 and not Post.is_busy(Game.run) and not main._screen._return_button.disabled, "08:30 failed to unlock field actions"): return
	await interact()
	if not check(Game.run.explore.spots[index].done and int(Game.run.t) == 170 and main.has_modal("explore_loot"), "Actual E search did not become available after arrival"): return
	await shot("arrived-search")
	finished += 1

func test_return() -> void:
	await fixture(true)
	Game.run.explore.bag = {"wood": 2}
	Game.refresh()
	await frames(5)
	var wood_before := Inv.count(Game.run.home, "wood")
	await click(main._screen._return_button)
	if failures: return
	if not check(int(Game.run.t) == 120 and int(Game.run.busy.get("end", 0)) == 150, "07:30 return lost its remaining 30 minutes"): return
	if not check(Game.run.explore.is_empty() and Inv.count(Game.run.home, "wood") == wood_before + 2, "Return changed the existing immediate cargo settlement"): return
	await answer_event()
	if failures or not return_ui(30): return
	await shot("return-30")
	var home: Dictionary = Game.run.home.duplicate(true)
	var before: Dictionary = Game.run.duplicate(true)
	var depart = Game.act(func(): return Post.act_explore(Game.run, "city_god"))
	var chore = Game.act(func(): return Post.act_rest(Game.run))
	if not check(str(depart) != "" and str(chore) != "" and Game.run == before, "Return travel allowed a second departure or home work"): return
	Game.act(func(): return Post.finish_explore(Game.run))
	if not check(Game.run == before, "Repeated return changed busy travel or credited cargo twice"): return
	Game.act(func(): return Post.advance(Game.run, 29))
	await frames(5)
	if not return_ui(1): return
	if not check(Game.run.home == home, "Remaining return travel credited cargo again"): return
	Game.act(func(): return Post.advance(Game.run, 1))
	await frames(10)
	if not check(Game.screen == "post" and Game.run.explore.is_empty() and not Post.is_busy(Game.run) and int(Game.run.t) == 150, "Actual return did not reach home at 08:30"): return
	if not check(Game.run.home == home, "Completed return credited cargo a second time"): return
	var arrived: Dictionary = Game.run.home.duplicate(true)
	Game.act(func(): return Post.finish_explore(Game.run))
	Game.act(func(): return Post.advance(Game.run, 1))
	if not check(Game.run.home == arrived and Game.run.explore.is_empty(), "Repeated return credited cargo twice"): return
	await shot("returned-home")
	finished += 1

func test_rates() -> void:
	await fixture()
	Game.act(func(): return Post.act_explore(Game.run, "rice_ruin"))
	await frames(10)
	await answer_event()
	if failures: return
	var screen = main._screen
	screen.set_process(false)
	screen._acc = 0.0
	var start := int(Game.run.t)
	Game.speed = 0
	screen._process(1.0)
	if not check(int(Game.run.t) == start, "Paused travel ignored speed zero"): return
	Game.speed = 1
	screen._process(0.025)
	Game.speed = 0
	if not check(int(Game.run.t) == start + 1, "Travel did not use the existing 40-minute busy rate"): return
	Game.act(func(): return Post.advance(Game.run, 29))
	await frames(5)
	if not check(not Post.is_busy(Game.run), "Rate fixture did not finish travel"): return
	screen._acc = 0.0
	start = int(Game.run.t)
	Game.speed = 3
	screen._process(0.25)
	Game.speed = 0
	if not check(int(Game.run.t) == start + 1, "Ordinary field time changed from 4 minutes per second"): return
	screen.set_process(true)
	finished += 1
