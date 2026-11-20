extends RefCounted
## 自宅剖开向院的一面，后檐、窗洞与廊柱仍连成完整屋架。本地 +Z 朝院子。

const K = preload("res://scripts/world/kit.gd")
const Assets = preload("res://scripts/world/assets.gd")
const Plan = preload("res://scripts/core/home_plan.gd")

const PLANKS := [Color("#997655"), Color("#a08060"), Color("#a58664")]
const PAVERS := [Color("#736f64"), Color("#79776c"), Color("#838075")]
const TIMBER := Color("#654833")
const TRIM := Color("#89694d")
const PLASTER := Color("#d1c3a7")
const PAPER := Color("#e3cba1")
const ROOF := Color("#465356")


static func build(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, h: float, kind: String, gallery_door := false) -> Dictionary:
	var room := K.node(parent, pos, Vector3(0, rot_y, 0), "house_" + kind)
	var outline := Plan.footprint(kind, w, d)
	var roof := K.node(room, Vector3.ZERO, Vector3.ZERO, "retained_eaves")
	var base := K.unique_mat(ROOF, 0.90)
	var tiles := K.unique_mat(Color.WHITE, 0.88)
	tiles.vertex_color_use_as_albedo = true
	tiles.vertex_color_is_srgb = true
	build_platform(room, outline, kind == "kitchen")
	K.collider(room, Vector3(w, h, 0.30), Vector3(0, h * 0.5, -d * 0.5))
	if kind == "hall":
		_main_rooms(room, roof, outline, h, base, tiles, gallery_door)
	else:
		_service_wing(room, roof, outline, h, kind, base, tiles)
	return {"node": room, "roof": roof, "fade_mats": [base, tiles], "w": w, "d": d, "footprint": outline}


