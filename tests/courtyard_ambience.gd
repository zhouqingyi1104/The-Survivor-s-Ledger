extends "res://tests/courtyard_scenery.gd"
## C1 宅院生活与灾后氛围契约测试（纵向 TDD，逐片追加）。
##
## 运行期检测：home_ambience.gd 缺失时 load() 为 null，契约以「特性缺失」失败
## （CHECK FAIL + COMPLETE code=1），不是 preload 编译失败。
##
## 运行（无头契约）：
##   godot --headless --path <项目> res://tests/courtyard_ambience.tscn
## 真窗口矩阵/性能（参数同父类）：
##   godot --path <项目> res://tests/courtyard_ambience.tscn -- --baseline ...

const AMBIENCE_PATH := "res://scripts/world/home_ambience.gd"
const LOG_PREFIX_AMB := "[COURTYARD_AMBIENCE]"
const LANTERN_EMIT := 2.5  # 自家灯笼点亮能量（arch.set_lantern），邻宅窗灯必须明显更弱

## 子类完成标记（启动器只认它）；父类 _ready 的所有出口都虚调用本函数。
func _finish(code: int) -> void:
	print("%s COMPLETE code=%d" % [LOG_PREFIX_AMB, code])
	get_tree().quit(code)


## 等待真实导航可查询，而非假定固定三个物理帧足够；无头异步烘焙在冷启动时
## 偶尔尚未同步。最多等5秒，超时仍保留真实不可达结果让契约失败，不降低判定。
func _contract(world: Node3D, run: Dictionary) -> Array:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_legality_cache.clear()
		var leg := _probe_foci(world)
		var ready := leg.size() == C1_FOCI.size()
		for value in leg.values():
			ready = ready and bool(value.get("reachable", false))
		if ready:
			break
		await get_tree().physics_frame
	return await super(world, run)


func _extra_contract(world: Node3D, run: Dictionary) -> Array:
	var out: Array = []
	_fixture_run_cached = run  # 真窗口矩阵复用同一夹具局面（见 _prepare_capture）
	var A = load(AMBIENCE_PATH)
	var S = load(SURR_PATH)
	var surr: Node3D = world.get_node_or_null("surroundings")
	var amb: Node3D = null
	if surr != null:
		amb = surr.get_node_or_null("ambience")
	out.append(_check("ambience_module_loads", A != null,
		"运行期 load(%s)：%s" % [AMBIENCE_PATH, "null（C1 氛围工厂尚未实现）" if A == null else "ok"]))
	out.append(_check("ambience_node_present",
		amb != null and amb is Node3D and amb.get_parent() == surr,
		"surroundings 下须有独立视觉根 \"ambience\"；实际：%s"
		% ("null（尚未接线）" if amb == null else "%s parent=%s" % [amb.get_class(), amb.get_parent()])))
	if A == null or amb == null:
		return out

	out.append_array(_slice_windows(world, run, A, S, amb))
	out.append_array(_slice_camera_legal(world))
	out.append_array(_slice_life(world, run, A, S, amb))
	out.append_array(_slice_phase_weather(world, run, A, S, amb))
	out.append_array(_slice_isolation(world, run, A, S, amb))
	return out


# ---------- 切片 2：昼/夜纸窗 ----------

func _slice_windows(world: Node3D, run: Dictionary, A, S, amb: Node3D) -> Array:
	var out: Array = []
	var missing_groups: Array = []
	for gname in A.GROUPS:
		if amb.get_node_or_null(gname) == null:
			missing_groups.append(gname)
	out.append(_check("ambience_groups_present", missing_groups.is_empty(),
		"缺小组：%s" % ", ".join(missing_groups)))

	# 未合并构建：逐构件核对窗灯真的贴在 C0 纸窗格上（完整旋转变换由 global_transform 承担）
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var raw_amb: Node3D = raw.get_node_or_null("ambience")
	var panes := _pane_centers(raw)
	var glows: Array = _group_mesh_centers(raw_amb, "win_post") if raw_amb != null else []
	glows.append_array(_group_mesh_centers(raw_amb, "win_pre") if raw_amb != null else [])
	# 贴合判定（真实窗法向，不再在世界 xy 平面上猜屋心径向）：
	# 从 C0 near 层真实纸窗 BoxMesh 取中心与外法向（global_transform.basis.z，
	# 纸窗局部 +Z 朝墙外，房屋 rotation 与侧窗 ry=90 都已含在全局变换里）。
	# 每片窗灯对每片纸窗求 delta：along=delta.dot(normal)、tang=切向分量长度。
	# 几何（home_surroundings._house/_window 实测）：纸窗中心在窗节点局部 z=.02、
	# 窗节点在 d/2+.01，实体前墙外皮在 d/2+.12 → 墙外皮相对纸窗中心 0.09；
	# 生产窗灯中心局部 z=.130（相对纸窗中心 +.110）、厚 .012，背面 +.104
	# 越过墙皮并留约 .014 间隙。故切向 ≤.06、窗灯中心法向距须在 .10.. .14。
	# 注意 C0 前墙是实体、纸窗并未挖洞，窗灯必须抬层到墙外，不许放宽几何。
	var bad := 0
	var lift_bad := 0
	var nearest_d := 1e9
	var lift_lo := 1e9
	var lift_hi := -1e9
	for g in glows:
		var best := 1e9
		var best_along := 0.0
		for p in panes:
			var pc: Vector3 = p["c"]
			var pn: Vector3 = p["n"]
			var alongv: float = (g - pc).dot(pn)
			var tang: float = ((g - pc) - pn * alongv).length()
			if tang < best:
				best = tang
				best_along = alongv
		nearest_d = minf(nearest_d, best)
		if best > 0.06:
			bad += 1
		if best_along < 0.10 or best_along > 0.14:
			lift_bad += 1
		lift_lo = minf(lift_lo, best_along)
		lift_hi = maxf(lift_hi, best_along)
	var lit_houses := _lit_house_set(glows)
	var sides := _side_spread(glows)
	var lit_all_real := true
	for h in lit_houses.keys():
		if _house_window_count(int(h)) == 0:
			lit_all_real = false
	out.append(_check("window_glow_on_real_panes",
		panes.size() >= 20 and glows.size() >= 10 and bad == 0 and lift_bad == 0,
		"纸窗格 %d 片，窗灯 %d 片，切向未贴合 %d（最近 %.3f），法向抬层错误 %d（法向距 [%.3f,%.3f]，须 .10.. .14）"
		% [panes.size(), glows.size(), bad, nearest_d, lift_bad, lift_lo, lift_hi]))
	out.append(_check("window_glow_four_sides",
		bool(sides["n"]) and bool(sides["s"]) and bool(sides["w"]) and bool(sides["e"])
			and lit_houses.size() >= 8,
		"亮灯户 %d 户，四向 n/s/w/e=%s/%s/%s/%s（细节不许只堆最远北排）"
		% [lit_houses.size(), sides["n"], sides["s"], sides["w"], sides["e"]]))
	out.append(_check("window_glow_not_on_windowless_house",
		glows.size() <= panes.size() and lit_all_real,
		"窗灯 %d ≤ 实窗格 %d；亮灯户均有真窗=%s" % [glows.size(), panes.size(), lit_all_real]))

	# 生产构建（已合并）：win_post 有真实渲染网格；win_pre 本切片尚为空
	var wp: Node3D = amb.get_node("win_post")
	var we: Node3D = amb.get_node("win_pre")
	out.append(_check("window_group_merged_rendered",
		_rendered_count(wp) > 0, "win_post 合并后渲染件 %d" % _rendered_count(wp)))
	out.append(_check("window_extra_group_rendered",
		_rendered_count(we) > 0, "win_pre 渲染件 %d（灾前加户窗灯）" % _rendered_count(we)))

	# 自发光能量弱于自家灯笼，整树无 Light3D
	var energies: Array = []
	var emit_bad := 0
	for v in _all_visuals(wp):
		var m: Material = (v as GeometryInstance3D).material_override
		if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
			var e: float = (m as BaseMaterial3D).emission_energy_multiplier
			energies.append(e)
			if e <= 0.0 or e >= LANTERN_EMIT:
				emit_bad += 1
	var lights := _count_class(amb, "Light3D")
	var energy_text: Array = []
	for e in energies:
		energy_text.append("%.2f" % e)
	out.append(_check("window_glow_weak_emissive_no_light",
		not energies.is_empty() and emit_bad == 0 and lights == 0,
		"自发光能量 %s（须 >0 且 < 灯笼 %.1f），Light3D=%d"
		% [energy_text, LANTERN_EMIT, lights]))

	# 真实 HomeWorld 接线：昼隐夜显，set_time / set_preset 两条路
	var day: Dictionary = run.duplicate()
	day.t = 360       # Post.clock = (360+360)%1440 = 12:00
	var night_run: Dictionary = run.duplicate()
	night_run.t = 1020  # clock 23:00
	world.sync(day)
	var wp_day_visible := wp.visible
	world.sync(night_run)
	var wp_night_visible := wp.visible
	world.set_preset("noon", 400)
	var wp_preset_noon := wp.visible
	world.set_preset("night", 400)
	var wp_preset_night := wp.visible
	world.set_preset("dusk", 400)
	var wp_preset_dusk := wp.visible
	out.append(_check("homeworld_window_day_night_switch",
		not wp_day_visible and wp_night_visible and not wp_preset_noon
			and wp_preset_night and wp_preset_dusk,
		"昼 sync=%s 夜 sync=%s preset noon/night/dusk=%s/%s/%s"
		% [wp_day_visible, wp_night_visible, wp_preset_noon, wp_preset_night, wp_preset_dusk]))

	# 早退陷阱：_set_lanterns 同值早退不得挡住窗灯更新（连续两次夜→一次午必须隐）
	world.set_time(night_run)
	world.set_time(night_run)
	world.set_time(day)
	out.append(_check("set_time_not_blocked_by_lantern_earlyreturn",
		not wp.visible, "两次夜 set_time 后再设正午，win_post.visible=%s（须 false）" % wp.visible))

	# 重复 sync 只切 visible：ambience 与 C0 near 层节点实例 id 不变、节点数不变
	var amb_ids_before := _instance_ids(amb)
	var near_ids_before := _instance_ids(world.surroundings.get_node("near"))
	var amb_count_before := _count_nodes(amb)
	world.sync(night_run)
	world.sync(night_run)
	world.sync(day)
	var amb_ids_after := _instance_ids(amb)
	var near_ids_after := _instance_ids(world.surroundings.get_node("near"))
	out.append(_check("repeat_sync_no_rebuild",
		amb_ids_before == amb_ids_after and near_ids_before == near_ids_after
			and _count_nodes(amb) == amb_count_before,
		"amb 节点 %d→%d，id 相等=%s；near 层 id 相等=%s"
		% [amb_count_before, _count_nodes(amb), amb_ids_before == amb_ids_after,
			near_ids_before == near_ids_after]))

	probe.queue_free()
	return out


