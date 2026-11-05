extends SceneTree
## Real field time across the existing 08:00 event stop. No UI, network or player save.
## godot --headless --path . --script res://tests/field_time.gd -- --only=outbound

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Events = preload("res://scripts/core/events.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const Inv = preload("res://scripts/core/inv.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Migrate = preload("res://scripts/core/migrate.gd")

const GROUPS := ["outbound", "return", "search", "persistence"]
const DAY := 7
const BASE := (DAY - 1) * 1440
var checks := 0
var failures := 0
var completed := 0
var selected := 0
var first_failure := ""
var save_counter := 0


func _initialize() -> void:
	Data.ensure()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		else:
			check(false, "unknown argument: " + arg)
			finish()
			return
	if not check(only == "" or only in GROUPS, "unknown --only group: " + only):
		finish()
		return
	for group in GROUPS:
		if only == "" or only == group: selected += 1
	for group in GROUPS:
		if only != "" and only != group: continue
		call("test_" + group)
		if failures > 0: break
	if failures == 0: check(selected > 0 and completed == selected, "selected group did not finish")
	finish()


func finish() -> void:
	print("[field_time] checks=%d completed=%d/%d failures=%d" % [checks, completed, selected, failures])
	if first_failure != "": print("[field_time] first failure: " + first_failure)
	quit(1 if failures > 0 else 0)


func check(ok: bool, message: String) -> bool:
	if failures > 0: return false
	checks += 1
	if not ok:
		failures += 1
		first_failure = message
		push_error(message)
	return ok


func canonical(value) -> String:
	return JSON.stringify(Data.normalize(value), "", true, true)


func saved_value(field: String, value) -> String:
	# SaveFile writes JSON at its default number precision. Keep every attribute
	# key/value at that exact wire precision; other fields remain bit-exact.
	if field == "attrs":
		return canonical(JSON.parse_string(JSON.stringify(value, "\t")))
	return canonical(value)


func sample(minute: int) -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 20261105, "normal")
	Pre.start_disaster(run)
	run.pday = DAY
	run.t = BASE + minute
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	for key in ["hp", "food", "water", "mood", "energy", "warmth"]: run.attrs[key] = 80.0
	return run


func reply(run: Dictionary) -> bool:
	if not check(run.pending_event != "", "expected a real pending 08:00 event"): return false
	var event: Dictionary = Events.entry(run)
	# Use a legal no-cost exit so travel/search energy checks exclude event economics.
	for index in range(event.get("choices", []).size() - 1, -1, -1):
		var choice: Dictionary = event.choices[index]
		var fx: Dictionary = choice.get("fx", {})
		if not choice.get("req", {}).is_empty() or float(fx.get("energy", 0)) != 0.0 or not fx.get("items", {}).is_empty() or fx.has("roll"): continue
		if not Events.choice_ok(run, choice): continue
		return check(Events.choose(run, index) == "" and run.pending_event == "", "real event reply did not clear pending")
	return check(false, "event has no legal resource/energy-free exit: " + str(run.pending_event))


func normal_index(run: Dictionary) -> int:
	for index in run.explore.get("spots", []).size():
		var spot: Dictionary = run.explore.spots[index]
		if not spot.get("done", false) and not spot.has("mainline") and not spot.has("neighbor") and not Expedition.target_locked(run, index): return index
	return -1


func travel(run: Dictionary, direction: String, start: int, remaining: int) -> bool:
	return check(not run.busy.is_empty() and str(run.busy.get("kind", "")) == "travel"
		and int(run.busy.get("start", -1)) == BASE + start and int(run.busy.get("end", -1)) == BASE + start + 60
		and int(run.busy.end) - int(run.t) == remaining and str(run.busy.get("data", {}).get("direction", "")) == direction,
		"travel clock missing/wrong: %s start=%d remaining=%d busy=%s" % [direction, start, remaining, canonical(run.busy)])


func blocked_search(run: Dictionary, index: int, label: String) -> bool:
	var before := canonical(run)
	var result := Post.search(run, index)
	return check((result.is_empty() or str(result.get("blocked", "")) != "") and canonical(run) == before, label)


