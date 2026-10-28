extends RefCounted
## 宅院营造：家具摆在哪（run.furniture）、造价、拆挪，以及各件家具每天、每夜的功用
## （腌菜坛、熏架、捕鼠笼、炭盆、香炉、摆设的舒适度……）。对应原版 Furniture* / FreeBuildMenu / Trap* 表。
##
## 一件家具：{uid, id, x, z, rot, job?}。x / z 是占地中心（米），rot 只取 0 / 90 / 180 / 270，
## 0 度时正面朝南（+z）。占地是不是撞墙、撞到院里的井和树，由 3D 那边（home_world.gd）用物理查；
## 这里只管能摆的区域、家具互相重叠、件数上限和造价，好在无界面测试里也能用。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")

const CORE_IDS := ["bed", "desk", "storage", "stove", "bench"]

const DAY := 1440
## 摆放吸附的格子（米）
const GRID := 0.25
## 能摆的区域：屋里（正屋、西厢灶房、东厢工坊）和院子
const INDOOR := [Rect2(-5.8, -7.9, 11.6, 4.2), Rect2(-9.9, -3.3, 3.6, 5.6), Rect2(6.3, -3.3, 3.6, 5.6)]
const OUTDOOR := [Rect2(-9.9, 2.6, 19.8, 4.1), Rect2(-6.1, -3.3, 12.2, 5.9)]
## 不许摆的：大门到正屋的中路、米袋 / 柴垛 / 木料堆（这几堆按存货画，没有碰撞）
const SIDE_YARD := Rect2(10.0, 2.7, 6.2, 4.0)
const SIDE_PASSAGE := Rect2(9.2, 3.0, 3.0, 3.0)
const RESERVED := [Rect2(-1.0, -3.8, 2.0, 10.9), Rect2(-9.7, -0.7, 1.6, 1.2), Rect2(-9.7, -3.6, 1.6, 1.2), Rect2(7.9, 0.6, 1.8, 1.6)]
## 开局的摆法（v0.4 以前固定在这些位置）
const DEFAULT_LAYOUT := [
	["bed", -4.0, -7.25, 0], ["desk", 4.2, -6.9, 0], ["bookshelf", 5.15, -7.6, 0],
	["storage", -9.45, 1.5, 90], ["stove", -8.9, -1.6, 90], ["bench", 9.0, -1.2, 270],
]
## 腌菜：鲜菜几棵 → 咸菜几坛
const PICKLE_VEG := ["cabbage", "radish", "mustard", "chive", "spinach"]
const PICKLE_DAYS := 2.0
const SMOKE_DAYS := 1.0
const TRAP_CHANCE := 0.4


static func table() -> Dictionary:
	return Data.table("furniture")


static func data(id: String) -> Dictionary:
	return table().get(id, {})


static func list(run: Dictionary, id := "") -> Array:
	var out := []
	for f in run.get("furniture", []):
		if id == "" or f.id == id:
			out.append(f)
	return out


static func count(run: Dictionary, id: String) -> int:
	return list(run, id).size()


static func find(run: Dictionary, uid: int) -> Dictionary:
	for f in run.get("furniture", []):
		if int(f.uid) == uid:
			return f
	return {}


## The first instance is the original workstation; extra same-type furniture stays independent.
static func core(run: Dictionary, id: String) -> Dictionary:
	if not id in CORE_IDS:
		return {}
	var found := list(run, id)
	return found[0] if not found.is_empty() else {}


static func is_core(run: Dictionary, f: Dictionary) -> bool:
	return not f.is_empty() and core(run, str(f.id)).get("uid", -1) == f.get("uid", -2)


static func stand(f: Dictionary) -> Vector3:
	var facing := front(int(f.rot))
	var depth := float(data(str(f.id)).get("size", [1, 1])[1])
	return Vector3(float(f.x) + facing.x * (depth * 0.5 + 0.8), 0, float(f.z) + facing.y * (depth * 0.5 + 0.8))


static func has_fn(run: Dictionary, fn: String) -> bool:
	for f in run.get("furniture", []):
		if data(f.id).get("fn", "") == fn:
			return true
	return false


