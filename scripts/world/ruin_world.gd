extends Node3D
## 外出搜寻的废墟：每处保有自己的空间格局，入口在南。能翻的地方发金光，翻过就暗下去。
## 每个地点有自己的陈设（义庄是棺材、县学是书架……），后墙外有僵尸游荡；阳气外泄满了会有一只扑进来。

const Craft = preload("res://scripts/world/building_craft.gd")
const Assets = preload("res://scripts/world/assets.gd")
const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const FieldProps = preload("res://scripts/world/field_props.gd")
const CaseScene = preload("res://scripts/world/side_case_scene.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Figure = preload("res://scripts/world/character.gd")
const Data = preload("res://scripts/core/data.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const SiteJourney = preload("res://scripts/core/site_journey.gd")

const ENTRY := Vector3(0, 0, 5.2)
const SPOT_RADIUS := 1.7

var sky: Dictionary
var point := ""
var player_ref: Node3D
var _spots := []
var _wanderers := []
var _hunter: Node3D
# Each site is a different connected footprint. The last cell is a dead-end
# behind the gate, so the locked area cannot be reached by walking around it.
const CELL := 6.0
const FOOTPRINTS := {
	"rice_ruin": [Vector2i(0,0), Vector2i(0,-1), Vector2i(-1,-1), Vector2i(-1,-2), Vector2i(1,0), Vector2i(1,-1), Vector2i(1,-2), Vector2i(0,-2), Vector2i(-2,-1)],
	"city_god": [Vector2i(0,0), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(1,-1), Vector2i(1,-2), Vector2i(0,-2), Vector2i(-1,-2), Vector2i(-2,0)],
	"school": [Vector2i(0,0), Vector2i(0,-1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(-2,-1), Vector2i(2,-1), Vector2i(0,-2)],
	"pharmacy_ruin": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,-2), Vector2i(0,-2), Vector2i(-2,-1)],
	"lumber": [Vector2i(0,0), Vector2i(-1,0), Vector2i(1,0), Vector2i(1,-1), Vector2i(-1,-1), Vector2i(-2,-1), Vector2i(-2,0), Vector2i(0,-1), Vector2i(2,-1)],
	"mortuary": [Vector2i(0,0), Vector2i(0,-1), Vector2i(1,-1), Vector2i(2,-1), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(2,0), Vector2i(3,0), Vector2i(-2,0), Vector2i(-2,-1), Vector2i(1,-2)],
	"granary": [Vector2i(0,0), Vector2i(-1,0), Vector2i(1,0), Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(1,-2), Vector2i(0,-2), Vector2i(2,0), Vector2i(2,-1), Vector2i(-2,-1)],
	"taoist_temple": [Vector2i(0,0), Vector2i(0,-1), Vector2i(0,-2), Vector2i(1,-2), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(-2,-1), Vector2i(-2,-2), Vector2i(-2,0), Vector2i(-3,0), Vector2i(2,-2)],
}
const ZONE_NAMES := {
	"rice_ruin": ["破店门", "量米堂", "账房走廊", "后院", "临街铺面", "粮车道", "伙计房", "筛粮间", "后粮仓"],
	"city_god": ["庙门", "香客院", "偏殿庭", "城隍正殿", "香亭", "侧廊", "祭台", "庙祝居", "封存供库"],
	"school": ["县学门", "讲堂", "西斋", "东斋", "门房", "前廊", "教习房", "学舍", "藏书阁"],
	"pharmacy_ruin": ["回春堂", "看诊堂", "炮制小巷", "等候室", "晾药房", "后堂", "药碾房", "掌柜房", "封药间"],
	"lumber": ["场门", "堆料场", "运木道", "锯棚", "工棚", "铁匠角", "卸料坪", "木工坊", "旧木库"],
	"mortuary": ["义庄门", "停灵堂", "守庄人房", "偏房", "前庭", "供案间", "停棺处", "守夜舍", "送葬径", "白幡院", "封棺室"],
	"granary": ["官仓门", "西仓道", "运粮道", "仓吏房", "粮车坪", "军粮间", "储粮架", "装卸道", "粮车棚", "巡仓径", "封粮仓"],
	"taoist_temple": ["山门", "石阶", "道观前庭", "偏殿", "外院", "经阁", "灵田", "静室", "松风径", "望山台", "丹房"],
}

# Map narrative actions to rooms that match their descriptions where space permits.
const JOURNEY_ROOMS := {
	"rice_ruin": [1,2,3], "city_god": [1,6,2], "school": [1,2,3],
	"pharmacy_ruin": [1,6,5,7,2], "lumber": [4,2,3,5,1],
	"mortuary": [1,9,5,2,6,3,7,4], "granary": [4,2,8,3,7,1,5,9],
	"taoist_temple": [0,2,5,6,3,7,9,8],
}

var feature_positions: Dictionary = {}
# Ids are the authoritative SiteJourney stage ids, never display text.
var journey_positions: Dictionary = {}
var _journey_nodes: Dictionary = {}
var _journey_enabled := false
# These are optional shortcuts; each has another route to both sides.
const JOURNEY_OBSTACLES := {
	"rice_ruin": {"stage":"s1", "from":Vector2i(0,-1), "to":Vector2i(-1,-1), "label":"堵路粮袋"},
	"school": {"stage":"s1", "from":Vector2i(0,-1), "to":Vector2i(-1,-1), "label":"倾倒书架"},
	"lumber": {"stage":"s1", "from":Vector2i(1,0), "to":Vector2i(1,-1), "label":"倾斜木架"},
	"granary": {"stage":"s4", "from":Vector2i(0,-1), "to":Vector2i(0,-2), "label":"堵门杂物"},
}
var journey_obstacles: Dictionary = {}
var gate_center := Vector3.ZERO
# Direction points from the public area towards the locked room.
var gate_normal := Vector3.ZERO
var locked_spot_index := -1
var _spot_positions: Array = []
var _gate_body: StaticBody3D
var _gate_mesh: Node3D
var _feature_markers: Node3D
var _unlocked := false

func _cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0, 3.0 + c.y * CELL)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _choose_positions(spots: Array) -> void:
	var cells: Array = FOOTPRINTS.get(point, FOOTPRINTS.rice_ruin)
	var locked: Vector2i = cells.back()
	var parent := Vector2i.ZERO
	for cell in cells.slice(0, cells.size() - 1):
		if absi(cell.x - locked.x) + absi(cell.y - locked.y) == 1:
			parent = cell
			break
	gate_normal = (_cell_center(locked) - _cell_center(parent)).normalized()
	gate_center = (_cell_center(locked) + _cell_center(parent)) * 0.5
	feature_positions = {"gate": gate_center - gate_normal * 1.1}
	var candidates: Array = []
	for cell in cells.slice(0, cells.size() - 1):
		var center := _cell_center(cell)
		for offset in [Vector3(-1.8,0,-1.8), Vector3(1.8,0,-1.8), Vector3(-1.8,0,1.8), Vector3(1.8,0,1.8)]:
			var p: Vector3 = center + offset
			if _flat_distance(p, ENTRY) >= 3.3 and _flat_distance(p, feature_positions.gate) >= 3.4:
				candidates.append(p)
	var used: Array = [ENTRY, feature_positions.gate]
	for key in ["clue_0", "clue_1"]:
		var choice := Vector3.INF
		var score := -1.0
		for candidate in candidates:
			var ok := true
			for existing in used:
				if _flat_distance(candidate, existing) < 3.4: ok = false
			# The second clue is deliberately elsewhere in the site.
			var value := 0.0 if key == "clue_0" else _flat_distance(candidate, used.back())
			if ok and value > score:
				choice = candidate
				score = value
		assert(choice != Vector3.INF, "No distinct clue position for " + point)
		feature_positions[key] = choice
		used.append(choice)
	for i in spots.size():
		var spot: Dictionary = spots[i]
		if spot.has("side_case"):
			_spot_positions.append(Vector3.INF)
			continue
		var is_signature := str(spot.get("name", "")) == str(Explore.SITE_SPOTS.get(point, "")) and not spot.has("mainline") and not spot.has("neighbor")
		if is_signature:
			locked_spot_index = i
			_spot_positions.append(_cell_center(locked))
			continue
		var choice := Vector3.INF
		for candidate in candidates:
			var ok := true
			for existing in used:
				if _flat_distance(candidate, existing) < 3.0: ok = false
			if ok:
				choice = candidate
				break
		assert(choice != Vector3.INF, "No distinct search position for " + point)
		_spot_positions.append(choice)
		used.append(choice)
	_choose_journey_positions(cells, used)
	# 先给原有搜点、现场行动、机关留足位置；同行调查另外找一间可直接走到的屋子。
	for i in spots.size():
		if spots[i].has("side_case"):
			_spot_positions[i] = _case_position(cells.slice(0, cells.size() - 1), used)


