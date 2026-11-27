extends RefCounted
## 宅院室内固定陈设。家具使用区仍由楼层的既有拾取体和通道决定。

const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const House = preload("res://scripts/world/home_house.gd")
const Craft = preload("res://scripts/world/building_craft.gd")
const Workshop = preload("res://scripts/world/household_models.gd")
const BOARD := "res://assets/third_party/polyhaven/textures/brown_planks_09/brown_planks_09_"
const STONE := "res://assets/third_party/polyhaven/textures/rock_face_03/rock_face_03_"


static func oiled_boards() -> ShaderMaterial:
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://scripts/world/attic_floorboards.gdshader")
	finish.set_shader_parameter("wood_color", load(BOARD + "diff.jpg"))
	finish.set_shader_parameter("wood_normal", load(BOARD + "nor.jpg"))
	finish.set_shader_parameter("wood_arm", load(BOARD + "arm.jpg"))
	return finish


static func stone_floor(room: Node3D) -> void:
	K.box(room, Vector3(8.04, 0.10, 7.04), Color("#4a4941"), Vector3(0, 0.024, 0))
	var flags := SurfaceTool.new()
	flags.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 长方青石按行错缝，每块取一片连续石皮；细倒角与石灰缝在斜光下才显出厚度。
	var widths := [1.46, 1.08, 1.64, 1.25, 0.99]
	for row in 10:
		var x := -4.0 - 0.48 * (row % 2)
		var col := 0
		while x < 4.0:
			var w: float = widths[(row * 3 + col) % widths.size()]
			var left := maxf(-4.0, x) + 0.008
			var right := minf(4.0, x + w) - 0.008
			if right - left > 0.035:
				var top := -3.5 + row * 0.7 + 0.008
				var bottom := top + 0.683
				var chip := 0.028 + 0.013 * ((row + col * 3) % 4)
				var rim := PackedVector2Array([Vector2(left+chip, top), Vector2(right-0.02, top), Vector2(right, top+0.025),
					Vector2(right, bottom-0.035), Vector2(right-0.031, bottom), Vector2(left+0.018, bottom), Vector2(left, bottom-0.036), Vector2(left, top+chip)])
				var center := Vector2((left + right) * 0.5, (top + bottom) * 0.5)
				var offset := Vector2(col * 0.31 + row * 0.23, row * 0.37 - col * 0.07)
				var tone := 0.82 + 0.038 * ((row * 7 + col * 5) % 6)
				var high := 0.10 + 0.001 * ((col + row) % 3)
				for i in rim.size():
					var j := (i + 1) % rim.size()
					var a := rim[i]
					var b := rim[j]
					var inner_a := a.move_toward(center, 0.016)
					var inner_b := b.move_toward(center, 0.016)
					var normal := Vector3(b.y - a.y, a.distance_to(b), a.x - b.x).normalized()
					for pt: Vector2 in [center, inner_a, inner_b]:
						_flag_vertex(flags, pt, high, Vector3.UP, tone, offset)
					_flag_vertex(flags, inner_a, high, normal, tone, offset)
					_flag_vertex(flags, a, high - 0.015, normal, tone, offset)
					_flag_vertex(flags, b, high - 0.015, normal, tone, offset)
					_flag_vertex(flags, inner_a, high, normal, tone, offset)
					_flag_vertex(flags, b, high - 0.015, normal, tone, offset)
					_flag_vertex(flags, inner_b, high, normal, tone, offset)
			x += w
			col += 1
	flags.generate_tangents()
	flags.index()
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://scripts/world/cellar_flagstone.gdshader")
	finish.set_shader_parameter("stone_color", load(STONE + "diff.jpg"))
	finish.set_shader_parameter("stone_normal", load(STONE + "nor.jpg"))
	finish.set_shader_parameter("stone_arm", load(STONE + "arm.jpg"))
	K._mesh(room, flags.commit(), finish, Vector3.ZERO)


