extends RefCounted
## 临川的造石、立木和沿街门面。砖石行与桥拱各自一次成面，不给行人增添碰撞。
const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")
const House = preload("res://scripts/world/home_house.gd")

static var _ashlar: BaseMaterial3D
static var _ridge_finish: StandardMaterial3D
static var _exposed_brick: BaseMaterial3D

static func stone() -> BaseMaterial3D:
	if _ashlar == null:
		_ashlar = Assets.pbr_unique("rock_01", 2.45, Color("#d2dce0"))
		_ashlar.vertex_color_use_as_albedo = true
		_ashlar.vertex_color_is_srgb = true
		_ashlar.normal_scale = 0.34
	return _ashlar


static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, tone: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
		s.set_normal(normal)
		s.set_color(tone)
		for p in [a, b, c, a, c, d]:
			s.add_vertex(p)
	else:
		s.set_normal(normal)
		s.set_color(tone)
		for p in [a, d, c, a, c, b]:
			s.add_vertex(p)


## 沿 X 挤出由 (Z,Y) 表示的石券横截面。四块侧面各有独立法线，石缝能吃到侧光。
static func _stone_block(s: SurfaceTool, outline: PackedVector2Array, xl: float, xr: float, tone: Color) -> void:
	var center := Vector2.ZERO
	for p in outline:
		center += p
	center /= outline.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for p in outline:
		left.append(Vector3(xl, p.y, p.x))
		right.append(Vector3(xr, p.y, p.x))
	_quad(s, left[0], left[1], left[2], left[3], Vector3.LEFT, tone)
	_quad(s, right[0], right[1], right[2], right[3], Vector3.RIGHT, tone)
	for i in 4:
		var j := (i + 1) % 4
		var out := (outline[i] + outline[j]) / 2.0 - center
		_quad(s, left[i], right[i], right[j], left[j], Vector3(0, out.y, out.x), tone)


static func _stone_mesh(parent: Node3D, surface: SurfaceTool) -> MeshInstance3D:
	surface.index()
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = stone()
	parent.add_child(node)
	return node


## 墙面留窄灰缝，丁顺错开。尺寸均为米；单个节点复用在地窖、码头及断墙。
static func courses(parent: Node3D, width: float, height: float, thickness: float, dark := false) -> void:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := maxi(1, roundi(height / 0.28))
	var columns := maxi(1, roundi(width / 0.65))
	var step := width / columns
	for row in rows:
		var shift := 0.5 * (row % 2)
		for col in range(columns + row % 2):
			var x0 := maxf(-width / 2.0, (col - shift) * step - width / 2.0) + 0.007
			var x1 := minf(width / 2.0, (col + 1.0 - shift) * step - width / 2.0) - 0.007
			var y := float(row) * height / rows + 0.006
			var top := float(row + 1) * height / rows - 0.006
			var deep := thickness / 2.0 + 0.004 * posmod(row * 7 + col * 3, 4)
			var p := PackedVector2Array([Vector2(-deep, y), Vector2(deep, y), Vector2(deep - 0.012, top), Vector2(-deep, top)])
			var value := (0.54 if dark else 0.75) + 0.028 * posmod(row * 7 + col * 5 + row * col, 7)
			_stone_block(s, p, x0, x1, Color(value * 0.97, value, value * 1.015))
	_stone_mesh(parent, s)


static func bridge_height(offset: float) -> float:
	if absf(offset) >= 3.9:
		return 0.0
	if absf(offset) >= 3.6:
		return (3.9 - absf(offset)) * 0.5
	return 0.15 + 0.90 * (1.0 - pow(offset / 3.6, 2))


