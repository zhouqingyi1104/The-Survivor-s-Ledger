extends SceneTree
## 只替换 CC0 家具图集上的画心。坐标取自两份 glTF 的 TEXCOORD_0，以原图集的像素计。

const MODELS := "res://assets/third_party/polyhaven/models/"
const SOURCES := "res://tools/pipeline/hall_prints/"
const MAPS := ["diff", "nor_gl", "arm"]
# 各扇正反面在扫描图集上的排布方向不同。
const SCREEN := [
	[Rect2i(33, 53, 190, 396), 0, false, false],
	[Rect2i(799, 442, 191, 397), 1, true, true],
	[Rect2i(290, 456, 187, 390), 0, false, false],
	[Rect2i(543, 49, 190, 395), 1, true, true],
]
# 绕灯身顺序排列，四种花各占相对的两面。
const LANTERN := [
	[Rect2i(427, 168, 36, 122), 0, false, true],
	[Rect2i(342, 312, 36, 123), 1, false, true],
	[Rect2i(428, 413, 36, 122), 2, false, true],
	[Rect2i(17, 666, 36, 122), 3, false, true],
	[Rect2i(615, 166, 36, 122), 0, false, true],
	[Rect2i(36, 472, 36, 123), 1, false, true],
	[Rect2i(572, 253, 37, 123), 2, false, true],
	[Rect2i(500, 282, 36, 122), 3, false, true],
]


func _initialize() -> void:
	var ok := bake("chinese_screen_panels", "persimmon_screen", SCREEN, 2, 1)
	if ok:
		ok = bake("chinese_chandelier", "lantern_flowers", LANTERN, 4, 2)
	quit(0 if ok else 1)


func bake(model: String, art: String, islands: Array, columns: int, color_scale: int) -> bool:
	var source := Image.new()
	var svg := FileAccess.get_file_as_string(SOURCES + art + ".svg")
	if svg.is_empty() or source.load_svg_from_string(svg, 2.0) != OK:
		push_error("无法读取画稿 " + art)
		return false
	source.convert(Image.FORMAT_RGB8)
	var cell := Vector2i(source.get_width() / columns, source.get_height())
	var prefix := MODELS + model + "/textures/"
	for channel: String in MAPS:
		var image := Image.new()
		var scan := FileAccess.get_file_as_bytes(prefix + model + "_" + channel + "_1k.jpg")
		if scan.is_empty() or image.load_jpg_from_buffer(scan) != OK or image.get_size() != Vector2i(1024, 1024):
			push_error("原始扫描图集尺寸不符 " + model + " " + channel)
			return false
		var scale := color_scale if channel == "diff" else 1
		if scale > 1:
			image.resize(1024 * scale, 1024 * scale, Image.INTERPOLATE_BILINEAR)
		image.convert(Image.FORMAT_RGB8)
		for island: Array in islands:
			var chart: Rect2i = island[0]
			# 两像素出血位于闲置 UV 隔离带，避免缩图漏出旧金粉和旧绢纹。
			var target := Rect2i(chart.position * scale, chart.size * scale).grow(2 * scale)
			match channel:
				"diff":
					var face := source.get_region(Rect2i(Vector2i(cell.x * int(island[1]), 0), cell))
					if island[2]: face.flip_x()
					if island[3]: face.flip_y()
					face.resize(target.size.x, target.size.y, Image.INTERPOLATE_LANCZOS)
					image.blit_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), target.position)
				"nor_gl":
					image.fill_rect(target, Color8(128, 128, 255))
				"arm":
					image.fill_rect(target, Color8(255, 203 if columns == 2 else 224, 0))
		var path := prefix + "%s_%s_%dk.webp" % [art, channel, scale]
		if image.save_webp(path, false) != OK:
			push_error("图集写入失败 " + path)
			return false
	return true