static func _flag_vertex(mesh: SurfaceTool, p: Vector2, height: float, normal: Vector3, tone: float, shift: Vector2) -> void:
	mesh.set_normal(normal)
	mesh.set_color(Color(tone, tone, tone))
	mesh.set_uv(p / 1.85 + shift)
	mesh.add_vertex(Vector3(p.x, height, p.y))


static func cellar_stores(room: Node3D) -> void:
	# 后墙石龛向墙外凹入。砖拱和收口石围住实际的空洞。
	var recess := K.node(room, Vector3(2.17, 0, -3.50))
	Craft.courses(K.node(recess, Vector3(0, 0.81, -0.24)), 1.49, 1.45, 0.13, false)
	K.box(recess, Vector3(1.72, 0.14, 0.58), K.STONE_DARK, Vector3(0, 0.77, 0))
	K.box(recess, Vector3(1.45, 1.05, 0.19), K.STONE_DARK, Vector3(0, 0.32, 0.04))
	var brick := K.Assets.pbr_unique("rock_01", 2.4, Color("#b7a88e"))
	brick.normal_scale = 0.24
	for side in [-1.0, 1.0]:
		K.box(recess, Vector3(0.22, 0.68, 0.44), brick, Vector3(side * 0.76, 1.12, 0))
	for i in 11:
		var angle := PI * (i + 0.5) / 11.0
		var size := 0.254 if i == 5 else 0.225
		K.box(recess, Vector3(0.211, size, 0.45), brick,
			Vector3(0.76 * cos(angle), 1.47 + 0.69 * sin(angle), 0), Vector3(0, 0, rad_to_deg(angle) - 90))
	# 泥陶油盏的光源藏在灯焰旁。外侧不透墙，灯槽后壁保留接触阴影。
	var brass := K.mat(Color("#817252"), 0.56)
	var base := Vector3(-0.16, 0.846, 0.062)
	K.cyl(recess, 0.10, 0.14, 0.041, brass, base + Vector3.UP * 0.02, Vector3.ZERO, 24)
	K.cyl(recess, 0.045, 0.079, 0.105, brass, base + Vector3.UP * 0.09, Vector3.ZERO, 20)
	K.cyl(recess, 0.172, 0.066, 0.083, brass, base + Vector3.UP * 0.173, Vector3.ZERO, 28)
	K.cyl(recess, 0.151, 0.15, 0.008, Color("#40382b"), base + Vector3.UP * 0.216, Vector3.ZERO, 28)
	K.sphere(recess, 0.050, K.mat(Color("#ffbf62"), 0.68, 2.0), base + Vector3(0.075, 0.28, 0.013), Vector3(0.53, 1.52, 0.53))
	var oil := K.light(recess, Color("#ffd39c"), 1.10, 5.8, base + Vector3(0.075, 0.42, 0.26), true)
	oil.shadow_blur = 1.35
	# 壁架收在原柜深度内，上层摆空坛，下层放叠套的笸箩。
	var rack := K.node(room, Vector3(-2.77, 0.10, -3.05))
	for x in [-0.81, 0.81]:
		for z in [-0.17, 0.17]:
			K.box(rack, Vector3(0.077, 1.68, 0.078), K.WOOD, Vector3(x, 0.84, z))
		K.box(rack, Vector3(0.07, 0.37, 0.06), K.WOOD_LIGHT, Vector3(x, 1.39, 0.018), Vector3(41, 0, 0))
	for y in [0.18, 0.86, 1.56]:
		K.box(rack, Vector3(1.77, 0.071, 0.48), K.WOOD_LIGHT, Vector3(0, y, 0))
		K.box(rack, Vector3(1.64, 0.075, 0.061), K.WOOD, Vector3(0, y - 0.055, 0.181))
	Props.clay_jar(rack, Vector3(-0.41, 0.90, 0), 0.66)
	Props.clay_jar(rack, Vector3(0.27, 0.90, 0.012), 0.48)
	for i in 2:
		var tray := Workshop.place(rack, &"Basket", Vector3(0.24, 0.22 + i * 0.12, 0))
		tray.scale = Vector3(0.72, 0.50, 0.63)
	Props.clay_jar(rack, Vector3(-0.48, 0.218, 0.006), 0.53)


