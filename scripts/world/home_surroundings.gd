extends RefCounted
## C0 宅院四周景物工厂（纯视觉背景，不进核心合并、无碰撞 / 无导航 / 无灯光 / 无交互）。
##
## build(parent, layout) 在 parent 下建名为 "surroundings" 的 Node3D，含 near / middle /
## far 三层；近景单独按材质合并（投影），中远景一起合并（关阴影），另加每户一条筒瓦
## MultiMesh。所有形体都是基本体（盒 / 柱 / 棱柱 / 球），复用 K 色板与 Arch.roof /
## Arch.ma_tou（这两个函数不产生碰撞体）；绝不调用 Arch.wall/hall/gate（会生成
## StaticBody），不放 OmniLight / 交互脚本，也不调用带碰撞的 Props.*。
##
## 布局按战术相机实测视野反推：默认机位俯角 54° / fov 42 / dist17，画面上缘只能看到
## 约 23m，因此近环压在 12-28m；中景 30-52m 服务广角（dist26/-50° 可见到 ~38m）；
## 城墙 62m、远山 95-150m 服务低机位（-24°）天际线。
##
## 配置独立读取 res://data/home_surroundings.json（不走 Data.table），文件缺失 / 解析失败 /
## 字段缺失一律回退内置默认值。布局由固定常量决定，确定性可重复构建（见 plan()）。

const K = preload("res://scripts/world/kit.gd")
const Arch = preload("res://scripts/world/arch.gd")

const CONFIG_PATH := "res://data/home_surroundings.json"