# ---------- 切片 3：炊烟 / 晾晒 / 短雪痕 ----------

func _slice_life(world: Node3D, run: Dictionary, A, S, amb: Node3D) -> Array:
	var out: Array = []
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var raw_amb: Node3D = raw.get_node_or_null("ambience")

	# 烟：静态、半透明、无发射、无粒子；贴烟囱根部在屋顶以上，细缕不扫地、不冒充火灾
	var smoke := _world_aabbs(raw_amb, "smoke_post")
	var particle_n := _count_class(amb, "GPUParticles3D") + _count_class(amb, "CPUParticles3D")
	var smoke_emit_bad := 0
	var smoke_wisps := 0
	for v in _group_visuals(raw_amb, "smoke_post"):
		var m: Material = (v as GeometryInstance3D).material_override
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			if bm.emission_enabled:
				smoke_emit_bad += 1
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bm.albedo_color.a < 0.6:
				smoke_wisps += 1
	var sm_hi := 0.0
	var sm_low := 9.0
	var sm_drift := 0.0
	var sm_centers: Array = []
	for b in smoke:
		sm_hi = maxf(sm_hi, b.top)
		sm_low = minf(sm_low, b.center.y)
		var near := _nearest_house(b.center, S)
		if near.d > sm_drift:
			sm_drift = near.d
		sm_centers.append(b.center)
	var smoke_sides := _side_spread(sm_centers)
	out.append(_check("smoke_cheap_static",
		# 只数 9 户×3 缕烟；26 件实体烟囱由 structure 契约单独验，不能混算活动烟缕。
		smoke.size() == 27 and particle_n == 0 and smoke_wisps == 27 and smoke_emit_bad == 0,
		"烟构件 %d（半透明烟缕 %d），粒子节点 %d，发光件 %d"
		% [smoke.size(), smoke_wisps, particle_n, smoke_emit_bad]))
	out.append(_check("smoke_thin_on_rooftops_four_sides",
		sm_low > 2.4 and sm_hi < 8.0 and sm_drift < 2.4
			and bool(smoke_sides["n"]) and bool(smoke_sides["s"])
			and bool(smoke_sides["w"]) and bool(smoke_sides["e"]),
		"烟 y[%.2f,%.2f]，离屋心水平最远 %.2fm，四向=%s/%s/%s/%s（不扫地、不冒充火柱）"
		% [sm_low, sm_hi, sm_drift, smoke_sides["n"], smoke_sides["s"],
			smoke_sides["w"], smoke_sides["e"]]))

	# 晾晒组只含 6 户×3 衣片；18 件永久木支架另由 structure 契约验收。
	var laundry := _world_aabbs(raw_amb, "laundry")
	var lc: Array = []
	var l_over_core := 0
	var l_low := 9.0
	var l_high := 0.0
	for b in laundry:
		lc.append(b.center)
		if absf(b.center.x) < 10.2 and b.center.z > -8.2 and b.center.z < 7.0:
			l_over_core += 1
		l_low = minf(l_low, b.center.y)
		l_high = maxf(l_high, b.top)
	var laundry_sides := _side_spread(lc)
	var laundry_houses := _lit_house_set(lc)
	out.append(_check("laundry_yards_four_sides",
		laundry.size() == 18 and l_over_core == 0
			and bool(laundry_sides["n"]) and bool(laundry_sides["s"])
			and bool(laundry_sides["w"]) and bool(laundry_sides["e"])
			and laundry_houses.size() >= 5 and l_high <= 2.6,
		"晾晒构件 %d，压核心 %d，户 %d，四向=%s/%s/%s/%s，y[%.2f,%.2f]"
		% [laundry.size(), l_over_core, laundry_houses.size(),
			laundry_sides["n"], laundry_sides["s"], laundry_sides["w"], laundry_sides["e"],
			l_low, l_high]))

	# 短雪痕：全部贴地（中心/顶都很低），从门前向街短铺，不向核心拖长
	var traces := _world_aabbs(raw_amb, "traces")
	var tr_high := 0.0
	var tr_over_core := 0
	for b in traces:
		tr_high = maxf(tr_high, b.top)
		if absf(b.center.x) < 10.2 and b.center.z > -8.2 and b.center.z < 7.0:
			tr_over_core += 1
	out.append(_check("traces_low_and_short",
		traces.size() >= 15 and tr_high < 0.25 and tr_over_core == 0,
		"雪痕 %d 条，最高顶 %.3f m，压核心 %d" % [traces.size(), tr_high, tr_over_core]))

	# 生产合并后三组都有真实渲染件
	for gname in ["smoke_post", "laundry", "traces"]:
		var g: Node3D = amb.get_node(gname)
		out.append(_check("group_merged_rendered_%s" % gname,
			_rendered_count(g) > 0, "%s 合并后渲染件 %d" % [gname, _rendered_count(g)]))

	# 昼显夜隐（sync 与 set_preset 两条路）；灾后小雪白天必须保留炊烟与晾晒
	var day: Dictionary = run.duplicate()
	day.t = 360
	var night_run: Dictionary = run.duplicate()
	night_run.t = 1020
	world.sync(day)
	var day_vis := {}
	var night_vis := {}
	for gname in ["smoke_post", "laundry", "traces"]:
		day_vis[gname] = (amb.get_node(gname) as Node3D).visible
	world.sync(night_run)
	for gname in ["smoke_post", "laundry", "traces"]:
		night_vis[gname] = (amb.get_node(gname) as Node3D).visible
	world.set_preset("noon", 400)
	var preset_noon := {}
	for gname in ["smoke_post", "laundry", "traces"]:
		preset_noon[gname] = (amb.get_node(gname) as Node3D).visible
	world.set_preset("night", 400)
	var preset_night := {}
	for gname in ["smoke_post", "laundry", "traces"]:
		preset_night[gname] = (amb.get_node(gname) as Node3D).visible
	var pure_day: Dictionary = A.state_for_run(day)
	out.append(_check("life_day_night_switch",
		bool(day_vis.smoke_post) and bool(day_vis.laundry) and bool(day_vis.traces)
			and not bool(night_vis.smoke_post) and not bool(night_vis.laundry)
			and bool(preset_noon.smoke_post) and not bool(preset_night.smoke_post)
			and bool(pure_day.smoke_post) and bool(pure_day.laundry),
		"昼 %s 夜 %s preset 午/夜 smoke=%s/%s；纯投影 smoke_post=%s"
		% [JSON.stringify(day_vis), JSON.stringify(night_vis),
			preset_noon.smoke_post, preset_night.smoke_post, pure_day.smoke_post]))

	probe.queue_free()
	return out


