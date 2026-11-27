extends RefCounted
## 临川城的行当字号与野外行动图记。招牌和地点按钮取用同一方画。

const SHEET := preload("res://assets/art/wayfinding/trade-marks.svg")
const FIELD_SHEET := preload("res://assets/art/wayfinding/field-marks.svg")
const KEYS := [&"home", &"rice_shop", &"market", &"grocery", &"smithy", &"pharmacy",
	&"builder", &"temple", &"bookshop", &"pawnshop", &"route", &"time",
	&"pack", &"opening", &"checklist", &"exposure"]
const FIELD_KEYS := [&"door_bar", &"window_board", &"water_vat", &"garden_bed", &"stove",
	&"cellar", &"watchtower", &"generator", &"heater", &"lumber", &"mortuary", &"granary", &"taoist_temple"]
const LANDMARKS := {&"rice_ruin": &"rice_shop", &"city_god": &"temple", &"school": &"bookshop", &"pharmacy_ruin": &"pharmacy"}
static var _regions := {}


static func texture(id: StringName) -> Texture2D:
	id = LANDMARKS.get(id, id)
	if _regions.has(id):
		return _regions[id]
	var sheet := SHEET
	var cell := KEYS.find(id)
	if cell < 0:
		cell = FIELD_KEYS.find(id)
		sheet = FIELD_SHEET
	if cell < 0:
		return null
	var part := AtlasTexture.new()
	part.atlas = sheet
	var side := sheet.get_width() / 4
	part.region = Rect2i((cell % 4) * side, (cell / 4) * side, side, side)
	part.filter_clip = true
	_regions[id] = part
	return part


static func icon(id: StringName, side: int) -> TextureRect:
	var mark := TextureRect.new()
	mark.texture = texture(id)
	mark.custom_minimum_size = Vector2(side, side)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mark


static func on_button(button: Button, id: StringName, side := 22) -> Button:
	button.icon = texture(id)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.add_theme_constant_override("icon_max_width", side)
	button.add_theme_constant_override("h_separation", 6)
	return button
