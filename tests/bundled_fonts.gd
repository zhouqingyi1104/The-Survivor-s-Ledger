extends Node
## 字体资源、完整源码/数据字符超集与各入口接入；不依赖操作系统安装的字体。
const Fonts = preload("res://scripts/ui/fonts.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Hud = preload("res://scripts/ui/hud_kit.gd")
const Kit = preload("res://scripts/world/kit.gd")
const Clock = preload("res://scripts/ui/widgets/clock_dial.gd")
var checks := 0
var failures := 0
var finished := 0
var character_count := 0
var source_count := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

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
	for test in [test_resources, test_character_coverage, test_consumers]:
		if str(test.get_method()) == first: start = true
		if not start or (only != "" and str(test.get_method()) != only): continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0: check(selected > 0 and selected == finished, "字体测试未完成所选场景")
	print("[bundled_fonts] %d 项检查，完成 %d/%d，失败 %d；%d 个源码/数据文件，%d 个非控制字符" % [checks, finished, selected, failures, source_count, character_count])
	get_tree().quit(1 if failures > 0 else 0)

func inspect_chain(font: Font, label: String, seen: Dictionary) -> void:
	if not check(font != null, label + " 字体为空"): return
	if seen.has(font.get_instance_id()): return
	seen[font.get_instance_id()] = true
	check(not font is SystemFont, label + " 仍依赖 SystemFont")
	if font is FontVariation:
		inspect_chain(font.base_font, label + "/base", seen)
	elif font is FontFile:
		check(not font.allow_system_fallback, label + " 允许系统字体回退")
		check(font.resource_path.begins_with("res://assets/fonts/") and font.data.size() > 0, label + " 不是随包的非空 FontFile")
	else:
		check(false, label + " 使用未验收的字体类型：" + font.get_class())
	for fallback in font.get_fallbacks(): inspect_chain(fallback, label + "/fallback", seen)

func test_resources() -> void:
	var fonts := {"book": Fonts.book(), "body": Fonts.body(), "bold": Fonts.bold()}
	for name in fonts:
		inspect_chain(fonts[name], name, {})
		# 原字体本机 18px 行高约 22、84px 约 100；防止回退字体抬高整行挤出既有布局。
		check(fonts[name].get_height(18) <= 24.0, "%s 18px 字体行高过大：%.1f" % [name, fonts[name].get_height(18)])
		check(fonts[name].get_height(84) <= 105.0, "%s 84px 字体行高过大：%.1f" % [name, fonts[name].get_height(84)])
	check(Fonts.book().resource_path.ends_with("LXGWWenKai-Regular.ttf"), "纸面字体不是霞鹜文楷原始资源")
	check(is_same(Fonts.book(), Fonts.book()) and is_same(Fonts.body(), Fonts.body()) and is_same(Fonts.bold(), Fonts.bold()), "字体入口未复用资源")
	if not check(Fonts.body() is FontVariation and Fonts.bold() is FontVariation, "正文/粗体没有显式使用字体字重轴"): return
	var body: FontVariation = Fonts.body()
	var bold: FontVariation = Fonts.bold()
	check(body.base_font is FontFile and body.base_font.resource_path.ends_with("NotoSansSC-VF.ttf"), "正文字体不是 Noto Sans SC 可变资源")
	check(is_same(bold.base_font, body.base_font), "正文/粗体字重轴未作用于同一内置字体")
	var server := TextServerManager.get_primary_interface()
	var primary_rids := []
	for pair in [[body, 400.0], [bold, 700.0]]:
		var weight = pair[0].variation_opentype.get(2003265652, -1)
		check(is_equal_approx(float(weight), pair[1]), "正文字重轴应为 %d，实际为 %s" % [pair[1], str(weight)])
		var rids: Array[RID] = pair[0].get_rids()
		if not check(not rids.is_empty(), "正文 %d 字重没有实际字体 RID" % pair[1]): return
		var coordinates := server.font_get_variation_coordinates(rids[0])
		check(is_equal_approx(float(coordinates.get(2003265652, -1)), pair[1]), "TextServer 实际 %d 字重未生效：%s" % [pair[1], str(coordinates)])
		primary_rids.append(rids[0])
	check(primary_rids[0] != primary_rids[1], "400 与 700 字重错误地复用了同一变体 RID")
	finished += 1

func add_characters(value: String, path: String, points: Dictionary) -> void:
	for index in value.length():
		var code := value.unicode_at(index)
		# 空白排版和 C0/C1 控制符不产生字形；注释、标点和符号仍完整扫描。
		if code < 32 or (code >= 127 and code <= 159) or code == 0xFEFF: continue
		if not points.has(code): points[code] = path

func decoded_characters(value: Variant, path: String, points: Dictionary) -> void:
	if value is String: add_characters(value, path, points)
	elif value is Array:
		for item in value: decoded_characters(item, path, points)
	elif value is Dictionary:
		for key in value:
			add_characters(str(key), path, points)
			decoded_characters(value[key], path, points)

func collect(path: String, extension: String, points: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if not check(directory != null, "无法读取字符覆盖目录：" + path): return
	for child in directory.get_directories(): collect(path.path_join(child), extension, points)
	for file in directory.get_files():
		if file.get_extension() != extension: continue
		var source_path := path.path_join(file)
		var text := FileAccess.get_file_as_string(source_path)
		if not check(not text.is_empty(), "源码/数据文件为空或不可读：" + source_path): return
		source_count += 1
		add_characters(text, source_path, points)
		if extension == "json":
			var parser := JSON.new()
			if check(parser.parse(text) == OK, "JSON 无法解码：" + source_path): decoded_characters(parser.data, source_path, points)

func test_character_coverage() -> void:
	var points := {}
	collect("res://scripts", "gd", points)
	collect("res://data", "json", points)
	add_characters("子丑寅卯辰巳午未申酉戌亥0123456789←→↑↓▶Ⅱ★·，。！？：；（）【】《》…—", "十二时辰与常用界面字符", points)
	character_count = points.size()
	check(source_count > 100 and character_count > 1000, "源码/数据扫描范围异常偏小")
	var codes := points.keys()
	codes.sort()
	var fonts := {"book": Fonts.book(), "body": Fonts.body(), "bold": Fonts.bold()}
	for name in fonts:
		var font: Font = fonts[name]
		var missing := PackedStringArray()
		for code in codes:
			if not font.has_char(code): missing.append("%s U+%04X (%s)" % [String.chr(code), code, str(points[code])])
		check(missing.is_empty(), "%s 禁用系统回退后缺字：%s" % [name, "; ".join(missing)])
	finished += 1

func test_consumers() -> void:
	check(is_same(UI.make_theme().default_font, Fonts.book()), "宣纸主题未使用内置楷书")
	check(is_same(UI.dark_theme().default_font, Fonts.body()), "深色主题未使用内置黑体")
	check(is_same(Hud.body_font(), Fonts.body()), "HUD 正文字体未接入统一入口")
	check(is_same(Hud.bold_font(), Fonts.bold()), "HUD 粗体未接入统一入口")
	check(is_same(Kit.font(), Fonts.book()), "3D 招牌字体未接入统一入口")
	var clock := Clock.new()
	clock.size = Vector2(100, 100)
	add_child(clock)
	await get_tree().process_frame
	check(is_same(clock._font, Fonts.book()), "时辰表盘字体未接入统一入口")
	for branch in Clock.BRANCHES: check(clock._font.has_char(branch.unicode_at(0)), "时辰表盘缺字：" + branch)
	var label := Hud.text("劫余录 19:30", 18, Hud.TEXT, true)
	check(is_same(label.get_theme_font("font"), Fonts.bold()), "HUD 粗体 Label 实际主题字体错误")
	label.free()
	clock.queue_free()
	await get_tree().process_frame
	finished += 1