# 近景宅院：x/z 米，rot_y 让门面朝街/巷，w 面宽、d 进深、h 檐高，style 0-3 决定门窗/附房变化。
# 正面约定局部 +Z；0=朝南(+Z)，180=朝北(-Z)，90=朝东(+X)，-90=朝西(-X)。
# 核心约束：核心 bounds x±10.2 / z[-8.2,7]；迎战通道 |x|≤3, z7.5..17 净高。
const NEAR_HOUSES: Array = [
	# 北排（贴厢房北端之外，越过山墙可见；正门机位两角）
	{"x": -14.5, "z": -11.0, "rot": 90.0, "w": 6.0, "d": 3.8, "h": 4.6, "style": 0, "annex": false},
	{"x": 14.5, "z": -11.0, "rot": -90.0, "w": 6.0, "d": 3.8, "h": 4.6, "style": 1, "annex": false},
	{"x": -6.0, "z": -15.0, "rot": 0.0, "w": 5.5, "d": 4.0, "h": 3.6, "style": 2, "annex": false},
	{"x": 6.0, "z": -15.0, "rot": 0.0, "w": 5.5, "d": 4.0, "h": 3.8, "style": 3, "annex": false},
	{"x": -20.0, "z": -18.0, "rot": 0.0, "w": 6.5, "d": 4.0, "h": 3.5, "style": 1, "annex": true},
	{"x": 0.0, "z": -22.0, "rot": 0.0, "w": 8.0, "d": 4.5, "h": 3.6, "style": 2, "annex": true},
	{"x": 20.0, "z": -18.0, "rot": 0.0, "w": 6.0, "d": 4.0, "h": 3.4, "style": 0, "annex": false},
	# 南排（后门机位看对街：贴厢房南端之外，夹着门前石板路，中路让开）
	{"x": -14.5, "z": 10.5, "rot": 180.0, "w": 6.0, "d": 4.0, "h": 4.6, "style": 3, "annex": true},
	{"x": 14.5, "z": 10.5, "rot": 180.0, "w": 6.0, "d": 4.0, "h": 4.6, "style": 0, "annex": false},
	{"x": -7.5, "z": 18.5, "rot": 180.0, "w": 5.5, "d": 4.0, "h": 3.6, "style": 1, "annex": false},
	{"x": 7.5, "z": 18.5, "rot": 180.0, "w": 5.5, "d": 4.0, "h": 3.7, "style": 2, "annex": false},
	{"x": -18.0, "z": 21.5, "rot": 180.0, "w": 6.5, "d": 4.5, "h": 3.4, "style": 0, "annex": true},
	{"x": 18.0, "z": 21.5, "rot": 180.0, "w": 6.0, "d": 4.0, "h": 3.3, "style": 2, "annex": true},
	# 东西巷两侧（贴墙排 + 南端排）
	{"x": -14.0, "z": -5.0, "rot": 90.0, "w": 6.0, "d": 3.8, "h": 4.3, "style": 0, "annex": false},
	{"x": 14.0, "z": -5.0, "rot": -90.0, "w": 6.0, "d": 3.8, "h": 4.2, "style": 2, "annex": false},
	{"x": -14.0, "z": 3.0, "rot": 90.0, "w": 5.5, "d": 3.8, "h": 3.6, "style": 3, "annex": true},
	{"x": 14.0, "z": 3.0, "rot": -90.0, "w": 5.5, "d": 3.8, "h": 3.5, "style": 1, "annex": false},
	{"x": -13.5, "z": 17.5, "rot": 90.0, "w": 5.5, "d": 3.6, "h": 3.5, "style": 2, "annex": false},
	{"x": 13.5, "z": 17.5, "rot": -90.0, "w": 5.5, "d": 3.6, "h": 3.4, "style": 0, "annex": true},
	{"x": -21.0, "z": -11.0, "rot": 90.0, "w": 5.0, "d": 3.5, "h": 3.3, "style": 2, "annex": false},
	{"x": 21.0, "z": -11.0, "rot": -90.0, "w": 5.0, "d": 3.5, "h": 3.2, "style": 1, "annex": false},
	{"x": -21.0, "z": 12.0, "rot": 90.0, "w": 5.5, "d": 3.8, "h": 3.2, "style": 3, "annex": false},
	{"x": 21.0, "z": 12.0, "rot": -90.0, "w": 5.5, "d": 3.8, "h": 3.3, "style": 0, "annex": true},
]
# 孤立冬树（巷口 / 院落间隙，避开 actors 与迎战通道）。
const NEAR_TREES: Array = [
	{"x": -24.0, "z": -24.0, "blossom": false},
	{"x": 24.0, "z": -23.0, "blossom": false},
	{"x": -24.5, "z": 24.0, "blossom": true},
	{"x": 24.5, "z": 23.5, "blossom": true},
	{"x": 0.0, "z": -27.0, "blossom": false},
	{"x": -26.5, "z": 2.0, "blossom": false},
	{"x": 26.5, "z": -2.0, "blossom": false},
]
# 柴堆（自制纯视觉，不用 Props.wood_pile 脚本子树）。
const NEAR_WOOD: Array = [{"x": 26.0, "z": 8.0, "rot": 20.0}, {"x": -26.0, "z": -8.0, "rot": -30.0}]
# 静态灯杆：门前路一对 + 后巷一对（x>10.2 或 |x|>3，不进迎战通道）。
const NEAR_LANTERNS: Array = [
	{"x": 4.6, "z": 15.6}, {"x": -4.6, "z": 15.6},
	{"x": 10.8, "z": -10.2}, {"x": -10.8, "z": -10.2},
]

# 中景屋（r 30..53，服务广角 / 对角机位的屋脊层次）。
const MID_XZ: Array = [
	[-38.0, -8.0, -90.0], [38.0, -8.0, 90.0],
	[-30.0, 22.0, -90.0], [30.0, 22.0, 90.0],
	[-12.0, -34.0, 0.0], [12.0, -34.0, 0.0],
	[0.0, -50.0, 0.0], [0.0, 40.0, 180.0],
	[34.0, 30.0, 180.0], [-34.0, 30.0, 180.0],
	[48.0, -20.0, 90.0], [-48.0, -18.0, -90.0],
	[52.0, 8.0, 90.0], [-52.0, 8.0, -90.0],
]
const MID_TREE_ANGLES: Array = [22.0, 67.0, 112.0, 157.0, 202.0, 247.0, 292.0, 337.0, 92.0, 272.0]
const MID_WALLS: Array = [
	[18.0, -40.0, 26.0, -36.0], [-26.0, -38.0, -18.0, -40.0],
	[42.0, -32.0, 50.0, -26.0], [-52.0, -2.0, -46.0, 6.0],
	[18.0, 44.0, 26.0, 40.0], [-24.0, 42.0, -16.0, 44.0],
]

