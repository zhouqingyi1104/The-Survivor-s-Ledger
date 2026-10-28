extends Node3D
## 宅院场景：徽派院落。北面正屋（神龛、床榻、书案），西厢灶房，东厢工坊，院中水井、菜畦、梅树、石桌，
## 南墙正中是大门，右侧一扇漏窗。门外是街，守具摆在街上，尸潮从街两头来。
## sync(run) 把局面画出来：存货堆多高、门窗破到什么程度、布了哪些守具、菜长到哪了、现在几时。
## 可交互的物件都登记在 spot_nodes 里（碰撞体带 "spot" 标记），界面靠它做悬停描边、点击菜单和头顶标签。

const K = preload("res://scripts/world/kit.gd")
const Arch = preload("res://scripts/world/arch.gd")
const Props = preload("res://scripts/world/props.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Home = preload("res://scripts/core/home.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const NeighborHome = preload("res://scripts/core/neighbor_home.gd")
const FloorWorld = preload("res://scripts/world/home_floor.gd")
const DecorationWorld = preload("res://scripts/world/home_decoration.gd")
const Assets = preload("res://scripts/world/assets.gd")
const Figure = preload("res://scripts/world/character.gd")
const Surroundings = preload("res://scripts/world/home_surroundings.gd")
# C1 邻宅氛围工厂运行期加载（缺失不影响宅院本体；由 C1 契约守底）。
const AmbiencePath := "res://scripts/world/home_ambience.gd"

const GATE_Z := 7.0
const WINDOW_POS := Vector3(5.6, 1.7, 7.0)
const SPAWN := Vector3(0, 0, 3.0)

## 可交互物：名称、站位（人走到哪儿做事）、头顶标签的位置
const SPOTS := {
	"shrine":  {"name": "神龛",   "stand": Vector3(0, 0, -6.0),    "tag": Vector3(0, 2.9, -7.4)},
	"well":    {"name": "水井",   "stand": Vector3(-3.0, 0, 0.1),  "tag": Vector3(-3.0, 2.6, 1.5)},
	"garden":  {"name": "菜畦",   "stand": Vector3(3.5, 0, -0.1),  "tag": Vector3(3.5, 1.4, 2.3)},
	"gate":    {"name": "大门",   "stand": Vector3(0, 0, 5.8),     "tag": Vector3(0, 3.9, 7.0)},
	"neighbor_home": {"name": "西邻院墙", "stand": Vector3(-8.9, 0, 3.6), "tag": Vector3(-9.65, 2.4, 3.6)},
}
const PLOT_POS := [Vector3(2.6, 0, 1.4), Vector3(4.5, 0, 1.4), Vector3(2.6, 0, 3.3), Vector3(4.5, 0, 3.3)]

var sky: Dictionary
var surroundings: Node3D
var halls := []
var gate: Dictionary
var lanterns := []
var spot_nodes := {}
var nav_region: NavigationRegion3D
var _room_nav := {}
var _window: Node3D
var _dynamic: Dictionary = {}
var _night := false
var _baked := false
var _garden_body: StaticBody3D
var _garden_rows := 0
var _nav_furniture_key := ""
var _current_run := {}
var _side_yard: Node3D
var _side_stage := ""
var _side_lantern := {}
var _floor := "courtyard"
var _floor_rooms := {}
var _outside_nodes: Array[Node3D] = []
var _outside_visibility := {}
var _neighbor_visual: Node3D
var _neighbor_visual_key := ""
var _neighbor_stand_key := ""
var _neighbor_stand := Vector3(-8.9, 0, 3.6)
# C1 邻宅氛围：set_time 缓存阶段/大雪上下文，set_preset 据此投影（不缓存 run 本体）。
var _amb_ctx := {"phase": "post", "pday": 1, "heavy": false}


func _ready() -> void:
	add_to_group("navsrc")
	sky = SkyKit.make(self, 26.0)
	# The overhead camera looks through many metres of fog even at nearby props.
	# Keep the courtyard legible instead of tinting the entire scene grey.
	sky.fog_mul = 0.12
	# C0 四周景物（近邻宅院/街巷、中景屋脊、远景城墙山脊）：视觉隔离根，不进核心合并，
	# 无碰撞/无导航/无灯光；显式列入 merge_static 的 skip。
	surroundings = Surroundings.build(self, {})
	_ground()
	_side_yard = K.node(self, Vector3.ZERO, Vector3.ZERO, "side_yard")
	_buildings()
	_neighbor_wall()
	_neighbor_visual = K.node(self, Vector3.ZERO, Vector3.ZERO, "neighbor_home_visual")
	_furniture()
	_decor()
	for floor_id in ["cellar", "attic", "guest_zhou"]:
		_floor_rooms[floor_id] = FloorWorld.build(self, floor_id)
		_floor_rooms[floor_id].root.visible = false
	for key in ["sacks", "firewood", "wood", "garden", "devices", "extras", "furnish", "decoration"]:
		_dynamic[key] = K.node(self, Vector3.ZERO, Vector3.ZERO, key)
	# 菜畦整块的拾取碰撞（菜苗每次重画，碰撞固定在这里；大小随画出来的畦数变，见 _fit_garden）
	var garden_root := K.node(self, Vector3.ZERO, Vector3.ZERO, "spot_garden")
	_garden_body = K.collider(garden_root, Vector3.ONE, Vector3.ZERO, {"spot": "garden"})
	spot_nodes["garden"] = _dynamic.garden
	# 静态的方块按材质合并；会动、会重画、要描边的留着；四周景物根整树跳过（层内各自合并）
	K.merge_static(self, [gate.node, _window, surroundings, _side_yard, _neighbor_visual, _floor_rooms.cellar.root, _floor_rooms.attic.root, _floor_rooms.guest_zhou.root] + spot_nodes.values() + _dynamic.values())
	# 只收集场景本身的节点，后加的玩家与相机不会被隐藏。
	for child in get_children():
		if child is Node3D and child != _floor_rooms.cellar.root and child != _floor_rooms.attic.root and child != _floor_rooms.guest_zhou.root and child != _dynamic.furnish:
			_outside_nodes.append(child)


func _ground() -> void:
	K.box(self, Vector3(120, 0.2, 120), K.SNOW, Vector3(0, -0.1, 0))
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 0.2, 120)
	cs.shape = shape
	floor_body.position.y = -0.1
	floor_body.add_child(cs)
	add_child(floor_body)
	# 院内青石板：一块块颜色略有不同
	K.box(self, Vector3(19.4, 0.04, 14.4), K.STONE_DARK, Vector3(0, 0.02, -0.5))
	var stone := BoxMesh.new()
	stone.size = Vector3(1.42, 0.06, 1.42)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stone
	var cols := 13
	var rows := 10
	mm.instance_count = cols * rows
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in cols:
		for j in rows:
			var k := i * rows + j
			mm.set_instance_transform(k, Transform3D(Basis().rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(-9.0 + i * 1.5, 0.045, -7.25 + j * 1.5)))
			var v := rng.randf_range(-0.08, 0.06)
			mm.set_instance_color(k, Color(0.92 + v, 0.92 + v, 0.9 + v * 0.8))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var base: BaseMaterial3D = Assets.pbr("cobblestone_floor_08", 1.5)
	var sm: BaseMaterial3D = base.duplicate() if base != null else StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.9
	mi.material_override = sm
	add_child(mi)
	# 门外街道（青石）；街对面人家、后巷邻院、城墙山脊等四周景物统一由 home_surroundings 构建
	K.box(self, Vector3(60, 0.04, 6), K.mat(Color("#8f8b84"), 0.95), Vector3(0, 0.02, 11))
	K.box(self, Vector3(60, 0.045, 1.2), K.SNOW, Vector3(0, 0.025, 13.6))


