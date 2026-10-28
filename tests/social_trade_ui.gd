extends Node
## Window-rendered local integration. Save, meta and Memory.md are all fixture-only.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Post = preload("res://scripts/core/post.gd")
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

func modal() -> Node:
	return main._modals.get("social_trade")

func button_with(prefix: String, parent: Node = null) -> Button:
	if parent == null: parent = main
	for button in parent.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix): return button
	return null

func action_button(action: String) -> Button:
	if modal() == null: return null
	for button in modal().find_children("*", "Button", true, false):
		if button.get_meta("trade_action", "") == action: return button
	return null

func contact_button(actor: String) -> Button:
	for button in modal().find_children("*", "Button", true, false):
		if button.get_meta("trade_contact", "") == actor: return button
	return null

func labels_in(parent: Node) -> String:
	var lines := PackedStringArray()
	for label in parent.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Could not click enabled UI button"):
		return
	var node: Node = button.get_parent()
	while node != null:
		if node is ScrollContainer:
			node.ensure_control_visible(button)
			await frames(2)
		node = node.get_parent()
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

func open_from_journal() -> void:
	if main.has_modal("social_trade"): main.close_modal("social_trade")
	if not main.has_modal("journal"):
		var entry: Button
		for button in main.find_children("*", "Button", true, false):
			if button.is_visible_in_tree() and button.tooltip_text == "劫余录":
				entry = button
				break
		await click(entry)
	if not check(main.has_modal("journal"), "HUD journal button failed to open journal"): return
	await click(button_with("纸鹤往来", main._modals.journal))
	check(main.has_modal("social_trade"), "Actual journal entry failed to open trade modal")

func snapshot(name: String) -> void:
	await frames(8)
	var viewport := get_viewport().get_visible_rect()
	# Content can extend vertically inside its scroll, but the outer panel and its width cannot.
	for panel in modal().find_children("*", "PanelContainer", true, false):
		var ancestor: Node = panel.get_parent()
		var inside_scroll := false
		while ancestor != null:
			if ancestor is ScrollContainer: inside_scroll = true
			ancestor = ancestor.get_parent()
		if not inside_scroll:
			check(viewport.encloses(panel.get_global_rect()), "Trade outer panel exceeded viewport")
	for button in modal().find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= viewport.end.x, "Trade button exceeded horizontal viewport: " + button.text)
	var scroll: ScrollContainer = modal().find_child("TradeDetailsScroll", true, false)
	check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "Trade details did not provide usable vertical scrolling")
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Trade screenshot failed")
	print("Social trade UI frame: ", path)