func _case_position(cells: Array, occupied: Array) -> Vector3:
	var result := Vector3.ZERO
	var best := -1.0
	for cell in cells:
		var center := _cell_center(cell)
		for offset in [Vector3.ZERO, Vector3(1.15, 0, 0), Vector3(-1.15, 0, 0), Vector3(0, 0, 1.15), Vector3(0, 0, -1.15)]:
			var pos: Vector3 = center + offset
			var clearance := INF
			for other in occupied:
				clearance = minf(clearance, _flat_distance(pos, other))
			if clearance > best:
				best = clearance
				result = pos
	return result

func _choose_journey_positions(cells: Array, used: Array) -> void:
	var stages: Array = SiteJourney.profile(point).get("stages", [])
	var occupied_cells: Array = []
	var public_cells := cells.slice(0, cells.size() - 1)
	for stage_index in stages.size():
		var stage: Dictionary = stages[stage_index]
		var choices: Array = JOURNEY_ROOMS.get(point, [])
		var preferred: Vector2i = public_cells[choices[stage_index]] if stage_index < choices.size() else Vector2i(999,999)
		var best := Vector3.INF
		var best_cell := Vector2i.ZERO
		var best_score := -1.0
		for cell in public_cells:
			var center := _cell_center(cell)
			for offset in [Vector3.ZERO,Vector3(-1.9,0,-1.9),Vector3(1.9,0,-1.9),Vector3(-1.9,0,1.9),Vector3(1.9,0,1.9),Vector3(0,0,-1.9),Vector3(0,0,1.9),Vector3(-1.9,0,0),Vector3(1.9,0,0)]:
				var candidate: Vector3 = center + offset
				var min_d := 999.0
				for p in used: min_d = minf(min_d, _flat_distance(candidate, p))
				if min_d < 2.9: continue
				# Visit a fresh room before placing a second station in one room.
				var score := min_d + (1000.0 if not cell in occupied_cells else 0.0) + (200.0 if cell == preferred else 0.0)
				if score > best_score:
					best_score = score
					best = candidate
					best_cell = cell
		assert(best != Vector3.INF, "No distinct journey station for " + point + ": " + str(stage.id))
		journey_positions[str(stage.id)] = best
		used.append(best)
		occupied_cells.append(best_cell)

