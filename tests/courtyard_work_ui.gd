extends "res://tests/food_drying_ui.gd"
## 玩家正常镜头和近景各录一次。用现场菜单读船信，晒匾的碰撞、家具挪动与楼层显隐按真实世界检查。
const Home = preload("res://scripts/core/home.gd")
const Story = preload("res://scripts/core/mainline.gd")
var screen: Control
var marks := {}


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 8891)
	Pre.start_disaster(Game.run)
	Post.Neighbor.state(Game.run).stage = "closed"
	Post.Director.state(Game.run).enabled = false
	var run: Dictionary = Game.run
	run.t = 360
	run.home = {"millet": 2, "water": 2, "firewood": 2, "salt": 1, "radish": 3, "lamp_oil": 1}
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(24)
	screen = main._screen
	var world: Node3D = screen.world
	var tray: Node3D = world._dynamic.drying_tray
	var letter: Node3D = world._dynamic.lane_letter
	var stove: Dictionary = Home.core(run, "stove")
	screen.player.global_position = Home.stand(stove)
	screen.rig.snap()
	if not check(letter.get_child_count() == 0 and tray.has_node("woven_tray"), "早期场景应有空匾、无船信"): return
	await photograph("tray-empty", tray)
	if not check(Post.act_drying(run, "start", "grain") == "", "没有铺上杂粮"): return
	world.sync(run)
	await photograph("tray-grain", tray)
	var model_id: int = tray.get_child(0).get_instance_id()
	world.sync(run)
	if not check(model_id == tray.get_child(0).get_instance_id() and tray.find_children("*", "CollisionObject3D", true, false).is_empty(), "库存同步重建了相同晒匾，或晒匾抢了碰撞"): return
	run.t = run.drying_batch.ready
	if not check(Post.act_drying(run, "turn") == "", "翻匾失败"): return
	world.sync(run)
	await photograph("tray-turned", tray)
	run.t = run.drying_batch.ready
	if not check(Post.act_drying(run, "take") == "" and Post.act_drying(run, "start", "radish") == "", "未清空旧批或未铺上萝卜"): return
	world.sync(run)
	await photograph("tray-radish", tray)
	var origin := Vector3(float(stove.x), 0, float(stove.z))
	var original_rotation := int(stove.rot)
	var target := Vector3.ZERO
	for x in range(2, 9):
		for z in range(4, 7):
			if world.move_spot_block(run, stove.uid, x, z, 180) == "":
				target = Vector3(x, 0, z)
				break
		if target != Vector3.ZERO: break
	if not check(target != Vector3.ZERO and Home.move(run, stove.uid, target.x, target.z, 180) == "", "院内没有可摆放灶台的位置"): return
	world.sync(run)
	if not check(tray.position != origin and tray.position.is_equal_approx(target) and is_equal_approx(absf(tray.rotation_degrees.y), 180), "晒匾未随灶台平移旋转"): return
	run.broken.append("stove")
	world.sync(run)
	if not check(tray.get_child_count() == 0, "坏灶仍浮着竹匾"): return
	run.broken.erase("stove")
	stove.x = origin.x
	stove.z = origin.z
	stove.rot = original_rotation
	run.facilities.append("cellar")
	world.set_floor("cellar")
	world.sync(run)
	if not check(not tray.is_visible_in_tree() and not letter.is_visible_in_tree(), "楼内有院中物件"): return
	world.set_floor("courtyard")
	if not check(tray.is_visible_in_tree() and tray.has_node("woven_tray"), "返回后晒匾丢失"): return
	run.t = Story.Lane.OPEN + 240
	run.pday = 1 + int(run.t / Post.DAY)
	screen.player.global_position = world.SPOTS.gate.stand
	screen.rig.snap()
	Game.refresh()
	await frames()
	if not check(letter.get_meta("appearance", "") == "offer", "达到邀约日期仍无布条"): return
	await photograph("gate-offer", letter)
	if not await gate("看看巷口的白布"): return
	if not check(button(main._modals.mainline, "在巷口留灯") != null, "大门入口未打开真实留灯操作"): return
	if not await click_button(main._modals.mainline, "在巷口留灯"): return
	if main.has_modal("mainline"):
		if not await click_button(main._modals.mainline, "合上"): return
	if not check(Post.advance(run, 30) == "" and run.mainline.lane_lantern.stage == "lit", "灯信未用三十分钟点灯"): return
	Game.refresh()
	await frames()
	if not check(letter.get_meta("appearance") == "waiting" and letter.find_children("*", "OmniLight3D", true, false).size() == 1, "未出现独立的信灯"): return
	await photograph("gate-lit", letter)
	run.t = int(run.mainline.lane_lantern.reply_t)
	run.pday += 1
	world.set_time(run)
	if not check(letter.get_meta("appearance") == "reply" and letter.find_children("*", "Label3D", true, false).size() == 1, "次日上午未显出布上回信"): return
	await photograph("gate-reply", letter)
	if not await gate("读船匠的回信"): return
	if not check(button(main._modals.mainline, "腾出西厢") != null or copy(main._modals.mainline).contains("娘走不动了"), "回信内容不符"): return
	if not await click_button(main._modals.mainline, "合上"): return
	run.t = Story.Lane.CLOSE
	world.set_time(run)
	if not check(letter.get_child_count() == 0 and not str(screen.actions_for("gate")).contains("读船匠的回信"), "逾期仍挂着信或保留了菜单"): return
	var dst := OS.get_environment("COURTYARD_WORK_CAPTURE")
	if dst != "":
		var file := FileAccess.open(dst.path_join("cameras.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(marks, "\t"))
	print("[courtyard_work_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func gate(prefix: String) -> bool:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_E
		e.physical_keycode = KEY_E
		e.pressed = down
		get_viewport().push_input(e)
	await frames()
	if not await click_button(screen._menu, prefix): return false
	return check(main.has_modal("mainline"), "大门信件未通向调查与出路")


func photograph(key: String, prop: Node3D) -> void:
	var dst := OS.get_environment("COURTYARD_WORK_CAPTURE")
	if dst == "": return
	var stove := key.begins_with("tray-")
	var focus := prop.to_global(Vector3(-0.29, 1.43, 0)) if stove else prop.to_global(Vector3(0, -0.23, -1.24))
	await frames()
	var camera: Camera3D = screen.rig.cam
	var hud_pos := camera.unproject_position(focus)
	RenderingServer.force_draw()
	var player_image := get_viewport().get_texture().get_image()
	player_image.save_png(dst.path_join(key + "-player.png"))
	# 同一帧关掉实物再绘制。中心附近须有本件道具造成的像素变化，排除墙体或屋檐全遮挡。
	prop.hide()
	RenderingServer.force_draw()
	var without := get_viewport().get_texture().get_image()
	prop.show()
	var changed := 0
	var region := Rect2i(Vector2i(hud_pos) - Vector2i(32, 32), Vector2i(64, 64)).intersection(Rect2i(Vector2i.ZERO, without.get_size()))
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var a := player_image.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.04: changed += 1
	if not check(changed > 30, "默认玩家镜头看不见 " + key + "，局部变化像素：" + str(changed)): return
	var portrait := Camera3D.new()
	screen.world.add_child(portrait)
	portrait.fov = 32
	portrait.global_position = prop.to_global(Vector3(0.72, 2.65, 2.06)) if stove else focus + Vector3(0.97, 0.31, -2.60)
	portrait.look_at(focus, Vector3.UP)
	portrait.current = true
	screen.hud.hide()
	screen._tag_layer.hide()
	screen.player.hide()
	await frames()
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(dst.path_join(key + "-detail.png"))
	marks[key] = {"player_target": [hud_pos.x, hud_pos.y], "visible_pixels": changed, "player_eye": str(camera.global_position), "close_eye": str(portrait.global_position), "focus": str(focus)}
	screen.hud.show()
	screen._tag_layer.show()
	screen.player.show()
	camera.current = true
	portrait.queue_free()
	await frames()
