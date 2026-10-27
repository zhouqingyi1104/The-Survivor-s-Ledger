extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Events = preload("res://scripts/core/events.gd")
const SiteJourney = preload("res://scripts/core/site_journey.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const HomeWorld = preload("res://scripts/world/home_world.gd")
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
			close_enough = pos.distance_to(world.ENTRY) < 1.25 and world.nearest_feature(pos) == "" and world.nearest_journey(pos) == "" and world.nearest(pos) == -2
		elif target.begins_with("journey:"):
			var jid := target.trim_prefix("journey:")
			close_enough = pos.distance_to(world.journey_positions[jid]) < 1.0 and world.nearest_feature(pos) == "" and world.nearest_journey(pos) == jid
		elif target.begins_with("spot:"):
			var spot_idx := int(target.trim_prefix("spot:"))
			close_enough = pos.distance_to(world._spots[spot_idx].pos) < 1.35 and world.nearest_feature(pos) == "" and world.nearest_journey(pos) == "" and world.nearest(pos) == spot_idx
		else:
			close_enough = pos.distance_to(world.feature_positions[target]) < 1.0 and world.nearest_feature(pos) == target
		if close_enough:
			goal = cell
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if absi(n.x) > 60 or absi(n.y) > 60 or previous.has(n): continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis.IDENTITY, Vector3(n.x * STEP, 0.9, n.y * STEP))
			q.exclude = [player.get_rid()]
			if not space.intersect_shape(q, 1).is_empty(): continue
			# 相邻格子均为空仍可能被薄墙隔开；检查整段胶囊扫掠。
			q.transform = Transform3D(Basis.IDENTITY, Vector3(cell.x * STEP, 0.9, cell.y * STEP))
			q.motion = Vector3(d.x * STEP, 0, d.y * STEP)
			if space.cast_motion(q)[0] < 1.0: continue
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
			if not check(err < 0.3, "Keyboard movement obstructed on route to %s at %s towards %s axis %d: enabled=%s modals=%s pending=%s clock=%d" % [target, str(player.position), str(goal), axis, str(player.enabled), str(main._modals.keys()), str(Game.run.get("pending_event", "")), int(Game.run.t)]): return false
	await frames()
	var arrived: bool = main._screen._near == -2 if target == "exit" else (main._screen._near_journey == target.trim_prefix("journey:") if target.begins_with("journey:") else (main._screen._near == int(target.trim_prefix("spot:")) if target.begins_with("spot:") else main._screen._near_feature == target))
	return check(arrived, "Keyboard walk did not reach %s at %s (near=%s, feature=%s)" % [target, str(player.position), str(main._screen._near), str(main._screen._near_feature)])


func journey_button(meta: String, value: String) -> Button:
	if not main.has_modal("site_journey"): return null
	for b in main._modals.site_journey.find_children("*", "Button", true, false):
		if str(b.get_meta(meta, "")) == value: return b
	return null


func hud_text() -> String:
	var out := ""
	for label in main._screen.hud.find_children("*", "Label", true, false): out += label.text + "\n"
	return out


func labels(root: Node) -> String:
	var out := ""
	for label in root.find_children("*", "Label", true, false): out += label.text + "\n"
	return out


func departure_menu() -> void:
	Game.speed = 0
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 7
	Game.run.t = 6 * 1440 + 500
	Game.run.flags["temple_open"] = true
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Mainline.state(Game.run).stage = "mortuary"
	Game.run.points["mortuary"] = {"looted_until": 11, "visits": 1}
	Game.go("post")
	await frames(12)
	# 门口 fixture 只定位入口；菜单通过玩家 E 和真实鼠标打开。
	main._screen.player.position = HomeWorld.SPOTS.gate.stand
	await frames()
	await key(KEY_E)
	var exit_button: Button = null
	for b in main._screen._menu.find_children("*", "Button", true, false):
		if b.text.begins_with("出门搜寻"): exit_button = b
	await click(exit_button)
	if not check(main.has_modal("explore_pick"), "Gate did not open departure menu"): return
	var text := labels(main._modals.explore_pick)
	check(text.contains("抵达后距21:00约 340 分钟") and text.contains("返程另需60分钟") and text.contains("含行走、机关和翻找") and text.contains("不含往返"), "Departure budget explanation missing")
	for spec in [["rice_ruin", "简单", "3–5小时"], ["pharmacy_ruin", "中等", "4–8小时"], ["granary", "困难", "8–12小时"]]:
		var row: Node = null
		for b in main._modals.explore_pick.find_children("*", "Button", true, false):
			if b.get_meta("explore_depart", "") == spec[0]: row = b.get_parent()
		check(row != null and labels(row).contains(spec[1]) and labels(row).contains(spec[2]), "Departure grade/estimate missing for " + str(spec[0]))
	var investigation: Node = null
	for b in main._modals.explore_pick.find_children("*", "Button", true, false):
		if b.get_meta("explore_depart", "") == "mortuary": investigation = b.get_parent()
	check(investigation != null and labels(investigation).contains("普通物资尚未恢复") and not labels(investigation).contains("可能找到"), "Investigation-only departure still promises supplies")
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(OS.get_temp_dir().path_join("ledger-journey-departure.png"))
	await key(KEY_ESCAPE)
	Game.speed = 1