func setup(pid: String, spots: Array) -> void:
	point = pid
	sky = SkyKit.make(self, 12.0)
	SkyKit.apply(sky, "ruin", 160)
	# 从断壁上方落下的冷光照到木纹、灰缝；暖色线索灯仍各自只照一小块。
	sky.sun.light_energy = 0.38
	sky.sun.light_color = Color("#acbbd0")
	sky.sun.rotation_degrees = Vector3(-41, -30, 0)
	sky.env.ambient_light_energy = 0.54
	_choose_positions(spots)
	_room()
	for k in spots.size():
		_spot_prop(k, spots[k])
	var p: Dictionary = Data.table("map_points")[pid]
	for k in maxi(1, int(p.danger) - 1):
		var f: Node3D = Figure.new()
		add_child(f)
		f.setup("jiangshi")
		f.hopping = true
		f.speed_scale = 0.7
		f.position = Vector3(-6 + k * 5.0, 0, -8.5)
		_wanderers.append({"fig": f, "dir": 1.0 if k % 2 == 0 else -1.0})


func _room() -> void:
	K.box(self, Vector3(80, 0.2, 80), Assets.pbr("snow_02", 5.5, Color("#bcc5c7")), Vector3(0, -0.1, 0))
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 0.2, 80)
	cs.shape = shape
	floor_body.position.y = -0.1
	floor_body.add_child(cs)
	add_child(floor_body)
	_expedition_layout()
	_make_journey_obstacle()
	_journey_props()
	# Local rubble belongs to each traversable part of the site, not the void.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(point)
	for cell in FOOTPRINTS.get(point, FOOTPRINTS.rice_ruin):
		var center := _cell_center(cell)
		var side := -1 if rng.randi_range(0, 1) == 0 else 1
		var at := center + Vector3(side * rng.randf_range(1.85, 2.48), 0.059, rng.randf_range(-2.2, 2.2))
		for j in 3:
			var offset := Vector3(rng.randf_range(-0.34, 0.34), 0, rng.randf_range(-0.40, 0.40))
			FieldProps.rubble(self, at + offset, j, rng.randf_range(0.56, 1.21), rng.randf_range(0.0, TAU))
	K.light(self, Color("#8fa2c8"), 0.8, 14.0, Vector3(0, 6, -5))
	_exit_marker()
	var keep: Array = [_gate_mesh]
	for obstacle in journey_obstacles.values():
		keep.append(obstacle.visual)
	for stage in _journey_nodes.values():
		keep.append(stage.node)
	K.merge_static(self, keep)


