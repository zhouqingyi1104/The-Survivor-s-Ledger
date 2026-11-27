extends RefCounted
## 两组陈设各自围绕一个起居动作展开。父节点的房间坐标和通道由楼层布局管理。
const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const House = preload("res://scripts/world/home_house.gd")
const FLOOR_Y := 0.132
const BED := Vector3(-0.10, 0, -0.14)
const SCREEN := Vector3(-0.19, 0, -1.47)
const TRUNK := Vector3(-0.13, 0, 1.28)
const BEDSIDE := Vector3(0.69, 0, -1.03)
const CHAIR := Vector3(0.585, 0.028, 0.055)
const TABLE := Vector3(-0.46, 0.028, -0.035)


static func build_group(group: String, parent: Node3D) -> void:
	var floor := K.node(parent, Vector3.UP * FLOOR_Y)
	match group:
		"berth":
			_sleeping_corner(floor)
		"sewing":
			_sewing_corner(floor)
	House.finish_joinery(floor)
	K.merge_static(floor, [])


## 茶几、椅子各自挡路，两者中间与矮席边缘仍可落脚。矮家具的导航体不留可烘焙的顶面。
static func block_group(group: String, parent: Node3D) -> void:
	match group:
		"berth":
			_block(parent, BED, Vector2(2.27, 0.96), 90.0)
			_block(parent, SCREEN, Vector2(1.31, 0.15), -4.0, 1.4)
			_block(parent, TRUNK, Vector2(1.05, 0.45))
			_block(parent, BEDSIDE, Vector2(0.48, 0.46), -7.0)
		"sewing":
			_block(parent, TABLE, Vector2(0.94, 0.94), 3.0)
			_block(parent, CHAIR, Vector2(0.66, 0.61), -104.0)


static func _block(parent: Node3D, at: Vector3, size: Vector2, turn := 0.0, height := 1.05) -> void:
	var body := K.collider(parent, Vector3(size.x, height, size.y), at + Vector3.UP * (FLOOR_Y + height * 0.5))
	body.rotation_degrees.y = turn


static func _sleeping_corner(floor: Node3D) -> void:
	var bed := K.node(floor, BED, Vector3(0, 90, 0))
	K.Assets.prop(bed, "chinese_sofa", Vector3.ZERO, 0.0, 1.0, false)
	var head := K.node(bed, Vector3(0, 0.49, 0), Vector3(0, 180, 0))
	Props.bedding(head, Vector3.ZERO, 0.82)
	# 床头半屏隔开身后的书架，东侧敞开，床脚留换衣的矮箱。
	var screen := K.node(floor, SCREEN, Vector3(0, -4, 0))
	screen.scale = Vector3(1.05, 0.92, 0.86)
	Props.furnishing(screen, "screen")
	var trunk := K.node(floor, TRUNK)
	var brass := K.mat(Color("#8b714b"), 0.54)
	for x: float in [-0.43, 0.43]:
		K.box(trunk, Vector3(0.09, 0.095, 0.41), K.WOOD, Vector3(x, 0.047, 0))
	K.box(trunk, Vector3(1.02, 0.31, 0.42), K.WOOD, Vector3(0, 0.24, 0))
	K.box(trunk, Vector3(1.055, 0.064, 0.452), K.WOOD_LIGHT, Vector3(0, 0.421, 0))
	for x: float in [-0.413, 0.413]:
		K.box(trunk, Vector3(0.063, 0.12, 0.014), brass, Vector3(x, 0.377, 0.22))
		K.cyl(trunk, 0.012, 0.012, 0.006, brass, Vector3(x, 0.345, 0.229), Vector3(90, 0, 0), 12)
	_draped_cloth(trunk, Vector3(-0.13, 0.455, 0.226), 0.47, 0.37, 0.15, Color("#965e50"))
	var stool := K.node(floor, BEDSIDE, Vector3(0, -7, 0))
	var stand := Props._fitted(stool, "chinese_stool", Vector3(0.53, 0.58, 0.47))
	var top := K.Assets.local_aabb(stand).end.y
	_reading_lamp(stool, Vector3(0, top, 0))
	for side: float in [-1.0, 1.0]:
		var shoe := K.node(floor, Vector3(0.60 + side * 0.092, 0, 0.17 + side * 0.027), Vector3(0, -61.0 + side * 6.0, 0))
		K.sphere(shoe, 0.092, K.mat(Color("#95876b"), 0.94), Vector3(0, 0.024, 0), Vector3(0.72, 0.23, 1.67))
		K.sphere(shoe, 0.086, K.mat(Color("#484953"), 0.92), Vector3(0, 0.054, -0.022), Vector3(0.73, 0.53, 1.47))
		K.sphere(shoe, 0.043, K.mat(Color("#2f3030"), 0.98), Vector3(0, 0.084, 0.046), Vector3(0.84, 0.20, 1.35))


