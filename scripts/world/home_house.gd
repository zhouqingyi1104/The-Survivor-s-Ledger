extends RefCounted
## 自宅剖开向院的一面，后檐、窗洞与廊柱仍连成完整屋架。本地 +Z 朝院子。

const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")

const PLANKS := [Color("#997655"), Color("#a08060"), Color("#a58664")]
const PAVERS := [Color("#736f64"), Color("#79776c"), Color("#838075")]
const TIMBER := Color("#654833")
const TRIM := Color("#89694d")
const PLASTER := Color("#d1c3a7")
const PAPER := Color("#e3cba1")


static func build(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, h: float, kind: String) -> Dictionary:
	var room := K.node(parent, pos, Vector3(0, rot_y, 0), "house_" + kind)
	var hall := kind == "hall"
	var kitchen := kind == "kitchen"
	_floor(room, w, d, kitchen)
	# 后墙保留原来的完整碰撞，窗户开在墙网格上。
	K.collider(room, Vector3(w, h, 0.3), Vector3(0, h * 0.5, -d * 0.5))
	_back_wall(room, w, d, h, kind)
	if hall:
		for side in [-1.0, 1.0]:
			_cut_end(room, side * w * 0.5, d, h)
		_woven_mat(room, Vector3(-w * 0.29, 0.14, d * 0.12), minf(2.25, w * 0.22))
	elif kitchen:
		_kitchen_wall(room, w, d, h)
	else:
		_tool_board(room, w, d, h)
	var z_front := d * 0.5 - 0.2
	var beam_y := h - 0.16
	var bays := 4 if hall else 2
	var timber := K.mat(K.WOOD)
	for i in bays + 1:
		if hall and i == 2:
			continue
		var x := w * (float(i) / bays - 0.5)
		var foot := Vector3(x, 0, z_front)
		K.box(room, Vector3(0.34, 0.22, 0.34), K.STONE, foot + Vector3.UP * 0.11)
		K.box(room, Vector3(0.19, beam_y - 0.18, 0.19), timber, foot + Vector3.UP * (beam_y + 0.18) * 0.5)
		K.box(room, Vector3(0.54, 0.15, 0.26), TRIM, foot + Vector3.UP * (beam_y - 0.15))
		K.collider(room, Vector3(0.3, h, 0.3), foot + Vector3.UP * h * 0.5)
		# 外端榀架横跨进深，巷口能看见梁与后檐的榫接。
		if i == 0 or i == bays:
			K.box(room, Vector3(0.19, 0.19, d + 0.18), timber, Vector3(x, beam_y, -0.04))
	if hall:
		# 正中开间留出通向神龛的视廊。两侧短廊各自承托一段瓦檐。
		for side in [-1.0, 1.0]:
			var veranda := K.node(room, Vector3(side * w * 0.375, beam_y, z_front))
			K.box(veranda, Vector3(w * 0.25 + 0.40, 0.19, 0.23), timber, Vector3.ZERO)
			var width := w * 0.25 + 0.48
			var eave := K.node(veranda, Vector3(0, 0.14, 0), Vector3(11, 0, 0))
			K.box(eave, Vector3(width, 0.10, 0.52), Color("#485256"), Vector3.ZERO)
			var rolls := maxi(2, roundi(width / 0.30))
			for i in rolls:
				var x := width * ((i + 0.5) / rolls - 0.5)
				K.cyl(eave, 0.047, 0.054, 0.55, Color("#626d6b"), Vector3(x, 0.055, 0), Vector3(90, 0, 0), 8)
	else:
		K.box(room, Vector3(w + 0.45, 0.19, 0.23), timber, Vector3(0, beam_y, z_front))
	var roof_mat := K.unique_mat(Color("#5d6768"), 0.90)
	var tile_mat := K.unique_mat(Color.WHITE, 0.88)
	tile_mat.vertex_color_use_as_albedo = true
	var roof := _back_roof(room, w, d, h, 1.55 if hall else (1.15 if kitchen else 0.90), roof_mat, tile_mat)
	return {"node": room, "roof": roof, "fade_mats": [roof_mat, tile_mat], "w": w, "d": d}


