extends RefCounted
## C5 的独立室内空间。房间位于院外，楼层切换由界面显式完成。
const K = preload("res://scripts/world/kit.gd")
const Figure = preload("res://scripts/world/character.gd")

const ORIGINS := {"cellar": Vector3(-40, 0, 0), "attic": Vector3(40, 0, 0), "guest_zhou": Vector3(0, 0, -40)}
const SIZE := Vector2(8.0, 7.0)

static func build(parent: Node3D, floor_id: String) -> Dictionary:
	if floor_id == "guest_zhou":
		return _build_guest(parent)
	var origin: Vector3 = ORIGINS[floor_id]
	var root := K.node(parent, origin, Vector3.ZERO, "floor_" + floor_id)
	var is_cellar := floor_id == "cellar"
	# 俯视时室外不应透过房间轮廓：暗色背景承托剖面，不参与碰撞与导航。
	var backdrop := StandardMaterial3D.new()
	backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.albedo_color = Color("#181b1e") if is_cellar else Color("#28211c")
	K.box(root, Vector3(52, 0.02, 52), backdrop, Vector3(0, 0.005, 0))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.0, 0)
	lamp.light_color = Color("#ffe0aa")
	lamp.light_energy = 1.7
	lamp.omni_range = 12.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
	var wall_color: Color = K.STONE_DARK if is_cellar else K.WOOD
	var floor_color: Color = K.STONE if is_cellar else K.WOOD_LIGHT
	K.box(root, Vector3(8, 0.07, 7), floor_color, Vector3(0, 0.04, 0))
	# 矮墙保留空间边界而不遮挡可旋转的俯视镜头。
	for x in [-4.0, 4.0]:
		K.solid(root, Vector3(0.24, 1.35, 7), wall_color, Vector3(x, 0.675, 0))
	for z in [-3.5, 3.5]:
		K.solid(root, Vector3(8, 1.35, 0.24), wall_color, Vector3(0, 0.675, z))
	if is_cellar:
		K.box(root, Vector3(1.4, 1.1, 0.45), K.WOOD, Vector3(-2.9, 0.55, -3.1))
		K.box(root, Vector3(1.2, 0.08, 0.52), K.WOOD_LIGHT, Vector3(-2.9, 0.9, -3.1))
	else:
		for x in [-3.3, 3.3]:
			K.box(root, Vector3(0.18, 2.5, 0.18), K.WOOD, Vector3(x, 1.25, -3.1))
		K.box(root, Vector3(6.8, 0.18, 0.18), K.WOOD, Vector3(0, 2.45, -3.1))
	var exit := K.node(root, Vector3(0, 0, 2.85), Vector3.ZERO, "floor_exit")
	K.box(exit, Vector3(1.2, 0.12, 0.8), K.WOOD_LIGHT, Vector3(0, 0.12, 0))
	for x in [-0.48, 0.48]:
		K.box(exit, Vector3(0.07, 0.12, 0.7), K.GOLD, Vector3(x, 0.2, 0))
	K.text3d(exit, "回宅院", Vector3(0, 1.0, 0), 48, Color("#f2d89c"))
	K.collider(exit, Vector3(1.2, 0.5, 0.6), Vector3(0, 0.25, 0), {"spot": "floor_exit"})
	var use := K.node(root, Vector3(0, 0, -3.0), Vector3.ZERO, "floor_use")
	K.box(use, Vector3(1.2, 0.8, 0.45), K.WOOD, Vector3(0, 0.4, 0))
	K.box(use, Vector3(1.3, 0.08, 0.5), K.WOOD_LIGHT, Vector3(0, 0.84, 0))
	K.collider(use, Vector3(1.2, 0.9, 0.45), Vector3(0, 0.45, 0), {"spot": "floor_use"})
	K.text3d(use, "整理台", Vector3(0, 1.35, 0), 48, Color("#f2d89c"))
	return {"root": root, "floor_exit": exit, "floor_use": use}


