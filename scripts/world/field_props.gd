extends RefCounted
## 搜寻点的物件都以地面为原点；通路、封锁和交互碰撞由 RuinWorld 管理。

const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")
const House = preload("res://scripts/world/home_house.gd")
const Props = preload("res://scripts/world/props.gd")


static func book(parent: Node3D, pos: Vector3, tilt := -8.0) -> void:
	var n := K.node(parent, pos, Vector3(0, tilt, 0))
	var indigo := K.mat(Color("#48575b"), 0.93)
	K.box(n, Vector3(0.42, 0.044, 0.29), Color("#c5b393"), Vector3.UP * 0.026)
	for y in [0.004, 0.052]:
		K.box(n, Vector3(0.436, 0.008, 0.30), indigo, Vector3(0, y, 0))
	K.box(n, Vector3(0.061, 0.002, 0.17), Color("#d8c8a9"), Vector3(0.143, 0.057, -0.016))
	for i in 4:
		K.box(n, Vector3(0.031, 0.007, 0.005), Color("#b6ab91"), Vector3(-0.20, 0.056, i * 0.07 - 0.107))


static func gate(parent: Node3D, span: float, across_x: bool) -> void:
	var n := K.node(parent, Vector3.ZERO, Vector3(0, 90 if across_x else 0, 0))
	for side in [-1, 1]:
		K.box(n, Vector3(0.16, 2.1, 0.26), K.WOOD, Vector3(side * (span * 0.5 - 0.08), 1.05, 0))
		for i in 6:
			var width := (span * 0.5 - 0.20) / 6.0
			K.box(n, Vector3(width - 0.012, 1.88, 0.105), K.WOOD_LIGHT,
				Vector3(side * (0.022 + width * (i + 0.5)), 0.98, 0))
		for y in [0.37, 1.59]:
			K.box(n, Vector3(span * 0.5 - 0.20, 0.12, 0.18), K.WOOD, Vector3(side * span * 0.244, y, 0))
	K.box(n, Vector3(span, 0.15, 0.29), K.WOOD, Vector3.UP * 2.025)
	K.box(n, Vector3(1.28, 0.092, 0.092), K.WOOD, Vector3(0, 0.96, 0.12))
	for x in [-0.34, 0.34]:
		K.box(n, Vector3(0.066, 0.17, 0.12), K.mat(Color("#615a50"), 0.49), Vector3(x, 0.96, 0.126))
	House.finish_joinery(n)
	K.merge_static(n, [])


static func clue(parent: Node3D, site: String, key: String) -> void:
	if key == "gate":
		match site:
			"city_god": table(parent, true)
			"pharmacy_ruin": medicine_tray(parent)
			"school": Props.bookshelf(parent, Vector3.ZERO)
			"lumber": Props.workbench(parent, Vector3.ZERO, 12, false)
			_: chest(parent)
	elif key == "clue_0" and site not in ["city_god", "granary"]:
		var desk := K.node(parent)
		desk.scale = Vector3.ONE * 0.76
		table(desk, false)
	else:
		var stone := (site == "city_god" and key == "clue_0") or site == "taoist_temple"
		var plaque := K.node(parent, Vector3.ZERO, Vector3(0, -8, 0))
		K.box(plaque, Vector3(0.54, 0.12, 0.40), K.STONE_DARK if stone else K.WOOD, Vector3.UP * 0.06)
		K.box(plaque, Vector3(0.44, 0.71, 0.115), K.STONE if stone else K.WOOD_LIGHT, Vector3.UP * 0.465)
		K.box(plaque, Vector3(0.28, 0.49, 0.012), K.STONE_DARK if stone else Color("#b3a78a"), Vector3(0, 0.47, 0.064))
		for i in 3:
			K.box(plaque, Vector3(0.014, 0.27 - 0.05 * i, 0.003), Color("#655c4e"), Vector3((i - 1) * 0.066, 0.50, 0.072))
		House.finish_joinery(plaque)
		K.merge_static(plaque, [])


