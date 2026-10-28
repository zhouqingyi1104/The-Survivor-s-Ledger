extends RefCounted
## 装修只生成视觉网格；不含碰撞、导航、交互或运行时灯光。
const K = preload("res://scripts/world/kit.gd")
const Decoration = preload("res://scripts/core/home_decoration.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")


static func sync(root: Node3D, run: Dictionary) -> void:
	var state := []
	for category in ["wall", "floor", "lamps", "plants"]:
		state.append(Decoration.selected(run, category))
	var expanded := Expansion.complete(run)
	var key := "|".join(state) + ("|expanded" if expanded else "|original")
	if root.get_meta("decoration_key", "") == key:
		return
	root.set_meta("decoration_key", key)
	K.clear(root)
	if state[0] != "original":
		_wall(root, str(state[0]), expanded)
	if state[1] != "original":
		_floor(root, str(state[1]))
	if state[2] != "original":
		_lamps(root, str(state[2]))
	if state[3] != "original":
		_plants(root, str(state[3]))


static func _wall(root: Node3D, choice: String, expanded: bool) -> void:
	var color := Color("#b89179") if choice == "warm" else Color("#79878b")
	# 仅覆盖墙体内侧，门窗、墙帽及原碰撞保持不变。
	K.box(root, Vector3(0.025, 2.4, 14.8), color, Vector3(-10.01, 1.7, -0.6))
	if expanded:
		K.box(root, Vector3(0.025, 2.4, 11.0), color, Vector3(10.01, 1.7, -2.5))
		K.box(root, Vector3(0.025, 2.4, 1.0), color, Vector3(10.01, 1.7, 6.5))
	else:
		K.box(root, Vector3(0.025, 2.4, 14.8), color, Vector3(10.01, 1.7, -0.6))
	K.box(root, Vector3(20.0, 2.8, 0.025), color, Vector3(0, 1.9, -8.01))
	# 窗口附近只铺上下边，留出格窗。
	K.box(root, Vector3(8.1, 2.4, 0.025), color, Vector3(-6.05, 1.7, 6.81))
	for span in [[2.0, 4.8], [6.4, 10.0]]:
		K.box(root, Vector3(span[1] - span[0], 2.4, 0.025), color, Vector3((span[0] + span[1]) / 2.0, 1.7, 6.81))
	for y in [0.75, 2.75]:
		K.box(root, Vector3(1.6, 0.5, 0.025), color, Vector3(5.6, y, 6.81))


static func _floor(root: Node3D, choice: String) -> void:
	var color := Color("#9c6954") if choice == "brick" else Color("#626f73")
	var seam := color.darkened(0.3)
	# 位于原铺石上方，碰撞仍由原地面提供。
	K.box(root, Vector3(19.35, 0.02, 14.35), color, Vector3(0, 0.095, -0.5))
	for i in range(-9, 10):
		K.box(root, Vector3(0.025, 0.005, 14.3), seam, Vector3(float(i), 0.108, -0.5))
	for i in range(-7, 7):
		K.box(root, Vector3(19.3, 0.005, 0.025), seam, Vector3(0, 0.108, float(i)))


static func _lamps(root: Node3D, choice: String) -> void:
	var color := Color("#bc392d") if choice == "red" else Color("#e3b252")
	for side in [-1.0, 1.0]:
		var post := Vector3(side * 6.1, 0, 4.8)
		K.cyl(root, 0.07, 0.08, 3.5, K.WOOD, post + Vector3(0, 1.75, 0))
		K.box(root, Vector3(0.8, 0.08, 0.08), K.WOOD, post + Vector3(-side * 0.36, 3.42, 0))
		var p := post + Vector3(-side * 0.7, 2.9, 0)
		K.cyl(root, 0.025, 0.025, 0.45, K.WOOD, p + Vector3(0, 0.38, 0))
		K.sphere(root, 0.26, K.mat(color, 0.8, 0.25), p, Vector3(1, 1.15, 1))
		K.cyl(root, 0.13, 0.13, 0.06, K.ROOF_EDGE, p + Vector3(0, 0.29, 0))
		K.cyl(root, 0.13, 0.13, 0.06, K.ROOF_EDGE, p - Vector3(0, 0.29, 0))


static func _plants(root: Node3D, choice: String) -> void:
	for p in [Vector3(-4.7, 0, 2.9), Vector3(5.5, 0, 4.6)]:
		K.cyl(root, 0.32, 0.24, 0.48, K.mat(Color("#7c5943")), p + Vector3(0, 0.24, 0))
		if choice == "bamboo":
			for j in range(3):
				var dx := (j - 1) * 0.13
				K.cyl(root, 0.025, 0.035, 1.35, K.mat(Color("#648447")), p + Vector3(dx, 1.15, 0))
				for k in range(3):
					K.box(root, Vector3(0.38, 0.025, 0.08), K.mat(Color("#80a563")), p + Vector3(dx, 0.95 + k * 0.3, 0), Vector3(0, j * 55, 20 - j * 20))
		else:
			K.cyl(root, 0.06, 0.09, 1.1, K.WOOD, p + Vector3(0, 1.0, 0))
			for offset in [Vector3(-0.23, 1.52, 0), Vector3(0.2, 1.7, 0.08), Vector3(0, 1.9, -0.05)]:
				K.sphere(root, 0.23, K.mat(Color("#d98491")), p + offset)
