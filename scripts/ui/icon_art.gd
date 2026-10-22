extends RefCounted
## 物品 / 家具图标：全部用 CanvasItem 现画（墨线 + 淡彩），不依赖任何图片资源。
## 画布固定按 48×48 的格算，调用方给实际像素，这里统一缩放。
## 每件东西认不出细节没关系，要能一眼分出"这是米还是符"。

const S := 38.0
const INK := Color("#2f2a24")
const INK_SOFT := Color("#5a5148")
const PAPER := Color("#efe7d6")
const RICE := Color("#e2d3ae")
const MALT := Color("#c9a86a")
const MEAT := Color("#a8524a")
const LEAF := Color("#5f7f47")
const LEAF_D := Color("#41582f")
const ROOT := Color("#c98b52")
const WATER := Color("#5a7f88")
const FIRE := Color("#c1522f")
const CHAR := Color("#4a4642")
const MED := Color("#8f6f4a")
const BLOOD := Color("#7a2b26")
const GOLD := Color("#c49a3c")
const JADE := Color("#7f9d84")
const WOOD := Color("#8a6243")
const WOOD_D := Color("#5b3b29")
const STONE := Color("#8b8681")
const IRON := Color("#6d737a")
const CLOTH := Color("#8f9aa6")
const SILVER := Color("#b9bfc4")


static func draw(c: CanvasItem, id: String, px: float, is_furn := false) -> void:
	var k := px / S
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	# 底下淡淡一圈影子，图标才不会飘
	c.draw_circle(Vector2(24, 40), 11.0, Color(0, 0, 0, 0.07))
	if is_furn:
		_furn(c, id)
	else:
		_item(c, id)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------- 小工具 ----------

static func _r(c, col: Color, x: float, y: float, w: float, h: float) -> void:
	c.draw_rect(Rect2(x, y, w, h), col, true)


static func _o(c, col: Color, x: float, y: float, w: float, h: float, wd := 1.6) -> void:
	c.draw_rect(Rect2(x, y, w, h), col, false, wd)


static func _c(c, col: Color, cx: float, cy: float, r: float) -> void:
	c.draw_circle(Vector2(cx, cy), r, col)


static func _p(c, col: Color, pts: Array) -> void:
	var v := PackedVector2Array()
	for p in pts:
		v.append(Vector2(p[0], p[1]))
	c.draw_colored_polygon(v, col)


static func _l(c, col: Color, x1: float, y1: float, x2: float, y2: float, wd := 1.6) -> void:
	c.draw_line(Vector2(x1, y1), Vector2(x2, y2), col, wd)


static func _arc(c, col: Color, cx: float, cy: float, r: float, a0: float, a1: float, wd := 1.8) -> void:
	c.draw_arc(Vector2(cx, cy), r, a0, a1, 20, col, wd)


# ---------- 物品 ----------

