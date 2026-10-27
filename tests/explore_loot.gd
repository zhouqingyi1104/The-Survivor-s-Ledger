extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Events = preload("res://scripts/core/events.gd")
var failures := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(msg)

func fixture() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 1001)
	Pre.start_disaster(run)
	run.pday = 2
	run.t = 1440 + 120
	return run

func _ready() -> void:
	var run := fixture()
	check(Post.act_explore(run, "rice_ruin") == "", "departure failed")
	var before := int(run.t)
	var result := Post.search(run, 0)
	var spot: Dictionary = run.explore.spots[0]
	check(spot.done and not result.found.is_empty() and spot.loot == result.found, "search must leave discovered loot on site")
	check(run.explore.bag.is_empty() and int(run.t) == before + 20, "search auto-packed or failed to spend time")
	var item := str(result.found.keys()[0])
	var n := int(result.found[item])
	check(Explore.take(run, 0, item, 1) == 1 and Inv.count(run.explore.bag, item) == 1, "partial take failed")
	check(Inv.count(spot.loot, item) == n - 1, "take did not decrement source")
	check(Explore.put_back(run, 0, item, 1) == 1 and Inv.count(spot.loot, item) == n, "put back failed")
	var saved := run.duplicate(true)
	check(Explore.take(saved, 0, item, 999) == n, "saved remaining loot cannot be claimed")
	check(Explore.take(saved, 0, item, 1) == 0, "duplicate take granted loot")
	check(Explore.put_back(saved, 0, item, -1) == 0 and Explore.take(saved, -1, item, 1) == 0, "invalid input accepted")
	var limit := Explore.carry(run)
	run.explore.bag = {"wood": int(ceil(limit / float(Data.item("wood").weight)))}
	check(Explore.take(run, 0, item, 1) == 0, "overfull bag accepted positive weight")
	check(Inv.count(spot.loot, item) == n, "failed take consumed source")
	run.explore.bag = {}
	spot.erase("loot")
	check(Explore.take(run, 0, item, 1) == 0, "old searched spot created loot")
	run.explore.bag[item] = 1
	check(Explore.put_back(run, 0, item, 1) == 1 and Explore.take(run, 0, item, 1) == 1, "old spot could not hold returned item")
	var quest := {"name": "任务", "done": true, "mainline": "mortuary", "loot": {item: 3}}
	run.explore.spots.append(quest)
	var q: int = run.explore.spots.size() - 1
	check(Explore.take(run, q, item, 1) == 0 and Explore.put_back(run, q, item, 1) == 0, "task loot transferred")
	var captured := fixture()
	Post.act_explore(captured, "rice_ruin")
	captured.explore.bag = {"wood": 4}
	captured.explore.exposure = 99
	var caught := Post.search(captured, 0)
	check(caught.caught and captured.explore.caught and Inv.count(captured.explore.bag, "wood") == 2, "capture did not apply original loss")
	check(not captured.explore.spots[0].has("loot") and Explore.take(captured, 0, str(caught.found.keys()[0]), 1) == 0, "captured new loot bypassed loss")
	check(Explore.put_back(captured, 0, "wood", 1) == 0, "captured player could put back")
	var weights := Explore.loot_pool("rice_ruin", "米仓")
	var original: Array = Data.table("map_points").rice_ruin.loot
	check(weights[0][1] == original[0][1] * 3 and weights[3][1] == original[3][1], "grain preference incorrect")
	check(Explore.loot_pool("rice_ruin", "柜台") == original and original[0][1] == 30, "default pool changed or source mutated")
	var prediction := Explore.exposure_range(run, "rice_ruin")
	var rng_before := int(run.rng_n)
	check(prediction == Vector2i(16, 24) and int(run.rng_n) == rng_before, "exposure range or RNG changed")
	for i in 100:
		var gain := Explore.exposure_gain(run, "rice_ruin")
		check(gain >= prediction.x and gain <= prediction.y, "random gain outside prediction")
	State.add_attr(run, "energy", -100)
	State.add_attr(run, "mood", -100)
	var tired := Explore.exposure_range(run, "rice_ruin")
	check(tired == Vector2i(23, 35), "low energy and mood range incorrect")
	var home_before := Inv.count(run.home, item)
	Post.finish_explore(run)
	check(run.explore.is_empty() and Inv.count(run.home, item) == home_before + 1, "return failed to transfer only bag")
	var late := fixture()
	Post.act_explore(late, "rice_ruin")
	late.t = 1440 + Post.CURFEW_AT - 10
	var late_result := Post.search(late, 0)
	check(int(late.t) == 1440 + Post.CURFEW_AT and late.explore.get("curfew_due", false), "search crossed curfew without persistent return marker")
	var late_item := str(late_result.found.keys()[0])
	var late_remaining := Inv.count(late.explore.spots[0].loot, late_item)
	late.explore.bag[late_item] = 1
	check(Explore.take(late, 0, late_item, 1) == 0 and Explore.put_back(late, 0, late_item, 1) == 0, "curfew allowed loot transfer")
	check(Inv.count(late.explore.spots[0].loot, late_item) == late_remaining and Inv.count(late.explore.bag, late_item) == 1, "curfew transfer changed inventory")
	var reloaded := late.duplicate(true)
	check(reloaded.explore.get("curfew_due", false), "curfew marker lost on save copy")
	late.pending_event = "n_cabinet"
	check(Post.finish_explore(late).is_empty() and not late.explore.is_empty(), "return skipped pending event")
	late.pending_event = ""
	late.busy = {"kind": "mainline"}
	check(Post.finish_explore(late).is_empty() and not late.explore.is_empty(), "return skipped unfinished work")
	late.busy = {}
	late.phase = "dead"
	check(Post.finish_explore(late).is_empty() and not late.explore.is_empty(), "dead player returned")
	var cabinet := fixture()
	Neighbor.state(cabinet).stage = "fetch"
	Post.act_explore(cabinet, "pharmacy_ruin")
	cabinet.t = 1440 + Post.CURFEW_AT - 10
	Post.search(cabinet, 0)
	check(cabinet.explore.get("curfew_due", false) and cabinet.pending_event == "n_cabinet", "cabinet and curfew did not coexist")
	check(Post.finish_explore(cabinet).is_empty() and not cabinet.explore.is_empty(), "cabinet was abandoned at curfew")
	check(Events.choose(cabinet, 0) == "" and cabinet.explore.get("curfew_due", false), "cabinet choice lost curfew marker")
	Post.finish_explore(cabinet)
	check(cabinet.explore.is_empty(), "resolved cabinet could not return")
	print("explore loot: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
