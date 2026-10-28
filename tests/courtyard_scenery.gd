extends Node3D
## C0 任务1：宅院「四周景物」契约测试 / 截图 / 性能一体脚手架。
##
## 三种跑法（用户参数一律放在 `--` 之后，用 OS.get_cmdline_user_args() 读取）：
##
## 1) 无头契约测试（默认，快速、有限，契约失败退出码非 0）：
##      godot --headless --path <项目> res://tests/courtyard_scenery.tscn
##    直接构造 HomeWorld + 固定种子局面（不经过 HUD / 不联网 / 不读写玩家存档）。
##    契约：HomeWorld 下存在视觉隔离的 "surroundings"（近/中/远三层，层内合并、
##    无碰撞/无导航/无灯光/无 spot），四正四隅八方位都有真实网格，重复构建签名一致，
##    toggle/rebuild 不改 Game.run / 局面 / 全局 RNG，缺配置有兜底。
##
## 2) 真窗口截图（--label=before|after 标记证据归属；同一机位/雾/夹具才可比）：
##      godot --path <项目> res://tests/courtyard_scenery.tscn -- \
##          --baseline --label=after --shots=<user:// 或原生绝对目录>
##          [--perf=<user:// 或原生绝对.json>]
##          [--resolution=1920x1080] [--trials=3] [--samples=240] [--quick]
##    固定机位矩阵：前/后/左/右/对角 × 默认/广角/低俯/顶视，预设 noon/dusk/night/blood。
##    保留现网雾（sky.fog_mul=0.12）与 CamRig 现行俯仰/距离限制。
##    无头模式下 --baseline 立即有限失败（不等待绘制、不挂死）。
##
## 3) 性能（随 --baseline，真窗口）：关 vsync（查询实际模式，无法关闭即失败）、
##    Engine.max_fps=0，预热后测真实帧间隔，输出中位/p95、draw calls / 对象数 /
##    节点数（总数与 world 子树分别标注）；截图与写盘帧不计入。
##
## 所有模式结尾都打印 `[COURTYARD_SCENERY] COMPLETE code=<n>`；中途异常退出不会有
## 这行，启动器据此防止「函数中断但计数看起来成功」。写盘/校验任何失败退出码非 0。