static func desk(root: Node3D, cellar: bool) -> void:
	# 保留旧桌占地与整理台触点。桌面有压条、抽屉和脚枨，桌下有真实的负空间。
	for x in [-0.5, 0.5]:
		for z in [-0.164, 0.164]:
			K.box(root, Vector3(0.075, 0.77, 0.073), K.WOOD, Vector3(x, 0.48, z))
		K.box(root, Vector3(0.061, 0.065, 0.38), K.WOOD_LIGHT, Vector3(x, 0.27, 0))
	K.box(root, Vector3(1.04, 0.067, 0.07), K.WOOD, Vector3(0, 0.30, -0.12))
	K.box(root, Vector3(1.14, 0.15, 0.36), K.WOOD, Vector3(0, 0.721, 0))
	for side in [-1.0, 1.0]:
		K.box(root, Vector3(0.49, 0.105, 0.025), K.WOOD_LIGHT, Vector3(side * 0.27, 0.72, 0.194))
		K.cyl(root, 0.025, 0.025, 0.022, K.mat(Color("#927950"), 0.52), Vector3(side*0.27, 0.72, 0.214), Vector3(90, 0, 0), 18)
	K.box(root, Vector3(1.29, 0.075, 0.50), K.WOOD_LIGHT, Vector3(0, 0.836, 0))
	if cellar:
		var basket := Workshop.place(root, &"Basket", Vector3(-0.31, 0.875, 0))
		basket.scale = Vector3(0.53, 0.50, 0.53)
		Props.clay_jar(root, Vector3(0.31, 0.875, -0.045), 0.36)
	else:
		var papers := Props.desk_items(root, Vector3(0.025, 0.876, 0.018))
		for fill in papers.find_children("*", "Light3D", true, false):
			fill.queue_free()
## 窗龛三扇分段的提帘。每幅的底梁单独绕卷，留出坐榻上的视线。
static func rolled_blind(wall: Node3D, span: float, drop: float) -> void:
	var width := span - 0.19
	var reed := K.mat(Color("#b18b60"), 0.88)
	var braid := K.mat(Color("#665843"), 0.93)
	var top := 2.185
	var slats := maxi(4, roundi(drop / 0.053))
	for i in slats:
		K.box(wall, Vector3(width, drop / slats - 0.003, 0.029), reed,
			Vector3(0, top - (i + 0.5) * drop / slats, 0.113), Vector3(5, 0, 0))
	K.cyl(wall, 0.056, 0.056, width+0.038, reed, Vector3(0, top-drop-0.012, 0.129), Vector3(0, 0, 90), 16)
	for side in [-1.0, 1.0]:
		var x: float = side * width * 0.30
		K.box(wall, Vector3(0.018, drop+0.065, 0.020), braid, Vector3(x, top-drop*0.5-0.021, 0.146))
		K.cyl(wall, 0.059, 0.059, 0.027, braid, Vector3(x, top-drop-0.012, 0.13), Vector3(0, 0, 90), 16)


