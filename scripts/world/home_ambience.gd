extends RefCounted
## C1 宅院四周「生活与灾后氛围」工厂（纯视觉，RefCounted 静态工厂）。
##
## 在 home_surroundings 的 near/middle/far 合并之后，由其在 surroundings 根下构造
## 名为 "ambience" 的 Node3D，内含固定小组：窗灯（夜）、炊烟（昼）、晾晒（昼/晴）、
## 短雪痕、封门旧损（灾后）、大雪积雪。全部几何只建一次，按小组各自 merge_static；
## sync/set_time/set_preset 只切换整组 visible（无 Light3D、无粒子、无 _process、
## 无碰撞/导航/spot/Audio），同状态直接早退，绝不重建节点或 C0 层。
##
## 外观只从 run.phase / run.pday / Post.clock(run) / State.weather(run)（大雪 pday6
## 起、cold20+）派生的有限投影；不读写 NPC/邻居生死迁居、不碰 run.broken/wreck、
## 不消耗全局或本局 RNG、不写 run/Game.run、不新增规则或存档字段。

const K = preload("res://scripts/world/kit.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")

## 固定小组（build 一次，apply 只切 visible）。
const GROUPS: Array[String] = [
	"win_post", "win_pre",        # 夜窗灯：灾后常驻子集 / 灾前额外子集
	"smoke_post", "smoke_pre",    # 昼炊烟缕：灾后常驻子集 / 灾前额外子集（砖烟囱在永久 fixtures）
	"laundry",                    # 晾晒布衣（昼且非大雪；木桩横杆在永久 fixtures）
	"traces",                     # 短雪痕（非大雪）
	"damage",                     # 少量封门旧损（仅灾后）
	"snow_heavy",                 # 大雪积雪（仅大雪）
]
## 永久结构容器名（不属于 GROUPS、不进 8 键投影）：砖烟囱/顶帽、晾衣木桩/横杆，
## build 一次、merge 一次，昼夜与大雪都不隐藏；只有烟缕与布衣随投影切换。
const FIXTURES_GROUP := "fixtures"
const STATE_KEY := "_amb_state"

# 灾后天黑后仍亮灯的近邻住户（NEAR_HOUSES 索引；固定选取，跨四向，不按日数变化）。
const WIN_POST: Array[int] = [0, 2, 5, 7, 10, 13, 16, 19, 21]
# 灾前额外亮灯的住户（灾后这些窗不再亮）。
const WIN_PRE_EXTRA: Array[int] = [6, 9, 11, 14, 17, 18]

const GLOW_COLOR := Color("#ffd27e")
const GLOW_EMIT := 0.6  # 弱自发光（自家灯笼点亮 2.5），且不带 Light3D

# 灾后白天仍生火的住户（固定子集，跨四向，不随日数增减）。
const SMOKE_POST: Array[int] = [1, 3, 4, 8, 10, 12, 14, 17, 20]
# 灾前额外生火的住户（灾后冷灶）。
const SMOKE_PRE_EXTRA: Array[int] = [0, 6, 11, 15]
# 房前晾衣住户（跨四向；避开封门户）。
const LAUNDRY: Array[int] = [2, 7, 10, 13, 16, 20]
# 门前短雪痕住户（只选房前不朝核心开的房屋）。
const TRACES: Array[int] = [0, 1, 5, 7, 9, 11, 12]

const SMOKE_COLOR := Color("#c2c7cd")
# 灾后少量封门旧损（固定四户，跨四向；不按日数增减、不代表任何 NPC 命运）。
# 9 号在南排直面门外迎战巷道，玩家出大门即可看到；15/18 号贴东西巷。
const DAMAGE: Array[int] = [4, 9, 15, 18]
# 大雪时额外积雪（门前雪包 + 檐口厚雪）的住户。
const SNOW_HEAVY: Array[int] = [0, 2, 9, 12, 13, 16, 20]
const PLANK_COLOR := Color("#745f47")


# ---------- 工厂 ----------