# Construct the actual connected rooms/yards, not just decoration on one shell.
func _expedition_layout() -> void:
	var cells: Array = FOOTPRINTS.get(point, FOOTPRINTS.rice_ruin)
	var names: Array = ZONE_NAMES.get(point, ZONE_NAMES.rice_ruin)
	var outdoor := point in ["lumber", "granary"]
	var floor_material: Material = {
		"lumber": Assets.pbr("brown_mud_dry", 3.4, Color("#aeaca2")), "granary":Assets.pbr("brown_mud_dry", 2.9, Color("#b2a391")),
		"mortuary": Assets.pbr("cobblestone_floor_08", 3.2, Color("#929a9c")), "city_god":Assets.pbr("square_cobblestone", 3.4, Color("#b5aea6")),
		"taoist_temple":Assets.pbr("cobblestone_floor_08", 3.7, Color("#bec1b6"))}.get(point, Assets.pbr("brown_planks_09", 2.85, Color("#a79a85")))
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var center := _cell_center(cell)
		K.box(self, Vector3(CELL, 0.06, CELL), floor_material, center + Vector3(0, 0.03, 0))
		K.text3d(self, str(names[i]), center + Vector3(0,2.1,-2.65), 45, Color("#d4c5a8"), true, 0.005)
		# Regional motifs sit against the walls; central routes stay traversable.
		if point == "lumber" and i in [1, 3, 6, 8]:
			Props.wood_pile(self, center + Vector3(-2.36, 0.059, 0), 7 + i % 3, 90.0)
		elif point in ["granary","rice_ruin"] and i in [1, 4, 7, cells.size() - 1]:
			Props.rice_sacks(self, center + Vector3(-2.15, 0, -2.45), 3)
		elif point == "pharmacy_ruin" and i in [0, 1, 5, 8]:
			for j in 4: K.box(self, Vector3(0.50, 0.36, 0.27), K.WOOD_LIGHT, center + Vector3(-2.3 + j * 0.50, 1.42, -2.8))
			for j in 4:
				K.box(self, Vector3(0.12, 0.07, 0.038), K.PAPER, center + Vector3(-2.3 + j * 0.50, 1.47, -2.645))
				K.cyl(self, 0.028, 0.036, 0.034, K.GOLD, center + Vector3(-2.3 + j * 0.50, 1.35, -2.641), Vector3(90, 0, 0), 8)
			K.box(self, Vector3(2.17, 1.07, 0.39), K.WOOD, center + Vector3(-1.56, 0.58, -2.81))
			K.box(self, Vector3(2.22, 0.11, 0.45), K.WOOD_LIGHT, center + Vector3(-1.56, 1.18, -2.78))
		elif point == "school" and i in [1, 2, 3, 6, 8]:
			K.box(self, Vector3(2.1,0.15,0.6), K.WOOD_LIGHT, center + Vector3(0,0.7,-2.6))
			for x in [-0.88, 0.88]:
				K.box(self, Vector3(0.12, 0.62, 0.46), K.WOOD, center + Vector3(x, 0.36, -2.6))
		elif point == "mortuary" and i in [1, 5, 6, 10]:
			var bier := K.node(self, center + Vector3(0, 0.059, -2.4), Vector3(0, 90, 0))
			FieldProps.coffin(bier, false)
		elif point in ["taoist_temple","city_god"] and i in [0, 3, 4, 6]:
			for sx in [-1, 1]:
				K.cyl(self, 0.13, 0.16, 2.1, K.LACQUER, center + Vector3(sx * 2.5, 1.05, -2.4))
		# Place recognizable, nonblocking local architecture along each zone's edge.
		match point:
			"rice_ruin":
				if i in [1, 2, 6]:
					K.box(self, Vector3(1.9, 0.12, 0.7), K.WOOD_LIGHT, center + Vector3(1.5, 0.8, -2.5))
					for x in [0.70, 2.30]:
						K.box(self, Vector3(0.12, 0.8, 0.5), K.WOOD, center + Vector3(x, 0.4, -2.5))
			"city_god":
				if i in [3, 5, 6]:
					FieldProps.incense_table(K.node(self, center + Vector3(0, 0.059, -2.42)), false)
			"school":
				if i in [1, 2, 3, 8]:
					for j in 3:
						FieldProps.book(self, center + Vector3(0.29 - j * 0.015, 0.775 + 0.058 * j, -2.58), 9 - 4 * j)
					FieldProps.book(self, center + Vector3(-0.48, 0.775, -2.61), -13)
			"pharmacy_ruin":
				if i in [2, 4, 6, 8]:
					Props.clay_jar(self, center + Vector3(-2.3, 0, -2.35), 0.50)
					if i == 8:
						Props.clay_jar(self, center + Vector3(-1.72, 0, -2.49), 0.38)
				elif i in [1, 3]:
					for x in [-0.60, 0.60]:
						K.box(self, Vector3(0.14, 0.40, 0.25), K.WOOD, center + Vector3(x, 0.20, -2.41))
					K.box(self, Vector3(1.60, 0.09, 0.32), K.WOOD_LIGHT, center + Vector3(0, 0.445, -2.41))
			"lumber":
				if i in [1, 3, 5, 7]:
					for j in 2:
						K.box(self, Vector3(0.12, 0.9, 0.12), K.WOOD, center + Vector3(1.5 + j * 0.8, 0.45, -2.5))
					K.box(self, Vector3(1.2, 0.12, 0.12), K.WOOD_LIGHT, center + Vector3(1.9, 0.9, -2.5))
			"mortuary":
				if i in [1, 6, 10]:
					FieldProps.table(K.node(self, center + Vector3(2.38, 0.059, -0.8), Vector3(0, 90, 0)), false)
			"granary":
				if i in [2, 5, 6, 9]:
					var pallet := K.node(self, center + Vector3(1.67, 0.059, -2.38))
					for x in [-0.68, 0.68]:
						K.box(pallet, Vector3(0.16, 0.18, 0.81), K.WOOD, Vector3(x, 0.09, 0))
					for j in 4:
						K.box(pallet, Vector3(1.77, 0.055, 0.183), K.WOOD_LIGHT, Vector3(0, 0.205, (j - 1.5) * 0.2))
					Props.rice_sacks(pallet, Vector3.UP * 0.2325, 3 + i % 3)
			"taoist_temple":
				if i in [2, 3, 5, 10]:
					FieldProps.incense_table(K.node(self, center + Vector3(0, 0.059, -2.42)), true)
		# Partial partitions create actual doorways and distinct connected rooms.
		for dir in [Vector2i(1,0), Vector2i(0,-1)]:
			var neighbor: Vector2i = cell + dir
			if not neighbor in cells or cell == cells.back() or neighbor == cells.back(): continue
			var seam := center + Vector3(dir.x * CELL * 0.5,0,dir.y * CELL * 0.5)
			var height := 0.9 if outdoor else 1.45
			for side in [-1,1]:
				var at := seam + (Vector3(0,height/2.0,side*2.325) if dir.x != 0 else Vector3(side*2.325,height/2.0,0))
				Craft.ruined_bay(self, at - Vector3.UP * height / 2.0, dir.x != 0, 1.35, height, outdoor, i + side)
		for dir in dirs:
			if cell + dir in cells: continue
			var wall_center := center + Vector3(dir.x * CELL * 0.5, 0, dir.y * CELL * 0.5)
			var height := 1.05 if outdoor or dir.y == 1 else 2.2
			Craft.ruined_bay(self, wall_center, dir.x != 0, CELL, height, outdoor, i * 3 + dir.x - dir.y)
	# A complete gate seals the only edge to the final room.
	var across_x := absf(gate_normal.x) > 0.5
	var gate_size := Vector3(0.26, 2.0, CELL) if across_x else Vector3(CELL, 2.0, 0.26)
	_gate_body = K.collider(self, gate_size, gate_center + Vector3(0,1,0))
	_gate_mesh = K.node(self, gate_center)
	FieldProps.gate(_gate_mesh, CELL, across_x)
	var profile: Dictionary = Expedition.profile(point)
	_feature_markers = K.node(self)
	for key in ["clue_0", "clue_1", "gate"]:
		var at: Vector3 = feature_positions[key]
		var label := str(profile.get("title", "机关")) if key == "gate" else str(profile.get("clues", [])[0 if key == "clue_0" else 1].get("title", "线索"))
		FieldProps.clue(K.node(self, at), point, key)
		K.text3d(_feature_markers, label, at + Vector3(0,1.35,0), 50, Color("#e7cd8a"), true, 0.005)
		K.light(_feature_markers, Color("#d6b879"), 0.5, 2.5, at + Vector3(0,1,0))