const HomeWorld = preload("res://scripts/world/home_world.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")
const PlayerScript = preload("res://scripts/world/player.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Inv = preload("res://scripts/core/inv.gd")

## 运行期加载：生产模块未交付时 load() 得到 null，契约以「特性缺失」失败（RED），
## 而不是整个测试脚本编译失败。
const SURR_PATH := "res://scripts/world/home_surroundings.gd"

const FIXED_SEED := 20261026
const LOG_PREFIX := "[COURTYARD_SCENERY]"
const SETUP_TOTAL := 4
const LAYER_NAMES: Array[String] = ["near", "middle", "far"]
const BAND_RADIUS := {"near": [10.0, 35.0], "middle": [30.0, 58.0], "far": [58.0, 180.0]}
const ANCHOR_NEAR_MAX := 6.0
const ANCHOR_MID_MAX := 9.0
const ANCHOR_FAR_MAX := 14.0

## 前 12 张与旧 before 同机位；后 4 张补测实际俯仰/距离端点，无旧 before 对照。
const SHOTS: Array[Dictionary] = [
	{"file": "noon_front", "preset": "noon", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "dusk_front", "preset": "dusk", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "night_front", "preset": "night", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "blood_front", "preset": "blood", "yaw": 0.0, "pitch": -54.0, "dist": 17.0},
	{"file": "noon_back", "preset": "noon", "yaw": 180.0, "pitch": -54.0, "dist": 17.0},
	{"file": "noon_left", "preset": "noon", "yaw": -90.0, "pitch": -54.0, "dist": 17.0},
	{"file": "noon_right", "preset": "noon", "yaw": 90.0, "pitch": -54.0, "dist": 17.0},
	{"file": "noon_diag", "preset": "noon", "yaw": -45.0, "pitch": -54.0, "dist": 19.0},
	{"file": "noon_front_wide", "preset": "noon", "yaw": 0.0, "pitch": -50.0, "dist": 26.0},
	{"file": "noon_front_low", "preset": "noon", "yaw": 0.0, "pitch": -24.0, "dist": 13.0},
	{"file": "noon_front_over", "preset": "noon", "yaw": 0.0, "pitch": -78.0, "dist": 25.0},
	{"file": "blood_diag", "preset": "blood", "yaw": -45.0, "pitch": -54.0, "dist": 19.0},
	{"file": "noon_boundary_front", "preset": "noon", "yaw": 0.0, "pitch": -20.0, "dist": 26.0},
	{"file": "noon_boundary_right", "preset": "noon", "yaw": 90.0, "pitch": -20.0, "dist": 26.0},
	{"file": "noon_boundary_back", "preset": "noon", "yaw": 180.0, "pitch": -20.0, "dist": 26.0},
	{"file": "noon_boundary_left", "preset": "noon", "yaw": -90.0, "pitch": -20.0, "dist": 26.0},
]


func _ready() -> void:
	# 兜底隔离：Game 自动加载的 _ready 比本场景更早（读 meta），真正的隔离靠启动器
	# 替换 APPDATA；这里保证本进程绝不写玩家存档 / 根 Memory.md。
	Game.no_save = true
	var pid := OS.get_process_id()
	Game.save_path = "user://c0-scenery-save-%d.json" % pid
	Game.meta_path = "user://c0-scenery-meta-%d.json" % pid
	Game.memory_path = "user://c0-scenery-Memory-%d.md" % pid
	Game.run = {}
	Game.meta = State.new_meta()

	var opts := _parse_args(OS.get_cmdline_user_args())
	if opts.has("help"):
		_print_usage()
		_finish(0)
		return
	var verr := _validate_opts(opts)
	if verr != "":
		print("%s 参数错误：%s" % [LOG_PREFIX, verr])
		_finish(3)
		return
	if bool(opts.baseline) and DisplayServer.get_name() == "headless":
		# 无头没有可绘制窗口：必须有限失败，不能 await frame_post_draw 挂死。
		print("%s --baseline 需要真窗口（当前 DisplayServer=headless），有限失败" % LOG_PREFIX)
		_finish(5)
		return

	var setup_steps := 0
	var world = HomeWorld.new() # 无类型声明：要调 HomeWorld 自定义方法
	add_child(world)
	await get_tree().process_frame
	setup_steps += 1  # 1. HomeWorld 构造（含静态几何合并 + 四周景物）

	var run := _fixture_run()
	if run.is_empty() or str(run.get("phase", "")) != "post":
		push_error("fixture run 构造失败")
		print("%s setup %d/%d：fixture run 不可用，中止" % [LOG_PREFIX, setup_steps, SETUP_TOTAL])
		_finish(3)
		return
	setup_steps += 1  # 2. 确定性局面

	world.sync(run)
	await get_tree().process_frame
	setup_steps += 1  # 3. sync 成功（存货 / 菜畦 / 导航烘焙）

	var node_total := _count_nodes(self)
	var world_nodes := _count_nodes(world)
	setup_steps += 1  # 4. 场景树统计

	var checks: Array = await _contract(world, run)
	if checks.is_empty():
		# 契约函数中途异常会返回空数组，绝不能 0/0 假绿。
		push_error("契约未产出任何检查项（函数可能中途中断）")
		_finish(1)
		return
	var passed := 0
	for c in checks:
		if bool(c.ok):
			passed += 1
		else:
			print("%s CHECK FAIL %s：%s" % [LOG_PREFIX, c.name, c.detail])
	print("%s setup %d/%d（节点：本场景子树 %d，world 子树 %d）" %
		[LOG_PREFIX, setup_steps, SETUP_TOTAL, node_total, world_nodes])
	print("%s checks=%d passed=%d failed=%d" % [LOG_PREFIX, checks.size(), passed, checks.size() - passed])

	if not bool(opts.baseline):
		_finish(0 if passed == checks.size() else 1)
		return

	# ---------- 真窗口截图 / 性能 ----------
	var code := await _run_baseline(world, opts, node_total, world_nodes)
	_finish(code)


## 结束前的唯一出口：完成标记携带真实退出码。
func _finish(code: int) -> void:
	print("%s COMPLETE code=%d" % [LOG_PREFIX, code])
	get_tree().quit(code)


## 固定种子的 scholar 局面：备劫三日直接结束 → 灾后第一日。
func _fixture_run() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), FIXED_SEED)
	Pre.end_day(run)
	Pre.end_day(run)
	Pre.end_day(run)
	if str(run.get("phase", "")) != "post":
		return {}
	Post.begin_day(run)
	Inv.add(run.home, "rice", 8)
	Inv.add(run.home, "millet", 3)
	Inv.add(run.home, "firewood", 5)
	Inv.add(run.home, "charcoal", 2)
	Inv.add(run.home, "wood", 6)
	var plot0: Dictionary = run.plots[0]
	plot0.crop = "radish"
	plot0.days = 2.5
	var plot1: Dictionary = run.plots[1]
	plot1.crop = "cabbage"
	plot1.days = 1.2
	run.facilities.append("stove")
	return run


