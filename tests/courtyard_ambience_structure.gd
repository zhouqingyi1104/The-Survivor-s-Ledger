extends "res://tests/courtyard_scenery.gd"
## C1 结构小修独立契约（有限无头场景，自带 COMPLETE 标记）：
## 1) 砖烟囱/顶帽与晾衣木桩/横杆属于永久 fixtures 容器（GROUPS 之外、8 键投影不变）；
## 2) 真实 HomeWorld 经 set_time 午→夜→大雪→恢复 与 set_preset 切换时，fixtures 的
##    实例 ID、global_transform、is_visible_in_tree 全程不变且始终可见，烟缕/布衣按投影切；
## 3) 未合并树中 fixtures 构件类型/数量/材质正确，净空与禁用节点扫描覆盖 fixtures；
## 4) current_state 缺 meta 不打 ERROR、返回投影副本。
##
## 运行：godot --headless --path <项目> res://tests/courtyard_ambience_structure.tscn

const A_PATH := "res://scripts/world/home_ambience.gd"
const LP := "[COURTYARD_AMB_STRUCTURE]"

const FORBIDDEN := ["CollisionObject3D", "NavigationRegion3D", "Light3D",
	"AudioStreamPlayer", "AudioStreamPlayer3D", "GPUParticles3D", "CPUParticles3D"]


func _finish(code: int) -> void:
	print("%s COMPLETE code=%d" % [LP, code])
	get_tree().quit(code)


func _ready() -> void:
	# 本进程绝不写玩家存档 / 根 Memory.md（与基类同等级隔离，路径按 PID 唯一）。
	Game.no_save = true
	var pid := OS.get_process_id()
	Game.save_path = "user://ambstruct-save-%d.json" % pid
	Game.meta_path = "user://ambstruct-meta-%d.json" % pid
	Game.memory_path = "user://ambstruct-Memory-%d.md" % pid
	Game.run = {}
	Game.meta = State.new_meta()

	var checks: Array = await _structure_contract()
	if checks.is_empty():
		push_error("structure contract produced no checks")
		_finish(1)
		return
	var passed := 0
	for c in checks:
		if bool(c.ok):
			passed += 1
		else:
			print("%s CHECK FAIL %s：%s" % [LP, c.name, c.detail])
	print("%s checks=%d passed=%d failed=%d" % [LP, checks.size(), passed, checks.size() - passed])
	_finish(0 if passed == checks.size() else 1)


