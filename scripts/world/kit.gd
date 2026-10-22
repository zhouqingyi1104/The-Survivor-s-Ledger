extends RefCounted
## 3D 搭建工具：材质色板 + 基本几何体（盒、柱、棱柱、球）+ 碰撞 + 3D 文字。
## 场景里没有美术资源，全部用这些基本体拼出来，走低多边形风格。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Assets = preload("res://scripts/world/assets.gd")

# 徽派色板：粉墙黛瓦、朱漆木作、青石地、雪
const WALL := Color("#ded8ca")
const WALL_SHADE := Color("#cfc8b8")
const ROOF := Color("#3b4046")
const ROOF_EDGE := Color("#2a2e33")
const WOOD := Color("#5b3b29")
const WOOD_LIGHT := Color("#8a6243")
const LACQUER := Color("#7c2a21")
const STONE := Color("#86827b")
const STONE_DARK := Color("#66635e")
const BRICK := Color("#7b5a4c")
const EARTH := Color("#5f4a3a")
const SNOW := Color("#e4e7ea")
const GREEN := Color("#5e7d4a")
const LEAF := Color("#7fa35e")
const PAPER := Color("#e6c25c")
const CINNABAR := Color("#a8322d")
const GOLD := Color("#c49a3c")
const CLOTH_BLUE := Color("#2f3f52")
const RICE_SACK := Color("#d8c9a3")
const SKIN := Color("#e2c3a3")
const JIANGSHI_SKIN := Color("#a9b5a0")
const WATER := Color("#3d5a5b")

static var _mats := {}

## 这些颜色自动换成带程序纹理的材质（世界坐标三面投影，盒子拼接处纹理连续）。
## [深色, 频率, 拉伸]
const TEXTURED := {
	"wall": [WALL, 0.92, 0.035, Vector3(1, 1, 1)],
	"wood": [WOOD, 0.72, 0.06, Vector3(1, 6, 1)],
	"wood_light": [WOOD_LIGHT, 0.75, 0.06, Vector3(1, 6, 1)],
	"lacquer": [LACQUER, 0.8, 0.05, Vector3(1, 5, 1)],
	"stone": [STONE, 0.82, 0.09, Vector3(1, 1, 1)],
	"stone_dark": [STONE_DARK, 0.82, 0.09, Vector3(1, 1, 1)],
	"snow": [SNOW, 0.94, 0.02, Vector3(1, 1, 1)],
	"earth": [EARTH, 0.7, 0.12, Vector3(1, 1, 1)],
	"brick": [BRICK, 0.78, 0.14, Vector3(1, 1, 1)],
}


## 有写实贴图（Poly Haven，CC0）的就用写实的：[贴图 id, 一张铺多少米, 染色]
const PBR := {
	"wall": ["white_stucco", 2.5, Color(1, 1, 1)],
	"snow": ["snow_02", 3.0, Color(1.22, 1.22, 1.28)],
	"stone": ["cobblestone_floor_08", 1.8, Color(1, 1, 1)],
	"stone_dark": ["square_cobblestone", 1.8, Color(0.8, 0.8, 0.8)],
	"wood": ["brown_planks_09", 1.4, Color(0.6, 0.46, 0.36)],
	"wood_light": ["brown_planks_09", 1.4, Color(1, 1, 1)],
}


static func _textured(color: Color) -> BaseMaterial3D:
	for key in TEXTURED:
		var spec: Array = TEXTURED[key]
		if (spec[0] as Color).is_equal_approx(color):
			if PBR.has(key):
				var p: Array = PBR[key]
				var real := Assets.pbr(p[0], p[1], p[2])
				if real != null:
					return real
			var key_full: String = "tex|" + str(key)
			if _mats.has(key_full):
				return _mats[key_full]
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = spec[2]
			noise.fractal_octaves = 4
			var ramp := Gradient.new()
			ramp.set_color(0, color.darkened(1.0 - float(spec[1])))
			ramp.set_color(1, color.lightened(0.04))
			var tex := NoiseTexture2D.new()
			tex.width = 256
			tex.height = 256
			tex.seamless = true
			tex.noise = noise
			tex.color_ramp = ramp
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex
			m.roughness = 0.88
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.35, 0.35, 0.35) * (spec[3] as Vector3)
			_mats[key_full] = m
			return m
	return null