# ---------- 契约 ----------

func _contract(world: Node3D, run: Dictionary) -> Array:
	var out: Array = []
	var S = load(SURR_PATH)
	var surr: Node3D = world.get_node_or_null("surroundings")

	out.append(_check("surroundings_node_present",
		surr != null and surr is Node3D and surr.get_parent() == world,
		"HomeWorld 直接子节点 Node3D \"surroundings\"；实际：%s"
		% ("null（景物尚未实现）" if surr == null else "%s parent=%s" % [surr.get_class(), surr.get_parent()])))
	if S == null:
		out.append(_check("factory_module_loads", false, "无法加载 %s" % SURR_PATH))
		return out
	out.append(_check("factory_module_loads", true, ""))
	if surr == null:
		return out

	# 三层结构 + 每层在核心合并之后仍有真实渲染网格
	for layer in LAYER_NAMES:
		var ln: Node3D = surr.get_node_or_null(layer)
		var present := ln != null and ln is Node3D
		var rendered := 0
		if present:
			rendered = _rendered_count(ln)
		out.append(_check("layer_rendered_%s" % layer,
			present and rendered > 0,
			"层 %s 应存在且含渲染网格（合并网格/多网格实例）；present=%s rendered=%d"
			% [layer, present, rendered]))

	# 无碰撞 / 无导航 / 无灯光 / 无可交互标记
	var forbidden := _forbidden_nodes(surr)
	out.append(_check("background_has_no_interactions",
		forbidden.is_empty(),
		"背景不得含 CollisionObject3D/NavigationRegion3D/OmniLight3D/spot 元数据；发现：%s"
		% ", ".join(forbidden.slice(0, 8))))

	# 八方位 × 三距离带：plan() 是工厂实际摆放用的锚点，每个锚点旁必须有真实 AABB。
	# 用未合并的独立构建取逐锚点小包围盒（merged 的按材质联合 AABB 会把不同房屋圈在一起）。
	var plan: Dictionary = S.plan()
	var probe := Node3D.new()
	add_child(probe)
	var raw: Node3D = S.build(probe, {}, false)
	var aabbs := _collect_aabbs(raw, Transform3D.IDENTITY)
	for layer in LAYER_NAMES:
		var anchors: Array = plan.get(layer, [])
		var missing := 0
		var octants := {}
		var max_d := ANCHOR_NEAR_MAX if layer == "near" else (ANCHOR_MID_MAX if layer == "middle" else ANCHOR_FAR_MAX)
		for a in anchors:
			var p := Vector3(float(a.get("x", 0)), 0.0, float(a.get("z", 0)))
			var d := _nearest_aabb_dist(p, aabbs)
			if d > max_d:
				missing += 1
				continue
			var band: Array = BAND_RADIUS[layer]
			var rr := Vector2(p.x, p.z).length()
			if rr >= band[0] and rr <= band[1]:
				octants[_octant(p)] = true
		var have := octants.keys().size()
		out.append(_check("coverage_%s" % layer,
			missing == 0 and anchors.size() >= 4 and have == 8,
			"%s：锚点 %d 个，无网格锚点 %d，覆盖方位 %d/8" % [layer, anchors.size(), missing, have]))

	# 低俯角天际线：生产构建（已合并）的 far 层整体 Y 向压缩（height_scale，默认 0.4），
	# 全局 AABB 最高点 ≤10m；压缩必须仍可见（不许 scale=0 / visible=false 藏峰）。
	var far_node: Node3D = surr.get_node_or_null("far")
	var far_top := -1e9
	var far_bottom := 1e9
	var far_visuals := 0
	if far_node != null:
		for v in _all_visuals(far_node):
			var vi2: VisualInstance3D = v
			var ab: AABB = vi2.global_transform * vi2.get_aabb()
			far_top = maxf(far_top, ab.end.y)
			far_bottom = minf(far_bottom, ab.position.y)
			far_visuals += 1
	var far_sy: float = far_node.scale.y if far_node != null else 0.0
	out.append(_check("far_skyline_compressed",
		far_node != null and far_node.visible and far_visuals > 0
			and far_sy >= 0.2 and far_sy <= 1.0 and far_top <= 10.0,
		"far 须可见、scale.y∈[0.2,1.0]、合并后全局 AABB 顶≤10.0m；visuals=%d scale.y=%.2f top=%.2f bottom=%.2f"
		% [far_visuals, far_sy, far_top, far_bottom]))

	# 山峰朝向：K.prism 三角形截面在 XY、沿本地 Z 拉伸；峰根节点须转 90-ang，
	# 使本地 ±Z 与锚点径向同向，玩家径向看到三角形山面而非长条平顶盒；
	# 主峰网格截面沿切向展开（x 宽 > z 深）。用未合并 raw 逐锚点核对几何。
	var raw_far: Node3D = raw.get_node_or_null("far")
	var peak_total := 0
	var peak_bad := 0
	var worst_dot := 2.0
	if raw_far != null:
		for a in plan.get("far", []):
			if str(a.get("kind", "")) != "peak":
				continue
			peak_total += 1
			var ax := float(a.x)
			var az := float(a.z)
			var radial := Vector3(ax, 0.0, az).normalized()
			var hit: Node3D = null
			var best_h := 1e9
			for c in raw_far.get_children():
				if c is Node3D and not (c is VisualInstance3D):
					var dh := Vector2(float(c.position.x) - ax, float(c.position.z) - az).length()
					if dh < best_h:
						best_h = dh
						hit = c
			if hit == null or best_h > ANCHOR_FAR_MAX:
				peak_bad += 1
				continue
			var ddot := absf(hit.global_transform.basis.z.normalized().dot(radial))
			worst_dot = minf(worst_dot, ddot)
			if ddot <= 0.99:
				peak_bad += 1
				continue
			var main_size := Vector3.ZERO
			var main_vol := -1.0
			for c in hit.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
					var mesh3: Mesh = (c as MeshInstance3D).mesh
					var ms: Vector3 = (mesh3 as PrismMesh).size if mesh3 is PrismMesh \
						else mesh3.get_aabb().size
					var vol := ms.x * ms.y * ms.z
					if vol > main_vol:
						main_vol = vol
						main_size = ms
			if main_vol <= 0.0 or main_size.x <= main_size.z:
				peak_bad += 1
	out.append(_check("peaks_face_radial",
		peak_total >= 4 and peak_bad == 0,
		"峰锚点 %d 座，朝向/截面不合格 %d，最差 |本地Z·径向|=%.3f（须>0.99），主峰须 size.x>size.z"
		% [peak_total, peak_bad, worst_dot if worst_dot <= 1.0 else -1.0]))

	# 确定性：再构建一个完整 HomeWorld，surroundings 签名必须一致
	var world2 = HomeWorld.new()
	add_child(world2)
	var surr2: Node3D = world2.get_node_or_null("surroundings")
	var sig_ok := false
	var sig_detail := "第二实例无 surroundings"
	if surr2 != null:
		var s1 := _signature(surr)
		var s2 := _signature(surr2)
		sig_ok = s1 == s2
		sig_detail = "sig1=%s sig2=%s" % [s1, s2]
	out.append(_check("deterministic_rebuild_signature", sig_ok, sig_detail))

	# toggle / rebuild 不改局面、Game.run、全局 RNG
	var run_hash := JSON.stringify(run).hash()
	seed(424242)
	var rng_before := [randi(), randi()]
	var game_run_empty: bool = Game.run.is_empty()
	surr.visible = false
	var hid := not surr.visible
	surr.visible = true
	var rebuilt: Node3D = S.replace(world, surr, {})
	world.surroundings = rebuilt
	var rebuilt_ok := rebuilt != null and world.get_node_or_null("surroundings") == rebuilt \
		and _rendered_count(rebuilt.get_node("near")) > 0 and _forbidden_nodes(rebuilt).is_empty()
	# replace 同步 remove_child + queue_free；不跨帧（跨帧会让环境节点消耗全局 RNG 污染断言）
	var freed_ok := surr.is_queued_for_deletion() and surr.get_parent() == null
	var run_hash2 := JSON.stringify(run).hash()
	var rng_after := [randi(), randi()]
	# 期望序列：同种子下取走两次后，不经重建应当得到的两个值
	seed(424242)
	randi(); randi()
	var rng_expect := [randi(), randi()]
	out.append(_check("toggle_works", hid and rebuilt.visible, "显隐切换失效"))
	out.append(_check("replace_rebuild_clean",
		rebuilt_ok and freed_ok,
		"replace 后新根就位且旧根离树；rebuilt_ok=%s freed_ok=%s" % [rebuilt_ok, freed_ok]))
	out.append(_check("state_invariant_after_rebuild",
		run_hash == run_hash2 and rng_after == rng_expect and game_run_empty and Game.run.is_empty(),
		"run_hash %s→%s, rng %s vs expect %s, Game.run empty=%s/%s"
		% [run_hash, run_hash2, rng_after, rng_expect, game_run_empty, Game.run.is_empty()]))

	# 原有核心坐标 / 交互点不变，C6 只新增一个隔墙交谈口。
	out.append(_check("core_layout_unchanged",
		absf(world.GATE_Z - 7.0) < 0.001 and world.spot_nodes.size() == 11 and world.spot_nodes.has("neighbor_home")
			and world.nearest_spot(Vector3(0, 0, 5.8)) == "gate"
			and world.indoors(Vector3(0, 0, -5.7)),
		"GATE_Z=%s spots=%d gate_spot=%s indoors=%s"
		% [world.GATE_Z, world.spot_nodes.size(), world.nearest_spot(Vector3(0, 0, 5.8)),
			world.indoors(Vector3(0, 0, -5.7))]))

	# 缺配置 / 怪字段都不崩，返回默认配置，且能独立构建
	var cfg: Dictionary = S.load_config("res://tests/no_such_c0_layout.json", {})
	var probe2 := Node3D.new()
	add_child(probe2)
	var built: Node3D = S.build(probe2, {"__bogus_key__": 1}, false)
	var fallback_ok := cfg.has("near") and cfg.has("middle") and cfg.has("far") \
		and built != null and _rendered_count(built.get_node_or_null("near")) > 0
	out.append(_check("missing_config_fallback", fallback_ok,
		"缺 JSON 应回退内置默认值且可构建；cfg keys=%s built=%s"
		% [cfg.keys(), built != null]))
	probe.queue_free()
	probe2.queue_free()
	out.append_array(_extra_contract(world, run))
	# 重建对照实例由基类在扩展契约结束后回收，当前子类不持有 world2。
	if is_instance_valid(world2) and world2.get_parent() != null:
		world2.queue_free()
	return out