func _buildings() -> void:
	halls.append(Arch.hall(self, Vector3(0, 0, -5.75), 0, 12.0, 4.5, 3.6, ["back", "left", "right"]))
	halls.append(Arch.hall(self, Vector3(-8.0, 0, -0.5), 90, 6.0, 3.6, 3.2, ["back"], false))
	halls.append(Arch.hall(self, Vector3(8.0, 0, -0.5), -90, 6.0, 3.6, 3.2, ["back"], false))
	Arch.wall(self, Vector3(-10.2, 0, -8.2), Vector3(10.2, 0, -8.2), 3.4)
	Arch.wall(self, Vector3(-10.2, 0, -8.2), Vector3(-10.2, 0, 7.0), 3.0)
	Arch.wall(self, Vector3(-10.2, 0, GATE_Z), Vector3(-1.9, 0, GATE_Z), 3.0)
	Arch.wall(self, Vector3(1.9, 0, GATE_Z), Vector3(10.2, 0, GATE_Z), 3.0)
	gate = Arch.gate(self, Vector3(0, 0, GATE_Z))
	_register("gate", gate.node)
	lanterns.append_array(gate.lanterns)
	_window = Arch.lattice_window(self, WINDOW_POS)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		lanterns.append(Arch.lantern(self, Vector3(x, 3.0, -2.9)))


## 只开放西邻隔墙交谈口；巷道和背景建筑仍不参与导航或拾取。
func _neighbor_wall() -> void:
	var root := _spot_root("neighbor_home")
	# 悬挂在院墙内侧的传话窗，留在独立节点内以支持悬停描边。
	K.box(root, Vector3(0.14, 1.15, 1.25), K.WOOD, Vector3(-9.93, 1.48, 3.6))
	K.box(root, Vector3(0.16, 0.85, 0.96), K.PAPER, Vector3(-9.84, 1.48, 3.6))
	for z in [3.28, 3.60, 3.92]:
		K.box(root, Vector3(0.19, 0.9, 0.06), K.WOOD_LIGHT, Vector3(-9.75, 1.48, z))
	K.box(root, Vector3(0.2, 0.06, 1.0), K.WOOD_LIGHT, Vector3(-9.75, 1.48, 3.6))
	K.collider(root, Vector3(0.5, 1.3, 1.4), Vector3(-9.68, 1.48, 3.6))
	_register("neighbor_home", root)


func _furniture() -> void:
	# 正屋中堂：条案供着牌位香烛，后面一扇屏风，两边太师椅，头顶一盏宫灯
	var shrine := _spot_root("shrine")
	if Assets.prop(shrine, "chinese_console_table", Vector3(0, 0, -7.15)) != null:
		Assets.prop(shrine, "chinese_screen_panels", Vector3(0, 0, -7.62))
		Props.altar_items(shrine, Vector3(0, 0.66, -7.15))
		Assets.prop(self, "chinese_armchair", Vector3(-1.5, 0, -7.0))
		Assets.prop(self, "chinese_armchair", Vector3(1.5, 0, -7.0))
		Assets.prop(self, "chinese_chandelier", Vector3(0, 3.5, -5.8), 0.0, 1.0, false)
	else:
		Props.shrine(shrine, Vector3(0, 0, -7.4))
	_register("shrine", shrine)
	_register("well", Props.well(_spot_root("well"), Vector3(-3.0, 0, 1.5)))


func _decor() -> void:
	Assets.prop(self, "folding_wooden_stool", Vector3(-1.8, 0, 0.6), 25.0)
	Assets.prop(self, "dead_tree_trunk", Vector3(8.7, 0, 3.4), 90.0)
	Assets.prop(self, "ceramic_vase_03", Vector3(-4.7, 0.84, 4.3), 0.0, 1.0, false)
	Assets.prop(self, "ceramic_vase_01", Vector3(5.2, 0, -7.6))
	Props.plum_tree(self, Vector3(-7.6, 0, 5.3))
	Props.stone_table(self, Vector3(-4.6, 0, 4.4))
	Props.stone_lantern(self, Vector3(-1.6, 0, 4.6))
	Props.stone_lantern(self, Vector3(1.6, 0, 4.6))
	Props.clay_jar(self, Vector3(-6.2, 0, 3.8))
	Props.clay_jar(self, Vector3(-6.0, 0, 4.7), 0.8)
	Props.potted_bamboo(self, Vector3(-5.6, 0, -7.5))
	Props.potted_bamboo(self, Vector3(9.4, 0, 6.3))
	Props.potted_bamboo(self, Vector3(-9.4, 0, -3.8))
	Props.laundry(self, Vector3(2.4, 0, 5.9), Vector3(5.2, 0, 5.9))
	Props.hanging_produce(self, Vector3(-6.25, 2.6, 2.55))
	Props.basket(self, Vector3(7.6, 0, 2.4), Color("#d8c9a3"))
	Props.basket(self, Vector3(7.0, 0, 2.9), Color("#a9c98a"))
	# 书架由 run.furniture 绘制，不能在原处再留一座静态副本。
	for x in [-2.2, 2.2]:
		Props.scroll_painting(self, Vector3(x, 2.1, -7.84))
	for x in [-3.0, 3.0]:
		Props.couplet(self, Vector3(x, 2.0, -3.52))


## 可交互物的容器：碰撞体带 spot 标记。
func _spot_root(id: String) -> Node3D:
	return K.node(self, Vector3.ZERO, Vector3.ZERO, "spot_" + id)


func _register(id: String, n: Node3D) -> void:
	spot_nodes[id] = n
	_tag_colliders(n, id)


func _tag_colliders(n: Node, id: String) -> void:
	if n is StaticBody3D:
		n.set_meta("spot", id)
	for c in n.get_children():
		_tag_colliders(c, id)


## 楼层切换由界面处理角色与时间；这里仅管理场景、拾取和导航。
func set_floor(id: String) -> void:
	var target := id if id in ["cellar", "attic", "guest_zhou"] else "courtyard"
	if target == _floor:
		return
	var was_outside := _floor == "courtyard"
	_floor = target
	if was_outside and _floor != "courtyard":
		_outside_visibility.clear()
		for node in _outside_nodes:
			if is_instance_valid(node):
				_outside_visibility[node] = node.visible
				node.visible = false
	elif not was_outside and _floor == "courtyard":
		for node in _outside_nodes:
			if is_instance_valid(node) and _outside_visibility.has(node):
				node.visible = bool(_outside_visibility[node])
		_outside_visibility.clear()
	for floor_id in _floor_rooms:
		_floor_rooms[floor_id].root.visible = floor_id == _floor
	spot_nodes.erase("floor_exit")
	spot_nodes.erase("floor_use")
	spot_nodes.erase("guest_talk")
	if _floor != "courtyard":
		spot_nodes["floor_exit"] = _floor_rooms[_floor].floor_exit
		if _floor == "guest_zhou":
			spot_nodes["guest_talk"] = _floor_rooms[_floor].guest_talk
		else:
			spot_nodes["floor_use"] = _floor_rooms[_floor].floor_use


## 路径查询前提交刚烘焙的楼层网格，避免切层首击使用旧地图。
func prepare_navigation() -> void:
	if is_inside_tree():
		NavigationServer3D.map_force_update(get_world_3d().navigation_map)
		NavigationServer3D.map_force_update(get_world_3d().navigation_map)