static func handcart(parent: Node3D) -> void:
	var iron := K.mat(Color("#4f4b43"), 0.51)
	K.cyl(parent, 0.059, 0.059, 1.32, iron, Vector3(0, 0.40, -0.13), Vector3(0, 0, 90), 12)
	for side in [-1, 1]:
		var wheel := K.node(parent, Vector3(side * 0.586, 0.40, -0.13))
		var tire := TorusMesh.new()
		tire.inner_radius = 0.345
		tire.outer_radius = 0.40
		tire.rings = 28
		tire.ring_segments = 8
		K._mesh(wheel, tire, iron, Vector3.ZERO, Vector3(0, 0, 90))
		K.cyl(wheel, 0.087, 0.093, 0.16, K.WOOD, Vector3.ZERO, Vector3(0, 0, 90), 16)
		for i in 6:
			K.box(wheel, Vector3(0.043, 0.727, 0.040), K.WOOD_LIGHT, Vector3.ZERO, Vector3(30.0 * i, 0, 0))
		K.box(parent, Vector3(0.079, 0.10, 2.35), K.WOOD, Vector3(side * 0.39, 0.45, 0.19), Vector3(5, 0, 0))
		K.box(parent, Vector3(0.064, 0.34, 1.38), K.WOOD, Vector3(side * 0.50, 0.71, -0.18))
	for i in 6:
		K.box(parent, Vector3(0.151, 0.057, 1.41), K.WOOD_LIGHT, Vector3((i - 2.5) * 0.161, 0.523, -0.18))
	K.box(parent, Vector3(1.02, 0.27, 0.064), K.WOOD, Vector3(0, 0.68, -0.89))
	var cargo := Props.rice_sacks(parent, Vector3(0.05, 0.553, -0.25), 2)
	cargo.scale = Vector3.ONE * 0.79
	House.finish_joinery(parent)
	K.merge_static(parent, [])


static func coffin(parent: Node3D, opened: bool) -> void:
	# 首端较宽，足端收窄；挪开棺盖时可以看到底板和围板的内侧。
	K.box(parent, Vector3(0.65, 0.084, 1.90), K.WOOD, Vector3.UP * 0.13)
	for z in [-0.68, 0.62]:
		K.box(parent, Vector3(0.80, 0.13, 0.118), K.WOOD, Vector3(0, 0.065, z))
	for side in [-1, 1]:
		for row in 3:
			K.box(parent, Vector3(0.058, 0.171, 1.91), K.WOOD, Vector3(side * 0.338, 0.254 + row * 0.174, 0),
				Vector3(0, side * -3.4, 0))
	for end in [-1, 1]:
		var width := 0.831 if end < 0 else 0.603
		K.box(parent, Vector3(width, 0.518, 0.068), K.WOOD, Vector3(0, 0.426, end * 0.933))
	var lid := K.node(parent, Vector3(0.275, 0.88, 0.06) if opened else Vector3.UP * 0.72,
		Vector3(0, 4, -31) if opened else Vector3.ZERO)
	for i in 5:
		K.box(lid, Vector3(0.167, 0.072, 2.0 - absf(i - 2.0) * 0.065), K.WOOD_LIGHT,
			Vector3((i - 2) * 0.165, 0.038 - absf(i - 2.0) * 0.014, 0))
	House.finish_joinery(parent)


static func chest(parent: Node3D, offering := false) -> void:
	K.box(parent, Vector3(0.85, 0.51, 0.54), K.WOOD, Vector3.UP * 0.32)
	for x in [-0.34, 0.34]:
		K.box(parent, Vector3(0.100, 0.08, 0.56), K.WOOD, Vector3(x, 0.04, 0))
		K.box(parent, Vector3(0.048, 0.53, 0.552), K.mat(Color("#5c5144"), 0.56), Vector3(x, 0.33, 0))
	K.box(parent, Vector3(0.90, 0.081, 0.58), K.WOOD_LIGHT, Vector3.UP * 0.619)
	if offering:
		K.box(parent, Vector3(0.24, 0.004, 0.029), Color("#29221c"), Vector3(0, 0.661, 0.014))
	K.box(parent, Vector3(0.076, 0.10, 0.026), K.mat(K.GOLD, 0.48), Vector3(0, 0.547, 0.290))
	House.finish_joinery(parent)
	K.merge_static(parent, [])


