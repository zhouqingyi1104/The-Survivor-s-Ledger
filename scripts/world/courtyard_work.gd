extends RefCounted
## 灶上的晒匾与门柱边的船信只投影存档状态。它们借用原来的灶、门交互和碰撞。
const K = preload("res://scripts/world/kit.gd")
const Props = preload("res://scripts/world/props.gd")
const Attic = preload("res://scripts/world/attic_living.gd")
const Home = preload("res://scripts/core/home.gd")
const Lane = preload("res://scripts/core/lane_lantern.gd")
static var _meal_material: StandardMaterial3D


static func sync_tray(root: Node3D, run: Dictionary) -> void:
	var stove := Home.core(run, "stove")
	var batch: Dictionary = run.get("drying_batch", {})
	var kind := str(batch.get("kind", "empty"))
	var double: bool = "stove" in run.get("facilities", [])
	var key := "%s/%s/%s" % [kind, batch.get("turned", false), double]
	if stove.is_empty() or "stove" in run.get("broken", []): key = "absent"
	if not stove.is_empty():
		root.position = Vector3(float(stove.x), 0.0, float(stove.z))
		root.rotation_degrees.y = float(stove.rot)
	if root.get_meta("appearance", "") == key: return
	root.set_meta("appearance", key)
	K.clear(root)
	if key == "absent": return
	# 靠灶背的两根木托架高于锅沿；匾边收在灶台的台面范围，不伸进人物落脚处。
	var tray := K.node(root, Vector3(-0.62 if double else -0.33, 1.4, -0.01), Vector3.ZERO, "woven_tray")
	for z: float in [-0.25, 0.25]:
		K.box(tray, Vector3(0.055, 0.50, 0.055), K.WOOD, Vector3(-0.28, -0.25, z))
		K.box(tray, Vector3(0.63, 0.040, 0.052), K.WOOD_LIGHT, Vector3(0, -0.014, z))
		K.box(tray, Vector3(0.27, 0.030, 0.038), K.WOOD, Vector3(-0.18, -0.103, z), Vector3(0, 0, 36))
	var bamboo := K.mat(Color("#b69257"), 0.81)
	var split := K.mat(Color("#d3af73"), 0.86)
	for i in range(-8, 9):
		var offset := float(i) * 0.040
		var chord := 2.0 * sqrt(0.337 * 0.337 - offset * offset)
		K.box(tray, Vector3(chord, 0.005, 0.031), split, Vector3(0, 0.011, offset))
		K.box(tray, Vector3(0.018, 0.004, chord), bamboo, Vector3(offset, 0.016, 0))
	var edge := PackedVector2Array([Vector2(0.327, 0.006), Vector2(0.349, 0.012),
		Vector2(0.368, 0.054), Vector2(0.366, 0.064), Vector2(0.354, 0.062), Vector2(0.335, 0.020)])
	K._mesh(tray, Props._turned_vessel(edge), bamboo, Vector3.ZERO)
	for i in 12:
		var a := TAU * i / 12.0
		K.box(tray, Vector3(0.039, 0.053, 0.013), K.mat(Color("#775e40"), 0.86),
			Vector3(sin(a) * 0.357, 0.04, cos(a) * 0.357), Vector3(-18, rad_to_deg(a), 0))
	var turned := bool(batch.get("turned", false))
	if kind in ["grain", "radish"]:
		_food(tray, kind, turned)
	K.merge_static(root, [])


static func _food(tray: Node3D, kind: String, turned: bool) -> void:
	# 饼沿留露出的谷粒，萝卜见浅色芯与深色皮；翻过的厚片集中在匾的一侧。
	var centers := [Vector2(-0.135, -0.125), Vector2(0.039, -0.17), Vector2(0.166, -0.033),
		Vector2(-0.191, 0.042), Vector2(-0.017, 0.004), Vector2(-0.082, 0.197), Vector2(0.103, 0.137)]
	for i in centers.size():
		var p: Vector2 = centers[i]
		if turned:
			p.x = p.x * 0.71 - 0.06
		var slice := K.node(tray, Vector3(p.x, 0.024 + (0.014 * (i % 2) if turned else 0.0), p.y),
			Vector3(2 + (i % 3) * 2, 17 + 37 * i, (-6 if i % 2 == 0 else 10) if turned else 0))
		slice.scale = Vector3(1.0 - 0.10 * (i % 3), 1.0, 1.0 + 0.05 * (i % 2))
		if kind == "grain":
			_grain_cake(slice, i, turned)
		else:
			var skin := K.mat(Color("#ac816b") if turned else Color("#ad8d7a"), 0.91)
			var flesh := K.mat(Color("#dbbf88") if turned else Color("#f0dfb9"), 0.87)
			var strip := K.node(slice)
			strip.scale = Vector3(0.60 + 0.08 * (i % 3), 1, 1.12)
			K.cyl(strip, 0.079, 0.073, 0.014, skin, Vector3.UP * 0.007, Vector3.ZERO, 18)
			K.cyl(strip, 0.074, 0.072, 0.004, flesh, Vector3.UP * 0.015, Vector3.ZERO, 18)
			for j in 3:
				var angle := 1.3 + 1.92 * j + float(i) * 0.21
				K.box(strip, Vector3(0.0020, 0.001, 0.047), Color("#d5bd92"),
					Vector3(sin(angle) * 0.029, 0.0175, cos(angle) * 0.029), Vector3(0, rad_to_deg(angle), 0))
	if turned:
		var tongs := K.node(tray, Vector3(0.19, 0.055, 0.027), Vector3(0, -13, 0))
		for side: float in [-1.0, 1.0]:
			K.box(tongs, Vector3(0.023, 0.016, 0.335), K.WOOD_LIGHT, Vector3(side * 0.023, 0, 0), Vector3(0, side * 7, 0))
		K.box(tongs, Vector3(0.045, 0.020, 0.033), Color("#746649"), Vector3(0, 0, -0.153))