func _make_journey_obstacle() -> void:
	if not JOURNEY_OBSTACLES.has(point): return
	var spec: Dictionary = JOURNEY_OBSTACLES[point]
	var a: Vector3 = _cell_center(spec.from)
	var b: Vector3 = _cell_center(spec.to)
	var center := (a + b) * 0.5
	var normal := (b - a).normalized()
	var across_x := absf(normal.x) > 0.5
	# The object fills the doorway, not the parallel bypass route.
	var size := Vector3(0.38,1.3,3.3) if across_x else Vector3(3.3,1.3,0.38)
	var body := K.collider(self,size,center + Vector3(0,0.65,0))
	var visual := K.node(self,center)
	var cargo := K.node(visual, Vector3.ZERO, Vector3(0, 90 if across_x else 0, 0))
	if point == "rice_ruin":
		for i in 4:
			var stack := Props.rice_sacks(cargo, Vector3((i - 1.5) * 0.79, 0, 0), 13)
			stack.scale = Vector3(0.63, 1.38, 0.55)
	else:
		for i in 3:
			var crate := K.node(cargo, Vector3((i - 1) * 1.05, 0, 0), Vector3(0, (i - 1) * 4, 0))
			crate.scale = Vector3(1.12, 1.14 + i * 0.09, 0.78)
			FieldProps.chest(crate)
		Props.wood_pile(cargo, Vector3(0.10, 0.80, 0), 3)
	K.text3d(visual,str(spec.label),Vector3(0,1.55,0),48,Color("#d4c5a8"),true,0.005)
	journey_obstacles[str(spec.stage)] = {"body":body,"visual":visual,"center":center,"normal":normal}


