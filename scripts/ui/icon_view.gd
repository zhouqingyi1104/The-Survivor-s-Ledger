extends Control
## 尚未收录到插画图集的物资或家具使用此控件。

const Art = preload("res://scripts/ui/icon_art.gd")

var id := ""
var is_furn := false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	if id == "":
		return
	var side := minf(size.x, size.y)
	draw_set_transform((size - Vector2.ONE * side) * 0.5)
	Art.draw(self, id, side, is_furn)
