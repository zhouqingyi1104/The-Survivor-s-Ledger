extends Node3D
## 外出搜寻的废墟：每处保有自己的空间格局，入口在南。能翻的地方发金光，翻过就暗下去。
## 每个地点有自己的陈设（义庄是棺材、县学是书架……），后墙外有僵尸游荡；阳气外泄满了会有一只扑进来。

const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
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
	_choose_positions(spots)
	_room()
	for k in spots.size():
		_spot_prop(k, spots[k].name)
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
	K.box(self, Vector3(80, 0.2, 80), K.mat(K.SNOW.darkened(0.25), 0.95), Vector3(0, -0.1, 0))
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
		for j in 3:
			var p := center + Vector3(rng.randf_range(-2.5,2.5), 0.08, rng.randf_range(-2.5,2.5))
			K.box(self, Vector3(rng.randf_range(0.2,0.5),rng.randf_range(0.1,0.3),rng.randf_range(0.2,0.5)),K.STONE_DARK,p,Vector3(0,rng.randf_range(0,90),rng.randf_range(-15,15)))
	K.light(self, Color("#8fa2c8"), 0.8, 14.0, Vector3(0, 6, -5))
	_exit_marker()


# Construct the actual connected rooms/yards, not just decoration on one shell.
func _expedition_layout() -> void:
	var cells: Array = FOOTPRINTS.get(point, FOOTPRINTS.rice_ruin)
	var names: Array = ZONE_NAMES.get(point, ZONE_NAMES.rice_ruin)
	var outdoor := point in ["lumber", "granary"]
	var floor_color = K.SNOW if point == "lumber" else (K.EARTH if point == "granary" else (K.STONE if point in ["mortuary", "city_god", "taoist_temple"] else K.WOOD))
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var center := _cell_center(cell)
		K.box(self, Vector3(CELL, 0.06, CELL), floor_color, center + Vector3(0,0.03,0))
		K.text3d(self, str(names[i]), center + Vector3(0,2.1,-2.65), 45, Color("#d4c5a8"), true, 0.005)
		# Regional motifs sit against the walls; central routes stay traversable.
		if point == "lumber":
			for row in 3: K.cyl(self, 0.20, 0.20, 2.2, K.WOOD_LIGHT, center + Vector3(-2.55, 0.2 + row * 0.33, 0), Vector3(90,0,0))
		elif point == "granary" or point == "rice_ruin":
			for j in 3: K.cyl(self, 0.18, 0.26, 0.65, K.RICE_SACK, center + Vector3(-2.5 + j * 0.5, 0.33, -2.5))
		elif point == "pharmacy_ruin":
			for j in 4: K.box(self, Vector3(0.4,0.4,0.15), K.WOOD_LIGHT, center + Vector3(-2.3 + j * 0.55, 1.5, -2.88))
		elif point == "school":
			K.box(self, Vector3(2.1,0.15,0.6), K.WOOD_LIGHT, center + Vector3(0,0.7,-2.6))
		elif point == "mortuary":
			K.box(self, Vector3(1.9,0.65,0.7), K.WOOD, center + Vector3(0,0.4,-2.5))
			K.box(self, Vector3(1.6,1.0,0.05), K.mat(Color("#c9c5b8")), center + Vector3(0,1.9,-2.86))
		else:
			for sx in [-1,1]: K.cyl(self, 0.13, 0.16, 2.1, K.LACQUER, center + Vector3(sx * 2.5,1.05,-2.4))
		# Place recognizable, nonblocking local architecture along each zone's edge.
		match point:
			"rice_ruin":
				K.box(self, Vector3(1.9,0.12,0.7), K.WOOD_LIGHT, center + Vector3(1.5,0.8,-2.5))
				K.box(self, Vector3(0.12,0.8,0.5), K.WOOD, center + Vector3(0.7,0.4,-2.5))
			"city_god":
				K.box(self, Vector3(1.8,0.75,0.6), K.LACQUER, center + Vector3(0,0.38,-2.55))
				K.cyl(self, 0.22,0.32,0.4, K.GOLD, center + Vector3(0,0.98,-2.5))
			"school":
				for j in 3:
					K.box(self, Vector3(0.45,0.1,0.3), K.PAPER, center + Vector3(-2.35,0.5+j*0.25,-2.5))
				K.box(self, Vector3(2.2,0.5,0.1), K.WOOD, center + Vector3(0,1.5,-2.85))
			"pharmacy_ruin":
				for j in 3:
					K.cyl(self, 0.18,0.22,0.45,K.mat(Color("#766e59")),center + Vector3(-2.2+j*0.5,0.25,-2.55))
			"lumber":
				for j in 2:
					K.box(self, Vector3(0.12,0.9,0.12),K.WOOD,center + Vector3(1.5+j*0.8,0.45,-2.5))
				K.box(self, Vector3(1.2,0.12,0.12),K.WOOD_LIGHT,center + Vector3(1.9,0.9,-2.5))
			"mortuary":
				K.box(self, Vector3(0.8,0.12,1.8),K.WOOD_LIGHT,center + Vector3(2.4,0.8,-0.8))
				K.box(self, Vector3(0.6,0.8,1.6),K.WOOD,center + Vector3(2.4,0.4,-0.8))
			"granary":
				for j in 3: K.box(self, Vector3(0.12,1.0,0.12),K.WOOD_LIGHT,center + Vector3(1.5+j*0.5,0.5,-2.55))
				K.box(self, Vector3(1.2,0.1,0.12),K.WOOD,center + Vector3(2.0,0.9,-2.55))
			"taoist_temple":
				K.box(self, Vector3(1.8,0.75,0.6),K.LACQUER,center + Vector3(0,0.38,-2.55))
				for j in 3: K.cyl(self, 0.07,0.1,0.3,K.GOLD,center + Vector3(-0.5+j*0.5,0.92,-2.5))
		# Partial partitions create actual doorways and distinct connected rooms.
		for dir in [Vector2i(1,0), Vector2i(0,-1)]:
			var neighbor: Vector2i = cell + dir
			if not neighbor in cells or cell == cells.back() or neighbor == cells.back(): continue
			var seam := center + Vector3(dir.x * CELL * 0.5,0,dir.y * CELL * 0.5)
			var height := 0.9 if outdoor else 1.45
			for side in [-1,1]:
				var size := Vector3(0.20,height,1.35) if dir.x != 0 else Vector3(1.35,height,0.20)
				var at := seam + (Vector3(0,height/2.0,side*2.325) if dir.x != 0 else Vector3(side*2.325,height/2.0,0))
				K.solid(self,size,K.WOOD if outdoor else K.WALL_SHADE,at)
		for dir in dirs:
			if cell + dir in cells: continue
			var wall_center := center + Vector3(dir.x * CELL * 0.5, 0, dir.y * CELL * 0.5)
			var height := 1.05 if outdoor or dir.y == 1 else 2.2
			var size := Vector3(0.22,height,CELL) if dir.x != 0 else Vector3(CELL,height,0.22)
			K.solid(self, size, K.WOOD if outdoor else K.WALL, wall_center + Vector3(0,height/2.0,0))
	# A complete gate seals the only edge to the final room.
	var across_x := absf(gate_normal.x) > 0.5
	var gate_size := Vector3(0.26, 2.0, CELL) if across_x else Vector3(CELL, 2.0, 0.26)
	_gate_body = K.collider(self, gate_size, gate_center + Vector3(0,1,0))
	_gate_mesh = K.node(self, gate_center)
	K.box(_gate_mesh, gate_size, K.WOOD, Vector3(0,1,0))
	for j in 5:
		var p := Vector3(0,0.12 + j * 0.4,0)
		K.box(_gate_mesh, Vector3(0.32,0.08,CELL) if across_x else Vector3(CELL,0.08,0.32), K.WOOD_LIGHT, p)
	var profile: Dictionary = Expedition.profile(point)
	for key in ["clue_0", "clue_1", "gate"]:
		var at: Vector3 = feature_positions[key]
		var label := str(profile.get("title", "机关")) if key == "gate" else str(profile.get("clues", [])[0 if key == "clue_0" else 1].get("title", "线索"))
		# Distinct found objects carry the clues without printing their solutions.
		if point == "school" or point == "rice_ruin":
			K.box(self, Vector3(0.65,0.08,0.45), K.PAPER, at + Vector3(0,0.18,0))
			K.cyl(self, 0.06, 0.06, 0.7, K.WOOD_LIGHT, at + Vector3(0,0.2,0.2), Vector3(0,0,90))
		elif point == "pharmacy_ruin":
			K.box(self, Vector3(0.55,0.45,0.28), K.WOOD, at + Vector3(0,0.23,0))
			K.box(self, Vector3(0.22,0.13,0.04), K.PAPER, at + Vector3(0,0.3,0.16))
		elif point == "lumber" or point == "granary":
			K.box(self, Vector3(0.65,0.18,0.3), K.WOOD_LIGHT, at + Vector3(0,0.12,0), Vector3(0,20,0))
		else:
			K.box(self, Vector3(0.55,0.65,0.24), K.STONE_DARK, at + Vector3(0,0.33,0))
			K.box(self, Vector3(0.22,0.26,0.03), K.PAPER, at + Vector3(0,0.42,0.13))
		K.text3d(self, label, at + Vector3(0,1.35,0), 50, Color("#e7cd8a"), true, 0.005)
		K.light(self, Color("#d6b879"), 0.5, 2.5, at + Vector3(0,1,0))


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
	if point == "rice_ruin":
		for j in 5:
			for row in 2:
				var offset := Vector3(0,0.3+row*0.6,-1.2+j*0.6) if across_x else Vector3(-1.2+j*0.6,0.3+row*0.6,0)
				K.cyl(visual,0.24,0.3,0.58,K.RICE_SACK,offset)
	else:
		K.box(visual,size,K.WOOD_LIGHT if point == "lumber" else K.WOOD,Vector3(0,0.65,0))
		for i in 3:
			if across_x:
				K.box(visual,Vector3(0.42,0.12,3.25),K.WOOD_LIGHT,Vector3(0,0.35+i*0.4,0))
			else:
				K.box(visual,Vector3(3.25,0.12,0.42),K.WOOD_LIGHT,Vector3(0,0.35+i*0.4,0))
	K.text3d(visual,str(spec.label),Vector3(0,1.55,0),48,Color("#d4c5a8"),true,0.005)
	journey_obstacles[str(spec.stage)] = {"body":body,"visual":visual,"center":center,"normal":normal}


