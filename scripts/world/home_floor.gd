extends RefCounted
## C5 的独立室内空间。房间位于院外，楼层切换由界面显式完成。
const K = preload("res://scripts/world/kit.gd")
const HomeHouse = preload("res://scripts/world/home_house.gd")
const Craft = preload("res://scripts/world/building_craft.gd")
const Fittings = preload("res://scripts/world/floor_fittings.gd")
const Figure = preload("res://scripts/world/character.gd")

const ORIGINS := {"cellar": Vector3(-40, 0, 0), "attic": Vector3(40, 0, 0), "guest_zhou": Vector3(0, 0, -40)}
const SIZE := Vector2(8.0, 7.0)
## 北侧凸出采光窗龛，南侧只在楼梯口伸出平台。原有可摆家具的中心区域包含在轮廓内。
const ATTIC_OUTLINE: Array[Vector2] = [
	Vector2(-4.15, -3.5), Vector2(1.25, -3.5), Vector2(2.15, -5.3),
	Vector2(3.8, -5.3), Vector2(4.9, -3.55), Vector2(4.9, -1.55),
	Vector2(4.0, -0.8), Vector2(4.0, 2.75), Vector2(1.55, 2.75),
	Vector2(1.55, 3.85), Vector2(-1.55, 3.85), Vector2(-1.55, 2.75),
	Vector2(-3.2, 2.75), Vector2(-4.15, 1.65),
]

static func build(parent: Node3D, floor_id: String) -> Dictionary:
	if floor_id == "guest_zhou":
		return _build_guest(parent)
	var origin: Vector3 = ORIGINS[floor_id]
	var root := K.node(parent, origin, Vector3.ZERO, "floor_" + floor_id)
	var is_cellar := floor_id == "cellar"
	_backdrop(root, Color("#181b1e") if is_cellar else Color("#28211c"), 0.0 if is_cellar else -1.45)
	var lamp: Light3D
	if is_cellar:
		var ceiling := OmniLight3D.new()
		ceiling.position = Vector3(-1.87, 3.1, 0.35)
		ceiling.shadow_enabled = true
		ceiling.shadow_blur = 1.6
		ceiling.omni_range = 12.0
		lamp = ceiling
	else:
		# 从纸窗朝木地板投一片宽光，一张影图即可留住窗边、梁下的明暗。
		var window_light := SpotLight3D.new()
		window_light.position = Vector3(2.86, 2.75, -4.40)
		window_light.basis = Basis.looking_at(Vector3(-2.5, -2.75, 4.0), Vector3.UP)
		window_light.spot_range = 12.0
		window_light.spot_angle = 72.0
		window_light.spot_angle_attenuation = 0.55
		window_light.shadow_enabled = true
		window_light.shadow_blur = 1.7
		lamp = window_light
	lamp.light_color = Color("#fcdfba") if is_cellar else Color("#ffe9c4")
	lamp.light_energy = 1.7 if is_cellar else 2.4
	root.add_child(lamp)
	if is_cellar:
		Fittings.stone_floor(root)
		for x in [-4.0, 4.0]:
			K.collider(root, Vector3(0.24, 1.35, 7), Vector3(x, 0.675, 0))
			var side := K.node(root, Vector3(x, 0, 0), Vector3(0, 90, 0))
			Craft.courses(side, 7.0, 1.35, 0.24, true)
			K.box(side, Vector3(7.08, 0.09, 0.29), K.STONE_DARK, Vector3(0, 1.36, 0))
		for z in [-3.5, 3.5]:
			K.collider(root, Vector3(8, 1.35, 0.24), Vector3(0, 0.675, z))
		Craft.courses(K.node(root, Vector3(0, 0, 3.5)), 8.0, 1.35, 0.24, true)
		# 厚后墙断开 1.6 米做灯龛，两侧的立柱落在整石柱础上。
		for extents: Vector2 in [Vector2(-4.0, 1.39), Vector2(2.95, 4.0)]:
			var mid := (extents.x+extents.y)*0.5
			Craft.courses(K.node(root, Vector3(mid, 0, -3.5)), extents.y-extents.x, 2.23, 0.28, true)
		Fittings.cellar_stores(root)
		for x in [-3.64, -0.84, 3.64]:
			K.box(root, Vector3(0.31, 0.22, 0.30), K.STONE_DARK, Vector3(x, 0.18, -3.24))
			K.box(root, Vector3(0.17, 1.98, 0.20), K.WOOD, Vector3(x, 1.22, -3.24))
			var direction := 1.0 if x < 0 else -1.0
			K.box(root, Vector3(0.12, 0.61, 0.16), K.WOOD_LIGHT, Vector3(x+direction*0.18, 1.99, -3.24), Vector3(0, 0, -direction*38))
		K.box(root, Vector3(8.05, 0.22, 0.31), K.WOOD, Vector3(0, 2.27, -3.35))
	else:
		_attic_shell(root)
	HomeHouse.finish_joinery(root)
	K.merge_static(root, [])
	var exit := K.node(root, Vector3(0, 0, 2.85), Vector3.ZERO, "floor_exit")
	Fittings.stairs(exit, is_cellar)
	K.text3d(exit, "回宅院", Vector3(0, 1.0, 0), 48, Color("#f2d89c"))
	K.collider(exit, Vector3(1.2, 0.5, 0.6), Vector3(0, 0.25, 0), {"spot": "floor_exit"})
	var use := K.node(root, Vector3(0, 0, -3.0), Vector3.ZERO, "floor_use")
	Fittings.desk(use, is_cellar)
	K.collider(use, Vector3(1.2, 0.9, 0.45), Vector3(0, 0.45, 0), {"spot": "floor_use"})
	K.text3d(use, "整理台", Vector3(0, 1.35, 0), 48, Color("#f2d89c"))
	# 拾取高亮沿设备自身的层级查找网格，整理台和楼梯各自合批。
	for fixture: Node3D in [exit, use]:
		HomeHouse.finish_joinery(fixture)
		K.merge_static(fixture, [])
	return {"root": root, "floor_exit": exit, "floor_use": use}