# 远景城墙：四面分段留豁口（不做成围城监狱），塔在段端；山脊环在 95..150 米。
const FAR_TOWERS: Array = [
	[-60.0, -62.0], [-24.0, -62.0], [24.0, -62.0], [60.0, -62.0],
	[-60.0, 62.0], [-22.0, 62.0], [22.0, 62.0], [60.0, 62.0],
	[-62.0, -48.0], [-62.0, -8.0], [-62.0, 8.0], [-62.0, 48.0],
	[62.0, -48.0], [62.0, -8.0], [62.0, 8.0], [62.0, 48.0],
]
const FAR_WALLS: Array = [
	[-60.0, -62.0, -24.0, -62.0], [24.0, -62.0, 60.0, -62.0],
	[-60.0, 62.0, -22.0, 62.0], [22.0, 62.0, 60.0, 62.0],
	[-62.0, -48.0, -62.0, -8.0], [-62.0, 8.0, -62.0, 48.0],
	[62.0, -48.0, 62.0, -8.0], [62.0, 8.0, 62.0, 48.0],
]
const PEAK_COLORS: Array = [Color("#6e7888"), Color("#5f6a7c"), Color("#7d8694")]


# ---------- 对外工厂 ----------

static func build(parent: Node3D, layout: Dictionary = {}, merge_layers: bool = true) -> Node3D:
	var cfg := load_config(CONFIG_PATH, layout)
	var root := K.node(parent, Vector3.ZERO, Vector3.ZERO, "surroundings")
	var near := K.node(root, Vector3.ZERO, Vector3.ZERO, "near")
	var middle := K.node(root, Vector3.ZERO, Vector3.ZERO, "middle")
	var far := K.node(root, Vector3.ZERO, Vector3.ZERO, "far")
	# 纯背景美术压缩：仅压扁 far 层 Y（低俯角下城墙/塔/山脊不再切掉城市上空），
	# 不动 XZ 摆位、近中景、核心建筑与影子；外部 JSON 钳制 0.2..1.0。
	far.scale.y = clampf(float(cfg.far.height_scale), 0.2, 1.0)
	var anchors := _make_plan(cfg)

	# 远地面：一直铺到山后（>相机远裁面内的所有可见处），低机位不露雪边；纯视觉无碰撞。
	K.box(far, Vector3(float(cfg.ground_size), 0.1, float(cfg.ground_size)),
		K.SNOW, Vector3(0, -0.07, 0))

	_build_streets(near)
	for a in anchors.near:
		match str(a.kind):
			"house": _house(near, a)
			"tree": _winter_tree(near, Vector3(float(a.x), 0, float(a.z)), bool(a.blossom), 1.0)
			"wood": _wood_pile(near, Vector3(float(a.x), 0, float(a.z)), float(a.get("rot", 0.0)))
			"lantern": _lantern_body(near, Vector3(float(a.x), 0, float(a.z)))
	for a in anchors.middle:
		if str(a.kind) == "mid_house":
			_middle_house(middle, a)
		else:
			_winter_tree(middle, Vector3(float(a.x), 0, float(a.z)), false, 0.8)
	for w in MID_WALLS.slice(0, int(cfg.middle.wall_bits)):
		_wall_run(middle, Vector2(float(w[0]), float(w[1])), Vector2(float(w[2]), float(w[3])),
			2.3, 0.3, K.WALL_SHADE)
	for a in anchors.far:
		if str(a.kind) == "tower":
			_tower(far, Vector3(float(a.x), 0, float(a.z)), float(cfg.far.tower_h))
		else:
			_peak(far, a)
	for w in FAR_WALLS:
		_wall_run(far, Vector2(float(w[0]), float(w[1])), Vector2(float(w[2]), float(w[3])),
			float(cfg.far.wall_h), float(cfg.far.wall_thick), K.WALL_SHADE)

	# 中远景阴影关闭（太阳阴影距离 60m，本来也照不到；省阴影通道）。
	_set_cast_shadow(middle, false)
	_set_cast_shadow(far, false)
	# 每层各自按材质合并：近景投阴影，中远景不投；近景另有每户一条筒瓦 MultiMesh。
	# merge_layers=false 只供测试取逐锚点小包围盒（真实运行一律合并）。
	if merge_layers:
		K.merge_static(near, [])
		K.merge_static(middle, [])
		K.merge_static(far, [])
	return root