static func _item(c, id: String) -> void:
	match id:
		"rice", "millet", "glutinous":
			_sack(c, RICE if id == "rice" else (MALT if id == "millet" else Color("#efe8d8")))
		"flatbread", "millet_cake", "rice_cake", "eight_treasure":
			_cake(c, MALT if id != "eight_treasure" else Color("#b57a5a"))
		"congee", "veg_soup", "egg_soup", "lingzhi_soup", "fried_rice":
			_bowl(c, _dish_color(id), _dish_garnish(id))
		"burnt":
			_bowl(c, CHAR)
		"pickles":
			_jar(c, LEAF_D, true)
		"jerky":
			_meat(c)
		"egg":
			_c(c, Color("#efe6d2"), 24, 26, 11)
			_c(c, Color("#d9a33c"), 24, 26, 5)
		"cabbage":
			_leafy(c, LEAF, LEAF.darkened(0.25))
		"radish":
			_p(c, ROOT, [[24, 12], [31, 22], [28, 34], [20, 34], [17, 22]])
			_l(c, LEAF_D, 24, 12, 21, 6)
			_l(c, LEAF_D, 24, 12, 27, 6)
		"chive":
			_leafy(c, Color("#6d9450"), LEAF_D)
		"lingzhi":
			_c(c, Color("#8e4a34"), 24, 26, 10)
			_c(c, Color("#c98b52"), 24, 26, 6)
			_r(c, WOOD_D, 22, 30, 4, 9)
		"mugwort":
			_herb(c)
		"water":
			_gourd(c)
		"firewood":
			_bundle(c, WOOD, WOOD_D)
		"charcoal":
			_bundle(c, Color("#3a3632"), CHAR)
		"lamp_oil":
			_jar(c, GOLD.darkened(0.1), false)
			_l(c, FIRE, 24, 14, 24, 8, 2.0)
		"salve", "plague_powder", "calm_soup":
			_packet(c, MED if id == "salve" else (Color("#7a8f6a") if id == "plague_powder" else Color("#9a7f9e")))
		"talisman", "talisman_paper":
			_talisman(c, RICE if id == "talisman_paper" else Color("#e8d49a"))
		"dog_blood":
			_jar(c, BLOOD, false)
		"caltrops":
			_spikes(c)
		"ink_line":
			_box(c, WOOD_D)
			_l(c, INK, 14, 30, 34, 30, 2.0)
			_c(c, INK, 34, 30, 2.6)
		"bagua":
			_mirror(c)
		"wood":
			_planks(c)
		"nails":
			_spikes(c, IRON)
		"cinnabar":
			_jar(c, FIRE.darkened(0.15), false)
		"cart":
			_cart(c)
		"chopper":
			_blade(c, IRON, true)
		"peach_sword":
			_blade(c, WOOD, false)
		"iron_lock":
			_lock(c)
		"seed_cabbage", "seed_radish", "seed_chive", "seed_lingzhi":
			_seedbag(c)
		"book_farm", "book_cook", "book_guard", "book_build", "book_daoist":
			_book(c, _book_color(id))
		"inkstone":
			_r(c, CHAR, 13, 22, 22, 12)
			_r(c, Color("#1d1a17"), 16, 25, 16, 6)
		"jade":
			_p(c, JADE, [[24, 12], [33, 26], [24, 38], [15, 26]])
		"bracelet":
			_arc(c, SILVER, 24, 26, 11, 0, TAU, 3.0)
		_:
			_box(c, INK_SOFT)


static func _dish_color(id: String) -> Color:
	match id:
		"congee":
			return Color("#efe6cf")
		"veg_soup":
			return LEAF
		"egg_soup":
			return Color("#e8cf8a")
		"lingzhi_soup":
			return Color("#8e4a34")
		"fried_rice":
			return Color("#c9a05a")
	return RICE


## 汤菜上的配料点：让白粥、菜汤、蛋花汤分得开。
static func _dish_garnish(id: String) -> Color:
	match id:
		"veg_soup":
			return LEAF_D
		"egg_soup":
			return Color("#d9a33c")
		"lingzhi_soup":
			return Color("#b06a4a")
		"fried_rice":
			return MEAT
	return Color(0, 0, 0, 0)


static func _book_color(id: String) -> Color:
	match id:
		"book_farm":
			return LEAF_D
		"book_cook":
			return ROOT
		"book_guard":
			return BLOOD
		"book_build":
			return MED
	return Color("#3d4a5a")


## 木箱：没有专门形状的东西用它兜底。
static func _box(c, fill: Color) -> void:
	_r(c, fill, 14, 20, 20, 16)
	_o(c, INK, 14, 20, 20, 16, 1.4)
	_l(c, fill.lightened(0.25), 14, 28, 34, 28, 1.4)
	_l(c, INK_SOFT, 24, 20, 24, 36, 1.2)


