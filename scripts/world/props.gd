extends RefCounted
## 院里的家具、物资堆、作物、守具。数量类的（米袋、柴垛、木料）按存货多少摆，让囤货看得见。

const K = preload("res://scripts/world/kit.gd")
const House = preload("res://scripts/world/home_house.gd")
const Workshop = preload("res://scripts/world/household_models.gd")
const COTTON = preload("res://scripts/world/woven_cotton.gdshader")
const STONE = preload("res://scripts/world/cut_bluestone.gdshader")
const GLAZE = preload("res://scripts/world/kiln_glaze.gdshader")
const WATER = preload("res://scripts/world/well_water.gdshader")
const INK = preload("res://scripts/world/ink_landscape.gdshader")

static var _surface_materials := {}
static var _jar_mesh: ArrayMesh
static var _vat_mesh: ArrayMesh
static var _wok_mesh: ArrayMesh
static var _bedding_meshes := {}
static var _bench_frame: Mesh
static var _well_timber: BaseMaterial3D
static var _cup_glaze: ShaderMaterial
static var _table_stone: ShaderMaterial
static var _screen_panels := {}
static var _foliage: StandardMaterial3D

static func _surface(shader: Shader) -> ShaderMaterial:
	if not _surface_materials.has(shader):
		var material := ShaderMaterial.new()
		material.shader = shader
		if shader == STONE:
			const ROCK := "res://assets/third_party/polyhaven/textures/rock_face_03/rock_face_03_"
			material.set_shader_parameter("stone_color", load(ROCK + "diff.jpg"))
			material.set_shader_parameter("stone_normal", load(ROCK + "nor.jpg"))
			material.set_shader_parameter("stone_arm", load(ROCK + "arm.jpg"))
		elif shader == GLAZE:
			material.set_shader_parameter("mineral_grain", preload("res://assets/third_party/polyhaven/textures/rock_face_03/rock_face_03_arm.jpg"))
		_surface_materials[shader] = material
	return _surface_materials[shader]


