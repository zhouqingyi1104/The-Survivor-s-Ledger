extends Node3D
## 新守具模型只投影真实设备，不参与碰撞或规则随机。
const State = preload("res://scripts/core/state.gd")
const World = preload("res://scripts/world/home_world.gd")
var checks := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(message)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 413)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	world.sync(run)
	check(world._dynamic.devices.get_node_or_null("device_armor_hook_0") == null, "未建造时出现破甲钩")
	check(world._dynamic.devices.get_node_or_null("device_horde_rope_0") == null, "未建造时出现拦尸绳阵")
	run.devices = [{"id": "armor_hook", "dur": 2}, {"id": "horde_rope", "dur": 2}]
	var before := JSON.stringify(run)
	world.sync(run)
	var hook: Node = world._dynamic.devices.get_node_or_null("device_armor_hook_0")
	var rope: Node = world._dynamic.devices.get_node_or_null("device_horde_rope_0")
	check(hook != null and hook.find_children("*", "MeshInstance3D", true, false).size() > 0, "破甲钩未显示")
	check(rope != null and rope.find_children("*", "MeshInstance3D", true, false).size() > 0, "拦尸绳阵未显示")
	if hook != null and rope != null:
		check(hook.find_children("*", "CollisionObject3D", true, false).is_empty() and rope.find_children("*", "CollisionObject3D", true, false).is_empty(), "守具视觉不可阻挡玩家")
	check(JSON.stringify(run) == before, "绘制守具改变了局面或随机状态")
	run.devices = []
	world.sync(run)
	check(world._dynamic.devices.get_node_or_null("device_armor_hook_0") == null and world._dynamic.devices.get_node_or_null("device_horde_rope_0") == null, "设备消失后模型残留")
	print("[M2_DEFENSE_WORLD] %d/%d failed=%d" % [checks - failed, checks, failed])
	get_tree().quit(1 if failed else 0)
