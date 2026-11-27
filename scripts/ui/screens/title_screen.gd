extends "res://scripts/ui/screens/screen_base.gd"
## 标题：雪夜远景上叠一页线装书封，题签和菜单沿书脊排列。
## 3D 远景跑在一个 SubViewport 里，界面照旧用代码搭，叠在上面。

const Vignette = preload("res://scripts/world/title_vignette.gd")

const INK_LIGHT := Color("#f1e7cd")
const INK_DIM := Color("#d0d2bf")
const SEAL := Color("#9c453b")
const GOLD := Color("#d8b26a")

var _vig
## 点的是「新开一卷」（快速）还是「自选开局」：有旧卷要先确认合卷，确认完照这个走
var _quick_new := true


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

	# 保留雪面的映光，在画幅底部收墨，让页脚能压住亮雪。
	var wash := GradientTexture2D.new()
	wash.width = 2
	wash.height = 256
	wash.fill_to = Vector2.DOWN
	wash.gradient = Gradient.new()
	wash.gradient.offsets = PackedFloat32Array([0.0, 0.58, 0.84, 1.0])
	wash.gradient.colors = PackedColorArray([Color(0.035,0.075,0.09,0.14),
			Color(0.035,0.075,0.09,0.14), Color(0.04,0.065,0.07,0.29), Color(0.03,0.045,0.05,0.72)])
	var night_ink := TextureRect.new()
	night_ink.texture = wash
	night_ink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	night_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	night_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night_ink)

	# 装订书封承接菜单；街景仅沿书页投下一道窄影。
	var fold := GradientTexture2D.new()
	fold.width = 128
	fold.height = 2
	fold.gradient = Gradient.new()
	fold.gradient.set_color(0, Color(0.035, 0.064, 0.059, 0.62))
	fold.gradient.set_color(1, Color(0.035, 0.064, 0.059, 0))
	fold.fill_to = Vector2.RIGHT
	var shadow := TextureRect.new()
	shadow.texture = fold
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.anchor_bottom = 1
	shadow.offset_left = 327
	shadow.offset_right = 377
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	var cover := TextureRect.new()
	cover.texture = preload("res://assets/ui/title-binding.svg")
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.anchor_bottom = 1
	cover.offset_right = 336
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)

	var title := Label.new()
	title.text = "劫余录"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_top = 54.0 / 720.0
	title.anchor_bottom = 147.0 / 720.0
	title.offset_left = 55
	title.offset_right = 252
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Color("#2d3530"))
	cover.add_child(title)
	var stamp := _seal("尸\n劫")
	stamp.anchor_top = 0.14
	stamp.anchor_bottom = 0.14
	stamp.offset_left = 254
	stamp.offset_right = 278
	stamp.offset_top = -21
	stamp.offset_bottom = 21
	cover.add_child(stamp)
	var en := Label.new()
	en.text = "THE SURVIVOR'S LEDGER"
	en.anchor_top = 147.0 / 720.0
	en.anchor_bottom = en.anchor_top
	en.offset_top = 10
	en.offset_left = 55
	en.add_theme_font_override("font", UI.Fonts.body())
	en.add_theme_font_size_override("font_size", 13)
	en.add_theme_color_override("font_color", Color("#d1c8a8"))
	cover.add_child(en)
	_ignore_pointer(cover)

	# 有续卷或坏档提示时仍可在较矮窗口滚动到末项。
	var scroll := ScrollContainer.new()
	scroll.anchor_top = 0.26
	scroll.anchor_bottom = 1
	scroll.offset_top = 12
	scroll.offset_bottom = -34
	scroll.offset_left = 53
	scroll.offset_right = 296
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var menu := UI.vbox(3)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(menu)

	var meta: Dictionary = Game.meta
	if Game.has_save():
		menu.add_child(_item(_continue_label(), Game.continue_game, true))
	# 第一次玩的人只该点一下就进城：身份、难度、誓约、开局筹备都收进「自选开局」
	menu.add_child(_item("新开一卷", _new_game.bind(true), true,
		"寻常年景、%s、不立愿，直接进城备劫。" % _quick_role_name()))
	menu.add_child(_item("自选开局", _new_game.bind(false), false,
		"自己挑身份、难度、誓约、同院的人与开局筹备。"))
	menu.add_child(_item("心法 · 道心 %d" % int(meta.daoxin), func(): Game.go("talents")))
	menu.add_child(_item("残卷 %d / %d" % [meta.clues.size(), Data.table("clues").size()], _show_clues))
	menu.add_child(_item("玩法说明", func(): Dialogs.manual()))
	menu.add_child(_item("存档备份", func(): Dialogs.save_pack()))
	menu.add_child(_item("导出试玩报告", _export_report))
	menu.add_child(_item("设置", func(): Dialogs.settings(false)))
	menu.add_child(_item("退出", func(): get_tree().quit()))
	# 存档出过事（写坏、写不进、退了备份）就在菜单下面说清楚，不静默吞掉
	if Game.save_notice != "":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.add_child(gap)
		var warn := Label.new()
		warn.text = Game.save_notice
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 14)
		warn.add_theme_color_override("font_color", Color("#e0a08a"))
		menu.add_child(warn)

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

