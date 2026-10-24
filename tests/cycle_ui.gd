extends Node
## Rendered mouse acceptance. Structured old receipts isolate this UI from the
## independently tested trade/neighbor archive chain; no player save or ARK IO.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
var main: Control
var checks := 0
var failures := 0

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
	return main._modals.get("cycle_inquiry")

func labels_in(node: Node) -> String:
	var lines := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func button_meta(key: String, value, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.has_meta(key) and button.get_meta(key) == value: return button
	return null

func button_text(text: String, node: Node = null) -> Button:
	if node == null: node = main
	for button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text == text: return button
	return null

func click(button: Button, twice := false) -> void:
	if not check(button != null and not button.disabled, "Missing enabled cycle mouse target"): return
	DisplayServer.window_move_to_foreground()
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await frames(2)
		ancestor = ancestor.get_parent()
	var point := button.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(point), "Cycle action lies outside 1280x720 viewport")
	# Keep the native cursor and viewport's hover position aligned. A later OS
	# mouse-enter event must not restore a different hover target between press
	# and release; every action below still receives exactly one mouse click.
	get_viewport().warp_mouse(point)
	await frames(1)
	check(is_instance_valid(button) and not button.is_queued_for_deletion(), "Cycle target was rebuilt while arranging its scroll position")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion)
	var hover := get_viewport().gui_get_hovered_control()
	if hover != button:
		print("Cycle mouse target: button=", button.get_path(), " rect=", button.get_global_rect(), " pointer=", get_viewport().get_mouse_position(), " hover=", hover.get_path() if hover != null else "none")
	check(hover == button, "Cycle mouse position does not hover the actual target button")
	var observed := [0]
	button.pressed.connect(func(): observed[0] += 1)
	for k in (2 if twice else 1):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		press.global_position = point
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = point
		release.global_position = point
		get_viewport().push_input(release)
	check(int(observed[0]) >= 1, "Actual cycle mouse press/release did not activate its target button")
	await frames(8)

func close_modals() -> void:
	for key in main._modals.keys(): main.close_modal(key)
	await frames()

func source(kind: String, actor := "ning") -> Dictionary:
	var status: String = {"promise": "kept", "breach": "broken", "rescue": "helped"}[kind]
	var fact_id: String = {"promise": "trade_2_repay", "breach": "trade_overdue_4", "rescue": "medicine"}[kind]
	return {"actor": actor, "kind": kind, "status": status, "source_life": 1, "source_id": "cycle-ui-prior-life", "fact_id": fact_id, "fact": Past._cycle_fact(actor, kind, status), "day": 2}

func fresh(kind := "", daily := false, sealed := false, second_case := false) -> void:
	await close_modals()
	Game.meta = State.new_meta()
	Game.meta.deaths = 1
	Game.run = State.new_run("escort", Game.meta, 8331)
	if kind != "":
		Past.state(Game.run).generation = 2
		var sources := [source(kind)]
		if second_case:
			var other := source("promise", "zhou")
			sources.append(other)
		Game.run.cycle_inquiry = {"schema": 1, "sources": sources}
	if daily: Game.run.flags.daily = "2026-10-24"
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Game.run.home = {"rice": 30, "water": 30, "firewood": 30, "wood": 30, "nails": 30, "mugwort": 30}
	Game.run.silver = 30000
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	Past.state(Game.run).schedule = []
	Crisis.state(Game.run).next_warning_day = 100000
	Npcs.state(Game.run).next_day = 100000
	if not sealed:
		Game.run.pday = 3
		Game.run.t = 2 * 1440 + 120
	Cycle.poll(Game.run)
	for attr in ["food", "water", "mood", "energy", "warmth"]: Game.run.attrs[attr] = 100
	Game.go("post")
	await frames(8)

func open_cycle() -> void:
	await close_modals()
	await click(button_meta("cycle_entry", "hud"))
	check(modal() != null and modal().find_child("CycleInquiryScroll", true, false) != null, "HUD cycle entry did not open actual scrollable dossier")

func first_case() -> Dictionary:
	return Cycle.view(Game.run).cases[0]

func advance_work(minutes: int) -> void:
	var before := int(Game.run.t)
	Game.act(func(): Post.advance(Game.run, minutes); return "")
	await frames(8)
	check(int(Game.run.t) == before + minutes, "Cycle work clock stopped unexpectedly")