# Stations are physical landmarks with site-specific materials, not UI-only rows.
func _journey_props() -> void:
	for stage in SiteJourney.profile(point).get("stages", []):
		var id := str(stage.id)
		var at: Vector3 = journey_positions[id]
		var n := K.node(self, at)
		var mat = K.STONE if point in ["city_god", "mortuary", "taoist_temple"] else K.WOOD_LIGHT
		if point == "lumber":
			K.cyl(n,0.20,0.20,0.85,mat,Vector3(0,0.16,0),Vector3(0,0,90))
		elif point in ["rice_ruin", "granary"]:
			K.cyl(n,0.18,0.26,0.55,K.RICE_SACK,Vector3(0,0.28,0))
		elif point == "pharmacy_ruin":
			K.cyl(n,0.15,0.2,0.4,K.mat(Color("#766e59")),Vector3(0,0.2,0))
		elif point == "school":
			K.box(n,Vector3(0.7,0.09,0.45),K.PAPER,Vector3(0,0.15,0))
		else:
			K.box(n,Vector3(0.55,0.35,0.4),mat,Vector3(0,0.18,0))
		var ring := TorusMesh.new()
		ring.inner_radius = 0.52
		ring.outer_radius = 0.58
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = K.mat(Color("#7db3a0"),0.6,1.3)
		mi.position.y = 0.06
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


