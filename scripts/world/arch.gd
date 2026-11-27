extends RefCounted
## 徽派建筑构件：屋顶、马头墙、厅堂、院墙、门楼、漏窗。
## 约定：Y 向上；局部 +Z 是"前"（开敞面 / 门面）。

const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")
const HomeHouse = preload("res://scripts/world/home_house.gd")
const Signs = preload("res://scripts/world/painted_signs.gd")

const EAVE := 0.8


## 双坡屋顶，屋脊沿 X。base 是檐口高度的中心点。返回屋顶节点（材质可单独淡出）。
static func roof(parent: Node3D, w: float, d: float, rise: float, base: Vector3, material: Material, eave := EAVE, tile_mat: Material = null) -> Node3D:
	var r := K.node(parent, base)
	K.prism(r, Vector3(d + eave * 2, rise, w + eave * 2), material, Vector3(0, rise / 2.0, 0), Vector3(0, 90, 0))
	tiles(r, w + eave * 2, d / 2.0 + eave, rise, tile_mat if tile_mat != null else HomeHouse.roof_tiles())
	# 屋脊与两端起翘
	K.box(r, Vector3(w + eave * 2 + 0.3, 0.2, 0.28), material, Vector3(0, rise + 0.05, 0))
	for sx in [-1, 1]:
		K.box(r, Vector3(0.5, 0.18, 0.26), material, Vector3(sx * (w / 2.0 + eave + 0.25), rise + 0.2, 0), Vector3(0, 0, sx * -35))
	# 檐口一道深色瓦当线
	for sz in [-1, 1]:
		K.box(r, Vector3(w + eave * 2, 0.08, 0.12), K.ROOF_EDGE, Vector3(0, 0.02, sz * (d / 2.0 + eave - 0.05)))
	return r


## 一条瓦垄包含上下压茬的筒瓦、板瓦与露在屋檐的胎口。两坡一次实例化。
static func tiles(parent: Node3D, length: float, half_depth: float, rise: float, material: Material) -> MultiMeshInstance3D:
	var runs := maxi(1, roundi(length / 0.33))
	var rows := clampi(roundi(half_depth / 0.68), 1, 5)
	var width := length / runs
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section := PackedVector2Array([Vector2(0, 0.070), Vector2(0.16, 0.047), Vector2(0.28, 0.004),
		Vector2(0.76, 0.004), Vector2(0.88, 0.048), Vector2(1, 0.070)])
	for row in rows:
		var near := float(row) / rows
		var far := float(row + 1) / rows
		var bottom := Vector2(near * half_depth, near * rise + 0.055 + 0.075 * pow(1.0 - near, 5))
		var top := Vector2(far * half_depth, far * rise + 0.030 + 0.075 * pow(1.0 - far, 5))
		for j in section.size() - 1:
			var a := section[j]
			var b := section[j + 1]
			var normal := Vector3(a.y - b.y, (b.x - a.x) * width, -rise / half_depth * (b.x - a.x) * width).normalized()
			for st: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2(0, 1)]:
				var profile := a.lerp(b, st.x)
				var along := bottom.lerp(top, st.y)
				surface.set_normal(normal)
				surface.set_uv(Vector2(0.039 + profile.x * 0.044, 0.870 + st.y * 0.060))
				surface.add_vertex(Vector3(profile.x * width, along.y + profile.y, along.x))
			if row > 0:
				continue # 压茬背面埋在下片瓦中，仅为外檐封胎口。
			for st: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2(0, 1)]:
				var profile := a.lerp(b, st.x)
				surface.set_normal(Vector3.FORWARD)
				surface.set_uv(Vector2(0.039 + profile.x * 0.044, 0.93 + st.y * 0.01))
				surface.add_vertex(Vector3(profile.x * width, bottom.y + profile.y - (1.0 - st.y) * 0.028, bottom.x))
	surface.generate_tangents()
	surface.index()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = surface.commit()
	mm.instance_count = runs * 2
	for side in 2:
		var turn := Basis(Vector3.UP, PI * side)
		for i in runs:
			var index := side * runs + i
			mm.set_instance_transform(index, Transform3D(turn, turn * Vector3(i * width - length / 2.0, 0, -half_depth)))
			var shade := 0.62 + 0.035 * posmod(i * 11 + side * 3, 5)
			mm.set_instance_color(index, Color(shade * 0.90, shade * 0.95, shade))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = mm
	batch.material_override = material
	parent.add_child(batch)
	return batch


