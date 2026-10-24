extends Node
## Real mouse/E-key story paths. Save, meta and Memory never use player paths.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
var main: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		get_tree().quit(1) # Stop at the first true failure; later branches are not evidence.
	return ok

func frames(n := 5) -> void:
	for k in n: await get_tree().process_frame

func modal() -> Node:
	return main._modals.get("mainline")

func labels_in(node: Node) -> String:
	var lines := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func meta_button(key: String, value, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.has_meta(key) and button.get_meta(key) == value: return button
	return null

func prefix_button(prefix: String, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix): return button
	return null

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Missing enabled mainline mouse target"): return
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await frames(2)
		ancestor = ancestor.get_parent()
	var point := button.get_global_rect().get_center()
	for k in (2 if twice else 1):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		Input.parse_input_event(press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = point
		Input.parse_input_event(release)
	await frames(7)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames()

func set_time(day: int, minute := 240) -> void:
	Game.run.pday = day
	Game.run.t = (day - 1) * 1440 + minute
	for attr in ["food", "water", "mood", "energy", "warmth"]: Game.run.attrs[attr] = 100
	Post.trade_refresh(Game.run)
	Game.refresh()
	await frames(6)

func fresh() -> void:
	await close_modals()
	Game.run = State.new_run("escort", Game.meta, 1842)
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Game.run.home = {"rice": 40, "water": 40, "firewood": 30, "wood": 30, "nails": 20, "talisman": 20, "talisman_paper": 20, "lamp_oil": 20, "dog_blood": 20}
	Game.run.known_clues = Data.table("clues").keys()
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	# Prior lives are really archived below; their unrelated awakening popups are
	# covered separately, and must not interrupt this exact-minute story fixture.
	Past.state(Game.run).schedule = []
	Mainline.state(Game.run)
	Npc.state(Game.run)
	Crisis.state(Game.run)
	await set_time(3)
	Game.go("post")
	await frames(7)
	check(not Mainline.state(Game.run).evidence.mortuary and not Mainline.state(Game.run).evidence.temple, "Inherited clues fabricated current-life evidence")

func open_story(from_journal := false) -> void:
	await close_modals()
	if from_journal:
		var journal: Button
		for button in main._screen.hud.find_children("*", "Button", true, false):
			if button.tooltip_text == "劫余录": journal = button; break
		await click(journal)
		await click(prefix_button("尸劫来历", main._modals.get("journal")))
	else: await click(meta_button("mainline_entry", true))
	check(modal() != null, "Visible story entry failed")

func advance_work(minutes: int) -> void:
	var before := int(Game.run.t)
	Game.act(func(): Post.advance(Game.run, minutes); return "")
	await frames(7)
	check(int(Game.run.t) == before + minutes, "Actual story work clock stopped: expected %d, actual %d, stage %s, pending %s" % [before + minutes, int(Game.run.t), str(Mainline.state(Game.run).stage), str(Game.run.pending_event)])

func snapshot(name: String, target: Node = null) -> void:
	await frames(6)
	if main._toasts.get_child_count() > 0: await get_tree().create_timer(2.9).timeout
	var viewport := get_viewport().get_visible_rect()
	if target == null: target = modal() if modal() != null else main._screen
	for panel in target.find_children("*", "PanelContainer", true, false):
		var ancestor: Node = panel.get_parent()
		var scrolling := false
		while ancestor != null:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling: check(viewport.encloses(panel.get_global_rect()), "Mainline outer panel exceeded 1280x720")
	for button in target.find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= viewport.end.x, "Mainline mouse target exceeded viewport width")
	if modal() != null:
		var scroll: ScrollContainer = modal().find_child("MainlineDetailsScroll", true, false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "Story costs/history do not scroll")
	if Game.screen == "post":
		var crisis: Control = main._screen.hud.find_child("CrisisHUDCard", true, false)
		if crisis != null:
			for panel in main._screen.hud.find_children("*", "PanelContainer", true, false):
				if panel == crisis or crisis.is_ancestor_of(panel): continue
				check(not crisis.get_global_rect().intersects(panel.get_global_rect()), "Mainline task integration obscured crisis card")
	DisplayServer.window_move_to_foreground()
	RenderingServer.force_draw() # A minimized/occluded window may skip frame_post_draw.
	var path := OS.get_environment("TEMP").path_join("ledger-mainline-" + name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Mainline screenshot failed")
	print("Mainline UI frame: ", path)

func choose(action: String, twice := false) -> void:
	if modal() == null: await open_story()
	await click(meta_button("mainline_action", action, modal()), twice)

func search_objective(kind: String) -> void:
	var idx := -1
	for k in Game.run.explore.spots.size():
		if str(Game.run.explore.spots[k].get("mainline", "")) == kind: idx = k; break
	if not check(idx >= 0, "Special mainline target missing from physical site"): return
	main._screen.player.position = main._screen.world._spots[idx].pos
	await frames(7)
	check(int(main._screen._near) == idx, "Physical proximity did not select mainline target")
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = KEY_E
	Input.parse_input_event(release)
	await frames(7)
	check(Game.run.busy.get("kind", "") == "mainline", "Actual E key did not start real investigation")
	check(meta_button("mainline_return", true).disabled, "Return button allowed unfinished investigation to be bypassed")
	check(str(main._screen._hint_label.text).contains("中") and not str(main._screen._hint_label.text).contains("已经翻过"), "Unfinished field work was described as already searched")

func investigate(kind: String, day: int, save_return := false) -> void:
	await close_modals()
	await set_time(day)
	if save_return:
		Neighbor.state(Game.run).stage = "investigate"
		Game.run.prof.search = 25 # Four ordinary spots plus two independent story targets.
	await open_story()
	var target := "mortuary" if kind == "mortuary" else "taoist_temple"
	if save_return:
		await click(meta_button("mainline_map", true, modal()))
		check(main.has_modal("explore_pick") and labels_in(main._modals.explore_pick).contains("本世调查"), "Actual map entry did not explain the special investigation")
		await click(meta_button("explore_depart", target, main._modals.explore_pick))
	else: await click(meta_button("mainline_depart", target, modal()))
	check(Game.screen == "explore", "Actual mouse departure did not reach the investigation site")
	if save_return:
		var has_neighbor := false
		check(Game.run.explore.spots.size() == 6, "The visit lost a normal or independent story target")
		var positions := []
		for k in Game.run.explore.spots.size():
			var pos: Vector3 = main._screen.world._spots[k].pos
			check(not pos in positions, "Independent objectives or normal loot physically overlapped")
			check(main._screen.world.nearest(pos) == k, "Physical E proximity cannot reach a retained target")
			positions.append(pos)
			if Game.run.explore.spots[k].get("neighbor", "") == "account": has_neighbor = true
		check(has_neighbor, "Mainline special target swallowed the existing neighbor account")
		Game.run.explore.caught = true
		main._screen.world.sync(Game.run)
		for k in Game.run.explore.spots.size():
			if Game.run.explore.spots[k].has("mainline"):
				var tag: String = main._screen.world._spots[k].label.text
				check(not tag.contains("已调查") and not tag.contains("已封阵"), "Capture fabricated a completed investigation or ritual label")
		Game.run.explore.caught = false
		main._screen.world.sync(Game.run)
		var player_pos: Vector3 = main._screen.player.position
		var camera_dist: float = main._screen.rig.dist
		main._screen.player.position = Vector3(0, 0, -0.7)
		main._screen.rig.dist = 20.0
		main._screen.rig.snap()
		await snapshot("six-targets", main._screen)
		main._screen.player.position = player_pos
		main._screen.rig.dist = camera_dist
		main._screen.rig.snap()
	await search_objective(kind)
	if save_return: await snapshot("investigating", main._screen)
	await advance_work(19)
	check(not bool(Mainline.state(Game.run).evidence[kind]), "Evidence became real before investigation and return completed")
	await advance_work(1)
	check(not Post.is_busy(Game.run) and not bool(Mainline.state(Game.run).evidence[kind]), "Investigation did not produce carried-only evidence")
	await click(meta_button("mainline_return", true))
	check(Post.is_busy(Game.run) and not bool(Mainline.state(Game.run).evidence[kind]), "Clicking return granted evidence without actual 60-minute travel")
	await advance_work(59)
	if save_return:
		Game.save_game()
		Game.run = {}
		Game.continue_game()
		await frames(7)
		check(Post.is_busy(Game.run) and not Mainline.state(Game.run).evidence.mortuary, "Save/load skipped the last minute of real return")
	await advance_work(1)
	check(bool(Mainline.state(Game.run).evidence[kind]) and Game.run.explore.is_empty() and Game.screen == "post", "Completed return failed to register real evidence at home")

func reach_routes(disrupt := false) -> void:
	await fresh()
	await open_story(true)
	check(labels_in(modal()).contains("期限") and labels_in(modal()).contains("旧世残卷"), "Deadline or current-life evidence boundary missing from panel")
	var water := Inv.count(Game.run.home, "water")
	var firewood := Inv.count(Game.run.home, "firewood")
	await choose("host", true)
	check(Post.is_busy(Game.run) and modal() == null and not main.has_modal("journal"), "Hosting did not close pause layers and start actual work")
	check(Inv.count(Game.run.home, "water") == water - 1 and Inv.count(Game.run.home, "firewood") == firewood - 1, "Fast double click did not pay exactly one displayed hospitality cost")
	await advance_work(30)
	check(Mainline.state(Game.run).stage == "mortuary", "Completed hospitality did not open mortuary investigation")
	await investigate("mortuary", 6, disrupt)
	await choose("disrupt" if disrupt else "copy")
	await advance_work(60 if disrupt else 30)
	check(Mainline.state(Game.run).stage == "temple", "Completed evidence handling did not open temple investigation")
	await investigate("temple", 8)
	check(Mainline.state(Game.run).stage == "routes", "Actual temple maps did not open routes")
	await set_time(12)
	await open_story()

func finish_dawn() -> void:
	await close_modals()
	await set_time(20, 1440)
	Game.run.dawn_due = true
	Game.run.report = {"day": 20, "night": [], "help": [], "settle": {"lines": [], "total": 0, "merit": 0}}
	Game.refresh()
	await frames(7)
	await click(prefix_button("翻过这一页"))
	check(Game.screen == "ending" and Game.run.phase == "ending", "Actual dawn acknowledgement did not open resolved ending")

func finish() -> void:
	Game.no_save = true
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Mainline fixture cleanup failed")
	main.queue_free()
	await frames(4)
	print("Mainline UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://mainline-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://mainline-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://mainline-ui-Memory-%d.md" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.speed = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(170).timeout.connect(func(): get_tree().quit(1))
	Game.no_save = false
	# Rejection and visible alternative, with no inherited-proof shortcut.
	await fresh()
	await open_story()
	await snapshot("contact")
	await click(meta_button("mainline_map", true, modal()))
	check(main.has_modal("explore_pick") and meta_button("explore_depart", "taoist_temple", main._modals.explore_pick).disabled, "Unopened temple was hidden or incorrectly allowed departure")
	check(labels_in(main._modals.explore_pick).contains("尚未找到进山路线"), "Locked map destination omitted its visible investigation prerequisite")
	await snapshot("map", main._modals.explore_pick)
	await open_story()
	await choose("refuse")
	await close_modals()
	await set_time(5)
	await open_story()
	check(meta_button("mainline_action", "self_route", modal()) != null, "Rejected Taoist left no usable self-investigation route")
	var original: Dictionary = Game.run.home.duplicate(true)
	Game.run.home = {}
	Game.refresh()
	await frames()
	var blocked := meta_button("mainline_action", "self_route", modal())
	check(blocked.disabled and labels_in(modal()).contains(blocked.tooltip_text), "Missing supplies did not show direct local blocker")
	Game.run.home = original
	Game.refresh()
	await frames()
	await choose("self_route")
	await advance_work(60)
	check(Mainline.state(Game.run).stage == "mortuary", "Independent investigation did not actually open mortuary")
	# Full physical investigation, capacity to change waves, save/load and rewind.
	await reach_routes(true)
	await snapshot("routes")
	check(int(Mainline.state(Game.run).interventions.disrupt_t) >= 0, "Disruption never became a real completed intervention")
	var before_route: Dictionary = Game.run.duplicate(true)
	Game.snapshots[str(int(Game.run.pday))] = before_route.duplicate(true)
	await choose("prepare_escape")
	await advance_work(90)
	check(Mainline.state(Game.run).route == "escape", "Completed preparation did not lock escape route")
	Game.run.pday += 1
	Game.run.t = (int(Game.run.pday) - 1) * 1440 + 240
	Game.rewind()
	await frames(7)
	check(Mainline.state(Game.run).route == "" and Mainline.state(Game.run).stage == "routes", "Rewind retained a route that had not happened in the restored page")
	await open_story()
	await choose("hold")
	await finish_dawn()
	check(Mainline.ending(Game.run).kind == "hold" and prefix_button("守 下 去") != null, "Hold ending lost continue-living option")
	await snapshot("hold", main._screen)
	await click(prefix_button("守 下 去"), true)
	check(Game.run.endless and Game.run.phase == "post", "Hold continuation failed or stale double click broke the new day")
	# Early exit is an actual work completion, with no twenty-day bonus.
	await reach_routes()
	await choose("prepare_escape")
	await advance_work(90)
	await set_time(18)
	await open_story()
	await choose("escape", true)
	await advance_work(119)
	check(Game.run.phase == "post", "Escape ended the life before 120-minute travel finished")
	await advance_work(1)
	check(Game.screen == "ending" and Mainline.ending(Game.run).kind == "escape" and Ledger.ending_bonus(Game.run) == 0, "Early escape ending or bonus boundary incorrect")
	check(prefix_button("守 下 去") == null and labels_in(main._screen).contains("道心 +0"), "Escape UI offered invalid continuation or wrong ending reward")
	await snapshot("escape", main._screen)
	await click(prefix_button("合 上"), true)
	check(Game.run.is_empty() and Game.screen == "title" and FileAccess.file_exists(Game.memory_path), "Actual ending close failed to archive Memory or return title")
	var memory := FileAccess.get_file_as_string(Game.memory_path)
	check(memory.contains("离城余生"), "Written prior-life Memory omitted actual early escape ending")
	# Ritual requires physical on-site work, then surviving the final dawn.
	await reach_routes()
	await choose("prepare_ritual")
	await advance_work(120)
	await set_time(18)
	await open_story()
	await click(meta_button("mainline_depart", "taoist_temple", modal()))
	await search_objective("ritual")
	await advance_work(89)
	check(int(Mainline.state(Game.run).interventions.ritual_t) < 0, "Ritual altered the wave before real on-site completion")
	await advance_work(1)
	check(int(Mainline.state(Game.run).interventions.ritual_t) >= 0, "Completed on-site ritual did not extinguish the lamps")
	var return_before := int(Game.run.t)
	await click(meta_button("mainline_return", true))
	if Post.is_busy(Game.run): await advance_work(60)
	else: check(int(Game.run.t) == return_before + 60, "Returning from completed ritual did not consume the actual journey")
	await finish_dawn()
	check(Mainline.ending(Game.run).kind == "ritual" and Ledger.ending_bonus(Game.run) == 10 and prefix_button("守 下 去") == null, "Ritual ending, reward or continuation boundary incorrect")
	await snapshot("ritual", main._screen)
	await click(prefix_button("合 上"), true)
	check(FileAccess.get_file_as_string(Game.memory_path).contains("七灯俱熄"), "Actual Memory close omitted completed ritual ending")
	await finish()