## 卧房纵跨两榀屋架，退进的厅堂举高，低矮的书斋在转角向院里采光。
static func _main_rooms(room: Node3D, roof: Node3D, plan: PackedVector2Array, h: float, base: Material, tiles: Material, gallery_door: bool) -> void:
	var west := plan[0].x
	var east := plan[1].x
	var back := plan[0].y
	var bed_end := plan[7].x
	var study_start := plan[6].x
	var bed_width := bed_end - west
	var hall_width := study_start - bed_end
	var study_width := east - study_start
	var bed_x := (west + bed_end) * 0.5
	var hall_x := (bed_end + study_start) * 0.5
	var study_x := (study_start + east) * 0.5
	var bed_h := h - 0.36
	var study_h := h - 0.59
	var hall_h := h + 0.36
	_wall_bay(room, west, bed_end, back, bed_h, true)
	_wall_bay(room, bed_end, study_start, back, hall_h, false)
	_wall_bay(room, study_start, east, back, study_h, true)
	# 厚侧墙沿原墙线收低。前伸的卧房和书斋外侧都是开敞挑廊。
	var old_front := -back - 0.20
	for x in [west, east]:
		_cut_end(room, x, -back * 2.0, bed_h if x == west else study_h, gallery_door and x == west)
	var bed_outer := Vector2(west, old_front)
	var bed_inner := Vector2(west * 0.50, old_front)
	var study_inner := Vector2(east * 0.50, old_front)
	var study_outer := Vector2(east, old_front)
	for point in [bed_outer, bed_inner]:
		_post(room, point, bed_h)
	for point in [study_inner, study_outer]:
		_post(room, point, study_h)
	# 露明梁架把床与中堂分开；头顶的挂落留足人的站高与鼠标视线。
	_rail(room, Vector2(west, back), bed_outer, bed_h, 0.19, 0.17, TIMBER)
	_rail(room, Vector2(bed_end, back), bed_inner, bed_h, 0.19, 0.17, TIMBER)
	_rail(room, Vector2(study_start, back), study_inner, study_h, 0.17, 0.15, TIMBER)
	_rail(room, Vector2(east, back), study_outer, study_h, 0.17, 0.15, TIMBER)
	# 西卧房与中堂以一列挂屏分隔。两端是收紧的帘头，中间留出净空。
	_hanging_screen(room, Vector2(bed_end, back + 0.08), bed_inner, bed_h - 0.04)
	# 西卧房的短山头退到床后，面院的一截沿外侧挑出短廊，院门口仍能看到床。
	var bed_gable_z := plan[8].y - 0.18
	_rail(room, bed_outer, Vector2(west, bed_gable_z), bed_h, 0.21, 0.20, TIMBER)
	_rail(room, bed_inner, Vector2(bed_end, bed_gable_z), bed_h, 0.21, 0.20, TIMBER)
	_gable(roof, Vector3(bed_x, bed_h, back + 0.55), bed_width + 0.44, 0.90, 2.12, base, tiles)
	var side_eave := K.node(roof, Vector3(west - 0.20, bed_h + 0.12, (back + 1.62 + bed_gable_z) * 0.5), Vector3(0, 90, 0))
	_slope(side_eave, Vector3.ZERO, bed_gable_z - back - 1.62, 0.75, 15, base, tiles)
	_rail(room, plan[8], plan[9], bed_h - 0.05, 0.13, 0.14, TIMBER)
	_woven_mat(room, Vector3(bed_x, 0.144, plan[8].y - 0.77), minf(2.35, bed_width * 0.7))
	# 正中厅堂抬梁。人从台阶进门时，门前不横跨整块檐板。
	_gable(roof, Vector3(hall_x, hall_h, back + 0.12), hall_width + 0.38, 1.38, 1.48, base, tiles)
	_rail(room, plan[7], plan[6], 0.14, 0.08, 0.21, TRIM)
	for step in 2:
		var edge := plan[7].y + (step + 1) * 0.33
		var stone_h := 0.105 - step * 0.034
		K.box(room, Vector3(hall_width * 0.75 + 0.24 * step, stone_h, 0.35), Color("#9e9c88"), Vector3(hall_x, stone_h * 0.5, edge - 0.165))
	# 东书斋三面转角撑起挂落，瓦口贴着挑台折转；俯视仍能看见里侧的书案。
	_slope(roof, Vector3(study_x, study_h - 0.12, back - 0.28), study_width + 0.40, 0.80, -21, base, tiles)
	_rail(room, study_outer, plan[2], study_h, 0.16, 0.16, TIMBER)
	_rail(room, study_inner, plan[5], study_h, 0.16, 0.16, TIMBER)
	_fret_eave(roof, plan[2], plan[3], study_h, base, tiles)
	_fret_eave(roof, plan[4], plan[5], study_h, base, tiles)
	_rail(room, plan[3], plan[4], study_h + 0.04, 0.085, 0.11, TIMBER)
	# 两列木扇留在靠山墙处，拉开后窗边仍能摆家具。
	_window_seat(room, Vector2(east, back + 0.28), Vector2(east, old_front - 0.48), study_h * 0.49)


static func _service_wing(room: Node3D, roof: Node3D, plan: PackedVector2Array, h: float, kind: String, base: Material, tiles: Material) -> void:
	var left := plan[0].x
	var right := plan[1].x
	var back := plan[0].y
	var width := right - left
	var depth := -2.0 * back
	var kitchen := kind == "kitchen"
	_wall_bay(room, left, right, back, h, true, width * 0.18)
	if kitchen:
		_kitchen_wall(room, width, depth, h)
	else:
		_tool_board(room, width, depth, h)
	# 实柱沿原柱线支撑穿枋。开敞的工作平台在柱线之外挑出，下面可以走人或放家具。
	var front := -back - 0.2
	for x in [left, 0.0, right]:
		_post(room, Vector2(x, front), h - 0.24)
	_rail(room, Vector2(left, front), Vector2(right, front), h - 0.24, 0.17, 0.18, TIMBER)
	for x in [left, right]:
		_rail(room, Vector2(x, back), Vector2(x, front), h - 0.24, 0.17, 0.15, TIMBER)
	if kitchen:
		# 灶房灶膛上方是高跨，矮一截的一侧是带罩棚的储藏廊。
		var joint := plan[3].x
		_slope(roof, Vector3((left + joint) * 0.5, h - 0.18, back - 0.30), joint - left + 0.36, 0.86, -23, base, tiles)
		_gable(roof, Vector3((right + joint) * 0.5, h + 0.08, back + 0.03), right - joint + 0.42, 0.90, 1.45, base, tiles)
		_fret_eave(roof, plan[2], plan[3], h - 0.20, base, tiles)
	else:
		_slope(roof, Vector3(0.0, h + 0.1, back - 0.3), width + 0.43, 1.12, -26, base, tiles)
		_fret_eave(roof, plan[2], plan[3], h - 0.20, base, tiles)
		_fret_eave(roof, plan[4], plan[5], h - 0.20, base, tiles)


