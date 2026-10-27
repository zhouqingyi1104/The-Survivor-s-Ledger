extends Node3D
## 外出搜寻的废墟：一间塌了半边顶的破屋，入口在南。能翻的地方发金光，翻过就暗下去。
## 每个地点有自己的陈设（义庄是棺材、县学是书架……），后墙外有僵尸游荡；阳气外泄满了会有一只扑进来。

const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const SkyKit = preload("res://scripts/world/sky.gd")
const Figure = preload("res://scripts/world/character.gd")
const Data = preload("res://scripts/core/data.gd")

const ENTRY := Vector3(0, 0, 5.2)
# 熟练搜寻的四处物资、邻人药账和主线专点可同时存在，六处必须各自可达。
const SPOT_POS := [Vector3(-5.0, 0, -3.6), Vector3(0.0, 0, -4.4), Vector3(5.0, 0, -3.6), Vector3(-5.6, 0, 1.6), Vector3(5.6, 0, 1.6), Vector3(0.0, 0, 1.6)]
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
	var ground := Color("#4a3a2c")
	if point in ["city_god", "mortuary", "taoist_temple"]: ground = Color("#565650")
	elif point == "lumber": ground = Color("#514638")
	elif point == "pharmacy_ruin": ground = Color("#4c4035")
	K.box(self, Vector3(16, 0.06, 12), K.mat(ground), Vector3(0, 0.03, 0))
	for k in 16:
		K.box(self, Vector3(0.03, 0.065, 12), K.mat(ground.darkened(0.4)), Vector3(-7.5 + k, 0.035, 0))
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
	_exit_marker()


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
		_spots[k].label.text = _spots[k].name + status
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
