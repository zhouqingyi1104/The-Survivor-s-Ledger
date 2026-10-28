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


func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://c3_fight_move_ui.json"
	Game.meta_path = "user://c3_fight_move_ui_meta.json"
	Game.memory_path = "user://c3_fight_move_ui_memory.md"
	Game.speed = 0
	Game.toast.connect(func(msg: String): messages.append(msg))
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 1001)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(120).timeout.connect(func(): get_tree().quit(1))
	await frames(50)
	var screen: Control = main._screen
	var f := Home.core(Game.run, "bench")
	var uid := int(f.uid)
	screen.player.global_position = Home.stand(f)
	screen.rig.snap()
	await frames(12)
	if not await open_move(uid):
		get_tree().quit(1)
		return
	screen.rig.snap()
	await frames(12)
	var dest := find_ground(uid, false)
	if not check(not dest.is_empty(), "找不到合法挪位目的地"):
		get_tree().quit(1)
		return
	Game.placing_at = dest.ground
	await frames()
	check(screen._ghost.visible and screen._ghost_mat.albedo_color.g > screen._ghost_mat.albedo_color.r, "战前合法预览不是绿色")
	var original := f.duplicate(true)
	Game.run.fight = NightFight.begin(1, false, Game.run)
	var snapshot: Array = Game.run.fight.targets.duplicate(true)
	await frames()
	check(screen._ghost.visible and screen._ghost_mat.albedo_color.r > screen._ghost_mat.albedo_color.g, "夜袭开始后预览未变红")
	check(screen._place_reason == "夜袭中不能挪动家具，先结束战斗。", "预览没有夜袭阻挡原因")
	# Confirmation is checked directly as well: a simultaneous fight must not bypass the final check.
	screen._place_at(dest.ground)
	await frames()
	check(Game.moving_uid == uid and same_furniture(f, original), "战斗开始后确认仍移动家具")
	check(Game.run.fight.targets == snapshot, "受阻确认改变夜袭目标")
	Game.run.fight = {}
	await frames()
	check(screen._ghost.visible and screen._ghost_mat.albedo_color.g > screen._ghost_mat.albedo_color.r, "战斗结束后预览未恢复")
	Game.placing_at = null
	await click(dest.screen)
	check(Game.placing == "" and not same_furniture(f, original), "战斗结束后不能确认移动")
	# Open the furniture list in a fresh fight and trigger its actual row button.
	Game.run.fight = NightFight.begin(1, false, Game.run)
	Dialogs.furnish()
	await frames()
	var modal: Control = main._modals.get("furnish")
	check(modal != null, "家具列表未打开")
	var button: Button = null
	if modal != null:
		for label in modal.find_children("*", "Label", true, false):
			if label.text.begins_with("工作台　("):
				for child in label.get_parent().get_children():
					if child is Button and child.text == "挪位": button = child
	check(button != null, "家具列表缺工作台挪位按钮")
	if button != null:
		button.pressed.emit()
		await frames()
		check(Game.placing == "" and main._modals.has("furnish"), "夜袭中列表仍进入挪位")
		check(not messages.is_empty() and messages.back() == "夜袭中不能挪动家具，先结束战斗。", "列表未提示夜袭中不可挪位")
	print("[C3_FIGHT_MOVE_UI] ", checks - failures, "/", checks, " failed=", failures)
	get_tree().quit(1 if failures else 0)