## 在 surroundings 根下构造 ambience；houses 为 home_surroundings.NEAR_HOUSES 数据。
## merge_layers=false（测试）时保留逐构件节点，供完整旋转变换 AABB 检查。
static func build(surr_root: Node3D, houses: Array, merge_layers: bool) -> Node3D:
	var amb := K.node(surr_root, Vector3.ZERO, Vector3.ZERO, "ambience")
	for gname in GROUPS:
		K.node(amb, Vector3.ZERO, Vector3.ZERO, gname)
	K.node(amb, Vector3.ZERO, Vector3.ZERO, FIXTURES_GROUP)
	_build_geometry(amb, houses)
	# 建造时全部可见（隐藏节点不会被 merge_static 收并），合并后再落回默认投影。
	if merge_layers:
		for gname in GROUPS:
			K.merge_static(amb.get_node(gname), [])
		K.merge_static(amb.get_node(FIXTURES_GROUP), [])
	apply(amb, project("post", 1, 12 * 60, false))
	return amb


# 几何构建在后续纵向切片中填充。
static func _build_geometry(amb: Node3D, houses: Array) -> void:
	var glow_mat := K.mat(GLOW_COLOR, 0.9, GLOW_EMIT)
	_build_windows(amb.get_node("win_post"), houses, WIN_POST, glow_mat)
	var smoke_mat := K.mat(SMOKE_COLOR, 1.0, 0.0, 0.55)
	_build_fixtures(amb.get_node(FIXTURES_GROUP), houses)
	_build_smoke(amb.get_node("smoke_post"), houses, SMOKE_POST, smoke_mat)
	_build_smoke(amb.get_node("smoke_pre"), houses, SMOKE_PRE_EXTRA, smoke_mat)
	_build_laundry(amb.get_node("laundry"), houses, LAUNDRY)
	_build_traces(amb.get_node("traces"), houses, TRACES)
	_build_damage(amb.get_node("damage"), houses, DAMAGE)
	_build_heavy_snow(amb.get_node("snow_heavy"), houses, SNOW_HEAVY)
	_build_windows(amb.get_node("win_pre"), houses, WIN_PRE_EXTRA, glow_mat)


## 与 home_surroundings._house 完全一致的窗格枚举（正面 dc±2.3 受 w/2-.8 限制；
## style>=2 一扇侧窗），保证窗灯只贴实际存在的窗。
static func _windows_of(h: Dictionary) -> Array:
	var w: float = h.w
	var d: float = h.d
	var style: int = int(h.style)
	var dc: float = [-0.5, 0.5, 0.0, 0.4][style]
	var out: Array = []
	for side in [-1.0, 1.0]:
		var wx: float = dc + side * 2.3
		if absf(wx) < w / 2.0 - 0.8:
			out.append({"pos": Vector3(wx, 1.45, d / 2.0 + 0.01), "ry": 0.0})
	if style >= 2:
		out.append({"pos": Vector3(w / 2.0 + 0.01, 1.45, -d * 0.15), "ry": 90.0})
	return out


## 每户一个与房屋同方位的节点，窗内两扇纸片各贴一片发光薄盒（相对 C0 纸窗外移一层）。
static func _build_windows(group: Node3D, houses: Array, indices: Array, glow_mat: Material) -> void:
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var hn := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		for win in _windows_of(h):
			var p := K.node(hn, win.pos, Vector3(0.0, float(win.ry), 0.0))
			# C0 纸窗中心在 d/2+.01、墙皮外沿在 d/2+.12（窗洞凹陷 0.08）；
			# 发光纸片必须抬到墙皮之外，否则被前墙实体埋住（侧窗同理，节点 ry=90 后局部 +Z 朝外）。
			for sx in [-0.22, 0.22]:
				K.box(p, Vector3(0.35, 0.55, 0.012), glow_mat, Vector3(sx, 0.0, 0.130))


## 永久结构：砖烟囱/顶帽（生火户）与晾衣木桩/横杆（晾衣户）。位置/形体/阴影与原
## smoke/laundry 小组内完全一致，只是迁到昼夜与大雪都不隐藏的 fixtures 容器。
static func _build_fixtures(group: Node3D, houses: Array) -> void:
	var chimney_ids: Dictionary = {}
	for i in SMOKE_POST + SMOKE_PRE_EXTRA:
		chimney_ids[int(i)] = true
	var frame_ids: Dictionary = {}
	for i in LAUNDRY:
		frame_ids[int(i)] = true
	var all_ids: Array = chimney_ids.keys().duplicate()
	for i in frame_ids.keys():
		if not all_ids.has(i):
			all_ids.append(i)
	all_ids.sort()
	for i in all_ids:
		var h: Dictionary = houses[int(i)]
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		if chimney_ids.has(int(i)):
			_build_chimney(n, h)
		if frame_ids.has(int(i)):
			_build_laundry_frame(n, h)


