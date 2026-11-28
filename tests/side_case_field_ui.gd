extends "site_journey_ui.gd"
## 从应约、实际步行取证一直走到院里合办，再验后案换线。可选读入已有百日游玩卷。

const Cases = preload("res://scripts/core/side_cases.gd")
const CaseBook = preload("res://scripts/ui/dialogs/side_cases.gd")
const Pack = preload("res://scripts/core/save_pack.gd")
const Visitor = preload("res://scripts/world/chronicle_visitor.gd")
const Ruins = preload("res://scripts/world/ruin_world.gd")
const Station = preload("res://scripts/world/side_case_scene.gd")
const WALK_KEYS := {KEY_W: "move_up", KEY_S: "move_down", KEY_A: "move_left", KEY_D: "move_right"}
var held_walk: Key = KEY_NONE


func key_event(code: Key, pressed: bool) -> void:
	if code in WALK_KEYS:
		held_walk = code if pressed else KEY_NONE
	super.key_event(code, pressed)
	Input.flush_buffered_events()


func _physics_process(_delta: float) -> void:
	# Windows 切走焦点会清空引擎的按住状态。保留真实 WASD 事件与胶囊碰撞来走路。
	if held_walk != KEY_NONE and not Input.is_action_pressed(WALK_KEYS[held_walk]):
		key_event(held_walk, true)


func click(button: Button) -> void:
	if not check(is_instance_valid(button) and not button.disabled, "界面没有可用按钮"): return
	var clip := get_viewport().get_visible_rect()
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await frames(3)
			clip = clip.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	var visible := clip.intersection(button.get_global_rect())
	if not check(visible.has_area(), "按钮滚动后仍被裁切：" + button.text): return
	var motion := InputEventMouseMotion.new()
	motion.position = visible.get_center()
	get_viewport().push_input(motion)
	# 同一次点击的按下与抬起打在同一可见像素，避免两者之间窗口收到别处的光标移动。
	for down in [true, false]:
		var edge := InputEventMouseButton.new()
		edge.button_index = MOUSE_BUTTON_LEFT
		edge.position = motion.position
		edge.pressed = down
		get_viewport().push_input(edge)
	await frames(6)


func button_named(modal: String, meta: String, value: String) -> Button:
	if not main.has_modal(modal): return null
	for button in main._modals[modal].find_children("*", "Button", true, false):
		if str(button.get_meta(meta, "")) == value: return button
	return null


func shot(filename: String) -> void:
	var folder := OS.get_environment("SIDE_CASE_SHOTS")
	if folder == "": return
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	check(picture.save_png(folder.path_join(filename + ".png")) == OK, "无法保存实机画面 " + filename)


func zoom_to_work() -> void:
	var rig = main._screen.rig
	if Game.screen == "post":
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
		motion.relative = Vector2(450, 33)
		motion.position = get_viewport().get_visible_rect().size * Vector2(0.55, 0.6)
		get_viewport().push_input(motion)
	for step in 20:
		if rig.dist <= 8.5: break
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = get_viewport().get_visible_rect().size * Vector2(0.55, 0.61)
		get_viewport().push_input(wheel)
	await frames(8)


func prepare() -> bool:
	var source := OS.get_environment("SIDE_CASE_OLD_SAVE")
	if source == "":
		Game.run = State.new_run("escort", Game.meta, 5000, "normal", [], [], [], true)
		Pre.start_disaster(Game.run)
		Game.run.pday = 81
		Game.run.t = 80 * Post.DAY
		Game.run.hundred_days.choices["blank_name"] = "write"
	else:
		var imported := Pack.parse(FileAccess.get_file_as_string(source))
		if not check(imported.ok, "旧卷导入失败：" + str(imported.note)): return false
		Game.run = imported.data.run
	if not check(Game.run.pday == 81 and Game.run.hundred_days.choices.get("blank_name") == "write", "请提供保留写真名路线的第81日晨卷"): return false
	Post.advance(Game.run, Post.EVENT_AT)
	if Game.run.pending_event != "":
		var morning := Events.entry(Game.run)
		for i in morning.choices.size():
			if morning.choices[i].get("req", {}).is_empty():
				Events.choose(Game.run, i)
				break
		Game.run.event_result = ""
	return check(Game.run.pending_event == "" and Cases.view(Game.run, "shadow_show").route.site == "city_god", "旧卷在应约前应走柳纫的城隍庙线")


