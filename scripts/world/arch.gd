extends RefCounted
## 徽派建筑构件：屋顶、马头墙、厅堂、院墙、门楼、漏窗。全部用基本体拼。
## 约定：Y 向上；局部 +Z 是"前"（开敞面 / 门面）。

const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")

const EAVE := 0.8


## 双坡屋顶，屋脊沿 X。base 是檐口高度的中心点。返回屋顶节点（材质可单独淡出）。
static func roof(parent: Node3D, w: float, d: float, rise: float, base: Vector3, material: Material, eave := EAVE, tile_mat: Material = null) -> Node3D:
	var r := K.node(parent, base)
	K.prism(r, Vector3(d + eave * 2, rise, w + eave * 2), material, Vector3(0, rise / 2.0, 0), Vector3(0, 90, 0))
	tiles(r, w + eave * 2, d / 2.0 + eave, rise, tile_mat if tile_mat != null else K.mat(Color("#4d535a"), 0.6))
	# 屋脊与两端起翘
	K.box(r, Vector3(w + eave * 2 + 0.3, 0.2, 0.28), material, Vector3(0, rise + 0.05, 0))
	for sx in [-1, 1]:
		K.box(r, Vector3(0.5, 0.18, 0.26), material, Vector3(sx * (w / 2.0 + eave + 0.25), rise + 0.2, 0), Vector3(0, 0, sx * -35))
	# 檐口一道深色瓦当线
	for sz in [-1, 1]:
		K.box(r, Vector3(w + eave * 2, 0.08, 0.12), K.ROOF_EDGE, Vector3(0, 0.02, sz * (d / 2.0 + eave - 0.05)))
	return r


## 筒瓦：两面坡上沿坡向一条条排开（MultiMesh，一个屋顶一次画完）。
static func tiles(parent: Node3D, length: float, half_depth: float, rise: float, material: Material) -> MultiMeshInstance3D:
	var spacing := 0.3
	var rows := int(length / spacing)
	var slope_len := sqrt(half_depth * half_depth + rise * rise)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.065
	mesh.bottom_radius = 0.065
	mesh.height = slope_len
	mesh.radial_segments = 6
	mesh.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = rows * 2
	var k := 0
	for side in [1.0, -1.0]:
		var up := Vector3(0, rise, -side * half_depth).normalized()
		var normal := Vector3(0, half_depth, side * rise).normalized()
		var basis := Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up))
		var mid := Vector3(0, rise / 2.0, side * half_depth / 2.0) + normal * 0.06
		for i in rows:
			var x := -length / 2.0 + spacing * (i + 0.5)
			mm.set_instance_transform(k, Transform3D(basis, mid + Vector3(x, 0, 0)))
			k += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	parent.add_child(mi)
	return mi


## 马头墙：山墙在屋顶上方阶梯状升起，每阶压一道黛瓦。x 是山墙所在位置，d 是进深。
static func ma_tou(parent: Node3D, x: float, z: float, d: float, eave_h: float, rise: float) -> void:
	var steps := [[d * 0.36, eave_h + rise + 0.7], [d * 0.7, eave_h + rise * 0.55 + 0.4], [d + 0.2, eave_h + 0.3]]
	for s in steps:
		var sw: float = s[0]
		var top: float = s[1]
		K.box(parent, Vector3(0.32, top, sw), K.WALL, Vector3(x, top / 2.0, z))
		K.box(parent, Vector3(0.5, 0.14, sw + 0.3), K.ROOF, Vector3(x, top + 0.07, z))
		for sz in [-1, 1]:
			K.box(parent, Vector3(0.46, 0.12, 0.34), K.ROOF, Vector3(x, top + 0.16, z + sz * (sw / 2.0 + 0.2)), Vector3(sz * 25, 0, 0))


