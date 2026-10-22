extends Node3D
## 临川城（备劫三日）：一条河东西横穿，家在南岸，过石拱桥是北岸的长街，铺子一字排开、门脸朝南；
## 长街正中有石阶上山，山上是青云观。
## 点铺子 → 主角沿街走过去。铺子门口人越来越多（拥挤 / 哄抢），关门的钉上门板。光随时辰走。

signal arrived(place: String)

const K = preload("res://scripts/world/kit.gd")
const Arch = preload("res://scripts/world/arch.gd")
const Props = preload("res://scripts/world/props.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Figure = preload("res://scripts/world/character.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Data = preload("res://scripts/core/data.gd")
const Assets = preload("res://scripts/world/assets.gd")

## 换成 cs-studio 中式铺面模型的铺子：[模型, 转多少度让门脸朝街, 缩放]。其余铺子还是程序搭的厅堂。
const MODEL_SHOPS := {
	"bookshop": ["bookstore", -90.0, 0.7], "market": ["butcher", 0.0, 0.7], "pawnshop": ["clothing_store", 0.0, 0.7],
	"grocery": ["clothing_store_brown", 0.0, 0.7], "builder": ["horse_room", 90.0, 0.7], "temple": ["bookstore_green", -90.0, 0.8],
}

## 地点：[门前站位, 朝向（门面朝哪）, 所在街道 z]
## [门前站位, 门脸朝向（0° 朝南，对着镜头）, 所在街道 z]
const PLACES := {
	"home":      [Vector3(0, 0, 13.0), 180.0, 13.0],
	"rice_shop": [Vector3(-9, 0, -2.0), 0.0, -1.0],
	"market":    [Vector3(9, 0, -2.0), 0.0, -1.0],
	"grocery":   [Vector3(-19, 0, -2.0), 0.0, -1.0],
	"smithy":    [Vector3(19, 0, -2.0), 0.0, -1.0],
	"pharmacy":  [Vector3(-29, 0, -2.0), 0.0, -1.0],
	"bookshop":  [Vector3(29, 0, -2.0), 0.0, -1.0],
	"pawnshop":  [Vector3(-39, 0, -2.0), 0.0, -1.0],
	"builder":   [Vector3(44, 0, -2.0), 0.0, -1.0],
	"temple":    [Vector3(0, 0, -9.0), 0.0, -1.0],
}
const RIVER_Z := 5.0

var sky: Dictionary
## 走路速度（米/秒，时间是压缩过的；测试时会调快）。
var walk_speed := 11.0
var walker: Node3D
var walking := false
var _crowds := {}
var _labels := {}
var _boards := {}
var _path: Array = []


func _ready() -> void:
	sky = SkyKit.make(self, 40.0)
	sky.fog_mul = 0.45
	_ground()
	for id in PLACES:
		_building(id)
	# 静态的方块按材质合并；关门才显示的门板留着
	K.merge_static(self, _boards.values() + _crowds.values())
	walker = Figure.new()
	walker.step_sound = "step_snow"
	add_child(walker)


func _ground() -> void:
	K.box(self, Vector3(160, 0.2, 120), K.mat(K.SNOW.darkened(0.08), 0.95), Vector3(0, -0.1, -10))
	# 河与河岸
	K.box(self, Vector3(160, 0.05, 6), K.mat(Color("#3f5f61"), 0.12), Vector3(0, 0.02, RIVER_Z))
	for sz in [-1, 1]:
		K.box(self, Vector3(160, 0.4, 0.6), K.STONE, Vector3(0, 0.15, RIVER_Z + sz * 3.2))
	# 石拱桥
	for k in 7:
		var t := (k - 3) / 3.0
		K.box(self, Vector3(3.2, 0.3, 1.25), K.STONE, Vector3(0, 0.9 * (1.0 - t * t), RIVER_Z + t * 3.6))
	for sx in [-1, 1]:
		K.box(self, Vector3(0.15, 0.5, 7.6), K.STONE_DARK, Vector3(sx * 1.6, 0.9, RIVER_Z))
	# 北岸长街、过桥到家的路、上山的石阶
	var road := K.mat(Color("#8f8b84"), 0.95)
	K.box(self, Vector3(96, 0.04, 3.6), road, Vector3(1, 0.03, -1.0))
	K.box(self, Vector3(3.6, 0.04, 6), road, Vector3(0, 0.03, 11.0))
	for k in 8:
		K.box(self, Vector3(3.5, 0.4 * (k + 1), 0.9), K.STONE, Vector3(0, 0.2 * (k + 1), -9.6 - k * 0.85))
	K.cyl(self, 9.0, 12.0, 3.2, K.mat(Color("#8c9187")), Vector3(0, 1.6, -22), Vector3.ZERO, 10)
	# 南岸河边一座凉亭（cs-studio）
	Assets.building(self, "gazebo", Vector3(-8.5, 0, RIVER_Z + 6.2), 0.0, 0.5)
	# 南岸的树、远山
	for x in [-12.0, -5.0, 6.0, 14.0]:
		Props.plum_tree(self, Vector3(x, 0, RIVER_Z + 4.6))
	for k in 7:
		K.cyl(self, 0.0, 20.0, 14.0 + (k % 3) * 5.0, K.mat(Color("#7d8a96"), 1.0), Vector3(-72.0 + k * 24.0, 5.0, -62), Vector3.ZERO, 6)


func _building(id: String) -> void:
	var spot: Vector3 = PLACES[id][0]
	var facing: float = PLACES[id][1]
	var dir := Vector3(sin(deg_to_rad(facing)), 0, cos(deg_to_rad(facing)))
	var center := spot - dir * 4.0
	if id == "temple":
		center = Vector3(0, 3.2, -21.0)
	var w := 7.0
	var d := 4.5
	var h := 3.4
	var root := K.node(self, center, Vector3(0, facing, 0))
	var name_text := "家"
	if id == "home":
		w = 6.0
		Arch.wall(root, Vector3(-4, 0, -2.5), Vector3(4, 0, -2.5), 2.6)
	else:
		name_text = Pre.shop(id).name
	if id == "temple":
		w = 9.0
		h = 4.2
	var model: Node3D = null
	if MODEL_SHOPS.has(id):
		model = Assets.building(root, MODEL_SHOPS[id][0], Vector3.ZERO, MODEL_SHOPS[id][1], MODEL_SHOPS[id][2])
	if model != null:
		# 模型的门脸对齐到街边：包围盒前沿放在 d/2
		var box := Assets.local_aabb(model)
		model.position = Vector3(-box.get_center().x, 0, d / 2.0 - box.end.z)
		w = box.size.x
		h = box.size.y * 0.72
		if id == "temple":
			K.cyl(root, 0.5, 0.6, 0.9, K.mat(Color("#6c5a3a"), 0.4), Vector3(0, 0.45, d / 2.0 + 1.6))
	else:
		var hall := Arch.hall(root, Vector3.ZERO, 0, w, d, h, ["back", "left", "right"])
		if id == "temple":
			for k in 3:
				K.box(hall.node, Vector3(w + 0.4, 0.5, 0.4), K.LACQUER, Vector3(0, 0.25, -d / 2.0))
			K.cyl(root, 0.5, 0.6, 0.9, K.mat(Color("#6c5a3a"), 0.4), Vector3(0, 0.45, d / 2.0 + 1.6))
	# 匾额
	var plaque := K.node(root, Vector3(0, h - 0.7, d / 2.0 + 0.05))
	K.box(plaque, Vector3(3.2, 1.1, 0.12), K.mat(Color("#1f1a16"), 0.5), Vector3.ZERO)
	K.box(plaque, Vector3(3.4, 1.25, 0.1), K.mat(K.GOLD, 0.4), Vector3(0, 0, -0.02))
	var plaque_text := K.text3d(plaque, name_text, Vector3(0, 0, 0.08), 140, Color("#f0cf72"), false)
	plaque_text.outline_size = 0
	if id != "pawnshop" or model == null:
		_decor(id, root, w, d)
	# 点击用的碰撞盒
	K.collider(root, Vector3(w, h + 1.5, d + 2.0), Vector3(0, (h + 1.5) / 2.0, 0.6), {"place": id})
	# 门板（关门时显示）
	var boards := K.node(root, Vector3(0, 0, d / 2.0 - 0.1))
	for k in 5:
		K.box(boards, Vector3(w - 0.4, 0.3, 0.08), K.WOOD_LIGHT, Vector3(0, 0.4 + k * 0.55, 0), Vector3(0, 0, -6 + (k % 2) * 12))
	boards.visible = false
	_boards[id] = boards
	_labels[id] = K.text3d(self, "", center + Vector3(0, h + 3.2, 0), 72, Color.WHITE, true, 0.009)
	_crowds[id] = K.node(self, spot - dir * 0.6, Vector3(0, facing, 0))


func _decor(id: String, root: Node3D, w: float, d: float) -> void:
	var front := d / 2.0 + 0.9
	match id:
		"rice_shop":
			Props.rice_sacks(root, Vector3(-1.8, 0, front), 9)
		"market":
			for k in 3:
				var x := -2.4 + k * 2.4
				K.box(root, Vector3(1.8, 0.8, 0.9), K.WOOD_LIGHT, Vector3(x, 0.4, front))
				K.box(root, Vector3(2.0, 0.06, 1.3), K.mat(Color("#7a8f5a")), Vector3(x, 2.0, front), Vector3(-12, 0, 0))
				for c in 4:
					K.sphere(root, 0.16, K.mat(Color("#a9c98a")), Vector3(x - 0.6 + c * 0.4, 0.95, front))
		"grocery":
			Props.firewood(root, Vector3(-2.0, 0, front), 8)
			K.cyl(root, 0.3, 0.3, 0.6, K.mat(Color("#4a3a2e"), 0.3), Vector3(2.2, 0.3, front))
		"smithy":
			K.box(root, Vector3(0.6, 0.6, 0.4), K.mat(Color("#3a3d42"), 0.3), Vector3(-1.5, 0.3, front))
			K.box(root, Vector3(1.0, 0.8, 1.0), K.BRICK, Vector3(1.8, 0.4, front))
			K.box(root, Vector3(0.6, 0.12, 0.6), K.mat(Color("#ff7a3d"), 0.5, 3.0), Vector3(1.8, 0.82, front))
			K.light(root, Color("#ff8a4a"), 2.0, 6.0, Vector3(1.8, 1.4, front))
		"pharmacy":
			K.box(root, Vector3(2.5, 1.8, 0.5), K.WOOD, Vector3(0, 0.9, -d / 2.0 + 0.5))
			for r in 4:
				for c in 6:
					K.box(root, Vector3(0.36, 0.36, 0.04), K.WOOD_LIGHT, Vector3(-1.0 + c * 0.4, 0.3 + r * 0.42, -d / 2.0 + 0.76))
		"bookshop":
			for k in 3:
				K.box(root, Vector3(0.5, 0.3, 0.35), K.mat(Color("#cbb98f")), Vector3(-1.5 + k * 1.5, 0.95, front), Vector3(0, k * 15, 0))
			K.box(root, Vector3(4.0, 0.8, 0.8), K.WOOD, Vector3(0, 0.4, front))
		"pawnshop":
			K.box(root, Vector3(1.6, 1.6, 0.1), K.WALL, Vector3(-w / 2.0 + 1.2, 1.6, d / 2.0 + 0.1))
			var big := K.text3d(root, "当", Vector3(-w / 2.0 + 1.2, 1.6, d / 2.0 + 0.17), 230, Color("#1f1a16"), false)
			big.outline_size = 0
		"builder":
			Props.wood_pile(root, Vector3(-2.0, 0, front + 0.6), 10)
			Props.wood_pile(root, Vector3(2.0, 0, front + 0.6), 7)
		"home":
			Props.plum_tree(root, Vector3(2.4, 0, 1.0))


# ---------- 按局面重画 ----------

func sync(run: Dictionary) -> void:
	for id in PLACES:
		_sync_place(run, id)
	if not walking:
		_place_walker(run.loc)
	var hour := int(run.hour)
	var t := clampf((hour - 3) / 6.0, 0.0, 1.0)
	if t < 0.5:
		SkyKit.blend(sky, "dawn", "noon", t * 2.0, 220)
	else:
		SkyKit.blend(sky, "noon", "dusk", (t - 0.5) * 2.0, 220)


func _sync_place(run: Dictionary, id: String) -> void:
	var label: Label3D = _labels[id]
	var crowd: Node3D = _crowds[id]
	K.clear(crowd)
	if id == "home":
		label.text = "家" + ("（在此）" if run.loc == "home" else "")
		label.modulate = Color("#f4ead6")
		return
	var status := Pre.status(run, id)
	var cost := Pre.travel_cost(run, id)
	var here: bool = run.loc == id
	label.text = "%s%s\n%s · %d时辰" % ["★ " if Pre.shop(id).get("must", false) else "", Pre.shop(id).name, status, cost] if not here else "%s（在此）\n%s" % [Pre.shop(id).name, status]
	var colors := {"正常": Color("#cfe3c0"), "拥挤": Color("#f0d48a"), "哄抢": Color("#ff9a8a"), "关门": Color("#b8b0a4")}
	label.modulate = colors.get(status, Color.WHITE)
	_boards[id].visible = status == "关门"
	var n: int = {"正常": 1, "拥挤": 5, "哄抢": 10, "关门": 0}.get(status, 0)
	if Pre.shop(id).kind != "goods":
		n = mini(n, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + int(run.day)
	for k in n:
		var f: Node3D = Figure.new()
		crowd.add_child(f)
		f.setup("villager", Color.from_hsv(rng.randf_range(0.0, 0.15), rng.randf_range(0.2, 0.45), rng.randf_range(0.3, 0.6)))
		f.position = Vector3(rng.randf_range(-2.8, 2.8), 0, rng.randf_range(-0.8, 1.6))
		f.rotation.y = rng.randf_range(0, TAU)
		if status == "哄抢":
			f.moving = true


func _place_walker(loc: String) -> void:
	walker.position = PLACES[loc][0]
	walker.rotation.y = deg_to_rad(float(PLACES[loc][1]) + 180.0)
	walker.moving = false


func setup_walker(kind: String) -> void:
	walker.setup(kind)


## 沿街走到 dest：先上自家门前的街，再走到桥头的南北大街，过桥，再拐到对方门前。
func walk(from: String, dest: String) -> void:
	var a: Vector3 = PLACES[from][0]
	var b: Vector3 = PLACES[dest][0]
	var za: float = PLACES[from][2]
	var zb: float = PLACES[dest][2]
	_path = [Vector3(a.x, 0, za), Vector3(0, 0, za)]
	if za != zb:
		_path.append(Vector3(0, 0, zb))
	_path.append(Vector3(b.x, 0, zb))
	_path.append(b)
	walker.position = a
	walking = true
	walker.moving = true


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in _crowds:
		for node in _crowds[id].get_children():
			var f = node
			if f.moving:
				f.position += Vector3(sin(t * 3.0 + f.get_index()), 0, cos(t * 2.0 + f.get_index())) * delta * 0.6
	if not walking:
		return
	if _path.is_empty():
		walking = false
		walker.moving = false
		arrived.emit("")
		return
	var target: Vector3 = _path[0]
	var to := target - walker.position
	to.y = 0
	var step := walk_speed * delta
	if to.length() <= step:
		walker.position = target
		_path.pop_front()
	else:
		walker.position += to.normalized() * step
		walker.face(to, 1.0)
	# 过桥时跟着桥面起伏
	var dz := walker.position.z - RIVER_Z
	walker.position.y = 0.9 * maxf(0.0, 1.0 - pow(dz / 3.6, 2)) + 0.15 if absf(walker.position.x) < 1.6 and absf(dz) < 3.6 else 0.0


## 鼠标点到的地点 id（没有返回空串）。
func pick(cam: Camera3D, screen_pos: Vector2) -> String:
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider.has_meta("place"):
		return ""
	return hit.collider.get_meta("place")