static func _backdrop(root: Node3D, color: Color, bottom := 0.0) -> void:
	# 俯视时室外不应透过房间轮廓：暗色背景承托剖面，不参与碰撞与导航。
	var backdrop := StandardMaterial3D.new()
	backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.albedo_color = color
	K.box(root, Vector3(52, 0.02, 52), backdrop, Vector3(0, bottom + 0.005, 0))
	# 近看时剖面外延续暗色底台。光照和雾不影响这个展示背景。
	backdrop.disable_fog = true
	var surround := CylinderMesh.new()
	surround.cap_top = false
	surround.cap_bottom = false
	surround.top_radius = 23
	surround.bottom_radius = 23
	surround.height = 38
	surround.rings = 1
	backdrop.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surround_mesh := K._mesh(root, surround, backdrop, Vector3(0, 12, 0))
	surround_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _attic_shell(root: Node3D) -> void:
	# 向南突出的一跨留出梯井，铺板只到承口；门槛、室内活动边界仍按整层轮廓。
	var platform := PackedVector2Array(ATTIC_OUTLINE)
	var stair_opening := [Vector2(0.70, 3.85), Vector2(0.70, 2.37), Vector2(-0.70, 2.37), Vector2(-0.70, 3.85)]
	for i in stair_opening.size():
		platform.insert(10 + i, stair_opening[i])
	HomeHouse.build_platform(root, platform, false, Fittings.oiled_boards())
	for i in ATTIC_OUTLINE.size():
		var a := ATTIC_OUTLINE[i]
		var b := ATTIC_OUTLINE[(i + 1) % ATTIC_OUTLINE.size()]
		var mid := (a + b) * 0.5
		var width := a.distance_to(b)
		var wall := K.node(root, Vector3(mid.x, 0, mid.y), Vector3(0, -rad_to_deg((b - a).angle()), 0))
		var window_bay := i >= 1 and i <= 3
		var height := 0.78
		if i == 0:
			height = 2.47
		elif i == ATTIC_OUTLINE.size() - 1:
			height = 1.85
		K.solid(wall, Vector3(width, height, 0.18), HomeHouse.plaster(), Vector3(0, height * 0.5, 0))
		if height > 1.0 or window_bay:
			HomeHouse.wall_base(wall, width, 0.62, false)
		K.box(wall, Vector3(width, 0.09, 0.25), K.WOOD, Vector3(0, height + 0.04, 0))
		if window_bay:
			# 三扇纸窗沿折面接合，窗台包住窗龛，人在楼梯口就能辨出坐向。
			HomeHouse.paper_window(wall, Vector3(0, 1.55, 0), width - 0.08, 1.2)
			for share in [-0.48, 0.0, 0.48]:
				K.box(wall, Vector3(0.075, 1.45, 0.13), K.WOOD, Vector3(width * share, 1.58, 0))
			for y in [1.06, 1.77, 2.2]:
				K.box(wall, Vector3(width, 0.075, 0.13), K.WOOD, Vector3(0, y, 0))
			Fittings.rolled_blind(wall, width, [0.48, 0.26, 0.36][i-1])
			K.box(wall, Vector3(width + 0.12, 0.12, 0.45), K.ROOF_EDGE, Vector3(0, 2.33, 0))
	# 正梁偏向后墙，人物与整理台在前方始终可见。
	for x in [-3.7, 0.95]:
		K.box(root, Vector3(0.18, 2.48, 0.18), K.WOOD, Vector3(x, 1.24, -3.43))
	var ridge_y := 3.55
	var rise := ridge_y - 2.48
	K.prism(root, Vector3(4.73, rise, 0.16), HomeHouse.plaster(), Vector3(-1.375, 2.48 + rise * 0.5, -3.49))
	for z in [-3.51, -2.75]:
		K.box(root, Vector3(4.94, 0.15, 0.16), K.WOOD, Vector3(-1.375, 2.48, z))
		K.box(root, Vector3(0.13, rise, 0.14), K.WOOD, Vector3(-1.375, 2.48 + rise * 0.5, z))
		for side in [-1.0, 1.0]:
			var half_span := 2.55
			K.box(root, Vector3(Vector2(half_span, rise).length(), 0.15, 0.18), K.WOOD,
				Vector3(-1.375 + side * half_span * 0.5, ridge_y - rise * 0.5, z),
				Vector3(0, 0, -side * rad_to_deg(atan2(rise, half_span))))
	for x in [-3.85, -1.375, 1.10]:
		K.box(root, Vector3(0.18, 0.14, 1.12), K.WOOD, Vector3(x, ridge_y if x == -1.375 else 2.48, -3.13))
	# 窗台兼作坐榻，设在屋后伸出的部分，留出原来的家具位置。
	var seat := K.node(root, Vector3(2.98, 0, ATTIC_OUTLINE[2].y + 0.32))
	Fittings.window_seat(seat)
	Fittings.attic_shelves(root)
	var reflected := K.light(root, Color("#ffebcf"), 1.35, 3.6, Vector3(2.72, 2.30, -3.72))
	reflected.light_specular = 0.28
	HomeHouse._woven_mat(root, Vector3(2.61, 0.146, -3.70), 1.65)