static func build_platform(room: Node3D, plan: PackedVector2Array, kitchen: bool) -> void:
	K.floor_slab(room, plan, 0.107, 0.01, Color("#737164"))
	var bounds := Rect2(plan[0], Vector2.ZERO)
	for point in plan:
		bounds = bounds.expand(point)
	var palette := PAVERS if kitchen else PLANKS
	var row_depth := 0.64 if kitchen else 0.39
	var board_width := 1.02 if kitchen else 2.28
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in ceili(bounds.size.y / row_depth):
		var z := bounds.position.y + row * row_depth
		var x := bounds.position.x - board_width * 0.5 * (row % 2)
		var col := 0
		while x < bounds.end.x:
			var tile := PackedVector2Array([Vector2(x + 0.009, z + 0.009), Vector2(x + board_width - 0.009, z + 0.009),
				Vector2(x + board_width - 0.009, z + row_depth - 0.009), Vector2(x + 0.009, z + row_depth - 0.009)])
			for clipped in Geometry2D.intersect_polygons(plan, tile):
				for index in Geometry2D.triangulate_polygon(clipped):
					var p: Vector2 = clipped[index]
					surface.set_color(palette[(row * 2 + col) % palette.size()])
					surface.set_normal(Vector3.UP)
					surface.add_vertex(Vector3(p.x, 0.131, p.y))
			x += board_width
			col += 1
	var boards := MeshInstance3D.new()
	boards.mesh = surface.commit()
	var finish := K.unique_mat(Color.WHITE, 0.90)
	finish.vertex_color_use_as_albedo = true
	finish.vertex_color_is_srgb = true
	boards.material_override = finish
	room.add_child(boards)
	for i in range(2, plan.size() - 1):
		_rail(room, plan[i], plan[i + 1], 0.11, 0.085, 0.12, TRIM)


static func _wall_bay(room: Node3D, left: float, right: float, back: float, h: float, has_window: bool, offset := 0.0) -> void:
	var width := right - left
	var root := K.node(room, Vector3((left + right) * 0.5, 0, back))
	var sill := h * 0.33
	var top := h * 0.79
	var pane := width * 0.57
	var lime: Material = Assets.pbr("white_stucco", 2.8, PLASTER)
	if lime == null:
		lime = K.mat(PLASTER)
	K.box(root, Vector3(width, sill, 0.27), lime, Vector3.UP * sill * 0.5)
	K.box(root, Vector3(width, h - top, 0.27), lime, Vector3.UP * (h + top) * 0.5)
	K.box(root, Vector3(width, sill * 0.58, 0.33), Color("#978873"), Vector3.UP * sill * 0.29)
	if has_window:
		_wall_span(root, -width * 0.5, offset - pane * 0.5, sill, top, 0, lime)
		_window(root, Vector3(offset, (sill + top) * 0.5, 0), pane, top - sill)
		_wall_span(root, offset + pane * 0.5, width * 0.5, sill, top, 0, lime)
	else:
		_wall_span(root, -width * 0.5, width * 0.5, sill, top, 0, lime)
	K.box(root, Vector3(width, 0.20, 0.34), TIMBER, Vector3.UP * (h - 0.10))
	for x in [-width * 0.5, width * 0.5]:
		K.box(root, Vector3(0.17, h, 0.34), TIMBER, Vector3(x, h * 0.5, 0))


static func _post(room: Node3D, point: Vector2, h: float) -> void:
	var foot := Vector3(point.x, 0.0, point.y)
	K.box(room, Vector3(0.35, 0.21, 0.35), K.STONE, foot + Vector3.UP * 0.105)
	K.box(room, Vector3(0.18, h - 0.20, 0.18), K.WOOD, foot + Vector3.UP * (h + 0.20) * 0.5)
	K.box(room, Vector3(0.42, 0.13, 0.28), TRIM, foot + Vector3.UP * (h - 0.12))
	K.collider(room, Vector3(0.30, h, 0.30), foot + Vector3.UP * h * 0.5)


