extends Control
## 时辰表盘：一圈十二时辰（子在顶、午在底），上半圈是夜、下半圈是昼，金针指着当前时刻。
## 对应原版右上角的 24 小时表盘。

const UI = preload("res://scripts/ui/ui_kit.gd")

const BRANCHES := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const NIGHT := Color("#18223a")
const DAY := Color("#7a4f2c")
const RING := Color("#d7aa4f")

## 钟面时刻（0..1439，0 = 子夜）
var minutes := 0:
	set(v):
		minutes = v
		queue_redraw()
var alert_minute := -1   # 尸潮时刻，表盘上点一个红点

var _font: Font


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(UI.FONT_NAMES)
	_font = f
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _point(c: Vector2, r: float, minute: float) -> Vector2:
	var a := minute / 1440.0 * TAU
	return c + Vector2(sin(a), -cos(a)) * r


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	# 昼夜两半：18:00→6:00 经过子时（顶）是夜
	draw_circle(c, r, DAY)
	var pts := PackedVector2Array([c])
	for k in 33:
		pts.append(_point(c, r, 1080.0 + k * (720.0 / 32.0)))
	draw_colored_polygon(pts, NIGHT)
	draw_arc(c, r, 0, TAU, 64, RING, 2.0, true)
	draw_arc(c, r - 3.5, 0, TAU, 64, Color(RING, 0.35), 1.0, true)
	# 刻度与时辰字
	for k in 24:
		var inner := r - (7.0 if k % 2 == 0 else 4.0)
		draw_line(_point(c, inner, k * 60.0), _point(c, r - 1.5, k * 60.0), Color(1, 1, 1, 0.55), 1.0, true)
	var fs := int(r * 0.24)
	for k in 12:
		# 子时以 0:00 为中
		var p := _point(c, r * 0.72, k * 120.0)
		var w := _font.get_string_size(BRANCHES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, p + Vector2(-w / 2.0, fs * 0.36), BRANCHES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
	if alert_minute >= 0:
		draw_circle(_point(c, r - 9.0, alert_minute), 3.5, Color("#e0503f"))
	# 指针
	var tip := _point(c, r * 0.86, minutes)
	draw_line(c, tip, Color("#f3d48a"), 2.5, true)
	draw_circle(tip, 3.0, Color("#f3d48a"))
	draw_circle(c, 4.0, RING)
	draw_circle(_point(c, r + 0.5, 0.0), 3.0, RING)
