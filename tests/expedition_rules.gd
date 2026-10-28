extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
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

func fixture(pid: String) -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 1001)
	Pre.start_disaster(run)
	run.pday = 7
	run.t = 6 * 1440 + 120
	run.flags["temple_open"] = true
	Director.state(run).enabled = false
	check(Post.act_explore(run, pid) == "", "departure " + pid)
	return run

func target(run: Dictionary) -> int:
	for idx in run.explore.spots.size():
		var spot: Dictionary = run.explore.spots[idx]
		if not spot.has("mainline") and not spot.has("neighbor") and str(spot.name) == str(Explore.SITE_SPOTS[run.explore.point]): return idx
	return -1

func _ready() -> void:
	var answers := {"rice_ruin": "west", "city_god": "water", "school": "know", "pharmacy_ruin": "ginseng", "lumber": "red", "mortuary": "west", "granary": "jia", "taoist_temple": "east"}
	for pid in answers:
		var run := fixture(pid)
		var p := Expedition.profile(pid)
		var i := target(run)
		check(i >= 0 and p.clues.size() == 2 and p.choices.size() == 3 and not p.has("answer"), pid + " profile")
		if i < 0: continue
		var before := int(run.t)
		check(Post.search(run, i).has("blocked") and Explore.search(run, i).has("blocked") and int(run.t) == before and not run.explore.spots[i].done, pid + " lock cannot be bypassed")
		check(Post.expedition_answer(run, str(answers[pid])).has("blocked") and int(run.t) == before, pid + " no blind answer")
		check(not Post.expedition_inspect(run, 0).has("blocked") and int(run.t) == before + p.inspect_minutes, pid + " inspect first")
		before = int(run.t)
		check(not Post.expedition_inspect(run, 0).has("blocked") and int(run.t) == before, pid + " repeat clue free")
		check(not Post.expedition_inspect(run, 1).has("blocked"), pid + " inspect second")
		var wrong := ""
		for c in p.choices:
			if str(c.id) != str(answers[pid]): wrong = str(c.id); break
		before = int(run.t)
		var exposure := int(run.explore.exposure)
		var res := Post.expedition_answer(run, wrong)
		check(not res.unlocked and not res.has("blocked") and int(run.t) == before + p.answer_minutes and int(run.explore.exposure) == exposure + p.wrong_exposure and int(Expedition.state(run).attempts) == 1, pid + " wrong cost and retry")
		before = int(run.t)
		check(Post.expedition_answer(run, "invalid").has("blocked") and int(run.t) == before, pid + " invalid choice")
		res = Post.expedition_answer(run, str(answers[pid]))
		check(res.unlocked and Expedition.state(run).unlocked and not Expedition.target_locked(run, i), pid + " solve")
		before = int(run.t)
		check(Post.expedition_answer(run, str(answers[pid])).unlocked and int(run.t) == before, pid + " duplicate completion")
		check(not Post.search(run, i).has("blocked") and run.explore.spots[i].done, pid + " accessible after solve")
	var old := fixture("rice_ruin")
	old.explore.erase("expedition")
	check(Expedition.state(old).clues == [false, false] and Expedition.target_locked(old, target(old)), "old in-flight save initializes locked")
	old.explore.spots.append({"name": Explore.SITE_SPOTS.rice_ruin, "done": false, "neighbor": "account"})
	old.explore.spots.append({"name": Explore.SITE_SPOTS.rice_ruin, "done": false, "mainline": "mortuary"})
	check(not Expedition.target_locked(old, old.explore.spots.size() - 1) and not Expedition.target_locked(old, old.explore.spots.size() - 2), "independent story objectives")
	Post.expedition_inspect(old, 0)
	var path := "user://expedition-rules-%d.json" % OS.get_process_id()
	check(SaveFile.write(path, {"run": old, "snapshots": {}}).ok, "save")
	var reload: Dictionary = Migrate.save(SaveFile.read(path).data).run
	check(Expedition.state(reload).clues == [true, false] and not Expedition.state(reload).unlocked, "saved clue")
	Post.expedition_inspect(reload, 1)
	Post.expedition_answer(reload, "west")
	check(SaveFile.write(path, {"run": reload, "snapshots": {}}).ok, "save solved")
	var solved: Dictionary = Migrate.save(SaveFile.read(path).data).run
	check(Expedition.state(solved).unlocked, "saved unlocked")
	SaveFile.forget(path)
	var old_loot := fixture("rice_ruin")
	var old_idx := target(old_loot)
	old_loot.explore.spots[old_idx].done = true
	old_loot.explore.spots[old_idx]["loot"] = {"rice": 2}
	old_loot.explore.erase("expedition")
	check(SaveFile.write(path, {"run": old_loot, "snapshots": {}}).ok, "write legacy in-flight loot")
	var restored_old: Dictionary = Migrate.save(SaveFile.read(path).data).run
	check(Expedition.state(restored_old).unlocked and not Expedition.target_locked(restored_old, old_idx), "legacy searched target remains reachable")
	check(Explore.take(restored_old, old_idx, "rice", 1) == 1 and Inv.count(restored_old.explore.bag, "rice") == 1, "legacy loot recovered")
	var old_loot_only := old_loot.duplicate(true)
	old_loot_only.explore.spots[old_idx].done = false
	old_loot_only.explore.erase("expedition")
	check(Expedition.state(old_loot_only).unlocked, "legacy retained loot signals already reached")
	SaveFile.forget(path)
	Post.finish_explore(solved)
	check(solved.explore.is_empty(), "leaving clears local state")
	check(Post.act_explore(solved, "rice_ruin") == "" and not Expedition.state(solved).unlocked and Expedition.state(solved).clues == [false, false], "next visit resets")
	var late := fixture("rice_ruin")
	late.t = 6 * 1440 + Post.CURFEW_AT - 2
	check(Post.expedition_inspect(late, 0).has("blocked") and not Expedition.state(late).clues[0] and late.explore.get("curfew_due", false), "curfew interrupts clue")
	var late_answer := fixture("rice_ruin")
	Expedition.state(late_answer).clues = [true, true]
	late_answer.t = 6 * 1440 + Post.CURFEW_AT - 2
	check(Post.expedition_answer(late_answer, "west").has("blocked") and not Expedition.state(late_answer).unlocked and int(Expedition.state(late_answer).attempts) == 0, "curfew interrupts answer")
	var caught := fixture("rice_ruin")
	Expedition.state(caught).clues = [true, true]
	caught.explore.exposure = 95
	var caught_res := Post.expedition_answer(caught, "east")
	check(caught_res.caught and caught.explore.caught and not Expedition.state(caught).unlocked and str(caught_res.text).contains("增加 5"), "wrong answer can cause capture and reports actual exposure")
	var fatal := fixture("rice_ruin")
	Expedition.state(fatal).clues = [true, true]
	fatal.t = 6 * 1440 + 300
	fatal.attrs.hp = 0.6
	fatal.attrs.food = 0
	fatal.attrs.water = 0
	check(Post.expedition_answer(fatal, "west").has("blocked") and fatal.phase == "dead" and not Expedition.state(fatal).unlocked, "death interrupts answer")
	var saw_event := false
	for seed_step in 30:
		var event_run := fixture("rice_ruin")
		event_run.t = 6 * 1440 + Post.EVENT_AT - 2
		event_run.rng_n = seed_step
		var event_result := Post.expedition_inspect(event_run, 0)
		if event_run.pending_event != "":
			saw_event = true
			check(event_result.has("blocked") and not Expedition.state(event_run).clues[0], "event interrupts clue")
			break
	check(saw_event, "event fixture triggered")
	var saw_boundary_event := false
	for seed_step in 30:
		var boundary := fixture("rice_ruin")
		boundary.t = 6 * 1440 + Post.EVENT_AT - Expedition.INSPECT_MINUTES
		boundary.rng_n = seed_step
		var boundary_result := Post.expedition_inspect(boundary, 0)
		if boundary.pending_event != "":
			saw_boundary_event = true
			check(not boundary_result.has("blocked") and Expedition.state(boundary).clues[0] and Post.expedition_inspect(boundary, 1).has("blocked"), "clue completed exactly as event arrived, but event blocks further action")
			break
	check(saw_boundary_event, "completion event fixture triggered")
	print("Expedition rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