## 砖烟囱出屋脊：实体砖体与顶帽留在永久 fixtures，不投影（与原实现一致）。
static func _build_chimney(n: Node3D, h: Dictionary) -> void:
	var w: float = h.w
	var d: float = h.d
	var hh: float = h.h
	var rise := d * 0.38
	var cx := -w * 0.28
	var cz := -d * 0.1
	var pot := K.box(n, Vector3(0.4, 0.7, 0.4), K.BRICK, Vector3(cx, hh + rise + 0.1, cz))
	pot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cap := K.box(n, Vector3(0.56, 0.12, 0.56), K.BRICK, Vector3(cx, hh + rise + 0.51, cz))
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 三缕细烟：压扁的半透明小球，静态、无粒子、无火色、不投影；砖烟囱已在永久 fixtures。
static func _build_smoke(group: Node3D, houses: Array, indices: Array, smoke_mat: Material) -> void:
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var w: float = h.w
		var d: float = h.d
		var hh: float = h.h
		var rise := d * 0.38
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		var cx := -w * 0.28
		var cz := -d * 0.1
		for k in 3:
			var yy := hh + rise + 0.72 + float(k) * 0.4
			var r := 0.17 + float(k) * 0.075
			var puff := K.sphere(n, r, smoke_mat,
				Vector3(cx + 0.1 + float(k) * 0.1, yy, cz + float(k) * 0.06), Vector3(1.0, 0.85, 1.0))
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 晾衣木桩 + 横杆：纯视觉无碰撞，永久可见（位置在房屋局部 +Z 门面朝街那侧）。
static func _build_laundry_frame(n: Node3D, h: Dictionary) -> void:
	var w: float = h.w
	var d: float = h.d
	var fz := d / 2.0 + 1.25
	var half := w * 0.22
	for sx in [-1.0, 1.0]:
		K.cyl(n, 0.04, 0.05, 1.9, K.WOOD, Vector3(sx * half, 0.95, fz), Vector3.ZERO, 6)
	K.cyl(n, 0.015, 0.015, half * 2.0 + 0.3, K.WOOD_LIGHT,
		Vector3(0.0, 1.85, fz), Vector3(0.0, 0.0, 90.0), 4)


## 房前三件布衣：随昼/非大雪显隐；木桩横杆已在永久 fixtures。
static func _build_laundry(group: Node3D, houses: Array, indices: Array) -> void:
	var cloth_cols: Array = [Color("#3f5a7a"), Color("#d8d0bd"), Color("#7a3a2e")]
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var w: float = h.w
		var d: float = h.d
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		var fz := d / 2.0 + 1.25
		var half := w * 0.22
		for k in 3:
			var xx := -half * 0.8 + float(k) * half * 0.8
			K.box(n, Vector3(0.5, 0.82, 0.03), K.mat(cloth_cols[k], 0.95),
				Vector3(xx, 1.4, fz), Vector3(0.0, float(k - 1) * 4.0, 0.0))


## 门前三短条踏乱的雪痕：深色薄贴片，全部贴地、朝街不朝核心。
static func _build_traces(group: Node3D, houses: Array, indices: Array) -> void:
	var mark := K.mat(Color("#6f6b64"), 0.97)
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var d: float = h.d
		var dc: float = [-0.5, 0.5, 0.0, 0.4][int(h.style)]
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		for k in 3:
			var zz := d / 2.0 + 0.6 + float(k) * 0.42
			K.box(n, Vector3(0.22, 0.02, 0.42), mark,
				Vector3(dc, 0.025, zz), Vector3(0.0, float(k * 7 - 7), 0.0))


## 封门旧损：门板前两条交叉旧木板 + 一根横压条，全部在房屋 footprint 内。
static func _build_damage(group: Node3D, houses: Array, indices: Array) -> void:
	var plank := K.mat(PLANK_COLOR, 0.95)
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var d: float = h.d
		var dc: float = [-0.5, 0.5, 0.0, 0.4][int(h.style)]
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		for sgn in [-1.0, 1.0]:
			K.box(n, Vector3(0.26, 1.7, 0.08), plank,
				Vector3(dc, 1.18, d / 2.0 + 0.06), Vector3(0.0, 0.0, sgn * 32.0))
		K.box(n, Vector3(0.82, 0.18, 0.08), plank,
			Vector3(dc, 1.52, d / 2.0 + 0.08))


