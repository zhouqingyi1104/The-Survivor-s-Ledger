extends Node3D
## 外出搜寻的废墟：每处保有自己的空间格局，入口在南。能翻的地方发金光，翻过就暗下去。
## 每个地点有自己的陈设（义庄是棺材、县学是书架……），后墙外有僵尸游荡；阳气外泄满了会有一只扑进来。

const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Figure = preload("res://scripts/world/character.gd")
const Data = preload("res://scripts/core/data.gd")
const Explore = preload("res://scripts/core/explore.gd")

const ENTRY := Vector3(0, 0, 5.2)
# 熟练搜寻的四处物资、邻人药账和主线专点可同时存在，六处必须各自可达。
const SPOT_POS := [Vector3(-5.0, 0, -3.6), Vector3(0.0, 0, -4.4), Vector3(5.0, 0, -3.6), Vector3(-5.6, 0, 1.6), Vector3(5.6, 0, 1.6), Vector3(0.0, 0, 1.6)]
# 按地点分配各目标的空间序列：前后、两翼和中轴不再统一排成 3×2。
# 第五、六项保留给邻人及主线专点；最近交互始终使用实际位置。
const SITE_SPOT_POS := {
	"rice_ruin": [Vector3(-5, 0, -4), Vector3(3, 0, -4), Vector3(-3, 0, -1), Vector3(5, 0, 0), Vector3(-5, 0, 2.7), Vector3(0, 0, 1.6)],
	"city_god": [Vector3(0, 0, -4.4), Vector3(-5, 0, -3), Vector3(5, 0, -3), Vector3(-5, 0, 2.1), Vector3(5, 0, 2.1), Vector3(0, 0, 1.6)],
	"school": [Vector3(-5, 0, -4), Vector3(4, 0, -4), Vector3(0, 0, -2.7), Vector3(-5, 0, 2.4), Vector3(5, 0, 2.4), Vector3(0, 0, 1.6)],
	"pharmacy_ruin": [Vector3(-5, 0, -4), Vector3(4.5, 0, -4), Vector3(0, 0, -2.6), Vector3(-5.5, 0, 2.4), Vector3(5.4, 0, 2.3), Vector3(0, 0, 1.6)],
	"lumber": [Vector3(-5.5, 0, -3.8), Vector3(1.0, 0, -4.4), Vector3(5.2, 0, -2.7), Vector3(-4.0, 0, 0.2), Vector3(5.0, 0, 2.8), Vector3(0, 0, 1.6)],
	"mortuary": [Vector3(-5, 0, -3.6), Vector3(5, 0, -3.6), Vector3(0, 0, -4.4), Vector3(-5.5, 0, 1.8), Vector3(5.5, 0, 1.8), Vector3(0, 0, 1.6)],
	"granary": [Vector3(-5, 0, -4), Vector3(5, 0, -4), Vector3(-4.5, 0, -0.3), Vector3(5, 0, 0.1), Vector3(-4.8, 0, 2.7), Vector3(0, 0, 1.6)],
	"taoist_temple": [Vector3(-5, 0, -3.8), Vector3(5, 0, -3.8), Vector3(0, 0, -4.4), Vector3(-5.5, 0, 2.1), Vector3(5.5, 0, 2.1), Vector3(0, 0, 1.6)],
}
const SPOT_RADIUS := 1.7

var sky: Dictionary
var point := ""
var player_ref: Node3D
var _spots := []
var _wanderers := []
var _hunter: Node3D


