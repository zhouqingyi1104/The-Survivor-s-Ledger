extends SceneTree
## 只烘焙角色实际穿戴的符纸与补子。源稿为原尺寸、无色噪的纸本与丝绣图案。

const PANELS := {"ward_paper": Vector2i(160, 320), "rank_badge": Vector2i(256, 256)}

func _initialize() -> void:
	for name: String in PANELS:
		var source := FileAccess.get_file_as_string("res://tools/pipeline/costume_panels/%s.svg" % name)
		var image := Image.new()
		if source.is_empty() or image.load_svg_from_string(source, 2.0) != OK:
			push_error("无法读取原稿：" + name)
			quit(1)
			return
		image.shrink_x2()
		image.convert(Image.FORMAT_RGB8)
		if image.get_size() != PANELS[name] or image.save_png("res://assets/models/folk/%s.png" % name) != OK:
			push_error("无法烘焙服饰图案：" + name)
			quit(1)
			return
		print(name, " ", image.get_size())
	quit()
