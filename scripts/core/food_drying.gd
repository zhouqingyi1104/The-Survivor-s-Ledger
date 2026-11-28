extends RefCounted
## 共用一面竹匾。初晒后可以收起干透的部分，也可以翻匾占用一天，把厚片一起收进柜里。
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const DAY := 1440
const RECIPES := {
	"grain": {"name": "蒸晒杂粮饼", "needs": {"millet": 1, "water": 1}, "fuel": 1,
		"days": 1, "item": "millet_cake", "first": 3, "full": 5},
	"radish": {"name": "盐晒萝卜", "needs": {"radish": 3, "salt": 1}, "fuel": 0,
		"days": 2, "item": "pickles", "first": 2, "full": 3},
}
const ENERGY := {"start": 4, "turn": 2, "take": 0}


static func ready_at(t: int) -> String:
	var clock := (t + 360) % DAY
	return "第 %d 日 %02d:%02d" % [1 + int(t / DAY), int(clock / 60), clock % 60]


static func summary(run: Dictionary) -> String:
	var batch: Dictionary = run.get("drying_batch", {})
	if batch.is_empty():
		return "空匾"
	var recipe: Dictionary = RECIPES[batch.kind]
	var stage := "可收" if int(run.t) >= int(batch.ready) else "%s 可收" % ready_at(batch.ready)
	return "%s · %s" % [recipe.name, stage]


static func block(run: Dictionary, action: String, kind: String, fuel: Dictionary) -> String:
	var batch: Dictionary = run.get("drying_batch", {})
	if action == "start":
		if not RECIPES.has(kind): return "没有这道晒方。"
		if not batch.is_empty(): return "匾上还有一批，收起才能再铺。"
		var recipe: Dictionary = RECIPES[kind]
		for id in recipe.needs:
			var missing: int = int(recipe.needs[id]) - Inv.count(run.home, id)
			if missing > 0:
				return "还缺%s ×%d。" % [Data.item_name(id), missing]
		if int(recipe.fuel) > 0 and fuel.is_empty(): return "蒸粮要一捆柴，或一筐炭。"
		return ""
	if batch.is_empty(): return "晒匾空着。"
	if int(run.t) < int(batch.ready): return "%s才晒好。" % ready_at(batch.ready)
	if action == "turn" and batch.turned: return "整匾已翻晒过，可以收了。"
	return ""


static func apply(run: Dictionary, action: String, kind: String, fuel: Dictionary) -> void:
	State.add_attr(run, "energy", -float(ENERGY[action]))
	if action == "start":
		var recipe: Dictionary = RECIPES[kind]
		Inv.take_all(run.home, recipe.needs)
		Inv.take_all(run.home, fuel)
		run.drying_batch = {"kind": kind, "ready": int(run.t) + int(recipe.days) * DAY, "turned": false}
		State.note(run, "灶边铺了一匾%s，%s可收。" % [recipe.name, ready_at(run.drying_batch.ready)])
		return
	var batch: Dictionary = run.drying_batch
	var recipe: Dictionary = RECIPES[batch.kind]
	if action == "turn":
		batch.turned = true
		batch.ready = int(run.t) + DAY
		State.note(run, "把%s的厚片翻了面，%s能收全匾。" % [recipe.name, ready_at(batch.ready)])
	else:
		var quantity := int(recipe.full if batch.turned else recipe.first)
		Inv.add(run.home, recipe.item, quantity)
		run.erase("drying_batch")
		State.note(run, "收起%s，%s ×%d 已入存货，竹匾腾出来了。" % [recipe.name, Data.item_name(recipe.item), quantity])


static func notify_ready(run: Dictionary, previous_t: int) -> void:
	var due := int(run.drying_batch.ready)
	if previous_t < due and int(run.t) >= due:
		State.note(run, "灶边的%s已经晒好，可以去收匾了。" % RECIPES[run.drying_batch.kind].name)
