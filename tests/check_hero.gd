extends Node
## 开发用：把主角实例摆出来，逐项报"挂件在不在、挂在哪"，免得靠猜。
## 运行：godot --headless --path . res://tests/check_hero.tscn

const Figure = preload("res://scripts/world/character.gd")

var _bodies: Array = ["female_long", "moon", "maid"]
var _i := 0


func _ready() -> void:
	_step()


func _step() -> void:
	if _i >= _bodies.size():
		get_tree().quit()
		return
	var body: String = _bodies[_i]
	var f := Figure.new()
	add_child(f)
	f.hero = true
	f.force_body = body
	f.setup("herbalist")
	# 挂点容器的缩放补偿要在 _process 里跑一帧才生效，先等几帧
	for k in 4:
		await get_tree().process_frame
	print("===== ", body)
	var mi := f.find_children("*", "MeshInstance3D", true, false).size()
	print("  网格数：", mi)
	var att := f.find_children("*", "BoneAttachment3D", true, false)
	print("  挂点：", att.size(), " → ", _names(att))
	for n in f.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s == null:
			continue
		var list := s.get_script_method_list()
		var is_ribbon := false
		for m in list:
			if m.name == "tick":
				is_ribbon = true
		if is_ribbon:
			var meshes := n.find_children("*", "MeshInstance3D", true, false)
			var deep: Node3D = n
			var d := 0
			while deep.get_child_count() > 0 and (deep.get_child(0) as Node3D) != null and (deep.get_child(0) as Node3D).get_child_count() >= 0 and d < 12:
				var nxt: Node3D = deep.get_child(0)
				if nxt is MeshInstance3D:
					break
				deep = nxt
				d += 1
			print("  飘带 网格=", meshes.size(), " 链深=", d,
				" root=", str(n.global_position), " 尖=", str(deep.global_position))
	print("  头顶高度：", f._head_top())
	_i += 1
	await get_tree().process_frame
	await get_tree().process_frame
	_step()


func _names(att: Array) -> Array:
	var out := []
	for a in att:
		out.append((a as BoneAttachment3D).bone_name)
	return out