func floor_origin() -> Vector3:
	return FloorWorld.ORIGINS.get(_floor, Vector3.ZERO)


func to_floor_local(p: Vector3) -> Vector3:
	return p - floor_origin()


func floor_spawn(id: String) -> Vector3:
	return SPAWN if id == "courtyard" else FloorWorld.spawn(id)


func spot_info(id: String) -> Dictionary:
	if _floor != "courtyard":
		return FloorWorld.info(_floor, id)
	match id:
		"neighbor_home":
			var info: Dictionary = SPOTS.neighbor_home.duplicate()
			if bool(NeighborHome.view(_current_run).get("knocked", false)):
				info.name = "老周家的院墙"
			info.stand = _neighbor_stand_for_layout()
			return info
		"floor_cellar":
			return {"name": "地窖盖板", "stand": Vector3(6, 0, -1.35), "tag": Vector3(6, 1.1, -2.4)}
		"floor_attic":
			return {"name": "阁楼梯", "stand": Vector3(-1.9, 0, -2.1), "tag": Vector3(-1.9, 1.3, -3.35)}
	return {}


## 旧存档允许家具占据新交谈点；从墙口附近寻找实际可达站位，不挪动旧家具。
func _neighbor_stand_for_layout() -> Vector3:
	var fallback: Vector3 = SPOTS.neighbor_home.stand
	if not is_inside_tree() or not _baked:
		return fallback
	var key := _furniture_nav_key(_current_run) + ":%d:%s" % [_garden_rows, _side_stage]
	if key == _neighbor_stand_key:
		return _neighbor_stand
	prepare_navigation()
	var map := get_world_3d().navigation_map
	var candidates: Array[Vector3] = [fallback]
	for x in [-8.6, -8.1, -7.6, -7.1]:
		for z in [3.6, 2.8, 4.4, 2.0, 5.2]:
			candidates.append(Vector3(x, 0, z))
	for candidate in candidates:
		var closest := NavigationServer3D.map_get_closest_point(map, candidate)
		if Vector2(closest.x - candidate.x, closest.z - candidate.z).length() > 0.25:
			continue
		var path := NavigationServer3D.map_get_path(map, SPAWN, candidate, true)
		if path.size() > 1 and Vector2(path[0].x - SPAWN.x, path[0].z - SPAWN.z).length() < 0.5 and Vector2(path[-1].x - candidate.x, path[-1].z - candidate.z).length() < 0.25:
			_neighbor_stand = candidate
			_neighbor_stand_key = key
			return candidate
	return fallback


func _spot_on_floor(id: String) -> bool:
	if id.begins_with("f_"):
		var f := Home.find(_current_run, int(id.substr(2)))
		return not f.is_empty() and str(f.get("floor", "courtyard")) == _floor
	if id == "guest_talk":
		return _floor == "guest_zhou"
	if id == "floor_use":
		return _floor in ["cellar", "attic"]
	if id == "floor_exit":
		return _floor != "courtyard"
	return _floor == "courtyard"


## 导航网格：按院里的静态碰撞烘焙，点哪儿走哪儿。
func _bake_nav() -> void:
	nav_region = _new_nav_region("courtyard")
	for floor_id in ["cellar", "attic", "guest_zhou"]:
		_room_nav[floor_id] = _new_nav_region(floor_id)
	# 首次建场景时碰撞体可能尚未进入物理空间；下一物理帧再烘焙一次。
	call_deferred("_finish_initial_navigation")


func _finish_initial_navigation() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	nav_region.bake_navigation_mesh(false)
	for region in _room_nav.values():
		region.bake_navigation_mesh(false)
	prepare_navigation()


func _new_nav_region(floor_id: String) -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "navsrc"
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# 都取格子的整数倍（烘焙时本来也会这么取整），免得报精度警告
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.filter_baking_aabb = _nav_bounds_for(floor_id)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)
	region.bake_navigation_mesh(false)
	return region


# 扩建只在施工完成后打开侧墙；中间阶段保留封闭的原院。
func _sync_side_yard(run: Dictionary) -> bool:
	var stage := Expansion.stage(run)
	if stage == _side_stage:
		return false
	_side_stage = stage
	K.clear(_side_yard)
	_side_lantern = {}
	if Expansion.complete(run):
		Arch.wall(_side_yard, Vector3(10.2, 0, -8.2), Vector3(10.2, 0, 3.0), 3.0)
		Arch.wall(_side_yard, Vector3(10.2, 0, 6.0), Vector3(10.2, 0, 7.0), 3.0)
		Arch.wall(_side_yard, Vector3(10.2, 0, 2.5), Vector3(16.5, 0, 2.5), 2.6)
		Arch.wall(_side_yard, Vector3(16.5, 0, 2.5), Vector3(16.5, 0, 6.9), 2.6)
		Arch.wall(_side_yard, Vector3(10.2, 0, 6.9), Vector3(16.5, 0, 6.9), 2.6)
		K.box(_side_yard, Vector3(6.1, 0.06, 4.2), K.STONE_DARK, Vector3(13.3, 0.06, 4.7))
		_side_lantern = Arch.lantern(_side_yard, Vector3(15.8, 2.2, 3.0))
		Arch.set_lantern(_side_lantern, _night)
	else:
		Arch.wall(_side_yard, Vector3(10.2, 0, -8.2), Vector3(10.2, 0, 7.0), 3.0)
		# 标记清理与备料的真实进度；均为无碰撞的视觉，不代表工程已经完工。
		if stage == "survey":
			for i in range(4):
				K.box(_side_yard, Vector3(0.55, 0.35, 0.45), K.STONE, Vector3(12.8 + i * 0.55, 0.18, 4.6 + (i % 2) * 0.45), Vector3(0, i * 20, i * 5))
		elif stage in ["cleared", "ready"]:
			K.box(_side_yard, Vector3(3.4, 0.025, 2.1), K.EARTH, Vector3(13.5, 0.045, 4.6))
			if stage == "ready":
				for i in range(3):
					K.box(_side_yard, Vector3(1.8, 0.12, 0.22), K.WOOD_LIGHT, Vector3(13.5, 0.15 + i * 0.12, 4.4))
				K.box(_side_yard, Vector3(0.4, 0.24, 0.4), K.WOOD, Vector3(14.8, 0.15, 4.8))
	return true


func _nav_bounds_for(floor_id: String) -> AABB:
	if floor_id != "courtyard":
		var p: Vector3 = FloorWorld.ORIGINS[floor_id]
		return AABB(p + Vector3(-4.2, -1, -3.7), Vector3(8.4, 6, 7.4))
	return AABB(Vector3(-10.5, -1, -8.5), Vector3(27.5, 6, 16)) if Expansion.complete(_current_run) else AABB(Vector3(-10.5, -1, -8.5), Vector3(21, 6, 16))


# ---------- 按局面重画 ----------

func sync(run: Dictionary) -> void:
	_current_run = run
	_sync_neighbor_visual(run)
	var side_changed := _sync_side_yard(run)
	DecorationWorld.sync(_dynamic.decoration, run)
	var old_rows := _garden_rows
	_rebuild_stock(run)
	_rebuild_garden(run)
	_rebuild_devices(run)
	_rebuild_extras(run)
	_rebuild_furniture(run)
	_update_gate(run)
	_update_window(run)
	set_time(run)
	# 灶台、工作台是每次同步重画的，砸掉的那件要重画之后再藏
	_apply_wrecked(run)
	# 灶台等是第一次同步时才摆上的，摆好再烘焙导航
	if not _baked:
		_baked = true
		_bake_nav()
		_nav_furniture_key = _furniture_nav_key(run)
	else:
		var key := _furniture_nav_key(run)
		if key != _nav_furniture_key or old_rows != _garden_rows or side_changed:
			_nav_furniture_key = key
			nav_region.navigation_mesh.filter_baking_aabb = _nav_bounds_for("courtyard")
			nav_region.bake_navigation_mesh(false)
			for region in _room_nav.values():
				region.bake_navigation_mesh(false)


