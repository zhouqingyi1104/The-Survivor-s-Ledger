extends SceneTree
## 从绘图源稿烘焙存货插画。运行 Godot --headless --path . --script tools/pipeline/bake_inventory.gd

const SOURCE := "res://tools/pipeline/inventory_art/"
const TARGET := "res://assets/ui/inventory/"
const SHEETS := ["food", "supplies", "tools", "misc"]
const FURNITURE_PARTS := ["furniture_home", "furniture_yard", "furniture_room"]


func _initialize() -> void:
	var requested := OS.get_cmdline_user_args()
	var names := PackedStringArray(SHEETS + ["rice", "nails", "paper", "furniture"]) if requested.is_empty() else requested
	for name in names:
		if name not in SHEETS and name not in ["rice", "nails", "paper", "furniture"]:
			push_error("未知图稿：" + name)
			quit(1)
			return
		var image := _furniture() if name == "furniture" else _raster(name)
		if image == null:
			push_error("图稿读取失败：" + name)
			quit(1)
			return
		var file := name + "_atlas" if name in SHEETS or name == "furniture" else name
		var error := image.save_png(TARGET + file + ".png")
		if error != OK:
			push_error("写入失败：" + file + " " + error_string(error))
			quit(1)
			return
		print(file, " ", image.get_size())
	quit()


func _raster(name: String) -> Image:
	var source := FileAccess.get_file_as_string(SOURCE + name + ".svg")
	var image := Image.new()
	if source.is_empty() or image.load_svg_from_string(source, 2.0 if name == "paper" else 6.0) != OK:
		return null
	# 按整数倍超采样后取 2×2 平均覆盖。单件为 288px；透明区颜色由导入器延展。
	image.shrink_x2()
	return image


func _furniture() -> Image:
	var sheet := Image.create_empty(864, 1728, false, Image.FORMAT_RGBA8)
	for i in FURNITURE_PARTS.size():
		var part := _raster(FURNITURE_PARTS[i])
		if part == null or part.get_size() != Vector2i(864, 576):
			return null
		sheet.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, i * part.get_height()))
	return sheet