static func bridge(parent: Node3D, pos: Vector3) -> void:
	var pier := K.node(parent, pos)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 楔形拱石穿过桥宽，两拱脚坐在驳岸上，拱腹在水面上留空。
	for i in 19:
		var a := PI * i / 19.0 + 0.002
		var b := PI * (i + 1) / 19.0 - 0.002
		var outline := PackedVector2Array([Vector2(2.83 * cos(a), -0.30 + 0.98 * sin(a)), Vector2(2.83 * cos(b), -0.30 + 0.98 * sin(b)),
			Vector2(3.13 * cos(b), -0.30 + 1.20 * sin(b)), Vector2(3.13 * cos(a), -0.30 + 1.20 * sin(a))])
		var value := 0.81 + 0.026 * posmod(i * 7, 5)
		_stone_block(s, outline, -1.62, 1.62, Color(value * 0.98, value, value * 1.015))
	# 拱背至踏面逐段填实。阶石顶面的曲线和行人使用同一高度。
	for i in 24:
		var z0 := -3.90 + i * 0.325 + 0.004
		var z1 := z0 + 0.317
		var h0 := bridge_height(z0)
		var h1 := bridge_height(z1)
		var low0 := minf(h0 - 0.12, -0.30 + 1.20 * sqrt(maxf(0, 1.0 - pow(z0 / 3.13, 2))))
		var low1 := minf(h1 - 0.12, -0.30 + 1.20 * sqrt(maxf(0, 1.0 - pow(z1 / 3.13, 2))))
		_stone_block(s, PackedVector2Array([Vector2(z0, low0), Vector2(z1, low1), Vector2(z1, h1), Vector2(z0, h0)]), -1.59, 1.59, Color("#b9bfbd"))
	_stone_mesh(pier, s)
	var grey := Assets.pbr("rock_01", 2.4, Color("#c9d1d1"))
	for flank in [-1.0, 1.0]:
		var x: float = flank * 1.48
		for i in 7:
			var z := (i - 3) * 1.15
			var y := bridge_height(z)
			K.box(pier, Vector3(0.21, 0.71, 0.24), grey, Vector3(x, y + 0.34, z))
			K.cyl(pier, 0.13, 0.17, 0.085, grey, Vector3(x, y + 0.738, z), Vector3(0, 22.5, 0), 8)
			if i < 6:
				var next_y := bridge_height(z + 1.15)
				var tilt := -rad_to_deg(atan2(next_y - y, 1.15))
				var run := Vector2(1.15, next_y - y).length()
				for rail_y in [0.29, 0.60]:
					K.box(pier, Vector3(0.13, 0.12, run), grey, Vector3(x, 0.5 * (y + next_y) + rail_y, z + 0.575), Vector3(tilt, 0, 0))