func test_outbound() -> void:
	var run := sample(90) # 07:30, travel must end at 08:30.
	var energy := float(run.attrs.energy)
	if not check(Post.act_explore(run, "rice_ruin") == "" and int(run.t) == BASE + 120 and run.pending_event != "", "07:30 departure did not stop at the real 08:00 event"): return
	if not travel(run, "out", 90, 30): return
	if not check(is_equal_approx(float(run.attrs.energy), energy - 14.0 - 0.6) and run.today.actions.count("explore") == 1,
		"departure did not charge the existing 6+8 effort exactly once plus 30-minute upkeep"): return
	var index := normal_index(run)
	if not check(index >= 0, "departure has no ordinary unlocked search point"): return
	var locked := canonical(run)
	for attempt in 2:
		if not check(Post.advance(run, 60) == "blocked" and canonical(run) == locked, "unanswered event advanced/restarted travel attempt %d" % attempt): return
	if not blocked_search(run, index, "pending outbound event allowed search or mutated state"): return
	if not reply(run): return
	if not check(Post.advance(run, 29) == "" and int(run.t) == BASE + 149, "answered event lost remaining 29 travel minutes"): return
	if not travel(run, "out", 90, 1): return
	if not blocked_search(run, index, "08:29 allowed search before arrival"): return
	if not check(Post.advance(run, 1) == "" and run.busy.is_empty() and int(run.t) == BASE + 150, "08:30 did not finish departure"): return
	if not check(is_equal_approx(float(run.attrs.energy), energy - 14.0 - 1.2), "resuming departure charged fixed effort again"): return
	var started := int(run.t)
	var found := Post.search(run, index)
	if not check(not found.get("found", {}).is_empty() and run.explore.spots[index].done and int(run.t) == started + 20, "arrived player cannot perform real 20-minute search"): return
	# A full uninterrupted journey keeps 60 minutes per leg and no return effort charge.
	var normal := sample(180)
	energy = float(normal.attrs.energy)
	if not check(Post.act_explore(normal, "rice_ruin") == "" and int(normal.t) == BASE + 240 and normal.busy.is_empty(), "uninterrupted departure changed 60-minute duration"): return
	if not check(is_equal_approx(float(normal.attrs.energy), energy - 14.0 - 1.2), "uninterrupted departure effort differs from interrupted trip"): return
	var home := canonical(normal.home)
	var report := Post.finish_explore(normal)
	if not check(not report.is_empty() and normal.explore.is_empty() and normal.busy.is_empty() and int(normal.t) == BASE + 300, "uninterrupted return changed 60-minute duration"): return
	if not check(canonical(normal.home) == home and is_equal_approx(float(normal.attrs.energy), energy - 14.0 - 2.4), "empty return granted goods or added fixed effort"): return
	# Travel ending exactly at 08:00 completes before the event and never needs extra minutes.
	var exact := sample(60)
	if not check(Post.act_explore(exact, "rice_ruin") == "" and int(exact.t) == BASE + 120 and exact.busy.is_empty() and exact.pending_event != "", "travel finishing exactly at 08:00 lost completion"): return
	if not reply(exact): return
	index = normal_index(exact)
	if not check(index >= 0 and not Post.search(exact, index).get("found", {}).is_empty() and int(exact.t) == BASE + 140, "completed boundary trip required extra travel or prevented search"): return
	completed += 1


func return_fixture() -> Dictionary:
	var run := sample(0)
	if not check(Post.act_explore(run, "rice_ruin") == "" and int(run.t) == BASE + 60 and run.busy.is_empty(), "return setup departure failed"): return {}
	var index := normal_index(run)
	if not check(index >= 0, "return setup lacks ordinary point"): return {}
	var result := Post.search(run, index)
	if not check(not result.get("found", {}).is_empty() and int(run.t) == BASE + 80, "return setup actual search failed"): return {}
	for item in result.found:
		if not check(Explore.take(run, index, str(item), int(result.found[item])) == int(result.found[item]), "return setup could not choose carried loot"): return {}
	if not check(not run.explore.bag.is_empty() and Post.advance(run, 10) == "" and int(run.t) == BASE + 90, "return setup did not reach 07:30 with real carried loot"): return {}
	return run


