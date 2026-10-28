extends Node
## C3: actual viewport input, moved core furniture, travel, damage and recovery.
## Run with isolated APPDATA/LOCALAPPDATA; never opens or writes a player's save.

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Home = preload("res://scripts/core/home.gd")
const Director = preload("res://scripts/core/director.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Post = preload("res://scripts/core/post.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")

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
	var viewport_size := get_viewport().get_visible_rect().size
	# Keep the candidate away from the top and bottom HUD controls.
	var bounds := Rect2(viewport_size * Vector2(0.22, 0.20), viewport_size * Vector2(0.56, 0.52))
	for z_step in range(-30, 26):
		for x_step in range(-38, 39):
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

func same_targets(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		var x: Array = a[i]
		var y: Array = b[i]
		if x.size() != y.size() or x.size() < 5: return false
		if str(x[0]) != str(y[0]) or str(x[3]) != str(y[3]) or str(x[4]) != str(y[4]): return false
		if not is_equal_approx(float(x[1]), float(y[1])) or not is_equal_approx(float(x[2]), float(y[2])): return false
		if x.size() > 5 and int(x[5]) != int(y[5]): return false
	return true

## Construct an isolated wall at the proposed front, after verifying the same
## furniture footprint and navigation are valid without that wall.
func check_front_walls(screen: Control, uid: int) -> void:
	var f := Home.find(Game.run, uid)
	for rot in [0, 90, 180, 270]:
		var candidate := {}
		for z in range(-15, 13):
			if not candidate.is_empty(): break
			for x in range(-19, 20):
				var px := x * 0.5
				var pz := z * 0.5
				if Home.spot_block(Game.run, str(f.id), px, pz, rot, uid) != "": continue
				if screen.world.move_spot_block(Game.run, uid, px, pz, rot) == "":
					candidate = {"x": px, "z": pz, "rot": rot}
					break
		if not check(not candidate.is_empty(), "%d 度找不到可用的测试位置" % rot): continue
		var proposed := f.duplicate(true)
		proposed.x = candidate.x
		proposed.z = candidate.z
		proposed.rot = rot
		var stand := Home.stand(proposed)
		var wall := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = Vector3(1.0, 1.5, 0.15) if rot % 180 == 0 else Vector3(0.15, 1.5, 1.0)
		shape_node.shape = wall_shape
		wall.add_child(shape_node)
		wall.position = stand + Vector3(0, 0.85, 0)
		screen.world.add_child(wall)
		await get_tree().physics_frame
		var reason: String = screen.world.move_spot_block(Game.run, uid, candidate.x, candidate.z, rot)
		check(reason == "家具正面被挡住了。", "%d 度正面墙体未单独拦截，位置=%s 原因=%s" % [rot, candidate, reason])
		screen.world.remove_child(wall)
		wall.queue_free()
		await get_tree().physics_frame

func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func check_arrival(screen: Control, id: String, label: String) -> void:
	var called := [false]
	screen.do_at(id, func(): called[0] = true)
	var deadline := Time.get_ticks_msec() + 12000
	while not called[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(called[0], label + " 未触发")
	var f := Home.core(Game.run, id)
	if not f.is_empty():
		var center := Vector3(float(f.x), 0, float(f.z))
		var size := Home.size_of(str(f.id), int(f.rot))
		check(flat_dist(screen.player.global_position, center) <= maxf(size.x, size.y) * 0.5 + 1.65, label + " 远离家具时已触发：人物=%s 家具=%s" % [screen.player.global_position, center])

func close_modal() -> void:
	await key(KEY_ESCAPE)
	await frames(5)

func _ready() -> void:
	# The process must also run with isolated APPDATA and LOCALAPPDATA.
	Game.no_save = true
	Game.save_path = "user://c3_core_ui_save.json"
	Game.meta_path = "user://c3_core_ui_meta.json"
	Game.memory_path = "user://c3_core_ui_memory.md"
	Game.speed = 0
	Game.toast.connect(func(msg: String): messages.append(msg))
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	var before: Dictionary = Game.run.duplicate(true)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	await frames(50)
	var screen: Control = main._screen
	var moved := {}
	var bench_uid := int(Home.core(Game.run, "bench").get("uid", -1))
	await check_front_walls(screen, bench_uid)
	check(screen.world.move_spot_block(Game.run, bench_uid, 5.25, -5.5, 270) != "", "工作台与书案站位重叠却允许摆放")
	check(screen.world.move_spot_block(Game.run, bench_uid, 4.2, -4.25, 180) != "", "旋转后的工作台与书案站位重叠却允许摆放")
	for id in ["bench", "stove", "bed", "desk", "storage"]:
		var f := Home.core(Game.run, id)
		if not check(not f.is_empty(), "缺少核心家具 " + id): continue
		var uid := int(f.uid)
		var initial := f.duplicate(true)
		# Center the real camera near the target before the physical pick.
		screen.player.global_position = Home.stand(f)
		screen.rig.snap()
		await frames(12)
		if not await open_move(uid): continue
		if id == "bed":
			screen.player.global_position = Vector3(-4, 0, -2.5)
			await frames(4)
		screen.rig.snap()
		await frames(12)
		var dest := find_ground(uid, false)
		if not check(not dest.is_empty(), id + " 无可点击的合法目标"):
			await key(KEY_ESCAPE)
			continue
		Game.placing_at = dest.ground
		await frames()
		check(screen._ghost.visible and screen._ghost_mat.albedo_color.g > screen._ghost_mat.albedo_color.r, id + " 合法预览未变绿")
		Game.placing_at = null
		await click(dest.screen)
		f = Home.find(Game.run, uid)
		if Game.placing != "" or same_furniture(f, initial):
			print("C3 drop diagnostic id=", id, " destination=", dest, " pick=", screen.world.pick_move_ground(screen.rig.cam, dest.screen, uid), " placing=", Game.placing, " original=", initial, " current=", f, " toast=", messages.back() if not messages.is_empty() else "")
		if not check(Game.placing == "" and not same_furniture(f, initial), id + " 点击地面未完成移动"):
			get_tree().quit(1)
			return
		check(int(f.uid) == uid and screen.world.spot_nodes.has("f_%d" % uid), id + " 身份/场景未保持")
		moved[id] = f.duplicate(true)
		# The test measures actual movement, not merely Player.arrived (which also fires on timeout).
		screen.player.global_position = Vector3(0, 0, 4.5)
		await frames(5)
		await check_arrival(screen, id, id + " 自动走到新位置")
		# Test E from the destination rather than invoking the menu directly.
		await key(KEY_E)
		if not screen._menu.visible or str(screen._menu_spot) != "f_%d" % uid:
			print("C3 E diagnostic id=", id, " player=", screen.player.global_position, " center=", f, " stand=", Home.stand(f), " nearest=", screen.world.nearest_spot(screen.player.global_position, 2.2), " menu=", screen._menu.visible, " menu_spot=", screen._menu_spot)
			check(false, id + " 的 E 互动未指向移动后的家具")
			get_tree().quit(1)
			return
		if screen._menu.visible: await key(KEY_ESCAPE)
		await frames(5)

	if moved.has("stove"):
		# Use the existing agenda entry point; the actual cook dialog must open near the new stove.
		Game.run.agenda.items = [{"id": "cook", "kind": "builtin", "done": false}]
		screen.player.global_position = Vector3(0, 0, 4.5)
		await frames(5)
		screen.agenda_do(0)
		var deadline := Time.get_ticks_msec() + 12000
		while not screen.modal_open() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var f := Home.core(Game.run, "stove")
		check(screen.modal_open(), "差事做饭未打开菜单")
		check(flat_dist(screen.player.global_position, Vector3(float(f.x), 0, float(f.z))) <= 2.6, "差事做饭在离灶台太远处执行")
		if screen.modal_open(): await close_modal()

	if moved.has("bed"):
		var f := Home.core(Game.run, "bed")
		Game.run.attrs.energy = 20
		screen.player.global_position = Vector3(0, 0, 4.5)
		await frames(4)
		await key(KEY_N)
		var deadline := Time.get_ticks_msec() + 12000
		while not Game.run.sleeping and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(Game.run.sleeping, "N 就寝快捷键未触发")
		await frames(4)
		check(flat_dist(screen.player.figure.global_position, Vector3(float(f.x), 0, float(f.z))) < 1.8, "睡姿未跟随床榻")
		Game.run.sleeping = false
		Game.run.attrs.energy = 100
		await frames(4)
		check(flat_dist(screen.player.global_position, Vector3(float(f.x), 0, float(f.z))) < 2.6, "醒来未在床榻旁")

	# Real legacy save plus its previous-day snapshot, each with no furniture.
	var legacy := before.duplicate(true)
	legacy.erase("furniture")
	legacy.erase("next_uid")
	legacy.broken = ["stove"]
	var legacy_save := Migrate.save({"run": legacy, "snapshots": {"1": legacy.duplicate(true)}})
	for id in ["bed", "desk", "storage", "stove", "bench"]:
		check(not Home.core(legacy_save.run, id).is_empty() and not Home.core(legacy_save.snapshots["1"], id).is_empty(), "旧档或快照缺失核心家具 " + id)
	check("stove" in legacy_save.run.broken and "stove" in legacy_save.snapshots["1"].broken, "旧档战损未保留")
	legacy_save.run.fight = NightFight.begin(5, false)
	legacy_save.run.fight.erase("targets")
	var legacy_targets := NightFight.fight_targets(legacy_save.run)
	var legacy_stove := Home.core(legacy_save.run, "stove")
	check(legacy_targets[3].size() > 5 and int(legacy_targets[3][5]) == int(legacy_stove.uid), "旧战斗未绑定迁移后的灶台")

	if moved.has("stove") and moved.has("bench"):
		Post.start_fight(Game.run, 5, false)
		var targets: Array = Game.run.fight.get("targets", [])
		for id in ["stove", "bench"]:
			var f := Home.core(Game.run, id)
			var found := false
			for row in targets:
				if row.size() > 5 and str(row[4]) == id and int(row[5]) == int(f.uid):
					found = is_equal_approx(float(row[1]), float(f.x)) and is_equal_approx(float(row[2]), float(f.z))
			check(found, id + " 夜袭目标位置或身份没有跟随家具")
		var hit_idx := -1
		for i in targets.size():
			if targets[i].size() > 5 and str(targets[i][4]) == "stove": hit_idx = i
		if check(hit_idx >= 0, "找不到灶台夜袭目标"):
			Post.apply_wreck(Game.run, hit_idx)
			screen.world.sync(Game.run)
			var f := Home.core(Game.run, "stove")
			var spot := "f_%d" % int(f.uid)
			check("stove" in Game.run.broken, "被袭后灶台战损未记录")
			check(screen.world._rubbles.has(spot), "被袭后灶台残骸缺失")
			if screen.world._rubbles.has(spot):
				check(flat_dist(screen.world._rubbles[spot].global_position, Vector3(float(f.x), 0, float(f.z))) < 0.1, "战损残骸未留在新位置")
		var fight_targets := targets.duplicate(true)
		var fight_save := SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
		if check(bool(fight_save.get("ok", false)) and Game.continue_game(), "进行中战斗存取失败"):
			await frames(8)
			if not same_targets(Game.run.fight.get("targets", []), fight_targets) or not "stove" in Game.run.broken:
				print("C3 combat save diagnostic before=", fight_targets, " after=", Game.run.fight.get("targets", []), " broken=", Game.run.get("broken", []), " fight=", Game.run.fight)
			check(same_targets(Game.run.fight.get("targets", []), fight_targets) and "stove" in Game.run.broken, "进行中战斗读档后目标或战损改变")
		Game.run.fight = {}

	var written: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	if check(bool(written.get("ok", false)), "隔离存档失败") and check(Game.continue_game(), "隔离读档失败"):
		await frames(12)
		for id in moved:
			check(same_furniture(Home.core(Game.run, id), moved[id]), id + " 读档后丢失位置")
		Game.rewind()
		await frames(12)
		for id in moved:
			check(same_furniture(Home.core(Game.run, id), Home.core(before, id)), id + " 回溯后未恢复位置")
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C3 core viewport: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