## 铁墩有窄腰和打平的砧面，木座用两道扁铁箍紧。
static func smith_anvil(parent: Node3D, pos: Vector3) -> void:
	var root := K.node(parent, pos, Vector3(0, -8, 0))
	for i in 3:
		K.box(root, Vector3(0.215, 0.51, 0.49), K.WOOD, Vector3((i - 1) * 0.222, 0.255, 0))
	House.finish_joinery(root)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("#515656")
	iron.metallic = 0.68
	iron.roughness = 0.59
	for y in [0.13, 0.385]:
		for side in [-1, 1]:
			K.box(root, Vector3(0.67, 0.032, 0.019), iron, Vector3(0, y, side * 0.25))
			K.box(root, Vector3(0.018, 0.032, 0.50), iron, Vector3(side * 0.335, y, 0))
	# x 左右不等长，右端收成短喙。截面的四角各削一道锻棱。
	var rings: Array[PackedVector3Array] = []
	for profile in [Vector4(-0.27, 0.27, 0.20, 0.51), Vector4(-0.28, 0.28, 0.20, 0.56),
			Vector4(-0.17, 0.18, 0.115, 0.63), Vector4(-0.16, 0.22, 0.13, 0.74),
			Vector4(-0.29, 0.47, 0.15, 0.82), Vector4(-0.29, 0.50, 0.145, 0.89)]:
		var left: float = profile.x
		var right: float = profile.y
		var half: float = profile.z
		var y: float = profile.w
		var nose := right * 0.55
		var end_width := half * (0.35 if y > 0.8 else 0.82)
		rings.append(PackedVector3Array([Vector3(left, y, -half * 0.83), Vector3(left + 0.033, y, -half),
			Vector3(nose, y, -half), Vector3(right, y, -end_width), Vector3(right, y, end_width),
			Vector3(nose, y, half), Vector3(left + 0.033, y, half), Vector3(left, y, half * 0.83)]))
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rings.size() - 1:
		for k in 8:
			var j := (k + 1) % 8
			var a := rings[row][k]
			var b := rings[row][j]
			_quad(s, a, b, rings[row+1][j], rings[row+1][k], Vector3(b.z - a.z, 0, a.x - b.x), Color.WHITE)
	var top := rings.back() as PackedVector3Array
	s.set_normal(Vector3.UP)
	for i in range(1, top.size() - 1):
		for v in [top[0], top[i], top[i+1]]:s.add_vertex(v)
	s.index()
	K._mesh(root, s.commit(), iron, Vector3.ZERO)
	var hammer := K.node(root, Vector3(-0.04, 0.896, 0.025), Vector3(0, -23, 0))
	K.cyl(hammer, 0.019, 0.017, 0.29, K.WOOD_LIGHT, Vector3(0, 0.03, 0.085), Vector3(90, 0, 0), 8)
	K.box(hammer, Vector3(0.14, 0.064, 0.066), iron, Vector3(0, 0.032, -0.067))


## 由店里实际的陈列方式决定开间：食材商号在檐下交货，书药当铺留高柜台与窗扇。
static func shopfront(parent: Node3D, id: String, w: float, d: float, h: float) -> void:
	var n := K.node(parent)
	var front := d * 0.5
	var enclosed := id in ["bookshop","pharmacy","pawnshop"]
	if id != "temple":
		for side in [-1.0, 1.0]:
			var width := w * (0.245 if enclosed else 0.14)
			var x: float = side * (w / 2.0 - width / 2.0 - 0.19)
			var z := front - 0.48
			K.box(n, Vector3(width, 0.77, 0.13), K.WOOD, Vector3(x, 0.53, z))
			K.box(n, Vector3(width + 0.08, 0.095, 0.31), K.WOOD_LIGHT, Vector3(x, 0.96, z))
			if enclosed:
				House.paper_window(n, Vector3(x, 1.69, z), width, 1.38)
			else:
				for i in 3:
					K.box(n, Vector3(0.05, 0.7, 0.14), K.WOOD_LIGHT, Vector3(x + (i - 1) * width * 0.31, 0.54, z + 0.02))
	for side in [-1.0, 1.0]:
		var x: float = side * (w / 2.0 - 0.27)
		var bracket := K.node(n, Vector3(x, h - 0.53, front + 0.18))
		K.box(bracket, Vector3(0.16, 0.66, 0.15), K.WOOD, Vector3(0, 0.03, 0.10), Vector3(-35, 0, 0))
		K.box(bracket, Vector3(0.30, 0.13, 0.64), K.WOOD_LIGHT, Vector3(0, 0.29, 0.23))
	if id in ["rice_shop","market","grocery","bookshop"]:
		var tint: Color = {"rice_shop":Color("#b19b73"),"market":Color("#75806c"),"grocery":Color("#91816d"),"bookshop":Color("#75848a")}[id]
		var cloth := K.mat(tint, 0.98).duplicate() as BaseMaterial3D
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		var span := w * 0.58
		var z0 := front + 0.37
		# 两侧斜杆撑住雨布，檐头车缝沉出很浅的弧。
		for side in [-1.0, 1.0]:
			K.box(n, Vector3(0.065, 0.065, 1.40), K.WOOD, Vector3(side * span / 2.0, h - 0.52, z0 + 0.55), Vector3(17, 0, 0))
		# 一整匹篷布系在两端，中腰渐垂。前缘是折回的短布帘。
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var columns := 24
		for i in columns + 1:
			var t := float(i) / columns
			var x := span * (t - 0.5)
			var sag := sin(PI * t)
			var pleat := sin(t * TAU * 3.0 + 0.38) * sag
			var front_height := h - 0.614 - 0.105 * sag + 0.023 * pleat
			var rim_z := z0 + 1.133 + 0.023 * pleat
			for point in [Vector3(x, h - 0.27 - 0.055 * sag, z0 - 0.1),
					Vector3(x, h - 0.49 - 0.12 * sag + 0.013 * pleat, z0 + 0.54),
					Vector3(x, front_height, rim_z), Vector3(x, front_height - 0.019, rim_z + 0.004),
					Vector3(x, front_height - 0.140 - 0.018 * sag, rim_z - 0.015)]:
				surface.add_vertex(point)
		for col in columns:
			for row in 4:
				var start := col * 5 + row
				for idx in [start, start + 5, start + 1, start + 5, start + 6, start + 1]:
					surface.add_index(idx)
		surface.generate_normals()
		var canopy := MeshInstance3D.new()
		canopy.mesh = surface.commit()
		canopy.material_override = cloth
		n.add_child(canopy)
	House.finish_joinery(n)