static func count_fn(run: Dictionary, fn: String) -> int:
	var n := 0
	for f in run.get("furniture", []):
		if data(f.id).get("fn", "") == fn:
			n += 1
	return n


# ---------- 占地 ----------

## 转过以后的长宽（米）。
static func size_of(id: String, rot: int) -> Vector2:
	var s: Array = data(id).get("size", [1, 1])
	return Vector2(s[1], s[0]) if posmod(rot, 180) == 90 else Vector2(s[0], s[1])


static func rect_of(id: String, x: float, z: float, rot: int) -> Rect2:
	var s := size_of(id, rot)
	return Rect2(x - s.x / 2.0, z - s.y / 2.0, s.x, s.y)


static func snap(v: float) -> float:
	return roundf(v / GRID) * GRID


## 正面朝向（单位向量，xz 平面）。
static func front(rot: int) -> Vector2:
	var a := deg_to_rad(float(rot))
	return Vector2(sin(a), cos(a))


static func _inside(r: Rect2, areas: Array) -> bool:
	# 角、边中点、中心都要落在某块区域里（区域是几块矩形拼起来的）
	var pts := [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center(),
		Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]
	for p in pts:
		var ok := false
		for a in areas:
			if (a as Rect2).grow(0.001).has_point(p):
				ok = true
				break
		if not ok:
			return false
	return true


static func area_of(r: Rect2, run: Dictionary = {}) -> String:
	if _inside(r, INDOOR):
		return "indoor"
	var outdoor := OUTDOOR.duplicate()
	if Expansion.complete(run):
		outdoor.append(SIDE_YARD)
	if _inside(r, outdoor):
		return "outdoor"
	return ""


## 能不能摆在这儿（不查造价）。ignore_uid：挪动时不和自己比。
static func spot_block(run: Dictionary, id: String, x: float, z: float, rot: int, ignore_uid := -1) -> String:
	var d := data(id)
	if d.is_empty():
		return "没有这种家具。"
	var r := rect_of(id, x, z, rot)
	var area := area_of(r, run)
	if area == "":
		return "这儿摆不下。"
	match d.get("where", "any"):
		"indoor":
			if area != "indoor":
				return "%s得摆在屋里。" % d.name
		"outdoor":
			if area != "outdoor":
				return "%s得摆在院里。" % d.name
	if Expansion.complete(run) and r.intersects(SIDE_PASSAGE):
		return "这儿要留作侧院通路。"
	for res in RESERVED:
		if r.intersects(res):
			return "这儿要留着走路 / 堆东西。"
	for f in run.get("furniture", []):
		if int(f.uid) == ignore_uid:
			continue
		if r.grow(-0.02).intersects(rect_of(f.id, float(f.x), float(f.z), int(f.rot))):
			return "和%s挤在一起了。" % data(f.id).name
	return ""


static func build_block(run: Dictionary, id: String) -> String:
	var d := data(id)
	if count(run, id) >= int(d.get("max", 1)):
		return "%s最多 %d 件。" % [d.name, int(d.get("max", 1))]
	if not Inv.has_all(run.home, d.get("cost", {})):
		return "料不够（%s）。" % Data.describe_items(d.get("cost", {}))
	return ""


## 添置前的总检查：料够不够、这个位置摆不摆得下。
static func place_block(run: Dictionary, id: String, x: float, z: float, rot: int, ignore_uid := -1) -> String:
	var err := build_block(run, id)
	if err != "":
		return err
	return spot_block(run, id, x, z, rot, ignore_uid)


## 营造要多久（分钟）：营造熟练每级快一成。
static func build_minutes(run: Dictionary, id: String) -> int:
	var lv := State.prof_level(run, "build")
	return maxi(10, int(round(float(data(id).get("build", 60)) * (1.0 - 0.1 * lv))))


# ---------- 增删挪 ----------