## 补修木板只在真实施工完成后显示；次日结算才挂出相应的记事牌。
## 这只是已发生事实的投影，没有碰撞、库存或独立 NPC 状态。
func _sync_neighbor_visual(run: Dictionary) -> void:
	var view: Dictionary = NeighborHome.view(run)
	_floor_rooms.guest_zhou.repaired_wall.visible = bool(view.get("wall_repaired", false))
	var key := "%s:%s:%s" % [view.get("wall_repaired", false), view.get("settled", false), view.get("choice", "")]
	if key == _neighbor_visual_key:
		return
	_neighbor_visual_key = key
	K.clear(_neighbor_visual)
	if bool(view.get("wall_repaired", false)):
		# 对应西侧近景屋的东向墙面；不为背景屋添加拾取或碰撞。
		for i in 3:
			K.box(_neighbor_visual, Vector3(0.12, 0.17, 1.55), K.WOOD_LIGHT, Vector3(-11.96, 2.0 + i * 0.21, 4.5))
		# 同一处共墙的院内侧补板；默认视角可能被对面房檐遮住，因此两面都投影。
		for i in 3:
			K.box(_neighbor_visual, Vector3(0.12, 0.13, 1.0), K.WOOD_LIGHT, Vector3(-9.58, 2.08 + i * 0.18, 4.5))
	if bool(view.get("settled", false)):
		var text: String = {"repair": "邻宅 · 修好", "trade": "邻宅 · 换物", "refuse": "邻宅 · 拒绝", "timeout": "邻宅 · 未回应"}.get(str(view.get("choice", "")), "")
		if text != "":
			K.box(_neighbor_visual, Vector3(0.12, 0.58, 1.8), K.WOOD, Vector3(-9.75, 2.55, 3.6))
			K.text3d(_neighbor_visual, text, Vector3(-9.5, 2.55, 3.6), 48, Color("#e6c25c"), true, 0.006)


func _furniture_nav_key(run: Dictionary) -> String:
	var parts: Array[String] = []
	for f in run.get("furniture", []):
		parts.append("%s:%s:%s:%s:%s:%s" % [f.uid, f.id, f.x, f.z, f.rot, f.get("floor", "courtyard")])
	return "|".join(parts)


func _rebuild_stock(run: Dictionary) -> void:
	var home: Dictionary = run.home
	K.clear(_dynamic.sacks)
	Props.rice_sacks(_dynamic.sacks, Vector3(-8.9, 0, -0.2), Inv.total(home, Inv.GRAINS))
	K.clear(_dynamic.firewood)
	Props.firewood(_dynamic.firewood, Vector3(-8.9, 0, -3.0), Inv.count(home, "firewood") + Inv.count(home, "charcoal") * 2)
	K.clear(_dynamic.wood)
	Props.wood_pile(_dynamic.wood, Vector3(8.7, 0, 1.4), Inv.count(home, "wood"), 90)


func _rebuild_garden(run: Dictionary) -> void:
	K.clear(_dynamic.garden)
	var plots: Array = []
	for plot in run.get("plots", []):
		if not plot.has("pot"):
			plots.append(plot)
	var crops: Dictionary = Data.table("crops")
	var visible_count := mini(maxi(plots.size(), 2), PLOT_POS.size())
	_fit_garden(ceili(visible_count / 2.0))
	for k in visible_count:
		if k < plots.size():
			var plot: Dictionary = plots[k]
			var growth := 0.0
			if plot.crop != "":
				growth = float(plot.days) / float(crops[plot.crop].days)
			Props.garden_plot(_dynamic.garden, PLOT_POS[k], plot.crop, growth, Post.plot_dry(run, plot))
		else:
			Props.garden_plot(_dynamic.garden, PLOT_POS[k], "", 0, true)


## 普通菜畦按非花盆索引显示；花盆标签跟随所属家具。
func plot_tag_position(run: Dictionary, index: int) -> Variant:
	var plots: Array = run.get("plots", [])
	if index < 0 or index >= plots.size():
		return null
	var plot: Dictionary = plots[index]
	if plot.has("pot"):
		var f := Home.find(run, int(plot.pot))
		if f.is_empty() or str(f.id) != "planter":
			return null
		if str(f.get("floor", "courtyard")) != _floor:
			return null
		return floor_origin() + Vector3(float(f.x), 0.9, float(f.z))
	if _floor != "courtyard":
		return null
	var ground_index := 0
	for i in index:
		if not plots[i].has("pot"):
			ground_index += 1
	return PLOT_POS[ground_index] + Vector3(0, 0.9, 0) if ground_index < PLOT_POS.size() else null


## 玩家自己添置的家具：按 run.furniture 摆，位置和朝向都听数据。
## 核心家具和附加家具都由同一份存档数据绘制。
func _rebuild_furniture(run: Dictionary) -> void:
	for spot in _furn_spots.keys():
		spot_nodes.erase(spot)
	_furn_spots.clear()
	K.clear(_dynamic.furnish)
	for f in run.get("furniture", []):
		var id := str(f.id)
		var spot := "f_%d" % int(f.uid)
		var origin: Vector3 = FloorWorld.ORIGINS.get(str(f.get("floor", "courtyard")), Vector3.ZERO)
		var root := K.node(_dynamic.furnish, origin + Vector3(float(f.x), 0.0, float(f.z)), Vector3(0, float(f.rot), 0), spot)
		if id in Home.CORE_IDS:
			_core_mesh(root, id, run)
		else:
			_furn_mesh(root, id)
		if id == "planter":
			for plot in run.get("plots", []):
				if int(plot.get("pot", -1)) == int(f.uid) and str(plot.get("crop", "")) != "":
					var crop := str(plot.crop)
					var crop_data: Dictionary = Data.table("crops").get(crop, {})
					if not crop_data.is_empty():
						var growth := float(plot.days) / float(crop_data.days)
						var plant := Props.garden_plot(root, Vector3(0, 0.36, 0), crop, growth, Post.plot_dry(run, plot))
						plant.name = "planter_crop"
						plant.scale = Vector3(0.7, 0.7, 0.26)
					break
		# 碰撞盒位于已经旋转的 root 内，局部尺寸必须使用零度尺寸。
		var sz := Home.size_of(id, 0)
		K.collider(root, Vector3(sz.x, 0.9, sz.y), Vector3(0, 0.45, 0), {"spot": spot})
		_register(spot, root)
		_furn_spots[spot] = int(f.uid)


func _core_mesh(root: Node3D, id: String, run: Dictionary) -> void:
	match id:
		"bed":
			if Assets.prop(root, "chinese_sofa", Vector3.ZERO) == null:
				Props.bed(root, Vector3.ZERO)
		"desk":
			if Assets.prop(root, "chinese_tea_table", Vector3.ZERO) != null:
				Assets.prop(root, "chinese_stool", Vector3(0, 0, 0.75), 180.0)
				Props.desk_items(root, Vector3(0, 0.5, 0))
			else:
				Props.desk(root, Vector3.ZERO)
		"storage":
			if Assets.prop(root, "chinese_cabinet", Vector3.ZERO) == null:
				Props.cabinet(root, Vector3.ZERO, 0)
		"stove":
			Props.stove(root, Vector3.ZERO, 0, "stove" in run.get("facilities", []))
		"bench":
			Props.workbench(root, Vector3.ZERO, 0)


