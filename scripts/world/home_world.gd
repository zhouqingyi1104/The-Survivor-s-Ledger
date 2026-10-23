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
const Assets = preload("res://scripts/world/assets.gd")
const Figure = preload("res://scripts/world/character.gd")

const GATE_Z := 7.0
const WINDOW_POS := Vector3(5.6, 1.7, 7.0)
const SPAWN := Vector3(0, 0, 3.0)

## 可交互物：名称、站位（人走到哪儿做事）、头顶标签的位置
const SPOTS := {
	"shrine":  {"name": "神龛",   "stand": Vector3(0, 0, -6.0),    "tag": Vector3(0, 2.9, -7.4)},
	"bed":     {"name": "床榻",   "stand": Vector3(-4.0, 0, -5.4), "tag": Vector3(-4.0, 2.3, -6.9)},
	"desk":    {"name": "书案",   "stand": Vector3(4.2, 0, -5.7),  "tag": Vector3(4.2, 1.7, -6.9)},
	"stove":   {"name": "灶台",   "stand": Vector3(-7.4, 0, -1.6), "tag": Vector3(-8.9, 1.7, -1.6)},
	"storage": {"name": "储物柜", "stand": Vector3(-7.6, 0, 1.9),  "tag": Vector3(-9.3, 2.4, 2.2)},
	"bench":   {"name": "工作台", "stand": Vector3(7.5, 0, -1.2),  "tag": Vector3(9.0, 1.7, -1.2)},
	"well":    {"name": "水井",   "stand": Vector3(-3.0, 0, 0.1),  "tag": Vector3(-3.0, 2.6, 1.5)},
	"garden":  {"name": "菜畦",   "stand": Vector3(3.5, 0, -0.1),  "tag": Vector3(3.5, 1.4, 2.3)},
	"gate":    {"name": "大门",   "stand": Vector3(0, 0, 5.8),     "tag": Vector3(0, 3.9, 7.0)},
}
const PLOT_POS := [Vector3(2.6, 0, 1.4), Vector3(4.5, 0, 1.4), Vector3(2.6, 0, 3.3), Vector3(4.5, 0, 3.3)]

var sky: Dictionary
var halls := []
var gate: Dictionary
var lanterns := []
var spot_nodes := {}
var nav_region: NavigationRegion3D
var _window: Node3D
var _dynamic: Dictionary = {}
var _night := false
var _baked := false
var _garden_body: StaticBody3D
var _garden_rows := 0


func _ready() -> void:
	add_to_group("navsrc")
	sky = SkyKit.make(self, 26.0)
	# The overhead camera looks through many metres of fog even at nearby props.
	# Keep the courtyard legible instead of tinting the entire scene grey.
	sky.fog_mul = 0.12
	_ground()
	_buildings()
	_furniture()
	_decor()
	for key in ["sacks", "firewood", "wood", "garden", "devices", "extras", "furnish"]:
		_dynamic[key] = K.node(self, Vector3.ZERO, Vector3.ZERO, key)
	# 菜畦整块的拾取碰撞（菜苗每次重画，碰撞固定在这里；大小随画出来的畦数变，见 _fit_garden）
	var garden_root := K.node(self, Vector3.ZERO, Vector3.ZERO, "spot_garden")
	_garden_body = K.collider(garden_root, Vector3.ONE, Vector3.ZERO, {"spot": "garden"})
	spot_nodes["garden"] = _dynamic.garden
	# 静态的方块按材质合并；会动、会重画、要描边的留着
	K.merge_static(self, [gate.node, _window] + spot_nodes.values() + _dynamic.values())


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
	# 门外街道（青石）
	K.box(self, Vector3(60, 0.04, 6), K.mat(Color("#8f8b84"), 0.95), Vector3(0, 0.02, 11))
	K.box(self, Vector3(60, 0.045, 1.2), K.SNOW, Vector3(0, 0.025, 13.6))
	# 街对面的人家（剪影）
	for k in 6:
		var x := -25.0 + k * 10.0
		var h := 4.0 + (k % 3) * 0.8
		K.box(self, Vector3(8, h, 4), K.WALL_SHADE, Vector3(x, h / 2.0, 17))
		K.box(self, Vector3(8.4, 0.3, 4.4), K.ROOF, Vector3(x, h + 0.15, 17))
		Arch.ma_tou(self, x - 4.0, 17, 4.0, h, 1.2)
	for x in [-14.0, 14.0]:
		Props.plum_tree(self, Vector3(x, 0, 12.5))


