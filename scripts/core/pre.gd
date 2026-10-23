extends RefCounted
## 备劫三日：城中采购。对应原版 PreDisasterMap / ShopUI / ChecklistManager：
## 走动耗时辰，独轮车有负重上限，回家才能卸货；铺子越往后越挤、越贵，有的会关门。

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Home = preload("res://scripts/core/home.gd")

const STATUS := ["正常", "拥挤", "哄抢"]
const DEPLETE := {2: 0.7, 3: 0.4}
const PAWN_RATE := 0.6
const HEIRLOOM_RATE := 0.9

const CHECKLIST := [
	{"name": "口粮", "ids": {"rice": 3, "millet": 3, "glutinous": 2, "flatbread": 1, "jerky": 1}, "levels": [24, 45], "unit": "顿"},
	{"name": "柴炭", "ids": {"firewood": 1, "charcoal": 2}, "levels": [16, 30], "unit": "份"},
	{"name": "药材", "ids": {"salve": 2, "plague_powder": 2, "mugwort": 1, "calm_soup": 1}, "levels": [4, 8], "unit": "份"},
	{"name": "守具", "ids": {"talisman": 1, "dog_blood": 2, "caltrops": 2, "ink_line": 3, "glutinous": 1}, "levels": [6, 12], "unit": "份"},
	{"name": "木料铁钉", "ids": {"wood": 1, "nails": 1}, "levels": [6, 12], "unit": "份"},
	{"name": "种子", "ids": {"seed_cabbage": 1, "seed_radish": 1, "seed_chive": 1}, "levels": [2, 4], "unit": "包"},
	{"name": "灯油", "ids": {"lamp_oil": 1}, "levels": [1, 3], "unit": "壶"},
]


static func shop(shop_id: String) -> Dictionary:
	return Data.table("shops")[shop_id]


static func status(run: Dictionary, shop_id: String) -> String:
	var s := shop(shop_id)
	if s.has("close"):
		var c: Dictionary = s.close
		if run.day > int(c.day) or (run.day == int(c.day) and run.hour >= int(c.hour)):
			return "关门"
	return STATUS[clampi(int(run.day) - 1, 0, 2)]


static func price(run: Dictionary, shop_id: String, item_id: String) -> int:
	var base := float(Data.item(item_id).price)
	var mul := 1.0
	var famine: bool = shop(shop_id).get("famine", false)
	match int(run.day):
		2:
			mul = 1.5 if famine else 1.2
		3:
			mul = 2.5 if famine else 1.5
	if State.has_talent(run, "thrifty"):
		mul *= 0.9
	return int(round(base * mul / 10.0)) * 10


## 手上最顶用的一件载具（在家里或车上都算），没有就空字典。
## 载具在 data/items.json 里写 vehicle: {"travel": 路程乘数, "carry": 多装的斤数}。
## 按**载重**挑最高的一辆：玩家一趟只推一辆车，装了独轮车就不会再回头推板车。
## 路程乘数取这辆车自己的——所以数据上要让"载重最大"的车同时"不更慢"，
## 否则买贵车反而降级（板车/独轮车都给 1.0、只有驴车 0.6，就是这个原因）。
static func vehicle_id(run: Dictionary) -> String:
	var best := ""
	var best_carry := -1
	for store in [run.home, run.cart]:
		for id in store:
			if Inv.count(store, id) <= 0:
				continue
			var v: Dictionary = Data.item(id).get("vehicle", {})
			if v.is_empty():
				continue
			var c := int(v.get("carry", 0))
			if c > best_carry:
				best = id
				best_carry = c
	return best


static func vehicle(run: Dictionary) -> Dictionary:
	var id := vehicle_id(run)
	return {} if id == "" else Data.item(id).get("vehicle", {})


static func capacity(run: Dictionary) -> int:
	var c := int(State.role(run).carry) + int(vehicle(run).get("carry", 0))
	if State.has_talent(run, "hoarder"):
		c += 20
	return c


static func cart_weight(run: Dictionary) -> float:
	return Inv.weight(run.cart)


