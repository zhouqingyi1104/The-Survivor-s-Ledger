extends RefCounted
## 阁楼里的床帐、地毯与晨起盥洗家具，尺寸用米。
const K = preload("res://scripts/world/kit.gd")
const House = preload("res://scripts/world/home_house.gd")
const Props = preload("res://scripts/world/props.gd")
const Figure = preload("res://scripts/world/character.gd")
const CARPET = preload("res://scripts/world/attic_carpet.gdshader")
static var _carpet: ShaderMaterial


static func floor_rug(parent: Node3D) -> void:
	if _carpet == null:
		_carpet = ShaderMaterial.new()
		_carpet.shader = CARPET
	var rug := PlaneMesh.new()
	rug.size = Vector2(2.65, 2.30)
	K._mesh(parent, rug, _carpet, Vector3.ZERO)


static func bed_curtains(bed: Node3D) -> void:
	# 帐顶留敞，前缘只挂短帷，玩家从屋中仍看得见被褥。
	for x: float in [-0.54, 0.54]:
		for z: float in [-1.11, 1.11]:
			K.box(bed, Vector3(0.058, 1.62, 0.058), House.TIMBER, Vector3(x, 1.10, z))
			K.cyl(bed, 0.047, 0.045, 0.047, House.TRIM, Vector3(x, 1.88, z), Vector3.ZERO, 12)
		K.box(bed, Vector3(0.063, 0.073, 2.30), House.TRIM, Vector3(x, 1.92, 0))
	for z: float in [-1.11, 1.11]:
		K.box(bed, Vector3(1.13, 0.075, 0.068), House.TRIM, Vector3(0, 1.92, z))
	var side := K.node(bed, Vector3(-0.54, 1.89, 0), Vector3(0, -90, 0))
	_curtain(side, -1.09, 0.71, 1.24, -1.0)
	var near := K.node(bed, Vector3(0.54, 1.89, 0), Vector3(0, -90, 0))
	_curtain(near, -1.09, 0.61, 1.28, -1.0)
	_curtain(near, 0.69, 0.40, 1.11, 1.0)
	_valance(near, 2.20)
	_valance(K.node(bed, Vector3(0, 1.89, 1.11)), 1.08)


static func _curtain(parent: Node3D, left: float, width: float, drop: float, tied_side: float) -> void:
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var folds := 24
	var rows := 14
	for j in rows + 1:
		var v := float(j) / rows
		var gather := 1.0 - smoothstep(0.0, 0.66, absf(v - 0.62))
		var breadth := width * (1.0 - 0.80 * gather)
		var start := left if tied_side < 0 else left + width - breadth
		for i in folds + 1:
			var u := float(i) / folds
			var curl := sin(u * TAU * 3.5 + v * 0.85)
			var shade := Color("#d4bda2") if j == rows - 1 or j == 1 else Color.WHITE
			if j == 9:
				shade = Color("#b18a58")
			cloth.set_color(shade)
			cloth.set_uv(Vector2(u, v))
			cloth.add_vertex(Vector3(start + u * breadth, -drop * v + 0.033 * curl * v,
				(0.014 + 0.039 * (1.0 - gather)) * curl + 0.012 * sin(v * PI)))
	_connect_grid(cloth, folds, rows)
	K._mesh(parent, cloth.commit(), Figure._cloth(Color("#ddd0a6")), Vector3.ZERO)


static func _valance(parent: Node3D, width: float) -> void:
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 4:
		for i in 33:
			var u := i / 32.0
			var depth := 0.108 + 0.088 * sin(u * PI) + 0.014 * cos(u * TAU * 6.0)
			var v: float = [0.0, 0.69, 0.84, 1.0][row]
			cloth.set_color(Color("#cfaa7a") if row == 2 else Color.WHITE)
			cloth.set_uv(Vector2(u, v))
			cloth.add_vertex(Vector3((u - 0.5) * width, -depth * v, 0.046 + 0.014 * cos(u * TAU * 8)))
	_connect_grid(cloth, 32, 3)
	K._mesh(parent, cloth.commit(), Figure._cloth(Color("#a5614c")), Vector3.ZERO)


static func _connect_grid(mesh: SurfaceTool, columns: int, rows: int) -> void:
	for y in rows:
		for x in columns:
			var k := y * (columns + 1) + x
			for index in [k, k + 1, k + columns + 2, k, k + columns + 2, k + columns + 1]:
				mesh.add_index(index)
	mesh.generate_normals()
	mesh.generate_tangents()


static func basin_stand(stand: Node3D) -> void:
	var rail := House.TIMBER
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			K.box(stand, Vector3(0.058, 0.75, 0.058), rail,
				Vector3(side * 0.229, 0.375, end * 0.215), Vector3(end * -4, 0, side * 4))
		K.box(stand, Vector3(0.49, 0.075, 0.054), House.TRIM, Vector3(0, 0.245, side * 0.23))
		K.box(stand, Vector3(0.059, 0.078, 0.51), House.TRIM, Vector3(side * 0.231, 0.69, 0))
	K.cyl(stand, 0.361, 0.347, 0.055, House.TRIM, Vector3.UP * 0.741, Vector3.ZERO, 40)
	var bowl := Props._turned_vessel(PackedVector2Array([
		Vector2(0.002, 0.000), Vector2(0.162, 0.000), Vector2(0.163, 0.021),
		Vector2(0.207, 0.041), Vector2(0.286, 0.106), Vector2(0.328, 0.178),
		Vector2(0.337, 0.199), Vector2(0.336, 0.210), Vector2(0.320, 0.210),
		Vector2(0.308, 0.176), Vector2(0.269, 0.111), Vector2(0.196, 0.058),
		Vector2(0.144, 0.042), Vector2(0.002, 0.042)]), true)
	var clay := K.mat(Color("#a6c1af"), 0.27)
	K._mesh(stand, bowl, clay, Vector3.UP * 0.769)
	var water := K.mat(Color("#728b80"), 0.16)
	K.cyl(stand, 0.275, 0.275, 0.002, water, Vector3.UP * 0.895, Vector3.ZERO, 48)