func _buildings() -> void:
	halls.append(Arch.hall(self, Vector3(0, 0, -5.75), 0, 12.0, 4.5, 3.6, ["back", "left", "right"]))
	halls.append(Arch.hall(self, Vector3(-8.0, 0, -0.5), 90, 6.0, 3.6, 3.2, ["back"], false))
	halls.append(Arch.hall(self, Vector3(8.0, 0, -0.5), -90, 6.0, 3.6, 3.2, ["back"], false))
	Arch.wall(self, Vector3(-10.2, 0, -8.2), Vector3(10.2, 0, -8.2), 3.4)
	Arch.wall(self, Vector3(-10.2, 0, -8.2), Vector3(-10.2, 0, 7.0), 3.0)
	Arch.wall(self, Vector3(10.2, 0, -8.2), Vector3(10.2, 0, 7.0), 3.0)
	Arch.wall(self, Vector3(-10.2, 0, GATE_Z), Vector3(-1.9, 0, GATE_Z), 3.0)
	Arch.wall(self, Vector3(1.9, 0, GATE_Z), Vector3(10.2, 0, GATE_Z), 3.0)
	gate = Arch.gate(self, Vector3(0, 0, GATE_Z))
	_register("gate", gate.node)
	lanterns.append_array(gate.lanterns)
	_window = Arch.lattice_window(self, WINDOW_POS)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		lanterns.append(Arch.lantern(self, Vector3(x, 3.0, -2.9)))


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
	# 西间：榻
	var bed := _spot_root("bed")
	if Assets.prop(bed, "chinese_sofa", Vector3(-4.0, 0, -7.25)) == null:
		Props.bed(bed, Vector3(-4.0, 0, -6.9))
	_register("bed", bed)
	Assets.prop(self, "ceramic_vase_02", Vector3(-5.5, 0, -7.55))
	# 东间：茶几当书案，配个凳子
	var desk := _spot_root("desk")
	if Assets.prop(desk, "chinese_tea_table", Vector3(4.2, 0, -6.9)) != null:
		Assets.prop(desk, "chinese_stool", Vector3(4.2, 0, -6.15), 180.0)
		Props.desk_items(desk, Vector3(4.2, 0.5, -6.9))
	else:
		Props.desk(desk, Vector3(4.2, 0, -6.9))
	_register("desk", desk)
	_register("well", Props.well(_spot_root("well"), Vector3(-3.0, 0, 1.5)))
	# 灶房：顶天的立柜存货，旁边一口陶罐
	var storage := _spot_root("storage")
	if Assets.prop(storage, "chinese_cabinet", Vector3(-9.45, 0, 2.2), 90.0) == null:
		Props.cabinet(storage, Vector3(-9.3, 0, 2.2), 90)
	_register("storage", storage)
	Assets.prop(self, "ceramic_pot", Vector3(-9.2, 0, 3.4), 30.0)
	_register("bench", Props.workbench(_spot_root("bench"), Vector3(9.0, 0, -1.2), -90))


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
	Props.bookshelf(self, Vector3(5.6, 0, -7.6))
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


## 导航网格：按院里的静态碰撞烘焙，点哪儿走哪儿。
func _bake_nav() -> void:
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
	nm.filter_baking_aabb = AABB(Vector3(-10.5, -1, -8.5), Vector3(21, 6, 16))
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_region.bake_navigation_mesh(false)


# ---------- 按局面重画 ----------

func sync(run: Dictionary) -> void:
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
	var plots: Array = run.get("plots", [])
	var crops: Dictionary = Data.table("crops")
	_fit_garden(ceili(maxi(plots.size(), 2) / 2.0))
	for k in maxi(plots.size(), 2):
		if k < plots.size():
			var plot: Dictionary = plots[k]
			var growth := 0.0
			if plot.crop != "":
				growth = float(plot.days) / float(crops[plot.crop].days)
			Props.garden_plot(_dynamic.garden, PLOT_POS[k], plot.crop, growth, Post.plot_dry(run, plot))
		else:
			Props.garden_plot(_dynamic.garden, PLOT_POS[k], "", 0, true)