## 走一趟要几个时辰。载具按路程乘数打折，最少一个时辰（再快也是走过去的）。
static func travel_cost(run: Dictionary, dest: String) -> int:
	if dest == run.loc:
		return 0
	var base := int(shop(run.loc).travel) if dest == "home" else int(shop(dest).travel)
	return maxi(1, int(round(float(base) * float(vehicle(run).get("travel", 1.0)))))


static func hours_left(run: Dictionary) -> int:
	return State.CURFEW_HOUR - int(run.hour)


static func travel_block(run: Dictionary, dest: String) -> String:
	if run.phase != "pre":
		return "现在不能出门。"
	if dest == run.loc:
		return "已经在这里了。"
	if dest != "home":
		if int(run.hour) + travel_cost(run, dest) >= State.CURFEW_HOUR:
			return "赶到时已经宵禁了。"
		if status(run, dest) == "关门":
			return "那边已经关门了。"
	return ""


static func travel(run: Dictionary, dest: String) -> String:
	var err := travel_block(run, dest)
	if err != "":
		return err
	run.hour = int(run.hour) + travel_cost(run, dest)
	run.loc = dest
	if dest == "home":
		_unload(run)
	else:
		var s := shop(dest)
		State.note(run, "到了%s。" % s.name)
		if status(run, dest) == "哄抢" and Rng.chance(run, 0.25):
			run.hour = mini(State.CURFEW_HOUR, int(run.hour) + 1)
			State.note(run, "铺子门口挤得水泄不通，硬是耗掉了一个时辰。")
	return ""


static func _unload(run: Dictionary) -> void:
	if not run.cart.is_empty():
		State.note(run, "回到家，卸下%s。" % Data.describe_items(run.cart))
		Inv.add_all(run.home, run.cart)
		run.cart = {}
	else:
		State.note(run, "回到家。")


static func buy_block(run: Dictionary, item_id: String, n: int) -> String:
	var shop_id: String = run.loc
	if shop_id == "home" or shop(shop_id).kind != "goods":
		return "这里不卖东西。"
	if status(run, shop_id) == "关门":
		return "已经关门了。"
	if int(run.shops[shop_id].get(item_id, 0)) < n:
		return "货不够了。"
	if int(run.silver) < price(run, shop_id, item_id) * n:
		return "银子不够。"
	var w := float(Data.item(item_id).weight) * n
	if cart_weight(run) + w > capacity(run):
		return "车上装不下了，先回家卸货。"
	return ""


static func buy(run: Dictionary, item_id: String, n := 1) -> String:
	var err := buy_block(run, item_id, n)
	if err != "":
		return err
	var shop_id: String = run.loc
	var cost := price(run, shop_id, item_id) * n
	run.silver -= cost
	run.shops[shop_id][item_id] = int(run.shops[shop_id][item_id]) - n
	Inv.add(run.cart, item_id, n)
	return ""


## 能买几个（货量、银子、车子三者取小）。
static func max_buy(run: Dictionary, item_id: String) -> int:
	var shop_id: String = run.loc
	var p := price(run, shop_id, item_id)
	var n := int(run.shops[shop_id].get(item_id, 0))
	if p > 0:
		n = mini(n, int(run.silver) / p)
	var w := float(Data.item(item_id).weight)
	if w > 0:
		n = mini(n, int(floor((capacity(run) - cart_weight(run)) / w)))
	return maxi(0, n)


static func pawn_value(item_id: String) -> int:
	var it := Data.item(item_id)
	var rate := HEIRLOOM_RATE if it.cat == "杂" else PAWN_RATE
	return int(round(float(it.price) * rate / 10.0)) * 10


static func pawnable(run: Dictionary) -> Array:
	var out := []
	for store in [run.cart, run.home]:
		for id in store:
			if pawn_value(id) > 0 and not id in out:
				out.append(id)
	return out


static func pawn(run: Dictionary, item_id: String) -> String:
	if run.loc != "pawnshop":
		return "得去当铺。"
	var store: Dictionary = run.cart if Inv.count(run.cart, item_id) > 0 else run.home
	if Inv.count(store, item_id) <= 0:
		return "没有这件东西。"
	var v := pawn_value(item_id)
	Inv.add(store, item_id, -1)
	run.silver += v
	State.note(run, "当了%s，得银 %s。" % [Data.item_name(item_id), money(v)])
	return ""