## 旧根立即离树并排队释放，再建新根（同名不打架）；返回新根。
static func replace(parent: Node3D, old: Node3D, layout: Dictionary = {}) -> Node3D:
	if is_instance_valid(old) and old.get_parent() != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	return build(parent, layout)


## 工厂实际摆放用的锚点（测试据此核对：每个锚点旁必须真有网格，且八方位全覆盖）。
static func plan(layout: Dictionary = {}) -> Dictionary:
	return _make_plan(load_config(CONFIG_PATH, layout))


# ---------- 配置 ----------

static func _defaults() -> Dictionary:
	return {
		"seed": 20261026,
		"ground_size": 520.0,
		"near": {"lantern_bodies": 4, "wood_piles": 2},
		"middle": {"houses": 14, "trees": 10, "wall_bits": 6},
		"far": {"wall_radius": 62.0, "wall_h": 9.0, "wall_thick": 1.6,
			"towers": 16, "tower_h": 12.5, "peaks": 16, "peak_r_in": 95.0, "peak_r_out": 150.0,
			"height_scale": 0.4},
	}


static func load_config(path: String, overrides: Dictionary = {}) -> Dictionary:
	var cfg := _defaults()
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_merge_cfg(cfg, parsed)
	_merge_cfg(cfg, overrides)
	# 钳制计数，外部 JSON 写离谱的值也不能越界切片
	cfg.middle.houses = clampi(int(cfg.middle.houses), 0, MID_XZ.size())
	cfg.middle.trees = clampi(int(cfg.middle.trees), 0, MID_TREE_ANGLES.size())
	cfg.middle.wall_bits = clampi(int(cfg.middle.wall_bits), 0, MID_WALLS.size())
	cfg.far.towers = clampi(int(cfg.far.towers), 0, FAR_TOWERS.size())
	cfg.far.peaks = clampi(int(cfg.far.peaks), 0, 32)
	cfg.ground_size = maxf(360.0, float(cfg.ground_size))
	return cfg


static func _merge_cfg(cfg: Dictionary, incoming: Dictionary) -> void:
	for key in incoming:
		if cfg.has(key) and incoming[key] is Dictionary and cfg[key] is Dictionary:
			for sub in incoming[key]:
				if (cfg[key] as Dictionary).has(sub):
					(cfg[key] as Dictionary)[sub] = (incoming[key] as Dictionary)[sub]
		elif cfg.has(key):
			cfg[key] = incoming[key]

# ---------- 锚点规划（确定性） ----------