static func add(run: Dictionary, id: String, x: float, z: float, rot: int) -> Dictionary:
	if not run.has("furniture"):
		run.furniture = []
	run.next_uid = int(run.get("next_uid", 1))
	var f := {"uid": run.next_uid, "id": id, "x": x, "z": z, "rot": posmod(rot, 360)}
	run.next_uid = int(run.next_uid) + 1
	run.furniture.append(f)
	if data(id).get("fn", "") == "plant":
		run.plots.append({"crop": "", "days": 0.0, "watered_t": int(run.get("t", 0)), "pot": f.uid})
	return f


## 移动入口、预览和最终写入共用，夜袭目标在整场战斗中保持不变。
static func move_block(run: Dictionary, uid: int) -> String:
	var f := find(run, uid)
	if f.is_empty():
		return "找不到这件家具。"
	if not run.get("fight", {}).is_empty():
		return "夜袭中不能挪动家具，先结束战斗。"
	if is_core(run, f) and str(f.id) in run.get("broken", []):
		return "先修好这件家具再挪位。"
	return ""


static func move(run: Dictionary, uid: int, x: float, z: float, rot: int) -> String:
	var block := move_block(run, uid)
	if block != "":
		return block
	var f := find(run, uid)
	x = snap(x)
	z = snap(z)
	var err := spot_block(run, f.id, x, z, rot, uid)
	if err != "":
		return err
	f.x = x
	f.z = z
	f.rot = posmod(rot, 360)
	return ""


## 拆掉：退一半的料（向下取整）。花盆里的菜、坛里腌着的东西就没了。
static func remove(run: Dictionary, uid: int) -> String:
	var f := find(run, uid)
	if f.is_empty():
		return "找不到这件家具。"
	var d := data(f.id)
	var back := {}
	for item in d.get("cost", {}):
		var n := int(floor(float(d.cost[item]) / 2.0))
		if n > 0:
			back[item] = n
	Inv.add_all(run.home, back)
	run.furniture.erase(f)
	for p in run.plots.duplicate():
		if int(p.get("pot", -1)) == uid:
			run.plots.erase(p)
	State.note(run, "拆了%s%s。" % [d.name, ("，收回" + Data.describe_items(back)) if not back.is_empty() else ""])
	return ""


## 开局摆法；备劫时订了大水缸的，再在院里放一口。
static func ensure_layout(run: Dictionary) -> void:
	if not run.has("furniture"):
		run.furniture = []
	if run.flags.get("layout_done", false):
		return
	run.flags["layout_done"] = true
	if run.furniture.is_empty():
		for row in DEFAULT_LAYOUT:
			add(run, row[0], row[1], row[2], row[3])
	if "water_vat" in run.get("facilities", []) and count(run, "water_vat") == 0:
		add(run, "water_vat", -5.2, 2.0, 0)


## 老卷中的固定工作家具没有数据时补回；已有位置和其他家具均保留。
static func ensure_core(run: Dictionary) -> void:
	if not run.get("furniture") is Array:
		run["furniture"] = []
	var max_uid := 0
	for f in run.furniture:
		max_uid = maxi(max_uid, int(f.get("uid", 0)))
	run["next_uid"] = maxi(int(run.get("next_uid", 1)), max_uid + 1)
	for row in DEFAULT_LAYOUT:
		if row[0] in CORE_IDS and core(run, str(row[0])).is_empty():
			add(run, str(row[0]), float(row[1]), float(row[2]), int(row[3]))


## 舒适度：摆设越多，屋里越像个家（每天心神加成的来源）。
static func comfort(run: Dictionary) -> int:
	var c := 0
	for f in run.get("furniture", []):
		c += int(data(f.id).get("comfort", 0))
	return c


# ---------- 腌菜坛、熏架 ----------

static func job_text(run: Dictionary, f: Dictionary) -> String:
	var job: Dictionary = f.get("job", {})
	if job.is_empty():
		return "空着"
	var left := int(job.done_t) - int(run.t)
	if left <= 0:
		return "好了，明早取出"
	return "%s · 还要 %d 时辰" % [Data.describe_items(job["in"]), int(ceil(left / 120.0))]