static func station(parent: Node3D, site: String, stage: String) -> void:
	var detail := K.node(parent, Vector3.UP * 0.045)
	detail.scale = Vector3.ONE * 0.65
	match site + "/" + stage:
		"school/s0", "pharmacy_ruin/s0", "mortuary/s0", "granary/s3", "taoist_temple/s2", "taoist_temple/s7":
			book(detail, Vector3.ZERO)
			return
		"school/s1":
			var shelf := Props.bookshelf(detail, Vector3.ZERO)
			shelf.rotation_degrees.z = 8
			shelf.position.y = 0.09
			return
		"school/s2", "mortuary/s7":
			Props.bedding(detail, Vector3.ZERO, 0.78)
			return
		"pharmacy_ruin/s1", "pharmacy_ruin/s4", "taoist_temple/s5":
			medicine_tray(detail)
			return
		"pharmacy_ruin/s3", "mortuary/s3", "mortuary/s6", "taoist_temple/s6":
			chest(detail)
			return
		"granary/s2":
			handcart(detail)
			return
		"lumber/s0", "lumber/s3":
			Props.workbench(detail, Vector3.ZERO, -8, false)
			return
		"lumber/s1", "lumber/s4", "granary/s1", "granary/s7":
			Props.wood_pile(detail, Vector3.ZERO, 4)
			return
		"granary/s4", "granary/s5", "city_god/s0", "city_god/s2", "taoist_temple/s0":
			Props.basket(detail, Vector3.ZERO, K.WOOD_LIGHT)
			return
		"taoist_temple/s3":
			Props.garden_plot(detail, Vector3.ZERO, "lingzhi", 0.8, false)
			return
	match site:
		"rice_ruin", "granary": Props.rice_sacks(detail, Vector3(0.16, 0, 0.13), 2)
		"lumber": Props.firewood(detail, Vector3.ZERO, 3)
		"pharmacy_ruin": Assets.prop(detail, "ceramic_pot", Vector3.ZERO, -13, 0.90, false)
		_:
			K.cyl(detail, 0.30, 0.34, 0.075, K.STONE_DARK, Vector3.UP * 0.037, Vector3.ZERO, 16)
			Assets.prop(detail, "ceramic_vase_02", Vector3(-0.06, 0.075, 0.01), 18, 0.78, false)


static func medicine_tray(parent: Node3D) -> void:
	var tray := K.node(parent)
	for x in [-0.46, 0.46]:
		K.box(tray, Vector3(0.085, 0.082, 0.60), K.WOOD, Vector3(x, 0.041, 0))
	for row in 4:
		K.box(tray, Vector3(1.24, 0.045, 0.142), K.WOOD_LIGHT, Vector3(0, 0.1045, (row - 1.5) * 0.146))
	for side in [-1, 1]:
		K.box(tray, Vector3(1.27, 0.064, 0.029), K.WOOD, Vector3(0, 0.14, side * 0.298))
		K.box(tray, Vector3(0.029, 0.082, 0.59), K.WOOD, Vector3(side * 0.622, 0.148, 0))
	House.finish_joinery(tray)
	K.merge_static(tray, [])
	Assets.prop(parent, "ceramic_pot", Vector3(-0.38, 0.127, -0.01), 12, 0.88, false)
	Assets.prop(parent, "ceramic_vase_02", Vector3(-0.03, 0.127, -0.075), -20, 0.72, false)
	book(parent, Vector3(0.34, 0.127, 0.055), 4)