# ---------- 切片 3 几何工具 ----------

func _group_visuals(root: Node, gname: String) -> Array:
	var g: Node = root.get_node_or_null(gname)
	if g == null:
		return []
	return _all_visuals(g)


## 完整旋转变换后的世界轴对齐包围盒（Transform3D * AABB 会按旋转扩张）。
func _world_aabbs(root: Node, gname: String) -> Array:
	var out: Array = []
	var g: Node = root.get_node_or_null(gname)
	if g == null:
		return out
	for v in _all_visuals(g):
		var vi := v as VisualInstance3D
		var ab: AABB = vi.global_transform * vi.get_aabb()
		out.append({"center": ab.get_center(), "half": ab.size * 0.5,
			"top": ab.end.y, "bottom": ab.position.y})
	return out


func _nearest_house(p: Vector3, S) -> Dictionary:
	var best_i := -1
	var best_d := 1e9
	for i in S.NEAR_HOUSES.size():
		var h: Dictionary = S.NEAR_HOUSES[i]
		var d2 := Vector2(p.x - float(h.x), p.z - float(h.z)).length()
		if d2 < best_d:
			best_d = d2
			best_i = i
	return {"i": best_i, "d": best_d}


# ---------- 切片 4：灾前/灾后阶段 + 小雪/大雪 ----------

