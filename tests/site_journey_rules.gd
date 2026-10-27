extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const Journey = preload("res://scripts/core/site_journey.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Director = preload("res://scripts/core/director.gd")
const Inv = preload("res://scripts/core/inv.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fixture(pid: String, skilled := false) -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 1001)
	Pre.start_disaster(run)
	if skilled: run.prof.search = 25
	run.pday = 7
	run.t = 6 * 1440 + 120
	run.flags["temple_open"] = true
	Director.state(run).enabled = false
	check(Post.act_explore(run, pid) == "", "departure " + pid)
	return run

func _ready() -> void:
	var answers := {"rice_ruin":"west", "city_god":"water", "school":"know", "pharmacy_ruin":"ginseng", "lumber":"red", "mortuary":"west", "granary":"jia", "taoist_temple":"east"}
	for pid in answers:
		var run := fixture(pid)
		var profile := Journey.profile(pid)
		for stage in profile.stages:
			var careful: Dictionary = stage.choices[0]
			var quick: Dictionary = stage.choices[1]
			var is_obstacle: bool = (pid in ["rice_ruin", "school", "lumber"] and stage.id == "s1") or (pid == "granary" and stage.id == "s4")
			check(bool(stage.obstacle) == is_obstacle and str(careful.description).contains("不可改选") and str(quick.description).contains("不可改选"), pid + " stage choice contract " + str(stage.id))
			if is_obstacle:
				check(str(careful.description).contains("移除现场障碍") and str(quick.description).contains("障碍保留，需绕行"), pid + " obstacle choice contract")
			if str(careful.effect) == "loot":
				check(str(careful.description).contains("留在现场"), pid + " loot retained")
			else:
				check(str(careful.description).contains("不获得物资"), pid + " nonloot outcome")
		var start := int(run.t)
		for stage in profile.stages:
			var result := Post.site_journey_action(run, str(stage.id), "careful")
			check(not result.has("blocked"), pid + " stage " + str(stage.id))
			check(not run.explore.caught, pid + " safe route caught")
		var cache_stage := "s0"
		var cache: Dictionary = Journey.state(run).caches.get(cache_stage, {})
		check(not cache.is_empty(), pid + " cache")
		if not cache.is_empty():
			var item := str(cache.keys()[0])
			check(Post.site_journey_take(run, cache_stage, item, 1) == 1, pid + " take")
			check(Post.site_journey_take(run, cache_stage, item, 1) == 0, pid + " no duplicate")
			check(Post.site_journey_put_back(run, cache_stage, item, 1) == 1 and Post.site_journey_take(run, cache_stage, item, 1) == 1, pid + " put and take")
			check(Post.site_journey_action(run, cache_stage, "careful").has("blocked"), pid + " completed cannot repeat")
		check(not Post.expedition_inspect(run, 0).has("blocked") and not Post.expedition_inspect(run, 1).has("blocked"), pid + " clues")
		check(Post.expedition_answer(run, answers[pid]).get("unlocked", false), pid + " gate")
		for i in run.explore.spots.size():
			var spot: Dictionary = run.explore.spots[i]
			if spot.has("mainline") or spot.has("neighbor"): continue
			var option := "site" if str(spot.name) == str(Explore.SITE_SPOTS[pid]) else "normal"
			check(not Post.search(run, i, option).has("blocked"), pid + " search " + option)
		check(not run.explore.caught, pid + " ordinary search safe")
		var elapsed := int(run.t) - start
		# 这里不运行玩家走路，只校验每项规则行动的计时；实走范围由窗口测试核验。
		var expected: int = profile.stages.size() * int(profile.stages[0].choices[0].minutes) + 20 + 2 * 20 + int(Explore.SITE_MINUTES.get(pid, 20))
		check(elapsed == expected, pid + " action-only elapsed %d expected %d" % [elapsed, expected])
		var return_item := str(profile.stages[0].choices[0].item)
		if pid == "mortuary":
			return_item = "lamp_oil"
			check(Post.site_journey_take(run, "s3", return_item, 1) == 1, pid + " take post-ward loot")
		var before_home := Inv.count(run.home, return_item)
		Post.finish_explore(run)
		check(Inv.count(run.home, return_item) > before_home, pid + " returned loot")
	for pid in answers:
		var run := fixture(pid, true)
		var profile := Journey.profile(pid)
		var start := int(run.t)
		for stage in profile.stages:
			if profile.grade == "hard" and stage.id == "s4": continue
			check(not Post.site_journey_action(run, str(stage.id), "careful").has("blocked"), pid + " skilled stage")
		if pid == "mortuary": check(Post.site_journey_take(run, "s0", "talisman", 1) == 1, "skilled mortuary ward material")
		check(not Post.expedition_inspect(run, 0).has("blocked") and not Post.expedition_inspect(run, 1).has("blocked") and Post.expedition_answer(run, answers[pid]).get("unlocked", false), pid + " skilled puzzle")
		var searched := 0
		for i in run.explore.spots.size():
			var spot: Dictionary = run.explore.spots[i]
			if spot.has("mainline") or spot.has("neighbor"): continue
			if searched == 2 and profile.grade == "hard": check(not Post.site_journey_action(run, "s4", "careful").has("blocked"), pid + " skilled staggered relief")
			var option := "site" if str(spot.name) == str(Explore.SITE_SPOTS[pid]) else "normal"
			check(not Post.search(run, i, option).has("blocked") and not run.explore.caught, pid + " skilled safe search")
			searched += 1
		var expected: int = profile.stages.size() * int(profile.stages[0].choices[0].minutes) + 20 + 3 * 20 + int(Explore.SITE_MINUTES.get(pid, 20))
		check(searched == 4 and int(run.t) - start == expected, pid + " skilled action-only time and four points")
	var bad := fixture("rice_ruin")
	var before := int(bad.t)
	check(Post.site_journey_action(bad, "missing", "careful").has("blocked") and Post.site_journey_action(bad, "s0", "bad").has("blocked") and int(bad.t) == before, "invalid action free")
	bad.explore.only_investigate = true
	check(Post.site_journey_action(bad, "s0", "careful").has("blocked"), "investigation only")
	bad.explore.only_investigate = false
	bad.explore.spots.append({"name": Explore.SITE_SPOTS.rice_ruin, "done":false, "neighbor":"account"})
	bad.explore.spots.append({"name": Explore.SITE_SPOTS.rice_ruin, "done":false, "mainline":"mortuary"})
	check(not Expedition.target_locked(bad, bad.explore.spots.size()-1) and not Expedition.target_locked(bad, bad.explore.spots.size()-2), "story targets reachable")
	var late := fixture("rice_ruin")
	late.t = 6 * 1440 + Post.CURFEW_AT - 2
	check(Post.site_journey_action(late, "s0", "careful").has("blocked") and Journey.state(late).completed.is_empty() and Journey.state(late).caches.is_empty(), "curfew no reward")
	var fatal := fixture("rice_ruin")
	fatal.attrs.hp = 0.6
	fatal.attrs.food = 0
	fatal.attrs.water = 0
	check(Post.site_journey_action(fatal, "s0", "careful").has("blocked") and Journey.state(fatal).completed.is_empty(), "death no reward")
	var saw_event := false
	for i in 30:
		var run := fixture("rice_ruin")
		run.t = 6 * 1440 + Post.EVENT_AT - 2
		run.rng_n = i
		var result := Post.site_journey_action(run, "s0", "careful")
		if run.pending_event != "":
			saw_event = true
			check(result.has("blocked") and Journey.state(run).completed.is_empty() and Journey.state(run).caches.is_empty(), "event no reward")
			break
	check(saw_event, "event fixture")
	var saved := fixture("rice_ruin")
	Post.site_journey_action(saved, "s0", "careful")
	var path := "user://site-journey-%d.json" % OS.get_process_id()
	check(SaveFile.write(path, {"run":saved, "snapshots":{}}).ok, "save")
	var restored: Dictionary = Migrate.save(SaveFile.read(path).data).run
	check(Journey.state(restored).completed.has("s0") and Journey.state(restored).caches.has("s0") and Post.site_journey_action(restored, "s0", "careful").has("blocked"), "load no repeat")
	SaveFile.forget(path)
	var old := fixture("rice_ruin")
	old.explore.erase("journey")
	check(Journey.state(old).completed.is_empty() and not Post.site_journey_action(old, "s0", "careful").has("blocked"), "old in-flight save")
	var quick := fixture("rice_ruin")
	quick.explore.exposure = 95
	var captured := Post.site_journey_action(quick, "s0", "quick")
	check(captured.get("caught", false) and quick.explore.caught and Journey.state(quick).caches.is_empty() and str(captured.text).contains("增加5"), "quick capture destroys unclaimed cache and reports actual exposure")
	var restock := fixture("rice_ruin")
	check(not Post.site_journey_action(restock, "s0", "careful").has("blocked"), "visit stage before ordinary searches")
	Post.finish_explore(restock)
	check(Explore.point_block(restock, "rice_ruin") != "", "stage only visit consumes restock")
	var saw_boundary := false
	for i in 30:
		var run := fixture("rice_ruin")
		run.t = 6 * 1440 + Post.EVENT_AT - int(Journey.profile("rice_ruin").stages[0].choices[0].minutes)
		run.rng_n = i
		var result := Post.site_journey_action(run, "s0", "careful")
		if run.pending_event != "":
			saw_boundary = true
			check(not result.has("blocked") and Journey.state(run).completed.has("s0") and Post.site_journey_action(run, "s1", "careful").has("blocked"), "event at completion settles but blocks next action")
			break
	check(saw_boundary, "completion event fixture")
	print("Site journey: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
