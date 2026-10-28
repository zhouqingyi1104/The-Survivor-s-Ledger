extends Node
## Mouse coverage for the identity surface. Mainline proof/wave rules have their
## own joint tests; these fixtures begin at their already-verified decision gate.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Data = preload("res://scripts/core/data.gd")
var main: Control
var checks := 0
var failures := 0
const BASE := {"scholar": "scholar_collate", "escort": "escort_intercept", "herbalist": "herbalist_lure", "watchman": "watchman_lane"}
const LEGACY := {"scholar": "scholar_diagram", "escort": "escort_convoy", "herbalist": "herbalist_ink", "watchman": "watchman_intel"}
const MINUTES := {"scholar_collate": 90, "escort_intercept": 90, "herbalist_lure": 60, "watchman_lane": 60, "scholar_diagram": 120, "escort_convoy": 120, "herbalist_ink": 90, "watchman_intel": 90}

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		get_tree().quit(1)
	return ok

func frames(n := 6) -> void:
	for k in n: await get_tree().process_frame

func modal() -> Node:
	return main._modals.get("identity")

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
	if not check(button != null and not button.disabled, "Missing enabled identity mouse target"): return
	DisplayServer.window_move_to_foreground()
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await frames(2)
		ancestor = ancestor.get_parent()
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames(2)
	for k in (2 if twice else 1):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		Input.parse_input_event(press)
		await frames(1)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = point
		Input.parse_input_event(release)
	await frames(8)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames()

func archive_fixture() -> Dictionary:
	var meta := State.new_meta()
	# Structured archival fixtures: never parse free text or write player Memory.
	for kind in ["ritual", "escape"]:
		var run := State.new_run("escort", meta, 710 + int(meta.runs))
		Pre.start_disaster(run)
		run.phase = "ending"
		run.pday = 18 if kind == "escape" else 20
		run.t = 17 * 1440 + 300 if kind == "escape" else 20 * 1440
		var story := Mainline.state(run)
		story.stage = "closed"
		story.route = kind
		story.evidence = {"mortuary": true, "temple": true}
		story.interventions = {"disrupt_t": -1, "ritual_t": 18 * 1440 if kind == "ritual" else -1}
		story.ending = {"kind": kind, "title": "离城余生" if kind == "escape" else "七灯俱熄", "text": "窗口专属解法的结构化旧世样本。", "bonus": 0 if kind == "escape" else 10, "can_continue": false}
		if kind == "ritual": Past.record(run, "ning", "medicine", "曾把药交给邻人。", 1)
		check(Past.archive(run, meta), "Structured old-life fixture did not archive")
	meta.deaths = 1
	return meta

func fresh(role: String, legacy := false, daily := false) -> void:
	await close_modals()
	Game.meta = archive_fixture() if legacy else State.new_meta()
	Game.meta.deaths = 1
	Game.run = State.new_run(role, Game.meta, 8172)
	if daily: Game.run.flags.daily = "2026-10-24"
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Game.run.home = {"rice": 30, "water": 30, "firewood": 30, "wood": 30, "nails": 20, "talisman": 20, "talisman_paper": 20, "lamp_oil": 20, "dog_blood": 20, "cinnabar": 20, "mugwort": 30, "plague_powder": 10, "caltrops": 10}
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Past.state(Game.run).schedule = []
	Crisis.state(Game.run).next_warning_day = 100
	Npc.state(Game.run)
	var story := Mainline.state(Game.run)
	story.stage = "mortuary_choice"
	story.evidence = {"mortuary": true, "temple": false}
	Game.run.pday = 8
	Game.run.t = 7 * 1440 + 240
	Post.trade_refresh(Game.run)
	for attr in ["food", "water", "mood", "energy", "warmth"]: Game.run.attrs[attr] = 100
	Game.go("post")
	await frames(8)

