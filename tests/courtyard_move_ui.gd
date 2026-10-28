extends Node
## C2: exercise actual viewport input, furniture pick, menu, preview and drop.
## Run with isolated APPDATA/LOCALAPPDATA; never opens or writes a player's save.

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Director = preload("res://scripts/core/director.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")

var main: Control
var checks := 0
var failures := 0
var messages: Array[String] = []

func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)
	return ok

func frames(n := 8) -> void:
	for i in n:
		await get_tree().process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames()

func click(pos: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames()

func menu_button(prefix: String) -> Button:
	for b in main._screen._menu.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.text.begins_with(prefix):
			return b
	return null

func find_pick(target: Vector3, spot_id: String) -> Vector2:
	var screen: Control = main._screen
	var center: Vector2 = screen.rig.cam.unproject_position(target)
	var bounds := get_viewport().get_visible_rect().grow(-10)
	for dx in range(-24, 25, 4):
		for dy in range(-24, 25, 4):
			var p := center + Vector2(dx, dy)
			if bounds.has_point(p) and str(screen.world.pick(screen.rig.cam, p).get("spot", "")) == spot_id:
				return p
	return Vector2(-1, -1)

func find_ground(uid: int, want_blocked: bool) -> Dictionary:
	var screen: Control = main._screen
	var f := Home.find(Game.run, uid)
	var bounds := get_viewport().get_visible_rect().grow(-20)
	for z_step in range(12, 25):
		for x_step in range(-30, 31):
			var world_pos := Vector3(x_step * 0.25, 0, z_step * 0.25)
			var p: Vector2 = screen.rig.cam.unproject_position(world_pos)
			if not bounds.has_point(p): continue
			var hit: Dictionary = screen.world.pick_move_ground(screen.rig.cam, p, uid)
			if not hit.has("ground"): continue
			var g: Vector3 = hit.ground
			var reason: String = screen.world.move_spot_block(Game.run, uid, g.x, g.z, Game.placing_rot)
			if (reason != "") == want_blocked and (want_blocked or Vector2(g.x - float(f.x), g.z - float(f.z)).length() > 1.0):
				return {"screen": p, "ground": g, "reason": reason}
	return {}

func same_furniture(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and int(a.get("uid", -1)) == int(b.get("uid", -2)) and str(a.get("id", "")) == str(b.get("id", "")) and int(a.get("rot", -1)) == int(b.get("rot", -2)) and is_equal_approx(float(a.get("x", 0)), float(b.get("x", 1))) and is_equal_approx(float(a.get("z", 0)), float(b.get("z", 1)))

func open_move(uid: int) -> bool:
	var screen: Control = main._screen
	var f := Home.find(Game.run, uid)
	var spot_id := "f_%d" % uid
	var p := find_pick(Vector3(float(f.x), 0.45, float(f.z)), spot_id)
	if not check(p.x >= 0, "附加家具没有可点击的物理拾取位置"): return false
	await click(p)
	if not check(screen._menu.visible, "点击附加家具未打开菜单"): return false
	var b := menu_button("挪位")
	if not check(b != null and not b.disabled, "菜单缺少可用的挪位入口"): return false
	await click(b.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 12000
	while Game.placing == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return check(Game.placing == str(f.id), "点击挪位后未进入家具预览")

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://courtyard_move_test_save.json"
	Game.meta_path = "user://courtyard_move_test_meta.json"
	Game.memory_path = "user://courtyard_move_test_memory.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	var f := Home.add(Game.run, "armchair", -4.5, 3.5, 0)
	var uid := int(f.uid)
	var initial := f.duplicate(true)
	var inventory: Dictionary = Game.run.home.duplicate(true)
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	Game.toast.connect(func(msg: String): messages.append(msg))
	await frames(40)
	if await open_move(uid):
		var screen: Control = main._screen
		screen.rig.snap()
		await frames(20)
		var invalid := find_ground(uid, true)
		if check(not invalid.is_empty(), "找不到实际可点击的非法地面"):
			Game.placing_at = invalid.ground
			await frames()
			check(screen._ghost.visible and screen._ghost_mat.albedo_color.r > screen._ghost_mat.albedo_color.g, "非法位置预览未变红")
			check(str(invalid.reason) in screen._live.place.text, "预览未显示非法位置的具体原因")
			messages.clear()
			if not screen.world.pick_move_ground(screen.rig.cam, invalid.screen, uid).has("ground"):
				print("Invalid pick diagnostic: ", invalid, " current=", screen.world.pick_move_ground(screen.rig.cam, invalid.screen, uid))
			await click(invalid.screen)
			check(Home.find(Game.run, uid) == initial and Game.placing != "", "非法放置改变了家具或退出预览")
			check(not messages.is_empty() and str(messages.back()) == str(invalid.reason), "非法点击未报告预览显示的具体原因：%s" % str(messages))
		await key(KEY_ESCAPE)
		check(Game.placing == "" and Home.find(Game.run, uid) == initial, "取消挪位改变家具或未退出")
		Game.placing_at = null
		if await open_move(uid):
			var old_rot := Game.placing_rot
			await key(KEY_R)
			check(Game.placing_rot == (old_rot + 90) % 360, "R 未旋转预览")
			var valid := find_ground(uid, false)
			if check(not valid.is_empty(), "找不到实际可点击的合法地面"):
				Game.placing_at = valid.ground
				await frames()
				check(screen._ghost.visible and screen._ghost_mat.albedo_color.g > screen._ghost_mat.albedo_color.r, "合法位置预览未变绿")
				check("可放下" in screen._live.place.text and "90°" in screen._live.place.text, "预览未显示可放下和当前朝向")
				if OS.get_environment("C2_SHOT") != "":
					RenderingServer.force_draw()
					get_viewport().get_texture().get_image().save_png(OS.get_environment("C2_SHOT"))
				Game.placing_at = null
				await click(valid.screen)
				var moved := Home.find(Game.run, uid)
				if Game.placing != "":
					print("Drop diagnostic: point=", valid.screen, " hit=", screen.world.pick_move_ground(screen.rig.cam, valid.screen, uid), " toast=", messages.back() if not messages.is_empty() else "")
				check(Game.placing == "", "合法放置未退出预览")
				check(int(moved.get("uid", -1)) == uid and int(moved.get("rot", -1)) == (old_rot + 90) % 360, "挪位未保持 UID 或旋转")
				check(is_equal_approx(float(moved.get("x", 0)), Home.snap(valid.ground.x)) and is_equal_approx(float(moved.get("z", 0)), Home.snap(valid.ground.z)), "家具位置未落在点击处")
				check(Game.run.home == inventory, "挪位改变了物资")
				check(screen.world.spot_nodes.has("f_%d" % uid), "挪位后场景未更新")
				var moved_copy := moved.duplicate(true)
				var written: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
				if check(bool(written.get("ok", false)), "隔离存档写入失败"):
					screen._start_move(uid)
					check(Game.placing != "", "读档前未进入预览")
					if check(Game.continue_game(), "隔离存档读回失败"):
						await frames()
						check(Game.placing == "" and Game.moving_uid == -1, "同屏读档未清除挪位预览")
						check(same_furniture(Home.find(Game.run, uid), moved_copy), "读档后家具位置或身份变化")
						main._screen._start_move(uid)
						check(Game.placing != "", "回溯前未进入预览")
						Game.rewind()
						await frames()
						check(Game.placing == "" and Game.moving_uid == -1, "同屏回溯未清除挪位预览")
						check(same_furniture(Home.find(Game.run, uid), initial), "翻回前一页未恢复原家具")
						main._screen._start_move(uid)
						check(Game.placing != "", "新局前未进入预览")
						Game.new_game("scholar")
						await frames()
						check(Game.placing == "" and Game.moving_uid == -1, "新局未清除挪位预览")
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C2 viewport: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