## 横枋、门槛与折檐都沿平面两端点搭建，不把斜边填成方台。
static func _rail(parent: Node3D, a: Vector2, b: Vector2, y: float, height: float, breadth: float, color) -> void:
	var center := (a + b) * 0.5
	K.box(parent, Vector3(a.distance_to(b) + 0.03, height, breadth), color, Vector3(center.x, y, center.y),
		Vector3(0, -rad_to_deg((b - a).angle()), 0))


static func _window_seat(room: Node3D, a: Vector2, b: Vector2, center_y: float) -> void:
	var center := (a + b) * 0.5
	var wall := K.node(room, Vector3(center.x - 0.18, center_y, center.y), Vector3(0, -90, 0))
	var length := a.distance_to(b)
	_window(wall, Vector3.ZERO, length, 0.82)
	K.box(wall, Vector3(length + 0.12, 0.11, 0.28), TRIM, Vector3(0, 0.46, 0))


## 轻木挂屏与收拢的青布帘沿卧房侧梁布置。米色透格之下留出穿行净高。
static func _hanging_screen(room: Node3D, a: Vector2, b: Vector2, level: float) -> void:
	var mid := (a + b) * 0.5
	var width := a.distance_to(b)
	var screen := K.node(room, Vector3(mid.x, level, mid.y), Vector3(0, -rad_to_deg((b - a).angle()), 0))
	var panel_height := 0.62
	var panels := 4
	var panel_w := width / panels
	for i in panels:
		var x := panel_w * (i + 0.5) - width * 0.5
		K.box(screen, Vector3(panel_w - 0.09, panel_height, 0.06), Color("#afaf8c"), Vector3(x, -panel_height * 0.5, 0))
		for part in [-0.31, 0.0, 0.31]:
			K.box(screen, Vector3(0.052, panel_height, 0.09), TIMBER, Vector3(x + panel_w * part, -panel_height * 0.5, 0))
		K.box(screen, Vector3(panel_w, 0.055, 0.095), TIMBER, Vector3(x, -0.22, 0))
	K.box(screen, Vector3(width, 0.08, 0.11), TIMBER, Vector3(0, -panel_height, 0))
	for side in [-1.0, 1.0]:
		for fold in 4:
			var drop := 1.16 - fold * 0.19
			var x: float = side * (width * 0.5 - 0.08 - fold * 0.11)
			var cloth := Color("#5d7069") if fold % 2 else Color("#75857a")
			K.box(screen, Vector3(0.12, drop, 0.095), cloth, Vector3(x, -drop * 0.5, 0))


## 转角书廊的短檐。倒挂的鹅颈枋和棂格坐在头顶，不挤占挑台。
static func _fret_eave(roof: Node3D, a: Vector2, b: Vector2, level: float, base: Material, tiles: Material) -> void:
	var mid := (a + b) * 0.5
	var width := a.distance_to(b)
	var bay := K.node(roof, Vector3(mid.x, level, mid.y), Vector3(0, -rad_to_deg((b - a).angle()), 0))
	K.box(bay, Vector3(width + 0.06, 0.12, 0.18), TIMBER, Vector3.ZERO)
	K.box(bay, Vector3(width + 0.03, 0.057, 0.11), TRIM, Vector3(0, -0.35, 0))
	var cells := maxi(2, roundi(width / 0.34))
	for i in cells:
		var x := width * ((i + 0.5) / cells - 0.5)
		K.box(bay, Vector3(0.055, 0.31, 0.10), TRIM, Vector3(x, -0.19, 0), Vector3(0, 0, 29))
	_slope(bay, Vector3(0, 0.13, -0.22), width + 0.18, 0.43, 9, base, tiles)