func _slice_phase_weather(world: Node3D, run: Dictionary, A, S, amb: Node3D) -> Array:
	var out: Array = []
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var raw_amb: Node3D = raw.get_node_or_null("ambience")

	# 封门旧损：门板位置交叉旧板，固定四户跨四向，y 在门高范围内，不出房屋 footprint
	var dmg := _world_aabbs(raw_amb, "damage")
	var dmg_houses := {}
	var dmg_bad := 0
	var dmg_y_hi := 0.0
	var dmg_y_lo := 9.0
	for b in dmg:
		var near := _nearest_house(b.center, S)
		if near.i < 0:
			dmg_bad += 1
			continue
		var h: Dictionary = S.NEAR_HOUSES[near.i]
		dmg_houses[near.i] = true
		var dx: float = b.center.x - float(h.x)
		var dz: float = b.center.z - float(h.z)
		var dloc := Transform3D(Basis(Vector3.UP, deg_to_rad(-float(h.rot))), Vector3.ZERO) \
			* Vector3(dx, 0.0, dz)
		if near.d > 5.0 or absf(dloc.x) > float(h.w) / 2.0 + 0.6 \
				or absf(dloc.z) > float(h.d) / 2.0 + 0.9:
			dmg_bad += 1
		dmg_y_hi = maxf(dmg_y_hi, b.top)
		dmg_y_lo = minf(dmg_y_lo, b.bottom)
	var dmg_sides: Array = []
	for i in dmg_houses.keys():
		var h: Dictionary = S.NEAR_HOUSES[int(i)]
		var x: float = h.x
		var z: float = h.z
		if z < -10.0:
			dmg_sides.append("n")
		if z > 8.0:
			dmg_sides.append("s")
		if x < -12.0:
			dmg_sides.append("w")
		if x > 12.0:
			dmg_sides.append("e")
	out.append(_check("damage_boarded_doors_four_sides",
		dmg.size() >= 8 and dmg_bad == 0 and dmg_houses.size() == 4
			and dmg_sides.has("n") and dmg_sides.has("s") and dmg_sides.has("w") and dmg_sides.has("e")
			and dmg_y_lo > 0.3 and dmg_y_hi < 3.2,
		"旧损 %d 件，户 %s（%s），越界 %d，y[%.2f,%.2f]"
		% [dmg.size(), dmg_houses.keys(), "/".join(dmg_sides), dmg_bad, dmg_y_lo, dmg_y_hi]))

	# 大雪积雪：门前矮雪包 + 檐口厚雪，四向都有，雪包不挡门中轴太高
	var heavy := _world_aabbs(raw_amb, "snow_heavy")
	var heavy_sides := _side_spread(heavy.map(func(b): return b.center))
	var heavy_top := 0.0
	for b in heavy:
		heavy_top = maxf(heavy_top, b.top)
	out.append(_check("heavy_snow_built_four_sides",
		heavy.size() >= 10 and heavy_top < 5.2
			and bool(heavy_sides["n"]) and bool(heavy_sides["s"])
			and bool(heavy_sides["w"]) and bool(heavy_sides["e"]),
		"积雪 %d 件，最高 %.2f m，四向=%s/%s/%s/%s"
		% [heavy.size(), heavy_top, heavy_sides["n"], heavy_sides["s"],
			heavy_sides["w"], heavy_sides["e"]]))

	# 灾前额外窗/烟小组有真网格
	out.append(_check("pre_extra_groups_rendered",
		_rendered_count(amb.get_node("win_pre")) > 0
			and _rendered_count(amb.get_node("smoke_pre")) > 0,
		"win_pre=%d smoke_pre=%d"
		% [_rendered_count(amb.get_node("win_pre")), _rendered_count(amb.get_node("smoke_pre"))]))

	# ---- 纯投影：阶段 / pday / 时辰 / 天气 ----
	var pre_noon := State.new_run("scholar", State.new_meta(), FIXED_SEED)
	pre_noon.t = 360
	var pre_night := pre_noon.duplicate(true)
	pre_night.t = 1020
	var s_pre_noon: Dictionary = A.state_for_run(pre_noon)
	var s_pre_night: Dictionary = A.state_for_run(pre_night)
	var small_noon: Dictionary = A.project("post", 1, 720, false)
	var small_night: Dictionary = A.project("post", 1, 1380, false)
	var heavy_noon: Dictionary = A.project("post", 8, 720, true)
	var heavy_night: Dictionary = A.project("post", 8, 1380, true)
	var p20: Dictionary = A.project("post", 20, 720, true)
	out.append(_check("projection_pre_phase",
		not bool(s_pre_noon.damage) and bool(s_pre_noon.smoke_post) and bool(s_pre_noon.smoke_pre)
			and bool(s_pre_noon.laundry) and not bool(s_pre_noon.snow_heavy)
			and bool(s_pre_night.win_post) and bool(s_pre_night.win_pre)
			and not bool(s_pre_night.damage),
		"灾前午 %s；灾前后夜 %s（不得有旧损）" % [JSON.stringify(s_pre_noon), JSON.stringify(s_pre_night)]))
	out.append(_check("projection_post_small_snow_life",
		bool(small_noon.damage) and bool(small_noon.smoke_post) and not bool(small_noon.smoke_pre)
			and bool(small_noon.laundry) and bool(small_noon.traces) and not bool(small_noon.snow_heavy)
			and bool(small_night.win_post) and not bool(small_night.win_pre) and bool(small_night.damage),
		"灾后小雪午 %s；夜 %s（生活痕迹保留、旧损显、加户窗不亮）"
		% [JSON.stringify(small_noon), JSON.stringify(small_night)]))
	out.append(_check("projection_heavy_snow",
		bool(heavy_noon.snow_heavy) and not bool(heavy_noon.laundry) and not bool(heavy_noon.traces)
			and bool(heavy_noon.smoke_post) and bool(heavy_noon.damage)
			and bool(heavy_night.win_post) and bool(heavy_night.snow_heavy) and bool(heavy_night.damage)
			and bool(p20.damage),
		"大雪午 %s；大雪夜 %s；p20 damage=%s（收晾晒/显积雪/仍有炊烟/旧损恒定）"
		% [JSON.stringify(heavy_noon), JSON.stringify(heavy_night), p20.damage]))

	# 大雪由真实 weather 表派生：pday8 cold20、pday12 cold30、pday1 cold10（都对齐正午）
	var day_base: Dictionary = run.duplicate(true)
	day_base.t = 360
	var heavy_run: Dictionary = day_base.duplicate(true)
	heavy_run.pday = 8
	heavy_run.t += 7 * 1440
	var deep_run: Dictionary = day_base.duplicate(true)
	deep_run.pday = 12
	deep_run.t += 11 * 1440
	out.append(_check("heavy_derived_from_weather_table",
		bool(A.state_for_run(heavy_run).snow_heavy) and bool(A.state_for_run(deep_run).snow_heavy)
			and not bool(A.state_for_run(run).snow_heavy),
		"pday1=%s pday8=%s pday12=%s" % [
			A.state_for_run(run).snow_heavy, A.state_for_run(heavy_run).snow_heavy,
			A.state_for_run(deep_run).snow_heavy]))

	# 灾后第 0 日（尸劫之夜/次日）：pday=0 时 HomeWorld.set_time 不读 weather 表
	# （State.weather 对 pday0 落到表末项 cold25），state_for_run 必须与之一致——
	# 只有 post 且 pday>0 才允许由 weather/pday 派生大雪，灾后第 0 夜不能凭空变大雪。
	var p0_noon: Dictionary = day_base.duplicate(true)
	p0_noon.pday = 0
	var p0_night: Dictionary = p0_noon.duplicate(true)
	p0_night.t = 1020
	var s_p0_noon: Dictionary = A.state_for_run(p0_noon)
	var s_p0_night: Dictionary = A.state_for_run(p0_night)
	out.append(_check("post_pday0_no_phantom_heavy_snow",
		not bool(s_p0_noon.snow_heavy) and bool(s_p0_noon.damage)
			and not bool(s_p0_night.snow_heavy) and bool(s_p0_night.win_post),
		"灾后 pday0 纯投影 午 %s；夜 %s（须无大雪、旧损在、夜窗灯亮）"
		% [JSON.stringify(s_p0_noon), JSON.stringify(s_p0_night)]))

	# ---- 真实 HomeWorld：灾前 sync 不崩，旧损/加户随阶段显隐 ----
	world.sync(pre_noon)
	var pre_dmg := (amb.get_node("damage") as Node3D).visible
	var pre_smoke_extra := (amb.get_node("smoke_pre") as Node3D).visible
	world.sync(run)
	var post_dmg := (amb.get_node("damage") as Node3D).visible
	var post_smoke_extra := (amb.get_node("smoke_pre") as Node3D).visible
	world.sync(pre_night)
	var pre_win_extra := (amb.get_node("win_pre") as Node3D).visible
	var run_night: Dictionary = run.duplicate(true)
	run_night.t = 1020
	world.sync(run_night)
	var post_win_extra := (amb.get_node("win_pre") as Node3D).visible
	out.append(_check("homeworld_phase_switch",
		not pre_dmg and pre_smoke_extra and post_dmg and not post_smoke_extra
			and pre_win_extra and not post_win_extra,
		"damage 前/后=%s/%s，smoke_pre=%s/%s，win_pre 夜前/后=%s/%s"
		% [pre_dmg, post_dmg, pre_smoke_extra, post_smoke_extra, pre_win_extra, post_win_extra]))

	# 大雪：sync 后收晾晒、显积雪、炊烟仍在；set_preset 沿用缓存大雪上下文
	world.sync(heavy_run)
	var h_laundry := (amb.get_node("laundry") as Node3D).visible
	var h_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	var h_smoke := (amb.get_node("smoke_post") as Node3D).visible
	world.set_preset("noon", 400)
	var hp_laundry := (amb.get_node("laundry") as Node3D).visible
	var hp_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	out.append(_check("homeworld_heavy_snow_switch",
		not h_laundry and h_heavy and h_smoke and not hp_laundry and hp_heavy,
		"大雪 sync 晾晒=%s 积雪=%s 炊烟=%s；preset noon 晾晒=%s 积雪=%s"
		% [h_laundry, h_heavy, h_smoke, hp_laundry, hp_heavy]))

	# 真实 HomeWorld：灾后 pday0 sync 不得显大雪（与 set_time 的 pday>0 守卫一致），
	# 午间晾晒在、夜里窗灯亮；set_preset 沿用的缓存 heavy 也必须为 false。
	world.sync(p0_noon)
	var p0_h_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	var p0_h_laundry := (amb.get_node("laundry") as Node3D).visible
	world.sync(p0_night)
	var p0_hn_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	var p0_hn_win := (amb.get_node("win_post") as Node3D).visible
	world.set_preset("noon", 400)
	var p0_p_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	out.append(_check("homeworld_post_pday0_no_heavy_snow",
		not p0_h_heavy and p0_h_laundry and not p0_hn_heavy and p0_hn_win
			and not p0_p_heavy,
		"灾后 pday0 真实 sync：午 积雪=%s 晾晒=%s；夜 积雪=%s 窗灯=%s；preset 午 积雪=%s"
		% [p0_h_heavy, p0_h_laundry, p0_hn_heavy, p0_hn_win, p0_p_heavy]))

	# 恢复小雪旧局面（正午）
	world.sync(day_base)
	var back_laundry := (amb.get_node("laundry") as Node3D).visible
	var back_heavy := (amb.get_node("snow_heavy") as Node3D).visible
	out.append(_check("recovery_to_small_snow",
		back_laundry and not back_heavy,
		"恢复小雪：晾晒=%s 积雪=%s" % [back_laundry, back_heavy]))

	probe.queue_free()
	return out

## C0 纸窗格：0.35x0.55x0.02 小盒（窗持有者内 ±0.22 处）。
## 返回每片纸窗的世界中心与墙外法向（局部 +Z 朝墙外；全局变换已含房屋/侧窗旋转）。
func _pane_centers(raw_root: Node3D) -> Array:
	var out: Array = []
	var near: Node = raw_root.get_node_or_null("near")
	if near == null:
		return out
	for v in _all_visuals(near):
		if not (v is MeshInstance3D):
			continue
		var mesh: Mesh = (v as MeshInstance3D).mesh
		if mesh is BoxMesh:
			var s: Vector3 = (mesh as BoxMesh).size
			if absf(s.x - 0.35) < 0.02 and absf(s.y - 0.55) < 0.02 and absf(s.z - 0.02) < 0.02:
				var vi := v as VisualInstance3D
				out.append({"c": vi.global_transform * vi.get_aabb().get_center(),
					"n": vi.global_transform.basis.z.normalized()})
	return out


func _group_mesh_centers(root: Node, gname: String) -> Array:
	var out: Array = []
	var g: Node = root.get_node_or_null(gname)
	if g == null:
		return out
	for v in _all_visuals(g):
		var vi := v as VisualInstance3D
		out.append(vi.global_transform * vi.get_aabb().get_center())
	return out