static func _sack(c, fill: Color) -> void:
	_p(c, fill, [[15, 22], [33, 22], [36, 36], [30, 40], [18, 40], [12, 36]])
	_l(c, INK_SOFT, 15, 22, 33, 22, 1.8)
	_l(c, WOOD_D, 19, 18, 29, 18, 2.2)
	_l(c, WOOD_D, 24, 18, 24, 22, 2.2)
	_c(c, RICE.darkened(0.1), 24, 20, 1.6)


static func _bowl(c, fill: Color, garnish := Color(0, 0, 0, 0)) -> void:
	_p(c, Color("#e6ddc8"), [[11, 22], [37, 22], [32, 36], [16, 36]])
	_arc(c, INK, 24, 22, 13, 0.15, PI - 0.15, 1.8)
	_p(c, fill, [[14, 23], [34, 23], [31, 27], [17, 27]])
	if garnish.a > 0.05:
		for i in 3:
			_c(c, garnish, 19 + i * 5, 24.5 + (i % 2) * 1.2, 1.5)
	for i in 2:
		_l(c, Color(1, 1, 1, 0.5), 20 + i * 6, 14, 19 + i * 6, 9, 1.4)


static func _cake(c, fill: Color) -> void:
	_c(c, fill, 24, 28, 12)
	_arc(c, INK, 24, 28, 12, 0, TAU, 1.6)
	for i in 3:
		_c(c, fill.darkened(0.25), 20 + i * 4, 26 + (i % 2) * 4, 1.4)


static func _jar(c, fill: Color, wide: bool) -> void:
	var w := 18.0 if wide else 14.0
	_p(c, fill, [[24 - w / 2, 20], [24 + w / 2, 20], [24 + w / 2 + 2, 34], [24 - w / 2 - 2, 34]])
	_r(c, Color("#6a5a4a"), 24 - w / 2 - 2, 17, w + 4, 4)
	_arc(c, INK, 24, 27, w / 2 + 1, -PI / 2, PI / 2, 1.4)


static func _meat(c) -> void:
	_p(c, MEAT, [[14, 20], [34, 17], [35, 30], [15, 33]])
	_l(c, MEAT.darkened(0.3), 18, 22, 18, 31, 1.4)
	_l(c, Color("#e0c9a0"), 30, 19, 30, 30, 2.2)


static func _leafy(c, light: Color, dark: Color) -> void:
	_c(c, light, 24, 27, 12)
	_arc(c, dark, 24, 27, 12, PI * 0.15, PI * 0.85, 2.0)
	_l(c, dark, 24, 15, 24, 20, 2.0)


static func _herb(c) -> void:
	_l(c, LEAF_D, 24, 14, 24, 38, 1.8)
	for i in 4:
		var y := 18.0 + i * 5.0
		_l(c, LEAF, 24, y, 17, y - 4, 1.6)
		_l(c, LEAF, 24, y, 31, y - 4, 1.6)


static func _gourd(c) -> void:
	_c(c, WATER, 24, 31, 9)
	_c(c, WATER, 24, 20, 6)
	_r(c, WOOD_D, 23, 12, 2, 5)
	c.draw_arc(Vector2(24, 31), 9, 0, TAU, 20, INK, 1.4)
	c.draw_arc(Vector2(24, 20), 6, 0, TAU, 20, INK, 1.4)


static func _bundle(c, light: Color, dark: Color) -> void:
	for i in 3:
		var y := 20.0 + i * 7.0
		_l(c, light, 13, y, 35, y - 2, 5.0)
		_l(c, dark, 13, y + 2, 35, y, 1.6)
	_l(c, Color("#8a7a5a"), 21, 18, 21, 40, 2.0)
	_l(c, Color("#8a7a5a"), 28, 18, 28, 40, 2.0)


static func _packet(c, fill: Color) -> void:
	_p(c, PAPER, [[14, 18], [34, 18], [32, 38], [16, 38]])
	_r(c, fill, 18, 22, 12, 8)
	_l(c, INK_SOFT, 14, 18, 34, 18, 1.6)
	_l(c, Color("#a33"), 24, 14, 24, 22, 1.6)