## 子类扩展契约（C1 宅院氛围）；基类默认不增加任何检查，C0 行为/计数不变。
func _extra_contract(world: Node3D, run: Dictionary) -> Array:
	return []


func _check(name: String, ok: bool, detail: String) -> Dictionary:
	return {"name": name, "ok": ok, "detail": detail}


func _rendered_count(n: Node) -> int:
	var c := 0
	for child in n.get_children():
		if child is MultiMeshInstance3D:
			if child.multimesh != null and child.multimesh.instance_count > 0:
				c += 1
		elif child is MeshInstance3D:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			if mesh != null and mesh.get_surface_count() > 0:
				c += 1
		if child is Node:
			c += _rendered_count(child)
	return c


func _forbidden_nodes(n: Node) -> Array:
	var found := []
	if n is CollisionObject3D or n is NavigationRegion3D or n is Light3D:
		found.append("%s(%s)" % [n.name, n.get_class()])
	if n is Node and n.has_meta("spot"):
		found.append("%s(meta:spot)" % n.name)
	for c in n.get_children():
		found.append_array(_forbidden_nodes(c))
	return found


func _collect_aabbs(n: Node, xf: Transform3D) -> Array:
	var out := []
	for c in n.get_children():
		if c is VisualInstance3D:
			var vi := c as VisualInstance3D
			var local := vi.get_aabb()
			if local.size.length() > 0.01:
				var w := xf * vi.transform
				out.append({"center": w * local.get_center(), "half": local.size.abs() * 0.5})
		if c is Node3D:
			out.append_array(_collect_aabbs(c, xf * (c as Node3D).transform))
		elif c is Node:
			out.append_array(_collect_aabbs(c, xf))
	return out