## 残墙保留真实受力位置；残砖压在墙脚，木柱和穿枋坐在残留墙段上。
static func ruined_bay(parent: Node3D, at: Vector3, along_z: bool, width: float, height: float, outdoor: bool, seed_value: int) -> void:
	var root := K.node(parent, at, Vector3(0, 90.0 if along_z else 0.0, 0))
	K.collider(root, Vector3(width, height, 0.20 if width < 2.0 else 0.22), Vector3.UP * height * 0.5)
	if outdoor:
		var count := maxi(2, ceili(width / 1.55))
		for i in count + 1:
			var h := height * (0.91 + 0.027 * posmod(seed_value + i * 7, 5))
			K.box(root, Vector3(0.15, h, 0.19), K.WOOD, Vector3(width * (float(i) / count - 0.5), h * 0.5, 0))
		for frac in [0.36, 0.76]:
			K.box(root, Vector3(width, 0.125, 0.105), K.WOOD_LIGHT, Vector3(0, height * frac, -0.052))
		return
	var foot := minf(0.59, height * 0.48)
	courses(root, width, foot, 0.25, true)
	var plaster := SurfaceTool.new()
	var core := SurfaceTool.new()
	plaster.begin(Mesh.PRIMITIVE_TRIANGLES)
	core.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 断口露出砌体与灰浆。灰皮的剥落边沿略低于砖芯，断面有厚度。
	var pieces := maxi(4, ceili(width / 0.43))
	var scar := 0.24 + 0.10 * posmod(seed_value, 5)
	var rim := PackedVector2Array()
	var skin := PackedFloat32Array()
	for i in pieces + 1:
		var t := float(i) / pieces
		var distance := absf(t - scar)
		var loss := 1.0 - smoothstep(0.035, 0.31 if t < scar else 0.26, distance)
		var nick := 0.016 * posmod(i * 11 + seed_value * 3, 5)
		var h := height - (height - foot) * 0.78 * loss - nick
		h = maxf(foot + 0.085, roundf(h / 0.075) * 0.075)
		var x := (t - 0.5) * width
		var bare := 0.009 + loss * (0.12 + nick * 1.4)
		if i > 0 and absf(h - rim[-1].y) > 0.16:
			var prev: Vector2 = rim[-1]
			# 断裂沿一截砖床横走，再向下一皮砖错落。
			rim.append(Vector2(lerpf(prev.x, x, 0.39), prev.y - 0.013))
			skin.append(maxf(foot + 0.01, skin[-1] - 0.021))
		rim.append(Vector2(x, h))
		skin.append(maxf(foot + 0.014, h - bare))
	var segments := rim.size() - 1
	for i in segments:
		var a := rim[i]
		var b := rim[i + 1]
		for side in [-1.0, 1.0]:
			var z: float = side * 0.116
			var inset: float = side * 0.097
			var outward := Vector3(0, 0, side)
			var low_a := Vector3(a.x, skin[i], z)
			var low_b := Vector3(b.x, skin[i+1], z)
			var bare_a := Vector3(a.x, a.y, inset)
			var bare_b := Vector3(b.x, b.y, inset)
			_quad(plaster, Vector3(a.x, foot, z), Vector3(b.x, foot, z), low_b, low_a, outward, Color.WHITE)
			_quad(core, low_a, low_b, bare_b, bare_a, outward, Color.WHITE)
		_quad(core, Vector3(a.x, a.y, -0.097), Vector3(b.x, b.y, -0.097), Vector3(b.x, b.y, 0.097), Vector3(a.x, a.y, 0.097), Vector3.UP, Color.WHITE)
	for end in [0, segments]:
		var p := rim[end]
		_quad(core, Vector3(p.x, foot, -0.11), Vector3(p.x, p.y, -0.097), Vector3(p.x, p.y, 0.097), Vector3(p.x, foot, 0.11), Vector3.LEFT if end == 0 else Vector3.RIGHT, Color.WHITE)
	if _exposed_brick == null:
		_exposed_brick = Assets.pbr_unique("brick_wall_09", 2.5, Color("#c6beae"))
		_exposed_brick.normal_scale = 0.36
	plaster.index()
	core.index()
	K._mesh(root, plaster.commit(), House.plaster(), Vector3.ZERO)
	K._mesh(root, core.commit(), _exposed_brick, Vector3.ZERO)
	for i in [0, segments]:
		var p := rim[i]
		K.box(root, Vector3(0.14, p.y, 0.25), K.WOOD, Vector3(p.x * 0.968, p.y / 2.0, 0))