static func _make_plan(cfg: Dictionary) -> Dictionary:
	var near: Array = []
	for h in NEAR_HOUSES:
		near.append({"kind": "house", "x": h.x, "z": h.z,
			"rot": h.rot, "w": h.w, "d": h.d, "h": h.h, "style": h.style, "annex": h.annex})
	for t in NEAR_TREES:
		near.append({"kind": "tree", "x": t.x, "z": t.z, "blossom": t.blossom})
	for w in NEAR_WOOD.slice(0, int(cfg.near.wood_piles)):
		near.append({"kind": "wood", "x": w.x, "z": w.z, "rot": w.rot})
	for l in NEAR_LANTERNS.slice(0, int(cfg.near.lantern_bodies)):
		near.append({"kind": "lantern", "x": l.x, "z": l.z})

	var middle: Array = []
	for i in mini(int(cfg.middle.houses), MID_XZ.size()):
		var m = MID_XZ[i]
		middle.append({
			"kind": "mid_house", "x": m[0], "z": m[1], "rot": m[2],
			"w": 5.2 + float(i % 3) * 0.7,
			"d": 3.2 + float((i * 7) % 5) * 0.3,
			"h": 3.0 + float((i * 5) % 4) * 0.3,
			"style": i % 4,
		})
	for i in mini(int(cfg.middle.trees), MID_TREE_ANGLES.size()):
		var ang := deg_to_rad(float(MID_TREE_ANGLES[i]))
		var rr := 34.0 + float(i % 4) * 5.0
		middle.append({"kind": "mid_tree", "x": cos(ang) * rr, "z": sin(ang) * rr})

	var far: Array = []
	for i in mini(int(cfg.far.towers), FAR_TOWERS.size()):
		var t = FAR_TOWERS[i]
		far.append({"kind": "tower", "x": t[0], "z": t[1]})
	for i in int(cfg.far.peaks):
		var deg := 11.0 + float(i) * 22.5
		var pa := deg_to_rad(deg)
		var rr: float = lerpf(float(cfg.far.peak_r_in), float(cfg.far.peak_r_out),
			0.25 + 0.5 * float(i % 2))
		far.append({
			"kind": "peak", "x": cos(pa) * rr, "z": sin(pa) * rr, "ang": deg,
			"tw": 42.0 + float(i % 4) * 8.0, "ph": 14.0 + float((i * 7) % 5) * 2.2,
			"snow": i % 2 == 0,
		})
	return {"near": near, "middle": middle, "far": far}


# ---------- 街巷 ----------

static func _build_streets(near: Node3D) -> void:
	var stone := K.mat(Color("#8f8b84"), 0.95)
	var ditch := K.mat(Color("#6a665f"), 0.97)
	# 门前石板路：只在中央通道，z 7.2..24，纯平面不挡迎战。
	K.box(near, Vector3(6.4, 0.05, 17.0), stone, Vector3(0, 0.015, 15.6))
	# 后巷（z=-10.6，贴着核心北墙 z=-8.2）
	K.box(near, Vector3(56.0, 0.05, 3.4), stone, Vector3(0, 0.015, -10.6))
	# 东西巷（核心墙 x=±10.2 与东/西排屋最近边 x≈12.6 之间）
	K.box(near, Vector3(1.9, 0.05, 32.0), stone, Vector3(-11.4, 0.015, 6.0))
	K.box(near, Vector3(1.9, 0.05, 32.0), stone, Vector3(11.4, 0.015, 6.0))
	# 巷口雪埂 / 排水沟（都低于 0.1m，纯贴片）
	for sx in [-1.0, 1.0]:
		K.box(near, Vector3(0.22, 0.07, 17.0), K.SNOW, Vector3(sx * 3.4, 0.02, 15.6))
		K.box(near, Vector3(0.3, 0.03, 17.0), ditch, Vector3(sx * 3.8, 0.005, 15.6))
		K.box(near, Vector3(56.0, 0.07, 0.22), K.SNOW, Vector3(0, 0.02, -12.4))
		K.box(near, Vector3(56.0, 0.03, 0.3), ditch, Vector3(0, 0.005, -8.6))
		K.box(near, Vector3(0.2, 0.06, 32.0), K.SNOW, Vector3(sx * 12.5, 0.02, 6.0))


# ---------- 近景民居 ----------