func _nearest_aabb_dist(p: Vector3, aabbs: Array) -> float:
	# 覆盖率只问水平摆位（山峰/塔楼有高度，y 偏移不应算作“没摆在锚点上”）。
	var best := 1e9
	for b in aabbs:
		var c: Vector3 = b["center"]
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < best:
			best = d
	return best


## 八方位：atan2(z,x) 量化到 45° 桶（E/NE/N/NW/W/SW/S/SE）。
func _octant(p: Vector3) -> int:
	var deg := rad_to_deg(atan2(p.z, p.x))
	if deg < 0.0:
		deg += 360.0
	return int(round(deg / 45.0)) % 8


func _signature(root: Node3D) -> int:
	var lines := []
	for layer in LAYER_NAMES:
		var ln: Node = root.get_node_or_null(layer)
		if ln == null:
			lines.append("%s:MISSING" % layer)
			continue
		var meshes := 0
		var instances := 0
		var centers := []
		for v in _all_visuals(ln):
			var vi: VisualInstance3D = v
			meshes += 1
			if vi is MultiMeshInstance3D and vi.multimesh != null:
				instances += vi.multimesh.instance_count
			var c := (vi.global_transform * vi.get_aabb().get_center()).snapped(Vector3.ONE * 0.01)
			centers.append("%s:%s" % [vi.get_class(), c])
		centers.sort()
		lines.append("%s:m%d:i%d:%d:%s" % [layer, meshes, instances, centers.size(), "/".join(centers.slice(0, 40))])
	return "\n".join(lines).hash()


