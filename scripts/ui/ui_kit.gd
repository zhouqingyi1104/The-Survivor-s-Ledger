extends RefCounted
## 界面工具：中国风主题（宣纸、墨、朱砂、黛青）和常用控件的构造函数。界面全部用代码搭。
##
## 两套色板：宣纸（标题、选身份这些 2D 页面）和夜色（3D 场景上弹的窗，和 HUD 一个调子）。
## 色名不变，值随 use_dark() 切换——main.gd 在 3D 场景上搭弹窗时切到夜色，搭完切回来，
## 所以弹窗内容的代码不用管自己在哪种底色上。

const PAPER_COLORS := {
	"paper": Color("#efe6d2"), "paper_light": Color("#f7f0e1"), "paper_dark": Color("#e2d5b8"),
	"ink": Color("#2b2620"), "ink_soft": Color("#6a5e52"), "ink_faint": Color("#a39785"),
	"cinnabar": Color("#a8322d"), "dai": Color("#3d5a5b"), "gold": Color("#b8893b"), "jade": Color("#5b7d5a"),
	"ember": Color("#c46a2b"), "border": Color("#8c7b65"), "panel": Color("#f5eddc"),
}
const DARK_COLORS := {
	"paper": Color("#191612"), "paper_light": Color("#1d1a16"), "paper_dark": Color("#100e0c"),
	"ink": Color("#f1e9d8"), "ink_soft": Color("#c9bfae"), "ink_faint": Color("#8a8072"),
	"cinnabar": Color("#e0685b"), "dai": Color("#8fc4cf"), "gold": Color("#d7aa4f"), "jade": Color("#8cc070"),
	"ember": Color("#e8955a"), "border": Color(0.72, 0.54, 0.23, 0.6), "panel": Color("#211d18"),
}

static var PAPER := Color("#efe6d2")
static var PAPER_LIGHT := Color("#f7f0e1")
static var PAPER_DARK := Color("#e2d5b8")
static var INK := Color("#2b2620")
static var INK_SOFT := Color("#6a5e52")
static var INK_FAINT := Color("#a39785")
static var CINNABAR := Color("#a8322d")
static var DAI := Color("#3d5a5b")
static var GOLD := Color("#b8893b")
static var JADE := Color("#5b7d5a")
static var EMBER := Color("#c46a2b")
static var BORDER := Color("#8c7b65")
static var PANEL := Color("#f5eddc")
static var dark := false
static var _dark_theme: Theme

const FONT_NAMES := ["KaiTi", "STKaiti", "楷体", "Kaiti SC", "SimSun", "Songti SC", "Microsoft YaHei",
	"Noto Serif CJK SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei"]

## 主场景（main.gd）启动时把自己挂在这里，弹窗和提示都找它。
static var host: Node = null


static func use_dark(on: bool) -> void:
	dark = on
	var c: Dictionary = DARK_COLORS if on else PAPER_COLORS
	PAPER = c.paper
	PAPER_LIGHT = c.paper_light
	PAPER_DARK = c.paper_dark
	INK = c.ink
	INK_SOFT = c.ink_soft
	INK_FAINT = c.ink_faint
	CINNABAR = c.cinnabar
	DAI = c.dai
	GOLD = c.gold
	JADE = c.jade
	EMBER = c.ember
	BORDER = c.border
	PANEL = c.panel


## 夜色主题：和 HUD 同样的深底、金边、雅黑正文。
static func dark_theme() -> Theme:
	if _dark_theme != null:
		return _dark_theme
	var c := DARK_COLORS
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC"] + FONT_NAMES)
	t.default_font = font
	t.default_font_size = 17
	t.set_color("font_color", "Label", c.ink)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", c.ink)
	t.set_stylebox("normal", "Button", _box(Color(0.12, 0.11, 0.1, 0.92), c.border, 1, 5, 12, 6))
	t.set_stylebox("hover", "Button", _box(Color(0.25, 0.2, 0.12, 0.96), c.gold, 1, 5, 12, 6))
	t.set_stylebox("pressed", "Button", _box(Color(0.32, 0.24, 0.12, 0.96), c.gold, 2, 5, 12, 6))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.1, 0.1, 0.7), Color(0.4, 0.4, 0.4, 0.4), 1, 5, 12, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", c.ink)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", c.gold)
	t.set_color("font_focus_color", "Button", c.ink)
	t.set_color("font_disabled_color", "Button", c.ink_faint)
	var panel := _box(Color(0.075, 0.068, 0.06, 0.94), c.border, 1, 6, 16, 14)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(c.ink_soft, Color(0, 0, 0, 0), 0, 3, 0, 0))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.06, 0.055, 0.05, 0.96), c.border, 1, 4, 10, 6))
	t.set_color("font_color", "TooltipLabel", c.ink)
	var sep := StyleBoxLine.new()
	sep.color = Color(0.72, 0.54, 0.23, 0.35)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	_dark_theme = t
	return t