static func _reading_lamp(parent: Node3D, pos: Vector3) -> void:
	var lamp := K.node(parent, pos)
	var dark := K.mat(Color("#584637"), 0.68)
	var paper := K.mat(Color("#efd5a0"), 0.88, 0.43)
	K.cyl(lamp, 0.095, 0.14, 0.052, dark, Vector3.UP * 0.026, Vector3.ZERO, 24)
	K.cyl(lamp, 0.057, 0.079, 0.09, dark, Vector3.UP * 0.084, Vector3.ZERO, 16)
	for height: float in [0.14, 0.412]:
		K.cyl(lamp, 0.133, 0.139, 0.025, dark, Vector3.UP * height, Vector3.ZERO, 6)
	K.cyl(lamp, 0.119, 0.126, 0.25, paper, Vector3.UP * 0.276, Vector3.ZERO, 6)
	for rib in 6:
		var angle := float(rib) * TAU / 6.0
		K.cyl(lamp, 0.007, 0.008, 0.265, dark, Vector3(sin(angle) * 0.125, 0.277, cos(angle) * 0.125), Vector3.ZERO, 6)
	var light := K.light(lamp, Color("#ffd9a2"), 0.68, 2.1, Vector3(0.015, 0.34, 0.01))
	light.name = "BedsideLampLight"
	light.light_specular = 0.2