## 独立访客客厅；没有整理台，自家家具/库存不属于此空间。
static func _build_guest(parent: Node3D) -> Dictionary:
	var root := K.node(parent, ORIGINS.guest_zhou, Vector3.ZERO, "floor_guest_zhou")
	_backdrop(root, Color("#262522"))
	HomeHouse.build_platform(root, PackedVector2Array([Vector2(-4, -3.5), Vector2(4, -3.5), Vector2(4, 3.5), Vector2(-4, 3.5)]), false, Fittings.oiled_boards())
	for x in [-3.76, 3.76]:
		for z in [-3.25, 3.25]:
			K.box(root, Vector3(0.16, 1.53, 0.16), K.WOOD, Vector3(x, 0.80, z))
	for z in [-3.5, 3.5]:
		K.box(root, Vector3(8.1, 0.12, 0.28), K.WOOD, Vector3(0, 1.38, z))
	for x in [-4.0, 4.0]:
		K.solid(root, Vector3(0.24, 1.35, 7), HomeHouse.plaster(), Vector3(x, 0.675, 0))
	for z in [-3.5, 3.5]:
		K.solid(root, Vector3(8, 1.35, 0.24), HomeHouse.plaster(), Vector3(0, 0.675, z))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.75, 2.85, -0.68)
	lamp.shadow_enabled = true
	lamp.shadow_blur = 1.6
	lamp.light_color = Color("#ffe0aa")
	lamp.light_energy = 1.7
	lamp.omni_range = 12.0
	root.add_child(lamp)
	# 访客在窗边落座；案、茶盏和书架都是布景，保留老周与修墙的交互。
	Fittings.guest_tea(root)
	HomeHouse.paper_window(root, Vector3(-2.4, 1.15, -3.27), 1.64, 1.0)
	HomeHouse.finish_joinery(root)
	K.merge_static(root, [])
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
	if floor_id == "attic":
		return Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), ATTIC_OUTLINE)
	return absf(q.x) < 3.8 and absf(q.z) < 3.3
