extends RefCounted
## 场景里的 HUD 风格（参考原版的布局与信息层级，配色换成中国风）：
## 深色半透明底、金色细描边、正文黑体（数字清楚）、标题楷体；圆形"印章"图标按钮。

const UI = preload("res://scripts/ui/ui_kit.gd")

const BG := Color(0.075, 0.068, 0.06, 0.84)
const BG_SOFT := Color(0.075, 0.068, 0.06, 0.62)
const BORDER := Color(0.72, 0.54, 0.23, 0.55)
const TEXT := Color("#f1e9d8")
const SUB := Color("#b9ae9c")
const FAINT := Color("#80776a")
const GOLD := Color("#d7aa4f")
const RED := Color("#d0574b")
const GREEN := Color("#7fb069")
const CYAN := Color("#8fd0e0")

const BAR_COLORS := {
	"food": Color("#c9a23f"), "water": Color("#4f8fb0"), "mood": Color("#6aa35e"),
	"energy": Color("#9a86c4"), "warmth": Color("#d07a3a"), "hp": Color("#c0463b"),
}
const BAR_ICONS := {"food": "饱", "water": "水", "mood": "神", "energy": "力", "warmth": "温", "hp": "血"}
const BODY_FONTS := ["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei"]

static var _body_font: Font
static var _bold_font: Font


static func body_font() -> Font:
	if _body_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(BODY_FONTS)
		_body_font = f
	return _body_font


static func bold_font() -> Font:
	if _bold_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(BODY_FONTS)
		f.font_weight = 700
		_bold_font = f
	return _bold_font


static func box(bg := BG, border := BORDER, radius := 6, mx := 12, my := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


static func panel(content: Control, bg := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg))
	p.add_child(content)
	return p


## 正文（黑体）。
static func text(t: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", bold_font() if bold else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## 标题（楷体）。
static func title(t: String, size := 22, color := TEXT) -> Label:
	var l := UI.label(t, size, color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func button(t: String, cb: Callable, disabled := false, tip := "", size := 15) -> Button:
	var b := Button.new()
	b.text = t
	b.disabled = disabled
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", body_font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", box(Color(0.12, 0.11, 0.1, 0.9), BORDER, 5, 12, 6))
	b.add_theme_stylebox_override("hover", box(Color(0.25, 0.2, 0.12, 0.95), GOLD, 5, 12, 6))
	b.add_theme_stylebox_override("pressed", box(Color(0.32, 0.24, 0.12, 0.95), GOLD, 5, 12, 6))
	b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.1, 0.1, 0.7), Color(0.4, 0.4, 0.4, 0.4), 5, 12, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.pressed.connect(cb)
	return b


## 高亮的主按钮（绿色，像原版菜单里的首选项）。
static func primary(t: String, cb: Callable, disabled := false, tip := "", size := 15) -> Button:
	var b := button(t, cb, disabled, tip, size)
	b.add_theme_stylebox_override("normal", box(Color("#3d6b3a"), Color("#7fb069"), 5, 12, 6))
	b.add_theme_stylebox_override("hover", box(Color("#4d8449"), Color("#a4d38c"), 5, 12, 6))
	return b


## 圆形印章按钮：一个字的图标，旁边写名字和快捷键。
class SealButton extends Button:
	var glyph := ""
	var accent := Color("#d7aa4f")

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0 - 1.0
		var c := size / 2.0
		var hovered := is_hovered()
		draw_circle(c, r, Color(0.08, 0.07, 0.06, 0.88))
		draw_arc(c, r, 0, TAU, 40, accent if hovered else Color(accent, 0.6), 1.5, true)
		draw_arc(c, r - 4, 0, TAU, 40, Color(accent, 0.25), 1.0, true)
		var f := get_theme_default_font()
		var fs := int(r * 0.95)
		var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if hovered else Color("#f1e9d8"))


static func seal(glyph: String, cb: Callable, tip := "", d := 44.0) -> Button:
	var b := SealButton.new()
	b.glyph = glyph
	b.custom_minimum_size = Vector2(d, d)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(cb)
	return b


## 右侧功能行：文字 + 快捷键 + 印章按钮（原版的 side-func-row）。
static func func_row(label: String, hotkey: String, glyph: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 8)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	var l := text(label, 15, TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(l)
	if hotkey != "":
		var k := text(hotkey, 11, SUB)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(k)
	h.add_child(v)
	h.add_child(seal(glyph, cb, label))
	return h


## 状态条一行：图标 + 名字 + 条 + 数值。返回 {row, bar, value}，每帧只改数值不重建。
static func stat_row(key: String, name_text: String, width := 150.0) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var icon := PanelContainer.new()
	icon.add_theme_stylebox_override("panel", box(Color(BAR_COLORS[key], 0.85), Color(1, 1, 1, 0.15), 11, 4, 0))
	icon.custom_minimum_size = Vector2(22, 22)
	var il := text(BAR_ICONS[key], 13, Color.WHITE, true)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_child(il)
	h.add_child(icon)
	var n := text(name_text, 14, TEXT, true)
	n.custom_minimum_size.x = 34
	h.add_child(n)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.08), 3, 0, 0))
	bar.add_theme_stylebox_override("fill", box(BAR_COLORS[key], Color(0, 0, 0, 0), 3, 0, 0))
	h.add_child(bar)
	var v := text("", 14, TEXT, true)
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return {"row": h, "bar": bar, "value": v}


static func tag(t: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(color, 0.85), Color(1, 1, 1, 0.2), 4, 8, 2))
	p.add_child(text(t, 13, Color.WHITE, true))
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	return p


## 进度小条（场景标签、忙碌进度用）。
static func mini_bar(color: Color, w := 70.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(w, 7)
	bar.add_theme_stylebox_override("background", box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 2, 0, 0))
	bar.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 2, 0, 0))
	return bar


## 把控件钉在屏幕某个角上（按最小尺寸）。
static func pin(c: Control, anchor: int, margin: int) -> Control:
	c.set_anchors_and_offsets_preset(anchor, Control.PRESET_MODE_MINSIZE, margin)
	var right: bool = anchor in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]
	var bottom: bool = anchor in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	var center_h: bool = anchor in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if center_h else (Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	return c


## 游戏分钟数 → "1天04:16" / "04:16"
static func duration(minutes: float) -> String:
	var m := maxi(0, int(minutes))
	var d := m / 1440
	var hh := (m % 1440) / 60
	var mm := m % 60
	if d > 0:
		return "%d天%02d:%02d" % [d, hh, mm]
	return "%02d:%02d" % [hh, mm]