static func window_seat(seat: Node3D) -> void:
	for side in [-1.0, 1.0]:
		for edge in [-1.0, 1.0]:
			K.box(seat, Vector3(0.095, 0.44, 0.089), K.WOOD, Vector3(side*0.70, 0.35, edge*0.185))
		K.box(seat, Vector3(0.076, 0.15, 0.43), K.WOOD, Vector3(side*0.70, 0.46, 0))
	K.box(seat, Vector3(1.43, 0.14, 0.071), K.WOOD, Vector3(0, 0.47, 0.18))
	K.box(seat, Vector3(1.47, 0.054, 0.43), K.WOOD_LIGHT, Vector3(0, 0.31, -0.008))
	K.box(seat, Vector3(1.58, 0.09, 0.54), K.WOOD_LIGHT, Vector3(0, 0.57, 0))
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://scripts/world/woven_cotton.gdshader")
	fabric.set_shader_parameter("linen", Color("#66817d"))
	fabric.set_shader_parameter("cover_print", preload("res://assets/art/textiles/indigo_fish.svg"))
	var padding := SurfaceTool.new()
	padding.begin(Mesh.PRIMITIVE_TRIANGLES)
	Props._filled_cloth(padding, 0, Vector3.ZERO, Vector2(1.25, 0.48), true)
	padding.generate_normals()
	var pad := K._mesh(seat, padding.commit(), fabric, Vector3(0.035, 0.616, 0.014))
	pad.scale.y=0.80
	var roll := K.node(seat, Vector3(-0.51, 0.789, 0.015), Vector3(0, -8, 0))
	var cotton:=K.mat(Color("#a79c82"), 0.94)
	K.cyl(roll, 0.098, 0.098, 0.405, cotton, Vector3.ZERO, Vector3(90, 0, 0), 24)
	for edge in [-1.0, 1.0]:
		K.cyl(roll, 0.100, 0.100, 0.038, K.mat(Color("#4a6263"), 0.9), Vector3(0, 0, edge*0.163), Vector3(90, 0, 0), 24)
	K.collider(seat, Vector3(1.54, 0.60, 0.50), Vector3(0, 0.34, 0))


static func attic_shelves(root: Node3D) -> void:
	# 压在背墙内缘的搁板与书匣，不伸到整理台或可摆放家具的范围。
	var shelf := K.node(root, Vector3(-2.35, 0, -3.30))
	for x in [-0.78, 0.78]:
		K.box(shelf, Vector3(0.08, 1.30, 0.09), K.WOOD, Vector3(x, 1.14, -0.045))
	for y in [0.96, 1.57]:
		K.box(shelf, Vector3(1.70, 0.060, 0.29), K.WOOD_LIGHT, Vector3(0, y, 0.02))
		for x in [-0.70, 0.70]:
			K.box(shelf, Vector3(0.065, 0.22, 0.061), K.WOOD, Vector3(x, y-0.1, 0.008), Vector3(-36, 0, 0))
	for level in 2:
		for i in (3 if level==0 else 2):
			var packet := K.node(shelf, Vector3(-0.36+0.017*i, 0.998+0.61*level+i*0.082, 0.04), Vector3(0, -4+i*2, 0))
			var cloth := K.mat(Color("#586e71") if (i+level)%2==0 else Color("#947251"), 0.92)
			K.box(packet, Vector3(0.52, 0.067, 0.225), Color("#c0ad87"), Vector3(0, 0.035, 0))
			K.box(packet, Vector3(0.535, 0.015, 0.238), cloth, Vector3(0, 0.073, 0))
			K.box(packet, Vector3(0.036, 0.072, 0.239), cloth, Vector3(-0.25, 0.039, 0))
	Props.clay_jar(shelf, Vector3(0.43, 1.604, 0.028), 0.38)
	for i in 2:
		K.cyl(shelf, 0.032, 0.032, 0.36, K.mat(Color("#bcab88"), 0.90), Vector3(0.36, 1.029, -0.04+i*0.083), Vector3(0, 3, 90), 14)