static func clothes_rail(rack: Node3D) -> void:
	var wood := House.TRIM
	for side: float in [-1.0, 1.0]:
		K.box(rack, Vector3(0.15, 0.08, 0.46), House.TIMBER, Vector3(side * 0.54, 0.05, 0))
		K.cyl(rack, 0.027, 0.034, 1.53, wood, Vector3(side * 0.54, 0.80, 0), Vector3.ZERO, 12)
		K.sphere(rack, 0.044, wood, Vector3(side * 0.54, 1.583, 0))
	K.box(rack, Vector3(1.12, 0.049, 0.044), House.TIMBER, Vector3.UP * 0.23)
	K.cyl(rack, 0.026, 0.026, 1.23, wood, Vector3.UP * 1.53, Vector3(0, 0, 90), 16)
	_hanging_towel(rack, -0.38, 0.25, 0.68, Color("#cab89b"))
	_work_jacket(K.node(rack, Vector3(0.15, 1.47, 0.055), Vector3(0, -5, -3)))


static func _work_jacket(hanger: Node3D) -> void:
	# 短褂有肩、袖、掩襟。不同宽度的断面在肘下收束，垂褶在下摆逐渐散开。
	var neck := K.mat(Color("#a58154"), 0.77)
	K.cyl(hanger, 0.012, 0.012, 0.14, neck, Vector3.UP * 0.034)
	for side: float in [-1.0, 1.0]:
		K.box(hanger, Vector3(0.31, 0.039, 0.051), House.TRIM,
			Vector3(side * 0.14, -0.056, 0), Vector3(0, 0, -side * 15))
	var shape := PackedVector2Array([Vector2(0.103, -0.02), Vector2(0.263, -0.104),
		Vector2(0.445, -0.206), Vector2(0.411, -0.356), Vector2(0.274, -0.372),
		Vector2(0.224, -0.405), Vector2(0.226, -0.641), Vector2(0.253, -0.929),
		Vector2(0.260, -0.96)])
	# 一侧用连续衣身，另一侧多留一层斜襟的收边。深色袖口与下摆压住毛边。
	var jacket := SurfaceTool.new()
	jacket.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		for j in shape.size() - 1:
			for i in 10:
				for ij: Vector2i in [Vector2i(i,j), Vector2i(i+1,j), Vector2i(i+1,j+1),
						Vector2i(i,j), Vector2i(i+1,j+1), Vector2i(i,j+1)]:
					var u := float(ij.x) / 10.0
					var profile := shape[ij.y]
					var v := -profile.y
					var x := side * u * profile.x
					var pleat := sin(u * 13.0 + v * 1.8 + side * 0.28)
					var z := 0.023 + (0.031 + 0.018 * v) * pleat + 0.022 * sin(u * PI)
					var facing := ij.y == shape.size()-1 or (ij.y in [3,4] and u > 0.83)
					jacket.set_color(Color("#8c8b72") if facing else Color.WHITE)
					jacket.set_uv(Vector2(0.5 + x, v))
					jacket.add_vertex(Vector3(x, profile.y - 0.017 * pleat * v, z))
	jacket.generate_normals()
	jacket.generate_tangents()
	jacket.index()
	K._mesh(hanger, jacket.commit(), Figure._cloth(Color("#799090")), Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var from := Vector3(0.092 * side, -0.015, 0.089)
		var to := Vector3(0.034 * -side, -0.239 if side < 0 else -0.17, 0.081)
		var seam := K.box(hanger, Vector3(0.025, from.distance_to(to), 0.009),
			K.mat(Color("#bbb198"), 0.94), (from + to) * 0.5)
		seam.quaternion = Quaternion(Vector3.UP, (from - to).normalized())


static func _hanging_towel(rack: Node3D, x: float, width: float, drop: float, dye: Color) -> void:
	var textile := SurfaceTool.new()
	textile.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section := PackedVector2Array([Vector2(-0.087, -drop * 0.70), Vector2(-0.045, -0.18),
			Vector2(-0.031, 0.000), Vector2(-0.025, 0.026), Vector2(0.0, 0.038),
			Vector2(0.027, 0.024), Vector2(0.035, -0.015), Vector2(0.057, -0.24),
			Vector2(0.083, -drop * 0.85), Vector2(0.083, -drop * 0.89), Vector2(0.087, -drop)])
	for j in section.size():
		var point := section[j]
		var hanging := maxf(0.0, -point.y / drop)
		for i in 19:
			var u := i / 18.0
			var pleat := sin(TAU * (2.1 * u + hanging * 0.2))
			textile.set_color(Color("#caaf8a") if j == 9 or i == 1 else Color.WHITE)
			textile.set_uv(Vector2(u, j / float(section.size() - 1)))
			textile.add_vertex(Vector3(x + (u - 0.5) * width + 0.023 * hanging,
				1.53 + point.y + hanging * (0.019 * pleat - 0.023 * u), point.x + hanging * 0.035 * pleat))
	_connect_grid(textile, 18, section.size() - 1)
	K._mesh(rack, textile.commit(), Figure._cloth(dye), Vector3.ZERO)