func test_return() -> void:
	var run := return_fixture()
	if failures > 0: return
	var bag: Dictionary = run.explore.bag.duplicate(true)
	var home: Dictionary = run.home.duplicate(true)
	var energy := float(run.attrs.energy)
	var result := Post.finish_explore(run)
	if not check(result.get("bag", {}) == bag and int(run.t) == BASE + 120 and run.pending_event != "", "07:30 real return did not stop at 08:00 with the selected bag"): return
	if not travel(run, "return", 90, 30): return
	if not check(is_equal_approx(float(run.attrs.energy), energy - 0.6), "interrupted return added fixed effort cost"): return
	var locked := canonical(run)
	if not check(Post.advance(run, 60) == "blocked" and canonical(run) == locked, "unanswered return event advanced time"): return
	if not reply(run): return
	var settled := canonical(run)
	if not check(Post.act_rest(run) != "" and Post.act_explore(run, "school") != "" and Post.finish_explore(run).is_empty()
		and canonical(run) == settled, "return accepted housework/new departure/re-entry or granted duplicate goods"): return
	if not check(Post.advance(run, 29) == "" and int(run.t) == BASE + 149, "return lost its remaining minutes"): return
	if not travel(run, "return", 90, 1): return
	if not check(Post.can_act(run, 0) != "" and Post.finish_explore(run).is_empty(), "08:29 return accepted another action"): return
	if not check(Post.advance(run, 1) == "" and int(run.t) == BASE + 150 and run.busy.is_empty() and run.explore.is_empty()
		and not run.get("neighbor_travel", false), "08:30 return did not complete/reset travel guard"): return
	if not check(Post.can_act(run, 0) == "" and is_equal_approx(float(run.attrs.energy), energy - 1.2), "completed return remains blocked or charged effort again"): return
	var expected := home.duplicate(true)
	Inv.add_all(expected, bag)
	if not check(run.home == expected, "return did not add exactly the chosen carried loot once"): return
	settled = canonical(run)
	if not check(Post.finish_explore(run).is_empty() and canonical(run) == settled, "completed return re-entered/granted loot twice"): return
	completed += 1


func test_search() -> void:
	var run := sample(50)
	if not check(Post.act_explore(run, "rice_ruin") == "" and int(run.t) == BASE + 110 and run.busy.is_empty(), "search setup did not arrive at 07:50"): return
	var index := normal_index(run)
	if not check(index >= 0, "search setup has no ordinary point"): return
	var energy := float(run.attrs.energy)
	var xp := int(run.prof.search)
	var result := Post.search(run, index)
	if not check(int(run.t) == BASE + 120 and run.pending_event != "" and str(result.get("blocked", "")) != "", "07:50 ordinary search did not report real 08:00 interruption"): return
	if not check(not run.explore.spots[index].done and not run.explore.spots[index].has("loot") and result.get("found", {}).is_empty()
		and int(run.prof.search) == xp and is_equal_approx(float(run.attrs.energy), energy - 0.2), "unfinished ordinary search granted loot/done/xp or charged fixed search effort"): return
	if not blocked_search(run, index, "unanswered search event accepted a retry"): return
	if not reply(run): return
	energy = float(run.attrs.energy)
	result = Post.search(run, index)
	if not check(int(run.t) == BASE + 140 and not result.get("found", {}).is_empty() and run.explore.spots[index].done
		and run.explore.spots[index].loot == result.found and int(run.prof.search) == xp + 2
		and is_equal_approx(float(run.attrs.energy), energy - 4.0 - 0.4), "retry did not pay a fresh full 20 minutes/one effort cost before granting loot and xp"): return
	if not blocked_search(run, index, "completed point allowed repeat time/RNG/loot/xp"): return
	# A normal search completing exactly at the event keeps its single earned result.
	var exact := sample(40)
	if not check(Post.act_explore(exact, "rice_ruin") == "" and int(exact.t) == BASE + 100, "exact-completion setup failed"): return
	index = normal_index(exact)
	if not check(index >= 0, "exact-completion setup lacks ordinary point"): return
	xp = int(exact.prof.search)
	energy = float(exact.attrs.energy)
	result = Post.search(exact, index)
	if not check(int(exact.t) == BASE + 120 and exact.pending_event != "" and exact.explore.spots[index].done
		and not result.get("found", {}).is_empty() and exact.explore.spots[index].loot == result.found
		and int(exact.prof.search) == xp + 2 and is_equal_approx(float(exact.attrs.energy), energy - 4.0 - 0.4), "07:40 search finishing exactly at 08:00 did not settle exactly once"): return
	var first_item := str(result.found.keys()[0])
	if not check(Explore.take(exact, index, first_item, 1) == 0, "pending event allowed collecting boundary loot"): return
	if not reply(exact): return
	if not check(Explore.take(exact, index, first_item, 1) == 1, "earned boundary loot unavailable after answer"): return
	if not blocked_search(exact, index, "boundary result granted twice after reply"): return
	# Reject bad indices, finished points and the real locked signature atomically.
	var invalid := sample(180)
	if not check(Post.act_explore(invalid, "rice_ruin") == "", "invalid-target setup failed"): return
	Expedition.state(invalid)
	for bad_index in [-1, invalid.explore.spots.size()]:
		if not blocked_search(invalid, bad_index, "invalid search index spent time/RNG or changed state"): return
	var locked := -1
	for i in invalid.explore.spots.size():
		if Expedition.target_locked(invalid, i): locked = i; break
	if not check(locked >= 0, "fixture lacks the real locked expedition target"): return
	if not blocked_search(invalid, locked, "locked target spent time/RNG or changed state"): return
	invalid.explore.erase("expedition")
	if not blocked_search(invalid, locked, "first locked rejection created a cache or changed time/RNG/state"): return
	completed += 1