# Stations are physical landmarks with site-specific materials, not UI-only rows.
func _journey_props() -> void:
	for stage in SiteJourney.profile(point).get("stages", []):
		var id := str(stage.id)
		var at: Vector3 = journey_positions[id]
		var n := K.node(self, at)
		FieldProps.station(n, point, id)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.536
		ring.outer_radius = 0.563
		ring.rings = 36
		ring.ring_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = K.mat(Color("#98c3ad"), 0.6, 0.60)
		mi.position.y = 0.078
		n.add_child(mi)
		var label := K.text3d(n,str(stage.title),Vector3(0,1.1,0),48,Color("#c3e0ce"),true,0.005)
		_journey_nodes[id] = {"node":n,"label":label,"title":str(stage.title)}


## 出口只作可见标识，不改变入口或通路的碰撞。
func _exit_marker() -> void:
	for sx in [-1, 1]:
		K.box(self, Vector3(0.14, 2.25, 0.14), K.WOOD_LIGHT, Vector3(sx * 1.3, 1.125, 5.85))
	K.box(self, Vector3(2.75, 0.16, 0.16), K.WOOD_LIGHT, Vector3(0, 2.2, 5.85))
	K.text3d(self, "出口 · 回宅", Vector3(0, 2.55, 5.75), 52, Color("#e6d5ac"), true, 0.008)
	# 一条低矮的石槛可从房间另一侧辨认方向，角色仍能走过。
	K.box(self, Vector3(2.0, 0.025, 0.45), K.mat(Color("#c2b18e")), Vector3(0, 0.045, 5.0))


