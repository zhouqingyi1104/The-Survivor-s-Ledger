extends RefCounted
## 分拣台、储物架、垫仓板分别成组。旧存档已有家具时，调用方可以单独让出其中一处。
const K = preload("res://scripts/world/kit.gd")
const House = preload("res://scripts/world/home_house.gd")
const Props = preload("res://scripts/world/props.gd")
const Pieces = preload("res://scripts/world/household_models.gd")
const Field = preload("res://scripts/world/field_props.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Planting = preload("res://scripts/world/yard_planting.gd")
## 顺着进货的次序装满各组，Vector2i 分别以斗、颗计。
const STOCK_CAPACITY := {&"delivery": Vector2i(5, 5), &"pantry": Vector2i(3, 5), &"sorting": Vector2i(1, 0)}
static var _cover_mesh: ArrayMesh
static var _crock_mesh: ArrayMesh
static var _cabbage: ArrayMesh


static func build_group(group: String, parent: Node3D) -> void:
	match group:
		"sorting":
			_sorting_table(parent)
		"pantry":
			_pantry_shelves(parent)
		"delivery":
			_receiving_platform(parent)
		"carrier":
			_carrying_yoke(parent)
	House.finish_joinery(parent)
	K.merge_static(parent, [])
	if STOCK_CAPACITY.has(StringName(group)):
		K.node(parent, Vector3.ZERO, Vector3.ZERO, "Stock")


static func sync_stock(groups: Dictionary, home: Dictionary) -> void:
	var available := Vector2i(maxi(0, Inv.total(home, Inv.GRAINS)), maxi(0, Inv.count(home, "cabbage")))
	for id: StringName in STOCK_CAPACITY:
		if not groups.has(id):
			continue
		var display: Node3D = groups[id].get_node("Stock")
		var shown := available.min(STOCK_CAPACITY[id])
		available -= shown
		if display.get_meta("shown", Vector2i(-1, -1)) == shown:
			continue
		display.set_meta("shown", shown)
		K.clear(display)
		match id:
			&"delivery":
				_platform_stock(display, shown.x)
				_basket_stock(display, Vector3(0.49, 0.30, 0.09), 1.12, shown.y)
			&"pantry":
				_shelf_stock(display, shown.x)
				_basket_stock(display, Vector3(0.20, 1.698, 0.08), 0.74, shown.y)
			&"sorting":
				if shown.x:
					Pieces.place(display, &"Sack", Vector3(0.37, 0.38, 0.02))
				else:
					_folded_sacks(display, Vector3(0.37, 0.38, 0.02), 3)
		House.finish_joinery(display)
		K.merge_static(display, [])


static func _sorting_table(table: Node3D) -> void:
	# 靠通道一边量米、记账。下层的箩筐可以从端头抽出来。
	for x: float in [-0.77, 0.77]:
		for z: float in [-0.38, 0.38]:
			K.box(table, Vector3(0.095, 0.85, 0.095), House.TIMBER, Vector3(x, 0.525, z))
		K.box(table, Vector3(0.072, 0.095, 0.86), House.TRIM, Vector3(x, 0.305, 0))
	for z: float in [-0.375, 0.375]:
		K.box(table, Vector3(1.63, 0.14, 0.074), House.TIMBER, Vector3(0, 0.869, z))
	for i in 4:
		K.box(table, Vector3(1.79, 0.060, 0.247), House.TRIM, Vector3(0, 0.956, (i - 1.5) * 0.251))
	for i in 3:
		K.box(table, Vector3(1.58, 0.051, 0.19), House.TRIM, Vector3(0, 0.35, (i - 1) * 0.205))
	_basket(table, Vector3(-0.40, 0.377, 0.025), 0.82)
	_basket(table, Vector3(-0.39, 0.47, 0.025), 0.84)
	var scale_stand := K.node(table, Vector3(-0.345, 0.986, -0.045))
	_steelyard(scale_stand)
	var measure := K.node(table, Vector3(0.55, 0.986, -0.146), Vector3(0, -12, 0))
	_grain_measure(measure)
	Field.book(table, Vector3(0.43, 0.987, 0.275), 10.0)


static func _steelyard(stand: Node3D) -> void:
	var brass := K.mat(Color("#ac895a"), 0.45)
	var iron := K.mat(Color("#534d45"), 0.52)
	var cord := K.mat(Color("#8a7553"), 0.93)
	K.box(stand, Vector3(0.26, 0.05, 0.25), House.TIMBER, Vector3(0, 0.025, -0.20))
	K.box(stand, Vector3(0.048, 0.62, 0.055), House.TRIM, Vector3(0, 0.35, -0.21))
	K.box(stand, Vector3(0.055, 0.045, 0.32), House.TRIM, Vector3(0, 0.65, -0.085))
	_line(stand, Vector3(0, 0.64, 0.052), Vector3(0, 0.508, 0.052), 0.008, cord)
	# 秤盘在短臂一端，砣绳挂在较长的带刻度秤杆上。
	_line(stand, Vector3(-0.255, 0.50, 0.052), Vector3(0.525, 0.517, 0.052), 0.015, K.mat(House.TIMBER))
	for i in 8:
		var x := 0.05 + i * 0.059
		K.cyl(stand, 0.016, 0.016, 0.008, brass, Vector3(x, 0.506 + x * 0.021, 0.052), Vector3(0, 0, 90), 10)
	var hook := Vector3(-0.214, 0.50, 0.052)
	var center := Vector3(-0.214, 0.138, 0.052)
	for i in 3:
		var angle := i * TAU / 3.0 + PI * 0.5
		_line(stand, hook, center + Vector3(cos(angle) * 0.17, 0.047, sin(angle) * 0.17), 0.0065, cord)
	var pan := Props._turned_vessel(PackedVector2Array([
		Vector2(0.001, 0.006), Vector2(0.075, 0.009), Vector2(0.15, 0.030),
		Vector2(0.181, 0.047), Vector2(0.177, 0.052), Vector2(0.144, 0.037), Vector2(0.001, 0.016)]))
	K._mesh(stand, pan, brass, center)
	_line(stand, Vector3(0.315, 0.514, 0.052), Vector3(0.315, 0.387, 0.052), 0.008, cord)
	K.cyl(stand, 0.028, 0.054, 0.078, iron, Vector3(0.315, 0.350, 0.052), Vector3.ZERO, 12)


static func _line(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var segment := K.cyl(parent, radius, radius, a.distance_to(b), material, (a + b) * 0.5, Vector3.ZERO, 8)
	segment.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


static func _grain_measure(parent: Node3D) -> void:
	# 木斗上口宽、底小，贯穿口沿的小木梁可提起整只斗。
	K.box(parent, Vector3(0.284, 0.035, 0.284), House.TIMBER, Vector3.UP * 0.02)
	for side: float in [-1.0, 1.0]:
		K.box(parent, Vector3(0.023, 0.202, 0.365), House.TRIM, Vector3(side * 0.163, 0.116, 0), Vector3(0, 0, -side * 13.0))
		K.box(parent, Vector3(0.340, 0.202, 0.023), House.TRIM, Vector3(0, 0.116, side * 0.163), Vector3(side * 13.0, 0, 0))
		K.box(parent, Vector3(0.026, 0.027, 0.390), House.TIMBER, Vector3(side * 0.185, 0.214, 0))
		K.box(parent, Vector3(0.351, 0.027, 0.026), House.TIMBER, Vector3(0, 0.214, side * 0.185))
	K.box(parent, Vector3(0.373, 0.033, 0.037), House.TRIM, Vector3(0, 0.228, -0.018))


static func _pantry_shelves(rack: Node3D) -> void:
	# 高架和矮架共用中央一对柱。留透背，玩家在通道中仍看得见后面的灯龛。
	for x: float in [-0.96, -0.04, 0.96]:
		var height := 1.17 if x < -0.9 else 1.91
		for z: float in [-0.36, 0.36]:
			K.box(rack, Vector3(0.072, height, 0.080), House.TIMBER, Vector3(x, 0.10 + height * 0.5, z))
	_shelf(rack, 0, 0.29, 2.00)
	_shelf(rack, 0, 1.00, 2.00)
	_shelf(rack, 0.46, 1.67, 1.08)
	for x: float in [-0.50, 0.46]:
		K.box(rack, Vector3(0.061, 1.12, 0.042), House.TRIM, Vector3(x, 0.64, -0.36), Vector3(0, 0, -54))
	# 重的封口坛贴近下层，浅箩和拿取频繁的干货放在伸手可及处。
	_sealed_vessel(rack, Vector3(-0.60, 0.318, 0), 0.74, Color("#94543d"))
	_sealed_vessel(rack, Vector3(-0.03, 0.318, 0.044), 0.68, Color("#867556"))
	Props.storage_jar(K.node(rack, Vector3(0.55, 0.318, 0)), 0.72, false)
	_basket(rack, Vector3(-0.61, 1.029, 0.035), 0.84)
	_basket(rack, Vector3(-0.61, 1.117, 0.035), 0.86)
	_sealed_vessel(rack, Vector3(-0.10, 1.029, 0.07), 0.45, Color("#647975"))
	_sealed_vessel(rack, Vector3(0.73, 1.698, -0.07), 0.47, Color("#995c45"))
	for x: float in [0.57, 0.808]:
		K.cyl(rack, 0.019, 0.019, 0.12, House.TIMBER, Vector3(x, 1.635, 0.385), Vector3(90, 0, 0), 12)
	# 串盐坛与封袋用的草绳，盘在架前的两只竹钉上。
	var coil := TorusMesh.new()
	coil.inner_radius = 0.097
	coil.outer_radius = 0.111
	coil.rings = 24
	coil.ring_segments = 6
	var fibre := K.mat(Color("#a99061"), 0.95)
	for i in 3:
		var loop := K._mesh(rack, coil, fibre, Vector3(0.57 - i * 0.005, 1.47 - i * 0.01, 0.408 + i * 0.009), Vector3(90, i * 4, 0))
		loop.scale = Vector3(0.57, 1.0, 1.56)


static func _shelf(rack: Node3D, center_x: float, y: float, width: float) -> void:
	for z: float in [-0.24, 0.0, 0.24]:
		K.box(rack, Vector3(width, 0.055, 0.235), House.TRIM, Vector3(center_x, y, z))
	for z: float in [-0.33, 0.33]:
		K.box(rack, Vector3(width - 0.06, 0.075, 0.058), House.TIMBER, Vector3(center_x, y - 0.060, z))


static func _sealed_vessel(parent: Node3D, pos: Vector3, size: float, cloth: Color) -> void:
	var jar := K.node(parent, pos)
	jar.scale = Vector3.ONE * size
	if not _crock_mesh:
		_crock_mesh = Props._turned_vessel(PackedVector2Array([
			Vector2(0.001, 0.006), Vector2(0.19, 0.006), Vector2(0.225, 0.052), Vector2(0.285, 0.13),
			Vector2(0.351, 0.30), Vector2(0.365, 0.42), Vector2(0.346, 0.54), Vector2(0.300, 0.63),
			Vector2(0.233, 0.695), Vector2(0.229, 0.743), Vector2(0.249, 0.760), Vector2(0.249, 0.776),
			Vector2(0.221, 0.776)]))
	K._mesh(jar, _crock_mesh, Props._surface(Props.GLAZE), Vector3.ZERO)
	if not _cover_mesh:
		_cover_mesh = _jar_cover()
	K._mesh(jar, _cover_mesh, K.mat(cloth, 0.94), Vector3.ZERO)
	var cord := K.mat(Color("#ac9673"), 0.93)
	var tie := TorusMesh.new()
	tie.inner_radius = 0.239
	tie.outer_radius = 0.253
	tie.rings = 32
	tie.ring_segments = 6
	K._mesh(jar, tie, cord, Vector3.UP * 0.722)
	for side: float in [-1.0, 1.0]:
		_line(jar, Vector3(0.12, 0.723, 0.214), Vector3(0.12 + side * 0.023, 0.645, 0.27), 0.007, cord)


static func _jar_cover() -> ArrayMesh:
	# 上段包住木盖的棱角，颈绳收束，余布在绳下散开。
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for ring: Vector2 in [Vector2(0.001, 0.857), Vector2(0.270, 0.831), Vector2(0.283, 0.778), Vector2(0.244, 0.722), Vector2(0.292, 0.632)]:
		var circle := PackedVector3Array()
		for i in 40:
			var angle := i * TAU / 40.0
			var drape := maxf(0.0, 0.722 - ring.y)
			var radius := ring.x + drape * 0.26 * cos(angle * 9.0)
			circle.append(Vector3(cos(angle) * radius, ring.y + drape * 0.33 * sin(angle * 5.0), sin(angle) * radius))
		rings.append(circle)
	for row in rings.size() - 1:
		for i in 40:
			var j := (i + 1) % 40
			for p: Vector3 in [rings[row][i], rings[row + 1][i], rings[row + 1][j], rings[row][i], rings[row + 1][j], rings[row][j]]:
				cap.add_vertex(p)
	cap.generate_normals()
	cap.index()
	return cap.commit()


static func _basket(parent: Node3D, pos: Vector3, size: float) -> void:
	Pieces.place(parent, &"Basket", pos).scale = Vector3.ONE * size


static func _receiving_platform(parent: Node3D) -> void:
	for x: float in [-0.65, 0, 0.65]:
		K.box(parent, Vector3(0.13, 0.13, 1.02), House.TIMBER, Vector3(x, 0.17, 0))
	for i in 6:
		K.box(parent, Vector3(1.78, 0.061, 0.164), House.TRIM, Vector3(0, 0.266, (i - 2.5) * 0.18))


static func _platform_stock(display: Node3D, bags: int) -> void:
	if bags == 0:
		# 空仓时木箱用来收折好的袋子，箱壁留缝，从正面也能看出是空箱。
		var crate := K.node(display, Vector3(-0.38, 0.298, -0.055), Vector3(0, -4, 0))
		for x: float in [-0.38, 0.38]:
			for z: float in [-0.29, 0.29]:
				K.box(crate, Vector3(.048, .36, .05), House.TIMBER, Vector3(x,.18,z))
			for h: float in [.092, .246]:
				K.box(crate, Vector3(.028,.111,.605), House.TRIM, Vector3(x,h,0))
		for z: float in [-.29,.29]:
			for h: float in [.092,.246]:
				K.box(crate, Vector3(.79,.111,.028), House.TRIM, Vector3(0,h,z))
		K.box(crate, Vector3(.75,.035,.55), House.TRIM, Vector3.UP * .028)
		_folded_sacks(crate, Vector3(0,.049,0), 4)
		return
	for i in mini(4, bags):
		var row := floori(i / 2.0)
		var col := i % 2
		var bag := Pieces.place(display, &"Sack", Vector3(-0.55 + col * 0.43, 0.30, -0.22 + row * 0.37))
		bag.rotation.y = -0.06 + col * 0.15 + PI * row
	if bags == 5:
		Pieces.place(display, &"Sack", Vector3(-0.38, 0.47, -0.025)).rotation.y = PI * 0.48


static func _shelf_stock(display: Node3D, bags: int) -> void:
	var middle := K.node(display, Vector3(0.52, 1.029, -0.10))
	middle.scale = Vector3.ONE * 0.88
	if bags == 0:
		var measure := K.node(middle, Vector3(0.02, 0.230, 0.09), Vector3(0, -9, 180))
		_grain_measure(measure)
	else:
		var places := [Vector3(0, 0, -0.08), Vector3(0.015, 0, 0.21), Vector3(0.02, 0.184, 0.060)]
		for i in bags:
			Pieces.place(middle, &"Sack", places[i]).rotation.y = PI if i == 2 else 0.0


static func _folded_sacks(parent: Node3D, center: Vector3, count: int) -> void:
	# 空袋摊开、对折叠放，口部松散。浅布真实的垂褶横放后仍能接住侧光。
	for i in count:
		var layer := K.node(parent, center + Vector3((i % 2) * 0.016, i * 0.023, i * 0.003), Vector3(0, 4.0 * (i - 1), 0))
		for pleat in 2:
			var fold := Pieces.place(layer, &"Cloth1", Vector3(0, 0.016 + pleat * 0.010, 0.185 - pleat * 0.028))
			fold.rotation.x = PI * 0.5
			fold.scale = Vector3(1.02, 0.43 - pleat * 0.032, 0.18)


static func _basket_stock(display: Node3D, pos: Vector3, size: float, count: int) -> void:
	var basket := K.node(display, pos)
	basket.scale = Vector3.ONE * size
	Pieces.place(basket, &"Basket")
	if count == 0:
		_basket(basket, Vector3(0.007, 0.073, 0), 0.92)
	elif count == 5:
		Pieces.place(basket, &"Cabbages")
	else:
		if not _cabbage:
			_cabbage = Planting._crop_mesh("cabbage")
		for i in count:
			var location := Vector3(-0.083 + (i % 2) * 0.165, 0.028, -0.071 + floori(i / 2.0) * 0.14)
			var head := MeshInstance3D.new()
			head.mesh = _cabbage
			head.scale = Vector3(0.73, 0.89, 0.73)
			head.rotation.y = i * 2.4
			head.position = location
			basket.add_child(head)


static func _carrying_yoke(parent: Node3D) -> void:
	# 两桶暂搁梯口，扁担卧在桶沿上，提梁折向外侧。
	var gear := K.node(parent, Vector3(0, 0.103, 0), Vector3(0, 8, 0))
	var iron := K.mat(Color("#554f43"), 0.57)
	for side: float in [-1.0, 1.0]:
		var bucket := K.node(gear, Vector3(side * 0.51, 0, 0), Vector3(0, side * 12, 0))
		var shell := Props._turned_vessel(PackedVector2Array([Vector2(0.182, 0.015), Vector2(0.245, 0.524),
			Vector2(0.241, 0.531), Vector2(0.217, 0.529), Vector2(0.155, 0.054), Vector2(0.001, 0.054)]), true)
		K._mesh(bucket, shell, House._mapped("brown_planks_09"), Vector3.ZERO)
		# 桶壁由各自顺纹的楔形拼板围住内胆，桶箍贴住拼板的斜度。
		for i in 16:
			var stave := K.node(bucket, Vector3.ZERO, Vector3(0, 22.5 * i, 0))
			K.box(stave, Vector3(0.099, 0.531, 0.023), House.TRIM if i % 5 else K.WOOD_LIGHT,
				Vector3(0, 0.265, 0.220), Vector3(7.0, 0, 0))
		for y: float in [0.093, 0.39]:
			var r := 0.209 + 0.124 * y
			var band := Props._turned_vessel(PackedVector2Array([Vector2(r - 0.004, 0), Vector2(r + 0.001, 0),
				Vector2(r + 0.006, 0.036), Vector2(r + 0.001, 0.036)]))
			K._mesh(bucket, band, iron, Vector3.UP * y)
		var pivot := Vector3(0, 0.482, 0)
		var last := pivot + Vector3.RIGHT * 0.254
		for i in range(1, 13):
			var a := PI * i / 12.0
			var next := pivot + Vector3(cos(a) * 0.254, sin(a) * 0.076, -sin(a) * side * 0.237)
			_line(bucket, last, next, 0.013, iron)
			last = next
		for end: float in [-1.0, 1.0]:
			K.cyl(bucket, 0.027, 0.027, 0.051, iron, pivot + Vector3.RIGHT * end * 0.250, Vector3(0, 0, 90), 12)
	# 肩位厚且平顺，梢端随削形收窄。整条担身共用一个连续的木纹切片。
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections: Array[PackedVector3Array] = []
	for i in 17:
		var t := (i - 8) / 8.0
		var center := Vector3(t * 0.823, 0.54 + 0.076 * pow(1.0 - absf(t), 2.0), 0)
		var half_width := 0.065 - 0.038 * absf(t)
		var half_height := 0.026 - 0.010 * absf(t)
		var profile := PackedVector3Array()
		for p: Vector2 in [Vector2(1, .55), Vector2(.81, 1), Vector2(-.81, 1), Vector2(-1, .55),
				Vector2(-1, -.55), Vector2(-.81, -1), Vector2(.81, -1), Vector2(1, -.55)]:
			profile.append(center + Vector3(0, p.y * half_height, p.x * half_width))
		sections.append(profile)
	for i in sections.size() - 1:
		for edge in 8:
			var next := (edge + 1) % 8
			for p: Vector3 in [sections[i][edge], sections[i + 1][next], sections[i + 1][edge],
					sections[i][edge], sections[i][next], sections[i + 1][next]]:
				s.set_uv(Vector2(p.x * 0.42 + 0.45, 0.556 + p.z * 0.29))
				s.set_color(Color("#c9ad81"))
				s.add_vertex(p)
	for index in [0, 16]:
		var ring := sections[index]
		for edge in range(1, 7):
			for p: Vector3 in ([ring[0], ring[edge+1], ring[edge]] if index == 0 else [ring[0], ring[edge], ring[edge+1]]):
				s.set_uv(Vector2(0.4 + p.z * 0.29, 0.55 + p.y * 0.08))
				s.set_color(Color("#b49b75"))
				s.add_vertex(p)
	s.generate_normals()
	s.generate_tangents()
	s.index()
	K._mesh(gear, s.commit(), House._mapped("brown_planks_09"), Vector3.ZERO)