func outing(id: String, pid: String, person: String, choice_id: String) -> void:
	CaseBook.open(id)
	await frames()
	await click(button_named("street_cases", "side_case_accept", id))
	var page := Cases.active(Game.run)
	if not check(page.get("id") == id and page.route.site == pid and page.person == person, id + " 应约后同行人和路线不符"): return
	await key(KEY_ESCAPE)
	Dialogs.explore_pick()
	await frames()
	await click(button_named("explore_pick", "explore_depart", pid))
	if not check(Game.screen == "explore" and Game.run.explore.get("point") == pid, "出门地图按钮未抵达 %s，实际地点 %s，界面 %s，面板 %s；%s" % [pid, Game.run.explore.get("point"), Game.screen, str(main._modals.keys()), str(messages)]): return
	var idx := -1
	for i in Game.run.explore.spots.size():
		if Game.run.explore.spots[i].get("side_case") == id: idx = i
	if not check(idx >= 0, "遗迹缺少证物"): return
	if not await walk("spot:%d" % idx): return
	await zoom_to_work()
	var scene = main._screen.world._spots[idx].case_scene
	if not check(scene.partner.kind == Visitor.PEOPLE[person][1] and scene.evidence.is_visible_in_tree(), "现场缺少正确的同伴或证物"): return
	await key(KEY_E)
	if not check(main.has_modal("side_case_site") and labels(main._modals.side_case_site).contains(person), "现场 E 没有显示搭档"): return
	await shot(id + "-site")
	await click(button_named("side_case_site", "side_case_search", id))
	if not check(Game.run.busy.get("kind") == "case_search" and scene.partner.working and main._screen.player.figure.working and not main._screen.player.enabled, "现场调查没有等工时或角色没有一同动手"): return
	await frames(180)
	await shot(id + "-working")
	# 只在已看到开工画面后拨完这段游戏时钟。
	Game.act(func(): return Post.advance(Game.run, int(Game.run.busy.end) - int(Game.run.t)))
	await frames()
	if not check(Game.run.explore.get("case_cargo") == id and not scene.partner.working, "调查到点没有带上证物"): return
	await key(KEY_E)
	if not check(main.has_modal("side_case_site") and labels(main._modals.side_case_site).contains(page.route.clue), "无法在原地重读线索"): return
	await key(KEY_ESCAPE)
	if not await walk("exit"): return
	await key(KEY_E)
	if not check(Game.screen == "post" and Cases.view(Game.run, id).stage == "returned", "出口返程未将物证带入宅院"): return
	CaseBook.open(id)
	await frames()
	await shot(id + "-home-record")
	await click(button_named("street_cases", "side_case_finish", choice_id))
	for tick in 240:
		if Game.run.busy.get("kind") == "case_work": break
		await get_tree().physics_frame
	if not check(Game.run.busy.get("kind") == "case_work", "结办按钮未让玩家走近并开工"): return
	var work: Dictionary = Game.run.busy.data
	var station: Node3D = main._screen.world._dynamic.case_work.get_child(0)
	if not check(station.partner.kind == Visitor.PEOPLE[work.person][1] and station.partner.working, "宅院没有对应的合办人"): return
	check(work.person == "石榴" and main._screen.player.figure.working, "院中没有和结办选项指名的人一起做事")
	var from_desk: Vector3 = station.global_position - main._screen.player.global_position
	check(Vector2(from_desk.x, from_desk.z).length() < 1.85, "街坊与主角没有在同一工作台边")
	check(station.global_position.distance_to(Visitor.PLACE) > 2.5, "合办伙伴撞上来信访客")
	await zoom_to_work()
	await frames(60)
	await shot(id + "-home-working")
	Game.act(func(): return Post.advance(Game.run, int(Game.run.busy.end) - int(Game.run.t)))
	await frames()
	check(Cases.completed_choice(Game.run, id) == choice_id and main._screen.world._dynamic.case_work.get_child_count() == 0, "合办结束后未落卷或伙伴未离场")


## 两趟实走之外，把同行桌放入每一种实际遗迹格局，用主角胶囊扫出从入口到证物的路。
func check_layouts() -> void:
	var props := Station.ANIMATIONS.keys()
	for i in Ruins.FOOTPRINTS.size():
		var pid: String = Ruins.FOOTPRINTS.keys()[i]
		Game.run = State.new_run("escort", Game.meta, 5000, "normal", [], [], [], true)
		Pre.start_disaster(Game.run)
		Explore.begin(Game.run, pid)
		var ex: Dictionary = Game.run.explore
		var original := Ruins.new()
		original.point = pid
		original._choose_positions(ex.spots)
		var unchanged := original._spot_positions.duplicate()
		original.free()
		var sample := {"side_case": "layout", "person": "桂娘", "prop": props[i], "name": "查访", "done": false}
		ex.spots.push_front(sample)
		Game.go("explore")
		await frames(6)
		var world = main._screen.world
		check(world._spot_positions.slice(1) == unchanged, pid + " 查访挪动了既有搜点")
		check(world._feature_markers.visible and world.nearest_feature(world.feature_positions.clue_0) == "clue_0", pid + " 普通搜寻时原机关线索消失")
		check(not route("spot:0").is_empty(), pid + " 查访点被普通搜点、其他交互或墙体挡住")
		ex.spots = [sample]
		ex.only_investigate = true
		Game.go("explore")
		await frames(6)
		world = main._screen.world
		check(not world._feature_markers.visible and world.nearest_feature(world.feature_positions.clue_0) == "" and world._gate_body.get_collision_layer_value(1), pid + " 专程查访时仍提示普通机关，或门墙消失")
		check(not route("spot:0").is_empty(), pid + " 专程查访没有可走通的路")
	# 前八个现场已实际创建，余下的一类仍检查能渲染出实体。
	var last := Station.new()
	main._screen.world.add_child(last)
	last.setup({"person":"秋禾", "prop":props.back()})
	check(not last.evidence.find_children("*", "MeshInstance3D", true, false).is_empty(), "种匣不是可见的实体")


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.toast.connect(func(message: String): messages.append(message))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(200).timeout.connect(func(): push_error("实机行程超时"); get_tree().quit(1))
	await frames(8)
	if prepare():
		Game.go("post")
		await frames(12)
		await outing("borrowed_address", "school", "许墨生", "pair")
		if not failed:
			check(Cases.view(Game.run, "shadow_show").route.site == "school", "陪石榴送信后，戏页应改在县学查访")
			await outing("shadow_show", "school", "石榴", "chorus")
		if not failed:
			await check_layouts()
	main.queue_free()
	await frames(4)
	print("[side_case_field_ui] %d checks, %d failures" % [checks, int(failed)])
	get_tree().quit(1 if failed else 0)