func _coffin(pos: Vector3, rot_y: float, open: bool) -> Node3D:
	var n := K.node(self, pos, Vector3(0, rot_y, 0))
	K.box(n, Vector3(0.8, 0.7, 2.0), K.mat(Color("#2a1f1a"), 0.6), Vector3(0, 0.35, 0))
	var lid := K.box(n, Vector3(0.85, 0.12, 2.05), K.mat(Color("#3a2a22"), 0.6), Vector3(0, 0.76, 0))
	if open:
		lid.position = Vector3(0.6, 0.4, 0.1)
		lid.rotation_degrees = Vector3(0, 12, 60)
	K.collider(n, Vector3(0.8, 0.8, 2.0), Vector3(0, 0.4, 0))
	return n


## 一处可翻的地方：按名字挑道具，脚下一圈金光，头上写名字。
func _spot_prop(k: int, spot_name: String) -> void:
	var pos: Vector3 = _spot_positions[k]
	var n := K.node(self, pos)
	if spot_name.contains("棺") or spot_name.contains("停尸"):
		_coffin(pos, 0.0, false)
	elif spot_name.contains("柜") or spot_name.contains("药"):
		Props.cabinet(n, Vector3(0, 0, -0.3), 0)
	elif spot_name.contains("仓") or spot_name.contains("粮") or spot_name.contains("米"):
		Props.rice_sacks(n, Vector3.ZERO, 5)
	elif spot_name.contains("木"):
		Props.wood_pile(n, Vector3.ZERO, 6)
	elif spot_name.contains("田"):
		K.box(n, Vector3(1.6, 0.2, 1.6), K.EARTH, Vector3(0, 0.1, 0))
		for c in 4:
			K.sphere(n, 0.1, K.mat(Color("#8a3b22"), 0.3), Vector3(-0.4 + c * 0.27, 0.25, 0), Vector3(1, 0.4, 1), true)
	elif spot_name.contains("车"):
		K.box(n, Vector3(1.2, 0.5, 2.0), K.WOOD_LIGHT, Vector3(0, 0.6, 0))
		for sx in [-1, 1]:
			K.cyl(n, 0.4, 0.4, 0.1, K.WOOD, Vector3(sx * 0.68, 0.4, 0), Vector3(0, 0, 90))
	elif spot_name.contains("铺盖"):
		K.box(n, Vector3(1.0, 0.2, 1.9), K.CLOTH_BLUE, Vector3(0, 0.1, 0))
	elif spot_name.contains("案") or spot_name.contains("桌") or spot_name.contains("台") or spot_name.contains("供") or spot_name.contains("香"):
		K.box(n, Vector3(1.6, 0.08, 0.8), K.WOOD, Vector3(0, 0.82, 0))
		for sx in [-1, 1]:
			K.box(n, Vector3(0.1, 0.8, 0.7), K.WOOD, Vector3(sx * 0.7, 0.4, 0))
		K.box(n, Vector3(0.4, 0.2, 0.3), K.WOOD_LIGHT, Vector3(0.3, 0.96, 0))
	else:
		K.box(n, Vector3(1.0, 0.7, 0.7), K.WOOD, Vector3(0, 0.35, 0))
		K.box(n, Vector3(1.05, 0.1, 0.75), K.WOOD_LIGHT, Vector3(0, 0.74, 0))
	K.collider(n, Vector3(1.2, 1.0, 1.0), Vector3(0, 0.5, 0))
	var glow := K.node(n)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.05
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = K.mat(Color("#ffc65a"), 0.5, 3.0)
	ring_mi.position.y = 0.05
	glow.add_child(ring_mi)
	K.light(glow, Color("#ffc65a"), 0.9, 3.5, Vector3(0, 1.4, 0))
	var label := K.text3d(n, spot_name, Vector3(0, 1.8, 0), 56, Color("#ffe3a0"), true, 0.005)
	_spots.append({"pos": pos, "glow": glow, "label": label, "name": spot_name})


func sync(run: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty():
		return
	_unlocked = bool(Expedition.state(run).get("unlocked", false))
	_journey_enabled = not bool(ex.get("only_investigate", false))
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