static func _floor(room: Node3D, w: float, d: float, kitchen: bool) -> void:
	K.box(room, Vector3(w + 0.5, 0.105, d + 0.42), Color("#68645b"), Vector3(0, 0.0525, 0))
	var palette := PAVERS if kitchen else PLANKS
	var rows := maxi(1, roundi(d / (0.64 if kitchen else 0.38)))
	var length := 1.0 if kitchen else 2.7
	var strip := d / rows
	for row in rows:
		var left := -w * 0.5
		var edge := left + (length * 0.5 if row % 2 else length)
		var column := 0
		while left < w * 0.5 - 0.02:
			var right := minf(edge, w * 0.5)
			var color: Color = palette[(row * 2 + column) % palette.size()]
			K.box(room, Vector3(right - left - 0.014, 0.026, strip - 0.014), color,
				Vector3((left + right) * 0.5, 0.118, (row + 0.5) * strip - d * 0.5))
			left = right
			edge += length
			column += 1
	K.box(room, Vector3(w + 0.40, 0.045, 0.18), TRIM, Vector3(0, 0.12, d * 0.5 + 0.08))


static func _back_wall(room: Node3D, w: float, d: float, h: float, kind: String) -> void:
	var back := -d * 0.5
	var sill := h * 0.37
	var top := h * 0.78
	var centers := PackedFloat32Array([-w * 0.32, w * 0.32]) if kind == "hall" else PackedFloat32Array([w * 0.22])
	var width := minf(1.95, w * 0.22)
	var lime: Material = Assets.pbr("white_stucco", 2.8, PLASTER)
	if lime == null:
		lime = K.mat(PLASTER)
	K.box(room, Vector3(w, sill, 0.27), lime, Vector3(0, sill * 0.5, back))
	K.box(room, Vector3(w, h - top, 0.27), lime, Vector3(0, (top + h) * 0.5, back))
	K.box(room, Vector3(w, sill * 0.57, 0.32), Color("#978873"), Vector3(0, sill * 0.285, back))
	K.box(room, Vector3(w, 0.09, 0.35), TRIM, Vector3(0, sill * 0.57, back))
	var left := -w * 0.5
	for x in centers:
		var edge := x - width * 0.5
		_wall_span(room, left, edge, sill, top, back, lime)
		var mid := Vector3(x, (sill + top) * 0.5, back)
		_window(room, mid, width, top - sill)
		left = x + width * 0.5
	_wall_span(room, left, w * 0.5, sill, top, back, lime)
	K.box(room, Vector3(w + 0.15, 0.19, 0.33), TIMBER, Vector3(0, h - 0.10, back))
	for x in [-w * 0.50, 0.0, w * 0.50]:
		K.box(room, Vector3(0.15, h, 0.34), TIMBER, Vector3(x, h * 0.5, back))


static func _wall_span(room: Node3D, left: float, right: float, low: float, high: float, z: float, lime: Material) -> void:
	if right > left:
		K.box(room, Vector3(right - left, high - low, 0.27), lime, Vector3((right + left) * 0.5, (high + low) * 0.5, z))


static func _window(room: Node3D, mid: Vector3, width: float, height: float) -> void:
	# 纸窗缩进墙体，深窗台和透木疏格在侧视、俯视下均有厚度。
	K.box(room, Vector3(width, height, 0.075), TIMBER, mid)
	K.box(room, Vector3(width - 0.14, height - 0.13, 0.088), K.mat(PAPER, 0.92, 0.12), mid)
	for x in [-0.25, 0.0, 0.25]:
		K.box(room, Vector3(0.045, height - 0.05, 0.115), TIMBER, mid + Vector3.RIGHT * x * width)
	K.box(room, Vector3(width, 0.05, 0.12), TIMBER, mid + Vector3.UP * height * 0.16)
	K.box(room, Vector3(width + 0.14, 0.10, 0.38), TRIM, mid + Vector3.DOWN * height * 0.5)


static func _cut_end(room: Node3D, x: float, d: float, h: float) -> void:
	# 山墙沿剖面逐级收低，原有实体墙继续决定通路。
	K.collider(room, Vector3(0.3, h, d), Vector3(x, h * 0.5, 0))
	for part in [[0.0, 0.36, h], [0.36, 0.63, h * 0.62], [0.63, 1.0, h * 0.29]]:
		var depth: float = (part[1] - part[0]) * d
		var z: float = -d * 0.5 + (part[1] + part[0]) * d * 0.5
		var top: float = part[2]
		K.box(room, Vector3(0.30, top, depth), PLASTER, Vector3(x, top * 0.5, z))
		K.box(room, Vector3(0.39, 0.10, depth + 0.035), Color("#56605f"), Vector3(x, top + 0.05, z))


