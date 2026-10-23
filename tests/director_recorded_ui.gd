extends Node
## Replays the single authorized ARK answer, offline. Never generates or retries.
const Core = preload("res://scripts/core/director.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Events = preload("res://scripts/core/events.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
var failures := 0
var checks := 0
var captured: Dictionary

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func replay() -> Dictionary:
	var r := State.new_run("escort", State.new_meta(), 321)
	Pre.start_disaster(r)
	r.pday = 3
	r.t = 3000
	r.home = captured.snapshot.state.stock.duplicate()
	var neighbor := Neighbor.state(r)
	for key in captured.snapshot.state.neighbor: neighbor[key] = captured.snapshot.state.neighbor[key]
	var d := Core.state(r)
	d.session = captured.snapshot.session
	d.relations = captured.snapshot.state.relations.duplicate()
	check(Core.accept(r, captured.snapshot, captured.result.plan), "Recorded ARK plan not accepted by Godot")
	return r

func at(r: Dictionary, day: int) -> void:
	r.pday = day
	r.t = (day - 1) * 1440 + 120

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.speed = 0
	Game.meta = State.new_meta()
	captured = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-ark-recorded.json"))
	check(captured.status == 200 and captured.result.reasoning_effort == "low", "Fixture is not the real low-reasoning success")
	for event in captured.result.plan.days:
		for index in event.choices.size():
			var r := replay()
			at(r, int(event.day))
			Core.poll(r)
			var c: Dictionary = event.choices[index]
			var before: Dictionary = r.home.duplicate()
			check(Events.choose(r, index) == "", "Recorded choice could not execute")
			for id in Core.GOODS:
				check(Inv.count(r.home, id) == Inv.count(before, id) - int(c.get("req", {}).get(id, 0)) + int(c.get("give", {}).get(id, 0)), "Recorded choice effect mismatch: " + id)
			check(int(r.director.relations[event.actor]) == int(captured.snapshot.state.relations[event.actor]) + int(c.get("relation", 0)), "Recorded relationship not applied")
			if c.has("after"):
				var stock: Dictionary = r.home.duplicate()
				at(r, int(event.day) + int(c.after.days))
				Core.poll(r)
				Core.poll(r)
				for id in c.after.give:
					check(Inv.count(r.home, id) == Inv.count(stock, id) + int(c.after.give[id]), "Recorded delayed consequence did not deliver exactly once")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for event in captured.result.plan.days:
		Game.run = replay()
		at(Game.run, int(event.day))
		Core.poll(Game.run)
		Game.go("post")
		for k in 10: await get_tree().process_frame
		check(main.has_modal("event"), "Recorded ARK event did not open")
		for button in main._modals.event.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				check(get_viewport().get_visible_rect().encloses(button.get_global_rect()), "Recorded ARK choice clipped")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("ledger-director-real-day-%d.png" % event.day))
	main.queue_free()
	for k in 3: await get_tree().process_frame
	print("Recorded ARK UI: %d checks, %d failures; 3 real events / 9 choices replayed without network" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