## 各类家具的样子：够看就行，都是基本体拼的。
func _furn_mesh(root: Node3D, id: String) -> void:
	match id:
		"bookshelf":
			K.box(root, Vector3(1.2, 1.8, 0.42), K.WOOD, Vector3(0, 0.9, 0))
			for y in [0.55, 0.95, 1.35, 1.72]:
				K.box(root, Vector3(1.1, 0.06, 0.4), K.WOOD_LIGHT, Vector3(0, y, 0))
			for i in 3:
				K.box(root, Vector3(0.28, 0.24, 0.3), K.CLOTH_BLUE if i % 2 else K.PAPER,
					Vector3(-0.38 + i * 0.36, 0.68 + (i % 2) * 0.4, 0))
		"rice_jar":
			K.box(root, Vector3(0.72, 0.7, 0.72), K.EARTH, Vector3(0, 0.35, 0))
			K.box(root, Vector3(0.8, 0.08, 0.8), K.STONE_DARK, Vector3(0, 0.72, 0))
			K.box(root, Vector3(0.5, 0.04, 0.5), K.RICE_SACK, Vector3(0, 0.76, 0))
		"pickle_jar":
			K.box(root, Vector3(0.52, 0.5, 0.52), K.EARTH, Vector3(0, 0.25, 0))
			K.box(root, Vector3(0.58, 0.06, 0.58), K.STONE_DARK, Vector3(0, 0.52, 0))
		"water_vat":
			Props.water_vat(root, Vector3.ZERO)
		"planter":
			K.box(root, Vector3(1.4, 0.36, 0.6), K.WOOD, Vector3(0, 0.18, 0))
			K.box(root, Vector3(1.24, 0.06, 0.46), K.EARTH, Vector3(0, 0.36, 0))
		"brazier":
			K.box(root, Vector3(0.7, 0.26, 0.7), K.STONE_DARK, Vector3(0, 0.13, 0))
			K.box(root, Vector3(0.5, 0.08, 0.5), K.mat(Color("#3a2a24"), 0.9), Vector3(0, 0.28, 0))
			for i in 3:
				K.box(root, Vector3(0.12, 0.06, 0.12), K.mat(K.CINNABAR, 0.6, 1.2),
					Vector3(-0.14 + i * 0.14, 0.33, 0.02 * i))
		"rat_trap":
			K.box(root, Vector3(0.5, 0.12, 0.36), K.WOOD_LIGHT, Vector3(0, 0.06, 0))
			K.box(root, Vector3(0.44, 0.04, 0.06), K.STONE_DARK, Vector3(0, 0.14, 0))
		"smoke_rack":
			for sx in [-0.5, 0.5]:
				K.box(root, Vector3(0.1, 1.5, 0.1), K.WOOD, Vector3(sx, 0.75, 0))
			K.box(root, Vector3(1.2, 0.1, 0.12), K.WOOD_LIGHT, Vector3(0, 1.45, 0))
			for i in 2:
				K.box(root, Vector3(0.18, 0.4, 0.18), K.CINNABAR.darkened(0.2), Vector3(-0.2 + i * 0.4, 1.18, 0))
		"incense":
			K.box(root, Vector3(0.34, 0.5, 0.34), K.WOOD, Vector3(0, 0.25, 0))
			K.box(root, Vector3(0.42, 0.06, 0.42), K.GOLD, Vector3(0, 0.53, 0))
		"screen":
			for i in 3:
				K.box(root, Vector3(0.42, 1.5, 0.06), K.WOOD, Vector3(-0.42 + i * 0.42, 0.75, 0))
				K.box(root, Vector3(0.34, 1.3, 0.03), K.PAPER, Vector3(-0.42 + i * 0.42, 0.75, 0.05))
		"armchair":
			K.box(root, Vector3(0.7, 0.1, 0.68), K.WOOD, Vector3(0, 0.45, 0))
			K.box(root, Vector3(0.7, 0.7, 0.1), K.WOOD, Vector3(0, 0.8, -0.3))
			for sx in [-0.35, 0.35]:
				K.box(root, Vector3(0.06, 0.45, 0.68), K.WOOD_LIGHT, Vector3(sx, 0.22, 0))
		"tea_table":
			K.box(root, Vector3(0.86, 0.08, 0.86), K.WOOD_LIGHT, Vector3(0, 0.52, 0))
			for sx in [-0.34, 0.34]:
				for sz in [-0.34, 0.34]:
					K.box(root, Vector3(0.08, 0.5, 0.08), K.WOOD, Vector3(sx, 0.25, sz))
			K.box(root, Vector3(0.16, 0.12, 0.16), K.PAPER, Vector3(0.1, 0.62, 0.05))
		"bamboo":
			K.box(root, Vector3(0.44, 0.36, 0.44), K.EARTH, Vector3(0, 0.18, 0))
			for i in 3:
				K.box(root, Vector3(0.06, 1.3 - i * 0.2, 0.06), K.LEAF.darkened(0.2),
					Vector3(-0.1 + i * 0.1, 0.65, 0.02 * i), Vector3(0, 0, (i - 1) * 8))
		_:
			var sz := Home.size_of(id, 0)
			K.box(root, Vector3(sz.x * 0.8, 0.7, sz.y * 0.8), K.WOOD_LIGHT, Vector3(0, 0.35, 0))


func _rebuild_devices(run: Dictionary) -> void:
	K.clear(_dynamic.devices)
	var counts := {}
	for d in run.get("devices", []):
		counts[d.id] = int(counts.get(d.id, 0)) + 1
	var rows := {"peach_stake": 9.6, "barricade": 10.8, "caltrop_field": 12.0, "rice_scatter": 7.9, "blood_sill": 7.5}
	for id in counts:
		for k in counts[id]:
			match id:
				"armor_hook":
					var hook_model := K.node(_dynamic.devices, Vector3.ZERO, Vector3.ZERO, "device_armor_hook_%d" % k)
					Props.device(hook_model, id, Vector3(0, 0, 8.6 + k * 0.45), k)
				"horde_rope":
					var rope_model := K.node(_dynamic.devices, Vector3.ZERO, Vector3.ZERO, "device_horde_rope_%d" % k)
					Props.device(rope_model, id, WINDOW_POS + Vector3(0, -1.4, 0.35 + k * 0.12), k)
				"ink_line":
					Props.device(_dynamic.devices, id, Vector3(0, 0, GATE_Z + 0.32 + k * 0.05), k)
					Props.device(_dynamic.devices, id, WINDOW_POS + Vector3(0, -1.4, 0.32), k)
				"talisman_wall":
					Props.device(_dynamic.devices, id, Vector3(0, 0, GATE_Z + 1.0), k)
				"bagua_mirror":
					Props.device(_dynamic.devices, id, Vector3(0, 3.55, GATE_Z + 0.3), k)
				_:
					var z: float = rows.get(id, 9.0) + k * 0.7
					Props.device(_dynamic.devices, id, Vector3(0, 0, z), k)