## 马头墙：山墙在屋顶上方阶梯状升起，每阶压一道黛瓦。x 是山墙所在位置，d 是进深。
static func ma_tou(parent: Node3D, x: float, z: float, d: float, eave_h: float, rise: float) -> void:
	var levels := [[0.0, d * 0.18, eave_h + rise + 0.62], [d * 0.18, d * 0.35, eave_h + rise * 0.55 + 0.38], [d * 0.35, d * 0.5 + 0.11, eave_h + 0.26]]
	for level in levels:
		var inner:float = level[0]
		var outer:float = level[1]
		var top:float = level[2]
		for side in [-1.0, 1.0]:
			var mid:float = z + side * (inner + outer) * 0.5
			var span := outer - inner
			K.box(parent, Vector3(0.32, top, span), HomeHouse.plaster(), Vector3(x, top / 2.0, mid))
			K.box(parent, Vector3(0.46, 0.10, span + 0.10), K.ROOF, Vector3(x, top + 0.05, mid))
			K.box(parent, Vector3(0.43, 0.075, 0.22), K.ROOF, Vector3(x, top + 0.105, z + side * (outer + 0.065)), Vector3(side * 18.0, 0, 0))


## 厅堂/廊屋。walls: "back"/"left"/"right" 里哪几面砌墙；前面开敞，只立柱。
## 返回 {node, roof, roof_mat, rect}，rect 是本地 XZ 范围，用来判断人在不在屋里。
static func hall(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, h: float, walls: Array, gables := true) -> Dictionary:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.box(n, Vector3(w + 0.6, 0.1, d + 0.6), K.STONE_DARK, Vector3(0, 0.05, 0))
	K.box(n, Vector3(w - 0.2, 0.02, d - 0.2), Assets.pbr("brown_planks_09", 2.3, Color("#aa8b70")), Vector3(0, 0.11, 0))
	if "back" in walls:
		K.solid(n, Vector3(w, h, 0.3), HomeHouse.plaster(), Vector3(0, h / 2.0, -d / 2.0))
		K.box(n, Vector3(w, 0.5, 0.32), K.WALL_SHADE, Vector3(0, 0.25, -d / 2.0))
	for side in [["left", -1], ["right", 1]]:
		if side[0] in walls:
			K.solid(n, Vector3(0.3, h, d), HomeHouse.plaster(), Vector3(side[1] * w / 2.0, h / 2.0, 0))
	# 前檐柱 + 额枋 + 挂落
	var bays := maxi(2, int(round(w / 3.0)))
	for k in bays + 1:
		var x := -w / 2.0 + w * k / float(bays)
		K.cyl(n, 0.13, 0.15, h, K.LACQUER, Vector3(x, h / 2.0, d / 2.0 - 0.2))
		K.collider(n, Vector3(0.3, h, 0.3), Vector3(x, h / 2.0, d / 2.0 - 0.2))
		K.cyl(n, 0.2, 0.22, 0.18, K.STONE, Vector3(x, 0.09, d / 2.0 - 0.2))
	K.box(n, Vector3(w + 0.3, 0.32, 0.3), K.WOOD, Vector3(0, h - 0.16, d / 2.0 - 0.2))
	for k in bays:
		var cx := -w / 2.0 + w * (k + 0.5) / float(bays)
		K.box(n, Vector3(w / bays - 0.5, 0.22, 0.06), K.WOOD_LIGHT, Vector3(cx, h - 0.45, d / 2.0 - 0.2))
	var roof_mat: BaseMaterial3D = Assets.pbr_unique("grey_roof_tiles", 1.6, Color(0.62, 0.64, 0.68))
	if roof_mat == null:
		roof_mat = K.unique_mat(K.ROOF.darkened(0.25), 0.8)
	var tile_mat := HomeHouse.roof_tiles().duplicate() as BaseMaterial3D
	var r := roof(n, w, d, d * 0.42, Vector3(0, h, 0), roof_mat, EAVE, tile_mat)
	if gables:
		for sx in [-1, 1]:
			ma_tou(n, sx * (w / 2.0 + 0.05), 0, d, h, d * 0.42)
	return {"node": n, "roof": r, "fade_mats": [roof_mat, tile_mat], "w": w, "d": d}


## 院墙一段（沿 X 或 Z 的直墙），粉墙 + 黛瓦压顶。
static func wall(parent: Node3D, a: Vector3, b: Vector3, h := 3.0) -> void:
	var mid := (a + b) / 2.0
	var length := a.distance_to(b)
	var along_x: bool = absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(length, h, 0.36) if along_x else Vector3(0.36, h, length)
	K.solid(parent, size, HomeHouse.plaster(), Vector3(mid.x, h / 2.0, mid.z))
	var trim := K.node(parent, mid, Vector3(0, 0 if along_x else 90, 0))
	var plinth := minf(0.48, h * 0.28)
	var block := Assets.pbr("rock_face_03", 2.8, Color("#a5acaa"))
	var count := maxi(1, roundi(length / 0.94))
	for row in 2:
		for i in range(count + row):
			var x0 := maxf(0, (i - row * 0.5) * length / count)
			var x1 := minf(length, (i + 1.0 - row * 0.5) * length / count)
			K.box(trim, Vector3(x1 - x0 - 0.013, plinth * 0.5 - 0.012, 0.407), block,
				Vector3((x0 + x1 - length) * 0.5, (row + 0.5) * plinth * 0.5, 0))
	HomeHouse.wall_cap(K.node(trim, Vector3.UP * h), length)