func setup(pid: String, spots: Array) -> void:
	point = pid
	sky = SkyKit.make(self, 12.0)
	SkyKit.apply(sky, "ruin", 160)
	_room()
	_dress(pid)
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
	_site_shell()
	_site_layout()
	# 碎砖、积雪
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(point)
	for k in 26:
		var p := Vector3(rng.randf_range(-7.4, 7.4), 0.08, rng.randf_range(-5.5, 5.5))
		if p.distance_to(ENTRY) < 2.0:
			continue
		K.box(self, Vector3(rng.randf_range(0.2, 0.5), rng.randf_range(0.1, 0.3), rng.randf_range(0.2, 0.5)), K.STONE_DARK, p, Vector3(0, rng.randf_range(0, 90), rng.randf_range(-15, 15)))
	for k in 3:
		K.sphere(self, 1.1, K.mat(K.SNOW), Vector3(-3.0 + k * 3.0, -0.6, -5.4), Vector3(1.4, 0.7, 0.8))
	K.light(self, Color("#8fa2c8"), 0.8, 14.0, Vector3(0, 6, -5))
	_exit_marker()


## 外围始终限制在原来的 16×12 范围内；墙的开合、材质和残存屋架随用途变化。
## 摄影机在南侧，前墙保持低矮，让玩家和搜寻目标可见。
func _site_shell() -> void:
	var outdoor := point in ["lumber", "granary"]
	var floor_mat = K.SNOW if point == "lumber" else (K.STONE if point in ["city_god", "mortuary", "taoist_temple", "granary"] else K.WOOD)
	K.box(self, Vector3(16, 0.06, 12), floor_mat, Vector3(0, 0.03, 0))
	if point == "lumber":
		# 木场是积雪的露天场地，运输过的地方露出泥土。
		K.box(self, Vector3(4.0, 0.02, 11.0), K.EARTH, Vector3(0, 0.07, 0))
	elif point == "granary":
		K.box(self, Vector3(3.0, 0.02, 11.0), K.EARTH, Vector3(0, 0.07, 0))
	var dirty = K.mat(K.WALL)
	var h := 1.15 if outdoor else 3.4
	for sx in [-1, 1]:
		K.solid(self, Vector3(6.5, h, 0.4), dirty, Vector3(sx * 4.75, h / 2.0, -6))
		# 米行缺一面店墙；讲堂有前廊；庙观为敞开的殿院。
		var side_h := h
		if point == "rice_ruin" and sx == 1: side_h = 1.2
		if point == "school" and sx == -1: side_h = 1.6
		if point in ["city_god", "taoist_temple"]: side_h = 1.25
		K.solid(self, Vector3(0.4, side_h, 12.4), dirty, Vector3(sx * 8, side_h / 2.0, 0))
		K.solid(self, Vector3(7.0, 0.9, 0.4), dirty, Vector3(sx * 4.5, 0.45, 6))
	# 不让角色从后方穿出，但缺口保留视线，仍可看见游荡者。
	K.box(self, Vector3(3.0, 0.8, 0.4), dirty, Vector3(0, 0.4, -6))
	K.collider(self, Vector3(3.0, 3.4, 0.4), Vector3(0, 1.7, -6))
	if not outdoor:
		# 屋架不挡镜头，前后各有不同的坍塌轮廓。
		for sx in [-1, 1]:
			K.box(self, Vector3(0.25, 3.0, 0.25), K.WOOD, Vector3(sx * 7.5, 1.5, -5.55))
		K.box(self, Vector3(15.0, 0.3, 0.3), K.WOOD, Vector3(0, 3.0, -5.55))
		K.box(self, Vector3(5.4, 0.22, 0.3), K.WOOD, Vector3(-4.1, 0.25, 0.3), Vector3(0, -28, 4))
		for k in 9:
			K.box(self, Vector3(0.55, 0.07, 0.38), K.ROOF, Vector3(-6.2 + k * 1.55, 0.08, -5.2), Vector3(0, k * 17, 8))
	else:
		# 无顶木场和粮仓各留一段棚檐，不以一整间废屋冒充露天场所。
		for sx in [-1, 1]:
			K.box(self, Vector3(0.25, 2.8, 0.25), K.WOOD, Vector3(sx * 7.2, 1.4, -5.5))
		K.box(self, Vector3(14.5, 0.2, 0.25), K.WOOD, Vector3(0, 2.8, -5.5))


## 低矮隔断是真实碰撞体，两端留出宽通道；不会遮住角色和交互标记。
func _divider(size: Vector3, at: Vector3, material = K.WOOD) -> void:
	K.solid(self, size, material, at)


