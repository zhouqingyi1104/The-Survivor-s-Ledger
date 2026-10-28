extends Node
## Actual mouse paths and rendered local consequences; save/meta/Memory are isolated.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Dialogue = preload("res://scripts/core/npc_dialogue.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
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
	return main._modals.get("npc_autonomy")

func labels_in(parent: Node) -> String:
	var lines := PackedStringArray()
	for label in parent.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func meta_button(key: String, value, parent: Node = null) -> Button:
	if parent == null: parent = main
	for button in parent.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.has_meta(key) and button.get_meta(key) == value: return button
	return null

func prefix_button(prefix: String, parent: Node = null) -> Button:
	if parent == null: parent = main
	for button in parent.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix): return button
	return null

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Missing enabled NPC UI button"): return
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

func open_from_journal() -> void:
	await close_modals()
	var entry: Button
	for button in main._screen.hud.find_children("*", "Button", true, false):
		if button.tooltip_text == "劫余录": entry = button; break
	await click(entry)
	check(main.has_modal("journal"), "Actual HUD journal entry failed")
	await click(prefix_button("邻人与商情", main._modals.get("journal")))
	check(modal() != null, "Journal NPC action entry failed")

func fresh(stockpile := false) -> void:
	await close_modals()
	Game.run = State.new_run("escort", Game.meta, 4242)
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Game.run.home = {"rice": 30, "wood": 20, "nails": 20, "firewood": 20, "water": 30, "mugwort": 20, "flatbread": 10}
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Past.state(Game.run).inherited = [{"life": 1, "actor": "ning", "fact_id": "hidden-fixture", "day": 2, "fact": "秘密旧世：你曾送过药。", "valence": 1}]
	var npcs := Npc.state(Game.run)
	var trade := Trade.state(Game.run)
	for actor in Trade.ACTORS:
		var item: String = {"ning": "mugwort", "zhou": "wood", "traveler": "firewood"}[actor]
		npcs.actors[actor].stock = {"rice": 4, item: 4}
	if stockpile:
		check(Crisis.propose(Game.run, {"kind": "herb_shortage", "actor": "ning", "warning_day": 2, "real": true}, 1), "Could not create published crisis fixture")
	else:
		Crisis.state(Game.run).next_warning_day = 9
		npcs.actors.ning.stock.rice = 0
		trade.actors.zhou.trust = -2
		trade.actors.traveler.trust = 3
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Post.trade_refresh(Game.run)
	Game.go("post")
	Game.refresh()
	await frames(9)

func execute_at_deadline(actor := "ning") -> void:
	await close_modals()
	var due := int(Npc.view(Game.run, actor).plan.due_t)
	Game.run.t = due - 10
	Game.run.pday = int(Game.run.t) / 1440 + 1
	main._screen.advance(10)
	Game.refresh()
	await frames(8)
	check(int(Game.run.t) == due and str(Npc.view(Game.run, actor).plan.status) == "done", "Real clock did not execute autonomous work at 16:00")

func snapshot(name: String) -> void:
	await frames(6)
	# Double-click rejection toasts are expected, but must not obscure evidence frames.
	if main._toasts.get_child_count() > 0: await get_tree().create_timer(2.9).timeout
	var viewport := get_viewport().get_visible_rect()
	if check(modal() != null, "NPC detail missing for rendered check"):
		for panel in modal().find_children("*", "PanelContainer", true, false):
			var ancestor: Node = panel.get_parent()
			var inside_scroll := false
			while ancestor != null:
				if ancestor is ScrollContainer: inside_scroll = true
				ancestor = ancestor.get_parent()
			if not inside_scroll: check(viewport.encloses(panel.get_global_rect()), "NPC outer panel exceeded 1280x720")
		for button in modal().find_children("*", "Button", true, false):
			var rect: Rect2 = button.get_global_rect()
			check(rect.position.x >= 0 and rect.end.x <= viewport.end.x, "NPC action exceeded horizontal viewport")
		var scroll: ScrollContainer = modal().find_child("NpcDetailsScroll", true, false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "NPC action details require usable scrolling")
	var crisis: Control = main._screen.hud.find_child("CrisisHUDCard", true, false)
	if crisis != null:
		check(viewport.encloses(crisis.get_global_rect()), "Crisis HUD exceeded viewport")
		for panel in main._screen.hud.find_children("*", "PanelContainer", true, false):
			if panel == crisis or crisis.is_ancestor_of(panel): continue
			check(not crisis.get_global_rect().intersects(panel.get_global_rect()), "NPC integration obscured crisis HUD")
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "NPC UI screenshot failed")
	print("NPC UI frame: ", path)

