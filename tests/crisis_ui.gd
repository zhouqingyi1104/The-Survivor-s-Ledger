extends Node
## Rendered local crisis loop. Never reads or writes the player's save/meta/Memory.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
var main: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func frames(count := 5) -> void:
	for k in count: await get_tree().process_frame

func labels_in(parent: Node) -> String:
	var lines := PackedStringArray()
	for label in parent.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func modal() -> Node:
	return main._modals.get("crisis")

func action_button(action: String) -> Button:
	if modal() == null: return null
	for button in modal().find_children("*", "Button", true, false):
		if button.get_meta("crisis_action", "") == action: return button
	return null

func hud_entry() -> Button:
	for button in main._screen.hud.find_children("*", "Button", true, false):
		if button.get_meta("crisis_entry", false): return button
	return null

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Missing enabled crisis UI button"): return
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
	await frames(6)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames()

func fresh(kind: String, real: bool, actor := "ning", publish := true) -> void:
	await close_modals()
	Game.run = State.new_run("escort", Game.meta, 4242)
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Game.run.home = {"rice": 30, "wood": 20, "nails": 20, "firewood": 20, "water": 30, "mugwort": 20, "flatbread": 10}
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	check(Crisis.propose(Game.run, {"kind": kind, "actor": actor, "warning_day": 2, "real": real}, 1), "Fixture proposal was not accepted")
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	if publish: Post.crisis_refresh(Game.run)
	Game.go("post")
	Game.refresh()
	await frames(8)
	check(Crisis.view(Game.run).get("kind", "") == (kind if publish else ""), "Warning publication state did not match fixture")

func open_journal() -> void:
	await close_modals()
	var journal_button: Button
	for button in main._screen.hud.find_children("*", "Button", true, false):
		if button.tooltip_text == "劫余录": journal_button = button; break
	await click(journal_button)
	var entry: Button
	if main.has_modal("journal"):
		for button in main._modals.journal.find_children("*", "Button", true, false):
			if button.text.begins_with("风声与危机"): entry = button; break
	await click(entry)
	check(modal() != null, "Actual journal crisis entry failed")

func complete_work(minutes: int) -> void:
	var before := int(Game.run.t)
	main._screen.advance(minutes)
	await frames(7)
	check(int(Game.run.t) == before + minutes and Game.run.busy.is_empty(), "Real game clock failed to complete crisis work")

func snapshot(name: String, with_modal := true) -> void:
	await frames(7)
	var viewport := get_viewport().get_visible_rect()
	var card: Control = main._screen.hud.find_child("CrisisHUDCard", true, false)
	if check(card != null, "Crisis HUD card missing"):
		check(viewport.encloses(card.get_global_rect()), "Crisis HUD card exceeded 1280x720")
		for panel in main._screen.hud.find_children("*", "PanelContainer", true, false):
			if panel == card or card.is_ancestor_of(panel): continue
			check(not card.get_global_rect().intersects(panel.get_global_rect()), "Crisis HUD obscures an existing task/clock/status panel")
	if with_modal and check(modal() != null, "Crisis detail modal missing"):
		for panel in modal().find_children("*", "PanelContainer", true, false):
			var ancestor: Node = panel.get_parent()
			var scrolling := false
			while ancestor != null:
				if ancestor is ScrollContainer: scrolling = true
				ancestor = ancestor.get_parent()
			if not scrolling: check(viewport.encloses(panel.get_global_rect()), "Crisis outer panel exceeded viewport")
		for button in modal().find_children("*", "Button", true, false):
			var rect: Rect2 = button.get_global_rect()
			check(rect.position.x >= 0 and rect.end.x <= viewport.end.x, "Crisis action exceeded horizontal viewport")
		var scroll: ScrollContainer = modal().find_child("CrisisDetailsScroll", true, false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "Crisis detail did not provide usable scrolling")
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Crisis screenshot failed")
	print("Crisis UI frame: ", path)