## 粉墙黛瓦马头墙宅院：侧墙、凹脸门楼、漏窗、硬山屋顶+马头墙、檐口积雪、单侧附房棚子。零碰撞。
static func _house(parent: Node3D, a: Dictionary) -> void:
	var w: float = a.w
	var d: float = a.d
	var h: float = a.h
	var style: int = a.style
	var n := K.node(parent, Vector3(float(a.x), 0, float(a.z)), Vector3(0, float(a.rot), 0))
	# 门前小院雪场（盖住核心土黄地面，薄雪一片）
	K.box(n, Vector3(w + 2.6, 0.04, d + 2.6), K.SNOW, Vector3(0, 0.0, 0.4))
	# 台基
	K.box(n, Vector3(w + 0.6, 0.3, d + 0.6), K.STONE_DARK, Vector3(0, 0.15, 0))
	# 后墙 / 山墙
	K.box(n, Vector3(w, h, 0.24), K.WALL, Vector3(0, h / 2.0, -d / 2.0))
	K.box(n, Vector3(0.24, h, d), K.WALL, Vector3(-w / 2.0, h / 2.0, 0))
	K.box(n, Vector3(0.24, h, d), K.WALL, Vector3(w / 2.0, h / 2.0, 0))
	# 前墙：门凹在偏轴位置，门宽 1.5，门上方过梁
	var dc: float = [-0.5, 0.5, 0.0, 0.4][style]
	var seg := (w - 1.5) / 2.0
	K.box(n, Vector3(seg, h, 0.24), K.WALL, Vector3(-(1.5 / 2.0 + seg / 2.0) + dc, h / 2.0, d / 2.0))
	K.box(n, Vector3(seg, h, 0.24), K.WALL, Vector3(1.5 / 2.0 + seg / 2.0 + dc, h / 2.0, d / 2.0))
	K.box(n, Vector3(1.9, 0.5, 0.26), K.WALL_SHADE, Vector3(dc, h - 0.25, d / 2.0))
	# 门板（深色，凹进半寸）
	K.box(n, Vector3(1.42, h - 0.6, 0.08), K.mat(Color("#3a271d"), 0.7),
		Vector3(dc, (h - 0.6) / 2.0, d / 2.0 - 0.02))
	# 正面窗：暗板 + 纸窗格
	for side in [-1.0, 1.0]:
		var wx: float = dc + side * 2.3
		if absf(wx) < w / 2.0 - 0.8:
			_window(n, Vector3(wx, 1.45, d / 2.0 + 0.01), 0.0)
	if style >= 2:
		_window(n, Vector3(w / 2.0 + 0.01, 1.45, -d * 0.15), 90.0)
	# 硬山双坡 + 马头墙
	Arch.roof(n, w, d, d * 0.38, Vector3(0, h, 0), K.mat(K.ROOF, 0.7), 0.55)
	Arch.ma_tou(n, w / 2.0 + 0.05, 0.0, d, h, d * 0.38)
	Arch.ma_tou(n, -w / 2.0 - 0.05, 0.0, d, h, d * 0.38)
	# 檐口积雪
	for sz in [-1.0, 1.0]:
		K.box(n, Vector3(w + 1.4, 0.06, 0.22), K.SNOW, Vector3(0, h + 0.04, sz * (d / 2.0 + 0.5)))
	# 单侧附房棚子（单坡）
	if bool(a.annex):
		var sx2 := -1.0 if style == 1 else 1.0
		var ax := sx2 * (w / 2.0 + 1.15)
		K.box(n, Vector3(2.2, 1.9, 2.0), K.WALL_SHADE, Vector3(ax, 0.95, 0.3))
		K.box(n, Vector3(1.0, 1.5, 0.06), K.mat(Color("#3a271d"), 0.7), Vector3(ax, 0.75, 1.28))
		K.box(n, Vector3(3.0, 0.12, 2.6), K.ROOF, Vector3(ax, 2.2, 0.3), Vector3(0, 0, -sx2 * 11.0))
		K.box(n, Vector3(2.9, 0.05, 2.5), K.SNOW, Vector3(ax, 2.26, 0.3), Vector3(0, 0, -sx2 * 11.0))


static func _window(n: Node3D, pos: Vector3, rot_y: float) -> void:
	var p := K.node(n, pos, Vector3(0, rot_y, 0))
	K.box(p, Vector3(0.95, 0.75, 0.06), K.mat(Color("#241f1a"), 0.8), Vector3.ZERO)
	K.box(p, Vector3(0.35, 0.55, 0.02), K.PAPER, Vector3(-0.22, 0, 0.02))
	K.box(p, Vector3(0.35, 0.55, 0.02), K.PAPER, Vector3(0.22, 0, 0.02))


