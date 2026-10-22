extends RefCounted
## 可存档的随机数：每次抽取都用 (局种子, 抽取计数) 重新播种。
## 存档里只需记一个整数 rng_n，读档、翻回生死簿后结果仍然可以复现。


static func _gen(run: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d" % [run.seed, run.rng_n])
	run.rng_n += 1
	return r


static func f(run: Dictionary) -> float:
	return _gen(run).randf()


static func i(run: Dictionary, lo: int, hi: int) -> int:
	return _gen(run).randi_range(lo, hi)


static func chance(run: Dictionary, p: float) -> bool:
	return f(run) < p


static func pick(run: Dictionary, arr: Array):
	if arr.is_empty():
		return null
	return arr[i(run, 0, arr.size() - 1)]


## entries 里每一项是数组，weight_index 指定权重所在位置。
static func weighted(run: Dictionary, entries: Array, weight_index := 1):
	var total := 0.0
	for e in entries:
		total += float(e[weight_index])
	var roll := f(run) * total
	for e in entries:
		roll -= float(e[weight_index])
		if roll < 0.0:
			return e
	return entries[-1]


static func shuffled(run: Dictionary, arr: Array) -> Array:
	var a := arr.duplicate()
	for k in range(a.size() - 1, 0, -1):
		var j := i(run, 0, k)
		var t = a[k]
		a[k] = a[j]
		a[j] = t
	return a