func finish() -> void:
	Game.no_save = true
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Crisis fixture cleanup failed")
	main.queue_free()
	await frames(4)
	print("Crisis UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://crisis-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://crisis-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://crisis-ui-Memory-%d.md" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.speed = 0
	Game.snapshots = {}
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(75).timeout.connect(func(): get_tree().quit(1))
	Game.no_save = false
	await fresh("well_freeze", true, "ning", false)
	check(main._screen.hud.find_child("CrisisHUDCard", true, false) == null, "Unpublished crisis appeared on HUD")
	# Poll at 08:00 then advance to 08:01: no random-event or hourly refresh can rescue a missing card.
	main._screen.advance(1)
	await frames(7)
	check(Game.run.pending_event == "" and main._screen.hud.find_child("CrisisHUDCard", true, false) != null, "First warning failed to build its HUD without a random event")
	await snapshot("ledger-crisis-hud", false)
	await click(hud_entry())
	if not check(modal() != null, "HUD crisis button failed to open detail"):
		await finish()
		return
	var initial := Crisis.view(Game.run)
	check(initial.confirmed == "unknown" and str(initial.evidence) == "", "UI leaked uninvestigated truth")
	check(labels_in(modal()).contains("还没查到证据") and labels_in(modal()).contains("线索来源"), "Unknown truth or source missing in panel")
	for action in ["investigate", "prepare", "aid", "ignore", "emergency"]:
		check(action_button(action) != null, "Missing crisis action: " + action)
	check(labels_in(modal()).contains("30") and labels_in(modal()).contains("精力"), "Investigation cost/time was hidden")
	var original_home: Dictionary = Game.run.home.duplicate(true)
	Game.run.home = {}
	Game.refresh()
	await frames()
	check(action_button("prepare").disabled and action_button("prepare").tooltip_text != "", "Missing materials did not disable preparation")
	check(labels_in(modal()).contains(action_button("prepare").tooltip_text), "Missing-material reason was hidden in a tooltip")
	Game.run.home = original_home
	Game.refresh()
	await frames()
	await snapshot("ledger-crisis-warning")
	var energy_before := State.attr(Game.run, "energy")
	await click(action_button("investigate"), true)
	check(Game.run.busy.get("kind", "") == "crisis" and not main.has_modal("crisis") and not main.has_modal("journal"), "Investigation failed to close blocking modals and start actual work")
	check(State.attr(Game.run, "energy") == energy_before - 4, "Fast double click charged investigation energy more than once")
	check(Crisis.view(Game.run).confirmed == "unknown", "Investigation revealed truth before work finished")
	await complete_work(30)
	check(Crisis.view(Game.run).confirmed == "real" and str(Crisis.view(Game.run).evidence) != "", "Completed investigation lacked real evidence")
	await open_journal()
	check(labels_in(modal()).contains("已核实 · 属实"), "Actual investigation result missing after reopening")
	var before: Dictionary = Game.run.home.duplicate(true)
	await click(action_button("prepare"))
	check(Inv.count(Game.run.home, "wood") == Inv.count(before, "wood") - 1 and Inv.count(Game.run.home, "firewood") == Inv.count(before, "firewood") - 1, "Well preparation did not pay displayed materials")
	check(not bool(Crisis.view(Game.run).protected), "Preparation protected the well before work completion")
	await complete_work(60)
	check(bool(Crisis.view(Game.run).protected), "Completed preparation did not protect this crisis")
	Game.save_game()
	Game.run = {}
	Game.continue_game()
	await frames()
	check(bool(Crisis.view(Game.run).protected) and Crisis.view(Game.run).confirmed == "real", "Isolated save/load lost investigation or protection")
	# Move the fixture to just before the deadline, then cross it with the real game clock.
	Game.run.t = int(Crisis.view(Game.run).impact_t) - 10
	Game.run.pday = int(Game.run.t) / 1440 + 1
	main._screen.advance(10)
	Game.refresh()
	await frames()
	check(Crisis.view(Game.run).stage == "resolved" and Crisis.view(Game.run).outcome == "averted", "Protected warning did not resolve at impact")
	await click(hud_entry())
	await snapshot("ledger-crisis-averted")
	await close_modals()
	var old_id := str(Crisis.view(Game.run).id)
	Game.run.pday = int(Crisis.state(Game.run).next_warning_day)
	Game.run.t = (int(Game.run.pday) - 1) * 1440 + 120
	main._screen.advance(1)
	await frames(7)
	var next_view := Crisis.view(Game.run)
	check(str(next_view.id) != old_id and Game.run.pending_event == "", "Next slot did not publish independently of random events")
	check(labels_in(main._screen.hud.find_child("CrisisHUDCard", true, false)).contains(str(next_view.title)), "Next crisis retained the previous HUD title")
	# Real shortage: explicit observation lock, then costly emergency restoration.
	await fresh("fuel_shortage", true, "zhou")
	await click(hud_entry())
	await click(action_button("ignore"))
	check(modal() != null and Crisis.view(Game.run).response == "ignore", "Ignoring did not keep the modal open or persist its choice")
	check(action_button("investigate").disabled and action_button("prepare").disabled, "Observation choice did not lock advance actions")
	Game.run.t = int(Crisis.view(Game.run).impact_t) - 10
	Game.run.pday = int(Game.run.t) / 1440 + 1
	await close_modals()
	main._screen.advance(10)
	Game.refresh()
	await frames()
	check(Crisis.view(Game.run).stage == "impact" and int(Crisis.market_effect(Game.run, "zhou").price_add) == 1, "Observed real shortage lacked its market consequence")
	await click(hud_entry())
	check(labels_in(modal()).contains("危机已发生"), "Actual impact missing from rendered panel")
	await snapshot("ledger-crisis-impact")
	before = Game.run.home.duplicate(true)
	await click(action_button("emergency"))
	check(Inv.count(Game.run.home, "wood") == Inv.count(before, "wood") - 2 and Inv.count(Game.run.home, "nails") == Inv.count(before, "nails") - 2, "Emergency did not charge displayed costs")
	await complete_work(90)
	check(Crisis.view(Game.run).outcome == "repaired" and int(Crisis.market_effect(Game.run, "zhou").price_add) == 0, "Completed emergency did not restore supply")
	# False rumor: inspection ends the crisis without requiring wasted preparation materials.
	await fresh("herb_shortage", false)
	await click(hud_entry())
	await click(action_button("investigate"))
	await complete_work(30)
	check(Crisis.view(Game.run).confirmed == "false" and Crisis.view(Game.run).outcome == "false_alarm", "False rumor inspection failed to close the loop")
	await click(hud_entry())
	await snapshot("ledger-crisis-false-alarm")
	# Earn a real favor through aid, then spend it on the alternative crisis response.
	await fresh("herb_shortage", true)
	check(Post.trade_action(Game.run, "ning", "aid", str(Trade.quote(Game.run, "ning").id)) == "", "Could not earn fixture favor from an actual aid transfer")
	check(int(Trade.contact(Game.run, "ning").favors) == 1, "Real transfer failed to grant a usable favor")
	Game.refresh()
	await frames()
	await click(hud_entry())
	before = Game.run.home.duplicate(true)
	await click(action_button("aid"))
	check(Inv.count(Game.run.home, "rice") == Inv.count(before, "rice") - 1 and int(Trade.contact(Game.run, "ning").favors) == 0, "Asking for help failed to consume rice and the real favor")
	await complete_work(30)
	check(bool(Crisis.view(Game.run).protected), "Completed favor response did not protect the crisis")
	await finish()