## 冬树：深色枝干 + 雪团 / 少量残梅；无碰撞体（Props.plum_tree 带碰撞，背景不能用）。
static func _winter_tree(parent: Node3D, pos: Vector3, blossom: bool, scale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(pos.x) * 131.0 + absf(pos.z) * 977.0) & 0x7fffffff
	var n := K.node(parent, pos, Vector3(0, rng.randf_range(-8.0, 8.0), 0))
	var bark := K.mat(Color("#3a2e27"))
	K.cyl(n, 0.1 * scale, 0.18 * scale, 2.1 * scale, bark, Vector3(0, 1.05 * scale, 0), Vector3(0, 0, 5))
	for b in 4:
		var bx: float = rng.randf_range(-0.55, 0.55) * scale
		var by: float = rng.randf_range(1.7, 2.5) * scale
		var bz: float = rng.randf_range(-0.45, 0.45) * scale
		K.cyl(n, 0.04 * scale, 0.08 * scale, 1.3 * scale, bark,
			Vector3(bx, by, bz), Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-45, 45)))
	var clumps := 12
	var bloom := K.mat(Color("#d9536a"), 0.6, 0.12)
	for i in clumps:
		var p2 := Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(2.1, 3.4), rng.randf_range(-0.9, 0.9)) * scale
		var mat = K.SNOW
		if blossom and i % 3 == 0:
			mat = bloom
		elif i % 4 == 0:
			mat = K.mat(Color("#4d5c43"))
		K.sphere(n, rng.randf_range(0.22, 0.36) * scale, mat, p2)


