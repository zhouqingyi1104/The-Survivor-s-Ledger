extends Node3D
## 外出搜寻的废墟：一间塌了半边顶的破屋，入口在南。能翻的地方发金光，翻过就暗下去。
## 每个地点有自己的陈设（义庄是棺材、县学是书架……），后墙外有僵尸游荡；阳气外泄满了会有一只扑进来。

const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Figure = preload("res://scripts/world/character.gd")
const Data = preload("res://scripts/core/data.gd")

const ENTRY := Vector3(0, 0, 5.2)
const SPOT_POS := [Vector3(-5.0, 0, -3.6), Vector3(0.0, 0, -4.4), Vector3(5.0, 0, -3.6), Vector3(-5.6, 0, 1.6), Vector3(5.6, 0, 1.6)]
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
	K.box(self, Vector3(16, 0.06, 12), K.mat(Color("#4a3a2c")), Vector3(0, 0.03, 0))
	for k in 16:
		K.box(self, Vector3(0.03, 0.065, 12), K.mat(Color("#2e241b")), Vector3(-7.5 + k, 0.035, 0))
	var dirty := K.mat(K.WALL.darkened(0.35))
	var h := 3.4
	# 后墙有个破洞，侧墙、前墙（门在正中）
	K.solid(self, Vector3(6.5, h, 0.4), dirty, Vector3(-4.75, h / 2.0, -6))
	K.solid(self, Vector3(6.5, h, 0.4), dirty, Vector3(4.75, h / 2.0, -6))
	K.box(self, Vector3(3.0, 1.0, 0.4), dirty, Vector3(0, 0.5, -6))
	K.collider(self, Vector3(3.0, h, 0.4), Vector3(0, h / 2.0, -6))
	for sx in [-1, 1]:
		K.solid(self, Vector3(0.4, h, 12.4), dirty, Vector3(sx * 8, h / 2.0, 0))
		# 前墙塌得只剩半截，镜头才看得进屋
		K.solid(self, Vector3(7.0, 1.1, 0.4), dirty, Vector3(sx * 4.5, 0.55, 6))
	# 屋顶塌光了：掉下来的梁和瓦片
	K.box(self, Vector3(6.5, 0.3, 0.3), K.WOOD, Vector3(1.5, 0.6, 3.2), Vector3(0, 25, 18))
	K.box(self, Vector3(5.0, 0.3, 0.3), K.WOOD, Vector3(-3.0, 0.3, 0.2), Vector3(0, -40, 6))
	for k in 18:
		K.box(self, Vector3(0.5, 0.06, 0.35), K.ROOF, Vector3(-6.0 + (k % 6) * 2.3, 0.08 + (k / 6) * 0.05, -1.0 + (k / 6) * 1.3), Vector3(0, k * 23, 8))
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


func _dress(pid: String) -> void:
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
	var pos: Vector3 = SPOT_POS[k % SPOT_POS.size()]
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
		_spots[k].glow.visible = not done
		_spots[k].label.text = _spots[k].name + ("（已翻过）" if ex.spots[k].done else "")
		_spots[k].label.modulate = Color("#9a948a") if done else Color("#ffe3a0")
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