func _site_layout() -> void:
	match point:
		"rice_ruin":
			# 米行：门内柜台与左右分仓，中央通往后场。
			for sx in [-1, 1]:
				_divider(Vector3(3.0, 0.8, 0.45), Vector3(sx * 4.3, 0.4, -0.9))
				K.box(self, Vector3(3.1, 0.08, 0.6), K.WOOD_LIGHT, Vector3(sx * 4.3, 0.82, -0.9))
		"pharmacy_ruin":
			# 前堂看诊柜台、后堂炮制区，用断开的柜台形成不同空间。
			for sx in [-1, 1]:
				_divider(Vector3(0.25, 1.65, 2.0), Vector3(sx * 2.7, 0.825, -3.0))
				for row in 3:
					K.box(self, Vector3(0.28, 0.08, 1.8), K.WOOD_LIGHT, Vector3(sx * 2.7, 0.4 + row * 0.4, -3.0))
			for sx in [-1, 1]:
				_divider(Vector3(2.5, 1.0, 0.5), Vector3(sx * 4.0, 0.5, -0.8))
				K.box(self, Vector3(2.6, 0.08, 0.6), K.WOOD_LIGHT, Vector3(sx * 4.0, 1.04, -0.8))
			K.box(self, Vector3(0.12, 0.03, 3.5), K.mat(Color("#69483e")), Vector3(1.1, 0.08, 1.8), Vector3(0, 18, 0))
		"school":
			# 前廊入讲堂；课桌错落，后部高台为讲席。
			K.box(self, Vector3(5.4, 0.12, 1.1), K.STONE, Vector3(0, 0.08, -5.1))
			# 书卷与条案排列成讲堂，斋舍在两侧。
			for sx in [-1, 1]:
				K.box(self, Vector3(0.18, 2.1, 1.8), K.WOOD, Vector3(sx * 7.45, 1.05, -2.0))
				for row in 4:
					K.box(self, Vector3(0.2, 0.3, 1.6), K.mat(Color("#a69270")), Vector3(sx * 7.3, 0.35 + row * 0.43, -2.0))
			for sx in [-1, 1]:
				for z in [-1.0, 3.5]:
					_divider(Vector3(1.4, 0.65, 0.5), Vector3(sx * 3.4, 0.325, z))
					K.box(self, Vector3(1.5, 0.08, 0.6), K.WOOD_LIGHT, Vector3(sx * 3.4, 0.69, z))
		"city_god", "taoist_temple":
			# 两座庙宇均沿中轴入殿；偏殿低围与地面界线不同。
			K.box(self, Vector3(2.3, 0.025, 10.2), K.STONE_DARK, Vector3(0, 0.07, -0.1))
			for sx in [-1, 1]:
				K.solid(self, Vector3(0.32, 2.7, 0.32), K.LACQUER, Vector3(sx * 2.7, 1.35, -4.75))
				_divider(Vector3(0.3, 0.75, 2.2), Vector3(sx * 2.6, 0.375, -1.9), K.LACQUER)
				if point == "taoist_temple":
					K.box(self, Vector3(2.7, 0.1, 1.6), K.EARTH, Vector3(sx * 6.0, 0.09, -0.9))
				else:
					K.box(self, Vector3(2.2, 0.12, 1.5), K.STONE_DARK, Vector3(sx * 6.0, 0.09, -0.9))
		"mortuary":
			# 中央停灵通道，左右屏障和白幡围出停棺区。
			K.box(self, Vector3(2.5, 0.025, 10.0), K.STONE_DARK, Vector3(0, 0.07, -0.1))
			for sx in [-1, 1]:
				_coffin(Vector3(sx * 3.7, 0, -1.5), 90.0, sx == -1)
				_divider(Vector3(0.18, 1.05, 2.0), Vector3(sx * 2.5, 0.525, -1.9))
				K.box(self, Vector3(0.05, 1.0, 1.7), K.mat(Color("#c7c1b3")), Vector3(sx * 2.5, 1.7, -1.9))
		"lumber":
			# 露天木场：堆料两翼夹着雪中拖运道。
			for sx in [-1, 1]:
				# 粗木沿边堆放，夹出无遮盖的拖运通道。
				for row in 3:
					K.cyl(self, 0.2, 0.2, 4.0, K.WOOD_LIGHT, Vector3(sx * 6.8, 0.22 + row * 0.34, -2.3), Vector3(90, 0, 0))
				for z in [-1.2, 2.7]:
					K.box(self, Vector3(2.4, 0.25, 0.25), K.WOOD, Vector3(sx * 4.0, 0.35, z))
					for xoff in [-0.8, 0.8]:
						K.box(self, Vector3(0.13, 0.65, 0.13), K.WOOD_LIGHT, Vector3(sx * 4.0 + xoff, 0.325, z))
		"granary":
			# 官仓：东西两仓的半高木隔板，中央是粮车经过的土路。
			for sx in [-1, 1]:
				K.box(self, Vector3(4.3, 0.05, 5.0), K.WOOD, Vector3(sx * 5.3, 0.08, -2.3))
				_divider(Vector3(0.25, 1.25, 3.0), Vector3(sx * 2.7, 0.625, -2.0))
				K.box(self, Vector3(0.12, 0.12, 3.1), K.WOOD_LIGHT, Vector3(sx * 2.7, 1.28, -2.0))
				for xoff in [-0.8, 0.8]:
					K.box(self, Vector3(0.12, 1.5, 0.12), K.WOOD_LIGHT, Vector3(sx * 5.8 + xoff, 0.75, -4.8))
				K.box(self, Vector3(1.8, 0.16, 0.16), K.WOOD, Vector3(sx * 5.8, 1.45, -4.8))


