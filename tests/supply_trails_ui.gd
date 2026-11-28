extends "res://tests/site_journey_ui.gd"
## 用既有的键盘寻路和鼠标输入，走一次从工棚到官仓的旧运单。

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.run = State.new_run("escort", Game.meta, 1034)
	Pre.start_disaster(Game.run)
	Game.run.pday = 7
	Game.run.t = 6 * 1440 + Post.EVENT_AT
	Neighbor.state(Game.run).stage = "closed"
	var nail_count := Inv.count(Game.run.home, "nails")
	Game.go("post")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(12)
	await _journey_to("lumber")
	if failed: return _finish()
	if not await walk("journey:s0"): return _finish()
	await key(KEY_E)
	check(journey_button("trail_action", "mark") == null, "取工牌前不应看见线索")
	await click(journey_button("journey_choice", "careful"))
	var mark := journey_button("trail_action", "mark")
	if not check(mark != null and mark.disabled, "未持铁钉时留记应禁用"): return _finish()
	await click(journey_button("journey_take", "nails"))
	mark = journey_button("trail_action", "mark")
	check(mark != null and not mark.disabled and labels(main._modals.site_journey).contains("粮车车底"), "领钉后能预览去向与选择")
	_capture("木场工牌")
	await click(mark)
	check(journey_button("trail_action", "keep") == null and Inv.count(Game.run.explore.bag, "nails") == 0, "留记后不可再劈牌")
	await key(KEY_ESCAPE)
	if not await walk("exit"): return _finish()
	await key(KEY_E)
	if not check(Game.screen == "post" and Game.run.explore.is_empty(), "真实出口未回家"): return _finish()
	await _journey_to("granary", "粮车车底")
	if failed: return _finish()
	if not await walk("journey:s2"): return _finish()
	await key(KEY_E)
	await click(journey_button("trail_action", "open"))
	_capture("官仓夹箱")
	await click(journey_button("trail_take", "nails"))
	check(Inv.count(Game.run.explore.bag, "nails") == 1 and journey_button("trail_take", "wood") != null, "逐件装入背囊")
	await key(KEY_ESCAPE)
	if not await walk("exit"): return _finish()
	await key(KEY_E)
	check(Game.screen == "post" and Inv.count(Game.run.home, "nails") == nail_count + 1, "真实返程将旧藏送进家中")
	_finish()


func _journey_to(pid: String, directions := "") -> void:
	main._screen.player.position = HomeWorld.SPOTS.gate.stand
	await frames()
	await key(KEY_E)
	var leave: Button
	for button in main._screen._menu.find_children("*", "Button", true, false):
		if button.text.begins_with("出门搜寻"): leave = button
	await click(leave)
	if not check(main.has_modal("explore_pick"), "院门未打开路线图"): return
	var depart: Button
	for button in main._modals.explore_pick.find_children("*", "Button", true, false):
		if button.get_meta("explore_depart", "") == pid: depart = button
	if not check(depart != null and not depart.disabled, pid + "未开放"): return
	if directions != "":
		check(labels(depart.get_parent()).contains(directions), "出门前地图漏掉取货位置")
	await click(depart)
	check(Game.screen == "explore" and Game.run.explore.get("point") == pid, "未抵达" + pid)


func _capture(label: String) -> void:
	var directory := OS.get_environment("SUPPLY_TRAIL_SHOTS")
	if directory != "":
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "实拍写盘")


func _finish() -> void:
	print("Supply trails UI: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
