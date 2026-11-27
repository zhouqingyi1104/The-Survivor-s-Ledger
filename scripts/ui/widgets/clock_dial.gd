extends Control
## 外圈读十二时辰，内圈分昼夜，朱针始终停在字圈以内。

const Fonts = preload("res://scripts/ui/fonts.gd")

const BRANCHES := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const INK := Color("#403e35")
const FACE := Color("#e5dac0")
const BRASS := Color("#a48b62")
const NIGHT := Color("#4c676d")
const DAY := Color("#d5ae79")
const POINTER := Color("#953f32")

## 钟面时刻（0..1439，0 = 子夜）
var minutes := 0:
	set(v):
		if v == minutes:
			return
		minutes = v
		queue_redraw()
var alert_minute := -1:
	set(v):
		if v == alert_minute:
			return
		alert_minute = v
		queue_redraw()

var _font: Font


func _ready() -> void:
	_font = Fonts.book()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _point(c: Vector2, r: float, minute: float) -> Vector2:
	var a := minute / 1440.0 * TAU
	return c + Vector2(sin(a), -cos(a)) * r


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	if r <= 2.0:
		return
	draw_circle(c, r, INK, true, -1.0, true)
	draw_circle(c, r - 1.6, FACE, true, -1.0, true)
	draw_arc(c, r - 3.0, 0, TAU, 72, BRASS, 1.2, true)
	# 一小时一刻，正时稍长，刻线只占外缘。
	for k in 24:
		var angle_minutes := k * 60.0
		var inner := r * (0.84 if k % 2 == 0 else 0.89)
		draw_line(_point(c, inner, angle_minutes), _point(c, r - 3.0, angle_minutes), BRASS, 1.15, true)
	var fs := maxi(6, roundi(r * 0.27))
	var baseline := (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	for k in 12:
		var p := _point(c, r * 0.715, k * 120.0)
		var w := _font.get_string_size(BRANCHES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, (p + Vector2(-w * 0.5, baseline)).round(), BRANCHES[k],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)

	# 昼夜两半：18:00→6:00 经过子时（顶）是夜
	var disc := r * 0.49
	draw_circle(c, disc, DAY, true, -1.0, true)
	var pts := PackedVector2Array([c])
	for k in 33:
		pts.append(_point(c, disc, 1080.0 + k * (720.0 / 32.0)))
	draw_colored_polygon(pts, NIGHT)
	var moon := c - Vector2(0, disc * 0.53)
	draw_circle(moon, disc * 0.21, FACE, true, -1.0, true)
	draw_circle(moon + Vector2(disc * 0.10, -disc * 0.07), disc * 0.18, NIGHT, true, -1.0, true)
	draw_circle(c + Vector2(0, disc * 0.53), disc * 0.19, Color("#f6deaa"), true, -1.0, true)
	draw_arc(c, disc, 0, TAU, 64, BRASS, 1.0, true)

	# 白边朱针在青黑和赭色上都清楚；尾配重比针尖短。
	var tip := _point(c, r * 0.47, minutes)
	var axis := (tip - c).normalized()
	var shoulder := axis.orthogonal() * (r * 0.055)
	var needle := PackedVector2Array([tip, c + shoulder, c - axis * r * 0.16, c - shoulder, tip])
	draw_colored_polygon(needle.slice(0, 4), POINTER)
	draw_polyline(needle, Color("#f6e5c5"), 1.15, true)
	draw_circle(c, r * 0.046, INK, true, -1.0, true)
	if alert_minute >= 0:
		var mark := _point(c, r - 3.2, alert_minute)
		draw_circle(mark, r * 0.081, INK, true, -1.0, true)
		draw_circle(mark, r * 0.058, Color("#dc7858"), true, -1.0, true)