## 用三道偏移山梁叠出鞍部与山脚，法线跨相邻山面平均。远山用轮廓和空气色控制层次。
static func ridge(parent: Node3D, width: float, depth: float, height: float, variant: int, snowy := false) -> void:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 24
	var mesh_rows: Array[PackedVector3Array] = []
	for row in 6:
		var points := PackedVector3Array()
		for i in cols + 1:
			var t := float(i) / cols
			var envelope := pow(maxf(0.0, sin(PI * t)), 0.61)
			var profile := 0.51 + 0.17 * sin(t * 11.4 + variant * 2.0) + 0.10 * sin(t * 24.0 + variant * 1.2) + 0.06 * sin(t * 39.0)
			var cross_height: float = [0.0, 0.29, 0.60, 1.0, 0.55, 0.03][row]
			var ridge_z: float = (float(row) / 5.0 - 0.5) * depth + sin(t * 13.0 + row * 0.81 + variant) * depth * 0.055
			points.append(Vector3((t - 0.5) * width, height * envelope * profile * cross_height, ridge_z))
		mesh_rows.append(points)
	for row in 5:
		for i in cols:
			for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i.ONE, Vector2i.ZERO, Vector2i.ONE, Vector2i(0, 1)]:
				var p := mesh_rows[row + offset.y][i + offset.x]
				var haze := clampf(p.y / height, 0, 1)
				var tone := Color("#7b8487").lerp(Color("#5f7177"), haze)
				if snowy:
					tone = tone.lerp(Color("#c3ced0"), smoothstep(0.43, 0.71, haze) * 0.60)
				s.set_color(tone)
				s.add_vertex(p)
	s.generate_normals()
	s.index()
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	if _ridge_finish == null:
		_ridge_finish = StandardMaterial3D.new()
		_ridge_finish.vertex_color_use_as_albedo = true
		_ridge_finish.vertex_color_is_srgb = true
		_ridge_finish.roughness = 1.0
	mi.material_override = _ridge_finish
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