func roundtrip(run: Dictionary, label: String) -> Dictionary:
	save_counter += 1
	var path := OS.get_temp_dir().path_join("ledger-field-time-%d-%d.json" % [OS.get_process_id(), save_counter])
	if not check(SaveFile.write(path, {"run": run, "snapshots": {}}).ok, label + " isolated save write failed"): return {}
	var read := SaveFile.read(path)
	var cleanup := SaveFile.forget(path)
	if not check(read.source == "main" and cleanup.ok and read.data.get("run") is Dictionary, label + " isolated save read/cleanup failed"): return {}
	return Migrate.upgrade(Data.normalize(read.data.run))


func barrier(run: Dictionary, label: String) -> bool:
	var before := canonical(run)
	return check(Post.advance(run, 30) == "blocked" and Post.act_rest(run) != "" and Post.can_act(run, 0) != ""
		and canonical(run) == before, label + " did not block time/housework atomically")


func travel_boundaries() -> bool:
	# Isolate return clock boundaries rather than simulating a full night.
	var wave := sample(Post.WAVE_AT - 30)
	wave.pday = 8 # A real scheduled wave night.
	wave.t = 7 * Post.DAY + Post.WAVE_AT - 30
	# This fixture jumps several days; settle the existing world/crisis catch-up
	# before testing rejection at a fixed, already observed clock.
	Post.trade_refresh(wave)
	Post.trade_refresh(wave)
	var start := int(wave.t)
	wave.busy = {"kind": "travel", "label": "return boundary fixture", "start": start, "end": start + 60,
		"data": {"direction": "return", "point": "rice_ruin"}}
	wave["neighbor_travel"] = true
	# An outstanding policy decision cannot erase or run through an existing trip.
	wave.plan_due = true
	if not barrier(wave, "unanswered policy during return"): return false
	if not check(Post.choose_policy(wave, "hold") == "", "real policy answer failed in return boundary fixture"): return false
	var clock := canonical(wave.busy)
	if not check(Post.advance(wave, 60) == "wave" and int(wave.t) == start + 30 and wave.wave_due
		and canonical(wave.busy) == clock and wave.get("neighbor_travel", false), "22:00 wave erased/restarted return clock"): return false
	if not barrier(wave, "unresolved wave during return"): return false
	var dawn := sample(Post.DAY - 30)
	Post.trade_refresh(dawn)
	Post.trade_refresh(dawn)
	start = int(dawn.t)
	dawn.busy = {"kind": "travel", "label": "dawn return fixture", "start": start, "end": start + 60,
		"data": {"direction": "return", "point": "rice_ruin"}}
	dawn["neighbor_travel"] = true
	clock = canonical(dawn.busy)
	if not check(Post.advance(dawn, 60) == "dawn" and int(dawn.t) == start + 30 and dawn.dawn_due
		and canonical(dawn.busy) == clock and dawn.get("neighbor_travel", false), "dawn erased/restarted return clock"): return false
	if not barrier(dawn, "unread dawn report during return"): return false
	Post.ack_dawn(dawn)
	if not check(int(dawn.pday) == DAY + 1 and canonical(dawn.busy) == clock and int(dawn.busy.end) - int(dawn.t) == 30,
		"new-day acknowledgement lost absolute return deadline"): return false
	if not check(Post.advance(dawn, 29) == "" and Post.is_busy(dawn) and Post.can_act(dawn, 0) != ""
		and int(dawn.busy.end) - int(dawn.t) == 1, "new day skipped remaining return minutes"): return false
	return check(Post.advance(dawn, 1) == "" and dawn.busy.is_empty() and not dawn.get("neighbor_travel", false)
		and int(dawn.t) == start + 60 and Post.can_act(dawn, 0) == "", "return did not finish once at original cross-dawn deadline")