func _rebuild_extras(run: Dictionary) -> void:
	K.clear(_dynamic.extras)
	spot_nodes.erase("floor_cellar")
	spot_nodes.erase("floor_attic")
	var facs: Array = run.get("facilities", [])
	if "water_vat" in facs:
		Props.water_vat(_dynamic.extras, Vector3(-5.2, 0, 2.0))
	if "watchtower" in facs:
		var t := K.node(_dynamic.extras, Vector3(8.6, 0, 5.6))
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				K.box(t, Vector3(0.14, 5.0, 0.14), K.WOOD, Vector3(sx * 0.6, 2.5, sz * 0.6))
		K.box(t, Vector3(1.6, 0.12, 1.6), K.WOOD_LIGHT, Vector3(0, 4.2, 0))
		K.prism(t, Vector3(2.0, 0.6, 2.0), K.ROOF, Vector3(0, 5.3, 0), Vector3(0, 90, 0))
	if "cellar" in facs:
		var hatch := K.node(_dynamic.extras, Vector3(6.0, 0, -2.4))
		K.box(hatch, Vector3(1.4, 0.08, 1.0), K.WOOD, Vector3(0, 0.09, 0))
		K.box(hatch, Vector3(0.1, 0.1, 0.5), K.mat(K.GOLD, 0.4), Vector3(0, 0.16, 0))
		K.text3d(hatch, "地窖", Vector3(0, 1.05, 0), 48, Color("#f2d89c"))
		K.collider(hatch, Vector3(1.4, 0.35, 1.0), Vector3(0, 0.18, 0), {"spot": "floor_cellar"})
		_register("floor_cellar", hatch)
	if Floors.unlocked(run, "attic"):
		var stairs := K.node(_dynamic.extras, Vector3(-1.9, 0, -3.35))
		for i in 3:
			K.box(stairs, Vector3(0.9, 0.12, 0.35), K.WOOD_LIGHT, Vector3(0, 0.08 + i * 0.12, -i * 0.25))
		K.text3d(stairs, "阁楼", Vector3(0, 1.2, 0), 48, Color("#f2d89c"))
		K.collider(stairs, Vector3(0.9, 0.65, 1.0), Vector3(0, 0.33, -0.25), {"spot": "floor_attic"})
		_register("floor_attic", stairs)
	if "door_bar" in facs:
		for y in [0.6, 2.2]:
			K.box(_dynamic.extras, Vector3(2.4, 0.14, 0.06), K.mat(Color("#4a4d52"), 0.4), Vector3(0, y, GATE_Z + 0.12))
	if State.flag(run, "dog"):
		Props.dog(_dynamic.extras, Vector3(1.4, 0, 5.4))


## 菜畦的碰撞只罩住画出来的那几排。做成 1 米高：既挡人，导航也不会把它的顶面当成能走上去的台子。
## 排数变了（扩了菜畦）就重新烘焙导航。
func _fit_garden(rows: int) -> void:
	if rows == _garden_rows:
		return
	_garden_rows = rows
	var depth := 1.8 * rows
	(_garden_body.get_child(0) as CollisionShape3D).shape.size = Vector3(3.6, 1.0, depth)
	_garden_body.position = Vector3(3.55, 0.5, PLOT_POS[0].z - 0.9 + depth / 2.0)


var _fight_figs := []
var _debris: Array = []
var _rubbles: Dictionary = {}   # 砸烂的家具 spot -> 塌料节点
var _furn_spots: Dictionary = {}  # 玩家添置的家具 spot -> uid

## 院子里的东西被啃了：原地留一堆碎屑。
## 存货、柴垛、菜畦靠 sync(run) 重画；家具塌不塌由 run.broken 决定（见 _apply_wrecked）。
func show_wreck(idx: int, pos: Vector3, kind: String) -> void:
	var root := K.node(self, Vector3.ZERO, Vector3.ZERO, "wreck")
	_debris.append(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(pos.x) * 131.0 + absf(pos.z) * 17.0) + idx * 977
	var col := K.EARTH
	match kind:
		"crop":
			col = K.GREEN
		"grain":
			col = K.RICE_SACK
		"fuel":
			col = K.WOOD_LIGHT
		"furniture":
			col = K.WOOD
	for i in 7:
		var p := pos + Vector3(rng.randf_range(-0.85, 0.85), 0.045, rng.randf_range(-0.85, 0.85))
		var size := Vector3(rng.randf_range(0.08, 0.3), rng.randf_range(0.04, 0.1), rng.randf_range(0.08, 0.26))
		K.box(root, size, col if i % 3 != 0 else col.darkened(0.3), p,
			Vector3(0, rng.randf_range(0, 90), rng.randf_range(-20, 20)))
	# 地上留一片暗渍，远看也知道这块被翻过
	K.box(root, Vector3(1.7, 0.012, 1.7), K.mat(Color("#3a2a24"), 0.95, 0.0, 0.5), pos + Vector3(0, 0.03, 0))


## 被砸烂的家具：好的一件藏起来，原处留一堆塌掉的木料——点了还能修。
## 灶台和工作台都是每次 sync 重画的，所以每次重画后都要再过一遍。
func _apply_wrecked(run: Dictionary) -> void:
	var active := []
	for id in ["stove", "bench"]:
		var f := Home.core(run, id)
		if f.is_empty():
			continue
		var spot := "f_%d" % int(f.uid)
		if id in run.get("broken", []):
			active.append(spot)
			_wreck_spot(spot, Vector3(float(f.x), 0, float(f.z)))
	for spot in _rubbles.keys():
		if not spot in active:
			_heal_spot(spot)


func _wreck_spot(spot: String, pos: Vector3) -> void:
	if spot_nodes.has(spot):
		spot_nodes[spot].visible = false
	if _rubbles.has(spot):
		_rubbles[spot].position = pos
		return
	var r := K.node(self, pos, Vector3.ZERO, "rubble_" + spot)
	K.solid(r, Vector3(1.4, 0.26, 1.0), K.WOOD.darkened(0.25), Vector3(0, 0.13, 0))
	for i in 5:
		K.box(r, Vector3(0.34, 0.16, 0.22), K.WOOD_LIGHT.darkened(0.25),
			Vector3((i - 2) * 0.42, 0.1, (i % 2) * 0.36), Vector3(0, i * 27, (i - 2) * 8))
	_tag_colliders(r, spot)
	_rubbles[spot] = r


func _heal_spot(spot: String) -> void:
	if spot_nodes.has(spot):
		spot_nodes[spot].visible = true
	if _rubbles.has(spot):
		_rubbles[spot].queue_free()
		_rubbles.erase(spot)


## 院门口的活人：门开着的时候，这一轮的僵尸会真的走进来。
func show_fight(fight: Dictionary) -> void:
	if fight.is_empty():
		for f in _fight_figs:
			f.queue_free()
		_fight_figs = []
		for d in _debris:
			d.queue_free()
		_debris = []
		return
	while _fight_figs.size() < fight.foes.size():
		var fig: Node3D = Figure.new()
		add_child(fig)
		fig.setup("jiangshi")
		fig.hopping = true
		fig.speed_scale = 1.0
		_fight_figs.append(fig)
	for i in fight.foes.size():
		var foe: Dictionary = fight.foes[i]
		var fig: Node3D = _fight_figs[i]
		if bool(foe.dead):
			if not fig.get_meta("down", false):
				fig.set_meta("down", true)
				fig.hopping = false
				fig.fall()
			continue
		fig.global_position = Vector3(float(foe.x), 0.0, float(foe.z))
		var to := Vector3(0, 0, GATE_Z if not bool(foe.inside) else 0.0) - fig.global_position
		to.y = 0
		if to.length() > 0.05:
			fig.face(to, 1.0)


