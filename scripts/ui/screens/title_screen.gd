extends "res://scripts/ui/screens/screen_base.gd"
## 标题：一片会动的雪夜远景（3D），左侧竖排菜单，左下角题名。
## 3D 远景跑在一个 SubViewport 里，界面照旧用代码搭，叠在上面。

const Vignette = preload("res://scripts/world/title_vignette.gd")

const INK_LIGHT := Color("#e8dfcc")
const INK_DIM := Color("#98a4b2")
const SEAL := Color("#c0392b")
const GOLD := Color("#d8b26a")

var _vig
var _base_modulate := 1.0


func build() -> void:
	# ---- 背景：3D 远景 ----
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	_vig = Vignette.new()
	vp.add_child(_vig)
	var bg := TextureRect.new()
	bg.texture = vp.get_texture()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ---- 压暗：整体一层，左侧与底部再各来一道，文字才压得住雪 ----
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.10)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	add_child(_grad(Color(0.02, 0.03, 0.05, 0.74), Color(0.02, 0.03, 0.05, 0.0), Vector2(0.5, 0.0)))
	add_child(_grad(Color(0.02, 0.03, 0.05, 0.0), Color(0.02, 0.03, 0.05, 0.72), Vector2(0.0, 0.55)))

	# ---- 左侧菜单 ----
	var left := UI.full_rect(MarginContainer.new())
	for side in ["left", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + side, 0)
	left.add_theme_constant_override("margin_left", 64)
	left.add_theme_constant_override("margin_top", 150)
	left.add_theme_constant_override("margin_bottom", 120)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var menu := UI.vbox(6)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.custom_minimum_size.x = 240
	left.add_child(menu)

	var meta: Dictionary = Game.meta
	if Game.has_save():
		menu.add_child(_item("续写此录", Game.continue_game, true))
	menu.add_child(_item("新开一卷", _new_game, true))
	menu.add_child(_item("心法 · 道心 %d" % int(meta.daoxin), func(): Game.go("talents")))
	menu.add_child(_item("残卷 %d / %d" % [meta.clues.size(), Data.table("clues").size()], _show_clues))
	menu.add_child(_item("设置", func(): Dialogs.settings(false)))
	menu.add_child(_item("制作名单", _show_credits))
	menu.add_child(_item("退出", func(): get_tree().quit()))

	# ---- 左下角：题名 ----
	var bottom := UI.full_rect(MarginContainer.new())
	bottom.add_theme_constant_override("margin_left", 64)
	bottom.add_theme_constant_override("margin_bottom", 54)
	bottom.add_theme_constant_override("margin_right", 64)
	bottom.add_theme_constant_override("margin_top", 54)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var col := UI.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(col)

	var seal_row := UI.hbox(10)
	var seal := _seal("尸 劫")
	seal.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	seal_row.add_child(seal)
	var line := ColorRect.new()
	line.color = SEAL
	line.custom_minimum_size = Vector2(120, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	seal_row.add_child(line)
	col.add_child(seal_row)
	var title := Label.new()
	title.text = "劫余录"
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", INK_LIGHT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	col.add_child(title)
	var en := Label.new()
	en.text = "T H E   S U R V I V O R ' S   L E D G E R"
	en.add_theme_font_size_override("font_size", 14)
	en.add_theme_color_override("font_color", INK_DIM)
	col.add_child(en)

	# ---- 底部一行小字 ----
	var foot := UI.full_rect(MarginContainer.new())
	foot.add_theme_constant_override("margin_bottom", 16)
	foot.add_theme_constant_override("margin_right", 22)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)
	var foot_col := UI.vbox(0)
	foot_col.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(foot_col)
	var foot_row := UI.hbox(16)
	foot_row.alignment = BoxContainer.ALIGNMENT_END
	foot_row.add_child(_tiny("已轮回 %d 次 · 最久活到第 %d 日 · 劫满 %d 次" % [
		int(meta.runs), int(meta.best_day), int(meta.endings)]))
	foot_row.add_child(_tiny("原型 v" + version_label()))
	foot_col.add_child(foot_row)
	# Decorative descendants also cover the menu: ignoring only their parent
	# does not prevent children from intercepting pointer input.
	_ignore_pointer(bottom)
	_ignore_pointer(foot)

	# 入场：整屏淡入
	modulate = Color(1, 1, 1, 0.0)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1, 1), 1.1)