func _structure_contract() -> Array:
	var out: Array = []
	var A = load(A_PATH)
	var S = load(SURR_PATH)
	out.append(_check("ambience_module_loads", A != null,
		"load(%s)=%s" % [A_PATH, A]))
	if A == null:
		return out

	# ---- 8 键投影协议：fixtures 不在投影里，键数/键名不变 ----
	var pj: Dictionary = A.project("post", 1, 720, false)
	var keys_ok: bool = pj.keys().size() == 8 and not pj.has("fixtures") and not A.GROUPS.has("fixtures")
	for g in A.GROUPS:
		if not pj.has(g) or typeof(pj[g]) != TYPE_BOOL:
			keys_ok = false
	out.append(_check("projection_still_eight_keys", keys_ok,
		"GROUPS=%d 投影键=%s，fixtures 不得入投影" % [A.GROUPS.size(), JSON.stringify(pj.keys())]))

	# ---- 真实 HomeWorld（生产合并树）----
	var world = HomeWorld.new()
	add_child(world)
	await get_tree().process_frame
	var run: Dictionary = _fixture_run()
	out.append(_check("fixture_run_ok", not run.is_empty() and run.get("phase", "") == "post",
		"fixture run phase=%s" % run.get("phase", "")))
	if run.is_empty():
		return out
	run.t = 360
	world.sync(run)
	await get_tree().process_frame

	var surr: Node3D = world.get_node_or_null("surroundings")
	var amb: Node3D = surr.get_node_or_null("ambience") if surr != null else null
	var fx: Node3D = amb.get_node_or_null("fixtures") if amb != null else null
	out.append(_check("fixtures_container_present",
		amb != null and fx != null and fx is Node3D and fx.get_parent() == amb,
		"amb=%s fixtures=%s parent=%s" % [amb, fx, fx.get_parent() if fx != null else null]))
	if amb == null:
		return out
	if fx != null:
		out.append(_check("fixtures_rendered_in_production", _rendered_count(fx) > 0,
			"永久结构合并后渲染件 %d" % _rendered_count(fx)))

	var ids0 := _snapshot_ids(fx) if fx != null else {}
	var xf0 := _snapshot_xf(fx) if fx != null else {}

	var day: Dictionary = run.duplicate(true)
	day.t = 360
	var night_run: Dictionary = run.duplicate(true)
	night_run.t = 1020
	var heavy: Dictionary = run.duplicate(true)
	heavy.pday = 8
	heavy.t = 360 + 7 * 1440

	var points: Array = [
		{"name": "noon", "r": day, "smoke": true, "laundry": true},
		{"name": "night", "r": night_run, "smoke": false, "laundry": false},
		{"name": "heavy_noon", "r": heavy, "smoke": true, "laundry": false},
		{"name": "restore_noon", "r": day, "smoke": true, "laundry": true},
	]
	var perm_bad := 0
	var switch_bad := 0
	var log_lines: Array = []
	for pt in points:
		world.set_time(pt.r)
		await get_tree().process_frame
		var same: bool = fx != null and _snapshot_ids(fx) == ids0 and _snapshot_xf(fx) == xf0 and fx.is_visible_in_tree()
		if not same:
			perm_bad += 1
		var sm := (amb.get_node("smoke_post") as Node3D).visible
		var ld := (amb.get_node("laundry") as Node3D).visible
		if sm != bool(pt.smoke) or ld != bool(pt.laundry):
			switch_bad += 1
		log_lines.append("%s:perm=%s,smoke=%s/%s,laundry=%s/%s"
			% [pt.name, same, sm, pt.smoke, ld, pt.laundry])

	# set_preset 两路：夜（ctx 灾后 pday1 非大雪）→ 午
	world.set_preset("night", 400)
	await get_tree().process_frame
	var preset_night_ok: bool = fx != null and _snapshot_ids(fx) == ids0 and _snapshot_xf(fx) == xf0 \
		and fx.is_visible_in_tree() and not (amb.get_node("smoke_post") as Node3D).visible \
		and not (amb.get_node("laundry") as Node3D).visible
	world.set_preset("noon", 400)
	await get_tree().process_frame
	var preset_noon_ok: bool = fx != null and _snapshot_ids(fx) == ids0 and _snapshot_xf(fx) == xf0 \
		and fx.is_visible_in_tree() and (amb.get_node("smoke_post") as Node3D).visible \
		and (amb.get_node("laundry") as Node3D).visible

	out.append(_check("fixtures_permanent_through_set_time",
		perm_bad == 0, "set_time 四点中永久结构变动 %d：%s" % [perm_bad, "; ".join(log_lines)]))
	out.append(_check("smoke_clothes_switch_with_set_time",
		switch_bad == 0, "烟/衣显隐与投影不符次数 %d：%s" % [switch_bad, "; ".join(log_lines)]))
	out.append(_check("fixtures_permanent_through_set_preset",
		preset_night_ok and preset_noon_ok,
		"preset night 永久+烟衣=%s；preset noon=%s" % [preset_night_ok, preset_noon_ok]))

	# ---- 未合并真实构建：逐构件核对永久/可消切分 ----
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var ra: Node3D = raw.get_node_or_null("ambience")
	var rfx: Node3D = ra.get_node_or_null("fixtures") if ra != null else null
	out.append(_check("raw_fixtures_container_present",
		rfx != null and rfx is Node3D, "未合并 ambience/fixtures=%s" % rfx))
	if rfx != null:
		var brick := _chimney_parts(rfx)
		var wood := _frame_parts(rfx)
		var all_vis: Array = _all_visuals(rfx)
		out.append(_check("fixture_parts_exact",
			brick.size() == 26 and wood.size() == 18 and all_vis.size() == 44,
			"砖烟囱件 %d（须 13 户×2=26），木支架件 %d（须 6 户×3=18），fixtures 总件 %d（须 44）"
			% [brick.size(), wood.size(), all_vis.size()]))

		# 烟小组只剩烟缕（球），晾衣小组只剩布衣（盒）
		var sp: Array = _all_visuals(ra.get_node("smoke_post"))
		var spe: Array = _all_visuals(ra.get_node("smoke_pre"))
		var lc: Array = _all_visuals(ra.get_node("laundry"))
		var puffs_ok: bool = sp.size() == 27 and spe.size() == 12 and lc.size() == 18
		for v in sp + spe:
			if (v as MeshInstance3D).mesh.get_class() != "SphereMesh":
				puffs_ok = false
		for v in lc:
			if (v as MeshInstance3D).mesh.get_class() != "BoxMesh":
				puffs_ok = false
		out.append(_check("toggle_groups_hold_only_smoke_and_cloth",
			puffs_ok, "smoke_post 球=%d（须27），smoke_pre 球=%d（须12），晾衣盒=%d（须18）"
			% [sp.size(), spe.size(), lc.size()]))

		# 夜：fixtures 全部仍可见；烟缕全隐。大雪午：支架在、烟在、布衣隐。
		A.apply(ra, A.project("post", 1, 1380, false))
		var fx_hidden := 0
		for v in all_vis:
			if not (v as Node3D).is_visible_in_tree():
				fx_hidden += 1
		var smoke_all_hidden := true
		for v in sp:
			if (v as Node3D).is_visible_in_tree():
				smoke_all_hidden = false
		A.apply(ra, A.project("post", 8, 720, true))
		var fx_hidden_heavy := 0
		for v in all_vis:
			if not (v as Node3D).is_visible_in_tree():
				fx_hidden_heavy += 1
		var smoke_heavy_vis := (ra.get_node("smoke_post") as Node3D).visible
		var cloth_heavy_hidden := not (ra.get_node("laundry") as Node3D).visible
		out.append(_check("fixtures_visible_night_and_heavy",
			fx_hidden == 0 and smoke_all_hidden and fx_hidden_heavy == 0
				and smoke_heavy_vis and cloth_heavy_hidden,
			"夜 fixtures 隐 %d、烟缕全隐=%s；大雪 fixtures 隐 %d、炊烟=%s、布衣隐=%s"
			% [fx_hidden, smoke_all_hidden, fx_hidden_heavy, smoke_heavy_vis, cloth_heavy_hidden]))

		# fixtures 净空：完整旋转变换 AABB，>0.5m 构件不进核心 footprint / 迎战通道
		var intrude_core := 0
		var intrude_lane := 0
		for v in all_vis:
			var vi := v as VisualInstance3D
			var ab: AABB = vi.global_transform * vi.get_aabb()
			if ab.end.y <= 0.5:
				continue
			var c: Vector3 = ab.get_center()
			if absf(c.x) < 10.2 and c.z > -8.2 and c.z < 7.0:
				intrude_core += 1
			if absf(c.x) <= 3.0 and c.z >= 7.5 and c.z <= 17.0:
				intrude_lane += 1
		out.append(_check("fixtures_core_lane_clearance",
			intrude_core == 0 and intrude_lane == 0,
			"fixtures 侵核心 %d，侵迎战通道 %d" % [intrude_core, intrude_lane]))

		# fixtures 禁用节点扫描（未合并树）
		var bad := _scan_forbidden(rfx)
		out.append(_check("fixtures_no_forbidden_nodes",
			bad.is_empty(), "fixtures 禁用节点：%s" % [JSON.stringify(bad.slice(0, 6))]))

	# 生产树 fixtures 同样扫一遍禁用节点
	out.append(_check("production_fixtures_no_forbidden_nodes",
		fx != null and _scan_forbidden(fx).is_empty(),
		"生产 fixtures：%s" % [JSON.stringify([] if fx == null else _scan_forbidden(fx).slice(0, 6))]))

	# ---- meta：缺键不报错；current_state 返回副本；同状态早退 ----
	var tmp := Node3D.new()
	add_child(tmp)
	var empty_state: Dictionary = A.current_state(tmp)
	var null_state: Dictionary = A.current_state(null)
	var first: bool = A.apply(tmp, A.project("post", 1, 720, false))
	var second: bool = A.apply(tmp, A.project("post", 1, 720, false))
	var cur: Dictionary = A.current_state(amb)  # 最后是 preset noon（灾后 pday1 非大雪）
	var copy_ok: bool = bool(cur.get("smoke_post", false)) and bool(cur.get("laundry", false))
	cur["smoke_post"] = false
	cur["injected_key"] = true
	var cur2: Dictionary = A.current_state(amb)
	copy_ok = copy_ok and bool(cur2.get("smoke_post", false)) and not cur2.has("injected_key")
	out.append(_check("meta_default_copy_and_early_return",
		empty_state.is_empty() and null_state.is_empty() and first and not second and copy_ok,
		"缺键默认=%s/%s，apply 首/次=%s/%s，副本防篡改=%s，当前投影=%s"
		% [empty_state.is_empty(), null_state.is_empty(), first, second, copy_ok, JSON.stringify(cur2)]))

	probe.queue_free()
	tmp.queue_free()
	return out