func run_route(pid: String, item: String, count: int, answer: String) -> void:
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 7
	Game.run.t = 6 * 1440
	Game.run.flags["temple_open"] = true
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	if not check(Post.act_explore(Game.run, pid) == "", "Departure " + pid): return
	# 真实时钟从出发后运行；选择一个不会在 8:00 抽到随机剧情的确定性种子。
	for seed in range(100):
		var probe: Dictionary = Game.run.duplicate(true)
		probe.rng_n = seed
		if Events.roll(probe) == "":
			Game.run.rng_n = seed
			break
	Game.go("explore")
	await frames(12)
	var profile := SiteJourney.profile(pid)
	check(profile.stages.size() == count and hud_text().contains("现场行动 0 / %d" % count) and hud_text().contains("距21:00还有") and hud_text().contains("返程 60 分钟"), pid + " route budget/progress absent")
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(OS.get_temp_dir().path_join("ledger-journey-hud-" + pid + ".png"))
	var start_t := int(Game.run.t)
	var home_before := Inv.count(Game.run.home, item)
	for stage in profile.stages:
		var id := str(stage.id)
		if not await walk("journey:" + id): return
		await key(KEY_E)
		if not check(main.has_modal("site_journey"), pid + " stage did not open " + id): return
		check(labels(main._modals.site_journey).contains("完成后不可改选"), pid + " missing irreversible choice notice")
		if id == "s0":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(OS.get_temp_dir().path_join("ledger-journey-choice-" + pid + ".png"))
		var before := int(Game.run.t)
		if id == "s0":
			await key(KEY_ESCAPE)
			check(not SiteJourney.state(Game.run).completed.has(id) and int(Game.run.t) <= before + 1, pid + " cancel cost or progress")
			await key(KEY_E)
		await click(journey_button("journey_choice", "careful"))
		if not check(SiteJourney.state(Game.run).completed.has(id), "%s stage not completed %s: screen=%s pending=%s messages=%s" % [pid, id, Game.screen, Game.run.get("pending_event", ""), str(messages)]): return
		check(int(Game.run.t) >= before + int(stage.choices[0].minutes), pid + " action did not consume listed time")
		if id == "s0":
			check(main.has_modal("site_journey") and journey_button("journey_take", item) != null, pid + " missing cache")
			await click(journey_button("journey_take", item))
			check(Inv.count(Game.run.explore.bag, item) == 1, pid + " cannot take cache item")
			await click(journey_button("journey_put", item))
			check(Inv.count(Game.run.explore.bag, item) == 0, pid + " cannot put back item")
			await click(journey_button("journey_take", item))
			check(Inv.count(Game.run.explore.bag, item) == 1, pid + " cannot retake cache item")
		if main.has_modal("site_journey"): await key(KEY_ESCAPE)
		await key(KEY_E)
		check(main.has_modal("site_journey") and journey_button("journey_choice", "careful") == null and labels(main._modals.site_journey).contains("不能改选"), pid + " completed stage could not reopen")
		if main.has_modal("site_journey"): await key(KEY_ESCAPE)
	check(SiteJourney.state(Game.run).completed.size() == count and int(Game.run.t) > start_t, pid + " incomplete route")
	for i in 2:
		if not await walk("clue_%d" % i): return
		await key(KEY_E)
		check(main.has_modal("expedition"), pid + " clue modal missing")
		if main.has_modal("expedition"): await key(KEY_ESCAPE)
	if not await walk("gate"): return
	await key(KEY_E)
	await click(modal_button(answer))
	check(Expedition.state(Game.run).unlocked, pid + " puzzle did not unlock")
	for i in Game.run.explore.spots.size():
		var spot: Dictionary = Game.run.explore.spots[i]
		if spot.has("mainline") or spot.has("neighbor"): continue
		if not await walk("spot:%d" % i): return
		await key(KEY_E)
		if main.has_modal("explore_options"):
			for b in main._modals.explore_options.find_children("*", "Button", true, false):
				if b.get_meta("explore_option", "") == "normal":
					await click(b)
					break
		check(spot.done and main.has_modal("explore_loot"), pid + " ordinary search did not complete")
		if main.has_modal("explore_loot"): await key(KEY_ESCAPE)
	var elapsed := int(Game.run.t) - start_t
	var bounds := Vector2i(180, 300) if profile.grade == "easy" else (Vector2i(240, 480) if profile.grade == "medium" else Vector2i(480, 720))
	check(elapsed >= bounds.x and elapsed <= bounds.y, "%s full 1x route took %d game minutes, expected %d–%d" % [pid, elapsed, bounds.x, bounds.y])
	print("Route ", pid, ": arrival to all stages, puzzle, searches ", elapsed, " game minutes; remaining ", maxi(0, Post.CURFEW_AT - Post.day_minute(Game.run)))
	if not await walk("exit"): return
	await key(KEY_E)
	print("Route ", pid, ": arrival through return ", int(Game.run.t) - start_t, " game minutes")
	check(Game.run.explore.is_empty() and Inv.count(Game.run.home, item) == home_before + 1, pid + " return lost selected supplies")


func _ready() -> void:
	Game.no_save = true
	Game.speed = 1
	Game.toast.connect(func(message: String): messages.append(message))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(300).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	await departure_menu()
	if OS.get_environment("JOURNEY_ONLY") != "hard":
		await run_route("rice_ruin", "rice", 3, "west")
		await run_route("pharmacy_ruin", "mugwort", 5, "ginseng")
	await run_route("mortuary", "talisman", 8, "west")
	print("Site journey UI: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