static func _talisman(c, paper: Color) -> void:
	_r(c, paper, 17, 10, 14, 28)
	_o(c, INK_SOFT, 17, 10, 14, 28, 1.2)
	_l(c, BLOOD, 24, 14, 24, 33, 2.2)
	for i in 3:
		_l(c, BLOOD, 20, 17 + i * 5, 28, 17 + i * 5, 1.3)


static func _spikes(c, col := IRON) -> void:
	for i in 3:
		var x := 15.0 + i * 9.0
		_p(c, col, [[x, 34], [x + 4, 34], [x + 2, 24]])
	_l(c, INK_SOFT, 12, 35, 36, 35, 1.6)


static func _mirror(c) -> void:
	var pts := []
	for i in 8:
		var a := TAU * i / 8.0 - PI / 8.0
		pts.append([24 + cos(a) * 12.0, 24 + sin(a) * 12.0])
	_p(c, GOLD.darkened(0.15), pts)
	_c(c, Color("#d8d2c4"), 24, 24, 7)
	_c(c, INK_SOFT, 24, 29, 2.8)


static func _planks(c) -> void:
	for i in 2:
		var y := 22.0 + i * 7.0
		_r(c, WOOD, 12, y, 24, 5)
		_o(c, WOOD_D, 12, y, 24, 5, 1.0)
	_c(c, IRON, 20, 24, 1.4)


static func _cart(c) -> void:
	_c(c, WOOD_D, 18, 32, 8)
	_c(c, WOOD, 18, 32, 5)
	c.draw_arc(Vector2(18, 32), 8, 0, TAU, 18, INK, 1.4)
	_l(c, WOOD_D, 18, 32, 34, 22, 2.2)
	_l(c, WOOD_D, 26, 22, 38, 22, 2.2)
	_l(c, WOOD_D, 34, 22, 34, 32, 2.2)


static func _blade(c, col: Color, short: bool) -> void:
	var tip := 22.0 if short else 10.0
	_p(c, col, [[22, 34], [30, 26], [30, tip + 4], [22, tip]])
	_l(c, WOOD_D, 22, 34, 32, 42, 3.0)
	_l(c, GOLD, 24, 32, 30, 34, 2.0)


static func _lock(c) -> void:
	_arc(c, IRON, 24, 22, 7, PI, TAU, 2.4)
	_r(c, IRON.lightened(0.1), 15, 24, 18, 14)
	_c(c, INK, 24, 31, 2.2)


static func _seedbag(c) -> void:
	_p(c, Color("#d9c49a"), [[16, 20], [32, 20], [30, 38], [18, 38]])
	_l(c, WOOD_D, 16, 20, 32, 20, 2.0)
	for i in 4:
		_c(c, Color("#6a5236"), 19 + (i % 2) * 10, 26 + int(i / 2) * 6, 1.8)


static func _book(c, cover: Color) -> void:
	_r(c, cover, 14, 14, 20, 24)
	_o(c, INK, 14, 14, 20, 24, 1.4)
	_r(c, Color("#efe7d6"), 16, 16, 3, 20)
	for i in 3:
		_l(c, Color(0.95, 0.93, 0.86, 0.85), 22, 20 + i * 5, 31, 20 + i * 5, 1.2)


# ---------- 家具 ----------