## 「续写此录」在存档有损时把话说在前头，别让玩家点进去才发现退回了一步。
func _continue_label() -> String:
	var st: Dictionary = Game.save_status()
	if st.future: return "续写此录 · 需要新版"
	if st.main: return "续写此录"
	if st.backup: return "续写此录 · 从备份"
	return "续写此录 · 读不出"


func _ignore_pointer(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_pointer(child)


## 项目的文字位置不动；书签色带标出主入口、悬停和键盘焦点。
func _item(text: String, cb: Callable, strong := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(204, 34)
	b.add_theme_font_size_override("font_size", 21 if strong else 18)
	b.add_theme_color_override("font_color", INK_LIGHT if strong else INK_DIM)
	b.add_theme_color_override("font_hover_color", INK_LIGHT)
	b.add_theme_color_override("font_focus_color", INK_LIGHT)
	b.add_theme_color_override("font_pressed_color", Color("#f5d89f"))
	b.add_theme_stylebox_override("normal", _tab(Color("#793e35") if strong else Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", _tab(Color("#4b5950"), GOLD))
	b.add_theme_stylebox_override("focus", _tab(Color(0, 0, 0, 0), GOLD))
	b.add_theme_stylebox_override("pressed", _tab(Color("#683c34"), GOLD))
	b.pressed.connect(cb)
	return b


func _tab(fill: Color, edge := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.border_width_left = 2
	box.content_margin_left = 13
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	return box


func _seal(text: String) -> Control:
	var p := PanelContainer.new()
	var block := StyleBoxFlat.new()
	block.bg_color = SEAL
	block.border_color = Color("#cba273")
	block.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", block)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_constant_override("line_spacing", -3)
	l.add_theme_color_override("font_color", Color("#f4dfb5"))
	p.add_child(l)
	return p


func _tiny(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#ddd8c8"))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.06, 0.82))
	return l


# ---------- 动作 ----------

func _quick_role_name() -> String:
	return str(Data.table("roles").get(Game.quick_role(), {}).get("name", ""))


## quick：「新开一卷」直接开局；否则「自选开局」去选身份。还有旧卷时两条路都先确认合卷。
func _new_game(quick: bool) -> void:
	_quick_new = quick
	if Game.has_save():
		UI.open_modal("confirm_new", "另起一卷？", _build_confirm, true, 520)
	else:
		_begin_new()


func _begin_new() -> void:
	if not _quick_new:
		Game.go("roles")
		return
	var err := Game.quick_start()
	if err != "":
		Game.toast.emit(err)


func _build_confirm(body: VBoxContainer) -> void:
	var st: Dictionary = Game.save_status()
	if st.future or (not st.main and not st.backup):
		body.add_child(UI.para("这一卷来自更新版本或已损坏，不能安全合卷。请先手动留存并移走存档目录中的 save.json 和 save.json.bak，再回来新开。", 18))
		body.add_child(UI.para("存档目录：%s" % ProjectSettings.globalize_path("user://"), 15))
		body.add_child(UI.button("知道了", func(): UI.close_modal("confirm_new")))
		return
	body.add_child(UI.para("还有一卷没写完。新开一卷会把它合上（这一轮的道心照常结算）。", 18))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.button("再想想", func(): UI.close_modal("confirm_new")))
	row.add_child(UI.seal_button("合上旧卷", _discard_and_new))
	body.add_child(row)


func _discard_and_new() -> void:
	UI.close_modal("confirm_new")
	# 读不出的卷不能让后续新局覆盖；结算失败也留在原局。
	if not Game.continue_game(): return
	if not Game.close_book(): return
	_begin_new()


## 试玩报告：把这些事实打包，玩家拿去发过来，我们就能复现那一局。
func _export_report() -> void:
	Dialogs.playtest_feedback()


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
		body.add_child(UI.para("五篇残卷拼在一起：尸劫是青云观主炼尸所致。下一卷，也许可以在血月之前上山。", 18, UI.CINNABAR))


## 版本号只在 project.godot 的 application/config/version 里维护（0.10.0 → "0.10"），界面不再写死。
static func version_label() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0")).trim_suffix(".0")