func test_persistence() -> void:
	for direction in ["out", "return"]:
		var run := sample(90) if direction == "out" else return_fixture()
		if failures > 0: return
		if direction == "out":
			if not check(Post.act_explore(run, "rice_ruin") == "", "saved outbound did not start"): return
		else:
			if not check(not Post.finish_explore(run).is_empty(), "saved return did not start"): return
		if not travel(run, direction, 90, 30): return
		var restored := roundtrip(run, direction)
		if failures > 0: return
		for field in ["busy", "pending_event", "explore", "home", "attrs", "t", "rng_n"]:
			if not check(saved_value(field, restored.get(field)) == saved_value(field, run.get(field)), direction + " save lost " + field): return
		var locked := canonical(restored)
		if not check(Post.advance(restored, 30) == "blocked" and canonical(restored) == locked, direction + " restored pending event advanced travel"): return
		if not reply(run) or not reply(restored): return
		if not check(Post.advance(run, 29) == "" and Post.advance(restored, 29) == "", direction + " saved trip did not resume"): return
		if not travel(restored, direction, 90, 1): return
		if not check(Post.advance(run, 1) == "" and Post.advance(restored, 1) == "" and restored.busy.is_empty()
			and int(restored.t) == BASE + 150, direction + " saved trip did not arrive at original deadline"): return
		for field in ["busy", "pending_event", "explore", "home", "attrs", "t", "rng_n", "today"]:
			if not check(saved_value(field, restored.get(field)) == saved_value(field, run.get(field)), direction + " restored outcome diverged in " + field): return
		# A second save after arrival cannot resurrect remaining travel or duplicate goods.
		var arrived := roundtrip(restored, direction + " arrived")
		if failures > 0: return
		if not check(arrived.busy.is_empty() and canonical(arrived.home) == canonical(restored.home)
			and canonical(arrived.explore) == canonical(restored.explore), direction + " post-arrival save duplicated/restarted travel"): return
	# Real fatal damage prevents the remaining trip from completing.
	var fatal := sample(90)
	if not check(Post.act_explore(fatal, "rice_ruin") == "", "fatal departure setup failed"): return
	if not travel(fatal, "out", 90, 30): return
	if not reply(fatal): return
	var fatal_index := normal_index(fatal)
	if not check(fatal_index >= 0, "fatal departure has no ordinary point"): return
	State.hurt(fatal, 1000.0, "event")
	if not check(State.check_death(fatal, "field-time fixture") and fatal.phase == "dead", "fatal damage did not settle death"): return
	var dead := canonical(fatal)
	if not check(Post.advance(fatal, 60) == "dead" and canonical(fatal) == dead, "dead traveler progressed/completed trip"): return
	if not blocked_search(fatal, fatal_index, "dead traveler could search or obtain goods"): return
	if not check(Post.finish_explore(fatal).is_empty() and canonical(fatal) == dead, "dead traveler completed return or banked loot"): return
	if not travel_boundaries(): return
	completed += 1
