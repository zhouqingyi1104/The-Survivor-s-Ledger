extends RefCounted
## 缓存独立网格，材质沿用导入表面。移动中的挂件只持有自己的变换。
const DIR := "res://assets/models/folk/"
static var _meshes := {}
static var _panels := {}

static func mesh(file: String, part: String) -> Mesh:
	var key := file + "/" + part
	if not _meshes.has(key):
		var scene := load(DIR + file + ".glb") as PackedScene
		var root := scene.instantiate()
		var all := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			all.append(root)
		for item: MeshInstance3D in all:
			var shaped := item.mesh as ArrayMesh
			for surface in shaped.get_surface_count():
				var mat := shaped.surface_get_material(surface) as BaseMaterial3D
				if mat:
					mat.vertex_color_use_as_albedo = true
					if mat.resource_name == "Sable short coat":
						mat.albedo_texture = preload("res://assets/models/folk/guard_hair.png")
						mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_meshes[file + "/" + str(item.name)] = shaped
		root.free()
	return _meshes[key]

static func attach(parent: Node3D, file: String, part: String, pos := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = mesh(file, part)
	instance.position = pos
	parent.add_child(instance)
	return instance

static func panel(file: String) -> StandardMaterial3D:
	if not _panels.has(file):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(DIR + file + ".png")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.93
		_panels[file] = mat
	return _panels[file]


static func sewn_panel(parent: Node3D, file: String, size: Vector2, pos: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var item := MeshInstance3D.new()
	item.mesh = quad
	item.position = pos
	item.material_override = panel(file)
	parent.add_child(item)
	return item