func finish() -> void:
	Game.no_save = true
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Fixture cleanup failed: " + path)
	if is_instance_valid(main): main.queue_free()
	await frames(4)
	print("Social trade UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://social-trade-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://social-trade-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://social-trade-ui-Memory-%d.md" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.speed = 0
	Game.snapshots = {}
	Game.run = State.new_run("escort", Game.meta, 1274)
	Pre.start_disaster(Game.run)
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Game.run.home = {"rice": 100, "wood": 100, "nails": 100, "mugwort": 100, "plague_powder": 100, "water": 100, "firewood": 100, "cloth": 100, "salve": 100, "flatbread": 100}
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Trade.influence(Game.run, "traveler", 4, "界面测试前置往来")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
	Game.no_save = false
	Game.go("post")
	Game.refresh()
	await frames(10)
	await open_from_journal()
	if not check(modal() != null, "Trade modal missing"):
		await finish()
		return
	var text := labels_in(modal())
	check(text.contains("信任") and text.contains("欠你的人情") and text.contains("失约未补"), "Relationship consequences missing from UI")
	check(text.contains("交出：") and text.contains("得到：") and text.contains("报价缘由："), "Quote cost, outcome or reason missing")
	check(text.contains("最近结果：过路客 · 界面测试前置往来"), "Global result on Ning's page did not identify the actual traveler")
	for actor in Trade.ACTORS:
		check(contact_button(actor) != null, "Contact tab missing: " + actor)
	for action in ["cash", "favor", "credit", "aid", "decline", "repay", "compensate"]:
		check(action_button(action) != null, "Trade action missing from rendered page: " + action)
	await snapshot("ledger-social-trade-quote")
	var quoted := Trade.quote(Game.run, "ning").duplicate(true)
	var before: Dictionary = Game.run.home.duplicate(true)
	await click(action_button("cash"), true)
	for id in quoted.req:
		check(Inv.count(Game.run.home, id) == Inv.count(before, id) - int(quoted.req[id]) + int(quoted.give.get(id, 0)), "Double click charged incorrect cash cost: " + id)
	for id in quoted.give:
		check(Inv.count(Game.run.home, id) == Inv.count(before, id) + int(quoted.give[id]) - int(quoted.req.get(id, 0)), "Cash outcome missing or duplicated: " + id)
	check(int(Trade.contact(Game.run, "ning").trust) == 1, "Cash trade did not gain exactly one trust")
	check(action_button("cash") != null and action_button("cash").disabled, "Consumed daily quote remained actionable")
	check(labels_in(modal()).contains("最近结果："), "Action feedback was not rendered")
	# Let the expected stale-token toast from the second click expire before evidence frames.
	await get_tree().create_timer(2.9).timeout
	await click(contact_button("zhou"))
	check(labels_in(modal()).contains("最近结果：阿宁 · 交出"), "Switching contact incorrectly attributed Ning's cash result")
	before = Game.run.home.duplicate(true)
	await click(action_button("decline"))
	check(Game.run.home == before, "Declining consumed inventory")
	await open_from_journal()
	check(action_button("cash") != null and action_button("cash").disabled, "Declined offer reopened on same day")
	check(labels_in(modal()).contains("婉拒"), "Decline consequence missing in rendered history")
	await click(contact_button("traveler"))
	await click(action_button("credit"))
	var debt: Dictionary = Trade.context(Game.run).debt.duplicate(true)
	if check(not debt.is_empty(), "Actual credit click did not create fixed debt"):
		check(labels_in(modal()).contains("18:00") and labels_in(modal()).contains("欠多少已经说定"), "Debt deadline or fixed terms missing")
		var debt_scroll: ScrollContainer = modal().find_child("TradeDetailsScroll", true, false)
		debt_scroll.ensure_control_visible(modal().find_child("TradeDebtSummary", true, false))
		await snapshot("ledger-social-trade-debt")
		before = Game.run.home.duplicate(true)
		await click(action_button("repay"))
		check(Trade.context(Game.run).debt.is_empty(), "Actual repay click did not clear debt")
		for id in debt.req:
			check(Inv.count(Game.run.home, id) == Inv.count(before, id) - int(debt.req[id]), "Repayment did not charge fixed resources")
	Game.save_game()
	Game.run = {}
	Game.continue_game()
	await frames()
	check(Trade.context(Game.run).debt.is_empty() and Trade.state(Game.run).history.size() >= 4, "Save/load lost trade history or restored paid debt")
	# Inspect fresh next-day options with no stock; disabled reasons must be visible in the page.
	Game.run.pday = 3
	Game.run.t = 2 * 1440 + 120
	Game.run.home = {}
	Game.refresh()
	await frames()
	await open_from_journal()
	await click(contact_button("ning"))
	check(action_button("cash") != null and action_button("cash").disabled, "Insufficient resources did not disable cash option")
	check(action_button("cash").tooltip_text != "" and labels_in(modal()).contains(action_button("cash").tooltip_text), "Resource block reason was hidden")
	Game.run.t = 2 * 1440 + 720
	Game.refresh()
	await frames()
	for action in ["cash", "favor", "credit", "aid", "decline"]:
		var option := action_button(action)
		check(option == null or option.disabled, "Night boundary left actionable daily option: " + action)
	await snapshot("ledger-social-trade-unavailable")
	await finish()