## 门楼：两扇可动的门（做破损、撞门的动画），门钉、春联、灯笼。返回各部件。
static func gate(parent: Node3D, pos: Vector3, width := 2.6, h := 3.0) -> Dictionary:
	var n := K.node(parent, pos)
	for sx in [-1, 1]:
		K.solid(n, Vector3(0.6, h + 0.6, 0.6), HomeHouse.plaster(), Vector3(sx * (width / 2.0 + 0.3), (h + 0.6) / 2.0, 0))
		var paper := Vector3(sx * (width / 2.0 + 0.3), h - 1.73, 0.31)
		K.box(n, Vector3(0.22, 1.6, 0.02), K.CINNABAR, paper)
		Signs.verse(n, 3 if sx > 0 else 2, Vector2(0.216, 1.59), paper + Vector3(0, 0, 0.011))
	K.box(n, Vector3(width + 1.4, 0.4, 0.5), K.WOOD, Vector3(0, h + 0.1, 0))
	K.box(n, Vector3(1.1, 0.36, 0.06), K.ROOF_EDGE, Vector3(0, h - 0.25, 0.29))
	var lintel := K.text3d(n, "春满人间", Vector3(0, h - 0.25, 0.325), 84, Color("#e1c186"), false, 0.0025)
	lintel.outline_size = 0
	roof(n, width + 0.8, 0.5, 0.55, Vector3(0, h + 0.3, 0), K.mat(K.ROOF, 0.7), 0.35)
	var leaves := []
	var leaf_mats := []
	for sx in [-1, 1]:
		var pivot := K.node(n, Vector3(sx * width / 2.0, 0, 0))
		var m := K.unique_mat(K.LACQUER, 0.47)
		m.albedo_texture = preload("res://assets/third_party/polyhaven/textures/brown_planks_09/brown_planks_09_diff.jpg")
		m.normal_enabled = true
		m.normal_texture = preload("res://assets/third_party/polyhaven/textures/brown_planks_09/brown_planks_09_nor.jpg")
		m.normal_scale = 0.25
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.36
		# 木纹随门板一起转动；三块漆板留有窄缝，破损时仍共用该门扇的染色。
		var board_w := (width * 0.5 - 0.04) / 3.0
		for i in 3:
			K.box(pivot, Vector3(h - 0.1, board_w - 0.009, 0.16), m,
				Vector3(-sx * (0.02 + (i + 0.5) * board_w), (h - 0.1) * 0.5, 0), Vector3(0, 0, 90))
		for row in 4:
			for col in 3:
				K.sphere(pivot, 0.04, K.mat(K.GOLD, 0.4), Vector3(-sx * (0.25 + col * 0.35), 0.6 + row * 0.55, 0.09))
		var bronze := _aged_brass()
		var latch := K.node(pivot, Vector3(-sx * (width / 2.0 - 0.21), 1.40, 0.105))
		K.box(latch, Vector3(0.16, 0.16, 0.045), bronze, Vector3.ZERO, Vector3(0, 0, 45))
		var ring := TorusMesh.new()
		ring.outer_radius = 0.089
		ring.inner_radius = 0.058
		ring.rings = 16
		ring.ring_segments = 8
		var knocker := MeshInstance3D.new()
		knocker.mesh = ring
		knocker.material_override = bronze
		knocker.position = Vector3(0, -0.078, 0.055)
		knocker.rotation.x = PI * 0.5
		latch.add_child(knocker)
		leaves.append(pivot)
		leaf_mats.append(m)
	var door_body := K.collider(n, Vector3(width, h, 0.3), Vector3(0, h / 2.0, 0))
	var lanterns := []
	for sx in [-1, 1]:
		lanterns.append(lantern(n, Vector3(sx * (width / 2.0 + 0.3), h - 0.5, 0.5)))
	return {"node": n, "leaves": leaves, "leaf_mats": leaf_mats, "collider": door_body, "lanterns": lanterns}


## 灯笼：红纱 + 内光。返回 {node, light, mat} 以便夜里点亮。
static var _silk_mesh: ArrayMesh
static var _silk_light: ImageTexture
static var _brass: StandardMaterial3D

static func _aged_brass() -> StandardMaterial3D:
	if _brass == null:
		_brass = K.unique_mat(Color("#aa8653"), 0.44)
		_brass.metallic = 0.66
	return _brass

