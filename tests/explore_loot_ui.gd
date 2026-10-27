extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
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
		get_tree().quit(1)
	return ok

func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame

func button(text: String) -> Button:
	if not main.has_modal("explore_loot"): return null
	for b in main._modals.explore_loot.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree(): return b
	return null

func click(b: Button) -> void:
	if not check(b != null and not b.disabled, "Missing loot button"): return
	var parent := b.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(b)
			await frames(2)
		parent = parent.get_parent()
	var p := b.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = p
	press.pressed = true
	get_viewport().push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = p
	get_viewport().push_input(release)
	await frames()

func interact() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.physical_keycode = KEY_E
	press.pressed = true
	get_viewport().push_input(press)
	var release := InputEventKey.new()
	release.keycode = KEY_E
	release.physical_keycode = KEY_E
	get_viewport().push_input(release)
	await frames()

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://explore-loot-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://explore-loot-ui-meta-%d.json" % OS.get_process_id()
	Game.memory_path = "user://explore-loot-ui-memory-%d.md" % OS.get_process_id()
	Game.speed = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 2
	Game.run.t = 1440 + 120
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	check(Post.act_explore(Game.run, "rice_ruin") == "", "Cannot enter ruins")
	Game.go("explore")
	await frames(10)
	main._screen.player.position = main._screen.world._spots[0].pos
	await frames()
	check(main._screen._near == 0, "Physical spot not reachable")
	var before := int(Game.run.t)
	await interact()
	check(main.has_modal("explore_loot") and Game.run.explore.spots[0].done, "E did not search and open the container")
	check(int(Game.run.t) == before + 20 and Game.run.explore.bag.is_empty(), "Search time or initial bag wrong")
	var loot: Dictionary = Game.run.explore.spots[0].loot
	if not check(not loot.is_empty(), "Fixture has no loot"): return
	var id := str(loot.keys()[0])
	var initial := Inv.count(loot, id)
	var viewport := get_viewport().get_visible_rect()
	for p in main._modals.explore_loot.find_children("*", "PanelContainer", true, false):
		check(viewport.encloses(p.get_global_rect()), "Loot panel exceeds viewport")
	DisplayServer.window_move_to_foreground()
	RenderingServer.force_draw()
	var path := OS.get_environment("TEMP").path_join("ledger-explore-loot-ui.png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot failed")
	print("Explore UI frame: ", path)
	await click(button("取 1"))
	check(Inv.count(Game.run.explore.bag, id) == 1 and Inv.count(loot, id) == initial - 1, "Take did not move one item")
	await click(button("放回 1"))
	check(Inv.count(Game.run.explore.bag, id) == 0 and Inv.count(loot, id) == initial, "Put back did not restore item")
	main.close_modal("explore_loot")
	await frames()
	await interact()
	check(main.has_modal("explore_loot") and int(Game.run.t) == before + 20, "Reopening consumed time or failed")
	Game.run.explore.bag = {"wood": int(ceil(Explore.carry(Game.run) / float(Data.item("wood").weight)))}
	Game.refresh()
	await frames()
	await click(button("尽量取"))
	check(Inv.count(loot, id) == initial and Inv.count(Game.run.explore.bag, id) == 0, "Capacity limit failed")
	main.close_modal("explore_loot")
	Game.run.explore.bag = {}
	Game.run.explore.exposure = 0
	Game.run.t = 1440 + 885
	Game.refresh()
	await frames()
	main._screen.player.position = main._screen.world._spots[1].pos
	await frames()
	await interact()
	await frames(20)
	check(not main.has_modal("explore_loot") and Game.run.explore.is_empty() and Game.screen == "post", "Search at curfew opened loot or failed to return")
	check(Post.day_minute(Game.run) == 960, "Curfew return did not consume 60 minutes")
	print("Explore loot UI: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await frames()
	get_tree().quit(1 if failures else 0)