## 玩家自己添置的家具：按 run.furniture 摆，位置和朝向都听数据。
## 默认那六件是场景里固定的，这里只画多出来的，免得画两遍。
func _rebuild_furniture(run: Dictionary) -> void:
	for spot in _furn_spots.keys():
		spot_nodes.erase(spot)
	_furn_spots.clear()
	K.clear(_dynamic.furnish)
	for f in run.get("furniture", []):
		var id := str(f.id)
		if id in STATIC_FURN:
			continue
		var spot := "f_%d" % int(f.uid)
		var root := K.node(_dynamic.furnish, Vector3(float(f.x), 0.0, float(f.z)), Vector3(0, float(f.rot), 0), spot)
		_furn_mesh(root, id)
		var sz := Home.size_of(id, int(f.rot))
		K.collider(root, Vector3(sz.x, 0.9, sz.y), Vector3(0, 0.45, 0), {"spot": spot})
		_register(spot, root)
		_furn_spots[spot] = int(f.uid)


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
			for i in 3:
				K.box(root, Vector3(0.16, 0.22, 0.16), K.GREEN, Vector3(-0.42 + i * 0.42, 0.48, 0))
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
	var facs: Array = run.get("facilities", [])
	var stove_root := K.node(_dynamic.extras, Vector3.ZERO, Vector3.ZERO, "spot_stove")
	Props.stove(stove_root, Vector3(-8.9, 0, -1.6), 90, "stove" in facs)
	_register("stove", stove_root)
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
		K.box(_dynamic.extras, Vector3(1.4, 0.08, 1.0), K.WOOD, Vector3(6.0, 0.09, -2.4))
		K.box(_dynamic.extras, Vector3(0.1, 0.1, 0.5), K.mat(K.GOLD, 0.4), Vector3(6.0, 0.16, -2.4))
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
	if _baked:
		nav_region.bake_navigation_mesh(true)


var _fight_figs := []
var _debris: Array = []
var _rubbles: Dictionary = {}   # 砸烂的家具 spot -> 塌料节点
var _furn_spots: Dictionary = {}  # 玩家添置的家具 spot -> uid
## 场景里本来就有的六件（床、书案、柜子、灶台、工作台，位置固定），添置的只画多出来的
const STATIC_FURN := ["bed", "desk", "storage", "stove", "bench"]

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
	var broken: Array = run.get("broken", [])
	for pair in [["stove", Vector3(-8.9, 0, -1.6)], ["bench", Vector3(9.0, 0, -1.2)]]:
		if str(pair[0]) in broken:
			_wreck_spot(str(pair[0]), pair[1])
		else:
			_heal_spot(str(pair[0]))


func _wreck_spot(spot: String, pos: Vector3) -> void:
	if spot_nodes.has(spot):
		spot_nodes[spot].visible = false
	if _rubbles.has(spot):
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
	_set_lanterns(h >= 17.5 or h < 6.5)


func set_preset(preset: String, snow := 400) -> void:
	SkyKit.apply(sky, preset, snow)
	_set_lanterns(preset in ["dusk", "night", "blood"])


func _set_lanterns(lit: bool) -> void:
	if lit == _night:
		return
	_night = lit
	for lan in lanterns:
		Arch.set_lantern(lan, lit)


# ---------- 交互与遮挡 ----------

## 离 pos 最近、在半径内的可交互物 id；没有返回空串。
func nearest_spot(pos: Vector3, radius := 1.8) -> String:
	var best := ""
	var best_d := radius
	for id in SPOTS:
		var p: Vector3 = SPOTS[id].stand
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < best_d:
			best = id
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
		return {"spot": hit.collider.get_meta("spot")}
	var p: Vector3 = hit.position
	if p.y < 0.3 and absf(p.x) < 10.0 and p.z > -8.0 and p.z < GATE_Z - 0.3:
		return {"ground": Vector3(p.x, 0, p.z)}
	return {}


## 人在屋里（踩木地板）吗。
func indoors(pos: Vector3) -> bool:
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