static func _woven_mat(room: Node3D, at: Vector3, width: float) -> void:
	K.box(room, Vector3(width, 0.024, 1.15), Color("#a69267"), at)
	for z in [-0.49, 0.49]:
		K.box(room, Vector3(width, 0.009, 0.07), Color("#536c66"), at + Vector3(0, 0.016, z))


static func _kitchen_wall(room: Node3D, w: float, d: float, h: float) -> void:
	var mid := Vector3(-w * 0.24, h * 0.52, -d * 0.5 + 0.20)
	K.box(room, Vector3(w * 0.30, 1.48, 0.07), Color("#ad9a83"), mid)
	K.box(room, Vector3(w * 0.38, 0.095, 0.36), TIMBER, mid + Vector3(0, 0.54, 0.11))
	# 两只小盏与挂在墙上的笊篱收在灶上方，不占灶前的站位。
	for x in [-0.42, -0.06, 0.35]:
		K.cyl(room, 0.13, 0.07, 0.10, Color("#b9ad95"), mid + Vector3(x, 0.64, 0.16))
	K.cyl(room, 0.25, 0.22, 0.075, Color("#947344"), mid + Vector3(0.4, -0.22, 0.09), Vector3(90, 0, 0))
	K.box(room, Vector3(0.065, 0.45, 0.055), TRIM, mid + Vector3(0.4, 0.06, 0.09))


static func _tool_board(room: Node3D, w: float, d: float, h: float) -> void:
	var mid := Vector3(-w * 0.24, h * 0.54, -d * 0.5 + 0.18)
	K.box(room, Vector3(w * 0.36, 1.17, 0.11), Color("#917551"), mid)
	for y in [-0.38, 0.32]:
		K.box(room, Vector3(w * 0.36 + 0.14, 0.09, 0.16), TIMBER, mid + Vector3.UP * y)
	# 墨斗、木角尺和弓锯都挂墙，桌面和实际工作台仍由家具独立摆放。
	K.box(room, Vector3(0.08, 0.48, 0.06), Color("#c1a57b"), mid + Vector3(-0.53, 0.01, 0.10))
	K.box(room, Vector3(0.40, 0.08, 0.06), Color("#c1a57b"), mid + Vector3(-0.36, -0.19, 0.10))
	for x in [0.07, 0.63]:
		K.box(room, Vector3(0.065, 0.41, 0.05), TRIM, mid + Vector3(x, 0.04, 0.10))
	K.box(room, Vector3(0.61, 0.06, 0.05), Color("#a5aaa3"), mid + Vector3(0.35, -0.10, 0.10))
	K.box(room, Vector3(0.61, 0.05, 0.05), TRIM, mid + Vector3(0.35, 0.17, 0.10))


static func _back_roof(room: Node3D, w: float, d: float, h: float, run_z: float, base: Material, tiles: Material) -> Node3D:
	var start := -d * 0.5 - 0.40
	var pitch := -24.0
	var roof := K.node(room, Vector3(0, h - 0.18, start), Vector3(pitch, 0, 0), "retained_eaves")
	var depth := run_z / cos(deg_to_rad(pitch))
	var width := w + 0.85
	K.box(roof, Vector3(width, 0.13, depth), base, Vector3(0, 0, depth * 0.5))
	K.box(roof, Vector3(width + 0.1, 0.10, 0.18), base, Vector3(0, 0.10, depth))
	var mesh := BoxMesh.new()
	var cols := ceili(width / 0.38)
	var rows := ceili(depth / 0.46)
	var tile_w := width / cols
	var tile_d := depth / rows
	mesh.size = Vector3(tile_w - 0.016, 0.065, tile_d + 0.06)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = rows * cols
	var index := 0
	var slates := [Color("#556269"), Color("#667373"), Color("#5e6a6e"), Color("#637078")]
	for j in rows:
		for i in cols:
			var center := Vector3((i + 0.5) * tile_w - width * 0.5, 0.092, (j + 0.5) * tile_d)
			mm.set_instance_transform(index, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(5.5)), center))
			mm.set_instance_color(index, slates[(i * 7 + j * 3 + i * j) % slates.size()])
			index += 1
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = mm
	batch.material_override = tiles
	roof.add_child(batch)
	return roof