func finish() -> void:
	Game.no_save = true
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "NPC fixture cleanup failed")
	if is_instance_valid(main): main.queue_free()
	await frames(4)
	print("NPC UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://npc-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://npc-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://npc-ui-Memory-%d.md" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.speed = 0
	Game.snapshots = {}
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	Game.no_save = false
	await fresh()
	check(Dialogue.state(Game.run).actors.is_empty(), "HUD or unseen actors froze dialogue before being read")
	check(Dialogs.npc_pending_count(Game.run) == 3, "HUD count did not reflect three independent decisions")
	check(str(main._screen.hud.find_child("NpcPendingSubtitle", true, false).text).contains("3"), "Existing journal subtitle did not expose pending NPC decisions")
	check(Npc.view(Game.run, "ning").plan.mode == "gather" and Npc.view(Game.run, "zhou").plan.mode == "guard" and Npc.view(Game.run, "traveler").plan.mode == "share", "Resource, trust and goodwill fixture did not produce distinct intentions")
	await open_from_journal()
	if modal() == null:
		await finish()
		return
	var text := labels_in(modal())
	check(Dialogue.state(Game.run).actors.size() == 1 and Dialogue.state(Game.run).actors.has("ning"), "Opening one actor froze another actor's unread dialogue")
	check(text.contains("对方存货") and text.contains("另算，不从这里出"), "NPC stock was confused with trading contract stock")
	check(text.contains("当前目标") and text.contains("决定原因") and text.contains("16:00") and text.contains("新报价政策"), "Goal, reason, deadline or actual policy missing")
	check(text.contains("按此计划的实际后果") and text.contains(str(Npc.view(Game.run, "ning").effect)), "Local numeric consequence missing before intervention")
	check(text.contains("尚未觉醒") and not text.contains("秘密旧世"), "UI exposed unawakened memory")
	for actor in Trade.ACTORS: check(meta_button("npc_contact", actor, modal()) != null, "Missing NPC tab: " + actor)
	for action in ["support", "favor", "decline"]: check(meta_button("npc_action", action, modal()) != null, "Missing NPC response: " + action)
	check(meta_button("npc_action", "favor", modal()).disabled and text.contains("人情"), "Unavailable favor was not visibly blocked")
	var before: Dictionary = Game.run.home.duplicate(true)
	Game.run.home = {}
	Game.refresh()
	await frames()
	var blocked := meta_button("npc_action", "support", modal())
	check(blocked.disabled and labels_in(modal()).contains(blocked.tooltip_text), "Material shortage reason hidden in tooltip")
	Game.run.home = before
	Game.refresh()
	await frames()
	await snapshot("ledger-npc-gather")
	var details: ScrollContainer = modal().find_child("NpcDetailsScroll", true, false)
	details.ensure_control_visible(meta_button("npc_action", "support", modal()))
	await snapshot("ledger-npc-choices")
	var rice_before := Inv.count(Game.run.home, "rice")
	var stock_before := int(Npc.view(Game.run, "ning").stock.rice)
	await click(meta_button("npc_action", "support", modal()), true)
	check(Inv.count(Game.run.home, "rice") == rice_before - 2 and int(Npc.view(Game.run, "ning").stock.rice) == stock_before + 2, "Fast double click did not transfer exactly the displayed support")
	check(int(Trade.contact(Game.run, "ning").favors) == 1 and int(Trade.contact(Game.run, "ning").trust) == 1, "Support did not create actual goodwill")
	check(str(Npc.view(Game.run, "ning").plan.response) == "support" and meta_button("npc_action", "support", modal()).disabled, "Intervention failed to lock once")
	check(Dialogs.npc_pending_count(Game.run) == 2 and labels_in(modal()).contains("最近结果"), "Support result or live pending count missing")
	check(str(modal().find_child("NpcDialogueText", true, false).text).contains(str(Npc.view(Game.run, "ning").effect)), "Read dialogue retained stale facts after supporting the plan")
	# First reading should freeze this actor alone; switching tabs must not rewrite it.
	var speech := str(Dialogue.render(Game.run, "ning").text)
	await click(meta_button("npc_contact", "zhou", modal()))
	check(labels_in(modal()).contains("收紧") and labels_in(modal()).contains("加"), "Guard intent and consequences missing")
	before = Game.run.home.duplicate(true)
	await click(meta_button("npc_action", "decline", modal()))
	check(Game.run.home == before and int(Trade.contact(Game.run, "zhou").trust) == -2, "Letting NPC decide cost material or caused an invented penalty")
	await click(meta_button("npc_contact", "traveler", modal()))
	check(labels_in(modal()).contains("回报"), "Goodwill-driven autonomous return missing")
	await click(meta_button("npc_contact", "ning", modal()))
	check(str(Dialogue.render(Game.run, "ning").text) == speech and str(modal().find_child("NpcDialogueText", true, false).text).ends_with(speech), "Previously read actor dialogue changed on tab return")
	await click(meta_button("npc_trade_entry", true, modal()))
	check(main.has_modal("social_trade") and not main.has_modal("npc_autonomy"), "NPC→trade actual mouse jump failed")
	check(meta_button("trade_contact", "ning", main._modals.social_trade).text.begins_with("●"), "Cross-entry lost selected actor")
	await click(meta_button("trade_npc_entry", true, main._modals.social_trade))
	check(modal() != null and not main.has_modal("social_trade"), "Trade→NPC actual mouse jump failed")
	Game.save_game()
	var saved: Dictionary = Npc.state(Game.run).duplicate(true)
	await close_modals()
	Game.run = {}
	Game.continue_game()
	await frames(9)
	check(Npc.state(Game.run) == saved, "Isolated save/load lost actor inventory or selected response")
	var gift_before := Inv.count(Game.run.home, "firewood")
	await execute_at_deadline()
	check(Inv.count(Game.run.home, "firewood") == gift_before + 1, "Autonomous sharing did not deliver actual finite stock")
	check(int(Npc.market_effect(Game.run, "zhou").price_add) == 1 and not bool(Npc.market_effect(Game.run, "zhou").credit_allowed), "Unassisted guarding failed to alter actual new-market policy")
	var after: Dictionary = Game.run.home.duplicate(true)
	Post.trade_refresh(Game.run)
	check(Game.run.home == after and Dialogs.npc_pending_count(Game.run) == 0, "Repeated refresh duplicated gift or reopened a completed intervention")
	await open_from_journal()
	check(labels_in(modal()).contains("已执行") and meta_button("npc_action", "support", modal()).disabled, "Completed action remained clickable")
	await snapshot("ledger-npc-executed")
	# A public crisis changes the relevant actor's intention; favor is a reserved real delivery.
	await fresh(true)
	check(Npc.view(Game.run, "ning").plan.mode == "stockpile", "Published herb crisis failed to cause protective stockpiling")
	Trade.state(Game.run).actors.ning.favors = 1
	Past.state(Game.run).awakenings.append({"actor": "ning", "life": 1, "age": 1, "fact_id": "ui-awake", "fact": "你曾在雪夜送来艾草。", "response": "acknowledge"})
	await open_from_journal()
	check(labels_in(modal()).contains("你曾在雪夜送来艾草") and labels_in(modal()).contains("已觉醒片段"), "Only actual awakened memory was not displayed")
	await snapshot("ledger-npc-crisis")
	var herb_before := Inv.count(Game.run.home, "mugwort")
	var npc_herb_before := int(Npc.view(Game.run, "ning").stock.mugwort)
	await click(meta_button("npc_action", "favor", modal()), true)
	check(int(Trade.contact(Game.run, "ning").favors) == 0 and int(Npc.view(Game.run, "ning").stock.mugwort) == npc_herb_before - 1, "Favor did not consume exactly one real favor and reserve NPC stock")
	check(Inv.count(Game.run.home, "mugwort") == herb_before and labels_in(modal()).contains("已约送达"), "Reserved favor arrived early or lacked visible promise")
	check(str(modal().find_child("NpcDialogueText", true, false).text).contains(str(Npc.view(Game.run, "ning").effect)), "Dialogue did not refresh locked favor delivery facts")
	await execute_at_deadline()
	check(Inv.count(Game.run.home, "mugwort") == herb_before + 1, "Reserved favor did not arrive through actual 16:00 execution")
	await open_from_journal()
	check(labels_in(modal()).contains("凭情改托（已送达）") and labels_in(modal()).contains("下一次决定"), "Delivered favor still appeared reserved or next decision was hidden")
	check(str(modal().find_child("NpcDialogueText", true, false).text).contains(str(Npc.view(Game.run, "ning").last_result)), "Dialogue did not show actual completed delivery facts")
	await snapshot("ledger-npc-favor")
	await finish()