## 门：越破越暗、越歪；破了以后一扇门倒开。开着的时候门扇拉到两边。
func _update_gate(run: Dictionary) -> void:
	var door: Dictionary = run.get("door", {"cur": 100, "max": 100})
	show_gate_ratio(float(door.cur) / maxf(1.0, float(door.max)))
	show_gate_open(bool(run.get("door_open", false)))


func show_gate_open(open: bool) -> void:
	for k in 2:
		var pivot: Node3D = gate.leaves[k]
		var sx := -1.0 if k == 0 else 1.0
		pivot.rotation_degrees.y = sx * (105.0 if open else 0.0)


func show_gate_ratio(ratio: float) -> void:
	for k in 2:
		var m: StandardMaterial3D = gate.leaf_mats[k]
		m.albedo_color = K.LACQUER.lerp(Color("#2a1d18"), 1.0 - ratio)
		var pivot: Node3D = gate.leaves[k]
		var sx := -1 if k == 0 else 1
		pivot.rotation_degrees = Vector3.ZERO
		if ratio <= 0.0:
			if k == 1:
				pivot.rotation_degrees.y = -70.0
			else:
				pivot.rotation_degrees.z = -6.0
		elif ratio < 0.5:
			pivot.rotation_degrees.z = sx * (1.0 - ratio) * 3.0


func _update_window(run: Dictionary) -> void:
	var w: Dictionary = run.get("window", {"cur": 60, "max": 60})
	var ratio := float(w.cur) / maxf(1.0, float(w.max))
	var old := _window.get_node_or_null("bars")
	if old != null:
		_window.remove_child(old)
		old.queue_free()
	Arch.window_bars(_window, 1.3, ratio, "window_board" in run.get("facilities", []))


# ---------- 时辰与光 ----------

## 按钟点给光：5-8 晨、8-16 午、16-19 暮、19-5 夜。
func set_time(run: Dictionary) -> void:
	var cold := int(State.weather(run).cold) if int(run.get("pday", 0)) > 0 else 10
	var snow := 250 + cold * 30
	var c := Post.clock(run) if run.has("t") else 720
	var h := c / 60.0
	if h >= 5.0 and h < 8.0:
		SkyKit.blend(sky, "night", "dawn", clampf((h - 5.0) / 1.5, 0.0, 1.0), snow)
	elif h >= 8.0 and h < 16.0:
		SkyKit.blend(sky, "dawn", "noon", clampf((h - 8.0) / 2.0, 0.0, 1.0), snow)
	elif h >= 16.0 and h < 19.0:
		SkyKit.blend(sky, "noon", "dusk", clampf((h - 16.0) / 2.0, 0.0, 1.0), snow)
	elif h >= 19.0 and h < 20.5:
		SkyKit.blend(sky, "dusk", "night", clampf((h - 19.0) / 1.5, 0.0, 1.0), snow)
	else:
		SkyKit.apply(sky, "night", snow)
	# C1 邻宅氛围必须在 _set_lanterns 同值早退之外无条件接线，
	# 否则夜晚二次 set_time 时天空变了窗灯不跟着变（假验收）。
	_apply_ambience_run(run)
	_set_lanterns(h >= 17.5 or h < 6.5)


func set_preset(preset: String, snow := 400) -> void:
	SkyKit.apply(sky, preset, snow)
	_set_lanterns(preset in ["dusk", "night", "blood"])
	_apply_ambience_preset(preset)


# ---------- C1 邻宅氛围 ----------

func _amb_node() -> Node3D:
	if surroundings == null:
		return null
	return surroundings.get_node_or_null("ambience")


func _apply_ambience_run(run: Dictionary) -> void:
	var A = load(AmbiencePath)
	var n := _amb_node()
	if A == null or n == null:
		return
	var st: Dictionary = A.state_for_run(run)
	_amb_ctx = {"phase": str(run.get("phase", "post")), "pday": int(run.get("pday", 1)),
		"heavy": bool(st.get("snow_heavy", false))}
	A.apply(n, st)


func _apply_ambience_preset(preset: String) -> void:
	var A = load(AmbiencePath)
	var n := _amb_node()
	if A != null and n != null:
		A.apply(n, A.state_for_preset(preset, _amb_ctx))


func _set_lanterns(lit: bool) -> void:
	if lit == _night:
		return
	_night = lit
	for lan in lanterns:
		Arch.set_lantern(lan, lit)
	if not _side_lantern.is_empty():
		Arch.set_lantern(_side_lantern, lit)


# ---------- 交互与遮挡 ----------

## 离 pos 最近、在半径内的可交互物 id；没有返回空串。
func nearest_spot(pos: Vector3, radius := 1.8) -> String:
	var best := ""
	var best_d := radius
	if _floor != "courtyard":
		for id in (["floor_exit", "guest_talk"] if _floor == "guest_zhou" else ["floor_exit", "floor_use"]):
			var info := spot_info(id)
			var p: Vector3 = info.stand
			var d := Vector2(pos.x - p.x, pos.z - p.z).length()
			if d < best_d:
				best = id
				best_d = d
		for f in _current_run.get("furniture", []):
			if str(f.get("floor", "courtyard")) != _floor:
				continue
			var p := floor_origin() + Vector3(float(f.x), 0, float(f.z))
			var d := Vector2(pos.x - p.x, pos.z - p.z).length()
			if d < best_d:
				best = "f_%d" % int(f.uid)
				best_d = d
		return best
	for id in SPOTS:
		var p: Vector3 = spot_info(id).stand if id == "neighbor_home" else SPOTS[id].stand
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < best_d:
			best = id
			best_d = d
	for id in ["floor_cellar", "floor_attic"]:
		if spot_nodes.has(id):
			var p: Vector3 = spot_info(id).stand
			var d := Vector2(pos.x - p.x, pos.z - p.z).length()
			if d < best_d:
				best = id
				best_d = d
	for f in _current_run.get("furniture", []):
		if str(f.get("floor", "courtyard")) != "courtyard" or not Home.is_core(_current_run, f):
			continue
		var p := Home.stand(f)
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < best_d:
			best = "f_%d" % int(f.uid)
			best_d = d
	return best


## 鼠标下面是什么：{"spot": id} / {"ground": 位置} / {}
func pick(cam: Camera3D, screen_pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 200.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	if hit.collider.has_meta("spot"):
		var id := str(hit.collider.get_meta("spot"))
		if _spot_on_floor(id):
			return {"spot": id}
		return {}
	var p: Vector3 = hit.position
	if p.y < 0.3 and _inside_pick_bounds(p):
		return {"ground": Vector3(p.x, 0, p.z)}
	return {}


func _inside_pick_bounds(p: Vector3) -> bool:
	if _floor != "courtyard":
		return FloorWorld.contains(_floor, p)
	if absf(p.x) < 10.0 and p.z > -8.0 and p.z < GATE_Z - 0.3:
		return true
	return Expansion.complete(_current_run) and p.x >= 10.0 and p.x < 16.3 and p.z > 2.7 and p.z < 6.7


## 移动时射线穿过所选家具自身，其他物体仍阻挡；允许原地改朝向。
func pick_move_ground(cam: Camera3D, screen_pos: Vector2, uid: int) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 200.0)
	var root: Node = spot_nodes.get("f_%d" % uid)
	if root != null:
		var excluded: Array[RID] = []
		_collect_collision_rids(root, excluded)
		q.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider.has_meta("spot"):
		return {}
	var p: Vector3 = hit.position
	if p.y < 0.3 and _inside_pick_bounds(p):
		return {"ground": Vector3(p.x, 0, p.z)}
	return {}


