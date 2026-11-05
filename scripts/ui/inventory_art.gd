extends RefCounted
## 家中存货专用插画。其它入口与家具继续使用原来的 IconArt。
## 图集按固定 4×4 等格读取，不修改或裁写源 PNG；来源见 docs/47。

const RICE = preload("res://assets/ui/inventory/rice.png")
const NAILS = preload("res://assets/ui/inventory/nails.png")
const SHEETS := {
	"food": preload("res://assets/ui/inventory/food_atlas.png"),
	"supplies": preload("res://assets/ui/inventory/supplies_atlas.png"),
	"tools": preload("res://assets/ui/inventory/tools_atlas.png"),
	"misc": preload("res://assets/ui/inventory/misc_atlas.png"),
}
const ITEMS := {
	"food": ["flatbread", "pickles", "jerky", "egg", "cabbage", "radish", "chive", "lingzhi", "water", "congee", "millet_cake", "veg_soup", "fried_rice", "rice_cake", "egg_soup", "eight_treasure"],
	"supplies": ["firewood", "charcoal", "lamp_oil", "diesel", "salve", "plague_powder", "mugwort", "calm_soup", "talisman", "dog_blood", "caltrops", "ink_line", "bagua", "talisman_paper", "cinnabar", "salt"],
	"tools": ["wood", "cart", "barrow", "donkey_cart", "chopper", "peach_sword", "iron_lock", "seed_cabbage", "seed_radish", "seed_chive", "seed_lingzhi", "book_farm", "book_cook", "book_guard", "book_build", "book_daoist"],
	"misc": ["millet", "glutinous", "inkstone", "jade", "bracelet", "lingzhi_soup", "burnt"],
}
const COLUMNS := 4
const ROWS := 4
static var _textures := {}


static func ids() -> Array:
	var result: Array = ["rice", "nails"]
	for group in ITEMS:
		result.append_array(ITEMS[group])
	return result


static func has(id: String) -> bool:
	if id in ["rice", "nails"]:
		return true
	for group in ITEMS:
		if id in ITEMS[group]:
			return true
	return false


static func texture(id: String) -> Texture2D:
	if id == "rice": return RICE
	if id == "nails": return NAILS
	if _textures.has(id): return _textures[id]
	for group in ITEMS:
		var index: int = ITEMS[group].find(id)
		if index < 0: continue
		var sheet: Texture2D = SHEETS[group]
		var cell := sheet.get_size() / Vector2(COLUMNS, ROWS)
		var art := AtlasTexture.new()
		art.atlas = sheet
		art.region = Rect2(Vector2(index % COLUMNS, index / COLUMNS) * cell, cell)
		art.filter_clip = true
		_textures[id] = art
		return art
	return null
