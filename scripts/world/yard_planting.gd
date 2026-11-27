extends RefCounted
## 院里的冬梅和菜畦。树与作物的网格可在数个场景、不同长势之间复用。
const K = preload("res://scripts/world/kit.gd")
const House = preload("res://scripts/world/home_house.gd")
const Assets = preload("res://scripts/world/assets.gd")

static var _tree: ArrayMesh
static var _soil: ArrayMesh
static var _frame: Mesh
static var _crops := {}
static var _pigments: StandardMaterial3D

static func _painted_mesh(surface: SurfaceTool) -> ArrayMesh:
	if not _pigments:
		_pigments = StandardMaterial3D.new()
		_pigments.vertex_color_use_as_albedo = true
		_pigments.vertex_color_is_srgb = true
		_pigments.cull_mode = BaseMaterial3D.CULL_DISABLED
		_pigments.roughness = 0.88
	surface.set_material(_pigments)
	surface.index()
	return surface.commit()

static func _face(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outside: Vector3, pigment: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var swap := normal.dot(outside) < 0.0
	s.set_normal(-normal if swap else normal)
	s.set_color(pigment)
	s.add_vertex(a)
	s.add_vertex(c if swap else b)
	s.add_vertex(b if swap else c)

## 锥段的端点共用枝节位置。小枝和花梗也用同一构造，避免花苞悬空。
static func _twig(s: SurfaceTool, a: Vector3, b: Vector3, thick: float, thin: float, hue: Color, sides := 6) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.88 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for i in sides:
		var angle := TAU * i / sides
		var step := TAU / sides
		var p := u * cos(angle) + v * sin(angle)
		var q := u * cos(angle + step) + v * sin(angle + step)
		var tone := hue.darkened(0.10 * (0.5 + 0.5 * sin(i * 2.1)))
		_face(s, a + thick * p, b + thin * p, b + thin * q, p + q, tone)
		_face(s, a + thick * p, b + thin * q, a + thick * q, p + q, tone)

static func plum_tree(parent: Node3D, pos: Vector3, collide := true) -> Node3D:
	var root := K.node(parent, pos)
	if not _tree:
		_tree = _plum_mesh()
	var tree := MeshInstance3D.new()
	tree.mesh = _tree
	tree.rotation.y = fposmod(pos.x * 0.74 + pos.z * 0.4, TAU)
	root.add_child(tree)
	if collide:
		K.collider(root, Vector3(0.5, 2.0, 0.5), Vector3(0, 1.0, 0))
	return root

static func _plum_mesh() -> ArrayMesh:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color("#4d3d35")
	var wood := Color("#725349")
	var crotch := Vector3(-0.14, 1.20, 0.06)
	var knee := Vector3(0.09, 0.52, -0.03)
	_twig(s, Vector3.ZERO, knee, 0.18, 0.137, bark, 11)
	_twig(s, knee, crotch, 0.145, 0.111, bark, 10)
	var leader := crotch + Vector3(0.23, 0.48, -0.09)
	var apex := leader + Vector3(-0.17, 0.40, -0.12)
	_twig(s, crotch, leader, 0.110, 0.082, bark, 9)
	_twig(s, leader, apex, 0.083, 0.058, bark, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4921
	for i in 5:
		var angle := i * 2.41 + 0.28
		var reach := 1.13 if i < 3 else 0.79
		var side := Vector3(cos(angle), 0, sin(angle))
		var cross_side := side.cross(Vector3.UP)
		var junction := crotch.lerp(leader, i * 0.40) if i < 3 else leader.lerp(apex, (i - 2) * 0.50)
		var limb := junction + side * reach * 0.47 + Vector3.UP * (0.33 + 0.06 * i)
		var elbow := limb + side * reach * 0.58 + cross_side * rng.randf_range(-0.16, 0.16) + Vector3.UP * 0.31
		_twig(s, junction, limb, 0.083 - 0.006 * i, 0.056, bark, 8)
		_twig(s, limb, elbow, 0.059, 0.037, bark, 7)
		for j in 3:
			var shoulder := limb.lerp(elbow, 0.18 + 0.39 * j)
			var spread := float(j - 1)
			var fork := shoulder + side * (0.16 + 0.09 * j) + cross_side * spread * 0.34 + Vector3.UP * rng.randf_range(0.16, 0.45)
			var tip := fork + side * rng.randf_range(0.05, 0.26) + cross_side * spread * 0.18 + Vector3.UP * rng.randf_range(0.27, 0.55)
			_twig(s, shoulder, fork, 0.038, 0.024, wood)
			_twig(s, fork, tip, 0.026, 0.008, wood)
			for spur in 3:
				var heel := fork.lerp(tip, 0.12 + 0.32 * spur)
				var branch := (side + cross_side * (1.0 if spur % 2 == 0 else -1.0) + Vector3.UP * 0.66).normalized()
				var twig_end := heel + branch * rng.randf_range(0.12, 0.22)
				_twig(s, heel, twig_end, 0.012, 0.003, wood, 5)
				var florets := 3 if (spur + i) % 3 != 0 else 2
				for k in florets:
					var node := heel.lerp(twig_end, 0.27 + 0.65 * k / (florets - 1))
					var turn := rng.randf_range(0.0, TAU)
					var normal := Vector3(cos(turn), rng.randf_range(0.52, 1.34), sin(turn)).normalized()
					var calyx := node + normal * 0.023
					_twig(s, node, calyx, 0.009, 0.012, Color("#733d43"), 5)
					if rng.randf() < 0.24:
						_twig(s, calyx, calyx + normal * 0.023, 0.013, 0.017, Color("#a85662"), 6)
						_twig(s, calyx + normal * 0.023, calyx + normal * 0.043, 0.017, 0.002, Color("#cd8287"), 6)
					else:
						var petal := Color("#dc9098").lerp(Color("#ffded2"), rng.randf())
						_blossom(s, calyx, normal, rng.randf_range(0.056, 0.079), petal)
	return _painted_mesh(s)

static func _blossom(s: SurfaceTool, center: Vector3, normal: Vector3, radius: float, hue: Color) -> void:
	var u := normal.cross(Vector3.UP).normalized()
	var v := normal.cross(u)
	for i in 5:
		var turn := TAU * i / 5.0
		var petal := u * cos(turn) + v * sin(turn)
		var wide := normal.cross(petal)
		var lobe := center + petal * radius * 0.66 + normal * radius * 0.18
		var nose := center + petal * radius + normal * radius * 0.38
		var left := lobe + wide * radius * 0.43
		var right := lobe - wide * radius * 0.43
		var rim := wide * radius * 0.16
		_face(s, center, left, lobe, normal, hue.darkened(0.08))
		_face(s, center, lobe, right, normal, hue)
		_face(s, left, nose + rim, lobe, normal, hue)
		_face(s, lobe, nose + rim, nose - rim, normal, hue)
		_face(s, lobe, nose - rim, right, normal, hue.lightened(0.04))
	_twig(s, center, center + normal * radius * 0.42, radius * 0.18, 0.002, Color("#d6ae6e"), 5)

static func garden_plot(parent: Node3D, pos: Vector3, crop: String, growth: float, dry: bool) -> Node3D:
	var root := K.node(parent, pos)
	if not _frame:
		var blank := Node3D.new()
		for side in [-1, 1]:
			K.box(blank, Vector3(1.6, 0.16, 0.067), K.WOOD, Vector3(0, 0.083, side * 0.767))
			K.box(blank, Vector3(0.067, 0.16, 1.466), K.WOOD, Vector3(side * 0.767, 0.083, 0))
			for end in [-1, 1]:
				K.box(blank, Vector3(0.076, 0.197, 0.076), K.WOOD, Vector3(side * 0.713, 0.099, end * 0.713))
		var boards := House.finish_joinery(blank)
		_frame = boards.mesh
		_frame.surface_set_material(0, boards.material_override)
		blank.free()
		_soil = _furrows()
	var edge := MeshInstance3D.new()
	edge.mesh = _frame
	root.add_child(edge)
	var earth := MeshInstance3D.new()
	earth.mesh = _soil
	earth.material_override = Assets.pbr("brown_mud_dry", 0.90, Color("#c9ae93") if dry else Color("#8e745e"))
	root.add_child(earth)
	if crop not in ["cabbage", "radish", "chive", "lingzhi"]:
		return root
	var size := clampf(growth, 0.15, 1.0)
	var kind := "ripe_radish" if crop == "radish" and size >= 1.0 else crop
	if not _crops.has(kind):
		_crops[kind] = _crop_mesh(kind)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _crops[kind]
	batch.instance_count = 9
	for k in 9:
		var x := (k % 3 - 1) * 0.46 + sin(k * 4.17) * 0.025
		var z := (floori(k / 3.0) - 1) * 0.46
		var facing := Basis(Vector3.UP, k * 2.41).scaled(Vector3.ONE * size * (0.90 + 0.07 * cos(k * 3.43)))
		batch.set_instance_transform(k, Transform3D(facing, Vector3(x, _soil_height(x, z) - 0.003, z)))
	var patch := MultiMeshInstance3D.new()
	patch.multimesh = batch
	root.add_child(patch)
	return root

static func _soil_height(x: float, z: float) -> float:
	var shoulder := z + 0.025 * sin(x * 4.2 + z * 2.7)
	var ridge := 0.5 + 0.5 * cos(shoulder * TAU / 0.46)
	var ends := 1.0 - smoothstep(0.56, 0.74, absf(x))
	return 0.122 + ends * (0.095 * ridge * ridge + 0.010 * sin(15.0 * x - z * 13.4))

static func _furrows() -> ArrayMesh:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in 32:
		for ix in 12:
			for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2.DOWN]:
				var x := lerpf(-0.74, 0.74, (ix + corner.x) / 12.0)
				var z := lerpf(-0.74, 0.74, (iz + corner.y) / 32.0)
				var dx := _soil_height(x - 0.01, z) - _soil_height(x + 0.01, z)
				var dz := _soil_height(x, z - 0.01) - _soil_height(x, z + 0.01)
				s.set_normal(Vector3(dx, 0.02, dz).normalized())
				s.set_uv(Vector2(x, z))
				s.add_vertex(Vector3(x, _soil_height(x, z), z))
	s.index()
	return s.commit()

static func _crop_mesh(kind: String) -> ArrayMesh:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "lingzhi":
		for k in 2:
			var foot := Vector3(-0.055 + 0.098 * k, 0, -0.035 * k)
			var neck := foot + Vector3(0.026, 0.116 + 0.044 * k, 0)
			_twig(s, foot, neck, 0.026, 0.022, Color("#935535"), 7)
			# 菌盖从偏心菌柄向外生长，琥珀色同心纹一直延伸到浅色边缘。
			for j in 18:
				var a := j * TAU / 18.0
				var b := (j + 1) * TAU / 18.0
				var p := Vector3(cos(a) * (0.099 + 0.021 * cos(3.0*a)), 0, sin(a) * 0.081)
				var q := Vector3(cos(b) * (0.099 + 0.021 * cos(3.0*b)), 0, sin(b) * 0.081)
				var zones := [Color("#6d4131"), Color("#994f31"), Color("#b47748"), Color("#d2a570")]
				for band in 4:
					var t := band / 4.0
					var u := (band + 1) / 4.0
					var l := neck + Vector3.UP * (0.032 - t*t*0.035) + Vector3.RIGHT * t * 0.029
					var r := neck + Vector3.UP * (0.032 - u*u*0.035) + Vector3.RIGHT * u * 0.029
					if band > 0:
						_face(s, l+p*t, l+q*t, r+q*u, Vector3.UP, zones[band])
					_face(s, l+p*t, r+q*u, r+p*u, Vector3.UP, zones[band])
	else:
		var cabbage := kind == "cabbage"
		var chive := kind == "chive"
		if kind == "ripe_radish":
			_twig(s, Vector3(0, -0.016, 0), Vector3(0, 0.036, 0), 0.074, 0.067, Color("#d5cfb2"), 10)
			_twig(s, Vector3(0, 0.036, 0), Vector3(0, 0.068, 0), 0.067, 0.021, Color("#c4ba96"), 10)
		for i in (12 if cabbage else 8):
			var angle := i * 2.40
			var outward := Vector3(cos(angle), 0, sin(angle))
			var spread := 0.078 if chive else 0.17
			var h := (0.34 if chive else 0.18) + 0.05 * sin(i * 0.97)
			var w := 0.010 if chive else (0.072 if cabbage else 0.042)
			var foot := Vector3.UP * (0.045 if kind == "ripe_radish" else 0.004)
			var shade := Color("#46604b").lerp(Color("#9fae79"), (0.25 if chive else 0.63) * (0.5 + 0.5 * sin(i * 3.1)) + 0.02 * i)
			if cabbage and i > 5:
				spread *= 0.56
				h *= 1.09
				shade = shade.lightened(0.16)
			# 中肋带出折面。外层菜叶向地面舒展，内层沿菜心收拢。
			var side := outward.cross(Vector3.UP)
			var last_ridge := foot
			var last_left := foot
			var last_right := foot
			for segment in 4:
				var t := (segment + 1) / 4.0
				var arc := sin(t * PI)
				var reach := spread * (t + (0.45 if cabbage else 0.18) * arc)
				var mid := foot + outward * reach + Vector3.UP * (h * (t - (0.35 if chive else 0.20) * t*t))
				var half_width := w * (0.027 + pow(arc, 0.70))
				var frill := 0.008 * sin(i * 4.3 + t * 12.1) * arc
				var ridge := mid + Vector3.UP * (0.010 * arc)
				var left := mid - side * half_width + Vector3.UP * (0.014 * arc + frill)
				var right := mid + side * half_width + Vector3.UP * (0.014 * arc - frill)
				var pigment := shade.lightened(0.070 * t)
				if segment > 0:
					_face(s, last_left, left, last_ridge, Vector3.UP, pigment)
					_face(s, last_ridge, right, last_right, Vector3.UP, pigment.darkened(0.07))
				_face(s, last_ridge, left, ridge, Vector3.UP, pigment)
				_face(s, last_ridge, ridge, right, Vector3.UP, pigment.darkened(0.07))
				last_left = left
				last_ridge = ridge
				last_right = right
	return _painted_mesh(s)
