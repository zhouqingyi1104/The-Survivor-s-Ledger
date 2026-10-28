extends Node
## Real viewport C5 contract. Run with isolated APPDATA/LOCALAPPDATA and save paths.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
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
		push_error("C5 UI: " + message)
	return ok

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func click(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(4)

func key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(4)

func button(prefix: String, root: Node) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.text.begins_with(prefix): return b
	return null

func pick_spot(target: Vector3, id: String) -> Vector2:
	var screen: Control = main._screen
	var center: Vector2 = screen.rig.cam.unproject_position(target)
	var bounds := get_viewport().get_visible_rect().grow(-10)
	for dx in range(-36, 37, 4):
		for dy in range(-36, 37, 4):
			var p := center + Vector2(dx, dy)
			if bounds.has_point(p) and str(screen.world.pick(screen.rig.cam, p).get("spot", "")) == id: return p
	return Vector2(-1, -1)

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func walk(target: Vector3, label: String) -> void:
	var screen: Control = main._screen
	screen.player.walk_to(target)
	var until := Time.get_ticks_msec() + 12000
	while screen.player.is_walking() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(flat(screen.player.global_position, target) < 0.9, label + " 未实际到达 " + str(screen.player.global_position))

func open_spot(id: String) -> bool:
	var screen: Control = main._screen
	var info: Dictionary = screen.world.spot_info(id)
	if not check(not info.is_empty(), "缺少入口 " + id): return false
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(info.tag, id)
	if not check(p.x >= 0, "入口不可物理拾取 " + id): return false
	await click(p)
	return check(screen._menu.visible, "点击入口未打开菜单 " + id)

func choose(prefix: String) -> bool:
	var screen: Control = main._screen
	var b := button(prefix, screen._menu)
	if not check(b != null and not b.disabled, "缺少可用菜单 " + prefix): return false
	await click(b.get_global_rect().get_center())
	var until := Time.get_ticks_msec() + 12000
	while screen.player.is_walking() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await frames(10)
	return true

func advance_work() -> void:
	var left := int(Game.run.busy.get("end", Game.run.t)) - int(Game.run.t)
	if left > 0: Post.advance(Game.run, left)
	Game.refresh()
	await frames(20)

func shot(name: String) -> void:
	var directory := OS.get_environment("C5_SHOT_DIR")
	if directory == "": return
	await get_tree().create_timer(3.0).timeout
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func choose_furniture(name: String, furniture_id: String) -> bool:
	var screen: Control = main._screen
	if not await open_spot("floor_use"): return false
	if not await choose("添置家具"): return false
	var until := Time.get_ticks_msec() + 12000
	while not main.has_modal("furnish") and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	if not check(main.has_modal("furnish"), "没有家具弹窗"): return false
	var modal: Control = main._modals["furnish"]
	var label: Label
	for candidate in modal.find_children("*", "Label", true, false):
		if candidate.text == name:
			label = candidate
			break
	if not check(label != null, "家具弹窗缺少 " + name): return false
	var card: Node = label
	var b: Button
	while card != modal:
		card = card.get_parent()
		b = button("去摆", card)
		if b != null: break
	if not check(b != null and not b.disabled, name + " 不能摆放"): return false
	var scroll: ScrollContainer
	var ancestor: Node = b.get_parent()
	while ancestor != modal:
		if ancestor is ScrollContainer:
			scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	if scroll != null:
		for i in 80:
			if scroll.get_global_rect().has_point(b.get_global_rect().get_center()): break
			for down in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
				ev.position = scroll.get_global_rect().get_center()
				ev.pressed = down
				get_viewport().push_input(ev)
			await frames(2)
	if not check(get_viewport().get_visible_rect().has_point(b.get_global_rect().get_center()) and (scroll == null or scroll.get_global_rect().has_point(b.get_global_rect().get_center())), name + " 按钮不可见"): return false
	await click(b.get_global_rect().get_center())
	return check(Game.placing == furniture_id and not main.has_modal("furnish"), name + " 未进入摆放")

func place_furniture(name: String, furniture_id: String) -> Dictionary:
	if not await choose_furniture(name, furniture_id): return {}
	var screen: Control = main._screen
	var origin: Vector3 = screen.world.floor_origin()
	screen.player.global_position = origin + Vector3(0, 0, 1.8)
	screen.rig.snap()
	await frames(10)
	for z in range(-8, 9):
		for x in range(-10, 11):
			var candidate := origin + Vector3(x * 0.25, 0, z * 0.25)
			var p: Vector2 = screen.rig.cam.unproject_position(candidate)
			if not get_viewport().get_visible_rect().grow(-20).has_point(p): continue
			var hit: Dictionary = screen.world.pick(screen.rig.cam, p)
			if not hit.has("ground"): continue
			var local: Vector3 = screen.world.to_floor_local(hit.ground)
			if screen.world.build_spot_block(Game.run, furniture_id, hit.ground.x, hit.ground.z, Game.placing_rot) != "": continue
			await click(p)
			if not check(str(Game.run.busy.get("kind", "")) == "furnish", name + " 点击地面未开始安放"): return {}
			await advance_work()
			var items := Home.list(Game.run, furniture_id)
			if not check(not items.is_empty(), name + " 施工后未出现"): return {}
			var f: Dictionary = items[-1]
			check(str(f.get("floor", "")) == Floors.current(Game.run) and absf(float(f.x) - local.x) < 0.4 and absf(float(f.z) - local.z) < 0.4, name + " 楼层归属/坐标错误")
			return f
	check(false, name + " 找不到可点击的合法摆放位置")
	return {}

func open_bench() -> bool:
	var screen: Control = main._screen
	var f := Home.core(Game.run, "bench")
	screen.player.global_position = Home.stand(f)
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(Vector3(float(f.x), 0.45, float(f.z)), "f_%d" % int(f.uid))
	if not check(p.x >= 0, "工作台不可拾取"): return false
	await click(p)
	return check(screen._menu.visible, "工作台菜单未打开")

func drink_from_room() -> void:
	if not await open_spot("floor_use"): return
	if not await choose("打开存货"): return
	if not check(main.has_modal("inventory"), "整理台未打开存货"): return
	var modal: Control = main._modals["inventory"]
	var tab := button("水", modal)
	if not check(tab != null, "存货没有水分类"): return
	await click(tab.get_global_rect().get_center())
	var drink := button("喝", modal)
	if not check(drink != null and not drink.disabled, "存货无法喝水"): return
	var before := int(Game.run.home.get("water", 0))
	Game.run.attrs.water = 30
	await click(drink.get_global_rect().get_center())
	check(int(Game.run.home.get("water", 0)) == before - 1 and float(Game.run.attrs.water) > 30, "整理台使用存货未真实扣水并恢复水分")
	await key(KEY_ESCAPE)

func inspect_furniture(f: Dictionary) -> void:
	if f.is_empty(): return
	var screen: Control = main._screen
	var p3: Vector3 = screen.world.floor_origin() + Vector3(float(f.x), 0.45, float(f.z))
	screen.player.global_position = screen.world.floor_origin() + Home.stand(f)
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(p3, "f_%d" % int(f.uid))
	if not check(p.x >= 0, "本层家具无法拾取"): return
	await click(p)
	var b := button("挪位", screen._menu)
	check(screen._menu.visible and b != null and not b.disabled, "本层家具不可交互")
	await key(KEY_ESCAPE)

func inspect_pot(f: Dictionary, other: Dictionary) -> void:
	var screen: Control = main._screen
	var p3: Vector3 = screen.world.floor_origin() + Vector3(float(f.x), 0.45, float(f.z))
	screen.player.global_position = screen.world.floor_origin() + Home.stand(f)
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(p3, "f_%d" % int(f.uid))
	if not check(p.x >= 0, "本层花盆不可拾取"): return
	await click(p)
	if not await choose("播种"): return
	if not check(main.has_modal("garden"), "点击本层花盆未打开菜畦"): return
	var modal: Control = main._modals["garden"]
	var this_found := false
	var other_found := false
	var ground_found := false
	for label in modal.find_children("*", "Label", true, false):
		this_found = this_found or label.text.begins_with("花盆 #%d" % int(f.uid))
		other_found = other_found or label.text.begins_with("花盆 #%d" % int(other.uid))
		ground_found = ground_found or label.text.begins_with("第 ")
	check(this_found and not other_found and not ground_found, "菜畦弹窗未按当前空间筛选花盆和院内菜畦")
	var plant := button("种白菜", modal)
	if check(plant != null and not plant.disabled, "花盆没有可用播种按钮"):
		var other_before := ""
		for plot in Game.run.plots:
			if int(plot.get("pot", -1)) == int(other.uid): other_before = str(plot.crop)
		await click(plant.get_global_rect().get_center())
		var own_crop := ""
		var other_crop := ""
		for plot in Game.run.plots:
			if int(plot.get("pot", -1)) == int(f.uid): own_crop = str(plot.crop)
			if int(plot.get("pot", -1)) == int(other.uid): other_crop = str(plot.crop)
		check(own_crop == "cabbage" and other_crop == other_before, "播种影响了其他空间的花盆")
	await key(KEY_ESCAPE)

func check_room_shortcuts() -> void:
	var screen: Control = main._screen
	var before: Vector3 = screen.player.global_position
	var water_before := int(Game.run.home.get("water", 0))
	Game.run.attrs.energy = 10
	await key(KEY_N)
	await frames(10)
	check(not Game.run.sleeping and Game.run.busy.is_empty() and flat(screen.player.global_position, before) < 0.8, "室内快捷就寝/小憩越层或启动")
	var draw := button("打水", screen)
	check(draw == null or draw.disabled, "室内仍展示可用的院井打水快捷项")
	check(int(Game.run.home.get("water", 0)) == water_before and not bool(Game.run.well_used), "室内快捷行为改变院井资源")
	Game.run.attrs.energy = 100

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://c5_ui_save.json"
	Game.meta_path = "user://c5_ui_meta.json"
	Game.memory_path = "user://c5_ui_memory.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.home.wood = 100
	Game.run.home.nails = 100
	Game.run.home.water = 10
	Game.run.rebirths_left = 1
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	var old_run: Dictionary = Game.run.duplicate(true)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(240).timeout.connect(func(): get_tree().quit(1))
	await frames(50)
	var screen: Control = main._screen
	if not await open_bench(): get_tree().quit(1); return
	var cellar_entry := button("进入地窖", screen._menu)
	check(cellar_entry == null or cellar_entry.disabled, "没有地窖资格时入口可用")
	await key(KEY_ESCAPE)
	Game.run.facilities.append("cellar")
	Game.refresh()
	await frames(15)
	await shot("cellar_entrance")
	var wood_before := int(Game.run.home.wood)
	var silver_before := int(Game.run.silver)
	if not await open_spot("floor_cellar"): get_tree().quit(1); return
	if not await choose("进入地窖"): get_tree().quit(1); return
	if not check(Floors.current(Game.run) == "cellar" and screen.world._floor == "cellar", "旧资格不能进入地窖"): get_tree().quit(1); return
	check(int(Game.run.home.wood) == wood_before and int(Game.run.silver) == silver_before, "已买地窖再次收费")
	var clock_before := int(Game.run.t)
	var water_before := float(Game.run.attrs.water)
	Game.speed = 1
	await get_tree().create_timer(1.5).timeout
	Game.speed = 0
	check(int(Game.run.t) > clock_before and float(Game.run.attrs.water) < water_before, "地窖正常运行时钟/水分未推进")
	await walk(screen.world.floor_origin() + Vector3(0, 0, -1.9), "地窖整理台")
	await drink_from_room()
	var cellar_f := await place_furniture("圈椅", "armchair")
	await inspect_furniture(cellar_f)
	await shot("cellar_day")
	var saved_t := int(Game.run.t)
	Game.run.t = Post.DUSK_AT + 120
	screen.world.set_time(Game.run)
	await shot("cellar_night")
	Game.run.t = saved_t
	screen.world.set_time(Game.run)
	if not await open_spot("floor_exit"): get_tree().quit(1); return
	if not await choose("返回宅院"): get_tree().quit(1); return
	check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard", "地窖返回院内失败")
	if not await open_bench(): get_tree().quit(1); return
	if not await choose("阁楼备料"): get_tree().quit(1); return
	check(Floors.attic_stage(Game.run) == "ready", "阁楼备料未生效")
	if not await open_bench(): get_tree().quit(1); return
	if not await choose("阁楼施工"): get_tree().quit(1); return
	check(str(Game.run.busy.get("kind", "")) == "attic_build", "阁楼未进入施工")
	await advance_work()
	check(Floors.attic_stage(Game.run) == "complete", "阁楼施工未完成")
	screen.player.global_position = screen.world.spot_info("floor_attic").stand
	screen.rig.snap()
	await frames(10)
	await shot("attic_entrance")
	if not await open_spot("floor_attic"): get_tree().quit(1); return
	if not await choose("进入阁楼"): get_tree().quit(1); return
	if not check(Floors.current(Game.run) == "attic" and screen.world._floor == "attic", "阁楼未进入"): get_tree().quit(1); return
	await walk(screen.world.floor_origin() + Vector3(0, 0, -1.9), "阁楼整理台")
	var attic_f := await place_furniture("圈椅", "armchair")
	await inspect_furniture(attic_f)
	await shot("attic_day")
	saved_t = int(Game.run.t)
	Game.run.t = Post.DUSK_AT + 120
	screen.world.set_time(Game.run)
	await shot("attic_night")
	Game.run.t = saved_t
	screen.world.set_time(Game.run)
	check(not cellar_f.is_empty() and not attic_f.is_empty() and int(cellar_f.uid) != int(attic_f.uid), "两层家具身份混淆")
	# Deliberate fixture: one planter on each floor plus the existing outdoor plots.
	# This checks the actual menus and clicks, not whether furnishing is possible.
	Game.run.home.seed_cabbage = 5
	var cellar_pot := Home.add(Game.run, "planter", 2.0, -1.0, 0, "cellar")
	var attic_pot := Home.add(Game.run, "planter", 2.0, -1.0, 0, "attic")
	Game.refresh()
	await frames(20)
	await check_room_shortcuts()
	await inspect_pot(attic_pot, cellar_pot)
	if not await open_spot("floor_exit"): get_tree().quit(1); return
	if not await choose("返回宅院"): get_tree().quit(1); return
	if not await open_bench(): get_tree().quit(1); return
	if not await choose("进入地窖"): get_tree().quit(1); return
	await check_room_shortcuts()
	await inspect_pot(cellar_pot, attic_pot)
	if not await open_spot("floor_exit"): get_tree().quit(1); return
	if not await choose("返回宅院"): get_tree().quit(1); return
	if not await open_bench(): get_tree().quit(1); return
	if not await choose("进入阁楼"): get_tree().quit(1); return
	var saved: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	if check(bool(saved.ok) and Game.continue_game(), "楼层存读失败"):
		await frames(20)
		check(Floors.current(Game.run) == "attic" and str(Home.find(Game.run, int(attic_f.get("uid", -1))).get("floor", "")) == "attic" and str(Home.find(Game.run, int(cellar_f.get("uid", -1))).get("floor", "")) == "cellar", "读档未恢复空间及家具")
		# Loading a different layout of the same room must not bury the player in furniture.
		var same_floor: Dictionary = Game.run.duplicate(true)
		var changed := Home.find(same_floor, int(attic_f.get("uid", -1)))
		changed.x = -2.0
		changed.z = 1.0
		var original_path := Game.save_path
		Game.save_path = "user://c5_ui_same_floor.json"
		screen.player.global_position = screen.world.floor_origin() + Vector3(-2, 0, 1)
		var altered: Dictionary = SaveFile.write(Game.save_path, {"run": same_floor, "snapshots": Game.snapshots})
		if check(bool(altered.ok) and Game.continue_game(), "同层布局存读失败"):
			await frames(20)
			check(flat(screen.player.global_position, screen.world.floor_origin() + Vector3(-2, 0, 1)) > 0.8, "同层读档家具覆盖人物时未安全复位")
			await walk(screen.world.floor_spawn("attic"), "同层读档后行动")
		SaveFile.forget(Game.save_path)
		Game.save_path = original_path
		Game.continue_game()
		await frames(20)
		Game.rewind()
		await frames(20)
		check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard" and not Floors.unlocked(Game.run, "cellar") and Home.list(Game.run, "armchair").is_empty(), "旧快照回溯后未回院/保留了新家具")
		check(flat(screen.player.global_position, screen.world.floor_spawn("courtyard")) < 1.0, "回溯后人物未安全返回")
		if check(Game.continue_game(), "恢复阁楼存档失败"):
			await frames(20)
			Game.run.pday = 1
			Game.run.t = Post.RAID_AT - 1
			Game.run.raid_tonight = true
			screen.advance(1)
			await frames(12)
			check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard" and flat(screen.player.global_position, screen.world.floor_spawn("courtyard")) < 1.0, "溃兵夜袭未强制安全回院")
			check(int(Game.run.t) == Post.RAID_AT, "溃兵夜袭时钟未推进")
			if check(Game.continue_game(), "再次恢复阁楼存档失败"):
				await frames(20)
				Game.run.pday = 2
				Game.run.t = Post.DAY + Post.WAVE_AT - 1
				Game.run.wave_day = 0
				Game.run.night_policy = "hold"
				# Skip the unrelated neighbour quest, whose overdue event would stop
				# time before the checkpoint in this intentionally jumped fixture.
				Game.run.neighbor.stage = "closed"
				screen.advance(1)
				await frames(12)
				check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard" and flat(screen.player.global_position, screen.world.floor_spawn("courtyard")) < 1.0, "尸潮未强制安全回院")
				check(int(Game.run.t) == Post.DAY + Post.WAVE_AT, "尸潮时钟未推进")
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C5 viewport: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