## 短山头保留木构山花、屋脊和两面小青瓦，中间的长跨敞开。
static func _gable(roof: Node3D, center: Vector3, width: float, rise: float, depth: float, base: Material, tiles: Material) -> void:
	var root := K.node(roof, center)
	var half := width * 0.5
	var pitch := rad_to_deg(atan2(rise, half))
	var face := depth * 0.5 - 0.13
	K.prism(root, Vector3(width - 0.24, rise, 0.17), Color("#b79b78"), Vector3(0, rise * 0.5, face))
	K.box(root, Vector3(width, 0.17, 0.20), TIMBER, Vector3(0, 0.02, face + 0.02))
	for side in [-1.0, 1.0]:
		var slope := K.node(root, Vector3(0, rise + 0.015, 0), Vector3(0, side * 90, 0))
		_slope(slope, Vector3.ZERO, depth, half + 0.06, pitch, base, tiles)
		K.box(root, Vector3(sqrt(half * half + rise * rise), 0.12, 0.15), TIMBER,
			Vector3(side * half * 0.5, rise * 0.5, face + 0.09), Vector3(0, 0, -side * pitch))
		K.box(root, Vector3(width * 0.16, 0.06, 0.14), TRIM,
			Vector3(side * width * 0.12, rise * 0.46, face + 0.105))
		K.box(root, Vector3(0.38, 0.11, 0.24), base,
			Vector3(side * (half + 0.11), 0.105, face + 0.06), Vector3(0, 0, side * 19.0))
		K.box(root, Vector3(0.40, 0.11, 0.24), TIMBER, Vector3(side * (half - 0.28), -0.08, face))
		K.box(root, Vector3(0.23, 0.11, 0.20), TRIM, Vector3(side * (half - 0.28), -0.18, face))
	for fraction in [-0.23, 0.0, 0.23]:
		var stud_h: float = rise * (1.0 - absf(fraction) * 2.0)
		K.box(root, Vector3(0.095, stud_h, 0.11), TIMBER, Vector3(width * fraction, stud_h * 0.5, face + 0.11))
	K.box(root, Vector3(0.17, 0.15, depth + 0.20), base, Vector3(0, rise + 0.13, 0))


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


static func _cut_end(room: Node3D, x: float, d: float, h: float, gallery_door: bool) -> void:
	var gap_start := -0.62
	var gap_end := 1.42
	var back := -d * 0.5
	var front := d * 0.5
	if gallery_door:
		for edge in [Vector2(back, gap_start), Vector2(gap_end, front)]:
			K.collider(room, Vector3(0.30, h, edge.y - edge.x), Vector3(x, h * 0.5, (edge.x + edge.y) * 0.5))
		for z in [gap_start, gap_end]:
			K.box(room, Vector3(0.32, 2.60, 0.14), TIMBER, Vector3(x, 1.30, z))
			K.collider(room, Vector3(0.32, 2.60, 0.14), Vector3(x, 1.30, z))
		K.solid(room, Vector3(0.32, 0.20, gap_end - gap_start + 0.24), TIMBER, Vector3(x, 2.60, (gap_start + gap_end) * 0.5))
	else:
		K.collider(room, Vector3(0.3, h, d), Vector3(x, h * 0.5, 0))
	# 阶段式剖面在西廊开口处分成两截，门洞中保留约 1.9 米净宽。
	for part in [[0.0, 0.36, h], [0.36, 0.63, h * 0.62], [0.63, 1.0, h * 0.29]]:
		var a: float = back + part[0] * d
		var b: float = back + part[1] * d
		if gallery_door:
			_gable_wall_piece(room, x, a, minf(b, gap_start), part[2])
			_gable_wall_piece(room, x, maxf(a, gap_end), b, part[2])
		else:
			_gable_wall_piece(room, x, a, b, part[2])


static func _gable_wall_piece(room: Node3D, x: float, a: float, b: float, top: float) -> void:
	if b <= a:
		return
	var z := (a + b) * 0.5
	K.box(room, Vector3(0.30, top, b - a), PLASTER, Vector3(x, top * 0.5, z))
	K.box(room, Vector3(0.39, 0.10, b - a + 0.035), Color("#56605f"), Vector3(x, top + 0.05, z))


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


static func _slope(parent: Node3D, start: Vector3, width: float, run_z: float, pitch: float, base: Material, tiles: Material) -> void:
	var roof := K.node(parent, start, Vector3(pitch, 0, 0))
	var depth := run_z / cos(deg_to_rad(pitch))
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
