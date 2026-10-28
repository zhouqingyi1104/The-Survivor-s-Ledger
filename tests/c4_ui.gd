extends Node
## Real viewport interaction. Run with isolated APPDATA and LOCALAPPDATA.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Post = preload("res://scripts/core/post.gd")
const Director = preload("res://scripts/core/director.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var main: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func frames(n := 8) -> void:
	for i in n:
		await get_tree().process_frame

func click(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(3)

func key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(3)

func scroll_down(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.position = p
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(3)

func button(prefix: String, root: Node) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.text.begins_with(prefix):
			return b
	return null

func pick_spot(target: Vector3, id: String) -> Vector2:
	var screen: Control = main._screen
	var center: Vector2 = screen.rig.cam.unproject_position(target)
	var bounds := get_viewport().get_visible_rect().grow(-10)
	for dx in range(-28, 29, 4):
		for dy in range(-28, 29, 4):
			var p := center + Vector2(dx, dy)
			if bounds.has_point(p) and str(screen.world.pick(screen.rig.cam, p).get("spot", "")) == id:
				return p
	return Vector2(-1, -1)

func open_expansion(action: String) -> bool:
	var screen: Control = main._screen
	var bench := Home.core(Game.run, "bench")
	screen.player.global_position = Home.stand(bench)
	screen.rig.snap()
	await frames(8)
	var p := pick_spot(Vector3(float(bench.x), 0.45, float(bench.z)), "f_%d" % int(bench.uid))
	if not check(p.x >= 0, "工作台不可拾取"): return false
	await click(p)
	var entry := button("东侧院扩建", screen._menu)
	if not check(entry != null and not entry.disabled, "工作台没有可用的东侧院扩建入口"): return false
	await click(entry.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 12000
	while not screen.modal_open() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not check(screen.modal_open(), "未打开扩建弹窗"): return false
	var b := button(action, main)
	if not check(b != null and not b.disabled, "扩建弹窗缺少可用按钮：" + action): return false
	await click(b.get_global_rect().get_center())
	return true

func choose_chair() -> bool:
	var screen: Control = main._screen
	var bench := Home.core(Game.run, "bench")
	screen.player.global_position = Home.stand(bench)
	screen.rig.snap()
	await frames(8)
	var p := pick_spot(Vector3(float(bench.x), 0.45, float(bench.z)), "f_%d" % int(bench.uid))
	if not check(p.x >= 0, "添置家具前工作台不可拾取"): return false
	await click(p)
	var entry := button("添置家具", screen._menu)
	if not check(entry != null and not entry.disabled, "工作台缺少添置家具入口"): return false
	await click(entry.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 12000
	while not main.has_modal("furnish") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not check(main.has_modal("furnish"), "未打开添置家具弹窗"): return false
	var modal: Control = main._modals["furnish"]
	var name_label: Label = null
	for label in modal.find_children("*", "Label", true, false):
		if label.text == "圈椅":
			name_label = label
			break
	if not check(name_label != null, "添置家具弹窗中没有圈椅"): return false
	var card: Node = name_label
	var choose: Button = null
	while card != modal:
		card = card.get_parent()
		choose = button("去摆", card)
		if choose != null: break
	if not check(choose != null and not choose.disabled, "圈椅卡片没有可用的去摆按钮"): return false
	# A button outside the window or a clipped scroll area cannot be clicked by a player.
	var scroll: ScrollContainer = null
	var ancestor: Node = choose.get_parent()
	while ancestor != modal:
		if ancestor is ScrollContainer:
			scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	if scroll != null:
		for i in 80:
			if scroll.get_global_rect().has_point(choose.get_global_rect().get_center()): break
			await scroll_down(scroll.get_global_rect().get_center())
	var on_screen := get_viewport().get_visible_rect().has_point(choose.get_global_rect().get_center())
	if scroll != null: on_screen = on_screen and scroll.get_global_rect().has_point(choose.get_global_rect().get_center())
	if not check(on_screen, "圈椅去摆按钮在可见区域外，玩家无法点击"): return false
	await click(choose.get_global_rect().get_center())
	if Game.placing != "armchair" or main.has_modal("furnish"):
		print("C4 chair diagnostic: placing=", Game.placing, " modal=", main.has_modal("furnish"), " button=", choose.get_global_rect(), " scroll=", scroll.get_global_rect() if scroll != null else Rect2(), " scroll_y=", scroll.scroll_vertical if scroll != null else -1)
		if OS.get_environment("C4_FAIL_SHOT") != "":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(OS.get_environment("C4_FAIL_SHOT"))
	return check(Game.placing == "armchair" and Game.moving_uid == -1 and not main.has_modal("furnish"), "点击圈椅去摆未进入摆放")

func advance_work() -> void:
	var remaining := int(Game.run.busy.get("end", Game.run.t)) - int(Game.run.t)
	if remaining > 0: Post.advance(Game.run, remaining)
	Game.refresh()
	await frames(8)

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func ground_at(target: Vector3) -> Dictionary:
	var screen: Control = main._screen
	var p: Vector2 = screen.rig.cam.unproject_position(target)
	if not get_viewport().get_visible_rect().grow(-10).has_point(p): return {}
	var hit: Dictionary = screen.world.pick(screen.rig.cam, p)
	if not hit.has("ground"): return {}
	return {"screen": p, "ground": hit.ground}

func move_back_from_side() -> void:
	var screen: Control = main._screen
	var chairs := Home.list(Game.run, "armchair")
	if not check(not chairs.is_empty(), "读档后没有可挪动的侧院家具"): return
	var chair: Dictionary = chairs[-1]
	var uid := int(chair.uid)
	screen.player.global_position = Vector3(12.5, 0, 4.8)
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(Vector3(float(chair.x), 0.45, float(chair.z)), "f_%d" % uid)
	if not check(p.x >= 0, "侧院家具无法实际拾取"): return
	await click(p)
	var move := button("挪位", screen._menu)
	if not check(move != null and not move.disabled, "侧院家具没有挪位入口"): return
	await click(move.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 12000
	while Game.moving_uid != uid and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not check(Game.moving_uid == uid, "侧院家具没有进入挪位预览"): return
	screen.player.global_position = Vector3(6.0, 0, 4.0)
	screen.rig.snap()
	await frames(10)
	var destination := {}
	for z in range(8, 25):
		if not destination.is_empty(): break
		for x in range(2, 35):
			var pt := Vector3(x * 0.25, 0, z * 0.25)
			var xy: Vector2 = screen.rig.cam.unproject_position(pt)
			if not get_viewport().get_visible_rect().grow(-20).has_point(xy): continue
			var hit: Dictionary = screen.world.pick_move_ground(screen.rig.cam, xy, uid)
			if not hit.has("ground"): continue
			var g: Vector3 = hit.ground
			if screen.world.move_spot_block(Game.run, uid, g.x, g.z, Game.placing_rot) == "":
				destination = {"screen": xy, "ground": g}
				break
	if not check(not destination.is_empty(), "原院没有可点击的合法挪回位置"): return
	await click(destination.screen)
	var moved := Home.find(Game.run, uid)
	check(Game.moving_uid == -1 and float(moved.get("x", 100)) < 10.0, "家具未通过鼠标挪回原院")

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://c4_ui_save.json"
	Game.meta_path = "user://c4_ui_meta.json"
	Game.memory_path = "user://c4_ui_memory.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.home.wood = 100
	Game.run.home.nails = 100
	Game.run.rebirths_left = 1
	var old_run: Dictionary = Game.run.duplicate(true)
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	await frames(45)
	var screen: Control = main._screen
	check(Expansion.stage(Game.run) == "survey", "旧状态应从查勘开始")
	check(Home.spot_block(Game.run, "armchair", 14.25, 3.5, 0) != "", "未完工允许侧院摆放")
	if not await open_expansion("查勘清理"):
		get_tree().quit(1); return
	check(str(Game.run.busy.get("kind", "")) == "expansion_clear", "清理未产生施工工时")
	check(Expansion.stage(Game.run) == "survey", "清理完成前已开放")
	await advance_work()
	check(Expansion.stage(Game.run) == "cleared", "清理完成后状态未改变")
	var wood := int(Game.run.home.wood)
	var nails := int(Game.run.home.nails)
	if not await open_expansion("备料"):
		get_tree().quit(1); return
	check(Expansion.stage(Game.run) == "ready", "备料后状态不对")
	check(int(Game.run.home.wood) == wood - 8 and int(Game.run.home.nails) == nails - 4, "备料未按成本扣除一次")
	# Persist unfinished state and verify it does not expose the side yard.
	var written: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	if check(bool(written.ok) and Game.continue_game(), "备料中存读档失败"):
		await frames(8)
		check(Expansion.stage(Game.run) == "ready", "读档丢失备料状态")
		check(Home.spot_block(Game.run, "armchair", 14.25, 3.5, 0) != "", "备料后却提前开放侧院")
	# Trigger an actual wave checkpoint while construction is in progress.
	Game.run.pday = 2
	Game.run.t = Post.DAY + Post.WAVE_AT - 10
	Game.run.night_policy = "hold"
	if not await open_expansion("开始施工"):
		get_tree().quit(1); return
	check(str(Game.run.busy.get("kind", "")) == "expansion_build", "施工没有实际工期")
	var stop := Post.advance(Game.run, 10)
	check(stop == "wave" and Game.run.busy.is_empty(), "尸潮没有中断施工：" + stop)
	check(Expansion.stage(Game.run) == "ready", "中断施工却完成或丢失备料")
	check(int(Game.run.home.wood) == wood - 8 and int(Game.run.home.nails) == nails - 4, "中断施工改变已备材料")
	# Resume on an ordinary daytime without advancing or claiming a battle result.
	Game.run.wave_due = false
	Game.run.pday = 1
	Game.run.t = 200
	Game.run.attrs.energy = 100
	Game.refresh()
	if not await open_expansion("开始施工"):
		get_tree().quit(1); return
	check(int(Game.run.home.wood) == wood - 8 and int(Game.run.home.nails) == nails - 4, "续工重复扣料")
	check(not Expansion.complete(Game.run), "施工计时结束前已开放")
	await advance_work()
	check(Expansion.complete(Game.run), "施工结束后未完工")
	await frames(30)
	if OS.get_environment("C4_SHOT") != "":
		screen.player.global_position = Vector3(6.0, 0, 4.5)
		screen.rig.dist = 26.0
		screen.rig.snap()
		await frames(12)
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(OS.get_environment("C4_SHOT"))
		screen.rig.dist = 17.0
	# Check actual movement from the old yard across the opened wall, not arrived signal alone.
	screen.player.global_position = Vector3(8.5, 0, 4.5)
	screen.rig.snap()
	await frames(10)
	var target := Vector3(14.25, 0, 4.5)
	var pick := ground_at(target)
	if check(not pick.is_empty(), "侧院地面无法鼠标拾取"):
		await click(pick.screen)
		var deadline := Time.get_ticks_msec() + 12000
		while screen.player.is_walking() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(flat(screen.player.global_position, pick.ground) < 0.8, "人物未实际穿过旧墙口到达侧院：%s" % screen.player.global_position)
	# Open the real furnishing dialog and click the chair card before choosing ground.
	if not await choose_chair():
		get_tree().quit(1); return
	screen.player.global_position = Vector3(12.0, 0, 4.5)
	screen.rig.snap()
	await frames(8)
	var place := ground_at(Vector3(14.25, 0, 3.5))
	if check(not place.is_empty(), "侧院摆放目标无法拾取"):
		await click(place.screen)
		check(Game.placing == "" and str(Game.run.busy.get("kind", "")) == "furnish", "鼠标点击未启动侧院家具建造")
		await advance_work()
		var chairs := Home.list(Game.run, "armchair")
		check(not chairs.is_empty() and float(chairs[-1].x) > 10.2, "家具未真实落在侧院")
	# Persist completed area and furniture, then rewind to pre-construction snapshot.
	written = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	if check(bool(written.ok) and Game.continue_game(), "完工存读档失败"):
		await frames(20)
		check(Expansion.complete(Game.run) and not Home.list(Game.run, "armchair").is_empty(), "读档丢失侧院或家具")
		await move_back_from_side()
		if check(Game.continue_game(), "挪回后重读侧院存档失败"):
			await frames(12)
			var restored := Home.list(Game.run, "armchair")
			check(not restored.is_empty() and float(restored[-1].x) > 10.2, "重读未恢复侧院家具位置")
		screen.player.global_position = Vector3(14.0, 0, 4.5)
		await frames(4)
		Game.rewind()
		await frames(20)
		check(not Expansion.complete(Game.run) and Home.list(Game.run, "armchair").is_empty(), "回溯未恢复原院界和家具")
		check(Home.spot_block(Game.run, "armchair", 14.25, 3.5, 0) != "", "回溯后仍能在侧院摆放")
		check(screen.player.global_position.x < 10.2, "侧院中回溯后人物被困在墙外：%s" % screen.player.global_position)
		screen.player.global_position = Vector3(8.5, 0, 4.5)
		await frames(8)
		screen.player.walk_to(Vector3(14.25, 0, 4.5))
		var until := Time.get_ticks_msec() + 12000
		while screen.player.is_walking() and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		check(screen.player.global_position.x < 10.2, "回溯后仍能穿过原院墙：%s" % screen.player.global_position)
		screen.player.stop()
		screen.player.walk_to(Vector3(0, 0, 4.5))
		until = Time.get_ticks_msec() + 12000
		while screen.player.is_walking() and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		check(flat(screen.player.global_position, Vector3(0, 0, 4.5)) < 0.8, "回院后无法正常走动")
		# Same-screen load of an old save while the player stands in the side yard.
		if check(Game.continue_game(), "重读完工存档失败"):
			await frames(20)
			screen.player.global_position = Vector3(14.0, 0, 4.5)
			await frames(4)
			var old_path := "user://c4_ui_old.json"
			var old_save: Dictionary = SaveFile.write(old_path, {"run": old_run, "snapshots": {}})
			Game.save_path = old_path
			if check(bool(old_save.ok) and Game.continue_game(), "同屏加载旧档失败"):
				await frames(20)
				check(not Expansion.complete(Game.run) and screen.player.global_position.x < 10.2, "侧院中读旧档将人物留在墙外")
				screen.player.walk_to(Vector3(0, 0, 4.5))
				until = Time.get_ticks_msec() + 12000
				while screen.player.is_walking() and Time.get_ticks_msec() < until:
					await get_tree().process_frame
				check(flat(screen.player.global_position, Vector3(0, 0, 4.5)) < 0.8, "读旧档回院后无法正常走动")
			SaveFile.forget(old_path)
			Game.save_path = "user://c4_ui_save.json"
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C4 viewport: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