func _all_visuals(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is VisualInstance3D:
			out.append(c)
		if c is Node:
			out.append_array(_all_visuals(c))
	return out


# ---------- 截图 + 性能 ----------

func _run_baseline(world, opts: Dictionary, node_total: int, world_nodes: int) -> int:
	var size := _parse_resolution(str(opts.get("resolution", "1280x720")))
	if size.x < 1280 or size.y < 720:
		print("%s --resolution 太小：%s（至少 1280x720）" % [LOG_PREFIX, str(opts.get("resolution", ""))])
		return 3
	await _resize_window(size)

	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 等两帧让模式生效，再查询实际模式；无法真关 vsync 的环境必须有限失败。
	await get_tree().process_frame
	await get_tree().process_frame
	var vsync_mode := DisplayServer.window_get_vsync_mode()
	if vsync_mode != DisplayServer.VSYNC_DISABLED:
		print("%s 无法关闭 vsync（实际模式=%d %s），帧时间测量无意义，失败" %
			[LOG_PREFIX, vsync_mode, _vsync_name(vsync_mode)])
		return 4

	var player = PlayerScript.new()
	_prepare_capture(world)
	world.add_child(player)
	player.setup("scholar")
	player.position = HomeWorld.SPAWN
	player.enabled = false

	var focus := Node3D.new()
	world.add_child(focus)
	var rig = CamRig.new()
	rig.set("target", focus)
	world.add_child(rig)
	rig.set("input_enabled", false)

	var settle := 5 if bool(opts.get("quick", false)) else 10
	var warmup := 24 if bool(opts.get("quick", false)) else 60

	for i in settle:
		await get_tree().process_frame
	var actual := get_viewport().get_visible_rect().size
	print("%s 视口逻辑 %dx%d；vsync 实际=%s(%d) max_fps=0" %
		[LOG_PREFIX, int(actual.x), int(actual.y), _vsync_name(vsync_mode), vsync_mode])

	_apply_view(rig, 0.0, -54.0, 17.0)
	world.set_preset("noon", 400)
	for i in warmup:
		await RenderingServer.frame_post_draw

	var perf := {}
	var perf_path := str(opts.get("perf", ""))
	if perf_path != "":
		var win_size := DisplayServer.window_get_size()
		perf = await _measure_perf(world, rig, opts, int(win_size.x), int(win_size.y),
			node_total, world_nodes, vsync_mode)
		var perr := _write_json(perf_path, perf)
		if perr != OK:
			print("%s 性能 JSON 写盘失败：%s（error %d）" % [LOG_PREFIX, perf_path, perr])
			return 7
		print("%s 性能 JSON：%s（ok）" % [LOG_PREFIX, perf_path])

	var shots_dir := str(opts.shots)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	if not DirAccess.dir_exists_absolute(shots_dir):
		print("%s 截图目录无法创建：%s" % [LOG_PREFIX, shots_dir])
		return 3
	var manifest: Array = []
	var saved := 0
	var capture_size := Vector2i.ZERO
	var shot_plan := _shot_plan()
	for shot in shot_plan:
		_prepare_shot(world, shot)
		_apply_view(rig, float(shot.yaw), float(shot.pitch), float(shot.dist))
		for i in settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		capture_size = Vector2i(img.get_width(), img.get_height())
		if capture_size.x != size.x or capture_size.y != size.y:
			print("%s 截图像素 %dx%d 与请求 %dx%d 不符，失败" %
				[LOG_PREFIX, capture_size.x, capture_size.y, size.x, size.y])
			return 6
		var path := shots_dir.path_join("%s.png" % str(shot.file))
		var err := img.save_png(path)
		var ok := err == OK and FileAccess.file_exists(path)
		if ok:
			saved += 1
		else:
			print("%s 截图失败：%s（error %d）" % [LOG_PREFIX, path, err])
			return 2
		var entry := {
			"file": "%s.png" % str(shot.file),
			"ok": ok,
			"preset": str(shot.preset),
			"yaw_deg": float(shot.yaw),
			"pitch_deg": float(shot.pitch),
			"dist": float(shot.dist),
			"resolution": [capture_size.x, capture_size.y],
			"fog_mul": float(world.sky.fog_mul),
		}
		var extra_meta := _shot_metadata(world, shot, img)
		for k in extra_meta:
			entry[k] = extra_meta[k]
		manifest.append(entry)
		print("%s saved %s.png（%s %dx%d）" % [
			LOG_PREFIX, str(shot.file), str(shot.preset), capture_size.x, capture_size.y])

	var manifest_data := {
		"kind": _manifest_kind(),
		"label": str(opts.get("label", "after")),
		"seed": FIXED_SEED,
		"resolution": [capture_size.x, capture_size.y],
		"requested_resolution": [size.x, size.y],
		"fog_mul": float(world.sky.fog_mul),
		"vsync_mode": _vsync_name(vsync_mode),
		"cam_bounds": {"pitch": [-80.0, -20.0], "dist": [7.0, 26.0], "fov": 42.0},
		"shots": manifest,
		"saved": saved,
		"total": shot_plan.size(),
	}
	var merr := _write_json(shots_dir.path_join("shots_manifest.json"), manifest_data)
	if merr != OK:
		print("%s 截图清单写盘失败：error %d" % [LOG_PREFIX, merr])
		return 8
	print("%s 截图 %d/%d，清单：shots_manifest.json（ok）" % [LOG_PREFIX, saved, shot_plan.size()])
	return 0 if saved == shot_plan.size() else 2


# ---------- 子类扩展钩子（C1 宅院氛围；基类默认行为 = 原 C0：16 机位、字段不变） ----------

## 截图机位清单。
func _shot_plan() -> Array:
	return SHOTS


## 真窗口捕获开始前的一次性准备（子类造 pre / 大雪局面）。
func _prepare_capture(world: Node3D) -> void:
	pass


## 每个机位的局面 / 预设切换；基类只切天空预设（C0 原行为）。
func _prepare_shot(world: Node3D, shot: Dictionary) -> void:
	world.set_preset(str(shot.preset), 400)


## 子类往清单条目里追加的实际状态字段；基类不追加任何键。
## img 为该机位刚截到的 Image（真窗口模式），供子类做真实像素诊断。
func _shot_metadata(world: Node3D, shot: Dictionary, _img: Image = null) -> Dictionary:
	return {}


## 清单 / 性能 JSON 的 kind 字段。
func _manifest_kind() -> String:
	return "courtyard_c0_shots"


func _perf_kind() -> String:
	return "courtyard_c0_perf"


func _resize_window(size: Vector2i) -> void:
	# 根 Window.size 在首帧设置会被忽略；不开无边框/独占全屏（远程桌面会卡）。
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_position(Vector2i(0, 0))
	for attempt in 3:
		DisplayServer.window_set_size(size)
		for i in 4:
			await get_tree().process_frame
		if DisplayServer.window_get_size().x >= size.x and DisplayServer.window_get_size().y >= size.y:
			break
	print("%s 屏幕 %dx%d，窗口客户区 %dx%d，请求 %dx%d（canvas_items 拉伸，以截图像素为准）" % [
		LOG_PREFIX, int(screen.x), int(screen.y),
		int(DisplayServer.window_get_size().x), int(DisplayServer.window_get_size().y), size.x, size.y])


func _apply_view(rig, yaw_deg: float, pitch: float, dist: float) -> void:
	rig.set("yaw", deg_to_rad(yaw_deg))
	rig.set("pitch", clampf(pitch, -80.0, -20.0))
	rig.set("dist", clampf(dist, 7.0, 26.0))
	rig.snap()


func _measure_perf(world, rig, opts: Dictionary, w: int, h: int,
		node_total: int, world_nodes: int, vsync_mode: int) -> Dictionary:
	var trials_n := maxi(1, int(opts.get("trials", 3)))
	var samples_n := maxi(30, int(opts.get("samples", 240)))
	_apply_view(rig, 0.0, -54.0, 17.0)
	world.set_preset("noon", 400)
	var trials: Array = []
	for t in trials_n:
		var us: PackedInt64Array = PackedInt64Array()
		var draws: PackedInt64Array = PackedInt64Array()
		var objs: PackedInt64Array = PackedInt64Array()
		for i in 6:
			await RenderingServer.frame_post_draw
		var last := Time.get_ticks_usec()
		for i in samples_n:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			us.append(now - last)
			last = now
			draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			objs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		trials.append({
			"frames": samples_n,
			"frame_ms": _stats_us(us),
			"draw_calls": _stats_int(draws),
			"objects_in_frame": _stats_int(objs),
		})
		print("%s perf trial %d/%d 完成（%d 帧，中位 %.3f ms）" %
			[LOG_PREFIX, t + 1, trials_n, samples_n, float(trials[t].frame_ms.median)])
	return {
		"kind": _perf_kind(),
		"label": str(opts.get("label", "after")),
		"seed": FIXED_SEED,
		"engine": Engine.get_version_info().get("string", ""),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")),
		"resolution": [w, h],
		"vsync_mode": _vsync_name(vsync_mode),
		"max_fps": 0,
		"camera": {"view": "noon_front", "yaw_deg": 0.0, "pitch_deg": -54.0, "dist": 17.0},
		"node_count_total": node_total,
		"world_node_count": world_nodes,
		"trials": trials,
		"note": "墙钟帧间隔（相邻 RenderingServer.frame_post_draw），固定机位、无玩法推进；"
			+ "截图与 JSON 写盘帧不在测量段内。node_count_total=本场景子树，world_node_count=HomeWorld 子树。",
	}


func _vsync_name(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "disabled"
		DisplayServer.VSYNC_ENABLED: return "enabled"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptive"
		DisplayServer.VSYNC_MAILBOX: return "mailbox"
	return "unknown(%d)" % mode


func _stats_us(values: PackedInt64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var ms := PackedFloat64Array()
	var sum := 0.0
	for v in sorted:
		ms.append(float(v) / 1000.0)
		sum += float(v) / 1000.0
	return {
		"min": ms[0],
		"max": ms[n - 1],
		"median": ms[n / 2],
		"p95": ms[mini(n - 1, int(round(float(n) * 0.95)) - 1)],
		"mean": sum / float(n),
	}


func _stats_int(values: PackedInt64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0
	for v in sorted:
		sum += int(v)
	return {"min": sorted[0], "max": sorted[n - 1], "median": sorted[n / 2], "mean": float(sum) / float(n)}


func _count_nodes(root: Node) -> int:
	var n := 1
	for c in root.get_children():
		n += _count_nodes(c)
	return n


func _write_json(path: String, data: Variant) -> int:
	var base := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(base)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return OK if FileAccess.file_exists(path) else FileAccess.get_open_error()


## 输出路径只允许 user:// 或原生绝对路径；拒绝相对路径，防止写进项目根 / cwd 垃圾。
func _validate_opts(opts: Dictionary) -> String:
	var label := str(opts.get("label", "after"))
	if label != "before" and label != "after":
		return "--label 只接受 before|after"
	for key in ["shots", "perf"]:
		var p := str(opts.get(key, ""))
		if p == "":
			continue
		if p.begins_with("user://"):
			continue
		if OS.has_feature("windows"):
			var drive: String = p.substr(0, 1).to_lower()
			if p.length() >= 3 and drive >= "a" and drive <= "z" and p[1] == ":" \
					and (p[2] == "/" or p[2] == "\\"):
				continue
		if p.begins_with("/"):
			continue
		return "%s 路径必须是 user:// 或原生绝对路径：%s" % [key, p]
	return ""


func _parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x", false)
	if parts.size() != 2:
		return Vector2i(0, 0)
	return Vector2i(int(parts[0]), int(parts[1]))


func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts := {
		"baseline": false,
		"quick": false,
		"label": "after",
		"shots": "",
		"perf": "",
		"resolution": "1280x720",
		"trials": 3,
		"samples": 240,
	}
	for a in args:
		if a == "--baseline":
			opts["baseline"] = true
		elif a == "--quick":
			opts["quick"] = true
		elif a.begins_with("--label="):
			opts["label"] = a.trim_prefix("--label=")
		elif a.begins_with("--shots="):
			opts["shots"] = a.trim_prefix("--shots=").replace("\\", "/")
		elif a.begins_with("--perf="):
			opts["perf"] = a.trim_prefix("--perf=").replace("\\", "/")
		elif a.begins_with("--resolution="):
			opts["resolution"] = a.trim_prefix("--resolution=")
		elif a.begins_with("--trials="):
			opts["trials"] = int(a.trim_prefix("--trials="))
		elif a.begins_with("--samples="):
			opts["samples"] = int(a.trim_prefix("--samples="))
		elif a == "--help" or a == "-h":
			opts["help"] = true
		else:
			print("%s 忽略未知参数：%s" % [LOG_PREFIX, a])
	# 空 shots 显式解析到隔离的 user:// 默认目录（且按 pid 唯一），不落到项目根。
	if bool(opts.baseline) and str(opts.shots) == "":
		opts["shots"] = "user://courtyard_c0_shots_%s_%d" % [str(opts.label), OS.get_process_id()]
	return opts


func _print_usage() -> void:
	print("用法：")
	print("  契约（无头）：godot --headless --path <项目> res://tests/courtyard_scenery.tscn")
	print("  截图：      ... res://tests/courtyard_scenery.tscn -- --baseline --label=after")
	print("              --shots=<user:// 或原生绝对目录> [--perf=<同上.json>]")
	print("              [--resolution=1920x1080] [--trials=3] [--samples=240] [--quick]")
