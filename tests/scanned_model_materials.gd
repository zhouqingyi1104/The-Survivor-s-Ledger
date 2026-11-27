extends SceneTree

const MODEL_ROOT := "res://assets/third_party/polyhaven/models/"
var failures := 0


func _initialize() -> void:
	var materials := 0
	for folder in ResourceLoader.list_directory(MODEL_ROOT):
		if not folder.ends_with("/"):
			continue
		var path := MODEL_ROOT + folder + folder.trim_suffix("/") + ".gltf"
		var scene := ResourceLoader.load(path) as PackedScene
		if not _check(scene != null, path):
			continue
		var instance := scene.instantiate()
		var seen := {}
		for node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for index in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.get_active_material(index) as BaseMaterial3D
				if not _check(mat != null, path + " missing material") or seen.has(mat):
					continue
				seen[mat] = true
				materials += 1
				_check_surface(mat, path)
		_check(not seen.is_empty(), path + " has no surfaces")
		instance.free()
	_check(materials >= 15, "missing scanned models")
	print("[scanned_model_materials] materials=%d failures=%d" % [materials, failures])
	quit(1 if failures else 0)


func _check_surface(mat: BaseMaterial3D, path: String) -> void:
	for texture in [mat.albedo_texture, mat.normal_texture, mat.roughness_texture]:
		if _check(texture != null, path + " missing texture"):
			var settings := ConfigFile.new()
			var source: String = texture.resource_path
			_check(settings.load(source + ".import") == OK and settings.get_value("params", "mipmaps/generate", false),
				source + " missing mipmaps")
	if mat.roughness_texture == null:
		return
	var packed := mat.roughness_texture.resource_path.get_file().contains("_arm_")
	_check(mat.ao_enabled == packed, path + " incorrect occlusion source")
	if packed:
		_check(mat.ao_texture == mat.roughness_texture and mat.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
			path + " lost packed red-channel occlusion")


func _check(ok: bool, detail: String) -> bool:
	if not ok:
		failures += 1
		push_error(detail)
	return ok