func _lit_house_set(centers: Array) -> Dictionary:
	var set2: Dictionary = {}
	var S = load(SURR_PATH)
	for c in centers:
		var best_i := -1
		var best_d := 1e9
		for i in S.NEAR_HOUSES.size():
			var h: Dictionary = S.NEAR_HOUSES[i]
			var d2 := Vector2(c.x - float(h.x), c.z - float(h.z)).length()
			if d2 < best_d:
				best_d = d2
				best_i = i
		if best_i >= 0 and best_d < 6.0:
			set2[best_i] = true
	return set2


func _house_window_count(i: int) -> int:
	var S = load(SURR_PATH)
	var h: Dictionary = S.NEAR_HOUSES[i]
	var n := 0
	var dc: float = [-0.5, 0.5, 0.0, 0.4][int(h.style)]
	for side in [-1.0, 1.0]:
		if absf(dc + side * 2.3) < float(h.w) / 2.0 - 0.8:
			n += 1
	if int(h.style) >= 2:
		n += 1
	return n


func _side_spread(centers: Array) -> Dictionary:
	var d := {"n": false, "s": false, "w": false, "e": false}
	for c in centers:
		if c.z < -10.0:
			d["n"] = true
		if c.z > 8.0:
			d["s"] = true
		if c.x < -12.0:
			d["w"] = true
		if c.x > 12.0:
			d["e"] = true
	return d


func _count_class(n: Node, cls: String) -> int:
	var c := 0
	if n.is_class(cls):
		c += 1
	for ch in n.get_children():
		c += _count_class(ch, cls)
	return c


func _instance_ids(n: Node) -> Dictionary:
	var d := {n.get_instance_id(): true}
	for c in n.get_children():
		var sub := _instance_ids(c)
		for k in sub:
			d[k] = true
	return d


# ---------- 切片 5：纯视觉隔离 / 重建一致 / RNG·局面·NPC 无关 / 净空 ----------

func _slice_isolation(world: Node3D, run: Dictionary, A, S, amb: Node3D) -> Array:
	var out: Array = []
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var raw_amb: Node3D = raw.get_node_or_null("ambience")

	# 禁用节点：碰撞 / 导航 / 灯光 / 音频 / 粒子 / 挂脚本（杜绝常驻 _process / 交互）/ spot 元数据。
	# 合并与未合并两棵树都扫。
	var forbidden_classes := ["CollisionObject3D", "NavigationRegion3D", "Light3D",
		"AudioStreamPlayer", "AudioStreamPlayer3D", "GPUParticles3D", "CPUParticles3D"]
	var scan := func(root: Node) -> Array:
		var found: Array = []
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for cls in forbidden_classes:
				if n.is_class(cls):
					found.append("%s:%s" % [n.name, cls])
			if n is Node and n.has_meta("spot"):
				found.append("%s:meta:spot" % n.name)
			if n.get_script() != null:
				found.append("%s:script" % n.name)
			for c in n.get_children():
				stack.append(c)
		return found
	var bad_raw: Array = scan.call(raw_amb)
	var bad_prod: Array = scan.call(amb)
	out.append(_check("ambience_no_forbidden_nodes",
		bad_raw.is_empty() and bad_prod.is_empty(),
		"未合并树发现 %s；生产树发现 %s" % [bad_raw.slice(0, 6), bad_prod.slice(0, 6)]))

	# 核心/迎战通道净空：完整旋转变换 AABB；高于 0.5m 的构件一律不得进核心 footprint
	# （|x|<10.2, z[-8.2,7]）或门前迎战通道（|x|<=3, z[7.5,17]）。贴地贴片（雪痕/雪包）豁免。
	var intrude_core: Array = []
	var intrude_lane: Array = []
	for gname in A.GROUPS:
		for b in _world_aabbs(raw_amb, str(gname)):
			if b.top <= 0.5:
				continue
			if absf(b.center.x) < 10.2 and b.center.z > -8.2 and b.center.z < 7.0:
				intrude_core.append("%s@%s" % [gname, b.center.snapped(Vector3.ONE * 0.1)])
			if absf(b.center.x) <= 3.0 and b.center.z >= 7.5 and b.center.z <= 17.0:
				intrude_lane.append("%s@%s" % [gname, b.center.snapped(Vector3.ONE * 0.1)])
	out.append(_check("ambience_core_lane_clearance",
		intrude_core.is_empty() and intrude_lane.is_empty(),
		"侵核心 %d：%s；侵通道 %d：%s"
		% [intrude_core.size(), intrude_core.slice(0, 4), intrude_lane.size(), intrude_lane.slice(0, 4)]))

	# 投影只含 GROUPS 布尔键，JSON 读回等价。
	var states: Array = [
		A.project("post", 1, 720, false), A.project("post", 8, 1380, true),
		A.project("pre", 0, 100, false), A.state_for_run(run)]
	var json_bad := 0
	var key_bad := 0
	for st in states:
		var back: Variant = JSON.parse_string(JSON.stringify(st))
		if not (back is Dictionary and back == st):
			json_bad += 1
		if st.keys().size() != A.GROUPS.size():
			key_bad += 1
		for k in st:
			if not A.GROUPS.has(k) or typeof(st[k]) != TYPE_BOOL:
				key_bad += 1
	out.append(_check("projection_bool_keys_json_roundtrip",
		json_bad == 0 and key_bad == 0,
		"JSON 不等价 %d，键/类型问题 %d" % [json_bad, key_bad]))

	# replace 重建后同 run 投影可重复：新树 apply 同状态，显隐向量一致；同状态早退且不增节点。
	var st_post: Dictionary = A.state_for_run(run)
	var rebuilt1: Node3D = S.replace(probe, raw, {})
	var amb1: Node3D = rebuilt1.get_node("ambience")
	A.apply(amb1, st_post)
	var vis1 := _group_vis(amb1, A)
	var n_before := _count_nodes(amb1)
	var changed_same: bool = A.apply(amb1, st_post)
	var rebuilt2: Node3D = S.replace(probe, rebuilt1, {})
	var amb2: Node3D = rebuilt2.get_node("ambience")
	A.apply(amb2, st_post)
	var vis2 := _group_vis(amb2, A)
	out.append(_check("replace_rebuild_sync_repeatable",
		vis1 == vis2 and not changed_same and _count_nodes(amb1) == n_before
			and A.current_state(amb2) == st_post,
		"重建间显隐一致=%s，同状态返回 false=%s，节点 %d→%d"
		% [vis1 == vis2, not changed_same, n_before, _count_nodes(amb1)]))

	# 全状态矩阵（pre/post × 午/夜 × 小雪/大雪 → 恢复）来回切：amb 与 C0 三层节点 id/数量不动。
	var noon: Dictionary = run.duplicate(true)
	noon.t = 360
	var night_run: Dictionary = run.duplicate(true)
	night_run.t = 1020
	var pre_noon := State.new_run("scholar", State.new_meta(), FIXED_SEED)
	pre_noon.t = 360
	var heavy: Dictionary = noon.duplicate(true)
	heavy.pday = 8
	heavy.t += 7 * 1440
	var amb_ids0 := _instance_ids(amb)
	var layer_ids0 := {}
	for ln in ["near", "middle", "far"]:
		layer_ids0[ln] = _instance_ids(world.surroundings.get_node(ln))
	for cycle in 2:
		for r0 in [noon, pre_noon, heavy, night_run]:
			world.sync(r0)
		world.set_preset("night", 400)
		world.set_preset("noon", 400)
	var ids_ok := _instance_ids(amb) == amb_ids0
	var layers_ok := true
	for ln in ["near", "middle", "far"]:
		if _instance_ids(world.surroundings.get_node(ln)) != layer_ids0[ln]:
			layers_ok = false
	out.append(_check("full_matrix_switch_no_rebuild",
		ids_ok and layers_ok,
		"全矩阵切换后 amb id 不变=%s，C0 near/middle/far id 不变=%s" % [ids_ok, layers_ok]))

	# NPC / 邻居生死迁居任务、核心 broken/wreck 与背景无绑定：投影与显隐必须完全一致。
	var npc_run: Dictionary = run.duplicate(true)
	npc_run["npcs"] = {"widow": {"dead": true}, "smith": {"relocated": true}}
	npc_run["neighbors"] = [{"id": 4, "dead": true, "moved": true}, {"id": 8, "quest": "gone"}]
	npc_run["dead_npcs"] = ["widow", "smith", "clerk"]
	npc_run["broken"] = ["stove", "bench", "gate"]
	npc_run["wreck"] = {"well": true}
	npc_run["quests"] = {"q_neighbor": 2}
	var npc_bad := 0
	for r1 in [run, noon, night_run, heavy]:
		var a: Dictionary = A.state_for_run(r1)
		var mut: Dictionary = r1.duplicate(true)
		mut["npcs"] = npc_run.npcs
		mut["neighbors"] = npc_run.neighbors
		mut["dead_npcs"] = npc_run.dead_npcs
		mut["broken"] = npc_run.broken
		mut["wreck"] = npc_run.wreck
		if A.state_for_run(mut) != a:
			npc_bad += 1
	world.sync(npc_run)
	var npc_vis := _group_vis(amb, A)
	world.sync(run)
	var clean_vis := _group_vis(amb, A)
	out.append(_check("npc_and_core_wreck_state_ignored",
		npc_bad == 0 and npc_vis == clean_vis,
		"投影受 NPC/核心损失影响次数 %d，显隐向量一致=%s" % [npc_bad, npc_vis == clean_vis]))

	# 不写 run / Game.run，不消耗全局 RNG。
	var run_hash0 := JSON.stringify(run).hash()
	seed(424242)
	randi(); randi()
	for r2 in [run, noon, night_run, heavy, pre_noon, npc_run]:
		A.state_for_run(r2)
		A.apply(amb, A.state_for_run(r2))
	world.sync(run)
	var run_hash1 := JSON.stringify(run).hash()
	var rng_b := [randi(), randi()]
	seed(424242)
	randi(); randi()
	var rng_expect := [randi(), randi()]
	out.append(_check("no_run_write_no_rng_consumption_no_game_run",
		run_hash0 == run_hash1 and rng_b == rng_expect and Game.run.is_empty(),
		"run_hash %s→%s，rng %s vs %s，Game.run empty=%s"
		% [run_hash0, run_hash1, rng_b, rng_expect, Game.run.is_empty()]))

	probe.queue_free()
	return out