## 柴堆：3 根横木 + 顶雪，全基本体，无脚本无碰撞。
static func _wood_pile(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var n := K.node(parent, pos, Vector3(0, rot_y, 0))
	var wood := K.mat(Color("#5a4632"), 0.9)
	for i in 3:
		K.cyl(n, 0.11, 0.13, 1.6, wood, Vector3((i - 1) * 0.22, 0.35, 0), Vector3(0, 0, 90), 8)
	K.box(n, Vector3(0.9, 0.1, 0.5), K.SNOW, Vector3(0, 0.52, 0), Vector3(0, 8, 0))


## 静态灯杆：木杆 + 红灯笼（自发光，无 OmniLight）。
static func _lantern_body(parent: Node3D, pos: Vector3) -> void:
	var n := K.node(parent, pos)
	K.cyl(n, 0.07, 0.09, 2.4, K.WOOD, Vector3(0, 1.2, 0), Vector3.ZERO, 8)
	K.box(n, Vector3(0.1, 0.1, 0.7), K.WOOD, Vector3(0, 2.32, 0.28))
	K.sphere(n, 0.2, K.mat(Color("#c23b2a"), 0.6, 0.5), Vector3(0, 2.02, 0.5), Vector3(1, 1.25, 1))
	K.cyl(n, 0.1, 0.1, 0.05, K.ROOF_EDGE, Vector3(0, 2.26, 0.5), Vector3.ZERO, 8)


# ---------- 中远景 ----------

## 中景简化屋：一盒粉墙 + 暗门窗 + 三棱柱黛瓦 + 檐雪，4-5 个基本体。
static func _middle_house(parent: Node3D, a: Dictionary) -> void:
	var w: float = a.w
	var d: float = a.d
	var h: float = a.h
	var n := K.node(parent, Vector3(float(a.x), 0, float(a.z)), Vector3(0, float(a.rot), 0))
	K.box(n, Vector3(w + 0.5, 0.25, d + 0.5), K.STONE_DARK, Vector3(0, 0.125, 0))
	K.box(n, Vector3(w, h, d), K.WALL_SHADE, Vector3(0, h / 2.0, 0))
	K.box(n, Vector3(1.1, h - 0.5, 0.06), K.mat(Color("#33241b"), 0.75),
		Vector3(0, (h - 0.5) / 2.0, d / 2.0 + 0.02))
	K.box(n, Vector3(0.8, 0.6, 0.05), K.mat(Color("#2b2722"), 0.85), Vector3(w * 0.28, 1.35, d / 2.0 + 0.02))
	K.box(n, Vector3(0.8, 0.6, 0.05), K.mat(Color("#2b2722"), 0.85), Vector3(-w * 0.28, 1.35, d / 2.0 + 0.02))
	var rise := d * 0.4
	K.prism(n, Vector3(d + 0.9, rise, w + 0.9), K.ROOF, Vector3(0, h + rise / 2.0, 0), Vector3(0, 90, 0))
	for sz in [-1.0, 1.0]:
		K.box(n, Vector3(w + 1.0, 0.05, 0.2), K.SNOW, Vector3(0, h + 0.03, sz * (d / 2.0 + 0.38)))
	K.box(n, Vector3(w + 0.9, 0.1, 0.12), K.ROOF_EDGE, Vector3(0, h + rise + 0.02, 0))


static func _wall_run(parent: Node3D, a: Vector2, b: Vector2, h: float, thick: float, mat) -> void:
	var mid := (a + b) * 0.5
	var len: float = a.distance_to(b)
	var phi := atan2(b.y - a.y, b.x - a.x)
	var n := K.node(parent, Vector3(mid.x, 0, mid.y), Vector3(0, -rad_to_deg(phi), 0))
	K.box(n, Vector3(len, h, thick), mat, Vector3(0, h / 2.0, 0))
	K.box(n, Vector3(len + 0.2, 0.18, thick + 0.3), K.ROOF_EDGE, Vector3(0, h + 0.09, 0))


static func _tower(parent: Node3D, pos: Vector3, h: float) -> void:
	var n := K.node(parent, pos)
	K.box(n, Vector3(6.5, h, 6.5), K.WALL_SHADE, Vector3(0, h / 2.0, 0))
	# 城墙段端城楼：四角垛口 + 檐
	for qx in [-2.4, 2.4]:
		for qz in [-2.4, 2.4]:
			K.box(n, Vector3(1.0, 0.7, 1.0), K.WALL_SHADE, Vector3(qx, h + 0.35, qz))
	K.box(n, Vector3(7.2, 0.4, 7.2), K.ROOF_EDGE, Vector3(0, h + 0.75, 0))
	# 四角攒尖 + 雪顶
	K.prism(n, Vector3(7.6, 2.6, 7.6), K.ROOF, Vector3(0, h + 2.05, 0), Vector3(0, 45, 0))
	K.prism(n, Vector3(4.2, 0.8, 4.2), K.SNOW, Vector3(0, h + 3.25, 0), Vector3(0, 45, 0))


static func _peak(parent: Node3D, a: Dictionary) -> void:
	# 转 90-ang：棱柱本地 ±Z（拉伸方向）对准锚点径向，XY 三角形截面沿切向展开，
	# 玩家沿径向看进来是三角山面；旧写法 -ang 看到的是长条平顶盒侧。
	var n := K.node(parent, Vector3(float(a.x), 0, float(a.z)), Vector3(0, 90.0 - float(a.ang), 0))
	var ph: float = a.ph
	var tw: float = a.tw
	# 颜色按山脊索引稳定取
	var idx := int(round((float(a.ang) - 11.0) / 22.5))
	var mat: Material = K.mat(PEAK_COLORS[idx % PEAK_COLORS.size()], 1.0)
	# 棱柱截面在 XY（切向宽 tw × 高 ph），沿本地 Z（径向）厚 18m。
	K.prism(n, Vector3(tw, ph, 18.0), mat, Vector3(0, ph / 2.0, 0))
	if bool(a.snow):
		K.prism(n, Vector3(tw * 0.55, ph * 0.32, 10.0), K.SNOW, Vector3(0, ph * 0.82, 0))


static func _set_cast_shadow(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_set_cast_shadow(c, on)
