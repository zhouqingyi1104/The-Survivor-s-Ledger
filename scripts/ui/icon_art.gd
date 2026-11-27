extends RefCounted
## 旧存档或扩展物件缺少专属画稿时使用包袱和木作样件。

const Catalog = preload("res://scripts/ui/inventory_art.gd")
const UNLISTED := preload("res://assets/ui/unlisted-objects.svg")


static func draw(canvas: CanvasItem, id: String, px: float, is_furn := false) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(px, px))
	var art := Catalog.furniture(id) if is_furn else Catalog.texture(id)
	if art != null:
		canvas.draw_texture_rect(art, bounds, false)
		return
	var side := float(UNLISTED.get_height())
	var cell := Rect2(side if is_furn else 0.0, 0.0, side, side)
	canvas.draw_texture_rect_region(UNLISTED, bounds, cell)
