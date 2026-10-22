extends Control
## 一个图标控件：物品 / 家具共用，画法见 icon_art.gd（纯代码画，不用图片）。

const Art = preload("res://scripts/ui/icon_art.gd")

var id := ""
var is_furn := false


func _draw() -> void:
	if id == "":
		return
	Art.draw(self, id, size.x, is_furn)
