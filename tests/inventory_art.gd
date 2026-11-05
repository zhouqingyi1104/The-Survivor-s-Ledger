extends Node
## 存货插画定向检查；像素几何不能代替图案识别与风格目视。
const Art = preload("res://scripts/ui/inventory_art.gd")
const Data = preload("res://scripts/core/data.gd")
const OUTPUT := "res://build/inventory-art-qa/pixel-audit.json"
var checks := 0
var failures := 0
var finished := 0
var image_cache := {}
var pixel_report := {}

func _ready() -> void:
	var only := ""
	var first := ""
	var start := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		elif arg.begins_with("--from="):
			first = arg.trim_prefix("--from=")
			start = false
	var selected := 0
	for test in [test_coverage, test_regions, test_pixels]:
		if str(test.get_method()) == first: start = true
		if not start or (only != "" and str(test.get_method()) != only): continue
		selected += 1
		test.call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and selected == finished, "测试未完成所选场景")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "pixels": pixel_report, "scope": "pixel_geometry_only_not_semantic_acceptance"}, "\t"))
	else: check(false, "无法写入像素检查证据")
	print("[inventory_art] %d 项检查，完成 %d/%d，失败 %d 处" % [checks, finished, selected, failures])
	get_tree().quit(1 if failures > 0 else 0)

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func test_coverage() -> void:
	var expected: Array = Data.table("items").keys()
	var actual: Array = Art.ids()
	var unique := {}
	for id in actual: unique[id] = true
	check(expected.size() == 57, "物品表不再是本批验收的 57 件")
	check(actual.size() == unique.size(), "插画 ID 重复")
	expected.sort()
	actual.sort()
	if not check(expected == actual, "插画 ID 与真实物品表不一致"): return
	for id in expected:
		if not check(Art.has(id) and Art.texture(id) is Texture2D, "真实物品插画缺失：" + id): return
		check(is_same(Art.texture(id), Art.texture(id)), "插画缓存没有复用同一纹理：" + id)
	check(not Art.has("inventory_future_fixture") and Art.texture("inventory_future_fixture") == null, "未知 ID 返回错误插画")
	check(not Art.has("") and Art.texture("") == null, "空 ID 返回错误插画")
	check(Art.texture("rice").resource_path == "res://assets/ui/inventory/rice.png", "米袋原插画路径改变")
	check(Art.texture("nails").resource_path == "res://assets/ui/inventory/nails.png", "铁钉原插画路径改变")
	finished += 1

func test_regions() -> void:
	var occupied := {}
	var sheets := {}
	for id in Art.ids():
		var texture: Texture2D = Art.texture(id)
		if id in ["rice", "nails"]:
			check(not texture is AtlasTexture, "既有独立插画被图集替换：" + id)
			continue
		if not check(texture is AtlasTexture, "新增插画没有使用图集区域：" + id): return
		var atlas: AtlasTexture = texture
		if not check(atlas.atlas != null and atlas.filter_clip, "图集源为空或没有裁切保护：" + id): return
		var size: Vector2 = atlas.atlas.get_size()
		var region := atlas.region
		if not check(size.x > 0 and size.y > 0, "图集尺寸无效：" + id): return
		check(region.size == size / 4, "区域不是一个等格：" + id)
		check(Rect2(Vector2.ZERO, size).encloses(region), "区域超出图集边界：" + id)
		check(region.position.x == floorf(region.position.x / region.size.x) * region.size.x and region.position.y == floorf(region.position.y / region.size.y) * region.size.y, "区域偏离等格边界：" + id)
		var key := "%s:%s" % [atlas.atlas.resource_path, str(region)]
		check(not occupied.has(key), "区域重复映射：%s 与 %s" % [id, str(occupied.get(key, ""))])
		occupied[key] = id
		sheets[atlas.atlas.resource_path] = true
	check(occupied.size() == 55, "新增插画的唯一图集区域不是 55 个")
	check(sheets.size() == 4, "新增插画没有使用四张图集")
	finished += 1

func source_image(texture: Texture2D) -> Image:
	var path: String = texture.resource_path
	if not image_cache.has(path): image_cache[path] = texture.get_image()
	return image_cache[path]

func test_pixels() -> void:
	for id in Art.ids():
		var texture: Texture2D = Art.texture(id)
		var atlas := texture as AtlasTexture
		var source: Texture2D = atlas.atlas if atlas != null else texture
		var image := source_image(source)
		if not check(image != null and not image.is_empty(), "插画像素为空：" + id): return
		if image.is_compressed():
			if not check(image.decompress() == OK, "插画解压失败：" + id): return
		# 原生图集可以是 1254px 等尺寸；浮点等格边界要向外覆盖，不能截断漏扫。
		var sampling := Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height()))
		if atlas != null: sampling = atlas.region
		var start := Vector2i(sampling.position.floor())
		var end := Vector2i(sampling.end.ceil())
		var region := Rect2i(start, end - start).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
		var pixels := 0
		var transparent := 0
		var edge_pixels := 0
		var min_point := region.size
		var max_point := Vector2i(-1, -1)
		for y in region.size.y:
			for x in region.size.x:
				var alpha := image.get_pixel(region.position.x + x, region.position.y + y).a
				if alpha < 0.05: transparent += 1
				if alpha <= 0.15: continue
				pixels += 1
				min_point = Vector2i(mini(min_point.x, x), mini(min_point.y, y))
				max_point = Vector2i(maxi(max_point.x, x), maxi(max_point.y, y))
				if x < 2 or y < 2 or x >= region.size.x - 2 or y >= region.size.y - 2: edge_pixels += 1
		var area := region.size.x * region.size.y
		pixel_report[id] = {"source": source.resource_path, "atlas_region": [sampling.position.x, sampling.position.y, sampling.size.x, sampling.size.y], "sampled_region": [region.position.x, region.position.y, region.size.x, region.size.y], "occupied_pixels": pixels, "transparent_pixels": transparent, "outer_two_pixel_occupied": edge_pixels, "content_bounds": [min_point.x, min_point.y, max_point.x, max_point.y]}
		check(pixels > area / 100, "插画几乎全透明或漏图：" + id)
		check(transparent > area / 10, "插画缺少透明背景：" + id)
		if atlas != null: check(edge_pixels == 0, "图集格边有实体像素，存在切边或邻图串入：" + id)
		if failures > 0: return
	finished += 1
