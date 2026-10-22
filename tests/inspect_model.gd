extends SceneTree
## 开发用：把 res://assets 下的角色模型逐个读一遍，打印身高、朝向、骨骼名、自带的动作。
## 运行：godot --headless --path . --script res://tests/inspect_model.gd -- <模型路径> ...

func _init() -> void:
	var paths := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			paths.append(a)
	if paths.is_empty():
		paths = [
			"res://assets/models/characters/female_long.glb",
			"res://assets/third_party/413games/base-motion-v7.glb",
			"res://assets/third_party/413games/moon-motion-v7.glb",
		]
	for p in paths:
		var sc: PackedScene = load(p)
		if sc == null:
			print("打不开 ", p)
			continue
		var n := sc.instantiate()
		print("===== ", p)
		print("  子节点：", _names(n.get_children()))
		var box := _aabb(n)
		var s := box.size
		print("  包围盒：%.3f x %.3f x %.3f（身高 %.3f 米）" % [s.x, s.y, s.z, s.y])
		print("  包围盒范围：", str(box.position), " → ", str(box.position + s))
		var sk: Skeleton3D = n.find_child("Skeleton3D", true, true)
		if sk != null:
			print("  骨骼数：", sk.get_bone_count())
			print("  骨骼名：", _bones(sk))
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, true)
		if ap != null:
			print("  自带动作：", ap.get_animation_list())
		n.free()
	quit()


func _names(kids: Array) -> Array:
	var out := []
	for k in kids:
		out.append(k.name + ":" + k.get_class())
	return out


func _bones(sk: Skeleton3D) -> Array:
	var out := []
	for i in mini(sk.get_bone_count(), 20):
		out.append(sk.get_bone_name(i))
	return out


func _xform_aabb(b: AABB, xf: Transform3D) -> AABB:
	var lo := xf * b.position
	var hi := lo
	for i in 8:
		var c := b.position + Vector3(
			b.size.x if i & 1 else 0.0,
			b.size.y if i & 2 else 0.0,
			b.size.z if i & 4 else 0.0)
		var w := xf * c
		lo = lo.min(w)
		hi = hi.max(w)
	return AABB(lo, hi - lo)


func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var b := _xform_aabb(m.get_aabb(), root.global_transform.affine_inverse() * m.global_transform)
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box