## 独立访客客厅；没有整理台，自家家具/库存不属于此空间。
static func _build_guest(parent: Node3D) -> Dictionary:
	var root := K.node(parent, ORIGINS.guest_zhou, Vector3.ZERO, "floor_guest_zhou")
	var backdrop := StandardMaterial3D.new()
	backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.albedo_color = Color("#262522")
	K.box(root, Vector3(52, 0.02, 52), backdrop, Vector3(0, 0.005, 0))
	K.box(root, Vector3(8, 0.07, 7), K.WOOD_LIGHT, Vector3(0, 0.04, 0))
	for x in [-4.0, 4.0]:
		K.solid(root, Vector3(0.24, 1.35, 7), K.WALL, Vector3(x, 0.675, 0))
	for z in [-3.5, 3.5]:
		K.solid(root, Vector3(8, 1.35, 0.24), K.WALL, Vector3(0, 0.675, z))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3, 0)
	lamp.light_color = Color("#ffe0aa")
	lamp.light_energy = 1.7
	lamp.omni_range = 12.0
	root.add_child(lamp)
	# 摆设仅为客厅背景，不表示可取走的库存。
	K.box(root, Vector3(1.1, 0.5, 0.8), K.WOOD, Vector3(-2.4, 0.25, -2.5))
	K.box(root, Vector3(1.4, 0.12, 0.95), K.WOOD_LIGHT, Vector3(-2.4, 0.55, -2.5))
	for x in [-2.9, -1.9]:
		for z in [-2.8, -2.2]:
			K.box(root, Vector3(0.12, 0.48, 0.12), K.WOOD, Vector3(x, 0.24, z))
	# 一扇纸窗和墙边书架仅作居室陈设，不注册碰撞或拾取。
	K.box(root, Vector3(1.5, 0.8, 0.08), K.WOOD, Vector3(-2.4, 0.94, -3.32))
	K.box(root, Vector3(1.28, 0.6, 0.1), K.PAPER, Vector3(-2.4, 0.94, -3.25))
	for x in [-2.8, -2.4, -2.0]:
		K.box(root, Vector3(0.05, 0.64, 0.12), K.WOOD, Vector3(x, 0.94, -3.18))
	K.box(root, Vector3(1.35, 0.05, 0.12), K.WOOD, Vector3(-2.4, 0.94, -3.18))
	K.box(root, Vector3(0.24, 1.05, 1.2), K.WOOD, Vector3(3.78, 0.58, -0.8))
	for y in [0.32, 0.67, 1.02]:
		K.box(root, Vector3(0.34, 0.06, 1.25), K.WOOD_LIGHT, Vector3(3.65, y, -0.8))
	for z in [-1.15, -0.87, -0.59]:
		K.box(root, Vector3(0.25, 0.22, 0.14), K.CLOTH_BLUE, Vector3(3.57, 0.82, z))
	var repaired := K.node(root, Vector3.ZERO, Vector3.ZERO, "repaired_wall")
	for i in 3:
		K.box(repaired, Vector3(1.5, 0.14, 0.12), K.WOOD_LIGHT, Vector3(2.4, 0.45 + i * 0.25, -3.33))
	repaired.visible = false
	var exit := K.node(root, Vector3(0, 0, 2.85), Vector3.ZERO, "floor_exit")
	K.box(exit, Vector3(1.2, 0.12, 0.8), K.WOOD_LIGHT, Vector3(0, 0.12, 0))
	K.text3d(exit, "回宅院", Vector3(0, 1.0, 0), 48, Color("#f2d89c"))
	K.collider(exit, Vector3(1.2, 0.5, 0.6), Vector3(0, 0.25, 0), {"spot": "floor_exit"})
	var talk := K.node(root, Vector3(0, 0, -2.2), Vector3.ZERO, "guest_talk")
	var zhou := Figure.new()
	talk.add_child(zhou)
	zhou.setup("villager")
	K.collider(talk, Vector3(0.8, 1.8, 0.8), Vector3(0, 0.9, 0), {"spot": "guest_talk"})
	K.text3d(talk, "老周", Vector3(0, 2.2, 0), 48, Color("#f2d89c"))
	return {"root": root, "floor_exit": exit, "guest_talk": talk, "repaired_wall": repaired}

static func spawn(floor_id: String) -> Vector3:
	return ORIGINS.get(floor_id, Vector3.ZERO) + Vector3(0, 0, 1.5)

static func info(floor_id: String, id: String) -> Dictionary:
	var origin: Vector3 = ORIGINS.get(floor_id, Vector3.ZERO)
	if id == "floor_exit":
		return {"name": "返回宅院", "stand": origin + Vector3(0, 0, 1.5), "tag": origin + Vector3(0, 1.4, 2.85)}
	if id == "guest_talk" and floor_id == "guest_zhou":
		return {"name": "老周", "stand": origin + Vector3(0, 0, -1.0), "tag": origin + Vector3(0, 2.2, -2.2)}
	if id == "floor_use":
		if floor_id == "guest_zhou": return {}
		return {"name": "地窖整理台" if floor_id == "cellar" else "阁楼整理台", "stand": origin + Vector3(0, 0, -1.9), "tag": origin + Vector3(0, 1.5, -3.0)}
	return {}

static func contains(floor_id: String, p: Vector3) -> bool:
	if not ORIGINS.has(floor_id):
		return false
	var q: Vector3 = p - ORIGINS[floor_id]
	return absf(q.x) < 3.8 and absf(q.z) < 3.3