static func order_block(run: Dictionary, fac_id: String) -> String:
	if run.loc != "builder":
		return "得去营造坊。"
	if fac_id in run.orders:
		return "已经订了。"
	if int(run.day) > int(shop("builder").order_last_day):
		return "工期来不及了。"
	if int(run.silver) < int(Data.table("facilities")[fac_id].price):
		return "银子不够。"
	return ""


static func order(run: Dictionary, fac_id: String) -> String:
	var err := order_block(run, fac_id)
	if err != "":
		return err
	var f: Dictionary = Data.table("facilities")[fac_id]
	run.silver -= int(f.price)
	run.orders.append(fac_id)
	State.note(run, "在营造坊订了%s。" % f.name)
	return ""


## 回家歇息，结束这一日（宵禁时也走这里）。第三日结束，尸劫降临。
static func end_day(run: Dictionary) -> String:
	if run.phase != "pre":
		return ""
	if run.loc != "home":
		run.loc = "home"
		_unload(run)
	run.day = int(run.day) + 1
	run.hour = State.OPEN_HOUR
	if int(run.day) > State.PRE_DAYS:
		start_disaster(run)
		return ""
	for shop_id in run.shops:
		for id in run.shops[shop_id]:
			var base := int(shop(shop_id).stock[id])
			run.shops[shop_id][id] = mini(int(run.shops[shop_id][id]), int(floor(base * DEPLETE[int(run.day)])))
	State.note(run, "又过了一日。街上的人更慌了，%s。" % ("米价涨了五成" if run.day == 2 else "到处都在抢粮"))
	return ""


static func start_disaster(run: Dictionary) -> void:
	run.phase = "post"
	run.loc = "home"
	var plots := 2
	for fac_id in run.orders:
		var fx: Dictionary = Data.table("facilities")[fac_id].effect
		run.facilities.append(fac_id)
		if fx.has("door_max"):
			run.door.max = int(run.door.max) + int(fx.door_max)
		if fx.has("window_max"):
			run.window.max = int(run.window.max) + int(fx.window_max)
		if fx.has("plots"):
			plots += int(fx.plots)
		if fx.has("water"):
			Inv.add(run.home, "water", int(fx.water))
	var locks := Inv.count(run.home, "iron_lock")
	if locks > 0:
		run.door.max = int(run.door.max) + 20 * locks
		Inv.add(run.home, "iron_lock", -locks)
	# 载具只在备劫三日有用，灾后一并清掉（原来只清家里的独轮车；车上的也要清，不然留着还能加负重）
	for id in Data.table("items"):
		if not Data.item(id).get("vehicle", {}).is_empty():
			for store in [run.home, run.cart]:
				var n := Inv.count(store, id)
				if n > 0:
					Inv.add(store, id, -n)
	run.door.cur = run.door.max
	run.window.cur = run.window.max
	for k in plots:
		run.plots.append({"crop": "", "days": 0.0, "watered_t": 0})
	Inv.add(run.home, "water", 4)
	# 进屋前把家里的家具摆出来（床、书案、柜子、灶台、工作台……），之后可以自己添置、挪动
	Home.ensure_layout(run)
	State.note(run, "第三日夜里，城北的钟乱敲起来。停尸三日的尸瘟死者，一个接一个坐了起来——尸劫降临。")
	run.t = 0
	Post.begin_day(run)


static func checklist(run: Dictionary) -> Array:
	var out := []
	for row in CHECKLIST:
		var n := 0
		for id in row.ids:
			n += (Inv.count(run.home, id) + Inv.count(run.cart, id)) * int(row.ids[id])
		var grade := "不足"
		if n >= int(row.levels[1]):
			grade = "宽裕"
		elif n >= int(row.levels[0]):
			grade = "适当"
		out.append({"name": row.name, "value": n, "unit": row.unit, "grade": grade})
	return out


## 文 → "x两x钱"（1 两 = 1000 文，1 钱 = 100 文）
static func money(wen: int) -> String:
	var liang := wen / 1000
	var qian := (wen % 1000) / 100
	if liang > 0 and qian > 0:
		return "%d两%d钱" % [liang, qian]
	if liang > 0:
		return "%d两" % liang
	return "%d钱" % qian if qian > 0 else "%d文" % wen