func _collect_collision_rids(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_collision_rids(child, out)


## 保守预留各核心站位及通向中轴的走廊，防止新增家具切断它们。
## 这是静态保留区，并非对玩家当前实际路线的寻路证明。
func _move_route_block(rect: Rect2, run: Dictionary, ignore_uid: int) -> bool:
	if _floor != "courtyard":
		return rect.intersects(Rect2(-0.8, -2.5, 1.6, 5.0))
	for info in SPOTS.values():
		var p: Vector3 = info.stand
		var left := minf(0.0, p.x)
		var lane := Rect2(left - 0.6, p.z - 0.6, absf(p.x) + 1.2, 1.2)
		if rect.intersects(lane):
			return true
	for f in run.get("furniture", []):
		if not Home.is_core(run, f) or int(f.uid) == ignore_uid:
			continue
		var p := Home.stand(f)
		var lane := Rect2(minf(0.0, p.x) - 0.6, p.z - 0.6, absf(p.x) + 1.2, 1.2)
		if rect.intersects(lane):
			return true
	# 中轴向北延伸至神龛，连接前庭与正屋。
	return rect.intersects(Rect2(-0.6, -6.6, 1.2, 13.2))


## 新建和挪位同样检查物理障碍与通路，不能穿过侧墙或堵住工作站。
func build_spot_block(run: Dictionary, id: String, x: float, z: float, rot: int) -> String:
	if _floor == "guest_zhou":
		return "做客时不能布置邻家的家具。"
	var local := to_floor_local(Vector3(x, 0, z))
	x = Home.snap(local.x)
	z = Home.snap(local.z)
	var err := Home.place_block(run, id, x, z, rot)
	if err != "":
		return err
	if _move_route_block(Home.rect_of(id, x, z, rot), run, -1):
		return "这里要留给工作站和通路。"
	if not is_inside_tree():
		return "院子还没准备好。"
	var size := Home.size_of(id, rot)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(0.01, size.x - 0.04), 0.7, maxf(0.01, size.y - 0.04))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, floor_origin() + Vector3(x, 0.45, z))
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 64):
		if hit.collider is StaticBody3D:
			return "这儿有东西挡着。"
		if hit.collider is CharacterBody3D:
			return "人站在这里，先让开。"
	return ""


## 摆放预览及确认共用。几何/规则以外还检查当前场景静态碰撞。
func move_spot_block(run: Dictionary, uid: int, x: float, z: float, rot: int) -> String:
	if _floor == "guest_zhou":
		return "做客时不能布置邻家的家具。"
	var eligibility := Home.move_block(run, uid)
	if eligibility != "":
		return eligibility
	var f := Home.find(run, uid)
	if str(f.get("floor", "courtyard")) != _floor:
		return "不能跨层挪动家具。"
	var local := to_floor_local(Vector3(x, 0, z))
	x = Home.snap(local.x)
	z = Home.snap(local.z)
	var err := Home.spot_block(run, str(f.id), x, z, rot, uid)
	if err != "":
		return err
	if _move_route_block(Home.rect_of(str(f.id), x, z, rot), run, uid):
		return "这里要留给工作站和通路。"
	if not is_inside_tree():
		return "院子还没准备好。"
	var size := Home.size_of(str(f.id), rot)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(0.01, size.x - 0.04), 0.7, maxf(0.01, size.y - 0.04))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, floor_origin() + Vector3(x, 0.45, z))
	var excluded: Array[RID] = []
	var source: Node = spot_nodes.get("f_%d" % uid)
	if source != null:
		_collect_collision_rids(source, excluded)
	q.exclude = excluded
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 64):
		if hit.collider is StaticBody3D:
			return "这儿有东西挡着。"
		if hit.collider is CharacterBody3D:
			return "人站在这里，先让开。"
	if Home.is_core(run, f):
		var proposed := f.duplicate()
		proposed.x = x
		proposed.z = z
		proposed.rot = rot
		var stand := Home.stand(proposed)
		# E 选择最近站位；预留足够间距，角色走到站位附近时仍能选中目标。
		for info in SPOTS.values():
			var other: Vector3 = info.stand
			if Vector2(stand.x - other.x, stand.z - other.z).length() < 2.0:
				return "家具正面离其他工作站太近。"
		for other in run.get("furniture", []):
			if int(other.uid) == uid or not Home.is_core(run, other):
				continue
			var p := Home.stand(other)
			if Vector2(stand.x - p.x, stand.z - p.z).length() < 2.0:
				return "家具正面离其他工作站太近。"
		var stand_rect := Rect2(stand.x - 0.4, stand.z - 0.4, 0.8, 0.8)
		if Home.area_of(stand_rect, run) == "":
			return "家具正面没有站人的地方。"
		var stand_shape := BoxShape3D.new()
		stand_shape.size = Vector3(0.75, 1.5, 0.75)
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = stand_shape
		sq.transform = Transform3D(Basis.IDENTITY, stand + Vector3(0, 0.85, 0))
		sq.exclude = excluded
		for hit in get_world_3d().direct_space_state.intersect_shape(sq, 64):
			if hit.collider is StaticBody3D:
				return "家具正面被挡住了。"
		var map := get_world_3d().navigation_map
		var nearest := NavigationServer3D.map_get_closest_point(map, stand)
		if Vector2(nearest.x - stand.x, nearest.z - stand.z).length() > 0.5:
			return "走不到家具正面。"
		var path := NavigationServer3D.map_get_path(map, SPAWN, stand, true)
		if path.is_empty() or Vector2(path[-1].x - stand.x, path[-1].z - stand.z).length() > 0.5:
			return "走不到家具正面。"
		# 当前导航尚未包含新位置，拒绝路径穿过拟摆放的家具。
		var footprint := Home.rect_of(str(f.id), x, z, rot).grow(0.35)
		for i in range(1, path.size()):
			var n := maxi(1, int(ceil(path[i-1].distance_to(path[i]) / 0.2)))
			for step in range(n + 1):
				var sample: Vector3 = path[i-1].lerp(path[i], float(step) / n)
				if footprint.has_point(Vector2(sample.x, sample.z)):
					return "家具挡住了走向正面的路。"
	return ""


## 人在屋里（踩木地板）吗。
func indoors(pos: Vector3) -> bool:
	if _floor != "courtyard":
		return true
	for h in halls:
		var local: Vector3 = (h.node as Node3D).to_local(pos)
		if absf(local.x) < h.w / 2.0 and absf(local.z) < h.d / 2.0:
			return true
	return false


## 人在屋檐下时，把那间屋的屋顶淡掉，免得挡住。
func update_roofs(player_pos: Vector3) -> void:
	for h in halls:
		var n: Node3D = h.node
		var local := n.to_local(player_pos)
		var inside: bool = absf(local.x) < h.w / 2.0 + 0.6 and local.z > -h.d / 2.0 - 0.2 and local.z < h.d / 2.0 + 0.9
		var target := 0.15 if inside else 1.0
		for m in h.fade_mats:
			_fade(m, target)


func _fade(m: BaseMaterial3D, target: float) -> void:
	if absf(m.albedo_color.a - target) < 0.005:
		return
	var a := lerpf(m.albedo_color.a, target, 0.15)
	if absf(a - target) < 0.01:
		a = target
	m.albedo_color.a = a
	var mode := BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	if m.transparency != mode:
		m.transparency = mode
