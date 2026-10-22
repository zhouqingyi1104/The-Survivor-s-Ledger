extends RefCounted
## 第三方美术资源（清单和许可证见 docs/03-art-assets.md）：
##   Poly Haven（CC0）家具模型和 PBR 贴图、cs-studio 中式铺面（免费，不得再分发）、Quaternius 人物和动画（CC0）。

const PH_MODELS := "res://assets/third_party/polyhaven/models/%s/%s.gltf"
const PH_TEX := "res://assets/third_party/polyhaven/textures/%s/%s_%s.jpg"
const BUILDINGS := "res://assets/models/buildings/%s.glb"

static var _scenes := {}
static var _mats := {}


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


## PBR 材质（颜色 + OpenGL 法线 + ARM），世界坐标三面投影；size 是一张贴图铺多少米。
static func pbr(id: String, size := 2.0, tint := Color.WHITE) -> BaseMaterial3D:
	var key := "%s|%.2f|%s" % [id, size, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var diff := PH_TEX % [id, id, "diff"]
	if not ResourceLoader.exists(diff):
		return null
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(PH_TEX % [id, id, "nor"])
	m.normal_scale = 1.0
	m.orm_texture = load(PH_TEX % [id, id, "arm"])
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / size
	_mats[key] = m
	return m


## 需要单独淡出的（屋顶）就复制一份。
static func pbr_unique(id: String, size := 2.0, tint := Color.WHITE) -> BaseMaterial3D:
	var m := pbr(id, size, tint)
	return m.duplicate() if m != null else null


## Poly Haven 模型：放到 parent 下，可选加一个按包围盒算的碰撞体。
static func prop(parent: Node3D, id: String, pos: Vector3, rot_y := 0.0, scale := 1.0, collide := true) -> Node3D:
	var ps := _scene(PH_MODELS % [id, id])
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if collide:
		add_box_collider(parent, n)
	return n


static func building(parent: Node3D, id: String, pos: Vector3, rot_y := 0.0, scale := 1.0) -> Node3D:
	var ps := _scene(BUILDINGS % id)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	return n


## 包围盒（在 n 的父节点坐标系里）。
static func local_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := n.transform
		var cur: Node = m
		var chain := Transform3D.IDENTITY
		while cur != n:
			chain = (cur as Node3D).transform * chain
			cur = cur.get_parent()
		var b := (t * chain) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## 按包围盒加碰撞。矮的（凳子、横倒的树干）也做成至少 1 米高：主角的胶囊体迈不上任何台阶，
## 导航却会把半米高的顶面当成能爬上去的台子，路径从上面穿过去，人就卡住。
static func add_box_collider(parent: Node3D, n: Node3D) -> StaticBody3D:
	var box := local_aabb(n)
	box.size.y = maxf(box.size.y, 1.0)
	var body := StaticBody3D.new()
	body.position = box.get_center()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body