static func guest_tea(root: Node3D) -> void:
	var shelves := Props.bookshelf(root, Vector3(3.73, 0.12, -0.82))
	shelves.rotation_degrees.y = -90
	var settee := K.node(root, Vector3(-2.4, 0.13, -2.55))
	var table := Props._fitted(settee, "chinese_tea_table", Vector3(1.47, 0.68, 0.92))
	var top := K.Assets.local_aabb(table).end.y
	var stool := K.node(root, Vector3(-1.52, 0.13, -1.70), Vector3(0, -26, 0))
	Props._fitted(stool, "folding_wooden_stool", Vector3(0.49, 0.45, 0.41))
	House._woven_mat(root, Vector3(-2.23, 0.146, -2.03), 1.93)
	var tea := K.node(settee, Vector3(0, top+0.002, 0))
	K.cyl(tea, 0.203, 0.194, 0.017, K.WOOD, Vector3(0, 0.010, 0), Vector3.ZERO, 32)
	var celadon := K.mat(Color("#869a87"), 0.39)
	var bowl := Props._turned_vessel(PackedVector2Array([Vector2(0.031, 0), Vector2(0.036, 0.012),
		Vector2(0.046, 0.022), Vector2(0.068, 0.068), Vector2(0.067, 0.074), Vector2(0.059, 0.073),
		Vector2(0.057, 0.058), Vector2(0.03, 0.023), Vector2(0.001, 0.019)]))
	for p: Vector3 in [Vector3(-0.072, 0.021, 0.068), Vector3(0.087, 0.021, -0.041)]:
		K._mesh(tea, bowl, celadon, p)
		K.cyl(tea, 0.055, 0.054, 0.003, K.mat(Color("#79582e"), 0.24), p+Vector3.UP*0.053, Vector3.ZERO, 24)


static func stairs(exit: Node3D, cellar: bool) -> void:
	var iron := K.mat(Color("#5a544a"), 0.55)
	if cellar:
		# 地窖用靠前墙向上的木梯，头两级仍落在原触点占地内。
		var angle := rad_to_deg(atan2(0.58, 1.31))
		for side in [-1.0, 1.0]:
			K.box(exit, Vector3(0.092, 1.45, 0.11), K.WOOD, Vector3(side*0.48, 0.813, -0.01), Vector3(angle, 0, 0))
			K.box(exit, Vector3(0.105, 0.17, 0.12), iron, Vector3(side*0.48, 0.24, -0.26), Vector3(angle, 0, 0))
		for i in 5:
			K.box(exit, Vector3(0.94, 0.066, 0.16), K.WOOD_LIGHT, Vector3(0, 0.26+i*0.245, -0.245+i*0.108))
	else:
		# 进深和踏步按上层板面向下排。梯井内衬低于地面，斜视可见每一级的踢面。
		K.box(exit, Vector3(1.4, 0.06, 1.48), Color("#392e25"), Vector3(0, -0.80, 0.26))
		var lining := K.mat(Color("#594536"), 0.89)
		for side in [-1.0, 1.0]:
			K.box(exit, Vector3(0.074, 0.90, 1.48), lining, Vector3(side * 0.662, -0.32, 0.26))
		K.box(exit, Vector3(1.4, 0.90, 0.09), lining, Vector3(0, -0.32, 0.96))
		for i in 5:
			var z := -0.326 + i * 0.263
			var y := 0.082 - i * 0.150
			K.box(exit, Vector3(1.27, 0.072, 0.269), K.WOOD_LIGHT, Vector3(0, y, z))
			K.box(exit, Vector3(1.20, 0.143, 0.041), K.WOOD, Vector3(0, y-0.074, z+0.112))
			for side in [-1.0, 1.0]:
				K.cyl(exit, 0.015, 0.015, 0.004, iron, Vector3(side*0.51, y+0.038, z+0.078), Vector3.ZERO, 10)
		for z in [-0.37, 0.82]:
			K.box(exit, Vector3(0.089, 0.67, 0.089), K.WOOD, Vector3(-0.694, 0.46, z))
		K.box(exit, Vector3(0.108, 0.083, 1.34), K.WOOD_LIGHT, Vector3(-0.694, 0.81, 0.225))