## 出口只作可见标识，不改变入口或通路的碰撞。
func _exit_marker() -> void:
	for sx in [-1, 1]:
		K.box(self, Vector3(0.14, 2.25, 0.14), K.WOOD_LIGHT, Vector3(sx * 1.3, 1.125, 5.85))
	K.box(self, Vector3(2.75, 0.16, 0.16), K.WOOD_LIGHT, Vector3(0, 2.2, 5.85))
	K.text3d(self, "出口 · 回宅", Vector3(0, 2.55, 5.75), 52, Color("#e6d5ac"), true, 0.008)
	# 一条低矮的石槛可从房间另一侧辨认方向，角色仍能走过。
	K.box(self, Vector3(2.0, 0.025, 0.45), K.mat(Color("#c2b18e")), Vector3(0, 0.045, 5.0))


func _dress(pid: String) -> void:
	# 墙边场景布置均为无碰撞装饰；保留六个搜寻点和南侧出口的行走空间。
	_site_detail(pid)
	match pid:
		"mortuary":
			for k in 4:
				_coffin(Vector3(-6.5 + k * 1.3, 0, 4.2), 90.0, k % 2 == 0)
			for k in 6:
				K.box(self, Vector3(0.5, 1.6, 0.02), K.mat(Color("#d9d4c4"), 0.9, 0.0, 0.85), Vector3(-6 + k * 2.4, 2.5, -5.7))
				K.box(self, Vector3(0.12, 0.3, 0.01), K.mat(K.PAPER, 0.8, 0.5), Vector3(-6 + k * 2.4, 1.7, -5.68))
			sky.env.fog_light_color = Color("#1f2a24")
		"city_god":
			K.box(self, Vector3(3.0, 1.0, 1.2), K.LACQUER, Vector3(0, 0.5, -5.1))
			var statue: Node3D = Figure.new()
			add_child(statue)
			statue.setup("villager", Color("#6a2a22"))
			statue.position = Vector3(0, 1.0, -5.3)
			statue.scale = Vector3.ONE * 1.6
			for sx in [-1, 1]:
				K.cyl(self, 0.18, 0.2, 3.4, K.LACQUER, Vector3(sx * 2.6, 1.7, -4.6))
		"school":
			for k in 4:
				var x: float = [-6.5, -3.5, 3.5, 6.5][k]
				var shelf := K.node(self, Vector3(x, 0, 4.4), Vector3(0, 0, 70 if k == 1 else 0))
				K.box(shelf, Vector3(1.6, 2.2, 0.4), K.WOOD, Vector3(0, 1.1, 0))
				for r in 4:
					K.box(shelf, Vector3(1.4, 0.3, 0.3), K.mat(Color("#b9a27a")), Vector3(0, 0.3 + r * 0.5, 0.06))
		"pharmacy_ruin":
			for x in [-5.5, 5.5]:
				var cab := K.node(self, Vector3(x, 0, 5.3))
				K.box(cab, Vector3(2.4, 2.2, 0.5), K.WOOD, Vector3(0, 1.1, 0))
				for r in 5:
					for c in 6:
						K.box(cab, Vector3(0.34, 0.34, 0.04), K.WOOD_LIGHT, Vector3(-1.0 + c * 0.4, 0.25 + r * 0.4, -0.27))
		"lumber":
			Props.wood_pile(self, Vector3(-5, 0, 4.3), 10)
			Props.wood_pile(self, Vector3(5, 0, 4.3), 9)
		"granary":
			for x in [-5.0, 5.0]:
				K.cyl(self, 0.0, 1.6, 1.4, K.RICE_SACK, Vector3(x, 0.7, 4.0), Vector3.ZERO, 10)
		"taoist_temple":
			K.box(self, Vector3(3.4, 1.0, 1.0), K.LACQUER, Vector3(0, 0.5, -5.2))
			for k in 7:
				var a := deg_to_rad(-60 + k * 20)
				var p := Vector3(sin(a) * 1.4, 1.1, -5.2 + cos(a) * 0.3 - 0.2)
				K.cyl(self, 0.06, 0.08, 0.12, K.GOLD, p)
				K.sphere(self, 0.05, K.mat(Color("#7dffb0"), 0.4, 4.0), p + Vector3(0, 0.1, 0))
			K.light(self, Color("#7dffb0"), 1.2, 6.0, Vector3(0, 1.6, -4.8))
			for sx in [-1, 1]:
				K.cyl(self, 0.18, 0.2, 3.4, K.LACQUER, Vector3(sx * 3.0, 1.7, -4.6))
		_:
			K.box(self, Vector3(3.0, 1.0, 0.8), K.WOOD, Vector3(-5.0, 0.5, 4.6))
			Props.rice_sacks(self, Vector3(5.5, 0, 4.5), 3)