func snapshot(name: String) -> void:
	await frames(6)
	if main._toasts.get_child_count() > 0: await get_tree().create_timer(2.9).timeout
	var target: Node = modal() if modal() != null else main._screen
	var viewport := get_viewport().get_visible_rect()
	for label in target.find_children("*", "Label", true, false):
		if label.text == "轮回调查 · 旧诺与今证": check(viewport.encloses(label.get_global_rect()), "Cycle fixed title clips outside viewport")
	for button in target.find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= viewport.end.x + 1, "Cycle button extends outside viewport width")
	for panel in target.find_children("*", "PanelContainer", true, false):
		var ancestor: Node = panel.get_parent()
		var scrolling := false
		while ancestor != null:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling: check(viewport.encloses(panel.get_global_rect()), "Cycle outer panel extends outside 1280x720")
	RenderingServer.force_draw()
	var path := OS.get_environment("TEMP").path_join("ledger-cycle-" + name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Cycle screenshot could not save")
	print("Cycle UI screenshot: ", path)

func investigate() -> void:
	await open_cycle()
	var text := labels_in(modal())
	check(text.contains("第1世") and text.contains("今世") and text.contains("期限"), "Dossier omitted old-life source or current-life boundary/deadline")
	check(first_case().evidence.is_empty(), "Player dream granted current-life evidence")
	var old: Callable = button_meta("cycle_action", "inquire", modal()).pressed.get_connections()[0].callable
	await click(button_meta("cycle_action", "inquire", modal()), true)
	check(modal() == null and Post.is_busy(Game.run), "Actual inquiry click failed to start work and return to play")
	check(first_case().stage == "lead" and first_case().evidence.is_empty(), "Starting inquiry prematurely verified source")
	await advance_work(29)
	check(first_case().stage == "lead", "Inquiry completed one minute early")
	await open_cycle()
	check(labels_in(modal()).contains("还需 1 分钟") and button_meta("cycle_action", "inquire", modal()).disabled, "Ongoing inquiry omitted actual remaining time or allowed duplicate work")
	await advance_work(1)
	check(first_case().stage == "interviewed" and first_case().evidence.is_empty(), "Inquiry completion skipped independent current-life verification")
	var before := Game.run.duplicate(true)
	old.call()
	await frames()
	check(Game.run == before, "Stale inquiry callback changed work or resources")
	await open_cycle()
	var fragment := button_meta("cycle_action", "verify_fragment", modal())
	check(fragment != null and fragment.disabled and labels_in(modal()).contains(fragment.tooltip_text), "Unawakened fragment route did not expose precise disabled reason")
	var rice := Inv.count(Game.run.home, "rice")
	await click(button_meta("cycle_action", "verify", modal()), true)
	check(Inv.count(Game.run.home, "rice") == rice - 1 and first_case().evidence.is_empty(), "Verification click charged twice or granted proof before completion")
	await advance_work(44)
	check(first_case().evidence.is_empty(), "Current-life proof appeared before verification finished")
	await advance_work(1)
	check(first_case().stage == "verified" and not first_case().evidence.is_empty(), "Actual verification did not return current-life evidence")

func test_routes() -> void:
	var routes := {"promise": ["renew", "small_pact"], "breach": ["pay_repair", "cash_restart"], "rescue": ["help_again", "mutual_help"]}
	for kind in routes:
		for action in routes[kind]:
			await fresh(kind)
			await investigate()
			await open_cycle()
			var spec: Dictionary = Cycle.ROUTES[action]
			var person := Trade.contact(Game.run, "ning")
			var trust := int(person.trust)
			var favors := int(person.favors)
			var money := int(Game.run.silver)
			var items: Dictionary = Game.run.home.duplicate()
			var button := button_meta("cycle_action", action, modal())
			check(button != null and not button.disabled and labels_in(modal()).contains("完工") and labels_in(modal()).contains("08:00"), "Route omitted its actual cost, delayed result or return time")
			if action == "pay_repair":
				await snapshot("verified")
				var scroll := modal().find_child("CycleInquiryScroll", true, false) as ScrollContainer
				scroll.ensure_control_visible(button_meta("cycle_action", "decline", modal()))
				await frames()
				await snapshot("choices")
			await click(button, true)
			if first_case().stage != "working" or int(Trade.contact(Game.run, "ning").trust) != trust:
				print("Cycle route diagnostic: kind=", kind, " action=", action, " case=", first_case(), " busy=", Game.run.busy, " trust_before=", trust, " trust_now=", Trade.contact(Game.run, "ning").trust, " log=", Game.run.log.slice(-4))
			check(first_case().stage == "working" and int(Trade.contact(Game.run, "ning").trust) == trust and int(Trade.contact(Game.run, "ning").favors) == favors, "Route selection changed relations before completion")
			check(int(Game.run.silver) == money - int(spec.silver), "Route UI did not charge its stated silver once")
			for item in spec.req: check(Inv.count(Game.run.home, item) == int(items[item]) - int(spec.req[item]), "Route UI charged item twice or omitted payment")
			await advance_work(int(spec.minutes))
			check(first_case().stage == "resolved" and int(Trade.contact(Game.run, "ning").trust) == trust + int(spec.trust) and int(Trade.contact(Game.run, "ning").favors) == favors + int(spec.favors), "Completed route did not affect actual trade trust/favor")
			await open_cycle()
			check(labels_in(modal()).contains("尚未送达") and button_meta("cycle_action", action, modal()) == null, "Completed route falsely claimed delivery or retained mutually exclusive actions")
			if action == "renew": await snapshot("promised")
			var c: Dictionary = Cycle.state(Game.run).cases[0]
			var delivery: Dictionary = c.delivery
			var owed: Dictionary = delivery.give.duplicate()
			var before: Dictionary = Game.run.home.duplicate()
			Game.run.t = int(delivery.due_t) - 1
			Game.run.pday = int(Game.run.t) / 1440 + 1
			Cycle.poll(Game.run)
			check(not delivery.done and Game.run.home == before, "Promised return arrived before locked deadline")
			Game.run.t = int(delivery.due_t)
			Game.run.pday = int(Game.run.t) / 1440 + 1
			Cycle.poll(Game.run)
			for item in owed: check(Inv.count(Game.run.home, item) == int(before.get(item, 0)) + int(owed[item]), "Actual delayed return did not deliver stated inventory")
			Game.refresh()
			await frames()
			check(labels_in(modal()).contains("已送达"), "Dossier did not refresh to actual delivered result")
			if action == "mutual_help": await snapshot("delivered")
			var settled: Dictionary = Game.run.home.duplicate()
			Cycle.poll(Game.run)
			check(Game.run.home == settled, "Rendered delivery could be collected twice")

func test_entries_and_boundaries() -> void:
	await fresh()
	await open_cycle()
	check(labels_in(modal()).contains("尚无可核实") and Cycle.view(Game.run).cases.is_empty(), "First life invented a prior-life case")
	await close_modals()
	Dialogs.journal()
	await frames()
	await click(button_meta("cycle_entry", "journal", main._modals.get("journal")))
	if modal() == null or main.has_modal("journal"):
		print("Cycle journal diagnostic: ", main._modals.keys(), " pointer=", get_viewport().get_mouse_position(), " source=", button_meta("cycle_entry", "journal", main._modals.get("journal")))
	check(modal() != null and not main.has_modal("journal"), "Actual journal entry failed to reveal cycle dossier")
	await close_modals()
	Dialogs.past_lives()
	await frames()
	await click(button_meta("cycle_entry", "past_lives", main._modals.get("past_lives")))
	check(modal() != null and not main.has_modal("past_lives"), "Actual past-life entry failed to reveal current inquiry")
	await fresh("promise", true)
	await open_cycle()
	check(labels_in(modal()).contains("每日局不启用") and Cycle.view(Game.run).cases.is_empty(), "Daily UI exposed old-life advantage")
	await fresh("rescue", false, true, true)
	await open_cycle()
	if Cycle.view(Game.run).cases.size() != 2 or not labels_in(modal()).contains("尚未起算") or not labels_in(modal()).contains("不代表邻人已经觉醒"):
		print("Cycle sealed diagnostic: ", Cycle.view(Game.run), "\n", labels_in(modal()))
	check(Cycle.view(Game.run).cases.size() == 2 and labels_in(modal()).contains("尚未起算") and labels_in(modal()).contains("不代表邻人已经觉醒"), "Future dossier slots omitted timing or falsely awakened an NPC")
	check(button_meta("cycle_action", "inquire", modal()) == null, "Sealed dream can be investigated before publication")
	await snapshot("sealed")
	await fresh("breach")
	await open_cycle()
	var stale: Callable = button_meta("cycle_action", "inquire", modal()).pressed.get_connections()[0].callable
	await fresh("rescue")
	var same: Dictionary = Game.run.duplicate(true)
	stale.call()
	await frames()
	check(Game.run == same, "Previous-life UI callback altered the new run")
	await open_cycle()
	Game.run.attrs.energy = 0
	Game.refresh()
	await frames()
	var inquire := button_meta("cycle_action", "inquire", modal())
	check(inquire.disabled and labels_in(modal()).contains(inquire.tooltip_text), "Insufficient-energy UI hid its blocking reason")
	Game.run.attrs.energy = 100
	var c: Dictionary = Cycle.state(Game.run).cases[0]
	Game.run.t = int(c.deadline_t)
	Game.run.pday = int(Game.run.t) / 1440 + 1
	Cycle.poll(Game.run)
	Game.refresh()
	await frames()
	check(first_case().stage == "expired" and labels_in(modal()).contains("窗口已过") and button_meta("cycle_action", "inquire", modal()) == null, "Expired dossier failed to explain consequence or kept an action alive")
	await snapshot("expired")

func test_fragment_decline_and_reload() -> void:
	await fresh("rescue")
	await open_cycle()
	await click(button_meta("cycle_action", "inquire", modal()))
	await advance_work(30)
	var p := Past.state(Game.run)
	p.awakenings = [{"actor": "ning", "life": 8, "fact_id": "medicine", "fact": "其他世次的救助", "age": 1, "response": ""}]
	await open_cycle()
	check(button_meta("cycle_action", "verify_fragment", modal()).disabled, "Unrelated generation unlocked NPC fragment proof")
	p.awakenings = [{"actor": "ning", "life": 1, "fact_id": "medicine", "fact": "你曾把药交给阿宁。", "age": 1, "response": ""}]
	Game.refresh()
	await frames()
	check(not button_meta("cycle_action", "verify_fragment", modal()).disabled and labels_in(modal()).contains("本人已公开对应碎片"), "Matching publicly awakened fragment failed to unlock alternate check")
	await snapshot("fragment")
	var water := Inv.count(Game.run.home, "water")
	await click(button_meta("cycle_action", "verify_fragment", modal()), true)
	check(Inv.count(Game.run.home, "water") == water - 1 and first_case().evidence.is_empty(), "Fragment route changed proof before work or charged twice")
	await advance_work(30)
	check(first_case().stage == "verified", "Fragment route failed to complete actual current-life proof")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(Game.run)))
	var view := Cycle.view(Game.run)
	Game.run = saved
	Game.go("post")
	await frames(8)
	await open_cycle()
	check(Cycle.view(Game.run) == view, "JSON save/load changed inquiry stage, current proof or locked options")
	for kind in ["promise", "breach", "rescue"]:
		await fresh(kind)
		await open_cycle()
		var items: Dictionary = Game.run.home.duplicate()
		var trust := int(Trade.contact(Game.run, "ning").trust)
		await click(button_meta("cycle_action", "decline", modal()), true)
		check(first_case().stage == "resolved" and Game.run.home == items and int(Trade.contact(Game.run, "ning").trust) == trust - 1, "Decline lacked concrete cost/opportunity consequence or charged twice")
		check(button_meta("cycle_action", "inquire", modal()) == null and labels_in(modal()).contains("信任-1"), "Closed old case retained an actionable alternative or hid result")

func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://cycle-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://cycle-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://cycle-ui-Memory-%d.md" % OS.get_process_id()
	Game.speed = 0
	Game.meta = State.new_meta()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(240).timeout.connect(func(): get_tree().quit(1))
	await test_entries_and_boundaries()
	if failures > 0: return
	await test_routes()
	if failures > 0: return
	await test_fragment_decline_and_reload()
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		check(not FileAccess.file_exists(path), "Cycle UI wrote player scratch persistence despite no_save")
	main.queue_free()
	await frames(4)
	print("Cycle UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