static func _sewing_corner(floor: Node3D) -> void:
	House._woven_mat(floor, Vector3(-0.02, 0.014, 0), 2.05)
	var chair := K.node(floor, CHAIR, Vector3(0, -104, 0))
	Props._fitted(chair, "chinese_armchair", Vector3(0.67, 1.24, 0.66))
	var table := K.node(floor, TABLE, Vector3(0, 3, 0))
	var top := Props._fitted(table, "chinese_tea_table", Vector3(0.97, 0.62, 0.94))
	var surface := K.node(table, Vector3.UP * K.Assets.local_aabb(top).end.y)
	# 一块旧衣摊在桌边，绣绷向坐者倾斜。线轴与茶盏分别放在左右手边。
	_draped_cloth(surface, Vector3(0.11, 0.003, 0.465), 0.36, 0.54, 0.17, Color("#6e8480"))
	var hoop := K.node(surface, Vector3(0.07, 0.24, -0.06), Vector3(0, 18, -36))
	var rim := TorusMesh.new()
	rim.outer_radius = 0.216
	rim.inner_radius = 0.195
	rim.rings = 40
	rim.ring_segments = 8
	K._mesh(hoop, rim, K.mat(Color("#b38b59"), 0.76), Vector3.ZERO)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_texture = preload("res://assets/art/textiles/indigo_fish.svg")
	cloth.roughness = 0.93
	var silk := SurfaceTool.new()
	silk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 40:
		for corner: Vector2 in [Vector2.ZERO, Vector2.from_angle(TAU * i / 40.0), Vector2.from_angle(TAU * (i + 1) / 40.0)]:
			silk.set_normal(Vector3.UP)
			silk.set_uv(Vector2(0.50 + corner.x * 0.31, 0.48 + corner.y * 0.46))
			silk.add_vertex(Vector3(corner.x * 0.202, 0.002, corner.y * 0.202))
	K._mesh(hoop, silk.commit(), cloth, Vector3.ZERO)
	for z: float in [-0.15, 0.04]:
		K.box(surface, Vector3(0.024, 0.18, 0.028), K.WOOD, Vector3(0.158, 0.091, z), Vector3(0, 0, -24))
	for i in 2:
		var spool := K.node(surface, Vector3(-0.22 + i * 0.11, 0, 0.19 - i * 0.024), Vector3(0, i * 21, 0))
		K.cyl(spool, 0.035, 0.036, 0.090, Color("#975c41") if i == 0 else Color("#c5af88"), Vector3.UP * 0.049, Vector3.ZERO, 14)
		for y: float in [0.007, 0.096]:
			K.cyl(spool, 0.044, 0.044, 0.014, K.WOOD_LIGHT, Vector3.UP * y, Vector3.ZERO, 14)
	var scissors := K.node(surface, Vector3(-0.15, 0.014, -0.037), Vector3(0, -36, 0))
	var iron := K.mat(Color("#736b57"), 0.49)
	var handle := TorusMesh.new()
	handle.outer_radius = 0.027
	handle.inner_radius = 0.018
	handle.rings = 16
	handle.ring_segments = 6
	for side: float in [-1.0, 1.0]:
		K._mesh(scissors, handle, iron, Vector3(side * 0.024, 0, 0.078))
		K.box(scissors, Vector3(0.012, 0.007, 0.13), iron, Vector3(side * 0.006, 0, -0.003), Vector3(0, -side * 12, 0))
	var porcelain := K.mat(Color("#bcc6b3"), 0.42)
	var cup := K.node(surface, Vector3(-0.263, 0.002, -0.208))
	K.cyl(cup, 0.109, 0.068, 0.016, porcelain, Vector3.UP * 0.008, Vector3.ZERO, 28)
	K._mesh(cup, Props._turned_vessel(PackedVector2Array([Vector2(0.038, 0), Vector2(0.042, 0.015),
		Vector2(0.077, 0.08), Vector2(0.081, 0.091), Vector2(0.073, 0.09), Vector2(0.045, 0.035),
		Vector2(0.001, 0.028)])), porcelain, Vector3.UP * 0.017)
	K.cyl(cup, 0.065, 0.065, 0.003, K.mat(Color("#765035"), 0.24), Vector3.UP * 0.090, Vector3.ZERO, 28)


## 经纱沿着桌沿折向下垂，褶皱到悬空的布角才加深。
static func _draped_cloth(parent: Node3D, pos: Vector3, width: float, depth: float, drop: float, color: Color) -> void:
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := PackedVector2Array([Vector2(-depth, 0.007), Vector2(-depth * 0.52, 0.011),
		Vector2(-0.025, 0.009), Vector2(0.005, 0.005), Vector2(0.020, -0.019),
		Vector2(0.025, -drop * 0.55), Vector2(0.036, -drop)])
	for row in profile.size():
		for i in 13:
			var across := i / 12.0
			var fall := clampf(-profile[row].y / drop, 0.0, 1.0)
			var wave := sin(TAU * (across * 2.1 + 0.12 * row))
			cloth.set_color(Color("#b4aa97") if i in [1, 11] else Color.WHITE)
			cloth.set_uv(Vector2(across, float(row) / (profile.size() - 1)))
			cloth.add_vertex(Vector3((across - 0.5) * width, profile[row].y + wave * 0.005,
				profile[row].x + (0.002 + 0.014 * fall) * wave))
	for row in profile.size() - 1:
		for i in 12:
			var a := row * 13 + i
			for index in [a, a + 1, a + 14, a, a + 14, a + 13]:
				cloth.add_index(index)
	cloth.generate_normals()
	cloth.generate_tangents()
	K._mesh(parent, cloth.commit(), preload("res://scripts/world/character.gd")._cloth(color), pos)