static func well(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	var masonry := SurfaceTool.new()
	masonry.begin(Mesh.PRIMITIVE_TRIANGLES)
	for course in 3:
		_well_course(masonry, course)
	var ring := MeshInstance3D.new()
	ring.mesh = masonry.commit()
	ring.material_override = _surface(STONE)
	n.add_child(ring)
	K.cyl(n, 0.527, 0.527, 0.042, _surface(WATER), Vector3(0, 0.235, 0), Vector3.ZERO, 32)
	K.collider(n, Vector3(1.6, 1.0, 1.6), Vector3(0, 0.5, 0))
	# 露天井架让人从院中也看得见井口、水和辘轳。
	var iron := K.mat(Color("#45433b"), 0.42)
	for sx in [-1, 1]:
		K.box(n, Vector3(0.16, 1.75, 0.19), K.WOOD, Vector3(sx * 0.73, 0.88, -0.07))
		K.box(n, Vector3(0.19, 0.075, 0.22), iron, Vector3(sx * 0.73, 1.67, -0.07))
		K.box(n, Vector3(0.18, 0.19, 0.21), Color("#59432e"), Vector3(sx * 0.73, 1.47, -0.07))
	var axle := Vector3(0, 1.49, -0.07)
	if _well_timber == null:
		_well_timber = K.Assets.pbr_unique("brown_planks_09", 1.0, Color("#c9ac85"))
		if _well_timber == null:
			_well_timber = K.unique_mat(Color("#82694f"))
		_well_timber.uv1_triplanar = false
		_well_timber.uv1_world_triplanar = false
		_well_timber.uv1_scale = Vector3.ONE
		_well_timber.normal_scale = 0.45
	var barrel := _turned_vessel(PackedVector2Array([Vector2(0.001, 0), Vector2(0.115, 0),
		Vector2(0.135, 0.025), Vector2(0.135, 1.875), Vector2(0.115, 1.90), Vector2(0.001, 1.90)]), true)
	K._mesh(n, barrel, _well_timber, axle + Vector3(0.95, 0, 0), Vector3(0, 0, 90))
	var hemp := K.mat(Color("#a18359"), 0.94)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.121
	coil.outer_radius = 0.161
	coil.rings = 16
	coil.ring_segments = 6
	for turn in 8:
		K._mesh(n, coil, hemp, axle + Vector3(-0.173 + 0.044 * turn, 0, 0), Vector3(0, 0, 87))
	for sx in [-1, 1]:
		K.cyl(n, 0.153, 0.153, 0.075, iron, axle + Vector3(sx * 0.54, 0, 0), Vector3(0, 0, 90), 18)
	K.box(n, Vector3(0.024, 0.65, 0.024), hemp, Vector3(0.12, 1.16, 0.065))
	K.box(n, Vector3(0.10, 0.34, 0.075), K.WOOD, axle + Vector3(0.93, -0.15, 0))
	K.cyl(n, 0.045, 0.045, 0.22, K.WOOD_LIGHT, axle + Vector3(1.0, -0.30, 0), Vector3(0, 0, 90))
	var pail := Vector3(0.12, 0.78, 0.065)
	var bucket := _turned_vessel(PackedVector2Array([Vector2(0.131, 0), Vector2(0.17, 0.26),
		Vector2(0.168, 0.27), Vector2(0.149, 0.27), Vector2(0.109, 0.035), Vector2(0.001, 0.035)]), true)
	K._mesh(n, bucket, _well_timber, pail - Vector3.UP * 0.135)
	for y in [-0.08, 0.072]:
		var radius: float = 0.15 + 0.15 * y
		var band := _turned_vessel(PackedVector2Array([Vector2(radius + 0.005, 0),
			Vector2(radius + 0.009, 0.023), Vector2(radius + 0.002, 0.024)]))
		K._mesh(n, band, iron, pail + Vector3.UP * (y - 0.012))
	House.finish_joinery(n)
	K.merge_static(n, [])
	return n


static func _well_course(surface: SurfaceTool, course: int) -> void:
	var blocks := 12
	var outer := 0.84 if course == 2 else 0.79
	var palette := [Color("#e2e4da"), Color("#c1c7c0"), Color("#f1ebdc"), Color("#d4d3c7")]
	for i in blocks:
		var start := TAU * (i + 0.5 * (course % 2)) / blocks + 0.009
		var end := start + TAU / blocks - 0.018
		var a := Vector3(cos(start), 0, sin(start))
		var b := Vector3(cos(end), 0, sin(end))
		var base := Vector3.UP * (0.05 + course * 0.245)
		var lift := Vector3.UP * 0.237
		var corners := PackedVector3Array([a * outer + base, b * outer + base, b * 0.53 + base, a * 0.53 + base])
		var color: Color = palette[(i * 3 + course) % palette.size()]
		var center := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
		var top := PackedVector3Array()
		for corner in corners:
			top.append(corner.move_toward(center, 0.025 + 0.008 * ((course + i) % 3)) + lift)
		_well_face(surface, top[0], top[1], top[2], top[3], color)
		for j in 4:
			var p := corners[j]
			var q := corners[(j + 1) % 4]
			var edge := lift - Vector3.UP * 0.033
			var shade := color.darkened(0.34 if j == 2 else (2 - course) * 0.08)
			_well_face(surface, p, q, q + edge, p + edge, shade)
			_well_face(surface, p + edge, q + edge, top[(j + 1) % 4], top[j], color)


static func _well_face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for p in [a, b, c, a, c, d]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(p)


static func stove(parent: Node3D, pos: Vector3, rot_y: float, double: bool) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	var w := 2.2 if double else 1.4
	K.collider(n, Vector3(w, 0.85, 1.0), Vector3(0, 0.425, 0))
	# 炉膛后缩，灶口用侧砖与过梁收边，余烬藏在阴面里。
	K.box(n,Vector3(w,0.85,0.74),K.BRICK,Vector3(0,0.425,-0.13))
	K.box(n,Vector3(w,0.15,0.26),K.BRICK,Vector3(0,0.075,0.37))
	K.box(n,Vector3(w,0.41,0.26),K.BRICK,Vector3(0,0.645,0.37))
	var pier_width := (w - (0.84 if double else 0.42) - (0.58 if double else 0.0)) * 0.5
	for side in [-1,1]:
		K.box(n,Vector3(pier_width,0.29,0.26),K.BRICK,Vector3(side*(w-pier_width)*0.5,0.295,0.37))
	if double:
		K.box(n,Vector3(0.58,0.29,0.26),K.BRICK,Vector3(0,0.295,0.37))
	K.box(n, Vector3(w + 0.1, 0.08, 1.1), _surface(STONE), Vector3(0, 0.88, 0))
	var holes := [-0.5, 0.5] if double else [0.0]
	if _wok_mesh == null:
		_wok_mesh = _turned_vessel(PackedVector2Array([Vector2(0.001, 0), Vector2(0.14, 0.017),
			Vector2(0.25, 0.066), Vector2(0.34, 0.141), Vector2(0.355, 0.169), Vector2(0.345, 0.181),
			Vector2(0.321, 0.156), Vector2(0.245, 0.093), Vector2(0.145, 0.047), Vector2(0.001, 0.029)]))
	var iron := K.mat(Color("#3c403c"), 0.37)
	for x in holes:
		K._mesh(n, _wok_mesh, iron, Vector3(x, 0.923, 0))
		for side in [-1, 1]:
			K.box(n, Vector3(0.12, 0.035, 0.068), iron, Vector3(x + side * 0.365, 1.085, 0))
		K.box(n, Vector3(0.42, 0.29, 0.016), Color("#312923"), Vector3(x, 0.295, 0.251))
		for coal in 3:
			K.sphere(n, 0.048, K.mat(Color("#a85b36"), 0.81, 0.21), Vector3(x - 0.09 + coal * 0.082, 0.173, 0.39), Vector3(1.0, 0.62, 0.74))
	K.box(n, Vector3(0.45, 2.6, 0.45), K.BRICK, Vector3(w / 2.0 - 0.15, 1.3, -0.3))
	K.merge_static(n, [])
	return n


## 柴垛：根数按存货多少（最多 12 捆）。
static func firewood(parent: Node3D, pos: Vector3, count: int) -> Node3D:
	var n := K.node(parent, pos)
	Workshop.stock(n, &"Billet", count)
	return n


## 米袋：一斗一袋，最多摆 16 袋。
static func rice_sacks(parent: Node3D, pos: Vector3, count: int) -> Node3D:
	var n := K.node(parent, pos)
	Workshop.stock(n, &"Sack", count)
	return n


static func wood_pile(parent: Node3D, pos: Vector3, count: int, rot_y := 0.0) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	Workshop.stock(n, &"Timber", count)
	return n


static func water_vat(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	if _vat_mesh == null:
		_vat_mesh = _turned_vessel(PackedVector2Array([
			Vector2(0.29, 0.00), Vector2(0.32, 0.025), Vector2(0.32, 0.07),
			Vector2(0.365, 0.14), Vector2(0.435, 0.36), Vector2(0.48, 0.61),
			Vector2(0.49, 0.77), Vector2(0.475, 0.84), Vector2(0.488, 0.86),
			Vector2(0.483, 0.89), Vector2(0.466, 0.90), Vector2(0.444, 0.89),
			Vector2(0.434, 0.871), Vector2(0.445, 0.79), Vector2(0.439, 0.66),
			Vector2(0.385, 0.34), Vector2(0.27, 0.09), Vector2(0.001, 0.07)]))
	K._mesh(n, _vat_mesh, _surface(GLAZE), Vector3.ZERO, Vector3.ZERO)
	K.cyl(n, 0.446, 0.446, 0.012, _surface(WATER), Vector3(0, 0.751, 0), Vector3.ZERO, 36)
	K.collider(n, Vector3(1.0, 0.9, 1.0), Vector3(0, 0.45, 0))
	return n


static func bed(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.solid(n, Vector3(2.2, 0.5, 1.3), K.WOOD, Vector3(0, 0.25, 0))
	bedding(n, Vector3(0, 0.50, 0), 1.10)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			K.box(n, Vector3(0.08, 1.9, 0.08), K.WOOD, Vector3(sx * 1.05, 0.95, sz * 0.6))
		K.box(n, Vector3(0.10, 0.08, 1.3), K.WOOD, Vector3(sx * 1.05, 1.9, 0))
	K.box(n, Vector3(2.2, 0.08, 0.10), K.WOOD, Vector3(0, 1.9, -0.60))
	K.box(n, Vector3(2.15, 1.2, 0.02), K.mat(Color("#c8b48a"), 0.9, 0.0, 0.75), Vector3(0, 1.3, -0.62))
	House.finish_joinery(n)
	K.merge_static(n,[])
	return n


## 席、枕与折好的夹被随床一起搬。榻靠墙的一侧留出扶手。
static func bedding(parent: Node3D, pos: Vector3, depth: float) -> void:
	var n := K.node(parent, pos)
	K.box(n, Vector3(1.94, 0.065, depth * 0.95), Color("#ad9872"), Vector3(0, 0.036, 0))
	if not _bedding_meshes.has(depth):
		_bedding_meshes[depth] = _bedding_mesh(depth)
	var sheet := MeshInstance3D.new()
	sheet.mesh = _bedding_meshes[depth]
	sheet.material_override = _surface(COTTON)
	n.add_child(sheet)


static func _bedding_mesh(depth: float) -> ArrayMesh:
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var next := _filled_cloth(cloth, 0, Vector3(-0.69, 0.069, -0.015), Vector2(0.47, depth * 0.77), true)
	_filled_cloth(cloth, next, Vector3(0.25, 0.043, 0.022), Vector2(1.42, depth * 1.06), false)
	cloth.generate_normals()
	return cloth.commit()


## 自边缘低垂、中部蓬松的连续曲面。枕芯四角收紧，被头翻边随棉絮的起伏走。
static func _filled_cloth(surface: SurfaceTool, start: int, center: Vector3, size: Vector2, pillow: bool) -> int:
	const COLS := 28
	const ROWS := 16
	for row in ROWS + 1:
		for col in COLS + 1:
			var uv := Vector2(float(col) / COLS, float(row) / ROWS)
			var p := uv * 2.0 - Vector2.ONE
			var xz := p * size * 0.5
			var gain := (1.0 - pow(absf(p.x), 6)) * (1.0 - pow(absf(p.y), 6))
			var h: float
			if pillow:
				xz *= Vector2(1.0 - 0.10 * pow(absf(p.y), 4), 1.0 - 0.09 * pow(absf(p.x), 4))
				h = 0.018 + 0.159 * pow(gain, 0.5) - 0.027 * exp(-5.0 * p.length_squared())
			else:
				xz.y += 0.015 * sin(p.x * 6.8 + p.y * 0.9)
				xz.x -= 0.032 * pow(absf(p.y), 5) * signf(p.x)
				var folds := 0.034 * sin(p.y * 8.7 + p.x * 1.8 + 0.6 * sin(p.x * 3.0))
				var cuff := 0.045 * exp(-70.0 * absf(uv.x - 0.10 - 0.012 * sin(TAU * uv.y)))
				h = 0.012 + pow(gain, 0.43) * (0.115 + folds + cuff + 0.018 * cos(p.x * 6.0 - p.y * 5.0))
			surface.set_uv(uv)
			surface.set_uv2(Vector2(0 if pillow else 1, 0))
			surface.add_vertex(center + Vector3(xz.x, h, xz.y))
	for row in ROWS:
		for col in COLS:
			var a := start + row * (COLS + 1) + col
			for index in [a, a + 1, a + COLS + 2, a, a + COLS + 2, a + COLS + 1]:
				surface.add_index(index)
	return start + (COLS + 1) * (ROWS + 1)


static func desk(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(1.8, 0.08, 0.8), K.WOOD, Vector3(0, 0.82, 0))
	for sx in [-1, 1]:
		K.box(n, Vector3(0.1, 0.8, 0.7), K.WOOD, Vector3(sx * 0.8, 0.4, 0))
	K.collider(n, Vector3(1.8, 0.9, 0.8), Vector3(0, 0.45, 0))
	desk_items(n, Vector3(0, 0.86, 0))
	K.box(n, Vector3(0.7, 0.45, 0.4), K.WOOD, Vector3(0, 0.22, 0.75))
	House.finish_joinery(n)
	K.merge_static(n,[])
	return n


static func shrine(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.solid(n, Vector3(2.4, 0.95, 0.8), K.LACQUER, Vector3(0, 0.475, 0))
	K.box(n, Vector3(2.5, 0.08, 0.9), K.WOOD, Vector3(0, 0.98, 0))
	K.box(n, Vector3(1.0, 1.1, 0.09), K.LACQUER, Vector3(0, 1.55, -0.28))
	K.box(n, Vector3(0.8, 0.9, 0.02), K.mat(Color("#312a23")), Vector3(0, 1.55, -0.22))
	for side in [-1, 1]:
		K.box(n, Vector3(0.065, 1.1, 0.09), K.WOOD, Vector3(side * 0.45, 1.55, 0.05))
	K.prism(n, Vector3(0.7, 0.25, 1.2), K.ROOF, Vector3(0, 2.22, -0.1), Vector3(0, 90, 0))
	var offerings := altar_items(n, Vector3(0, 1.02, 0.065))
	offerings.scale = Vector3.ONE * 1.42
	House.finish_joinery(n)
	K.merge_static(n,[offerings])
	return n


static func workbench(parent: Node3D, pos: Vector3, rot_y: float, collide := true) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	if collide:
		K.collider(n, Vector3(2.0, 0.85, 0.9), Vector3(0, 0.425, 0))
	if _bench_frame == null:
		_bench_frame = _workbench_frame()
	var body := MeshInstance3D.new()
	body.mesh = _bench_frame
	n.add_child(body)
	Workshop.place(n, &"Worktools", Vector3.UP * 0.951)
	return n


static func _workbench_frame() -> Mesh:
	var n := Node3D.new()
	for side in [-1, 1]:
		for edge in [-1, 1]:
			K.box(n, Vector3(0.14, 0.85, 0.15), K.WOOD, Vector3(side * 0.88, 0.425, edge * 0.35))
		K.box(n, Vector3(1.8, 0.13, 0.08), K.WOOD, Vector3(0, 0.70, side * 0.36))
		K.box(n, Vector3(0.10, 0.12, 0.80), K.WOOD, Vector3(side * 0.88, 0.20, 0))
	K.box(n, Vector3(1.78, 0.06, 0.57), K.WOOD_LIGHT, Vector3(0, 0.23, 0))
	for plank in 3:
		K.box(n, Vector3(2.1, 0.1, 0.327), K.WOOD_LIGHT, Vector3(0, 0.90, (plank - 1) * 0.334))
	var joinery := House.finish_joinery(n)
	var mesh := joinery.mesh
	mesh.surface_set_material(0, joinery.material_override)
	n.free()
	return mesh


static func cabinet(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.solid(n, Vector3(1.4, 2.0, 0.6), K.WOOD, Vector3(0, 1.0, 0))
	for k in 3:
		K.box(n, Vector3(1.25, 0.55, 0.04), K.WOOD_LIGHT, Vector3(0, 0.4 + k * 0.62, 0.3))
		K.sphere(n, 0.035, K.mat(K.GOLD, 0.4), Vector3(0, 0.4 + k * 0.62, 0.33))
	House.finish_joinery(n)
	K.merge_static(n,[])
	return n


## 菜畦一块，作物按种类和长势画出来。
static func garden_plot(parent: Node3D, pos: Vector3, crop: String, growth: float, dry: bool) -> Node3D:
	return preload("res://scripts/world/yard_planting.gd").garden_plot(parent, pos, crop, growth, dry)


static func plum_tree(parent: Node3D, pos: Vector3, collide := true) -> Node3D:
	return preload("res://scripts/world/yard_planting.gd").plum_tree(parent, pos, collide)


static func dog(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, 200, 0))
	var fur := K.mat(Color("#b8883e"))
	K.box(n, Vector3(0.28, 0.26, 0.6), fur, Vector3(0, 0.38, 0))
	K.box(n, Vector3(0.22, 0.22, 0.26), fur, Vector3(0, 0.56, 0.36))
	K.box(n, Vector3(0.12, 0.1, 0.14), fur, Vector3(0, 0.52, 0.52))
	for sx in [-1, 1]:
		K.box(n, Vector3(0.06, 0.1, 0.04), fur.albedo_color.darkened(0.3), Vector3(sx * 0.08, 0.7, 0.32))
		for sz in [-1, 1]:
			K.box(n, Vector3(0.07, 0.26, 0.07), fur, Vector3(sx * 0.1, 0.13, sz * 0.22))
	K.box(n, Vector3(0.05, 0.05, 0.3), fur, Vector3(0, 0.5, -0.38), Vector3(-40, 0, 0))
	return n


static func stone_lantern(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	var stone := _surface(STONE)
	for course in [[0.235,0.245,0.075,0.038], [0.132,0.214,0.081,0.115],
			[0.096,0.126,0.525,0.418], [0.193,0.101,0.119,0.740], [0.224,0.193,0.056,0.829]]:
		K.cyl(n, course[0], course[1], course[2], stone, Vector3.UP * course[3], Vector3(0,22.5,0),8)
	for x in [-0.126,0.126]:
		for z in [-0.126,0.126]:
			K.box(n, Vector3(0.057,0.318,0.057), stone, Vector3(x,1.014,z))
	K.cyl(n,0.090,0.066,0.052,K.mat(Color("#746349"),0.48),Vector3.UP * 0.884,Vector3.ZERO,16)
	K.sphere(n, 0.040, K.mat(Color("#ecac69"), 0.79, 0.71), Vector3.UP * 0.954, Vector3(0.63,1.42,0.63))
	for course in [[0.225,0.234,0.052,1.187],[0.315,0.313,0.043,1.233],
			[0.124,0.315,0.088,1.298],[0.062,0.125,0.083,1.382],[0.082,0.061,0.042,1.444],
			[0.020,0.082,0.080,1.503]]:
		K.cyl(n, course[0],course[1],course[2],stone,Vector3.UP*course[3],Vector3(0,22.5,0),8)
	K.merge_static(n, [])
	return n


# ---------- 守具（摆在门外街上） ----------

static func device(container: Node3D, id: String, pos: Vector3, index: int) -> void:
	var parent := K.node(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + index
	match id:
		"peach_stake":
			for k in 6:
				var p := pos + Vector3(-1.5 + k * 0.6, 0, 0)
				var post := K.node(parent, p, Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-8, 8)))
				K.cyl(post, 0.065, 0.084, 0.9, K.WOOD, Vector3.UP * 0.45, Vector3.ZERO, 10)
				K.cyl(post, 0.026, 0.065, 0.18, K.WOOD_LIGHT, Vector3.UP * 0.99, Vector3.ZERO, 10)
				K.cyl(post, 0.072, 0.074, 0.053, K.mat(Color("#884b39"),0.88), Vector3.UP * 0.81,Vector3.ZERO,10)
		"barricade":
			for k in 3:
				var p := pos + Vector3(-1.4 + k * 1.4, 0.55, 0)
				K.box(parent, Vector3(0.12, 1.5, 0.12), K.WOOD_LIGHT, p, Vector3(0, 0, 40))
				K.box(parent, Vector3(0.12, 1.5, 0.12), K.WOOD_LIGHT, p, Vector3(0, 0, -40))
			K.box(parent, Vector3(4.0, 0.12, 0.12), K.WOOD, pos + Vector3(0, 0.6, 0))
		"armor_hook":
			# 一排带铁钩的低横木，摆在院门外；仅表现已建好的守具。
			K.box(parent, Vector3(3.0, 0.15, 0.18), K.WOOD_LIGHT, pos + Vector3(0, 0.48, 0))
			for k in 4:
				var p := pos + Vector3(-1.1 + k * 0.72, 0.55, 0)
				K.box(parent, Vector3(0.08, 0.6, 0.08), K.mat(Color("#777d82"), 0.4), p, Vector3(0, 0, -25))
				K.box(parent, Vector3(0.3, 0.08, 0.08), K.mat(Color("#777d82"), 0.4), p + Vector3(0.1, 0.28, 0))
		"horde_rope":
			# 窗前的绳网用可见绳索表示，不加碰撞或额外战斗效果。
			var cord := K.mat(Color("#a28662"), 0.94)
			for k in 4:
				for j in 8:
					var t := j / 8.0
					var u := (j + 1) / 8.0
					var a := pos + Vector3(-1.25 + 2.5*t,0.35+k*0.28-0.064*absf(sin(TAU*t)),0.018*cos(PI*t))
					var b := pos + Vector3(-1.25 + 2.5*u,0.35+k*0.28-0.064*absf(sin(TAU*u)),0.018*cos(PI*u))
					var strand := K.cyl(parent,0.022,0.022,a.distance_to(b),cord,(a+b)*0.5,Vector3.ZERO,6)
					strand.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
			for x in [-1.1, 0.0, 1.1]:
				K.cyl(parent, 0.026, 0.027, 1.1, cord, pos + Vector3(x, 0.78, 0),Vector3.ZERO,7)
		"caltrop_field":
			for k in 26:
				var p := pos + Vector3(rng.randf_range(-2.0, 2.0), 0.06, rng.randf_range(-0.6, 0.6))
				K.cyl(parent, 0.0, 0.06, 0.12, K.mat(Color("#3d4146"), 0.4), p, Vector3(rng.randf_range(0, 90), rng.randf_range(0, 360), 0), 3)
		"rice_scatter":
			var grain := SphereMesh.new()
			grain.radius = 0.016
			grain.height = 0.072
			grain.radial_segments = 6
			grain.rings = 2
			for k in 60:
				var p := pos + Vector3(rng.randf_range(-1.8, 1.8), 0.02, rng.randf_range(-0.5, 0.5))
				K._mesh(parent, grain, K.mat(Color("#dfd2b3"),0.88), p, Vector3(90,rng.randf_range(0, 180),0))
		"blood_sill":
			var imprint := PlaneMesh.new()
			imprint.size = Vector2(2.4,0.62)
			var wash := K._mesh(parent,imprint,_surface(preload("res://scripts/world/sill_wash.gdshader")),pos + Vector3.UP * 0.056)
			wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"talisman_wall":
			for k in 9:
				var a := -60.0 + k * 15.0
				var p := pos + Vector3(sin(deg_to_rad(a)) * 2.0, 1.6 + 0.25 * sin(k * 1.3), cos(deg_to_rad(a)) * 0.6)
				var slip := Workshop.place(parent, &"Slip", p)
				slip.rotation_degrees = Vector3(0, a, rng.randf_range(-8, 8))
		"ink_line":
			for k in 4:
				K.cyl(parent, 0.012, 0.012, 3.0, K.mat(Color("#38312b"),0.85), pos + Vector3(0, 0.5 + k * 0.6, 0),Vector3(0,0,90),6)
		"bagua_mirror":
			Workshop.place(parent, &"Mirror", pos).rotation.x = PI * 0.5
	House.finish_joinery(parent)
	K.merge_static(parent, [])


# ---------- 院中陈设（让院子有人住过的样子） ----------

static func stone_table(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	if _table_stone == null:
		_table_stone = _surface(STONE).duplicate()
		_table_stone.set_shader_parameter("polished", 0.85)
	var stone := _table_stone
	K.cyl(n, 0.61, 0.52, 0.08, stone, Vector3(0, 0.73, 0), Vector3.ZERO, 28)
	K.cyl(n, 0.59, 0.61, 0.07, stone, Vector3(0, 0.80, 0), Vector3.ZERO, 28)
	K.cyl(n, 0.22, 0.3, 0.69, stone, Vector3(0, 0.345, 0), Vector3.ZERO, 16)
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.05
		K.cyl(n, 0.16, 0.20, 0.33, stone, p + Vector3(0, 0.165, 0), Vector3.ZERO, 16)
		K.cyl(n, 0.20, 0.17, 0.08, stone, p + Vector3(0, 0.37, 0), Vector3.ZERO, 20)
		K.cyl(n, 0.19, 0.20, 0.045, stone, p + Vector3(0, 0.431, 0), Vector3.ZERO, 20)
	K.collider(n, Vector3(1.3, 0.85, 1.3), Vector3(0, 0.42, 0))
	if _cup_glaze == null:
		_cup_glaze = _surface(GLAZE).duplicate()
		_cup_glaze.set_shader_parameter("glaze", Color("#a7b5a5"))
		_cup_glaze.set_shader_parameter("bare_clay", Color("#968068"))
	var cup := _turned_vessel(PackedVector2Array([Vector2(0.038, 0), Vector2(0.040, 0.016),
		Vector2(0.058, 0.032), Vector2(0.074, 0.105), Vector2(0.073, 0.119),
		Vector2(0.064, 0.119), Vector2(0.059, 0.096), Vector2(0.040, 0.034), Vector2(0.001, 0.031)]))
	K._mesh(n, cup, _cup_glaze, Vector3(0.2, 0.835, 0.1))
	return n


static func clay_jar(parent: Node3D, pos: Vector3, s := 1.0) -> Node3D:
	var n := K.node(parent, pos)
	if _jar_mesh == null:
		# 从露胎的圈足向上收肩、卷唇，再向内折回釉面，俯视可见真实罐口。
		_jar_mesh = _turned_vessel(PackedVector2Array([
			Vector2(0.18, 0.012), Vector2(0.19, 0.045), Vector2(0.19, 0.065),
			Vector2(0.27, 0.16), Vector2(0.345, 0.30), Vector2(0.37, 0.45),
			Vector2(0.35, 0.56), Vector2(0.29, 0.65), Vector2(0.20, 0.71),
			Vector2(0.178, 0.755), Vector2(0.187, 0.772), Vector2(0.214, 0.786),
			Vector2(0.216, 0.808), Vector2(0.203, 0.826), Vector2(0.178, 0.822),
			Vector2(0.158, 0.80), Vector2(0.150, 0.754), Vector2(0.20, 0.675),
			Vector2(0.27, 0.55), Vector2(0.28, 0.38), Vector2(0.23, 0.23), Vector2(0.001, 0.15)]))
	var pot := MeshInstance3D.new()
	pot.mesh = _jar_mesh
	pot.material_override = _surface(GLAZE)
	pot.scale = Vector3.ONE * s
	n.add_child(pot)
	K.collider(n, Vector3(0.7, 0.8, 0.7) * s, Vector3(0, 0.4 * s, 0))
	return n


static func _turned_vessel(rim: PackedVector2Array, long_grain := false) -> ArrayMesh:
	const SIDES := 36
	var height := 0.001
	for point in rim:
		height = maxf(height, point.y)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rim.size():
		var tangent := (rim[mini(row + 1, rim.size() - 1)] - rim[maxi(0, row - 1)]).normalized()
		for i in SIDES + 1:
			var u := float(i) / SIDES
			var direction := Vector3(cos(u * TAU), 0, sin(u * TAU))
			surface.set_normal(direction * tangent.y - Vector3.UP * tangent.x)
			var uv := Vector2(rim[row].y * 0.42, 0.106 + u * 0.060) if long_grain else Vector2(u, rim[row].y / height)
			surface.set_uv(uv)
			surface.add_vertex(direction * rim[row].x + Vector3.UP * rim[row].y)
	for row in rim.size() - 1:
		for i in SIDES:
			var a := row * (SIDES + 1) + i
			for index in [a, a + 1, a + SIDES + 2, a, a + SIDES + 2, a + SIDES + 1]:
				surface.add_index(index)
	return surface.commit()


static func potted_bamboo(parent: Node3D, pos: Vector3, collide := true) -> Node3D:
	var n := K.node(parent, pos)
	var pot := _turned_vessel(PackedVector2Array([Vector2(0.20, 0), Vector2(0.205, 0.04),
		Vector2(0.25, 0.08), Vector2(0.296, 0.40), Vector2(0.315, 0.434),
		Vector2(0.312, 0.462), Vector2(0.278, 0.464), Vector2(0.265, 0.40)]))
	K._mesh(n, pot, _surface(GLAZE), Vector3.ZERO)
	K.cyl(n, 0.27, 0.27, 0.016, Color("#4b4033"), Vector3.UP * 0.407, Vector3.ZERO, 32)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100 + pos.z)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var angle := k * TAU / 5.0 + rng.randf_range(-0.25, 0.25)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var base := outward * rng.randf_range(0.045, 0.15) + Vector3.UP * 0.41
		var h := rng.randf_range(1.5, 2.10)
		var lean := rng.randf_range(0.18, 0.45)
		var prev := base
		for j in range(1, 8):
			var t := j / 7.0
			var joint := base + Vector3.UP * (h * t) + outward * (lean * t * t)
			_bamboo_stem(foliage, prev, joint, lerpf(0.020,0.007,t), Color("#737557"))
			_bamboo_stem(foliage, joint - Vector3.UP * 0.016, joint, lerpf(0.024,0.009,t), Color("#95916a"))
			prev = joint
			if j < 3:
				continue
			var direction := outward.rotated(Vector3.UP, (1.0 if j % 2 else -1.0) * 1.20)
			var branch := direction * rng.randf_range(0.20, 0.36) + Vector3.UP * 0.13
			_bamboo_stem(foliage, joint, joint + branch, 0.007, Color("#626d4f"))
			for leaf in 4:
				var side := -1.0 if leaf % 2 else 1.0
				var growth := direction.rotated(Vector3.UP, side * rng.randf_range(0.36, 1.25))
				var origin := joint + branch * (0.26 + 0.24 * leaf)
				_bamboo_leaf(foliage, origin, growth * rng.randf_range(0.17, 0.27),
					Color("#55664b").lerp(Color("#86916b"), rng.randf()))
	foliage.generate_normals()
	if _foliage == null:
		_foliage = StandardMaterial3D.new()
		_foliage.vertex_color_use_as_albedo = true
		_foliage.vertex_color_is_srgb = true
		_foliage.roughness = 0.91
		_foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
	K._mesh(n, foliage.commit(), _foliage, Vector3.ZERO)
	if collide:
		K.collider(n, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0))
	return n


static func _bamboo_stem(surface: SurfaceTool, base: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var axis := (end - base).normalized()
	var x := axis.cross(Vector3.FORWARD).normalized() * radius
	var z := x.cross(axis)
	surface.set_color(color)
	for i in 5:
		var a := i * TAU / 5.0
		var b := (i + 1) * TAU / 5.0
		var p := x * cos(a) + z * sin(a)
		var q := x * cos(b) + z * sin(b)
		for point in [base + p, base + q, end + q, base + p, end + q, end + p]:
			surface.add_vertex(point)


static func _bamboo_leaf(surface: SurfaceTool, base: Vector3, length: Vector3, color: Color) -> void:
	var center := base + length * 0.41 + Vector3.UP * 0.024
	var width := length.normalized().cross(Vector3.UP) * 0.026
	var tip := base + length - Vector3.UP * 0.048
	var ridge := center + Vector3.UP * 0.014
	for side in [-1.0, 1.0]:
		var edge: Vector3 = center + side * width
		surface.set_color(color.darkened(0.09 if side < 0 else 0.0))
		var triangles := [base, edge, ridge, ridge, edge, tip] if side < 0 else [base, ridge, edge, ridge, tip, edge]
		for point in triangles:
			surface.add_vertex(point)


static func laundry(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var n := K.node(parent, a)
	var length := a.distance_to(b)
	n.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	for x in [0.0, length]:
		K.cyl(n, 0.035, 0.053, 2.0, K.WOOD, Vector3(x, 1.0, 0), Vector3.ZERO, 10)
	var cord := K.mat(Color("#9a7f59"), 0.93)
	for span in 8:
		var t := span / 8.0
		var u := (span + 1) / 8.0
		var start := Vector3(t * length, 1.94 - 0.125 * sin(PI * t), 0)
		var end := Vector3(u * length, 1.94 - 0.125 * sin(PI * u), 0)
		var strand := K.cyl(n, 0.011, 0.011, start.distance_to(end), cord, (start + end) * 0.5, Vector3.ZERO, 6)
		strand.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	for k in 3:
		var t := 0.24 + k * 0.26
		var h := 1.94 - 0.125 * sin(PI * t)
		Workshop.place(n, StringName("Cloth%d" % k), Vector3(t * length, h, 0.007))
		for edge in [-1, 1]:
			K.box(n, Vector3(0.019, 0.089, 0.036), K.WOOD_LIGHT, Vector3(t * length + edge * 0.18, h + 0.005, 0.017), Vector3(0, 0, edge * 7))
	House.finish_joinery(n)
	K.merge_static(n, [])
	return n


## 灶房柱上挂的辣椒串、蒜辫。
static func hanging_produce(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	Workshop.place(n, &"Strings")
	return n


static func basket(parent: Node3D, pos: Vector3, filled: Color) -> Node3D:
	var n := K.node(parent, pos)
	Workshop.place(n, &"Basket")
	Workshop.place(n, &"Cabbages" if filled.g > filled.r else &"Rice")
	return n


## 山水挂轴：挂在墙上，画心是几笔远山。
static func scroll_painting(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(0.7, 1.5, 0.02), K.mat(Color("#cdb98d")), Vector3.ZERO)
	var paper := QuadMesh.new()
	paper.size = Vector2(0.58, 1.23)
	K._mesh(n, paper, _surface(INK), Vector3(0, 0.02, 0.014))
	K.cyl(n, 0.03, 0.03, 0.8, K.WOOD, Vector3(0, -0.77, 0.01), Vector3(0, 0, 90), 6)
	return n


static func bookshelf(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(1.16, 1.76, 0.055), Color("#69533f"), Vector3(0, 0.94, -0.18))
	for x in [-0.56, 0.56]:
		K.box(n, Vector3(0.075, 1.85, 0.43), K.WOOD, Vector3(x, 0.925, 0))
	for y in [0.22, 0.74, 1.27, 1.82]:
		K.box(n, Vector3(1.18, 0.06, 0.45), K.WOOD_LIGHT, Vector3(0, y, 0))
	var cloth := [Color("#495d63"), Color("#89624d"), Color("#777d62")]
	for level in 3:
		var bottom := 0.25 + level * 0.525
		var side := 1.0 if level == 1 else -1.0
		for i in 3:
			var at := Vector3(side * (0.16 + i * 0.011), bottom + 0.038 + i * 0.076, 0.035)
			K.box(n, Vector3(0.52, 0.067, 0.31), cloth[(i + level) % 3], at)
			K.box(n, Vector3(0.47, 0.041, 0.019), Color("#cabb94"), at + Vector3(0, 0, 0.153))
		K.cyl(n, 0.056, 0.058, 0.35, Color("#bca47e"), Vector3(-side * 0.31, bottom + 0.18, 0.01), Vector3(0, 0, side * 12))
	House.finish_joinery(n)
	K.merge_static(n, [])
	return n


## 添置家具复用已扫描的圈椅、茶几，尺寸按旧家具的占地和使用高度对齐。
static func _fitted(parent: Node3D, name: String, bounds: Vector3) -> Node3D:
	var item := K.Assets.prop(parent, name, Vector3.ZERO, 0.0, 1.0, false)
	if item == null:
		return null
	var box := K.Assets.local_aabb(item)
	var scale_by := minf(bounds.x / box.size.x, minf(bounds.y / box.size.y, bounds.z / box.size.z))
	item.scale *= scale_by
	item.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z) * scale_by
	return item


static func furnishing(n: Node3D, id: String) -> bool:
	match id:
		"armchair":
			if _fitted(n, "chinese_armchair", Vector3(0.80, 1.12, 0.78)) == null:
				for x in [-0.30, 0.30]:
					for z in [-0.28, 0.28]:
						K.box(n,Vector3(0.062,0.45,0.061),K.WOOD,Vector3(x,0.225,z))
					K.box(n,Vector3(0.07,0.055,0.56),K.WOOD_LIGHT,Vector3(x,0.66,0))
				K.box(n,Vector3(0.67,0.08,0.63),K.WOOD_LIGHT,Vector3.UP*0.46)
				K.box(n,Vector3(0.28,0.55,0.065),K.WOOD,Vector3(0,0.77,-0.27))
		"tea_table":
			var table := _fitted(n, "chinese_tea_table", Vector3(0.99, 0.56, 0.81))
			var top := 0.50
			if table:
				top = K.Assets.local_aabb(table).end.y
			else:
				K.box(n,Vector3(0.83,0.068,0.66),K.WOOD_LIGHT,Vector3(0,0.466,0))
				for x in [-0.35,0.35]:
					for z in [-0.26,0.26]:
						K.box(n,Vector3(0.075,0.44,0.075),K.WOOD,Vector3(x,0.22,z))
			var cup := _turned_vessel(PackedVector2Array([Vector2(0.031,0),Vector2(0.035,0.012),Vector2(0.065,0.078),
					Vector2(0.069,0.088),Vector2(0.061,0.091),Vector2(0.052,0.070),Vector2(0.014,0.019)]))
			K._mesh(n,cup,_surface(GLAZE),Vector3(0.12,top,0.055))
		"screen":
			for i in 3:
				var part := K.node(n, Vector3((i-1)*0.40,0,0.08 if i==1 else 0.0), Vector3(0,20 if i%2 else -20,0))
				for x in [-0.202,0.202]:
					K.box(part,Vector3(0.034,1.54,0.045),K.WOOD,Vector3(x,0.77,0))
				for y in [0.14,0.36,1.50]:
					K.box(part,Vector3(0.39,0.039,0.045),K.WOOD,Vector3(0,y,0))
				K.box(part,Vector3(0.372,0.19,0.027),K.WOOD_LIGHT,Vector3(0,0.25,0))
				K.box(part,Vector3(0.372,1.10,0.026),Color("#c7bca3"),Vector3(0,0.93,0))
				var paper := QuadMesh.new()
				paper.size = Vector2(0.34,1.05)
				if not _screen_panels.has(i):
					var ink := _surface(INK).duplicate() as ShaderMaterial
					ink.set_shader_parameter("triptych_panel", float(i))
					_screen_panels[i] = ink
				K._mesh(part,paper,_screen_panels[i],Vector3(0,0.93,0.015))
		"rice_jar","pickle_jar":
			var scale_by := 0.97 if id == "rice_jar" else 0.72
			storage_jar(n,scale_by,id == "rice_jar")
		"brazier":
			Workshop.place(n, &"Brazier")
		"incense":
			Workshop.place(n, &"Incense")
		"bamboo":
			potted_bamboo(n, Vector3.ZERO, false).scale = Vector3.ONE * 0.75
		"planter":
			for x in [-0.60,0.60]:
				K.box(n,Vector3(0.092,0.35,0.49),K.WOOD,Vector3(x,0.175,0))
			for z in [-0.24,0.24]:
				for j in 2:
					K.box(n,Vector3(1.38,0.104,0.042),K.WOOD_LIGHT,Vector3(0,0.16+j*0.11,z))
			K.box(n,Vector3(1.18,0.115,0.435),K.Assets.pbr("brown_mud_dry",0.84,Color("#9a856a")),Vector3(0,0.236,0))
		"rat_trap":
			# 一只旧竹笼，保留可拾取的家具占地。
			for z in [-0.117,0.117]:
				K.box(n,Vector3(0.48,0.055,0.034),K.WOOD,Vector3(0,0.030,z))
			for i in 7:
				var hoop := TorusMesh.new()
				hoop.outer_radius = 0.131
				hoop.inner_radius = 0.118
				hoop.rings = 16
				hoop.ring_segments = 5
				K._mesh(n,hoop,K.mat(Color("#946d48"),0.91),Vector3(-0.21+i*0.07,0.096,0),Vector3(0,0,90))
			for z in [-0.082,0,0.082]:
				K.box(n,Vector3(0.47,0.016,0.018),K.WOOD_LIGHT,Vector3(0,0.215-absf(z)*0.34,z))
		"smoke_rack":
			for x in [-0.5,0.5]:
				K.box(n, Vector3(0.069,1.51,0.075),K.WOOD,Vector3(x,0.755,0))
				K.box(n, Vector3(0.106,0.073,0.48),K.WOOD,Vector3(x,0.037,0))
			K.box(n,Vector3(1.15,0.065,0.068),K.WOOD_LIGHT,Vector3(0,1.47,0))
			Workshop.place(n,&"SmokedMeat")
		_:
			return false
	House.finish_joinery(n)
	K.merge_static(n, [])
	return true


static func storage_jar(n: Node3D, size: float, rice: bool) -> void:
	var vessel := _turned_vessel(PackedVector2Array([Vector2(0.21,0),Vector2(0.23,0.043),
			Vector2(0.31,0.14),Vector2(0.366,0.37),Vector2(0.347,0.54),Vector2(0.29,0.652),
			Vector2(0.231,0.68),Vector2(0.227,0.728),Vector2(0.241,0.743),Vector2(0.237,0.757)]))
	var body := K.node(n)
	body.scale = Vector3.ONE * size
	K._mesh(body,vessel,_surface(GLAZE),Vector3.ZERO)
	if rice:
		for i in 5:
			var z := (i-2)*0.096
			var width := 2.0 * sqrt(0.244*0.244-z*z)
			K.box(body,Vector3(width,0.031,0.093),K.WOOD_LIGHT,Vector3(0,0.763,z),Vector3(0,0,0))
		K.box(body,Vector3(0.16,0.051,0.04),K.WOOD,Vector3(0,0.801,0))
	else:
		var cap := _turned_vessel(PackedVector2Array([Vector2(0.258,0),Vector2(0.26,0.026),Vector2(0.22,0.055),
				Vector2(0.095,0.087),Vector2(0.044,0.1),Vector2(0.038,0.137),Vector2(0.018,0.145)]))
		K._mesh(body,cap,_surface(GLAZE),Vector3.UP*0.744)


## 廊柱上的楹联。
static func couplet(parent: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.box(n, Vector3(0.205, 1.60, 0.020), Color("#82533a"), Vector3.ZERO)
	K.box(n, Vector3(0.184, 1.56, 0.006), Color("#923f32"), Vector3(0, 0, 0.012))
	var verse := "梅\n开\n千\n树\n雪" if pos.x > 0 else "竹\n报\n四\n时\n安"
	var ink := K.text3d(n, verse, Vector3(0, 0, 0.020), 48, Color("#2c221e"), false, 0.0034)
	ink.outline_size = 0
	ink.line_spacing = 18.0
	ink.shaded = true
	return n


## 条案上的供奉：牌位、香炉、一对蜡烛。y 是条案面高。
static func altar_items(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	var lacquer := K.mat(Color("#573a30"), 0.46)
	K.box(n, Vector3(0.34, 0.043, 0.20), lacquer, Vector3(0, 0.022, -0.02))
	K.box(n, Vector3(0.28, 0.054, 0.15), lacquer, Vector3(0, 0.067, -0.02))
	K.box(n, Vector3(0.222, 0.37, 0.072), lacquer, Vector3(0, 0.276, -0.024))
	K.sphere(n, 0.110, lacquer, Vector3(0, 0.459, -0.024), Vector3(1, 0.56, 0.327))
	for side in [-1, 1]:
		K.box(n, Vector3(0.009, 0.325, 0.007), Color("#937752"), Vector3(side * 0.084, 0.286, 0.015))
	var inscription := K.text3d(n, "先\n人\n之\n位", Vector3(0, 0.282, 0.019), 48, Color("#d2b77d"), false, 0.00138)
	inscription.outline_size = 0
	inscription.shaded = true
	K.cyl(n, 0.08, 0.1, 0.1, K.mat(Color("#6c5a3a"), 0.4), Vector3(0, 0.05, 0.11))
	for sx in [-1, 1]:
		K.cyl(n, 0.025, 0.025, 0.2, K.mat(Color("#e8dcc0")), Vector3(sx * 0.5, 0.1, 0.05))
		K.sphere(n, 0.022, K.mat(Color("#ffb34a"), 0.5, 4.0), Vector3(sx * 0.5, 0.22, 0.05))
		K.light(n, Color("#ffb36b"), 0.5, 2.5, Vector3(sx * 0.5, 0.4, 0.2))
	return n


## 书案上的书和油灯。y 是桌面高。
static func desk_items(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	for k in 2:
		var book := K.node(n, Vector3(-0.25 + 0.016 * k, 0.060 * k, 0.075), Vector3(0, k * 6 - 4, 0))
		K.box(book, Vector3(0.32, 0.044, 0.216), Color("#cabb97"), Vector3(0, 0.028, 0))
		K.box(book, Vector3(0.33, 0.012, 0.228), Color("#57666b"), Vector3(0, 0.054, 0))
		K.box(book, Vector3(0.035, 0.061, 0.23), Color("#4a575b"), Vector3(-0.149, 0.03, 0))
		K.box(book, Vector3(0.058, 0.002, 0.116), Color("#c4b792"), Vector3(0.086, 0.061, -0.016))
	var leaf := K.node(n, Vector3(0.14, 0.009, -0.072), Vector3(0, -7, 0))
	K.box(leaf, Vector3(0.325, 0.014, 0.254), Color("#dbcba5"), Vector3.ZERO)
	for i in 4:
		K.box(leaf, Vector3(0.008, 0.002, 0.09 + 0.013 * (i % 3)), Color("#91816a"), Vector3(0.082 - 0.031 * i, 0.008, -0.017))
	K.cyl(n, 0.085, 0.066, 0.045, K.mat(Color("#4b4f47"), 0.42), Vector3(0.245, 0.024, 0.156), Vector3.ZERO, 18)
	K.cyl(n, 0.047, 0.047, 0.004, K.mat(Color("#262b2a"), 0.18), Vector3(0.245, 0.048, 0.156), Vector3.ZERO, 18)
	K.cyl(n, 0.009, 0.011, 0.27, Color("#977245"), Vector3(0.107, 0.023, 0.102), Vector3(90, 66, 0), 8)
	K.light(n, Color("#ffb36b"), 0.6, 3.0, Vector3(0.25, 0.3, 0.2))
	K.merge_static(n, [])
	return n