func _group_vis(root: Node3D, A) -> Array:
	var out: Array = []
	for gname in A.GROUPS:
		var g: Node = root.get_node_or_null(str(gname))
		out.append(g != null and (g as Node3D).visible)
	return out

# ---------- 真窗口截图矩阵：24 状态，全部站在玩家真实可达的院内机位 ----------
#
# 机位事实（经父代理真窗口探针 legal-view-probe 实测，不沿用任何名单式假合法）：
#   * HomeWorld.pick 的院内点击矩形是 |x|<10、-8<z<GATE_Z-0.3=6.7、y<.3；
#     导航网格也只烘焙核心 AABB（x[-10.5,10.5], z[-8.5,7.5]）。旧矩阵的
#     s9/s10/se0/n4/n13 全在院外，既点不到也走不到——已全部删除。
#   * 六个焦点每个都在捕获/契约时用「pick 矩形 + NavigationServer3D 真实
#     寻路（map_get_path / map_get_closest_point，XZ 误差<.15）」复验。
#   * CamRig 朝向（以源码为准，不沿用旧注释）：offset=(0,0,dist) 先绕 X 按
#     pitch 再绕 Y 按 yaw 旋转。yaw0 相机在 +Z 侧向 -Z（北）看；yaw180 看南；
#     yaw+90 相机在 +X 侧向 -X（西）看；yaw-90 在 -X 侧向 +X（东）看。
#   * pitch∈[-80,-20]、dist∈[7,26]、fov42、sky/fog 一律不动。
#
# 窗灯证据不再用「全图夜暖色>午」这种自家灯笼也能满足的弱代理：north_inner
# 同机位同预设做 on/off 消融（off 是 QA 显式关灯，非自然世界状态，清单明示）。
#
# pre 仅小雪（大雪按天气表 pday6+ 只属于 post）；pre 对照是隔离场景能力验证，
# 不代表灾前宅院入口。
const C1_SHOTS: Array[Dictionary] = [
	# 灾后·小雪 15：court 午间四向 + 夜间正面（5，与 C0 同性能机位同条件）；
	# 南西/南东内院站位（yaw180 看南排邻宅）、北内院站位 noon/dusk/night_on/night_off、
	# 西/东内院站位；南东与北各一条 pitch=-20 最低俯角端点。
	{"file": "ps_noon_front", "focus": "court", "phase": "post", "snow": "small", "preset": "noon", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ps_noon_back", "focus": "court", "phase": "post", "snow": "small", "preset": "noon", "yaw": 180.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ps_noon_left", "focus": "court", "phase": "post", "snow": "small", "preset": "noon", "yaw": -90.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ps_noon_right", "focus": "court", "phase": "post", "snow": "small", "preset": "noon", "yaw": 90.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ps_night_front", "focus": "court", "phase": "post", "snow": "small", "preset": "night", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ps_noon_south_w", "focus": "south_w_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 180.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ps_noon_south_e", "focus": "south_e_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 180.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ps_noon_north", "focus": "north_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	{"file": "ps_dusk_north", "focus": "north_inner", "phase": "post", "snow": "small", "preset": "dusk", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	{"file": "ps_night_north_on", "focus": "north_inner", "phase": "post", "snow": "small", "preset": "night", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	# QA 消融臂：与 on 完全同机位同夜空，仅人工关窗灯；不是自然世界状态。
	{"file": "ps_night_north_off", "focus": "north_inner", "phase": "post", "snow": "small", "preset": "night", "yaw": 0.0, "pitch": -50.0, "dist": 26.0, "qa_win_off": true},
	{"file": "ps_noon_west", "focus": "west_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 90.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ps_noon_east", "focus": "east_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": -90.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ps_low_south_e", "focus": "south_e_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 180.0, "pitch": -20.0, "dist": 26.0},
	{"file": "ps_low_north", "focus": "north_inner", "phase": "post", "snow": "small", "preset": "noon", "yaw": 0.0, "pitch": -20.0, "dist": 26.0},
	# 灾后·大雪 6：南两站位、北站位与 court 前向昼夜对照，北站位血月。
	{"file": "ph_noon_south_w", "focus": "south_w_inner", "phase": "post", "snow": "heavy", "preset": "noon", "yaw": 180.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ph_noon_south_e", "focus": "south_e_inner", "phase": "post", "snow": "heavy", "preset": "noon", "yaw": 180.0, "pitch": -40.0, "dist": 26.0},
	{"file": "ph_noon_north", "focus": "north_inner", "phase": "post", "snow": "heavy", "preset": "noon", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	{"file": "ph_noon_court", "focus": "court", "phase": "post", "snow": "heavy", "preset": "noon", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ph_night_court", "focus": "court", "phase": "post", "snow": "heavy", "preset": "night", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "ph_blood_north", "focus": "north_inner", "phase": "post", "snow": "heavy", "preset": "blood", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	# 灾前·小雪 3（隔离场景能力对照，不代表灾前宅院入口）。
	{"file": "pre_noon_south_w", "focus": "south_w_inner", "phase": "pre", "snow": "small", "preset": "noon", "yaw": 180.0, "pitch": -40.0, "dist": 26.0},
	{"file": "pre_noon_north", "focus": "north_inner", "phase": "pre", "snow": "small", "preset": "noon", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	{"file": "pre_night_north", "focus": "north_inner", "phase": "pre", "snow": "small", "preset": "night", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
]
## 六个合法焦点：全部在 pick 院内矩形内、且在真实烘焙导航网格上（XZ<.15）。
## north_inner 在北正屋台基前院内；south_* 门内两侧；west/east 厢房南角院地。
const C1_FOCI := {
	"court": Vector3(0.0, 0.0, 0.0),
	"north_inner": Vector3(-0.8, 0.0, -5.5),
	"south_w_inner": Vector3(-6.2, 0.0, 6.0),
	"south_e_inner": Vector3(6.2, 0.0, 6.0),
	"west_inner": Vector3(-8.0, 0.0, 4.5),
	"east_inner": Vector3(8.0, 0.0, 4.5),
}
const C1_NAV_TOL := 0.15

var _fixture_run_cached: Dictionary = {}
var _shot_runs: Dictionary = {}
var _focus_nodes: Dictionary = {}
var _default_focus: Node3D = null
var _active_focus := "court"
var _rig_cache: Node = null
var _capture_player: Node = null
var _legality_cache: Dictionary = {}
var _rig_refs: Dictionary = {}
var _roofs_settled_last := false


func _shot_plan() -> Array:
	return C1_SHOTS


func _manifest_kind() -> String:
	return "courtyard_c1_ambience_shots"


func _perf_kind() -> String:
	return "courtyard_c1_ambience_perf"


# ---------- 机位合法性：pick 矩形 + 真实导航（headless 契约与窗口矩阵共用） ----------

## 对每个焦点实测：pick 院内矩形、closest_point XZ 误差、从 SPAWN 的真实寻路。
## 不看名字白名单；判定全在 XZ 平面（导航网格地面有固定 Y 偏移，3D 距离会假失败）。
func _probe_foci(world: Node3D) -> Dictionary:
	if not _legality_cache.is_empty():
		return _legality_cache
	var map_rid: RID = world.get_world_3d().navigation_map
	var spawn: Vector3 = HomeWorld.SPAWN
	for key in C1_FOCI:
		var p: Vector3 = C1_FOCI[key]
		var pick_ok: bool = p.y < 0.3 and absf(p.x) < 10.0 \
				and p.z > -8.0 and p.z < float(world.GATE_Z) - 0.3
		var closest_err := -1.0
		var end_err := -1.0
		var path_n := 0
		# RID 在首次地图同步前就已有效，但 map_get_iteration_id 仍为 0；此刻
		# 查询会触发 NavigationServer "query made before first map
		# synchronization" ERROR。故要求 iteration_id > 0（至少同步过一次）；
		# and 短路保证无效 RID 不会传入查询，查询该 ID 本身无副作用。
		var map_ok := map_rid.is_valid() \
				and NavigationServer3D.map_get_iteration_id(map_rid) > 0
		if map_ok:
			var cp: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, p)
			closest_err = Vector2(cp.x - p.x, cp.z - p.z).length()
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, spawn, p, true)
			path_n = path.size()
			if path_n > 0:
				var e: Vector3 = path[path_n - 1]
				end_err = Vector2(e.x - p.x, e.z - p.z).length()
		var reachable: bool = pick_ok and map_ok and closest_err >= 0.0 and closest_err < C1_NAV_TOL \
				and path_n >= 2 and end_err >= 0.0 and end_err < C1_NAV_TOL
		_legality_cache[key] = {
			"pick_ok": pick_ok, "map_ok": map_ok,
			"nav_closest_err": closest_err, "nav_path_points": path_n,
			"nav_path_end_err": end_err, "reachable": reachable,
		}
	return _legality_cache


## headless 契约：矩阵形状、六焦点真实可达、消融臂同机位、相机/雾边界未被改动。
func _slice_camera_legal(world: Node3D) -> Array:
	var out: Array = []
	var leg := _probe_foci(world)
	var details: Array = []
	var bad := 0
	for key in ["court", "north_inner", "south_w_inner", "south_e_inner", "west_inner", "east_inner"]:
		var L: Dictionary = leg.get(key, {})
		var ok: bool = bool(L.get("reachable", false))
		if not ok:
			bad += 1
		details.append("%s=%s(pick=%s map=%s close=%.3f pts=%d end=%.3f)" % [
			key, ok, L.get("pick_ok"), L.get("map_ok"),
			float(L.get("nav_closest_err", -1.0)), int(L.get("nav_path_points", 0)),
			float(L.get("nav_path_end_err", -1.0))])
	print("%s 六焦点 pick+NavigationServer 实测：%s" % [LOG_PREFIX_AMB, "；".join(details)])
	out.append(_check("c1_foci_player_reachable", bad == 0 and leg.size() == 6,
		"六焦点均须在 pick 矩形内且 NavigationServer 寻路 XZ<%.2f：%s"
		% [C1_NAV_TOL, "；".join(details)]))

	var shape_bad := 0
	var foci_used: Dictionary = {}
	var on_shot: Dictionary = {}
	var off_shot: Dictionary = {}
	for shot in C1_SHOTS:
		var fname := str(shot.file)
		if not C1_FOCI.has(str(shot.focus)):
			shape_bad += 1
		foci_used[str(shot.focus)] = true
		if shot.has("fov") or float(shot.pitch) < -80.0 or float(shot.pitch) > -20.0 \
				or float(shot.dist) < 7.0 or float(shot.dist) > 26.0:
			print("%s 违反相机边界：pitch=%s dist=%s fov=%s" % [fname, shot.pitch, shot.dist, shot.get("fov")])
			shape_bad += 1
		for k in ["phase", "snow", "preset", "yaw"]:
			if not shot.has(k):
				shape_bad += 1
		if fname == "ps_night_north_on":
			on_shot = shot
		elif fname == "ps_night_north_off":
			off_shot = shot
	out.append(_check("c1_shot_matrix_shape",
		C1_SHOTS.size() == 24 and shape_bad == 0 and foci_used.size() == 6,
		"矩阵 %d 张，形状违规 %d，焦点 %d 类（%s）；须 24 张、六焦点齐、pitch/dist 不出界、不改 fov"
		% [C1_SHOTS.size(), shape_bad, foci_used.size(), "/".join(foci_used.keys())]))

	var pair_ok: bool = not on_shot.is_empty() and not off_shot.is_empty() \
			and bool(off_shot.get("qa_win_off", false)) and not bool(on_shot.get("qa_win_off", false))
	for k in ["focus", "phase", "snow", "preset", "yaw", "pitch", "dist"]:
		if on_shot.get(k) != off_shot.get(k):
			pair_ok = false
	out.append(_check("c1_night_window_ablation_pair", pair_ok,
		"north 夜窗 on/off 必须同机位同局面，off 须显式 qa_win_off：on=%s off=%s"
		% [JSON.stringify(on_shot), JSON.stringify(off_shot)]))

	out.append(_check("c1_camera_fog_bounds_untouched",
		absf(float(world.sky.fog_mul) - 0.12) < 0.001,
		"world.sky.fog_mul=%.3f（须保持 C0 的 0.12）" % float(world.sky.fog_mul)))
	return out


# ---------- 真窗口捕获钩子 ----------

## 真窗口捕获前准备三种局面：灾后小雪（夹具）、灾后大雪（pday8）、灾前。
func _prepare_capture(world: Node3D) -> void:
	var small: Dictionary = _fixture_run_cached if not _fixture_run_cached.is_empty() else _fixture_run()
	small.t = 360
	var heavy: Dictionary = small.duplicate(true)
	heavy.pday = 8
	heavy.t += 7 * 1440
	var pre := State.new_run("scholar", State.new_meta(), FIXED_SEED)
	pre.t = 360
	_shot_runs = {"post_small": small, "post_heavy": heavy, "pre_small": pre}
	_focus_nodes.clear()
	for key in C1_FOCI:
		if key == "court":
			continue
		var fn := Node3D.new()
		fn.position = C1_FOCI[key]
		world.add_child(fn)
		_focus_nodes[key] = fn
	_active_focus = "court"
	_capture_player = null
	_rig_cache = null
	_legality_cache.clear()
	_rig_refs.clear()


## 每机位：真实 sync 局面 + 天空预设；把基类创建的真实 PlayerScript 移到该焦点，
## 调真实 world.update_roofs 到稳定（玩家在屋檐下时屋顶淡化，是原功能，不改材质规则）；
## QA 消融臂在自然投影之后用 apply 显式关窗灯（复制缓存状态，保持缓存一致）。
func _prepare_shot(world: Node3D, shot: Dictionary) -> void:
	_active_focus = str(shot.get("focus", "court"))
	var key := "%s_%s" % [str(shot.phase), str(shot.snow)]
	var r: Dictionary = _shot_runs.get(key, _fixture_run_cached)
	world.sync(r)
	# 天空雪量按天气表：小雪 cold10=550，大雪 cold20=850；amb 投影由 sync 缓存的 ctx 决定。
	var snow_amount := 850 if str(shot.snow) == "heavy" else 550
	world.set_preset(str(shot.preset), snow_amount)
	var focus_pos: Vector3 = C1_FOCI.get(_active_focus, Vector3.ZERO)
	var player := _find_player(world)
	_roofs_settled_last = false
	if player != null:
		player.global_position = focus_pos
		# 玩家在屋内（north_inner 贴近北正屋）时淡化屋顶；迭代真实 lerp 到稳定。
		# 穿墙/瞬移由导航合法性把关，这里不改任何材质规则。
		var prev: Array = _roof_alpha_snapshot(world)
		for i in 200:
			world.update_roofs(focus_pos)
			var cur: Array = _roof_alpha_snapshot(world)
			var maxd := 0.0
			for j in cur.size():
				maxd = maxf(maxd, absf(float(cur[j]) - float(prev[j])))
			prev = cur
			if maxd < 0.001:
				_roofs_settled_last = true
				break
	if bool(shot.get("qa_win_off", false)):
		var A = load(AMBIENCE_PATH)
		var amb: Node = world.surroundings.get_node_or_null("ambience")
		if A != null and amb != null:
			# 显式 QA 覆盖：从真实缓存状态复制，只关窗灯；下一机位自然 sync/preset 会恢复。
			var forced: Dictionary = A.current_state(amb).duplicate(true)
			forced["win_post"] = false
			forced["win_pre"] = false
			A.apply(amb, forced)


func _find_player(world: Node3D) -> Node:
	if _capture_player != null and is_instance_valid(_capture_player):
		return _capture_player
	for c in world.get_children():
		if c.get_script() == PlayerScript:
			_capture_player = c
			return c
	return null


func _roof_alpha_snapshot(world: Node3D) -> Array:
	var a: Array = []
	for h in world.halls:
		for m in h.fade_mats:
			a.append(float(m.albedo_color.a))
	return a


## 基类机位应用前换焦点（性能段不传 shot，_active_focus=court，与 C0 同机位）。
func _apply_view(rig, yaw_deg: float, pitch: float, dist: float) -> void:
	_rig_cache = rig
	var target: Node3D = _default_focus
	if _active_focus != "court" and _focus_nodes.has(_active_focus):
		target = _focus_nodes[_active_focus]
	if target != null:
		rig.set("target", target)
	super(rig, yaw_deg, pitch, dist)
	if _default_focus == null:
		_default_focus = rig.get("target") if _active_focus == "court" else _default_focus


## 每机位置记：真实 8 小组 .visible（不抄缓存 meta）、真实导航合法性、
## 真实 rig 目标/相机位置（公式与实例并记）、消融臂标记、真实像素诊断。
func _shot_metadata(world: Node3D, shot: Dictionary, img: Image = null) -> Dictionary:
	var A = load(AMBIENCE_PATH)
	var focus_name := str(shot.get("focus", "court"))
	var focus_pos: Vector3 = C1_FOCI.get(focus_name, Vector3.ZERO)
	# amb_state 必须从真实小组 .visible 读取（QA 关窗后与自然投影不同，照实记）。
	var amb_state: Dictionary = {}
	var amb: Node = world.surroundings.get_node_or_null("ambience")
	if amb != null and A != null:
		for gname in A.GROUPS:
			var g: Node = amb.get_node_or_null(str(gname))
			amb_state[str(gname)] = g != null and (g as Node3D).visible
	var leg: Dictionary = _probe_foci(world).get(focus_name, {})
	var yaw_f := float(shot.yaw)
	var pitch_f := float(shot.pitch)
	var dist_f := float(shot.dist)
	var cam_formula: Vector3 = focus_pos + Vector3(0.0, 1.0, 0.0) \
			+ Vector3(0.0, 0.0, dist_f).rotated(Vector3.RIGHT, deg_to_rad(pitch_f)) \
				.rotated(Vector3.UP, deg_to_rad(yaw_f))
	var cam_actual: Vector3 = cam_formula
	var cam_available := false
	var target_actual: Array = []
	if _rig_cache != null:
		var t = _rig_cache.get("target")
		if t is Node3D:
			var tp: Vector3 = (t as Node3D).global_position
			target_actual = [tp.x, tp.y, tp.z]
		var c = _rig_cache.get("cam")
		if c is Camera3D:
			cam_available = true
			cam_actual = (c as Camera3D).global_position
	var meta := {
		"c1_phase": str(shot.phase),
		"c1_snow": str(shot.snow),
		"c1_focus": focus_name,
		"focus_valid": bool(leg.get("reachable", false)),
		"focus_pick_ok": bool(leg.get("pick_ok", false)),
		"focus_nav_closest_err": float(leg.get("nav_closest_err", -1.0)),
		"focus_nav_path_points": int(leg.get("nav_path_points", 0)),
		"focus_nav_path_end_err": float(leg.get("nav_path_end_err", -1.0)),
		"focus_xyz": [focus_pos.x, focus_pos.y, focus_pos.z],
		"rig_target_xyz": target_actual,
		"cam_xyz": [cam_actual.x, cam_actual.y, cam_actual.z],
		"cam_xyz_formula": [cam_formula.x, cam_formula.y, cam_formula.z],
		"cam_actual_available": cam_available,
		"roofs_settled": _roofs_settled_last,
		"amb_state": amb_state,
	}
	# 消融标记：on 为自然状态，off 明确标注 QA 人工关灯，禁止把 off 当自然世界状态。
	if str(shot.file) == "ps_night_north_on":
		meta["ablation"] = {"id": "north_windows", "arm": "on", "natural": true,
			"pair": "ps_night_north_off.png"}
	elif str(shot.file) == "ps_night_north_off":
		meta["ablation"] = {"id": "north_windows", "arm": "off", "natural": false,
			"override": "qa_force_win_post_pre_off", "pair": "ps_night_north_on.png"}
	if img != null:
		var diag := _image_diag(img)
		for k in diag:
			meta[k] = diag[k]
		# 同机位首帧（小雪正午）参照：大雪/灾前/消融的 whole-frame 差异只作如实记录，
		# 验证器不设视角依赖阈值；结构契约 + 消融像素差 + 父目视才是判据。
		var rkey := "%s|%.0f|%.0f|%.0f" % [focus_name, yaw_f, pitch_f, dist_f]
		var cur := img.duplicate()
		cur.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		if _rig_refs.has(rkey):
			meta["diff_vs_first_frac"] = _lum_diff(_rig_refs[rkey], cur)
		else:
			_rig_refs[rkey] = cur
	return meta


## 步长 4 采样：warm=窗灯暖色像素，lum=平均亮度，white=雪白占比。全部来自刚截到的真实帧。
## （Python 证据验证器用同样步长/阈值从磁盘 PNG 重算，manifest 数字必须对得上像素。）
func _image_diag(img: Image) -> Dictionary:
	var warm := 0
	var white := 0
	var lum_sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			var r8 := int(c.r * 255.0)
			var g8 := int(c.g * 255.0)
			var b8 := int(c.b * 255.0)
			lum_sum += (0.3 * c.r + 0.59 * c.g + 0.11 * c.b)
			if r8 > 110 and r8 - b8 > 45 and r8 - g8 > 15:
				warm += 1
			if r8 > 200 and g8 > 200 and b8 > 200:
				white += 1
			n += 1
	return {"warm_frac": float(warm) / float(n), "lum_mean": lum_sum / float(n),
		"white_frac": float(white) / float(n), "diag_samples": n}


func _lum_diff(a: Image, b: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, 90, 2):
		for x in range(0, 160, 2):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			sum += absf((0.3 * ca.r + 0.59 * ca.g + 0.11 * ca.b)
				- (0.3 * cb.r + 0.59 * cb.g + 0.11 * cb.b))
			n += 1
	return sum / float(n)
