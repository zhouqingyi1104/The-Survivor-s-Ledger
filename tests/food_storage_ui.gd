extends "res://tests/food_drying_ui.gd"
## 固定三件已摆好的家具。接近后按 E，从场景菜单开始封坛、挂肉、装饵。
const Home = preload("res://scripts/core/home.gd")


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 4185)
	Pre.start_disaster(Game.run)
	Game.run.home = {"cabbage": 3, "salt": 1, "rat": 2, "firewood": 1, "millet": 1}
	var jar := Home.add(Game.run, "pickle_jar", -4, 3, 0)
	var rack := Home.add(Game.run, "smoke_rack", 4, -1, 0)
	var trap := Home.add(Game.run, "rat_trap", 4, 4, 0)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(25)
	if not await at_furniture(jar, "装坛"): return
	if not await click_button(main._modals.food_storage, "封 3 份"): return
	if not check(jar.job.out == {"pickles": 3} and not Game.run.home.has("cabbage"), "封坛和实际物资不一致"): return
	if not await click_button(main._modals.food_storage, "合上"): return
	if not await at_furniture(rack, "上架"): return
	if not await click_button(main._modals.food_storage, "挂 2 块"): return
	if not check(rack.job.out == {"smoked_rat": 2} and not Game.run.home.has("rat"), "挂肉和实际物资不一致"): return
	if not await click_button(main._modals.food_storage, "合上"): return
	if not await at_furniture(trap, "装饵"): return
	if not await click_button(main._modals.food_storage, "分六晚的饵"): return
	if not check(trap.bait_left == 6 and not Game.run.home.has("millet") and button(main._modals.food_storage, "分六晚的饵", false).disabled, "装饵没有扣粮或还能重复扣"): return
	screen_shot("trap")
	print("[food_storage_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func at_furniture(f: Dictionary, caption: String) -> bool:
	var screen: Control = main._screen
	var uid := "f_%d" % int(f.uid)
	var info: Dictionary = screen._spot_info(uid)
	if not check(not info.is_empty(), "没有交互点：" + uid): return false
	screen.player.global_position = info.stand
	await frames(12)
	if not check(screen.world.nearest_spot(screen.player.global_position, 2.2) == uid, "交互点错选：" + uid): return false
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_E
		key.physical_keycode = KEY_E
		key.pressed = down
		get_viewport().push_input(key)
	await frames()
	if not await click_button(screen._menu, caption): return false
	return check(main.has_modal("food_storage"), "家具面板未打开：" + caption)
