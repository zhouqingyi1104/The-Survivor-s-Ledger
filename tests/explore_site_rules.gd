extends Node

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Events = preload("res://scripts/core/events.gd")
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
	check(Post.act_explore(run, pid) == "", "departure " + pid)
	run.explore["expedition"] = {"clues": [true, true], "unlocked": true, "attempts": 1}
	return run

func site_index(run: Dictionary) -> int:
	var signature := str(Explore.SITE_SPOTS[run.explore.point])
	for i in run.explore.spots.size():
		if str(run.explore.spots[i].name) == signature and not run.explore.spots[i].has("mainline") and not run.explore.spots[i].has("neighbor"): return i
	return -1

func _ready() -> void:
	for pid in Explore.SITE_SPOTS:
		var run := fixture(pid)
		var i := site_index(run)
		check(i >= 0 and run.explore.spots.size() <= 6, "missing signature " + pid)
		if i < 0: continue
		var rng_before := int(run.rng_n)
		var opts := Explore.site_options(run, i)
		check(opts.size() == 2 and opts[0].id == "normal" and opts[1].id == "site", "options " + pid)
		check(int(run.rng_n) == rng_before, "preview consumed randomness " + pid)
		for j in run.explore.spots.size():
			if j != i and not run.explore.spots[j].has("mainline") and not run.explore.spots[j].has("neighbor"):
				check(Explore.site_options(run, j).size() == 1, "non-signature special " + pid)
		if pid == "mortuary":
			check(opts[1].block != "", "mortuary should need talisman")
			var t := int(run.t)
			check(Post.search(run, i, "site").has("blocked") and int(run.t) == t and not run.explore.spots[i].done, "blocked action mutated")
			Inv.add(run.explore.bag, "talisman", 1)
			run.explore.exposure = 50
		var before := int(run.t)
		var old_mood := State.attr(run, "mood")
		var risk := Explore.exposure_range(run, pid)
		var res := Post.search(run, i, "site")
		check(not res.is_empty() and not res.has("blocked") and run.explore.spots[i].done, "special action " + pid)
		check(int(run.t) == before + int(Explore.SITE_MINUTES.get(pid, 20)), "special minutes " + pid)
		check(run.explore.bag.is_empty(), "special auto packed " + pid)
		if Explore.SITE_ITEMS.has(pid): check(res.found == Explore.SITE_ITEMS[pid] and run.explore.spots[i].loot == res.found, "fixed loot " + pid)
		if pid == "city_god": check(res.found.is_empty() and State.attr(run, "mood") == old_mood + 3, "temple offering")
		if pid == "mortuary": check(Inv.count(run.explore.bag, "talisman") == 0 and int(run.explore.exposure) == 30 + int(res.gain), "ward item and exposure")
		if pid == "granary": check(int(res.gain) >= risk.x + 25 and int(res.gain) <= risk.y + 25, "granary noise")
		if pid == "taoist_temple":
			var after := Explore.exposure_range(run, pid)
			check(after == Vector2i(maxi(0, risk.x - 8), maxi(0, risk.y - 8)), "taoist subsequent risk")
		var snapshot := run.duplicate(true)
		check(snapshot.explore.get("site_used", false), "site choice lost on save copy " + pid)
		before = int(run.t)
		check(Post.search(run, i, "site").is_empty() and int(run.t) == before, "duplicate search " + pid)
		Post.finish_explore(run)
		check(Explore.point_block(run, pid) != "", "immediate repeat visit " + pid)
	var late := fixture("rice_ruin")
	var index := site_index(late)
	late.t = 6 * 1440 + Post.CURFEW_AT - 10
	var interrupted := Post.search(late, index, "site")
	check(late.explore.get("curfew_due", false) and interrupted.has("blocked") and not late.explore.spots[index].done and not late.explore.spots[index].has("loot") and Explore.take(late, index, "rice", 1) == 0, "site action crosses curfew")
	var untouched := -1
	for j in late.explore.spots.size():
		if not late.explore.spots[j].done: untouched = j; break
	var late_t := int(late.t)
	check(untouched >= 0 and Post.search(late, untouched).is_empty() and int(late.t) == late_t, "curfew accepted another search")
	var caught := fixture("granary")
	index = site_index(caught)
	caught.explore.exposure = 90
	var caught_res := Post.search(caught, index, "site")
	check(caught_res.caught and not caught.explore.spots[index].has("loot"), "capture retained site loot")
	var fatal := fixture("granary")
	index = site_index(fatal)
	fatal.explore.exposure = 90
	fatal.attrs.hp = 1.0
	var fatal_res := Post.search(fatal, index, "site")
	check(fatal_res.caught and fatal.phase == "dead" and State.attr(fatal, "hp") <= 0, "fatal capture did not settle death")
	var saw_event := false
	for seed_step in 30:
		var event_run := fixture("rice_ruin")
		index = site_index(event_run)
		event_run.t = 6 * 1440 + Post.EVENT_AT - 10
		event_run.rng_n = seed_step
		var event_result := Post.search(event_run, index, "site")
		if event_run.pending_event != "":
			saw_event = true
			check(event_result.has("blocked") and int(event_run.t) == 6 * 1440 + Post.EVENT_AT and not event_run.explore.spots[index].done and not event_run.explore.spots[index].has("loot") and not event_run.explore.get("site_used", false), "event granted unfinished action")
			var event_data: Dictionary = Events.entry(event_run)
			var resolved := false
			for j in event_data.get("choices", []).size():
				if Events.choice_ok(event_run, event_data.choices[j]) and Events.choose(event_run, j) == "": resolved = true; break
			check(resolved and event_run.pending_event == "", "event could not be resolved")
			if resolved:
				var retry_start := int(event_run.t)
				var retry := Post.search(event_run, index, "site")
				check(not retry.has("blocked") and int(event_run.t) == retry_start + 30 and retry.found == Explore.SITE_ITEMS.rice_ruin, "event retry was free or failed")
			break
	check(saw_event, "event fixture did not trigger")
	var saw_boundary_event := false
	for seed_step in 30:
		var boundary := fixture("rice_ruin")
		index = site_index(boundary)
		boundary.t = 6 * 1440 + Post.EVENT_AT - 30
		boundary.rng_n = seed_step
		var boundary_res := Post.search(boundary, index, "site")
		if boundary.pending_event != "":
			saw_boundary_event = true
			check(int(boundary.t) == 6 * 1440 + Post.EVENT_AT and not boundary_res.has("blocked") and boundary.explore.spots[index].done and boundary_res.found == Explore.SITE_ITEMS.rice_ruin, "event at completion did not settle finished action")
			check(Post.blocked(boundary) and Explore.take(boundary, index, "rice", 1) == 0, "pending event allowed loot transfer")
			var boundary_event: Dictionary = Events.entry(boundary)
			var resolved := false
			for j in boundary_event.get("choices", []).size():
				if Events.choice_ok(boundary, boundary_event.choices[j]) and Events.choose(boundary, j) == "": resolved = true; break
			check(resolved and Explore.take(boundary, index, "rice", 1) == 1, "finished loot unavailable after event")
			break
	check(saw_boundary_event, "completion event fixture did not trigger")
	var saved := fixture("rice_ruin")
	index = site_index(saved)
	Post.search(saved, index, "site")
	var path := "user://explore-site-rules-%d.json" % OS.get_process_id()
	check(SaveFile.write(path, {"run": saved, "snapshots": {}}).ok, "write test save")
	var reload: Dictionary = Migrate.save(SaveFile.read(path).data).run
	check(reload.explore.get("site_used", false) and reload.explore.spots[index].done and Inv.count(reload.explore.spots[index].loot, "rice") == 2, "saved site state lost")
	check(Post.search(reload, index, "site").is_empty() and Explore.take(reload, index, "rice", 1) == 1 and Explore.take(reload, index, "rice", 5) == 1 and Explore.take(reload, index, "rice", 1) == 0, "reload duplicated loot")
	SaveFile.forget(path)
	var old := fixture("rice_ruin")
	index = site_index(old)
	old.explore.erase("site_used")
	old.explore.erase("site_ward")
	check(Post.search(old, index, "site").found == Explore.SITE_ITEMS.rice_ruin, "old in-flight save unavailable")
	print("Explore sites: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