## 一处可翻的地方：按名字挑道具，脚下一圈金光，头上写名字。
func _spot_prop(k: int, spot: Dictionary) -> void:
	var pos: Vector3 = _spot_positions[k]
	var n := K.node(self, pos)
	var spot_name := str(spot.name)
	var scene: CaseScene
	if spot.has("side_case"):
		scene = CaseScene.new()
		n.add_child(scene)
		scene.setup(spot)
	else:
		FieldProps.spot(n, spot_name)
	K.collider(n, Vector3(1.2, 1.0, 1.0), Vector3(0, 0.5, 0))
	var glow := K.node(n)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.973
	ring.outer_radius = 1.012
	ring.rings = 44
	ring.ring_segments = 6
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = K.mat(Color("#ddb477"), 0.5, 0.65)
	ring_mi.position.y = 0.078
	glow.add_child(ring_mi)
	K.light(glow, Color("#ffe5c6"), 0.82, 3.1, Vector3(0, 1.4, 0))
	var label := K.text3d(n, spot_name, Vector3(0, 1.8, 0), 56, Color("#ffe3a0"), true, 0.005)
	if scene != null:
		label.position.y = 2.85
		label.font_size = 46
	_spots.append({"pos": pos, "glow": glow, "label": label, "name": spot_name, "case_scene": scene})


