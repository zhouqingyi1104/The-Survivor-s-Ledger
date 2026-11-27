extends Control
## 尚未收录到插画图集的物资或家具使用此控件。

const Art = preload("res://scripts/ui/icon_art.gd")

var id := ""
var is_furn := false


func _draw() -> void:
	if id == "":
		return
	Art.draw(self, id, size.x, is_furn)
