extends Node
## Window-rendered integration fixture. No ARK requests or player save writes.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Events = preload("res://scripts/core/events.gd")
const Director = preload("res://scripts/core/director.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Inv = preload("res://scripts/core/inv.gd")
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

func button_with(prefix: String, parent: Node = null) -> Button:
	if parent == null: parent = main
	for button in parent.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix): return button
	return null

func labels_in(parent: Node) -> String:
	var lines := PackedStringArray()
	for label in parent.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func snapshot(name: String) -> void:
	await frames(8)
	var viewport := get_viewport().get_visible_rect()
	for modal in main._modals.values():
		for panel in modal.find_children("*", "PanelContainer", true, false):
			if panel.is_visible_in_tree():
				check(viewport.encloses(panel.get_global_rect()), "Past-life modal panel clipped: " + str(modal.key))
		for button in modal.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				check(viewport.encloses(button.get_global_rect()), "Past-life modal button clipped: " + button.text)
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot could not be saved")
	print("Past lives UI frame: ", path)

func finish() -> void:
	Game.no_save = true
	for path in [Game.save_path, Game.meta_path]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(absolute) == OK, "Scratch save cleanup failed: " + path)
	if is_instance_valid(main): main.queue_free()
	await frames(4)
	print("Past lives UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	# Set both paths before enabling writes; generation selection below is fixture-only.
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.save_path = "user://past-lives-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://past-lives-ui-meta-%d.json" % OS.get_process_id()
	Game.meta = State.new_meta()
	Game.speed = 0
	Game.snapshots = {}
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(1))
	Game.run = State.new_run("escort", Game.meta, 1274)
	Pre.start_disaster(Game.run)
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Game.run.home = {"rice": 3, "plague_powder": 1}
	Director.state(Game.run).enabled = false
	check(Neighbor.poll(Game.run) == "n_request", "First-life neighbor request was not available")
	check(Events.choose(Game.run, 1) == "", "Actual neighbor donation failed")
	check(Neighbor.state(Game.run).resolution == "donated" and Inv.count(Game.run.home, "plague_powder") == 0, "Actual medicine transfer did not pay its cost")
	check(Past.state(Game.run).trace.size() == 1 and Past.state(Game.run).trace[0].fact_id == "medicine", "Executed medicine choice was not recorded")
	var first_id: String = Past.state(Game.run).id
	Game.no_save = false
	Game.run.phase = "dead"
	Game.restart_from_cover()
	await frames()
	check(int(Past.book(Game.meta).count) == 1 and Past.book(Game.meta).lives[0].id == first_id, "Restart did not archive exactly one real life")
	check(int(Past.state(Game.run).generation) == 2 and Past.state(Game.run).inherited.size() == 1, "Restarted life did not inherit the executed fact")
	var restarted_id: String = Past.state(Game.run).id
	Game.save_game()
	Game.meta = Game._read_json(Game.meta_path)
	Game.run = {}
	Game.continue_game()
	check(int(Past.book(Game.meta).count) == 1 and Past.state(Game.run).id == restarted_id, "Scratch meta/save reload lost the past-life archive")
	check(Past.state(Game.run).inherited[0].fact_id == "medicine", "Save/load lost the actual past-life fact")
	# Pick a naturally scheduled second life; never force probability or inject a memory.
	var candidate: Dictionary = {}
	for seed_value in range(1, 201):
		var generated := State.new_run("escort", Game.meta, seed_value)
		if not Past.state(generated).schedule.is_empty():
			candidate = generated
			break
	if not check(not candidate.is_empty(), "No natural awakening fixture found in 200 new-life candidates"):
		await finish()
		return
	Game.run = candidate
	Pre.start_disaster(Game.run)
	Game.snapshots = {}
	Neighbor.state(Game.run).stage = "closed"
	Game.run.home = {"rice": 3}
	Director.state(Game.run).enabled = false
	var scheduled: Dictionary = Past.state(Game.run).schedule[0]
	Game.run.pday = int(scheduled.day)
	Game.run.t = (int(scheduled.day) - 1) * 1440 + 120
	check(Past.public_memories(Game.run).is_empty(), "Unawakened archive leaked into the director snapshot")
	check(Director.poll(Game.run).begins_with("world:memory:"), "Offline director did not trigger the scheduled awakening")
	Game.go("post")
	Game.refresh()
	await frames(8)
	if not check(main.has_modal("event"), "Awakening did not reach the actual event modal"):
		await finish()
		return
	var event: Dictionary = Events.entry(Game.run)
	check(event.choices.size() == 3 and event.has("past_memory"), "Awakening did not offer its three local choices")
	check(Past.public_memories(Game.run).size() == 1 and Director.snapshot(Game.run).state.recollections.size() == 1, "Awakened fact was not made available to future planning")
	var modal: Node = main._modals.event
	check(labels_in(modal).contains("你曾把药交给阿宁。") and labels_in(modal).contains("前世的片段"), "Rendered awakening lost its true fact or past-life distinction")
	for prefix in ["承认这段似曾相识", "送出米 1", "只当作一场旧梦"]:
		check(button_with(prefix, modal) != null, "Missing awakening choice: " + prefix)
	var pay := button_with("送出米 1", modal)
	if not check(pay != null and not pay.disabled and pay.text.contains("需"), "Paid awakening choice did not expose its real cost"):
		await finish()
		return
	await snapshot("ledger-past-lives-awakening")
	var rice_before := Inv.count(Game.run.home, "rice")
	var relation_before := int(Director.state(Game.run).relations.ning)
	# Two same-frame real button signals emulate a fast double click before UI rebuild.
	pay.pressed.emit()
	pay.pressed.emit()
	await frames()
	check(Inv.count(Game.run.home, "rice") == rice_before - 1, "Repeated actual button signal charged rice more than once")
	check(int(Director.state(Game.run).relations.ning) == relation_before + 2, "Awakening relationship consequence was missing or duplicated")
	check(Past.public_memories(Game.run)[0].response == "compensate", "Actual UI choice did not persist its response")
	Game.save_game()
	Game.meta = Game._read_json(Game.meta_path)
	Game.run = {}
	Game.continue_game()
	await frames()
	check(Past.public_memories(Game.run)[0].response == "compensate" and Inv.count(Game.run.home, "rice") == rice_before - 1, "Save/load lost the awakening response or paid cost")
	check(int(Past.book(Game.meta).count) == 1, "Response save/load incorrectly sealed another life")
	Director.poll(Game.run)
	check(Game.run.pending_event == "" and Past.public_memories(Game.run).size() == 1, "Already witnessed awakening repeated after load")
	main.close_modal("event")
	Dialogs.journal()
	await frames()
	var memory_button := button_with("前世记忆", main._modals.journal)
	if check(memory_button != null and not memory_button.disabled, "Journal is missing its past-life memory entry"):
		memory_button.pressed.emit()
		await frames()
		check(main.has_modal("past_lives"), "Past-life journal button did not open its actual page")
		if main.has_modal("past_lives"):
			var memories_text := labels_in(main._modals.past_lives)
			check(memories_text.contains("你曾把药交给阿宁。"), "Memory journal omitted the verified old-life fact")
			await snapshot("ledger-past-lives-journal")
	await finish()
