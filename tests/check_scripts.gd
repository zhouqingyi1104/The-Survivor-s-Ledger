extends Node
## 在完整的项目环境里（自动加载单例都在）把 res://scripts 下所有脚本加载一遍，确认都能编译。
## 运行：godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var bad := 0
	var files := _collect("res://scripts")
	for path in files:
		var s = load(path)
		if s == null or not s.can_instantiate():
			bad += 1
			print("编译失败：", path)
	print("共 %d 个脚本，失败 %d 个" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)


func _collect(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_collect(dir_path.path_join(d)))
	return out
