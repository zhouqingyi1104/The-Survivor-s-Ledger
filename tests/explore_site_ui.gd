extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
var main: Control
var checks := 0
var failed := false
var site_idx := -1
var messages: Array[String] = []

func remember_toast(message: String) -> void:
	messages.append(message)

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error(message)
	return ok

func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame

func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)
	ev = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	get_viewport().push_input(ev)
	await frames()

func click(b: Button) -> void:
	if not check(b != null and not b.disabled, "Missing enabled choice button"): return
	var container := b.get_parent()
	while container != null:
		if container is ScrollContainer:
			container.ensure_control_visible(b)
			await frames(3)
		container = container.get_parent()
	var p := b.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	ev.pressed = true
	get_viewport().push_input(ev)
	ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	get_viewport().push_input(ev)
	await frames(8)

func option_button(id: String) -> Button:
	if not main.has_modal("explore_options"): return null
	for b in main._modals.explore_options.find_children("*", "Button", true, false):
		if b.get_meta("explore_option", "") == id: return b
	return null

func enter_point(pid: String) -> void:
	Game.run = State.new_run("escort", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Game.run.pday = 6
	Game.run.t = 5 * 1440 + 120
	Neighbor.state(Game.run).stage = "closed"
	Director.state(Game.run).enabled = false
	check(Post.act_explore(Game.run, pid) == "", "Cannot enter " + pid)
	# 此套件专测已打开通路后的特色搜寻；机关和真实步行由 expedition_ui 单独覆盖。
	Game.run.explore["expedition"] = {"clues": [true, true], "unlocked": true, "attempts": 1}
	Game.go("explore")
	await frames(10)
	site_idx = -1
	for i in Game.run.explore.spots.size():
		if Explore.site_options(Game.run, i).size() > 1:
			site_idx = i
			break
	if not check(site_idx >= 0, "No featured point: " + pid): return
	main._screen.player.position = main._screen.world._spots[site_idx].pos
	await frames()
	check(main._screen._near == site_idx, "Physical location unreachable: " + pid)

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.toast.connect(remember_toast)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	var titles := []
	for pid in ["rice_ruin", "pharmacy_ruin"]:
		await enter_point(pid)
		var before := int(Game.run.t)
		await key(KEY_E)
		if not check(main.has_modal("explore_options"), "Choice did not open: " + pid): continue
		var options: Array = Explore.site_options(Game.run, site_idx)
		var site: Dictionary = {}
		for option in options:
			if option.id == "site": site = option
		if not check(not site.is_empty(), "Missing site choice: " + pid): continue
		titles.append(str(site.title))
		var descriptions := []
		for label in main._modals.explore_options.find_children("*", "Label", true, false): descriptions.append(label.text)
		check(str(site.description) in descriptions, "Choice effects not shown: " + pid)
		check(option_button("site") != null and option_button("normal") != null, "Both choices must be visible")
		var viewport := get_viewport().get_visible_rect()
		for panel in main._modals.explore_options.find_children("*", "PanelContainer", true, false):
			check(viewport.encloses(panel.get_global_rect()), "Choice panel exceeds viewport")
		if pid == "rice_ruin":
			DisplayServer.window_move_to_foreground()
			RenderingServer.force_draw()
			var path := OS.get_environment("TEMP").path_join("ledger-site-choice-ui.png")
			check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot failed")
			print("Site choice frame: ", path)
			await key(KEY_ESCAPE)
			check(not main.has_modal("explore_options") and int(Game.run.t) == before and not Game.run.explore.spots[site_idx].done, "Cancel consumed time or searched")
			await key(KEY_E)
		await click(option_button("site"))
		check(Game.run.explore.spots[site_idx].done and int(Game.run.t) > before, "Choice did not search and consume time: " + pid)
		check(int(Game.run.t) == before + 30, "Site choice spent unexpected time: " + pid)
		var loot: Dictionary = Game.run.explore.spots[site_idx].get("loot", {})
		if pid == "rice_ruin":
			check(Inv.count(loot, "rice") == 2 and Inv.count(loot, "millet") == 1, "Rice choice did not produce promised supplies")
		else:
			check(Inv.count(loot, "salve") == 1 and Inv.count(loot, "plague_powder") == 1, "Pharmacy choice did not produce promised supplies")
		check(main.has_modal("explore_loot"), "Site search did not open loot: " + pid)
		if main.has_modal("explore_loot"):
			main.close_modal("explore_loot")
			await frames()
			var after := int(Game.run.t)
			await key(KEY_E)
			check(main.has_modal("explore_loot") and int(Game.run.t) == after, "Reopening did not preserve searched container")
			main.close_modal("explore_loot")
			await frames()
	check(titles.size() == 2 and titles[0] != titles[1], "Locations did not offer distinct actions")
	# 验证普通情况与上限/下限：反馈必须是实际结算值，不弹空的拾取窗。
	for bounded in [false, true]:
		await enter_point("city_god")
		Game.run.attrs.mood = 100.0 if bounded else 50.0
		Game.run.explore.exposure = 0 if bounded else 20
		var old_mood := State.attr(Game.run, "mood")
		var old_exposure := int(Game.run.explore.exposure)
		messages.clear()
		await key(KEY_E)
		await click(option_button("site"))
		var expected := "留下供物 · 心情 %d → %d（含耗时变化） · 阳气外泄 %d → %d" % [old_mood, State.attr(Game.run, "mood"), old_exposure, int(Game.run.explore.exposure)]
		check(expected in messages, "Offering feedback does not report actual values")
		check(not main.has_modal("explore_loot"), "Offering opened an empty loot modal")
		check(Game.run.explore.spots[site_idx].done, "Offering did not complete")
	await enter_point("city_god")
	Game.run.t = 5 * 1440 + 885
	var interrupted: Dictionary = Game.run.explore
	var mood := State.attr(Game.run, "mood")
	messages.clear()
	await key(KEY_E)
	await click(option_button("site"))
	await frames(20)
	check(not interrupted.spots[site_idx].done and not interrupted.get("site_used", false), "Curfew awarded an incomplete offering")
	check(State.attr(Game.run, "mood") <= mood, "Curfew granted offering mood before completion")
	check(Game.run.explore.is_empty() and Game.screen == "post", "Interrupted curfew did not return home")
	check(not main.has_modal("explore_loot"), "Interrupted action opened loot")
	var reported_interruption := false
	for message in messages:
		if "未完成" in message: reported_interruption = true
	check(reported_interruption, "Interrupted action lacks explanation")
	print("Site choice UI: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	Game.toast.disconnect(remember_toast)
	main.queue_free()
	await frames()
	get_tree().quit(1 if failed else 0)