# ---------- 工具 ----------

func _snapshot_ids(n: Node) -> Dictionary:
	if n == null:
		return {}
	var d := {n.get_instance_id(): true}
	for c in n.get_children():
		var sub := _snapshot_ids(c)
		for k in sub:
			d[k] = true
	return d


func _snapshot_xf(n: Node) -> Dictionary:
	if n == null:
		return {}
	var d := {}
	for v in _all_visuals(n):
		var vi := v as VisualInstance3D
		d[vi.get_instance_id()] = vi.global_transform
	return d


## 砖烟囱：0.4×0.7×0.4 囱身 + 0.56×0.12×0.56 顶帽（按形体而非颜色识别，纹理材质无关）。
func _chimney_parts(root: Node) -> Array:
	var out: Array = []
	for v in _all_visuals(root):
		var mi := v as MeshInstance3D
		if mi.mesh is BoxMesh:
			var s: Vector3 = (mi.mesh as BoxMesh).size
			if (s.is_equal_approx(Vector3(0.4, 0.7, 0.4))) \
					or s.is_equal_approx(Vector3(0.56, 0.12, 0.56)):
				out.append(mi)
	return out


## 晾衣支架：两根 r_bot=0.05/h=1.9 木桩 + 一根 r=0.015 横杆。
func _frame_parts(root: Node) -> Array:
	var out: Array = []
	for v in _all_visuals(root):
		var mi := v as MeshInstance3D
		if mi.mesh is CylinderMesh:
			var m := mi.mesh as CylinderMesh
			if is_equal_approx(m.height, 1.9) and is_equal_approx(m.bottom_radius, 0.05) \
					or (is_equal_approx(m.top_radius, 0.015) and is_equal_approx(m.bottom_radius, 0.015)):
				out.append(mi)
	return out


func _scan_forbidden(root: Node) -> Array:
	var found: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for cls in FORBIDDEN:
			if n.is_class(cls):
				found.append("%s:%s" % [n.name, cls])
		if n.get_script() != null:
			found.append("%s:script" % n.name)
		for c in n.get_children():
			stack.append(c)
	return found