static func mat(color: Color, rough := 0.85, emit := 0.0, alpha := 1.0) -> BaseMaterial3D:
	if emit == 0.0 and alpha >= 1.0 and is_equal_approx(rough, 0.85):
		var t := _textured(color)
		if t != null:
			return t
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, emit, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## 每次都新建（需要单独变色、变透明的部件用，比如屋顶淡出、门受损变暗）。
static func unique_mat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, color if color is Material else mat(color), pos, rot_deg)


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, color, pos: Vector3, rot_deg := Vector3.ZERO, sides := 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	return _mesh(parent, m, color if color is Material else mat(color), pos, rot_deg)


static func sphere(parent: Node3D, r: float, color, pos: Vector3, scale := Vector3.ONE, hemi := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = 12
	m.rings = 6
	var mi := _mesh(parent, m, color if color is Material else mat(color), pos)
	mi.scale = scale
	return mi


## 胶囊（人物四肢用）。沿 Y 轴，h 是总长。
static func capsule(parent: Node3D, r: float, h: float, color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 10
	m.rings = 4
	return _mesh(parent, m, color if color is Material else mat(color), pos, rot_deg)


## 三棱柱：截面三角形在 XY 平面，沿 Z 拉伸。屋顶用它，转 90° 让屋脊沿 X。
static func prism(parent: Node3D, size: Vector3, color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _mesh(parent, m, color if color is Material else mat(color), pos, rot_deg)


## 静态碰撞盒（看不见）。
static func collider(parent: Node3D, size: Vector3, pos: Vector3, meta := {}) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	for k in meta:
		body.set_meta(k, meta[k])
	parent.add_child(body)
	return body


## 看得见又挡人的盒子。
static func solid(parent: Node3D, size: Vector3, color, pos: Vector3) -> MeshInstance3D:
	collider(parent, size, pos)
	return box(parent, size, color, pos)


static func font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(UI.FONT_NAMES)
	return f


static func text3d(parent: Node3D, text: String, pos: Vector3, size := 64, color := Color.WHITE, billboard := true, pixel := 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = pixel
	l.position = pos
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.1, 0.08, 0.06, 0.85)
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = billboard
	parent.add_child(l)
	return l


static func node(parent: Node3D, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, node_name := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	if node_name != "":
		n.name = node_name
	parent.add_child(n)
	return n


static func light(parent: Node3D, color: Color, energy: float, rng: float, pos: Vector3, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


## 把 root 下面不会再变的基本体（方块、圆柱、棱柱、球……）按材质合并成一个网格。
## 场景是上千个小方块拼的，不合并每块都是一次绘制调用（阴影再翻倍）。
## 不碰的：skip 里的节点连同子孙（会动的门扇、按局面重画的堆、要描边的物件、会显隐的门板），
## 挂了脚本的节点（人物等）、骨骼，以及当前隐藏的节点。返回合并掉的网格数。
static func merge_static(root: Node3D, skip: Array) -> int:
	var groups := {}
	var merged := []
	_collect_static(root, Transform3D.IDENTITY, skip, groups, merged)
	for key in groups:
		var g: Array = groups[key]
		var mi := MeshInstance3D.new()
		mi.name = "merged"
		mi.mesh = (g[2] as SurfaceTool).commit()
		mi.material_override = g[0]
		mi.cast_shadow = g[1]
		root.add_child(mi)
	for mi in merged:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	return merged.size()


static func _collect_static(n: Node, xf: Transform3D, skip: Array, groups: Dictionary, merged: Array) -> void:
	for c in n.get_children():
		if c in skip or not c is Node3D or c.get_script() != null or c is Skeleton3D or not (c as Node3D).visible:
			continue
		var cxf: Transform3D = xf * (c as Node3D).transform
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh is PrimitiveMesh and mi.material_override != null and mi.material_overlay == null and mi.get_child_count() == 0:
			var key := "%d|%d" % [mi.material_override.get_instance_id(), mi.cast_shadow]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [mi.material_override, mi.cast_shadow, st]
			(groups[key][2] as SurfaceTool).append_from(mi.mesh, 0, cxf)
			merged.append(mi)
		else:
			_collect_static(c, cxf, skip, groups, merged)


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
