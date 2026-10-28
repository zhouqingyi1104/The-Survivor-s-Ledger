extends RefCounted
## 院里的家具、物资堆、作物、守具。数量类的（米袋、柴垛、木料）按存货多少摆，让囤货看得见。

const K = preload("res://scripts/world/kit.gd")


static func well(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.cyl(n, 0.75, 0.8, 0.7, K.STONE, Vector3(0, 0.35, 0), Vector3.ZERO, 10)
	K.cyl(n, 0.58, 0.58, 0.72, K.mat(Color("#1c1f22")), Vector3(0, 0.37, 0), Vector3.ZERO, 10)
	K.cyl(n, 0.56, 0.56, 0.02, K.mat(K.WATER, 0.2), Vector3(0, 0.55, 0), Vector3.ZERO, 10)
	K.collider(n, Vector3(1.6, 1.0, 1.6), Vector3(0, 0.5, 0))
	for sx in [-1, 1]:
		K.box(n, Vector3(0.12, 1.9, 0.12), K.WOOD, Vector3(sx * 0.75, 0.95, 0))
	K.cyl(n, 0.08, 0.08, 1.5, K.WOOD_LIGHT, Vector3(0, 1.6, 0), Vector3(0, 0, 90))
	K.prism(n, Vector3(1.3, 0.45, 2.0), K.ROOF, Vector3(0, 2.1, 0), Vector3(0, 90, 0))
	K.cyl(n, 0.16, 0.13, 0.22, K.WOOD_LIGHT, Vector3(0.25, 1.05, 0))
	K.box(n, Vector3(0.01, 0.55, 0.01), K.ROOF_EDGE, Vector3(0.25, 1.4, 0))
	return n


static func stove(parent: Node3D, pos: Vector3, rot_y: float, double: bool) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	var w := 2.2 if double else 1.4
	K.solid(n, Vector3(w, 0.85, 1.0), K.BRICK, Vector3(0, 0.425, 0))
	K.box(n, Vector3(w + 0.1, 0.08, 1.1), K.STONE_DARK, Vector3(0, 0.88, 0))
	var holes := [-0.5, 0.5] if double else [0.0]
	for x in holes:
		K.sphere(n, 0.34, K.mat(Color("#2a2826"), 0.4), Vector3(x, 0.9, 0), Vector3(1, 0.6, 1), true)
		K.box(n, Vector3(0.36, 0.26, 0.04), K.mat(Color("#ff7a3d"), 0.5, 1.8), Vector3(x, 0.32, 0.51))
	K.box(n, Vector3(0.45, 2.6, 0.45), K.BRICK, Vector3(w / 2.0 - 0.15, 1.3, -0.3))
	return n


## 柴垛：根数按存货多少（最多 12 捆）。
static func firewood(parent: Node3D, pos: Vector3, count: int) -> Node3D:
	var n := K.node(parent, pos)
	for k in mini(count, 12):
		var layer := k / 4
		var col := k % 4
		K.cyl(n, 0.12, 0.12, 0.9, K.WOOD_LIGHT, Vector3(-0.39 + col * 0.26, 0.12 + layer * 0.22, 0), Vector3(90, 0, 0), 7)
	return n


## 米袋：一斗一袋，最多摆 16 袋。
static func rice_sacks(parent: Node3D, pos: Vector3, count: int) -> Node3D:
	var n := K.node(parent, pos)
	for k in mini(count, 16):
		var layer := k / 6
		var idx := k % 6
		var x := -0.75 + (idx % 3) * 0.5 + (0.25 if layer % 2 == 1 else 0.0)
		var z := -0.25 + (idx / 3) * 0.5
		K.sphere(n, 0.27, K.RICE_SACK, Vector3(x, 0.22 + layer * 0.36, z), Vector3(1, 0.85, 1.15))
		K.cyl(n, 0.06, 0.08, 0.1, K.RICE_SACK.darkened(0.2), Vector3(x, 0.47 + layer * 0.36, z))
	return n


static func wood_pile(parent: Node3D, pos: Vector3, count: int, rot_y := 0.0) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	for k in mini(count, 10):
		K.box(n, Vector3(2.0, 0.18, 0.2), K.WOOD_LIGHT.darkened(0.1 * (k % 2)), Vector3(0, 0.1 + (k / 3) * 0.19, -0.25 + (k % 3) * 0.25))
	return n


static func water_vat(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.cyl(n, 0.48, 0.38, 0.9, K.mat(Color("#4a3a2e"), 0.3), Vector3(0, 0.45, 0))
	K.cyl(n, 0.44, 0.44, 0.02, K.mat(K.WATER, 0.1), Vector3(0, 0.85, 0))
	K.collider(n, Vector3(1.0, 0.9, 1.0), Vector3(0, 0.45, 0))
	return n


static func bed(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.solid(n, Vector3(2.2, 0.5, 1.3), K.WOOD, Vector3(0, 0.25, 0))
	K.box(n, Vector3(2.0, 0.12, 1.1), K.mat(Color("#b8ab92")), Vector3(0, 0.56, 0))
	K.box(n, Vector3(1.3, 0.16, 1.05), K.CLOTH_BLUE, Vector3(0.3, 0.68, 0))
	K.box(n, Vector3(0.35, 0.14, 0.6), K.mat(Color("#d8cdb5")), Vector3(-0.75, 0.68, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			K.box(n, Vector3(0.08, 1.9, 0.08), K.WOOD, Vector3(sx * 1.05, 0.95, sz * 0.6))
	K.box(n, Vector3(2.2, 0.08, 1.3), K.WOOD, Vector3(0, 1.9, 0))
	K.box(n, Vector3(2.15, 1.2, 0.02), K.mat(Color("#c8b48a"), 0.9, 0.0, 0.75), Vector3(0, 1.3, -0.62))
	return n


static func desk(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(1.8, 0.08, 0.8), K.WOOD, Vector3(0, 0.82, 0))
	for sx in [-1, 1]:
		K.box(n, Vector3(0.1, 0.8, 0.7), K.WOOD, Vector3(sx * 0.8, 0.4, 0))
	K.collider(n, Vector3(1.8, 0.9, 0.8), Vector3(0, 0.45, 0))
	for k in 3:
		K.box(n, Vector3(0.36, 0.06, 0.26), K.mat(Color("#cbb98f")), Vector3(-0.55, 0.89 + k * 0.065, 0.05), Vector3(0, k * 8, 0))
	K.box(n, Vector3(0.5, 0.02, 0.36), K.mat(Color("#efe6d2")), Vector3(0.1, 0.87, 0.1))
	K.cyl(n, 0.08, 0.1, 0.12, K.ROOF_EDGE, Vector3(0.6, 0.92, -0.15))
	K.light(n, Color("#ffb36b"), 0.6, 3.0, Vector3(0.6, 1.2, -0.15))
	K.box(n, Vector3(0.7, 0.45, 0.4), K.WOOD, Vector3(0, 0.22, 0.75))
	return n


static func shrine(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.solid(n, Vector3(2.4, 0.95, 0.8), K.LACQUER, Vector3(0, 0.475, 0))
	K.box(n, Vector3(2.5, 0.08, 0.9), K.WOOD, Vector3(0, 0.98, 0))
	K.box(n, Vector3(1.0, 1.1, 0.5), K.LACQUER, Vector3(0, 1.55, -0.1))
	K.box(n, Vector3(0.8, 0.9, 0.02), K.mat(Color("#1f1a16")), Vector3(0, 1.55, 0.16))
	K.box(n, Vector3(0.3, 0.6, 0.06), K.mat(K.GOLD, 0.4), Vector3(0, 1.5, 0.12))
	K.prism(n, Vector3(0.7, 0.25, 1.2), K.ROOF, Vector3(0, 2.22, -0.1), Vector3(0, 90, 0))
	K.cyl(n, 0.16, 0.2, 0.18, K.mat(Color("#6c5a3a"), 0.4), Vector3(0, 1.11, 0.2))
	for sx in [-1, 1]:
		K.cyl(n, 0.04, 0.04, 0.24, K.mat(Color("#e8dcc0")), Vector3(sx * 0.6, 1.14, 0.2))
		K.sphere(n, 0.03, K.mat(Color("#ffb34a"), 0.5, 4.0), Vector3(sx * 0.6, 1.29, 0.2))
		K.light(n, Color("#ffb36b"), 0.5, 2.5, Vector3(sx * 0.6, 1.4, 0.3))
	K.box(n, Vector3(1.4, 0.5, 0.03), K.CINNABAR, Vector3(0, 2.6, -0.32))
	return n


static func workbench(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.solid(n, Vector3(2.0, 0.85, 0.9), K.WOOD_LIGHT, Vector3(0, 0.425, 0))
	K.box(n, Vector3(2.1, 0.1, 1.0), K.WOOD, Vector3(0, 0.9, 0))
	K.box(n, Vector3(0.7, 0.04, 0.16), K.mat(Color("#9aa0a6"), 0.3), Vector3(-0.4, 0.98, 0.1), Vector3(0, 20, 0))
	K.box(n, Vector3(0.08, 0.08, 0.5), K.WOOD, Vector3(0.5, 0.99, 0.0))
	K.box(n, Vector3(0.2, 0.1, 0.12), K.mat(Color("#55595e"), 0.3), Vector3(0.5, 1.02, 0.25))
	K.box(n, Vector3(0.36, 0.2, 0.26), K.ROOF_EDGE, Vector3(0.75, 1.05, -0.25))
	return n


static func cabinet(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.solid(n, Vector3(1.4, 2.0, 0.6), K.WOOD, Vector3(0, 1.0, 0))
	for k in 3:
		K.box(n, Vector3(1.25, 0.55, 0.04), K.WOOD_LIGHT, Vector3(0, 0.4 + k * 0.62, 0.3))
		K.sphere(n, 0.035, K.mat(K.GOLD, 0.4), Vector3(0, 0.4 + k * 0.62, 0.33))
	return n


## 菜畦一块，作物按种类和长势画出来。
static func garden_plot(parent: Node3D, pos: Vector3, crop: String, growth: float, dry: bool) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(1.6, 0.18, 1.6), K.WOOD, Vector3(0, 0.09, 0))
	K.box(n, Vector3(1.45, 0.2, 1.45), K.mat(K.EARTH.darkened(0.25 if not dry else 0.0)), Vector3(0, 0.12, 0))
	if crop == "":
		for k in 3:
			K.box(n, Vector3(1.3, 0.04, 0.12), K.SNOW, Vector3(0, 0.23, -0.45 + k * 0.45))
		return n
	var g := clampf(growth, 0.15, 1.0)
	for ix in 3:
		for iz in 3:
			var p := Vector3(-0.45 + ix * 0.45, 0.22, -0.45 + iz * 0.45)
			match crop:
				"cabbage":
					K.sphere(n, 0.17 * g, K.mat(Color("#a9c98a")), p + Vector3(0, 0.12 * g, 0), Vector3(1, 0.8, 1))
				"radish":
					K.cyl(n, 0.0, 0.12 * g, 0.35 * g, K.LEAF, p + Vector3(0, 0.17 * g, 0))
					if g >= 1.0:
						K.sphere(n, 0.08, K.mat(Color("#f2efe8")), p + Vector3(0, 0.03, 0))
				"chive":
					for t in 3:
						K.box(n, Vector3(0.02, 0.4 * g, 0.02), K.LEAF, p + Vector3(-0.05 + t * 0.05, 0.2 * g, 0), Vector3(0, 0, -12 + t * 12))
				"lingzhi":
					K.cyl(n, 0.025, 0.03, 0.18 * g, K.WOOD_LIGHT, p + Vector3(0, 0.09 * g, 0))
					K.sphere(n, 0.12 * g, K.mat(Color("#8a3b22"), 0.3), p + Vector3(0, 0.18 * g, 0), Vector3(1, 0.4, 1), true)
	return n


static func plum_tree(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	var bark := K.mat(Color("#3a2e27"))
	K.cyl(n, 0.12, 0.2, 2.2, bark, Vector3(0, 1.1, 0), Vector3(0, 0, 6))
	var branches := [[Vector3(-0.5, 2.3, 0.1), Vector3(0, 0, 40)], [Vector3(0.6, 2.5, -0.1), Vector3(0, 0, -45)], [Vector3(0.1, 2.9, 0.3), Vector3(20, 0, 5)], [Vector3(-0.2, 2.7, -0.5), Vector3(-35, 0, 15)]]
	for b in branches:
		K.cyl(n, 0.04, 0.08, 1.4, bark, b[0], b[1])
	var blossom := K.mat(Color("#d9536a"), 0.6, 0.15)
	var snow := K.mat(K.SNOW)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 70:
		var p := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(2.0, 3.6), rng.randf_range(-1.0, 1.0))
		K.sphere(n, rng.randf_range(0.05, 0.09), blossom if k % 4 != 0 else snow, p)
	K.collider(n, Vector3(0.5, 2.0, 0.5), Vector3(0, 1.0, 0))
	return n


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
	K.cyl(n, 0.12, 0.16, 0.9, K.STONE, Vector3(0, 0.45, 0), Vector3.ZERO, 6)
	K.box(n, Vector3(0.42, 0.34, 0.42), K.STONE, Vector3(0, 1.07, 0))
	K.box(n, Vector3(0.24, 0.2, 0.44), K.mat(Color("#ffb36b"), 0.5, 1.2), Vector3(0, 1.07, 0))
	K.cyl(n, 0.0, 0.42, 0.3, K.STONE_DARK, Vector3(0, 1.39, 0), Vector3.ZERO, 6)
	return n


# ---------- 守具（摆在门外街上） ----------

static func device(parent: Node3D, id: String, pos: Vector3, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + index
	match id:
		"peach_stake":
			for k in 6:
				var p := pos + Vector3(-1.5 + k * 0.6, 0, 0)
				K.cyl(parent, 0.07, 0.08, 0.9, K.mat(Color("#c79a6a")), p + Vector3(0, 0.45, 0), Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)), 6)
				K.cyl(parent, 0.0, 0.07, 0.25, K.mat(Color("#e0c19b")), p + Vector3(0, 1.02, 0), Vector3.ZERO, 6)
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
			for k in 4:
				K.box(parent, Vector3(2.5, 0.07, 0.07), K.mat(Color("#c6a06a")), pos + Vector3(0, 0.35 + k * 0.28, 0))
			for x in [-1.1, 0.0, 1.1]:
				K.box(parent, Vector3(0.07, 1.1, 0.07), K.mat(Color("#c6a06a")), pos + Vector3(x, 0.78, 0))
		"caltrop_field":
			for k in 26:
				var p := pos + Vector3(rng.randf_range(-2.0, 2.0), 0.06, rng.randf_range(-0.6, 0.6))
				K.cyl(parent, 0.0, 0.06, 0.12, K.mat(Color("#3d4146"), 0.4), p, Vector3(rng.randf_range(0, 90), rng.randf_range(0, 360), 0), 3)
		"rice_scatter":
			for k in 60:
				var p := pos + Vector3(rng.randf_range(-1.8, 1.8), 0.02, rng.randf_range(-0.5, 0.5))
				K.box(parent, Vector3(0.04, 0.02, 0.07), K.mat(Color("#f4f0e2")), p, Vector3(0, rng.randf_range(0, 180), 0))
		"blood_sill":
			K.box(parent, Vector3(2.4, 0.02, 0.6), K.mat(Color("#4a0f0f"), 0.3), pos + Vector3(0, 0.01, 0))
		"talisman_wall":
			for k in 9:
				var a := -60.0 + k * 15.0
				var p := pos + Vector3(sin(deg_to_rad(a)) * 2.0, 1.6 + 0.25 * sin(k * 1.3), cos(deg_to_rad(a)) * 0.6)
				K.box(parent, Vector3(0.18, 0.4, 0.01), K.mat(K.PAPER, 0.8, 0.8), p, Vector3(0, a, rng.randf_range(-8, 8)))
		"ink_line":
			for k in 4:
				K.box(parent, Vector3(3.0, 0.015, 0.015), K.mat(Color("#111111")), pos + Vector3(0, 0.5 + k * 0.6, 0))
		"bagua_mirror":
			var m := K.cyl(parent, 0.32, 0.32, 0.06, K.mat(Color("#d9c27a"), 0.2, 0.6), pos, Vector3(90, 0, 0), 8)
			K.cyl(m, 0.24, 0.24, 0.07, K.mat(Color("#cfd8dc"), 0.05, 0.4), Vector3.ZERO, Vector3.ZERO, 8)


# ---------- 院中陈设（让院子有人住过的样子） ----------

static func stone_table(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.cyl(n, 0.62, 0.62, 0.12, K.STONE, Vector3(0, 0.78, 0), Vector3.ZERO, 16)
	K.cyl(n, 0.22, 0.3, 0.72, K.STONE_DARK, Vector3(0, 0.36, 0), Vector3.ZERO, 10)
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.05
		K.cyl(n, 0.2, 0.24, 0.45, K.STONE, p + Vector3(0, 0.225, 0), Vector3.ZERO, 10)
	K.collider(n, Vector3(1.3, 0.85, 1.3), Vector3(0, 0.42, 0))
	K.cyl(n, 0.06, 0.07, 0.12, K.mat(Color("#e8e2d2"), 0.3), Vector3(0.2, 0.9, 0.1))
	return n


static func clay_jar(parent: Node3D, pos: Vector3, s := 1.0) -> Node3D:
	var n := K.node(parent, pos)
	K.sphere(n, 0.38 * s, K.mat(Color("#5a3d2b"), 0.35), Vector3(0, 0.38 * s, 0), Vector3(1, 1.1, 1))
	K.cyl(n, 0.2 * s, 0.24 * s, 0.14 * s, K.mat(Color("#4a3224"), 0.35), Vector3(0, 0.8 * s, 0))
	K.collider(n, Vector3(0.7, 0.8, 0.7) * s, Vector3(0, 0.4 * s, 0))
	return n


static func potted_bamboo(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.cyl(n, 0.32, 0.24, 0.5, K.mat(Color("#6b4a36"), 0.6), Vector3(0, 0.25, 0), Vector3.ZERO, 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100 + pos.z)
	for k in 5:
		var off := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var h := rng.randf_range(1.6, 2.4)
		var tilt := Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		K.cyl(n, 0.025, 0.03, h, K.mat(Color("#6f8f45")), off + Vector3(0, 0.5 + h / 2.0, 0), tilt, 6)
		for j in 4:
			var lp := off + Vector3(rng.randf_range(-0.25, 0.25), 0.9 + h * (0.4 + j * 0.15), rng.randf_range(-0.25, 0.25))
			K.box(n, Vector3(0.28, 0.01, 0.06), K.mat(Color("#7aa04e")), lp, Vector3(0, rng.randf_range(0, 180), rng.randf_range(-30, 30)))
	K.collider(n, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0))
	return n


static func laundry(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var n := K.node(parent)
	for p in [a, b]:
		K.cyl(n, 0.04, 0.05, 2.0, K.WOOD, p + Vector3(0, 1.0, 0), Vector3.ZERO, 6)
	var mid := (a + b) / 2.0
	var length := a.distance_to(b)
	K.cyl(n, 0.015, 0.015, length, K.WOOD_LIGHT, mid + Vector3(0, 1.9, 0), Vector3(0, 0, 90), 4)
	var colors := [Color("#3f5a7a"), Color("#d8d0bd"), Color("#7a3a2e")]
	for k in 3:
		var p := a.lerp(b, 0.25 + k * 0.25) + Vector3(0, 1.45, 0)
		K.box(n, Vector3(0.55, 0.85, 0.02), K.mat(colors[k], 0.95), p, Vector3(0, 0, randf_range(-3, 3)))
	return n


## 灶房柱上挂的辣椒串、蒜辫。
static func hanging_produce(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	for k in 9:
		K.cyl(n, 0.0, 0.04, 0.13, K.mat(Color("#b52a1e"), 0.5), Vector3(0.05 * (k % 2), -k * 0.1, 0), Vector3(180, 0, 0), 5)
	for k in 6:
		K.sphere(n, 0.06, K.mat(Color("#efe8d6")), Vector3(0.35, -k * 0.11, 0.02))
	return n


static func basket(parent: Node3D, pos: Vector3, filled: Color) -> Node3D:
	var n := K.node(parent, pos)
	K.cyl(n, 0.32, 0.24, 0.3, K.mat(Color("#a2804d")), Vector3(0, 0.15, 0), Vector3.ZERO, 10)
	K.sphere(n, 0.27, K.mat(filled), Vector3(0, 0.28, 0), Vector3(1, 0.35, 1), true)
	return n


## 山水挂轴：挂在墙上，画心是几笔远山。
static func scroll_painting(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(0.7, 1.5, 0.02), K.mat(Color("#cdb98d")), Vector3.ZERO)
	K.box(n, Vector3(0.58, 1.2, 0.022), K.mat(Color("#ede5d1")), Vector3(0, 0.02, 0))
	for k in 3:
		K.prism(n, Vector3(0.3 - k * 0.05, 0.22 + k * 0.08, 0.005), K.mat(Color(0.25, 0.25, 0.27, 0.5 + k * 0.15)), Vector3(-0.1 + k * 0.12, -0.25 + k * 0.05, 0.014))
	K.cyl(n, 0.03, 0.03, 0.8, K.WOOD, Vector3(0, -0.77, 0.01), Vector3(0, 0, 90), 6)
	return n


static func bookshelf(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.solid(n, Vector3(1.2, 2.0, 0.4), K.WOOD, Vector3(0, 1.0, 0))
	var colors := [Color("#b9a27a"), Color("#8a6a4a"), Color("#c9b48a"), Color("#6e5a44")]
	for r in 4:
		K.box(n, Vector3(1.1, 0.04, 0.38), K.WOOD_LIGHT, Vector3(0, 0.3 + r * 0.45, 0.02))
		for c in 6:
			K.box(n, Vector3(0.14, 0.28, 0.28), K.mat(colors[(r + c) % 4]), Vector3(-0.42 + c * 0.17, 0.46 + r * 0.45, 0.04))
	return n


## 廊柱上的楹联。
static func couplet(parent: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	K.box(n, Vector3(0.2, 1.6, 0.02), K.mat(Color("#9e2a22")), Vector3.ZERO)
	for k in 5:
		K.box(n, Vector3(0.1, 0.1, 0.025), K.mat(Color("#d9b65a"), 0.5), Vector3(0, 0.6 - k * 0.3, 0.002))
	return n


## 条案上的供奉：牌位、香炉、一对蜡烛。y 是条案面高。
static func altar_items(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	K.box(n, Vector3(0.36, 0.5, 0.2), K.LACQUER, Vector3(0, 0.25, -0.02))
	K.box(n, Vector3(0.2, 0.36, 0.03), K.mat(K.GOLD, 0.4), Vector3(0, 0.26, 0.085))
	K.cyl(n, 0.08, 0.1, 0.1, K.mat(Color("#6c5a3a"), 0.4), Vector3(0, 0.05, 0.11))
	for sx in [-1, 1]:
		K.cyl(n, 0.025, 0.025, 0.2, K.mat(Color("#e8dcc0")), Vector3(sx * 0.5, 0.1, 0.05))
		K.sphere(n, 0.022, K.mat(Color("#ffb34a"), 0.5, 4.0), Vector3(sx * 0.5, 0.22, 0.05))
		K.light(n, Color("#ffb36b"), 0.5, 2.5, Vector3(sx * 0.5, 0.4, 0.2))
	return n


## 书案上的书和油灯。y 是桌面高。
static func desk_items(parent: Node3D, pos: Vector3) -> Node3D:
	var n := K.node(parent, pos)
	for k in 3:
		K.box(n, Vector3(0.28, 0.05, 0.2), K.mat(Color("#cbb98f")), Vector3(-0.2, 0.025 + k * 0.052, 0.05), Vector3(0, k * 8, 0))
	K.box(n, Vector3(0.36, 0.015, 0.26), K.mat(Color("#efe6d2")), Vector3(0.12, 0.008, -0.05))
	K.cyl(n, 0.05, 0.07, 0.09, K.ROOF_EDGE, Vector3(0.25, 0.045, 0.2))
	K.light(n, Color("#ffb36b"), 0.6, 3.0, Vector3(0.25, 0.3, 0.2))
	return n