static func table(parent: Node3D, offering: bool) -> void:
	var id := "chinese_console_table" if offering else "chinese_tea_table"
	var ref := Assets.prop(parent, id, Vector3.ZERO, 0.0, 0.78, false)
	var top := 0.70
	if ref != null:
		top = Assets.local_aabb(ref).end.y
	else:
		K.box(parent, Vector3(1.36, 0.09, 0.65), K.WOOD, Vector3.UP * (top - 0.045))
		for x in [-0.59, 0.59]:
			for z in [-0.23, 0.23]:
				K.box(parent, Vector3(0.072, top - 0.08, 0.072), K.WOOD, Vector3(x, (top - 0.08) * 0.5, z))
	if offering:
		Props.altar_items(parent, Vector3.UP * top)
	else:
		book(parent, Vector3(0.15, top, 0.02))
		book(parent, Vector3(0.13, top + 0.058, 0.018), 3)


static func spot(parent: Node3D, label: String) -> void:
	match label:
		"前厅棺木", "地下停尸间":
			coffin(parent, label == "地下停尸间")
			K.collider(parent, Vector3(0.8, 0.8, 2.0), Vector3.UP * 0.4)
		"粮车": handcart(parent)
		"米仓", "后院粮袋", "东仓", "西仓": Props.rice_sacks(parent, Vector3.ZERO, 5)
		"药柜", "柜台", "封存药柜":
			var furnishing := Assets.prop(parent, "chinese_cabinet", Vector3(0, 0, -0.3), 0, 0.8, false)
			if furnishing == null:
				chest(parent)
			K.collider(parent, Vector3(1.4, 2, 0.6), Vector3(0, 1, -0.3))
		"伙计铺盖", "斋舍", "看场人屋", "掌柜卧房", "守庄人屋", "观主静室":
			var bed_z := 0.77 if label == "掌柜卧房" else 0.0
			var mat := K.node(parent, Vector3(0, 0.047, bed_z), Vector3(0, 78, 0))
			Props.bedding(mat, Vector3.ZERO, 0.86)
			if label == "掌柜卧房":
				Assets.prop(parent, "chinese_cabinet", Vector3(0, 0, -0.3), 0, 0.80, false)
				K.collider(parent, Vector3(1.4, 2, 0.6), Vector3(0, 1, -0.3))
		"供桌", "香案下", "后堂供案", "偏殿": table(parent, true)
		"账房", "讲堂", "教谕书房", "仓吏房", "守庄人药账", "炼尸阵的运尸簿": table(parent, false)
		"观主七灯图与后山道图":
			table(parent, false)
			var maps := K.node(parent, Vector3(-0.28, 0.06, 0.67), Vector3(0, 12, 0))
			K.box(maps, Vector3(0.66, 0.014, 0.38), K.PAPER, Vector3.UP * 0.008)
			for x in [-0.32, 0.32]:
				K.cyl(maps, 0.043, 0.043, 0.42, K.PAPER, Vector3(x, 0.044, 0), Vector3(90, 0, 0), 14)
		"七星灯阵眼 · 按图封阵":
			var altar := K.node(parent)
			K.cyl(altar, 0.62, 0.69, 0.14, K.STONE, Vector3.UP * 0.07, Vector3.ZERO, 16)
			var marks := [Vector2(-0.38, 0.17), Vector2(-0.23, 0.31), Vector2(-0.02, 0.17),
				Vector2(-0.17, 0.02), Vector2(0.02, -0.07), Vector2(0.23, -0.12), Vector2(0.34, -0.30)]
			for mark: Vector2 in marks:
				K.cyl(altar, 0.065, 0.040, 0.045, K.mat(Color("#92704b"), 0.53),
					Vector3(mark.x, 0.163, mark.y), Vector3.ZERO, 12)
				K.sphere(altar, 0.018, K.mat(Color("#edac65"), 0.7, 0.8),
					Vector3(mark.x, 0.195, mark.y), Vector3(0.60, 1.35, 0.60))
			K.merge_static(altar, [])
		"藏书阁", "经阁": Props.bookshelf(parent, Vector3.ZERO)
		"木垛": Props.wood_pile(parent, Vector3.ZERO, 6)
		"工棚", "铁匠角": Props.workbench(parent, Vector3.ZERO, 0, false)
		"灵田": Props.garden_plot(parent, Vector3.ZERO, "lingzhi", 0.8, false)
		"后堂", "炮制间", "丹房":
			medicine_tray(parent)
		_: chest(parent, label == "功德箱")