## 大雪：门前矮雪包（半球压扁）+ 前檐一道厚雪帽；雪包低矮不挡迎战通道。
static func _build_heavy_snow(group: Node3D, houses: Array, indices: Array) -> void:
	for i in indices:
		var h: Dictionary = houses[int(i)]
		var w: float = h.w
		var d: float = h.d
		var hh: float = h.h
		var dc: float = [-0.5, 0.5, 0.0, 0.4][int(h.style)]
		var n := K.node(group, Vector3(float(h.x), 0.0, float(h.z)),
			Vector3(0.0, float(h.rot), 0.0), "h%d" % int(i))
		var mound := K.sphere(n, 0.55, K.SNOW,
			Vector3(dc, 0.02, d / 2.0 + 0.65), Vector3(1.0, 0.5, 1.0), true)
		mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		K.box(n, Vector3(w * 0.7, 0.1, 0.34), K.SNOW,
			Vector3(0.0, hh + 0.09, d / 2.0 + 0.5))


# ---------- 纯状态投影 ----------

## phase/pday/clock(0..1439)/heavy(大雪) → 各小组显隐。纯函数，不读 run。
static func project(phase: String, pday: int, clock_min: int, heavy: bool) -> Dictionary:
	var night: bool = clock_min < 6 * 60 + 30 or clock_min >= 17 * 60 + 30
	var pre: bool = phase == "pre"
	return {
		"win_post": night,
		"win_pre": night and pre,
		"smoke_post": not night,
		"smoke_pre": (not night) and pre,
		"laundry": (not night) and not heavy,
		"traces": not heavy,
		"damage": phase == "post",
		"snow_heavy": heavy,
	}


## 只依据允许的四个来源派生投影（大雪：灾后 pday>=6 或天气 cold>=20）。
## pday=0 不读 weather 表——State.weather 对 pday0 落到表末项 cold25 会凭空开大雪；
## HomeWorld.set_time 同样只在 pday>0 时读 weather（否则 cold=10），此处必须对齐。
static func state_for_run(run: Dictionary) -> Dictionary:
	var phase := str(run.get("phase", "post"))
	var pday := int(run.get("pday", 0))
	var clock_min: int = Post.clock(run) if run.has("t") else 12 * 60
	var heavy := false
	if phase == "post" and pday > 0:
		var cold := int(State.weather(run).get("cold", 0))
		heavy = pday >= 6 or cold >= 20
	return project(phase, pday, clock_min, heavy)


## set_preset 路径：用 HomeWorld 缓存的阶段/大雪上下文 + 预设名派生投影。
static func state_for_preset(preset: String, ctx: Dictionary) -> Dictionary:
	var clock_min: int = {"dawn": 7 * 60, "noon": 12 * 60, "dusk": 18 * 60,
		"night": 23 * 60, "blood": 23 * 60}.get(preset, 12 * 60)
	return project(str(ctx.get("phase", "post")), int(ctx.get("pday", 1)),
		clock_min, bool(ctx.get("heavy", false)))


# ---------- 应用（只切 visible，同状态早退） ----------

## 把投影落到小组 visible；返回是否发生了变化。永不重建节点。
## 缺 meta 时先 has_meta 再读：get_meta(key, null) 在 Godot 4 仍打印 ERROR，
## 不能用默认参数形式探测（也不能静默吞掉其他错误）。
static func apply(amb: Node3D, state: Dictionary) -> bool:
	if amb == null:
		return false
	if amb.has_meta(STATE_KEY):
		var prev = amb.get_meta(STATE_KEY)
		if prev is Dictionary and prev == state:
			return false
	for gname in GROUPS:
		var g: Node = amb.get_node_or_null(gname)
		if g != null:
			(g as Node3D).visible = bool(state.get(gname, false))
	# 存副本：调用者之后改原字典不会污染元缓存（否则下一次同状态早退会被破坏）。
	amb.set_meta(STATE_KEY, state.duplicate())
	return true


## 返回当前投影的副本（调用者可任意改）；缺 meta / amb 为空时返回 {}，同样不打 ERROR。
static func current_state(amb: Node3D) -> Dictionary:
	if amb != null and amb.has_meta(STATE_KEY):
		var v = amb.get_meta(STATE_KEY)
		if v is Dictionary:
			return (v as Dictionary).duplicate()
	return {}