## 厅堂/廊屋。walls: "back"/"left"/"right" 里哪几面砌墙；前面开敞，只立柱。
## 返回 {node, roof, roof_mat, rect}，rect 是本地 XZ 范围，用来判断人在不在屋里。
static func hall(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, h: float, walls: Array, gables := true) -> Dictionary:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.box(n, Vector3(w + 0.6, 0.1, d + 0.6), K.STONE_DARK, Vector3(0, 0.05, 0))
	K.box(n, Vector3(w - 0.2, 0.02, d - 0.2), K.mat(Color("#7a6a58")), Vector3(0, 0.11, 0))
	if "back" in walls:
		K.solid(n, Vector3(w, h, 0.3), K.WALL, Vector3(0, h / 2.0, -d / 2.0))
		K.box(n, Vector3(w, 0.5, 0.32), K.WALL_SHADE, Vector3(0, 0.25, -d / 2.0))
	for side in [["left", -1], ["right", 1]]:
		if side[0] in walls:
			K.solid(n, Vector3(0.3, h, d), K.WALL, Vector3(side[1] * w / 2.0, h / 2.0, 0))
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
	var tile_mat := K.unique_mat(Color("#3e4349"), 0.6)
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
	K.solid(parent, size, K.WALL, Vector3(mid.x, h / 2.0, mid.z))
	K.box(parent, Vector3(size.x, 0.5, size.z) + Vector3(0.04, 0, 0.04), K.WALL_SHADE, Vector3(mid.x, 0.25, mid.z))
	var cap := Vector3(length + 0.2, 0.16, 0.7) if along_x else Vector3(0.7, 0.16, length + 0.2)
	K.box(parent, cap, K.ROOF, Vector3(mid.x, h + 0.08, mid.z))
	var ridge := Vector3(length + 0.2, 0.12, 0.22) if along_x else Vector3(0.22, 0.12, length + 0.2)
	K.box(parent, ridge, K.ROOF_EDGE, Vector3(mid.x, h + 0.2, mid.z))


## 门楼：两扇可动的门（做破损、撞门的动画），门钉、春联、灯笼。返回各部件。
static func gate(parent: Node3D, pos: Vector3, width := 2.6, h := 3.0) -> Dictionary:
	var n := K.node(parent, pos)
	for sx in [-1, 1]:
		K.solid(n, Vector3(0.6, h + 0.6, 0.6), K.WALL, Vector3(sx * (width / 2.0 + 0.3), (h + 0.6) / 2.0, 0))
		K.box(n, Vector3(0.22, 1.6, 0.02), K.CINNABAR, Vector3(sx * (width / 2.0 + 0.3), 1.9, 0.31))
	K.box(n, Vector3(width + 1.4, 0.4, 0.5), K.WOOD, Vector3(0, h + 0.1, 0))
	K.box(n, Vector3(1.1, 0.36, 0.06), K.ROOF_EDGE, Vector3(0, h - 0.25, 0.29))
	roof(n, width + 0.8, 0.5, 0.55, Vector3(0, h + 0.3, 0), K.mat(K.ROOF, 0.7), 0.35)
	var leaves := []
	var leaf_mats := []
	for sx in [-1, 1]:
		var pivot := K.node(n, Vector3(sx * width / 2.0, 0, 0))
		var m := K.unique_mat(K.LACQUER, 0.6)
		K.box(pivot, Vector3(width / 2.0 - 0.04, h - 0.1, 0.16), m, Vector3(-sx * width / 4.0, (h - 0.1) / 2.0, 0))
		for row in 4:
			for col in 3:
				K.sphere(pivot, 0.04, K.mat(K.GOLD, 0.4), Vector3(-sx * (0.25 + col * 0.35), 0.6 + row * 0.55, 0.09))
		K.box(pivot, Vector3(0.12, 0.12, 0.05), K.mat(K.GOLD, 0.4), Vector3(-sx * (width / 2.0 - 0.18), 1.4, 0.1))
		leaves.append(pivot)
		leaf_mats.append(m)
	var door_body := K.collider(n, Vector3(width, h, 0.3), Vector3(0, h / 2.0, 0))
	var lanterns := []
	for sx in [-1, 1]:
		lanterns.append(lantern(n, Vector3(sx * (width / 2.0 + 0.3), h - 0.5, 0.5)))
	return {"node": n, "leaves": leaves, "leaf_mats": leaf_mats, "collider": door_body, "lanterns": lanterns}


## 灯笼：红纱 + 内光。返回 {node, light, mat} 以便夜里点亮。
static func lantern(parent: Node3D, pos: Vector3) -> Dictionary:
	var n := K.node(parent, pos)
	K.box(n, Vector3(0.03, 0.3, 0.03), K.WOOD, Vector3(0, 0.35, 0))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#c23b2a")
	m.emission_enabled = true
	m.emission = Color("#ff7a3d")
	m.emission_energy_multiplier = 0.0
	K.sphere(n, 0.24, m, Vector3.ZERO, Vector3(1, 1.2, 1))
	K.cyl(n, 0.12, 0.12, 0.06, K.ROOF_EDGE, Vector3(0, 0.29, 0))
	K.cyl(n, 0.12, 0.12, 0.06, K.ROOF_EDGE, Vector3(0, -0.29, 0))
	var l := K.light(n, Color("#ffae6b"), 0.0, 7.0, Vector3(0, -0.1, 0))
	return {"node": n, "light": l, "mat": m}


static func set_lantern(lan: Dictionary, lit: bool) -> void:
	lan.mat.emission_energy_multiplier = 2.5 if lit else 0.0
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