func _site_detail(pid: String) -> void:
	match pid:
		"rice_ruin", "granary":
			# 米行的量米台和官仓的分仓木栏。
			for sx in [-1, 1]:
				for k in 3:
					K.box(self, Vector3(0.28, 1.4, 0.28), K.WOOD, Vector3(sx * 7.5, 0.7, -3.9 + k * 2.0))
				K.box(self, Vector3(0.12, 0.12, 4.5), K.WOOD_LIGHT, Vector3(sx * 7.5, 1.15, -1.9))
			if pid == "granary":
				K.text3d(self, "官仓", Vector3(0, 2.7, -5.65), 64, Color("#c9b48d"), true, 0.008)
			else:
				for k in 3:
					K.cyl(self, 0.28, 0.24, 0.38, K.WOOD_LIGHT, Vector3(-7.1, 0.19, -4.9 + k * 0.7))
		"school":
			# 残存的讲堂黑板与两侧散落的课册。
			K.box(self, Vector3(3.3, 1.15, 0.12), K.WOOD, Vector3(0, 2.15, -5.7))
			K.text3d(self, "温故知新", Vector3(0, 2.25, -5.55), 52, Color("#d6c7a6"), true, 0.008)
			for sx in [-1, 1]:
				for k in 4:
					K.box(self, Vector3(0.38, 0.06, 0.28), K.mat(Color("#a99a7b")), Vector3(sx * (7.0 + 0.12 * (k % 2)), 0.09 + 0.06 * k, -3.8 + k * 1.4), Vector3(0, k * 18, 0))
		"pharmacy_ruin":
			# 药铺侧墙药格与晾药架，轮廓不同于普通粮仓。
			for sx in [-1, 1]:
				K.box(self, Vector3(2.3, 1.65, 0.16), K.WOOD, Vector3(sx * 4.4, 2.0, -5.7))
				for row in 3:
					for col in 5:
						K.box(self, Vector3(0.36, 0.38, 0.04), K.WOOD_LIGHT, Vector3(sx * 4.4 - 0.8 + col * 0.4, 1.45 + row * 0.48, -5.58))
			K.text3d(self, "回春堂", Vector3(0, 2.9, -5.65), 60, Color("#d2c39c"), true, 0.008)
			for sx in [-1, 1]:
				for k in 4:
					K.box(self, Vector3(0.18, 0.12, 0.9), K.WOOD_LIGHT, Vector3(sx * 7.7, 1.3 + k * 0.42, -3.7))
				for k in 3:
					K.cyl(self, 0.16, 0.14, 0.36, K.mat(Color("#766e59")), Vector3(sx * 7.0, 0.2, -4.8 + k * 0.5))
		"lumber":
			# 木场两侧锯木架和沿墙堆放的长木。
			K.box(self, Vector3(3.4, 0.14, 0.14), K.WOOD_LIGHT, Vector3(0, 2.2, -5.68))
			for sx in [-1, 1]:
				K.box(self, Vector3(0.16, 2.4, 0.16), K.WOOD, Vector3(sx * 1.6, 1.2, -5.68))
			K.text3d(self, "木料场", Vector3(0, 2.65, -5.55), 58, Color("#cbb897"), true, 0.008)
			for sx in [-1, 1]:
				for k in 4:
					K.cyl(self, 0.18, 0.18, 3.6, K.WOOD_LIGHT, Vector3(sx * 7.2, 0.2 + k * 0.31, -3.6 + (k % 2) * 0.12), Vector3(90, 0, 0))
		"mortuary":
			# 墙侧停灵的白幡，和庙宇红柱形成清楚区别。
			for sx in [-1, 1]:
				for k in 3:
					K.box(self, Vector3(0.04, 1.6, 0.55), K.mat(Color("#c9c5b8")), Vector3(sx * 7.7, 2.1, -4.5 + k * 2.0))
		"city_god", "taoist_temple":
			for sx in [-1, 1]:
				K.box(self, Vector3(0.22, 2.8, 0.22), K.LACQUER, Vector3(sx * 7.5, 1.4, -2.2))
				K.box(self, Vector3(0.08, 1.2, 0.45), K.mat(Color("#a98a50") if pid == "taoist_temple" else Color("#9d4a35")), Vector3(sx * 7.36, 2.05, -2.2))
			K.text3d(self, "青云观" if pid == "taoist_temple" else "城隍庙", Vector3(0, 3.1, -5.6), 58, Color("#d2b477"), true, 0.008)


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
	var positions: Array = SITE_SPOT_POS.get(point, SPOT_POS)
	var pos: Vector3 = positions[k % positions.size()]
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
	var label := K.text3d(n, spot_name, Vector3(0, 2.3, 0), 64, Color("#ffe3a0"), true, 0.008)
	_spots.append({"pos": pos, "glow": glow, "label": label, "name": spot_name})


func sync(run: Dictionary) -> void:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty():
		return
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
		var special_text := " · 特色：" + str(Explore.SITE_TITLES.get(point, "")) if special else ""
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
func nearest(pos: Vector3) -> int:
	var flat := Vector3(pos.x, 0, pos.z)
	if flat.distance_to(ENTRY) < 1.6:
		return -2
	var best := -1
	var best_d := SPOT_RADIUS
	for k in _spots.size():
		var d := flat.distance_to(_spots[k].pos)
		if d < best_d:
			best = k
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