static func make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	t.default_font = font
	t.default_font_size = 19

	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)

	t.set_stylebox("normal", "Button", _box(Color("#f6efe0"), INK_SOFT, 1, 3, 12, 6))
	t.set_stylebox("hover", "Button", _box(Color("#fbf7ee"), CINNABAR, 1, 3, 12, 6))
	t.set_stylebox("pressed", "Button", _box(Color("#e8dcc2"), CINNABAR, 2, 3, 12, 6))
	t.set_stylebox("disabled", "Button", _box(Color("#ebe3d2"), Color("#cbbfa7"), 1, 3, 12, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", CINNABAR)
	t.set_color("font_pressed_color", "Button", CINNABAR)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_FAINT)

	var panel := _box(Color("#f5eddc"), Color("#8c7b65"), 2, 4, 14, 12)
	panel.shadow_color = Color(0.2, 0.15, 0.08, 0.18)
	panel.shadow_size = 4
	t.set_stylebox("panel", "PanelContainer", panel)

	t.set_stylebox("background", "ProgressBar", _box(Color("#d9ccb0"), Color("#b3a487"), 1, 2, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(INK_SOFT, Color(0, 0, 0, 0), 0, 2, 0, 0))

	t.set_stylebox("panel", "TooltipPanel", _box(PAPER_LIGHT, INK_SOFT, 1, 3, 10, 6))
	t.set_color("font_color", "TooltipLabel", INK)

	var sep := StyleBoxLine.new()
	sep.color = Color("#c7b896")
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	return t


static func _box(bg: Color, border: Color, border_w: int, radius: int, mx: int, my: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


# ---------- 控件 ----------

static func label(text: String, size := 0, color := INK, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color != INK:
		l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 单行文字，超出宽度显示省略号（HUD 用：自动换行的文字在布局前会把面板撑得很高）。
static func line(text: String, size: int, color: Color, width: float) -> Label:
	var l := label(text, size, color)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = width
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## 日志的单行版本，给 HUD 用。
static func log_lines(lines: Array, count: int, size: int, width: float) -> VBoxContainer:
	var v := vbox(2)
	for k in range(maxi(0, lines.size() - count), lines.size()):
		var text: String = lines[k]
		var cut := text.find("】")
		if text.begins_with("【") and cut > 0:
			text = text.substr(cut + 1)
		v.add_child(line(text, size, INK, width))
	return v


static func heading(text: String, size := 26, color := INK) -> Label:
	return label(text, size, color)


static func para(text: String, size := 0, color := INK_SOFT) -> Label:
	return label(text, size, color, true)


static func button(text: String, cb: Callable, disabled := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	if tip != "":
		b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


## 主要操作用的朱砂按钮。
static func seal_button(text: String, cb: Callable, disabled := false, tip := "") -> Button:
	var b := button(text, cb, disabled, tip)
	b.add_theme_stylebox_override("normal", _box(Color("#a8322d"), Color("#7d211d"), 1, 3, 16, 8))
	b.add_theme_stylebox_override("hover", _box(Color("#bb3d37"), Color("#7d211d"), 1, 3, 16, 8))
	b.add_theme_stylebox_override("pressed", _box(Color("#8f2a26"), Color("#5e1916"), 1, 3, 16, 8))
	b.add_theme_color_override("font_color", Color("#f7f0e1"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("#f7f0e1"))
	return b


static func panel(content: Control = null, bg := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	if bg != PANEL:
		var sb := _box(bg, BORDER, 1 if dark else 2, 6 if dark else 4, 14, 12)
		p.add_theme_stylebox_override("panel", sb)
	if content != null:
		p.add_child(content)
	return p


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func grid(columns: int, hsep := 8, vsep := 6) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	return g


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func sep() -> HSeparator:
	return HSeparator.new()


static func expand(c: Control, ratio := 1.0) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	return c


static func fixed_width(c: Control, w: float) -> Control:
	c.custom_minimum_size.x = w
	return c


static func bar(value: float, max_value: float, color: Color, w := 0.0, h := 14.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = max_value
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	if w <= 0:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", _box(color, Color(0, 0, 0, 0), 0, 2, 0, 0))
	return b


## 名称 + 进度条 + 数值 一行。
static func stat_row(name_text: String, value: int, max_value: int, color: Color, name_w := 56.0) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(fixed_width(label(name_text, 18, INK_SOFT), name_w))
	h.add_child(bar(value, max_value, color))
	h.add_child(fixed_width(label("%d/%d" % [value, max_value], 16, INK_SOFT), 70))
	return h


## 小色签，用来标状态（不足 / 拥挤 / 已沦陷……）。
static func tag(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(color, 0.14), color, 1, 3, 6, 1)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(label(text, 15, color))
	return p


static func scroll(child: Control, min_h := 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size.y = min_h
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## 日志行：去掉【】里的时间前缀后着色。
static func log_view(lines: Array, count: int, size := 16) -> VBoxContainer:
	var v := vbox(3)
	var start := maxi(0, lines.size() - count)
	for k in range(start, lines.size()):
		var line: String = lines[k]
		var h := hbox(6)
		var cut := line.find("】")
		if line.begins_with("【") and cut > 0:
			h.add_child(fixed_width(label(line.substr(1, cut - 1), size - 2, INK_FAINT), 128))
			h.add_child(label(line.substr(cut + 1), size, INK, true))
		else:
			h.add_child(label(line, size, INK, true))
		v.add_child(h)
	return v


# ---------- 弹窗 / 提示（转给 main.gd） ----------

static func open_modal(key: String, title: String, build: Callable, closable := true, width := 760.0) -> void:
	if host != null:
		host.open_modal(key, title, build, closable, width)


static func close_modal(key: String) -> void:
	if host != null:
		host.close_modal(key)


static func has_modal(key: String) -> bool:
	return host != null and host.has_modal(key)