static func lantern(parent: Node3D, pos: Vector3) -> Dictionary:
	var n := K.node(parent, pos)
	K.box(n, Vector3(0.03, 0.3, 0.03), K.WOOD, Vector3(0, 0.35, 0))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color("#ff955c")
	m.emission_energy_multiplier = 0.0
	if _silk_mesh == null:
		_silk_mesh = _lantern_shade()
		_silk_light = _lantern_transmission()
	m.emission_texture = _silk_light
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var shade := MeshInstance3D.new()
	shade.mesh = _silk_mesh
	shade.material_override = m
	n.add_child(shade)
	for y in [-0.233, 0.233]:
		K.cyl(n, 0.145, 0.145, 0.036, Color("#554337"), Vector3.UP * y)
		K.cyl(n, 0.144, 0.144, 0.013, _aged_brass(), Vector3.UP * (y * 1.09))
	K.cyl(n, 0.017, 0.032, 0.13, Color("#97462f"), Vector3(0, -0.31, 0))
	var l := K.light(n, Color("#ffae6b"), 0.0, 7.0, Vector3(0, -0.1, 0))
	return {"node": n, "light": l, "mat": m}


static func _lantern_shade() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.125, -0.225), Vector2(0.224, -0.167), Vector2(0.25, -0.05),
		Vector2(0.25, 0.05), Vector2(0.224, 0.167), Vector2(0.125, 0.225)])
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 36
	for row in profile.size():
		var dr := profile[mini(row + 1, profile.size() - 1)] - profile[maxi(row - 1, 0)]
		for i in SIDES + 1:
			var a := TAU * i / SIDES
			var rib := i % 3 == 0
			var radius := profile[row].x - (0.012 if rib else 0.0)
			var silk := Color("#a73e2b") if rib else Color("#d06641")
			skin.set_color(silk.darkened(0.26 * absf(profile[row].y) / 0.225).srgb_to_linear())
			skin.set_uv(Vector2(float(i) / SIDES, (profile[row].y + 0.225) / 0.45))
			skin.set_normal(Vector3(cos(a) * dr.y, -dr.x, sin(a) * dr.y).normalized())
			skin.add_vertex(Vector3(cos(a) * radius, profile[row].y, sin(a) * radius))
	for row in profile.size() - 1:
		for i in SIDES:
			var a := row * (SIDES + 1) + i
			var b := a + 1
			for index in [a, b, b + SIDES + 1, a, b + SIDES + 1, a + SIDES + 1]:
				skin.add_index(index)
	return skin.commit()


## 灯芯从罩子中段透光，十二道竹骨和上下铜箍留在暗处。
static func _lantern_transmission() -> ImageTexture:
	var mask := Image.create_empty(192, 64, false, Image.FORMAT_RGBA8)
	for y in mask.get_height():
		var height_ratio := (y + 0.5) / mask.get_height()
		var center := sin(PI * height_ratio)
		for x in mask.get_width():
			var phase := fposmod((x + 0.5) / 16.0, 1.0)
			var rib := smoothstep(0.02, 0.20, minf(phase, 1.0 - phase))
			var brightness := 0.19 + 0.81 * center * (0.33 + 0.67 * rib)
			mask.set_pixel(x, y, Color(brightness, brightness, brightness))
	mask.generate_mipmaps()
	return ImageTexture.create_from_image(mask)


static func set_lantern(lan: Dictionary, lit: bool) -> void:
	lan.mat.emission_energy_multiplier = 1.6 if lit else 0.0
	lan.light.light_energy = 1.6 if lit else 0.0


## 漏窗：墙上的方形花格窗，两面都看得到。返回节点（破损时换格子）。
static func lattice_window(parent: Node3D, pos: Vector3, size := 1.3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(size + 0.2, size + 0.2, 0.42), K.ROOF_EDGE, Vector3.ZERO)
	K.box(n, Vector3(size, size, 0.44), K.mat(Color("#1d1a17")), Vector3.ZERO)
	return n


static func window_bars(win: Node3D, size: float, ratio: float, boarded: bool) -> void:
	var bars := K.node(win, Vector3.ZERO, Vector3.ZERO, "bars")
	var count := 5
	var keep := int(ceil(count * clampf(ratio, 0.0, 1.0)))
	for k in count:
		var off := -size / 2.0 + size * (k + 0.5) / count
		if k < keep:
			K.box(bars, Vector3(0.07, size, 0.46), K.WALL, Vector3(off, 0, 0))
		if k < keep or k % 2 == 0:
			K.box(bars, Vector3(size, 0.07, 0.46), K.WALL, Vector3(0, off, 0))
	if boarded and ratio > 0.2:
		for k in 3:
			K.box(bars, Vector3(size + 0.3, 0.22, 0.08), K.WOOD_LIGHT, Vector3(0, -0.4 + k * 0.4, 0.27), Vector3(0, 0, -8 + k * 8))
