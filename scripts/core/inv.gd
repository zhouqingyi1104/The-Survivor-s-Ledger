extends RefCounted
## 物品仓：{物品id: 数量}。家中存货、独轮车、外出背囊都用同一种结构。

const Data = preload("res://scripts/core/data.gd")

const GRAINS := ["rice", "millet", "glutinous"]


static func count(store: Dictionary, id: String) -> int:
	return int(store.get(id, 0))


static func add(store: Dictionary, id: String, n: int) -> void:
	var c := count(store, id) + n
	if c <= 0:
		store.erase(id)
	else:
		store[id] = c


static func add_all(store: Dictionary, items: Dictionary) -> void:
	for id in items:
		add(store, id, int(items[id]))


static func has_all(store: Dictionary, req: Dictionary) -> bool:
	for id in req:
		if count(store, id) < int(req[id]):
			return false
	return true


static func take_all(store: Dictionary, req: Dictionary) -> void:
	for id in req:
		add(store, id, -int(req[id]))


static func weight(store: Dictionary) -> float:
	var w := 0.0
	for id in store:
		w += float(Data.item(id).get("weight", 0)) * count(store, id)
	return w


static func ids_in_cat(store: Dictionary, cat: String) -> Array:
	var out := []
	for id in store:
		if Data.item(id).get("cat", "") == cat:
			out.append(id)
	return out


## 能直接吃的东西，按饱腹从低到高排（交出去的时候先交差的）。
static func food_ids(store: Dictionary) -> Array:
	var pairs := []
	for id in ids_in_cat(store, "食"):
		pairs.append([_food_value(id), id])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	return pairs.map(func(p): return p[1])


static func _food_value(id: String) -> int:
	return int(Data.item(id).get("eat", {}).get("food", 0))


static func total(store: Dictionary, ids: Array) -> int:
	var n := 0
	for id in ids:
		n += count(store, id)
	return n


## 从 ids 里按顺序凑够 n 个拿走，返回实际拿走的 {id: 数量}。
static func take_any(store: Dictionary, ids: Array, n: int) -> Dictionary:
	var taken := {}
	for id in ids:
		while n > 0 and count(store, id) > 0:
			add(store, id, -1)
			taken[id] = int(taken.get(id, 0)) + 1
			n -= 1
	return taken