## 腌菜：n 棵同样的鲜菜 + 1 把盐，两天后得 n 坛咸菜。
static func pickle(run: Dictionary, uid: int, veg: String, n: int) -> String:
	var f := find(run, uid)
	if f.is_empty() or f.id != "pickle_jar":
		return "找不到腌菜坛。"
	if not f.get("job", {}).is_empty():
		return "坛里还腌着东西。"
	if not veg in PICKLE_VEG:
		return "这个腌不了。"
	n = clampi(n, 1, 4)
	if Inv.count(run.home, veg) < n:
		return "%s不够。" % Data.item_name(veg)
	if Inv.count(run.home, "salt") < 1:
		return "没有盐。"
	Inv.add(run.home, veg, -n)
	Inv.add(run.home, "salt", -1)
	f.job = {"in": {veg: n}, "out": {"pickles": n}, "done_t": int(run.t) + int(PICKLE_DAYS * DAY)}
	State.note(run, "把 %d 棵%s码进坛里，撒了盐封好。" % [n, Data.item_name(veg)])
	return ""


## 熏肉：鲜肉若干 + 1 捆柴，熏一天成腊肉。
static func smoke(run: Dictionary, uid: int, meat: String, n: int) -> String:
	var f := find(run, uid)
	if f.is_empty() or f.id != "smoke_rack":
		return "找不到熏架。"
	if not f.get("job", {}).is_empty():
		return "架上还挂着东西。"
	if meat != "rat":
		return "这个熏不了。"
	n = clampi(n, 1, 4)
	if Inv.count(run.home, meat) < n:
		return "%s不够。" % Data.item_name(meat)
	if Inv.count(run.home, "firewood") < 1:
		return "没有柴。"
	Inv.add(run.home, meat, -n)
	Inv.add(run.home, "firewood", -1)
	f.job = {"in": {meat: n}, "out": {"smoked_rat": n}, "done_t": int(run.t) + int(SMOKE_DAYS * DAY)}
	State.note(run, "把 %d 块%s挂上熏架，底下煨着湿柴。" % [n, Data.item_name(meat)])
	return ""


# ---------- 夜里、天亮 ----------

## 20:00 烧火时：有炭盆的屋里更暖、睡得更安稳。返回给夜报的话。
static func night_heat(run: Dictionary) -> String:
	if count_fn(run, "heat") <= 0:
		return ""
	State.add_attr(run, "mood", 2)
	State.add_attr(run, "warmth", 6)
	return "炭盆烧得通红，屋里暖烘烘的。"


## 21:00 捕鼠笼自取一把粮作饵。
static func bait_traps(run: Dictionary) -> void:
	for f in list(run, "rat_trap"):
		if f.get("baited", false):
			continue
		var taken := Inv.take_any(run.home, ["millet", "beans", "rice"], 1)
		f.baited = not taken.is_empty()


## 6:00 天亮：腌菜、熏肉出坛下架，捕鼠笼收笼，香炉、摆设给心神。返回夜报的句子。
static func dawn(run: Dictionary) -> Array:
	var lines := []
	for f in run.get("furniture", []):
		var job: Dictionary = f.get("job", {})
		if not job.is_empty() and int(run.t) >= int(job.done_t):
			Inv.add_all(run.home, job.out)
			lines.append("%s里取出%s。" % [data(f.id).name, Data.describe_items(job.out)])
			f.job = {}
	var caught := 0
	for f in list(run, "rat_trap"):
		if f.get("baited", false) and Rng.chance(run, TRAP_CHANCE):
			caught += 1
		f.baited = false
	if caught > 0:
		Inv.add(run.home, "rat", caught)
		lines.append("捕鼠笼里逮到 %d 只老鼠。" % caught)
	if count(run, "incense") > 0:
		State.add_attr(run, "mood", 3)
		run.today["merit"] = int(run.today.get("merit", 0)) + 1
		lines.append("香炉里一炷香燃尽了。")
	var c := comfort(run)
	if c >= 4:
		State.add_attr(run, "mood", minf(6.0, c * 0.5))
	return lines