static func _furn(c, id: String) -> void:
	match id:
		"bed":
			_r(c, WOOD, 9, 26, 30, 12)
			_r(c, Color("#cfc6b2"), 11, 24, 26, 6)
			_l(c, WOOD_D, 9, 38, 9, 42, 2.0)
			_l(c, WOOD_D, 39, 38, 39, 42, 2.0)
		"desk":
			_table(c, 1.0)
			_r(c, PAPER, 18, 18, 10, 6)
			_l(c, WOOD_D, 16, 22, 22, 16, 1.4)
		"bench":
			_r(c, WOOD, 8, 24, 32, 7)
			_l(c, WOOD_D, 11, 31, 11, 40, 3.0)
			_l(c, WOOD_D, 37, 31, 37, 40, 3.0)
			_l(c, IRON, 16, 16, 22, 24, 2.0)
		"storage":
			_r(c, WOOD_D, 13, 12, 22, 30)
			for i in 3:
				_l(c, WOOD, 13, 18 + i * 9, 35, 18 + i * 9, 1.6)
			_c(c, GOLD, 24, 27, 1.6)
		"stove":
			_r(c, Color("#7b5a4c"), 10, 24, 28, 16)
			_arc(c, Color("#2a2826"), 18, 26, 4.5, 0, TAU, 2.0)
			_arc(c, Color("#2a2826"), 30, 26, 4.5, 0, TAU, 2.0)
			_c(c, FIRE, 18, 26, 2.2)
			_c(c, FIRE, 30, 26, 2.2)
		"bookshelf", "screen":
			_r(c, WOOD_D, 12, 10, 24, 32)
			for i in 3:
				_l(c, WOOD, 12, 19 + i * 8, 36, 19 + i * 8, 1.6)
				for j in 2:
					_r(c, CLOTH if (i + j) % 2 else PAPER, 15 + j * 11, 13 + i * 8, 7, 6)
		"rice_jar", "pickle_jar", "water_vat":
			_jar(c, RICE if id == "rice_jar" else (LEAF_D if id == "pickle_jar" else WATER), true)
		"planter":
			_r(c, WOOD, 10, 28, 28, 11)
			_r(c, Color("#5f4a3a"), 12, 26, 24, 3)
			for i in 3:
				_c(c, LEAF, 16 + i * 8, 22, 4)
		"brazier":
			_p(c, STONE, [[13, 26], [35, 26], [32, 38], [16, 38]])
			_c(c, FIRE, 24, 28, 4)
			_l(c, FIRE.darkened(0.2), 24, 24, 22, 18, 1.6)
		"smoke_rack":
			_l(c, WOOD_D, 14, 14, 14, 40, 3.0)
			_l(c, WOOD_D, 34, 14, 34, 40, 3.0)
			_l(c, WOOD, 14, 18, 34, 18, 3.0)
			for i in 2:
				_c(c, MEAT, 19 + i * 10, 24, 3.4)
		"rat_trap":
			_r(c, WOOD, 12, 30, 24, 7)
			_l(c, IRON, 12, 30, 36, 22, 1.8)
		"incense":
			_r(c, WOOD_D, 19, 26, 10, 12)
			_r(c, GOLD, 17, 24, 14, 3)
			_l(c, INK_SOFT, 24, 24, 24, 14, 1.2)
		"armchair":
			_r(c, WOOD, 14, 22, 20, 6)
			_r(c, WOOD_D, 14, 12, 20, 10)
			_l(c, WOOD_D, 14, 28, 14, 38, 3.0)
			_l(c, WOOD_D, 34, 28, 34, 38, 3.0)
		"tea_table":
			_table(c, 0.8)
			_c(c, PAPER, 24, 20, 4)
		"bamboo":
			_r(c, Color("#5f4a3a"), 16, 30, 16, 9)
			for i in 3:
				_l(c, LEAF_D, 20 + i * 4, 30, 18 + i * 5, 12, 2.0)
		_:
			_table(c, 1.0)


static func _table(c, scale: float) -> void:
	_r(c, WOOD, 24 - 14 * scale, 22, 28 * scale, 5)
	_l(c, WOOD_D, 24 - 12 * scale, 27, 24 - 12 * scale, 40, 2.6)
	_l(c, WOOD_D, 24 + 12 * scale, 27, 24 + 12 * scale, 40, 2.6)
