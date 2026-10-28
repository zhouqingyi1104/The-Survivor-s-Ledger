extends Node
## Rendered 1280x720 mouse acceptance for applied openings, not a full-life balance test.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Opening = preload("res://scripts/core/opening.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Inv = preload("res://scripts/core/inv.gd")
var main: Control
var checks := 0
var failures := 0
const ROLES := ["scholar", "escort", "herbalist", "watchman"]
const OLD := {"scholar": "scholar_lamps", "escort": "escort_oldroad", "herbalist": "herbalist_oldcase", "watchman": "watchman_oldledger"}

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		get_tree().quit(1)
	return ok

func frames(n := 6) -> void:
	for k in n: await get_tree().process_frame

func labels_in(node: Node) -> String:
	var out := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): out.append(label.text)
	return "\n".join(out)

func button_meta(key: String, value, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.has_meta(key) and button.get_meta(key) == value: return button
	return null

func text_button(text: String, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text == text: return button
	return null

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Missing enabled opening mouse target"): return
	DisplayServer.window_move_to_foreground()
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await frames(2)
		ancestor = ancestor.get_parent()
	var point := button.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(point), "Opening mouse target lies outside viewport")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await frames(2)
	for k in (2 if twice else 1):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		get_viewport().push_input(press)
		await frames(1)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = point
		get_viewport().push_input(release)
	await frames(8)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames()

func archived_meta() -> Dictionary:
	var meta := State.new_meta()
	for kind in ["ritual", "escape"]:
		var run := State.new_run("escort", meta, 741 + int(meta.runs))
		Pre.start_disaster(run)
		run.phase = "ending"
		run.pday = 18 if kind == "escape" else 20
		run.t = 17 * 1440 + 300 if kind == "escape" else 20 * 1440
		var story := Mainline.state(run)
		story.stage = "closed"
		story.route = kind
		story.evidence = {"mortuary": true, "temple": true}
		story.interventions = {"disrupt_t": -1, "ritual_t": 18 * 1440 if kind == "ritual" else -1}
		story.ending = {"kind": kind, "title": "离城余生" if kind == "escape" else "七灯俱熄", "text": "窗口验收结构化旧世样本。", "bonus": 0 if kind == "escape" else 10, "can_continue": false}
		if kind == "ritual":
			Past.record(run, "ning", "medicine", "曾把药交给邻人。", 1)
			Trade.state(run).actors.zhou.breaches = 1
			Trade.state(run).actors.zhou.breach_total = 1
			var crisis := Crisis.state(run)
			crisis.completed = [{"id": "ui-real-crisis", "kind": "well_freeze", "actor": "ning", "stage": "resolved", "warning_day": 2, "impact_t": 3 * 1440 + 720, "end_t": 5 * 1440 + 120, "investigated": true, "confirmed": "real", "response": "prepare", "protected": true, "outcome": "averted"}]
		check(Past.archive(run, meta), "Structured old-life UI fixture failed archival")
	meta.deaths = 1
	check(Past.opening_inheritance(meta).size() == 6, "UI fixture did not produce six real archived opening sources")
	return meta

func setup_challenge(role: String, rich := false) -> void:
	await close_modals()
	Game.run = {}
	Game.snapshots = {}
	Game.meta = archived_meta() if rich else State.new_meta()
	Game.meta.deaths = 1
	Game.pending_opening_setup = {}
	Game.pending_role = role
	Game.pending_difficulty = "normal"
	Game.go("challenge")
	await frames(8)
	check(main._screen.find_child("OpeningChoiceScroll", true, false) != null, "Opening choices omitted from scroll")
	check(button_meta("opening_choice", "plain").text.begins_with("■"), "Normal entry did not default to plain")
	check(button_meta("opening_choice", OLD[role]).disabled == not rich, "Legacy opening lock does not match real archive")
	for suffix in ["stock", "neighbors"]: check(not button_meta("opening_choice", role + "_" + suffix).disabled, "Base identity opening unexpectedly locked")
	check(button_meta("opening_choice", "cash_account").disabled == not rich, "Prior breach opening lock has wrong reason")
	check(button_meta("opening_choice", "old_crisis").disabled == not rich, "Prior real crisis opening lock has wrong reason")

func assert_applied(role: String, id: String, vows: Array = []) -> void:
	check(Game.screen == "pre" and Game.run.phase == "pre" and Game.run.role == role, "Actual start did not enter selected role's preparation")
	var view := Opening.view(Game.run)
	check(Game.run.opening.choice == id and Game.run.opening.applied, "Actual start applied a different opening")
	var baseline := State.new_run(role, Game.meta, int(Game.run.seed), "normal", [], [], vows)
	var fx: Dictionary = view.effects
	check(int(Game.run.silver) == int(baseline.silver) - int(fx.silver_cost), "Opening coin cost differs from visible applied effect")
	check(int(Game.run.hour) == State.OPEN_HOUR + int(fx.hours), "Opening preparation time differs from visible applied effect")
	var expected: Dictionary = baseline.home.duplicate(true)
	for item in fx.spent: Inv.add(expected, item, -int(fx.spent[item]))
	for item in fx.gained: Inv.add(expected, item, int(fx.gained[item]))
	check(Game.run.home == expected, "Actual opening inventory does not match paid/gained items")
	for actor in fx.contacts:
		var person := Trade.contact(Game.run, actor)
		check(person.trust == int(fx.contacts[actor].trust) and person.favors == int(fx.contacts[actor].favors), "Actual this-life relation/favor does not match choice")
	check(Game.pending_role == "", "Successful start left a repeatable pending role")

func snapshot(name: String, node: Node = null) -> void:
	await frames(6)
	if node == null: node = main._screen
	var viewport := get_viewport().get_visible_rect()
	if node == main._screen and Game.screen == "challenge":
		for label in node.find_children("*", "Label", true, false):
			if label.text == "立什么愿，带什么家伙": check(viewport.encloses(label.get_global_rect()), "Opening fixed header clips outside 1280x720: " + str(label.get_global_rect()))
	for button in node.find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= viewport.end.x + 1, "Opening button extends outside 1280 viewport width")
	for panel in node.find_children("*", "PanelContainer", true, false):
		var ancestor: Node = panel.get_parent()
		var scrolling := false
		while ancestor != null:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling: check(viewport.encloses(panel.get_global_rect()), "Opening outer panel extends outside 1280x720")
	RenderingServer.force_draw()
	var path := OS.get_environment("TEMP").path_join("ledger-opening-" + name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Opening screenshot could not save")
	print("Opening UI screenshot: ", path)

func test_options(role: String) -> void:
	await setup_challenge(role)
	check(labels_in(main._screen).contains("只选一项") and labels_in(main._screen).contains(button_meta("opening_choice", OLD[role]).tooltip_text) and button_meta("opening_choice", OLD[role]).tooltip_text != "", "Opening screen omitted purpose or actual legacy lock reason")
	if role == "scholar": await snapshot("locked")
	for id in [role + "_stock", role + "_neighbors", OLD[role]]:
		await setup_challenge(role, true)
		await click(button_meta("opening_choice", id))
		if not button_meta("opening_choice", id).text.begins_with("■"):
			print("Unselected opening mouse: role=", role, " id=", id, " ui_pick=", main._screen._opening_id, " pending=", Game.pending_role, " block=", button_meta("opening_choice", id).tooltip_text, " mouse=", get_viewport().get_mouse_position())
		check(button_meta("opening_choice", id).text.begins_with("■") and not button_meta("opening_choice", "plain").text.begins_with("■"), "Opening single-select did not replace plain")
		if id == "herbalist_oldcase": await snapshot("legacy")
		await click(button_meta("opening_start", "selected"), true)
		assert_applied(role, id)
		check(main._modals.is_empty(), "Starting double-click triggered an unrelated preparation action")
		if id == "herbalist_neighbors":
			await click(button_meta("opening_entry", "pre"))
			var modal: Node = main._modals.get("opening")
			check(modal != null and labels_in(modal).contains(str(Opening.view(Game.run).title)), "Preparation opening entry did not show immutable applied facts")
			await snapshot("detail", modal)
			await close_modals()
			await click(text_button("劫余录", main._screen.hud))
			await click(button_meta("opening_entry", "journal", main._modals.get("journal")))
			check(main.has_modal("opening") and not main.has_modal("journal"), "Journal opening entry did not reveal details")
			await close_modals()

func test_constraints() -> void:
	await setup_challenge("scholar", true)
	await click(button_meta("opening_choice", "scholar_stock"))
	await click(button_meta("challenge_choice", "extra_oil"))
	await click(button_meta("opening_mode", "endless"))
	await click(button_meta("opening_start", "plain"))
	assert_applied("scholar", "plain")
	check(Game.run.endless and Game.run.tally.boons.is_empty() and Game.run.tally.vows.is_empty(), "Plain skip lost mode or retained challenge choices")
	await setup_challenge("escort", true)
	await click(button_meta("opening_choice", "escort_oldroad"))
	await click(button_meta("opening_mode", "daily"))
	check(button_meta("opening_choice", "plain").text.begins_with("■"), "Daily switch retained a private old-life selection")
	for id in ["escort_stock", "escort_neighbors", "escort_oldroad", "cash_account", "old_crisis"]: check(button_meta("opening_choice", id).disabled, "Daily allowed nonplain opening")
	check(labels_in(main._screen).contains("每日"), "Daily lock is not explained")
	await snapshot("daily")
	await click(button_meta("opening_start", "selected"))
	assert_applied("escort", "plain")
	check(Past.daily(Game.run) and Game.run.opening.inherited.is_empty(), "Daily birth retained private opening sources")
	await setup_challenge("herbalist", true)
	await click(button_meta("opening_choice", "herbalist_oldcase"))
	await click(button_meta("challenge_choice", "bare"))
	check(button_meta("opening_choice", "plain").text.begins_with("■") and button_meta("opening_choice", "herbalist_stock").disabled, "Bare vow did not suppress item-granting opening")
	await click(button_meta("opening_start", "selected"))
	assert_applied("herbalist", "plain", ["bare"])
	check(Game.run.home.is_empty() and "bare" in Game.run.tally.vows, "Bare opening acquired items or dropped vow")
	for id in ["cash_account", "old_crisis"]:
		await setup_challenge("watchman", true)
		await click(button_meta("opening_choice", id))
		await click(button_meta("opening_start", "selected"))
		assert_applied("watchman", id)

func ending_fixture(dead: bool) -> void:
	Pre.start_disaster(Game.run)
	Game.run.pending_event = ""
	Game.run.phase = "dead" if dead else "ending"
	Game.run.death_cause = "窗口验收的本世死亡样本。"
	if not dead:
		Game.run.pday = 21
		Game.run.t = 20 * 1440
		var story := Mainline.state(Game.run)
		story.stage = "closed"
		story.route = "hold"
		story.ending = {"kind": "hold", "title": "劫 满", "text": "窗口验收已结束本世。", "bonus": 10, "can_continue": true}
	Game.go("dead" if dead else "ending")
	await frames(8)

func test_next_life() -> void:
	for dead in [false, true]:
		await setup_challenge("herbalist", true)
		await click(button_meta("opening_choice", "herbalist_oldcase"))
		await click(button_meta("opening_mode", "endless"))
		await click(button_meta("opening_start", "selected"))
		Game.run.companions = ["carpenter"]
		await ending_fixture(dead)
		check(labels_in(main._screen).contains("沿用今世开局"), "Restart did not disclose preserved opening")
		var next_button := button_meta("opening_next", true)
		var stale_next: Callable = next_button.pressed.get_connections()[0].callable
		var stale_restart: Callable = text_button("重新来过" if dead else "重 走").pressed.get_connections()[0].callable
		await snapshot("dead" if dead else "ending")
		var old_count := int(Past.book(Game.meta).count)
		await click(next_button, true)
		check(Game.screen == "challenge" and Game.run.is_empty() and Past.book(Game.meta).count == old_count + 1, "Choose next opening failed once-only settlement/navigation")
		check(main._screen._endless and main._screen._mates == ["carpenter"] and Game.pending_opening_setup.is_empty(), "Next-opening mode and housemates were not restored once")
		check(button_meta("opening_choice", "plain").text.begins_with("■"), "Next-opening screen silently reselected old opening")
		await click(button_meta("opening_choice", "herbalist_stock"))
		await click(button_meta("opening_start", "selected"))
		var after := Game.run.duplicate(true)
		stale_next.call()
		stale_restart.call()
		await frames()
		check(Game.run == after and Game.screen == "pre", "Prior-life ending callback changed new life")
		await ending_fixture(dead)
		await click(text_button("重新来过" if dead else "重 走"), true)
		check(Game.screen == "pre" and Game.run.opening.choice == "herbalist_stock", "Original restart did not preserve chosen opening")

func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://opening-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://opening-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://opening-ui-Memory-%d.md" % OS.get_process_id()
	Game.speed = 0
	Game.meta = State.new_meta()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(240).timeout.connect(func(): get_tree().quit(1))
	if "--layout-only" in OS.get_cmdline_user_args():
		await setup_challenge("escort", true)
		await click(button_meta("opening_mode", "daily"))
		await snapshot("daily")
	else:
		for role in ROLES:
			print("Opening UI role: ", role)
			await test_options(role)
		await test_constraints()
		await test_next_life()
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Opening fixture cleanup failed")
	main.queue_free()
	await frames(4)
	print("Opening UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
