extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Events = preload("res://scripts/core/events.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const STEP := 0.5
var main: Control
var checks := 0
var failed := false
var messages: Array[String] = []


func check(ok: bool, msg: String) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error(msg)
	return ok


func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame


func key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func key(code: Key) -> void:
	key_event(code, true)
	await frames(2)
	key_event(code, false)
	await frames()


func modal_button(meta: String) -> Button:
	if not main.has_modal("expedition"): return null
	for b in main._modals.expedition.find_children("*", "Button", true, false):
		if str(b.get_meta("expedition_choice", "")) == meta: return b
	return null


func click(b: Button) -> void:
	if not check(is_instance_valid(b) and not b.disabled, "Missing enabled button"): return
	var container := b.get_parent()
	while container != null:
		if container is ScrollContainer:
			container.ensure_control_visible(b)
			await frames(3)
		container = container.get_parent()
	var p := b.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = p
	get_viewport().push_input(motion)
	await frames(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	ev.pressed = true
	get_viewport().push_input(ev)
	await frames(2)
	ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	get_viewport().push_input(ev)
	await frames(6)


func modal_text() -> String:
	var out := ""
	if main.has_modal("expedition"):
		for label in main._modals.expedition.find_children("*", "Label", true, false): out += label.text + "\n"
	return out


# 用角色同尺寸胶囊在物理世界寻找步行路径；此函数不会改变角色位置。
func route(target: String) -> Array:
	var world = main._screen.world
	var player: CharacterBody3D = main._screen.player
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var start := Vector2i(roundi(player.position.x / STEP), roundi(player.position.z / STEP))
	var todo: Array[Vector2i] = [start]
	var previous := {start: start}
	var cursor := 0
	var goal := start
	var found := false
	while cursor < todo.size():
		var cell: Vector2i = todo[cursor]
		cursor += 1
		var pos := Vector3(cell.x * STEP, 0, cell.y * STEP)
		var close_enough := false
		if target == "exit":
			close_enough = pos.distance_to(world.ENTRY) < 1.25 and world.nearest_feature(pos) == "" and world.nearest(pos) == -2
		elif target.begins_with("spot:"):
			var spot_idx := int(target.trim_prefix("spot:"))
			close_enough = pos.distance_to(world._spots[spot_idx].pos) < 1.35 and world.nearest_feature(pos) == "" and world.nearest(pos) == spot_idx
		else:
			close_enough = pos.distance_to(world.feature_positions[target]) < 1.0 and world.nearest_feature(pos) == target
		if close_enough:
			goal = cell
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if absi(n.x) > 22 or absi(n.y) > 20 or previous.has(n): continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis.IDENTITY, Vector3(n.x * STEP, 0.9, n.y * STEP))
			q.exclude = [player.get_rid()]
			if not space.intersect_shape(q, 1).is_empty(): continue
			previous[n] = cell
			todo.append(n)
	if not found: return []
	var path := [goal]
	while goal != start:
		goal = previous[goal]
		path.push_front(goal)
	return path


func walk(target: String) -> bool:
	var path := route(target)
	if not check(not path.is_empty(), "No walkable path to " + target): return false
	var player: CharacterBody3D = main._screen.player
	for i in range(1, path.size()):
		var cell: Vector2i = path[i]
		var goal := Vector2(cell.x * STEP, cell.y * STEP)
		for axis in [0, 1]:
			var remaining := (goal.x - player.position.x) if axis == 0 else (goal.y - player.position.z)
			if absf(remaining) < 0.12: continue
			var code: Key = (KEY_D if remaining > 0 else KEY_A) if axis == 0 else (KEY_S if remaining > 0 else KEY_W)
			key_event(code, true)
			for tick in 30:
				await get_tree().physics_frame
				var now := (goal.x - player.position.x) if axis == 0 else (goal.y - player.position.z)
				if absf(now) < 0.12 or signf(now) != signf(remaining): break
			key_event(code, false)
			await get_tree().physics_frame
			var err := absf((goal.x - player.position.x) if axis == 0 else (goal.y - player.position.z))
			if not check(err < 0.3, "Keyboard movement obstructed on route to " + target): return false
	await frames()
	var arrived: bool = main._screen._near == -2 if target == "exit" else (main._screen._near == int(target.trim_prefix("spot:")) if target.begins_with("spot:") else main._screen._near_feature == target)
	return check(arrived, "Keyboard walk did not reach %s at %s (near=%s, feature=%s)" % [target, str(player.position), str(main._screen._near), str(main._screen._near_feature)])


func visit(pid: String, wrong: String, right: String) -> void:
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 7
	Game.run.t = 6 * 1440 + 120
	Game.run.flags["temple_open"] = true
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	if not check(Post.act_explore(Game.run, pid) == "", "Departure " + pid): return
	Game.go("explore")
	await frames(12)
	var profile := Expedition.profile(pid)
	if not await walk("gate"): return
	var start_t := int(Game.run.t)
	await key(KEY_E)
	check(main.has_modal("expedition"), pid + " gate did not open")
	check(modal_text().contains("仅保留本次外出") and modal_text().contains("回家后重置"), pid + " missing per-visit notice")
	check(not modal_text().contains(str(profile.clues[0].text)), pid + " leaked undiscovered clue")
	check(modal_button(right) != null and modal_button(right).disabled, pid + " allowed choice before clues")
	await key(KEY_ESCAPE)
	check(not main.has_modal("expedition") and int(Game.run.t) == start_t and not Expedition.state(Game.run).unlocked, pid + " cancel changed state")
	for i in 2:
		if not await walk("clue_%d" % i): return
		# 让第一个地点的第一条线索恰在事件时刻完成，验证剧情优先且成果可回看。
		var event_boundary := pid == "rice_ruin" and i == 0
		if event_boundary:
			Game.run.t = 6 * 1440 + Post.EVENT_AT - int(profile.inspect_minutes)
			var selected := false
			for seed in range(100):
				var probe: Dictionary = Game.run.duplicate(true)
				probe.rng_n = seed
				var rolled := Events.roll(probe)
				if rolled != "":
					Game.run.rng_n = seed
					selected = true
					break
			if not check(selected, "No deterministic event fixture"): return
		var before := int(Game.run.t)
		await key(KEY_E)
		if event_boundary:
			check(Expedition.state(Game.run).clues[0] and main.has_modal("event") and not main.has_modal("expedition"), "Event did not take priority after completed clue")
			if main.has_modal("event"):
				for b in main._modals.event.find_children("*", "Button", true, false):
					if not b.disabled:
						await click(b)
						break
				if main.has_modal("event"):
					for b in main._modals.event.find_children("*", "Button", true, false):
						if b.text == "知道了":
							await click(b)
							break
			check(not main.has_modal("event") and Game.run.pending_event == "", "Event did not resolve")
			await key(KEY_E)
		check(main.has_modal("expedition") and modal_text().contains(str(profile.clues[i].text)), pid + " clue not visible")
		check(int(Game.run.t) == before + int(profile.inspect_minutes), pid + " clue time")
		await key(KEY_ESCAPE)
		await key(KEY_E)
		check(main.has_modal("expedition") and int(Game.run.t) == before + int(profile.inspect_minutes), pid + " repeat clue cost time")
		await key(KEY_ESCAPE)
		if i == 0:
			var journal: Button = null
			for b in main._screen.hud.find_children("*", "Button", true, false):
				if b.get_meta("expedition_journal", false): journal = b
			await click(journal)
			check(main.has_modal("expedition") and modal_text().contains(str(profile.clues[0].text)) and not modal_text().contains(str(profile.clues[1].text)), pid + " journal lost known or exposed unknown clue")
			await key(KEY_ESCAPE)
	if not await walk("gate"): return
	await key(KEY_E)
	check(modal_text().contains(str(profile.clues[0].text)) and modal_text().contains(str(profile.clues[1].text)), pid + " gate missing clues")
	if pid == "rice_ruin":
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(OS.get_temp_dir().path_join("ledger-expedition-puzzle.png"))
	var before := int(Game.run.t)
	var exposure := int(Game.run.explore.exposure)
	messages.clear()
	await click(modal_button(wrong))
	check(not Expedition.state(Game.run).unlocked and int(Game.run.t) == before + int(profile.answer_minutes) and int(Game.run.explore.exposure) == exposure + int(profile.wrong_exposure), pid + " wrong answer cost")
	check(not messages.is_empty(), pid + " wrong feedback missing")
	await key(KEY_E)
	await click(modal_button(right))
	check(Expedition.state(Game.run).unlocked and int(Game.run.t) == before + 2 * int(profile.answer_minutes), pid + " correct answer")
	await frames()
	var idx: int = main._screen.world.locked_spot_index
	if not check(idx >= 0, pid + " no locked target"): return
	if not await walk("spot:%d" % idx): return
	await key(KEY_E)
	if main.has_modal("explore_options"):
		for b in main._modals.explore_options.find_children("*", "Button", true, false):
			if b.get_meta("explore_option", "") == "normal":
				await click(b)
				break
	check(Game.run.explore.spots[idx].done and main.has_modal("explore_loot"), pid + " unlocked target not searchable")
	if main.has_modal("explore_loot"): main.close_modal("explore_loot")
	if not await walk("exit"): return
	await key(KEY_E)
	check(Game.run.explore.is_empty() and Game.screen == "post", pid + " could not return through exit")


func investigation_visit() -> void:
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 5
	Game.run.t = 4 * 1440 + 120
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Mainline.state(Game.run).stage = "mortuary"
	Game.run.points["mortuary"] = {"looted_until": 11, "visits": 1}
	if not check(Post.act_explore(Game.run, "mortuary") == "", "Investigation departure"): return
	check(Game.run.explore.only_investigate and Game.run.explore.spots.all(func(s): return s.has("mainline") or s.has("neighbor")), "Not an actual investigation-only visit")
	Game.go("explore")
	await frames(12)
	var hud_text := ""
	for label in main._screen.hud.find_children("*", "Label", true, false): hud_text += label.text + "\n"
	check(hud_text.contains("专程查访") and hud_text.contains("翻不出物资") and not hud_text.contains("搜寻 0 / 0"), "Investigation-only HUD misleading")
	if not await walk("gate"): return
	await key(KEY_E)
	check(main.has_modal("expedition") and modal_text().contains("机关后面也翻不出物资") and modal_text().contains("不受机关阻拦"), "Investigation-only gate missing explanation")
	await key(KEY_ESCAPE)
	var task := -1
	for i in Game.run.explore.spots.size():
		if Game.run.explore.spots[i].has("mainline"): task = i
	if not check(task >= 0, "Investigation task missing"): return
	if not await walk("spot:%d" % task): return
	await key(KEY_E)
	check(not Game.run.busy.is_empty() and Game.run.busy.get("kind", "") == "mainline", "Task inaccessible without solving optional gate")


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.toast.connect(func(message: String): messages.append(message))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	await visit("rice_ruin", "east", "west")
	await visit("pharmacy_ruin", "ginger", "ginseng")
	await investigation_visit()
	print("Expedition UI: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
