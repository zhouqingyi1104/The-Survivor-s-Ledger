extends SceneTree
## 检查导入后的第三方资源：节点结构、骨骼、动画轨道路径、尺寸。
## 运行：godot --headless --path . --script res://tests/inspect_assets.gd


func _init() -> void:
	_tree("res://assets/models/characters/male_long.glb", 3)
	var ual: Node = load("res://assets/third_party/quaternius/ual/UAL1_Standard.glb").instantiate() if ResourceLoader.exists("res://assets/third_party/quaternius/ual/UAL1_Standard.glb") else null
	if ual != null:
		_print_tree(ual, 0, 3)
		var ap: AnimationPlayer = ual.find_child("AnimationPlayer", true, false)
		print("anims:", ap.get_animation_list())
		var anim := ap.get_animation(ap.get_animation_list()[ap.get_animation_list().size() - 1])
		print("tracks:", anim.get_track_count(), " first:", anim.track_get_path(0), " len:", anim.length, " loop:", anim.loop_mode)
		print("anim root_node:", ap.root_node, " ap parent:", ap.get_parent().name)
	for f in ["chinese_sofa", "chinese_cabinet", "chinese_console_table", "chinese_tea_table", "chinese_screen_panels", "chinese_armchair", "chinese_stool", "chinese_commode", "chinese_chandelier", "ceramic_vase_01", "ceramic_pot", "folding_wooden_stool", "dead_tree_trunk"]:
		var path := "res://assets/third_party/polyhaven/models/%s/%s.gltf" % [f, f]
		var n: Node3D = load(path).instantiate()
		print(f, " aabb ", _aabb(n))
	for b in ["bookstore", "butcher", "clothing_store", "gazebo", "horse_room"]:
		var n: Node3D = load("res://assets/models/buildings/%s.glb" % b).instantiate()
		print(b, " aabb ", _aabb(n))
	quit()


func _tree(path: String, depth: int) -> void:
	var n: Node = load(path).instantiate()
	print("== ", path)
	_print_tree(n, 0, depth)
	print("aabb ", _aabb(n))


func _print_tree(n: Node, level: int, depth: int) -> void:
	if level > depth:
		return
	var extra := ""
	if n is Skeleton3D:
		extra = " bones=%d" % (n as Skeleton3D).get_bone_count()
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		var mats := []
		for k in m.get_surface_count():
			var mat := m.surface_get_material(k)
			mats.append(mat.resource_name if mat != null else "-")
		extra = " surfaces=%s" % str(mats)
	print("  ".repeat(level), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		_print_tree(c, level + 1, depth)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := _global(m)
		var b := t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _global(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