func sync(run: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty():
		return
	_unlocked = bool(Expedition.state(run).get("unlocked", false))
	_journey_enabled = not bool(ex.get("only_investigate", false))
	_feature_markers.visible = _journey_enabled or not ex.spots.any(func(spot: Dictionary) -> bool: return spot.has("side_case"))
	var journey: Dictionary = SiteJourney.state(run)
	for id in journey_obstacles:
		var cleared := str(journey.get("completed", {}).get(id, "")) == "careful"
		journey_obstacles[id].visual.visible = not cleared
		journey_obstacles[id].body.set_collision_layer_value(1, not cleared)
	for id in _journey_nodes:
		_journey_nodes[id].node.visible = _journey_enabled
		_journey_nodes[id].label.text = str(_journey_nodes[id].title) + (" · 已查" if journey.get("completed", {}).has(id) else "")
	if is_instance_valid(_gate_mesh): _gate_mesh.visible = not _unlocked
	if is_instance_valid(_gate_body):
		_gate_body.set_collision_layer_value(1, not _unlocked)
	for k in mini(_spots.size(), ex.spots.size()):
		var done: bool = ex.spots[k].done or ex.caught
		var scene: CaseScene = _spots[k].case_scene
		if scene != null:
			var busy: Dictionary = run.get("busy", {})
			var in_progress: bool = busy.get("kind") == "case_search" and busy.get("data", {}).get("id") == ex.spots[k].side_case
			scene.sync(in_progress, bool(ex.spots[k].done), bool(ex.caught))
			_spots[k].glow.visible = not done
			var state := "（已取证）" if ex.spots[k].done else ("（合查中）" if in_progress else "")
			_spots[k].label.text = "%s · 同行\n%s%s" % [ex.spots[k].person, _spots[k].name, state]
			continue
		var marker := str(ex.spots[k].get("mainline", ""))
		var work: Dictionary = run.get("mainline", {}).get("work", {})
		var working: bool = marker != "" and str(work.get("action", "")) == "search_" + marker and not ex.caught
		var loot = ex.spots[k].get("loot", {})
		var has_loot := false
		if loot is Dictionary:
			for amount in loot.values():
				if int(amount) > 0: has_loot = true; break
		var available: bool = ex.spots[k].done and has_loot and not ex.caught
		_spots[k].glow.visible = not done or working or available
		var status := "（调查中）" if working else ("（已封阵）" if marker == "ritual" and ex.spots[k].done else ("（已调查）" if marker != "" and ex.spots[k].done else ("（仍有物资）" if available else ("（已翻过）" if ex.spots[k].done else ""))))
		var special: bool = not done and not ex.get("site_used", false) and not ex.get("curfew_due", false) and not ex.spots[k].has("mainline") and not ex.spots[k].has("neighbor") and str(ex.spots[k].get("name", "")) == str(Explore.SITE_SPOTS.get(point, ""))
		var special_text := " · 特色" if special else ""
		_spots[k].label.text = _spots[k].name + special_text + status
		_spots[k].label.modulate = Color("#9a948a") if done and not working and not available else Color("#ffe3a0")
	if ex.caught and _hunter == null:
		_hunter = Figure.new()
		add_child(_hunter)
		_hunter.setup("jiangshi")
		_hunter.hopping = true
		_hunter.speed_scale = 1.4
		_hunter.position = Vector3(0, 0, -6.5)
		Sfx.play("ling", -2.0, 0.0)
		Sfx.play_at("zombie", _hunter.position + Vector3(0, 1.6, 0), self, 4.0)


## 最近的可翻处下标；在门口返回 -2；都不在返回 -1。
func _visible_from(pos: Vector3, target: Vector3, allow_target_body := false) -> bool:
	if not is_inside_tree(): return false
	var from := Vector3(pos.x, 0.8, pos.z)
	var to := Vector3(target.x, 0.8, target.z)
	if from.distance_to(to) < 0.02: return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if is_instance_valid(player_ref) and player_ref is CollisionObject3D:
		query.exclude = [player_ref.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	# Search props have their own small collider; walls cannot be bypassed by E.
	return allow_target_body and (hit.position as Vector3).distance_to(to) < 0.9

func spot_position(idx: int) -> Vector3:
	return _spot_positions[idx]


func nearest(pos: Vector3) -> int:
	var flat := Vector3(pos.x, 0, pos.z)
	if flat.distance_to(ENTRY) < 1.6 and _visible_from(flat, ENTRY): return -2
	var best := -1
	var best_d := SPOT_RADIUS
	for k in _spots.size():
		if k == locked_spot_index and not _unlocked: continue
		var d := flat.distance_to(_spots[k].pos)
		if d < best_d and _visible_from(flat, _spots[k].pos, true):
			best = k
			best_d = d
	return best

func nearest_feature(pos: Vector3) -> String:
	if not _feature_markers.visible: return ""
	var best := ""
	var best_d := 1.35
	for key in ["clue_0", "clue_1", "gate"]:
		var target: Vector3 = feature_positions.get(key, Vector3.INF)
		var d := _flat_distance(pos, target)
		if d < best_d and _visible_from(pos, target):
			best = key
			best_d = d
	return best


func nearest_journey(pos: Vector3) -> String:
	if not _journey_enabled: return ""
	var best := ""
	var best_d := 1.1
	for id in journey_positions:
		var target: Vector3 = journey_positions[id]
		var d := _flat_distance(pos,target)
		if d < best_d and _visible_from(pos,target):
			best = str(id)
			best_d = d
	return best


func _process(delta: float) -> void:
	for w in _wanderers:
		var f: Node3D = w.fig
		f.position.x += w.dir * delta * 1.2
		if absf(f.position.x) > 9.0:
			w.dir = -w.dir
		f.rotation.y = PI / 2.0 if w.dir > 0 else -PI / 2.0
	if _hunter != null and player_ref != null:
		var to := player_ref.global_position - _hunter.position
		to.y = 0
		if to.length() > 0.9:
			_hunter.position += to.normalized() * delta * 3.2
			_hunter.face(to, 1.0)