func open_identity(from_journal := false) -> void:
	await close_modals()
	if from_journal:
		var journal: Button
		for button in main._screen.hud.find_children("*", "Button", true, false):
			if button.tooltip_text == "劫余录": journal = button; break
		await click(journal)
		await click(meta_button("identity_entry", "journal", main._modals.get("journal")))
	else:
		await click(meta_button("mainline_entry", true))
		if not main.has_modal("mainline"):
			print("Missing story after actual mouse: screen=", Game.screen, " modals=", main._modals.keys(), " role=", Game.run.role, " busy=", Game.run.busy, " pointer=", get_viewport().get_mouse_position())
			await snapshot("missing-story", main._screen)
		await click(meta_button("identity_entry", "mainline", main._modals.get("mainline")))
	check(modal() != null, "Identity entry failed to open actual modal")

func advance_work(minutes: int) -> void:
	var before := int(Game.run.t)
	Game.act(func(): Post.advance(Game.run, minutes); return "")
	await frames(8)
	check(int(Game.run.t) == before + minutes, "Identity work clock unexpectedly stopped")

func snapshot(name: String, target: Node = null) -> void:
	await frames(6)
	if main._toasts.get_child_count() > 0: await get_tree().create_timer(2.9).timeout
	if target == null: target = modal() if modal() != null else main._screen
	var viewport := get_viewport().get_visible_rect()
	for panel in target.find_children("*", "PanelContainer", true, false):
		var ancestor: Node = panel.get_parent()
		var scrolling := false
		while ancestor != null:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling: check(viewport.encloses(panel.get_global_rect()), "Identity outer panel exceeded 1280x720")
	for button in target.find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= viewport.end.x, "Identity mouse target exceeded viewport width")
	if modal() != null:
		var scroll: ScrollContainer = modal().find_child("IdentityDetailsScroll", true, false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "Identity details do not scroll")
	DisplayServer.window_move_to_foreground()
	RenderingServer.force_draw()
	var path := OS.get_environment("TEMP").path_join("ledger-identity-" + name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Identity screenshot failed")
	print("Identity UI frame: ", path)

func craft_recipe(id: String, output: String, output_count: int) -> void:
	await close_modals()
	Dialogs.build()
	await frames()
	var button := meta_button("identity_craft", id, main._modals.get("build"))
	check(button != null and not button.disabled and button.text.contains("60 分钟") and button.text.contains("精力 6"), "Learned identity recipe lacks real cost or enabled craft target")
	if id == "scribe_talisman":
		var scroll: ScrollContainer = main._modals.get("build").find_children("*", "ScrollContainer", true, false)[0]
		scroll.ensure_control_visible(button)
		await snapshot("craft", main._modals.get("build"))
	var before := Inv.count(Game.run.home, output)
	await click(button, true)
	check(Post.is_busy(Game.run) and not main.has_modal("build"), "Identity craft did not start actual work or close pause layer")
	await advance_work(59)
	check(Inv.count(Game.run.home, output) == before, "Craft produced output before actual completion")
	await advance_work(1)
	check(Inv.count(Game.run.home, output) == before + output_count, "Identity craft produced wrong amount or double-click duplicated work")

func test_base(role: String) -> void:
	await fresh(role)
	await open_identity(role == "scholar")
	var base := meta_button("identity_action", BASE[role], modal())
	var old := meta_button("identity_action", LEGACY[role], modal())
	check(base != null and not base.disabled and old != null and old.disabled, "Base and previous-life requirements did not differ for " + role)
	check(labels_in(modal()).contains("行动与代价") and labels_in(modal()).contains("这一世还得亲自做"), "Identity costs or evidence boundary invisible")
	if role == "scholar":
		await snapshot("locked")
		var paper := Inv.count(Game.run.home, "talisman_paper")
		Game.run.home.talisman_paper = 0
		Game.refresh()
		await frames()
		check(meta_button("identity_action", BASE[role], modal()).disabled and labels_in(modal()).contains("材料"), "Insufficient materials did not show an explicit disabled choice")
		Game.run.home.talisman_paper = paper
		Game.refresh()
		await frames()
	var hp := int(Game.run.attrs.hp)
	var chosen: String = BASE[role]
	await click(meta_button("identity_action", chosen, modal()), true)
	check(Post.is_busy(Game.run) and modal() == null and not main.has_modal("mainline") and not main.has_modal("journal"), "Identity choice left time paused behind a modal")
	check(Identity.state(Game.run).completed_t < 0, "Identity expertise granted before actual work")
	if role == "escort": check(int(Game.run.attrs.hp) == hp - 12, "Interception did not pay its displayed health cost once")
	if role == "scholar":
		await snapshot("working", main._screen)
		await open_identity()
		check(labels_in(modal()).contains("还要 90 分钟") and meta_button("identity_action", chosen, modal()).disabled, "Ongoing identity work has no accurate remaining time or allows duplicate start")
		await close_modals()
	await advance_work(int(MINUTES[chosen]) - 1)
	check(Identity.state(Game.run).completed_t < 0, "Identity solution completed one minute early")
	await advance_work(1)
	check(int(Identity.state(Game.run).completed_t) >= 0 and Mainline.state(Game.run).stage == "temple", "Completed identity solution did not progress the actual mainline")
	await open_identity()
	check(meta_button("identity_action", BASE[role], modal()).disabled and meta_button("identity_action", LEGACY[role], modal()).disabled, "Mutually exclusive solution remained repeatable")
	check(not Identity.view(Game.run).history.is_empty(), "Completed choice absent from visible history")
	if role == "scholar": await craft_recipe("scribe_talisman", "talisman", 2)
	if role == "herbalist": await craft_recipe("efficient_plague", "plague_powder", 1)

func test_legacy(role: String) -> void:
	await fresh(role, true)
	await open_identity()
	check(not meta_button("identity_action", LEGACY[role], modal()).disabled and labels_in(modal()).contains("第 1 世"), "Real archived experience did not unlock or identify source for " + role)
	var old_callback: Callable = meta_button("identity_action", LEGACY[role], modal()).pressed.get_connections()[0].callable
	if role == "scholar": await snapshot("legacy")
	await click(meta_button("identity_action", LEGACY[role], modal()), true)
	await advance_work(int(MINUTES[LEGACY[role]]))
	check(int(Identity.state(Game.run).completed_t) >= 0, "Legacy choice failed to finish actual work")
	if role == "herbalist": await craft_recipe("medicinal_talisman", "talisman", 1)
	if role == "watchman":
		await open_identity()
		var text := labels_in(modal())
		check(text.contains("第 11 夜") and text.contains("第 17 夜") and text.contains("第 20 夜"), "Unlocked intelligence did not display actual future nights")
		var scroll: ScrollContainer = modal().find_child("IdentityDetailsScroll", true, false)
		scroll.ensure_control_visible(modal().find_child("IdentityIntel", true, false))
		await snapshot("intel")
	await fresh(role, true)
	var before := Game.run.duplicate(true)
	old_callback.call()
	await frames()
	check(Game.run == before, "Previous-life UI callback applied a choice to the new life")

func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://identity-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://identity-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://identity-ui-Memory-%d.md" % OS.get_process_id()
	Game.meta = archive_fixture()
	Game.speed = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	Game.go("roles")
	await frames(8)
	for role in BASE: check(meta_button("identity_role", role) != null, "Role screen omitted a playable identity")
	check(labels_in(main._screen).contains("身份解法") and labels_in(main._screen).contains("前世经验"), "Role cards did not preview identity and legacy routes")
	await snapshot("roles", main._screen)
	for role in BASE: await test_base(role)
	for role in LEGACY: await test_legacy(role)
	await fresh("scholar", true, true)
	await open_identity()
	check(not meta_button("identity_action", BASE.scholar, modal()).disabled and meta_button("identity_action", LEGACY.scholar, modal()).disabled, "Daily mode failed to preserve base identity while rejecting old-life advantage")
	check(labels_in(modal()).contains("每日"), "Daily old-life restriction has no visible reason")
	await snapshot("daily")
	await close_modals()
	Dialogs.past_lives()
	await frames()
	await click(meta_button("identity_entry", "past_lives", main._modals.get("past_lives")))
	check(modal() != null and not main.has_modal("past_lives"), "Past-life page failed to reveal the identity route surface")
	await click(meta_button("identity_story", true, modal()))
	check(main.has_modal("mainline") and modal() == null, "Identity panel failed to return to live investigation goals")
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Identity fixture cleanup failed")
	main.queue_free()
	await frames(4)
	print("Identity UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
