extends RefCounted
## 装修只生成视觉网格；不含碰撞、导航、交互或运行时灯光。
const K = preload("res://scripts/world/kit.gd")
const Arch = preload("res://scripts/world/arch.gd")
const Props = preload("res://scripts/world/props.gd")
const Assets = preload("res://scripts/world/assets.gd")
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
	var color := Arch.HomeHouse.plaster().duplicate() as ShaderMaterial
	color.set_shader_parameter("lime", Color("#b89179") if choice == "warm" else Color("#79878b"))
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
	var stone := Assets.pbr("square_cobblestone", 3.4, Color("#a6b0b3"))
	var brick := Assets.pbr("brick_wall_09", 2.9, Color("#c3a48a"))
	K.box(root, Vector3(19.35, 0.02, 14.35), brick if choice == "brick" else stone, Vector3(0, 0.095, -0.5))


static func _lamps(root: Node3D, choice: String) -> void:
	var color := Color("#bc392d") if choice == "red" else Color("#e3b252")
	for side in [-1.0, 1.0]:
		var post := Vector3(side * 6.1, 0, 4.8)
		K.cyl(root, 0.07, 0.08, 3.5, K.WOOD, post + Vector3(0, 1.75, 0))
		K.box(root, Vector3(0.8, 0.08, 0.08), K.WOOD, post + Vector3(-side * 0.36, 3.42, 0))
		var p := post + Vector3(-side * 0.7, 2.9, 0)
		K.cyl(root, 0.025, 0.025, 0.45, K.WOOD, p + Vector3(0, 0.38, 0))
		var shade := Arch.lantern(root, p)
		# 装修灯帘不贡献局部光源。两款染色保持玩家所选的朱红、暖金。
		shade.light.free()
		shade.mat.albedo_color = color.lightened(0.32)
		shade.mat.emission = color
		shade.mat.emission_energy_multiplier = 0.42


static func _plants(root: Node3D, choice: String) -> void:
	for p in [Vector3(-4.7, 0, 2.9), Vector3(5.5, 0, 4.6)]:
		if choice == "bamboo":
			Props.potted_bamboo(root, p, false)
		else:
			var pot := Props.flowerpot(root, p)
			var trunk := K.node(pot, Vector3.UP * 0.385)
			trunk.scale = Vector3.ONE * 0.53
			Props.plum_tree(trunk, Vector3.ZERO, false)
