extends Node3D
## C0 异步行为守卫（需要物理帧 / 真实相机射线）：
##  - 背景任何 AABB 都不侵入大门迎战通道（|x|<=3, 7.5<=z<=17, 0.5<=y<=8）；
##  - 核心地面拾取仍可用（相机射线命中院内 ground）；
##  - 物理帧之后背景仍无碰撞体、无导航；
##  - 大门 / 街上战斗坐标常量未改动；
##  - 运行期缺失生产模块时有限失败（exit 1），不挂死。
## 运行：godot --headless --path <项目> res://tests/courtyard_rules.tscn

const HomeWorld = preload("res://scripts/world/home_world.gd")
const State = preload("res://scripts/core/state.gd")
const SURR_PATH := "res://scripts/world/home_surroundings.gd"
const PREFIX := "[COURTYARD_RULES]"

var checks: Array = []
var passed := 0


func _ready() -> void:
	Game.no_save = true
	var pid := OS.get_process_id()
	Game.save_path = "user://c0-rules-save-%d.json" % pid
	Game.meta_path = "user://c0-rules-meta-%d.json" % pid
	Game.memory_path = "user://c0-rules-Memory-%d.md" % pid
	Game.run = {}
	Game.meta = State.new_meta()

	var world = HomeWorld.new()
	add_child(world)
	await get_tree().process_frame
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261026)
	world.sync(run)
	for i in 3:
		await get_tree().physics_frame

	var S = load(SURR_PATH)
	_ok("factory_module_loads", S != null, "load(%s)" % SURR_PATH)
	var surr: Node3D = world.get_node_or_null("surroundings")
	_ok("surroundings_present", surr != null and surr.get_parent() == world, "根节点")
	if S == null or surr == null:
		_finish()
		return

	var forbidden := _forbidden(surr)
	_ok("no_physics_in_background", forbidden.is_empty(), ", ".join(forbidden.slice(0, 8)))

	# 迎战通道净空：用未合并构建的逐盒 AABB（合并后的材质联合 AABB 会把多户人家圈在一起）
	var raw_host := Node3D.new()
	add_child(raw_host)
	var raw: Node3D = S.build(raw_host, {}, false)
	var intruders: Array = []
	for b in _collect_aabbs(raw, Transform3D.IDENTITY):
		var c: Vector3 = b["center"]
		var h: Vector3 = b["half"]
		# 通道盒 |x|<=3, z 7.5..17, y 0.5..8；地面/街巷顶面 <0.5 自然排除
		if absf(c.x) < 3.0 + h.x and c.z + h.z > 7.5 and c.z - h.z < 17.0 \
				and c.y + h.y > 0.5 and c.y - h.y < 8.0:
			intruders.push_back("%s@%s" % [b.get("name", "?"), c])
	_ok("street_approach_clear", intruders.is_empty(), ", ".join(intruders.slice(0, 6)))

	# 核心拾取：院内射线必须得到 ground 或 spot
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 13, 9)
	cam.look_at(Vector3(0, 0, -1), Vector3.UP, false)
	cam.current = true
	for i in 2:
		await get_tree().process_frame
		for j in 2:
			await get_tree().physics_frame
	var vp := get_viewport().get_visible_rect().size
	var hit := world.pick(cam, Vector2(vp.x * 0.5, vp.y * 0.5))
	_ok("courtyard_pick_still_works",
		hit.has("ground") or hit.has("spot"), "pick=%s" % hit)

	# 战斗坐标 / 常量（float32 字面量比较用容差）
	var gate_stand_z: float = world.SPOTS["gate"]["stand"].z
	_ok("fight_coordinates_unchanged",
		absf(world.GATE_Z - 7.0) < 0.001 and absf(gate_stand_z - 5.8) < 0.001
			and world.nearest_spot(Vector3(0, 0, 5.8)) == "gate",
		"GATE_Z=%s gate=%s stand.z=%.4f" % [world.GATE_Z, world.nearest_spot(Vector3(0, 0, 5.8)), gate_stand_z])

	# 核心物理地面仍在（院中点有碰撞）
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(2, 5, 2), Vector3(2, -5, 2))
	var floor_hit := space.intersect_ray(q)
	_ok("core_floor_physics_intact", not floor_hit.is_empty(), "ray(2,*,2)=%s" % floor_hit.get("collider"))

	_finish()


## 记录一条契约结果。
func _ok(name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "ok": ok})
	if ok:
		passed += 1
	else:
		print("%s CHECK FAIL %s：%s" % [PREFIX, name, detail])


func _forbidden(n: Node) -> Array:
	var out := []
	if n is CollisionObject3D or n is NavigationRegion3D:
		out.append("%s(%s)" % [n.name, n.get_class()])
	if n.has_meta("spot"):
		out.append("%s(spot)" % n.name)
	for c in n.get_children():
		out.append_array(_forbidden(c))
	return out


func _collect_aabbs(n: Node, xf: Transform3D) -> Array:
	var out := []
	for c in n.get_children():
		if c is VisualInstance3D:
			var vi := c as VisualInstance3D
			var local := vi.get_aabb()
			if local.size.length() > 0.01:
				var w := xf * vi.transform
				out.append({"center": w * local.get_center(), "half": local.size.abs() * 0.5, "name": vi.name})
		if c is Node3D:
			out.append_array(_collect_aabbs(c, xf * (c as Node3D).transform))
	return out


func _finish() -> void:
	print("%s checks=%d passed=%d failed=%d" % [PREFIX, checks.size(), passed, checks.size() - passed])
	print("%s COMPLETE code=%d" % [PREFIX, 0 if passed == checks.size() else 1])
	get_tree().quit(0 if passed == checks.size() else 1)
