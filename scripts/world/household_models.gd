extends RefCounted
## 共用小件的网格和图集。每一堆库存只提交一次，存货增减无需重新造网格。

const LIBRARY := preload("res://assets/models/household/household.glb")
static var _meshes := {}

static func mesh(id: StringName) -> Mesh:
	if _meshes.is_empty():
		var library := LIBRARY.instantiate()
		for piece: MeshInstance3D in library.find_children("*", "MeshInstance3D", true, false):
			# 导入器从 atlas 的首种材料推断颜色用法，显式保留 glTF 的线性染色。
			var finish := piece.mesh.surface_get_material(0) as BaseMaterial3D
			finish.vertex_color_use_as_albedo = true
			finish.vertex_color_is_srgb = false
			finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_meshes[piece.name] = piece.mesh
		library.free()
	return _meshes[id]


static func place(parent: Node3D, id: StringName, pos := Vector3.ZERO) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh(id)
	piece.position = pos
	parent.add_child(piece)
	return piece


static func stock(parent: Node3D, id: StringName, count: int) -> void:
	var maximum := 16 if id == &"Sack" else (12 if id == &"Billet" else 10)
	var amount := clampi(count, 0, maximum)
	if amount == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh(id)
	mm.instance_count = amount
	for i in amount:
		var form := Basis.IDENTITY
		var center := Vector3.ZERO
		match id:
			&"Sack":
				var layer := floori(i / 6.0)
				center = Vector3((i % 3 - 1) * 0.519 + 0.05 * (layer % 2), 0.197 * layer,
						(-0.5 + floori((i % 6) / 3.0)) * 0.377)
				form = Basis(Vector3.UP, 0.235 * sin(i * 1.84) + PI * (i % 2))
				form = form.scaled(Vector3(1.0 + 0.043 * cos(i * 2.3), 0.96 + 0.028 * sin(i), 1))
			&"Billet":
				var layer := floori(i / 4.0)
				form = Basis(Vector3.FORWARD, 0.46 * sin(2.2 * i) + PI * (layer % 2))
				form = Basis(Vector3.UP, 0.033 * cos(i * 3.2)) * form
				center = Vector3(-0.354 + (i % 4) * 0.227 + (layer % 2) * 0.045,
						0.106 + layer * 0.174, 0.063 * sin(i * 1.4))
			&"Timber":
				form = Basis(Vector3.UP, 0.026 * sin(i * 2.0))
				center = Vector3(0.084 * sin(i * 2.6), 0.084 + floori(i / 3.0) * 0.165, (i % 3 - 1) * 0.202)
		mm.set_instance_transform(i, Transform3D(form, center))
	var pile := MultiMeshInstance3D.new()
	pile.multimesh = mm
	parent.add_child(pile)