func _process(_delta: float) -> void:
	if _vig == null:
		return
	var m := get_viewport().get_mouse_position()
	var s := get_viewport().get_visible_rect().size
	if s.x > 1.0 and s.y > 1.0:
		_vig.set_parallax(m / s)


# ---------- 小件 ----------

func _ignore_pointer(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_pointer(child)


## 左侧菜单的一条：平时是灰的，指上去变暖白并沉下去一点。
func _item(text: String, cb: Callable, strong := false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20 if strong else 18)
	b.add_theme_color_override("font_color", INK_LIGHT if strong else INK_DIM)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", SEAL)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	b.custom_minimum_size = Vector2(210, 32)
	b.mouse_entered.connect(func(): b.position.x = 6.0)
	b.mouse_exited.connect(func(): b.position.x = 0.0)
	b.pressed.connect(cb)
	return b


func _seal(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEAL
	sb.border_color = Color("#8e2a22")
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("#f6e7cf"))
	p.add_child(l)
	return p


func _tiny(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.72, 0.77, 0.84, 0.62))
	return l


## 一道方向渐变，用来压暗画面边缘。
func _grad(from: Color, to: Color, dir_vec: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill_from = Vector2.ZERO
	t.fill_to = dir_vec
	var tr := TextureRect.new()
	tr.texture = t
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ---------- 动作 ----------

func _new_game() -> void:
	if Game.has_save():
		UI.open_modal("confirm_new", "另起一卷？", _build_confirm, true, 520)
	else:
		Game.go("roles")


func _build_confirm(body: VBoxContainer) -> void:
	body.add_child(UI.para("还有一卷没写完。新开一卷会把它合上（这一轮的道心照常结算）。", 18))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.button("再想想", func(): UI.close_modal("confirm_new")))
	row.add_child(UI.seal_button("合上旧卷", _discard_and_new))
	body.add_child(row)


func _discard_and_new() -> void:
	UI.close_modal("confirm_new")
	Game.continue_game()
	Game.close_book()
	Game.go("roles")


func _show_clues() -> void:
	UI.open_modal("clues", "残卷", _build_clues, true, 640)


func _build_clues(body: VBoxContainer) -> void:
	var clues: Dictionary = Data.table("clues")
	for id in clues:
		var known: bool = id in Game.meta.clues
		var row := UI.vbox(2)
		row.add_child(UI.label(clues[id].name, 20, UI.CINNABAR if known else UI.INK_FAINT))
		row.add_child(UI.para(clues[id].text if known else "（还没读到这一页）", 17, UI.INK if known else UI.INK_FAINT))
		body.add_child(row)
	if Game.meta.clues.size() >= clues.size():
		body.add_child(UI.sep())
		body.add_child(UI.para("五篇残卷拼在一起，真相只有一个：尸劫是青云观主炼尸所致。下一卷，也许可以在血月之前上山。", 18, UI.CINNABAR))


func _show_credits() -> void:
	UI.open_modal("credits", "制作名单", _build_credits, true, 680)


## 第三方美术资源的来源和许可证（data/credits.json）。
func _build_credits(body: VBoxContainer) -> void:
	var credits: Dictionary = Data.table("credits")
	# 条目多了会超出屏幕，放进滚动区
	var list := UI.vbox(8)
	for id in credits:
		var row := UI.vbox(2)
		row.add_child(UI.label(credits[id].name, 20, UI.CINNABAR))
		for line in credits[id].lines:
			row.add_child(UI.para(line, 16))
		list.add_child(row)
	body.add_child(UI.scroll(list, 520))


## 版本号只在 project.godot 的 application/config/version 里维护（0.10.0 → "0.10"），界面不再写死。
static func version_label() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0")).trim_suffix(".0")
