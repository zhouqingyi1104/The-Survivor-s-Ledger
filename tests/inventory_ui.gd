extends Node
## 窗口定向验收：分类、真实鼠标使用并刷新、空库存及 Esc。
## tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/inventory_ui.tscn

const Demo = preload("res://scripts/dev/demo.gd")
var main: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 6) -> void:
	for i in count:
		await get_tree().process_frame

func labels() -> Array:
	var result := []
	for label in main._modals["inventory"].find_children("*", "Label", true, false):
		result.append(label.text)
	return result

func button(text: String) -> Button:
	for candidate in main._modals["inventory"].find_children("*", "Button", true, false):
		if candidate.text == text and candidate.is_visible_in_tree():
			return candidate
	return null

func click(target: Control) -> void:
	if target == null:
		check(false, "找不到使用按钮")
		return
	var point := target.get_global_rect().get_center()
	check(get_viewport().get_visible_rect().has_point(point), "使用按钮不在窗口内")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	get_viewport().push_input(press)
	await frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	get_viewport().push_input(release)
	await frames()

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://inventory-ui-%d.json" % OS.get_process_id()
	Game.meta_path = "user://inventory-ui-meta-%d.json" % OS.get_process_id()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	await frames(8)
	Demo._to_post()
	Game.run.home = {"flatbread": 2, "water": 1, "wood": 3, "rice": 4, "nails": 2}
	Game.refresh()
	await frames(10)
	Dialogs.inventory()
	await frames()
	check(main.has_modal("inventory"), "存货弹窗没有打开")
	check(button("全部") != null and button("食") != null and button("水") != null and button("材") != null, "分类筛选缺失")
	check("炊饼" in labels() and "×2" in labels(), "炊饼或初始数量缺失")
	var art_paths := []
	for illustration in main._modals["inventory"].find_children("*", "TextureRect", true, false):
		if illustration.texture != null:
			art_paths.append(illustration.texture.resource_path)
	check("res://assets/ui/inventory/rice.png" in art_paths and "res://assets/ui/inventory/nails.png" in art_paths, "米袋与铁钉插画未加载")
	await click(button("水"))
	check("清水" in labels() and not "炊饼" in labels(), "水分类筛选错误：%s" % str(labels()))
	await click(button("全部"))
	check("炊饼" in labels(), "返回全部未恢复列表")
	await click(button("食"))
	await click(button("吃"))
	check(int(Game.run.home.get("flatbread", 0)) == 1, "真实点击未消耗一份炊饼")
	check("炊饼" in labels() and "×1" in labels(), "消耗后物品数量未刷新")
	await click(button("吃"))
	check(not Game.run.home.has("flatbread"), "第二次点击未消耗最后一份")
	check(not "炊饼" in labels() and button("食") == null, "最后一份用完后物品或空分类仍存在")
	check("清水" in labels(), "当前分类耗尽后没有返回全部")
	Game.run.home = {}
	Game.refresh()
	await frames()
	check("家中暂无存货。" in labels(), "空库存提示未显示")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	await frames()
	check(not main.has_modal("inventory"), "Esc 未关闭存货弹窗")
	print("存货窗口验收：%d 项，%d 处失败" % [checks, failures])
	main.queue_free()
	await frames()
	get_tree().quit(1 if failures > 0 else 0)