static func _grain_cake(parent: Node3D, variant: int, toasted: bool) -> void:
	# 指腹压出的翘边和凹窝比均匀球面更能辨出手摊的饼。着色随饼面起伏，暗边只留一圈。
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hues := [Color("#cc9658"), Color("#dfac6c"), Color("#edc78b")] if not toasted else [Color("#a87546"), Color("#cc985b"), Color("#dbb57e")]
	var rings := [Vector2(0.02, 0.002), Vector2(0.89, 0.003), Vector2(1.0, 0.011),
		Vector2(0.93, 0.022), Vector2(0.58, 0.029), Vector2(0.015, 0.025)]
	for row in rings.size():
		var ring: Vector2 = rings[row]
		for side in 21:
			var a := TAU * side / 20.0
			var edge := 1.0 + 0.061 * sin(a * 3.0 + variant) + 0.037 * sin(a * 5.0 - variant)
			var height := ring.y + 0.005 * ring.x * sin(a * 3.0 + variant * 1.4)
			var base: Color = hues[0] if row < 3 else hues[1]
			var light: Color = hues[2]
			surface.set_color(base.lerp(light, (0.5 + 0.45 * cos(a * 2.0 + variant + row * 0.7)) * (0.2 if row < 3 else 0.9)))
			surface.add_vertex(Vector3(cos(a) * 0.098 * ring.x * edge, height, sin(a) * 0.082 * ring.x * edge))
	for row in range(rings.size() - 1):
		for i in 20:
			var k := row * 21 + i
			for index in [k, k + 1, k + 22, k, k + 22, k + 21]:
				surface.add_index(index)
	surface.generate_normals()
	if _meal_material == null:
		_meal_material = StandardMaterial3D.new()
		_meal_material.roughness = 0.93
		_meal_material.vertex_color_use_as_albedo = true
	K._mesh(parent, surface.commit(), _meal_material, Vector3.ZERO)
	for j in 4:
		var a := 1.8 * j + 0.65 * variant
		var radius := 0.027 + 0.010 * (j % 3)
		K.sphere(parent, 0.0045, Color("#f2d18b"), Vector3(sin(a) * radius, 0.029, cos(a) * radius), Vector3(1.5, 0.30, 0.74))


static func sync_letter(root: Node3D, run: Dictionary) -> void:
	var stage := Lane.status(run.get("mainline", {}), int(run.get("t", 0))) if run.get("phase") == "post" else ""
	if stage not in ["offer", "waiting", "reply"]: stage = "absent"
	if root.get_meta("appearance", "") == stage: return
	root.set_meta("appearance", stage)
	K.clear(root)
	if stage == "absent": return
	# 窗楣上固定的木臂探进院里，避开门楼的屋檐，仰看和俯看都能认出信物。
	var arm := K.node(root)
	K.box(arm, Vector3(0.16, 0.35, 0.075), K.WOOD, Vector3(0, -0.105, -0.218))
	K.box(arm, Vector3(0.093, 0.076, 1.16), K.WOOD_LIGHT, Vector3(0, 0, -0.77))
	K.box(arm, Vector3(0.058, 0.062, 0.48), K.WOOD, Vector3(0, -0.125, -0.415), Vector3(-31, 0, 0))
	var peg := K.node(arm, Vector3(0, 0.035, -1.27))
	K.cyl(peg, 0.027, 0.027, 0.73, K.WOOD_LIGHT, Vector3.ZERO, Vector3(0, 0, 90), 12)
	var white := Color("#e4d9be")
	var flag := K.node(peg, Vector3(-0.13, 0.018, 0), Vector3(0, 180, 2))
	if stage == "reply":
		Attic._draped_cloth(flag, Vector3.ZERO, 0.48, 0.10, 0.62, white)
		var written := K.text3d(flag, "望留宿", Vector3(0, -0.23, 0.065), 56, Color("#423b32"), false, 0.0023)
		written.outline_size = 0
		K.box(flag, Vector3(0.045, 0.057, 0.006), Color("#96533f"), Vector3(0.148, -0.427, 0.05), Vector3(0, 0, 8))
	else:
		Attic._draped_cloth(flag, Vector3.ZERO, 0.29, 0.10, 0.66, white)
		Attic._draped_cloth(flag, Vector3(0.078, -0.019, -0.066), 0.129, 0.07, 0.38, Color("#c8baa1"))
	K.box(peg, Vector3(0.12, 0.043, 0.085), Color("#91744d"), Vector3(-0.13, 0.026, 0.008), Vector3(0, 2, 2))
	if stage == "waiting":
		var holder := K.node(peg, Vector3(0.15, -0.63, -0.02))
		K.cyl(holder, 0.195, 0.14, 0.041, K.WOOD, Vector3.ZERO, Vector3.ZERO, 8)
		var lamp := K.node(holder, Vector3.UP * 0.02)
		lamp.scale = Vector3.ONE * 1.18
		Attic._reading_lamp(lamp, Vector3.ZERO)
		for x: float in [-0.17, 0.17]:
			K.cyl(holder, 0.007, 0.007, 0.61, Color("#82704b"), Vector3(x, 0.31, 0), Vector3.ZERO, 8)
	K.merge_static(root, [])
