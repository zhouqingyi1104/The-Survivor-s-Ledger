extends SceneTree
## C1: the shipped offline decisions, their real economics and the existing 08:00 slot.
## godot --headless --path . --script res://tests/offline_events.gd -- --only=choices
## No autoload API, HTTP fixture, model call, player save or wall-clock randomness.

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Events = preload("res://scripts/core/events.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Migrate = preload("res://scripts/core/migrate.gd")

const ORIGINAL := ["n_request", "n_cabinet", "n_delivery", "n_thanks", "n_distance", "n_lead", "n_evidence",
	"refugee", "deserters", "neighbor_girl", "girl_gift", "taoist", "old_neighbor", "paper_crane",
	"paper_crane_wood", "plague_cough", "foul_well", "stray_dog", "bell", "grain_moths", "night_knock",
	"drift_horde", "frozen_river"]
const LEGACY := ["neighbor_girl", "girl_gift", "paper_crane", "paper_crane_wood", "taoist"]
const GROUPS := ["schema", "choices", "selection", "clock", "persistence"]
var checks := 0
var failures := 0
var finished := 0
var selected := 0
var choice_outcomes := 0
var daily_presentations := 0
var first_failure := ""


func _initialize() -> void:
	Data.ensure()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	if not check(only == "" or only in GROUPS, "unknown --only group: " + only):
		finish()
		return
	for group in GROUPS:
		if only == "" or only == group: selected += 1
	for group in GROUPS:
		if only != "" and only != group: continue
		call("test_" + group)
		if failures > 0: break
	if failures == 0: check(selected > 0 and finished == selected, "a selected group did not finish")
	finish()


func finish() -> void:
	print("[offline_events] checks=%d completed=%d/%d failures=%d" % [checks, finished, selected, failures])
	print("[offline_events] choice_outcomes=%d daily_presentations=%d" % [choice_outcomes, daily_presentations])
	if first_failure != "": print("[offline_events] first failure: " + first_failure)
	quit(1 if failures > 0 else 0)


func check(ok: bool, message: String) -> bool:
	if failures > 0: return false
	checks += 1
	if not ok:
		failures += 1
		first_failure = message
		push_error(message)
	return ok


func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 20261105)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	for key in ["hp", "mood", "energy"]: run.attrs[key] = 50.0
	return run


func at(run: Dictionary, day: int, minute := 110) -> void:
	run.pday = day
	run.t = (day - 1) * Post.DAY + minute


func ordinary_ids() -> Array:
	var ids := []
	var events: Dictionary = Data.table("events")
	for id in events:
		if events[id].get("story", "") == "" and id not in LEGACY: ids.append(id)
	return ids


func added_ids() -> Array:
	var ids := []
	for id in Data.table("events"):
		if id not in ORIGINAL: ids.append(id)
	return ids


func integer(value) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


func validate_req(req, label: String) -> bool:
	if not check(req is Dictionary, label + " req is not an object"): return false
	for key in req:
		if not check(key in ["any_food", "any_grain", "silver"] or Data.table("items").has(key), label + " unknown requirement " + str(key)): return false
		if not check(integer(req[key]) and int(req[key]) > 0, label + " nonpositive/noninteger requirement " + str(key)): return false
	return true


func validate_fx(fx, label: String, depth := 0) -> bool:
	if not check(fx is Dictionary and depth <= 4, label + " invalid effect object/depth"): return false
	for key in fx:
		if not check(key in ["items", "merit", "mood", "hp", "energy", "roll"] or (depth > 0 and key == "result"), label + " unsupported/story-authorizing effect " + str(key)): return false
		match key:
			"items":
				if not check(fx.items is Dictionary and not fx.items.is_empty(), label + " invalid item effects"): return false
				for id in fx.items:
					if not check(Data.table("items").has(id) and integer(fx.items[id]) and int(fx.items[id]) != 0, label + " unknown/noninteger/zero item effect " + str(id)): return false
			"roll":
				var roll = fx.roll
				if not check(roll is Dictionary and roll.has_all(["p", "ok", "fail"]) and roll.size() == 3, label + " invalid probability branch"): return false
				if not check((roll.p is float or roll.p is int) and is_finite(float(roll.p)) and float(roll.p) > 0.0 and float(roll.p) < 1.0, label + " unreachable probability branch"): return false
				if not validate_fx(roll.ok, label + "/ok", depth + 1): return false
				if not validate_fx(roll.fail, label + "/fail", depth + 1): return false
			"result":
				if not check(fx.result is String and not fx.result.strip_edges().is_empty(), label + " blank branch result"): return false
			_:
				if not check(integer(fx[key]), label + " noninteger attribute/merit effect"): return false
	return true


func test_schema() -> void:
	var events: Dictionary = Data.table("events")
	if not check(events.size() == 72 and added_ids().size() == 49, "expected 23 existing + 49 new = 72 entries"): return
	if not check(ordinary_ids().size() == 60, "story/legacy rows counted toward the 60 available random events"): return
	for id in ORIGINAL:
		if not check(events.has(id), "existing pending-save event removed: " + id): return
	var titles := {}
	for id in added_ids():
		var entry: Dictionary = events[id]
		if not check(not str(id).begins_with("n_") and not str(id).begins_with("world:"), "new ordinary event uses a reserved routing prefix: " + id): return
		for key in entry:
			if not check(key in ["title", "text", "min_day", "max_day", "weight", "once", "choices", "req_flag", "not_flag"], id + " unsupported event field " + str(key)): return
		for field in ["title", "text"]:
			if not check(entry.get(field) is String and not str(entry[field]).strip_edges().is_empty(), id + " blank " + field): return
		if not check(not titles.has(entry.title), id + " duplicates new event title"): return
		titles[entry.title] = true
		# Late-life entries may remain available through the existing day-99 window.
		if not check(integer(entry.get("min_day")) and integer(entry.get("max_day")) and int(entry.min_day) >= 1 and int(entry.min_day) <= 20 and int(entry.max_day) <= 99 and int(entry.min_day) <= int(entry.max_day), id + " invalid authored day window"): return
		if not check(integer(entry.get("weight")) and int(entry.weight) > 0, id + " invalid weight"): return
		if entry.has("once") and not check(entry.once is bool, id + " once is not boolean"): return
		for field in ["req_flag", "not_flag"]:
			if entry.has(field) and not check(entry[field] is String and not str(entry[field]).is_empty(), id + " invalid flag condition"): return
		if not check(entry.get("choices") is Array and entry.choices.size() >= 2, id + " fewer than two decisions"): return
		var free := false
		var alternatives := {}
		for index in entry.choices.size():
			var choice = entry.choices[index]
			var label := "%s/%d" % [id, index]
			if not check(choice is Dictionary, label + " choice is not an object"): return
			for key in choice:
				if not check(key in ["text", "hint", "req", "fx", "result"], label + " unsupported choice field " + str(key)): return
			if not check(choice.get("text") is String and not str(choice.text).strip_edges().is_empty(), label + " blank choice text"): return
			if not check(not alternatives.has(choice.text), label + " duplicates choice wording"): return
			alternatives[choice.text] = true
			if not check(choice.get("result", "") is String, label + " result is not text"): return
			if not validate_req(choice.get("req", {}), label): return
			if not validate_fx(choice.get("fx", {}), label): return
			if not check(not str(choice.get("result", "")).strip_edges().is_empty() or choice.get("fx", {}).has("roll"), label + " no result in either deterministic or probability path"): return
			if choice.get("req", {}).is_empty(): free = true
		if not check(free, id + " has no resource-free exit"): return
	finished += 1


## Reduce authored probability leaves to independently check the actual resource receipt.
func outcomes(fx: Dictionary) -> Array:
	var base := fx.duplicate(true)
	base.erase("roll")
	if not fx.has("roll"): return [{"fx": base, "path": [], "result": str(fx.get("result", ""))}]
	var rows := []
	for success in [true, false]:
		var branch: Dictionary = fx.roll.ok if success else fx.roll.fail
		for child in outcomes(branch):
			var combined := base.duplicate(true)
			for key in child.fx:
				if key == "items":
					if not combined.has("items"): combined.items = {}
					for item in child.fx.items: combined.items[item] = int(combined.items.get(item, 0)) + int(child.fx.items[item])
				elif key != "result": combined[key] = int(combined.get(key, 0)) + int(child.fx[key])
			var path := [success]
			path.append_array(child.path)
			rows.append({"fx": combined, "path": path, "result": child.result if child.result != "" else str(branch.get("result", ""))})
	return rows


func cursor_for(run: Dictionary, fx: Dictionary, path: Array) -> int:
	if path.is_empty(): return int(run.rng_n)
	for cursor in 4096:
		var probe := run.duplicate(true)
		probe.rng_n = cursor
		var current := fx
		var matches := true
		for success in path:
			if Rng.chance(probe, float(current.roll.p)) != success:
				matches = false
				break
			current = current.roll.ok if success else current.roll.fail
		if matches: return cursor
	return -1


func free_choice(run: Dictionary) -> int:
	var entry := Events.entry(run)
	for index in entry.get("choices", []).size():
		if entry.choices[index].get("req", {}).is_empty() and Events.choice_ok(run, entry.choices[index]): return index
	return -1


func test_choices() -> void:
	for id in added_ids():
		var entry: Dictionary = Data.table("events")[id]
		for index in entry.choices.size():
			var choice: Dictionary = entry.choices[index]
			var label := "%s/%d" % [id, index]
			var poor := sample()
			poor.home = {}
			poor.silver = 0
			poor.pending_event = id
			if not choice.get("req", {}).is_empty():
				var untouched := JSON.stringify(poor)
				if not check(not Events.choice_ok(poor, choice) and Events.choose(poor, index) != "" and JSON.stringify(poor) == untouched, label + " insufficient cost mutated state"): return
				# All other costs are payable: a later missing ingredient must not
				# charge an earlier one, even for multi-resource exchanges.
				for missing in choice.req:
					var short := sample()
					for item in Data.table("items"): short.home[item] = 100
					short.silver = 100000
					short.pending_event = id
					var quantity := int(choice.req[missing])
					match missing:
						"silver": short.silver = quantity - 1
						"any_food":
							for item in Inv.food_ids(short.home): short.home.erase(item)
							Inv.add(short.home, "flatbread", quantity - 1)
						"any_grain":
							for item in Inv.GRAINS: short.home.erase(item)
							Inv.add(short.home, "rice", quantity - 1)
						_: short.home[missing] = quantity - 1
					var unchanged := JSON.stringify(short)
					if not check(not Events.choice_ok(short, choice) and Events.choose(short, index) != "" and JSON.stringify(short) == unchanged, label + " partially charged when missing " + str(missing)): return
			var energy_cost := -float(choice.get("fx", {}).get("energy", 0))
			if energy_cost > 0.0:
				for available in [0.0, energy_cost - 0.1]:
					var tired := sample()
					for item in Data.table("items"): tired.home[item] = 100
					tired.silver = 100000
					tired.pending_event = id
					tired.attrs.energy = available
					var unchanged := JSON.stringify(tired)
					if not check(not Events.choice_ok(tired, choice) and Events.choose(tired, index) != "" and JSON.stringify(tired) == unchanged, label + " granted work or charged resources with insufficient energy %.1f/%.1f" % [available, energy_cost]): return
				var exact := sample()
				for item in Data.table("items"): exact.home[item] = 100
				exact.silver = 100000
				exact.pending_event = id
				exact.attrs.energy = energy_cost
				if not check(Events.choice_ok(exact, choice) and Events.choose(exact, index) == "" and float(exact.attrs.energy) == 0.0 and exact.pending_event == "", label + " exact energy cost was rejected or not paid in full"): return
			for outcome in outcomes(choice.get("fx", {})):
				var run := sample()
				for item in Data.table("items"): run.home[item] = 100
				run.silver = 100000
				run.pending_event = id
				var expected_store: Dictionary = run.home.duplicate(true)
				var expected_silver := int(run.silver)
				for key in choice.get("req", {}):
					var quantity := int(choice.req[key])
					match key:
						"silver": expected_silver -= quantity
						"any_food": Inv.take_any(expected_store, Inv.food_ids(expected_store), quantity)
						"any_grain": Inv.take_any(expected_store, Inv.GRAINS, quantity)
						_: Inv.add(expected_store, key, -quantity)
				for item in outcome.fx.get("items", {}): Inv.add(expected_store, item, int(outcome.fx.items[item]))
				var expected_attrs: Dictionary = run.attrs.duplicate(true)
				for key in ["hp", "mood", "energy"]:
					expected_attrs[key] = clampf(float(expected_attrs[key]) + float(outcome.fx.get(key, 0)), 0.0, float(State.attr_max(run, key)))
				var merit := int(run.today.get("merit", 0)) + int(outcome.fx.get("merit", 0))
				var cursor := cursor_for(run, choice.get("fx", {}), outcome.path)
				if not check(cursor >= 0, label + " probability leaf unreachable with deterministic cursors"): return
				run.rng_n = cursor
				var guarded := {"flags": run.flags.duplicate(true), "clues": run.known_clues.duplicate(true), "mainline": run.mainline.duplicate(true), "neighbor": run.neighbor.duplicate(true), "raid": run.raid_tonight}
				if not check(Events.choice_ok(run, choice) and Events.choose(run, index) == "", label + " funded choice rejected"): return
				if not check(run.home == expected_store and int(run.silver) == expected_silver, label + " paid cost/item receipt differs from authored amount"): return
				for key in ["hp", "mood", "energy"]:
					if not check(is_equal_approx(float(run.attrs[key]), float(expected_attrs[key])), label + " wrong " + key + " consequence"): return
				if not check(int(run.today.get("merit", 0)) == merit and int(run.rng_n) == cursor + outcome.path.size(), label + " wrong merit/random branch count"): return
				var result := str(outcome.result) if outcome.result != "" else str(choice.get("result", ""))
				if not check(run.pending_event == "" and id in run.seen_events and run.event_result == result, label + " missing resolved/seen/result receipt"): return
				if not check(run.flags == guarded.flags and run.known_clues == guarded.clues and run.mainline == guarded.mainline and run.neighbor == guarded.neighbor and run.raid_tonight == guarded.raid, label + " granted unrelated story or raid state"): return
				var settled := JSON.stringify(run)
				if not check(Events.choose(run, index) == "" and JSON.stringify(run) == settled, label + " duplicate answer applied twice"): return
				choice_outcomes += 1
		var empty := sample()
		empty.pending_event = id
		empty.home = {}
		empty.silver = 0
		empty.attrs.energy = 0.0
		var unchanged := JSON.stringify(empty)
		if not check(Events.choose(empty, -1) != "" and Events.choose(empty, entry.choices.size()) != "" and JSON.stringify(empty) == unchanged, id + " invalid index mutated the event"): return
		var exit_index := free_choice(empty)
		if not check(exit_index >= 0 and Events.choose(empty, exit_index) == "" and empty.pending_event == "", id + " empty household with zero energy cannot leave the event"): return
	finished += 1


func test_selection() -> void:
	var ids := ordinary_ids()
	var events: Dictionary = Data.table("events")
	for id in ids:
		var run := sample()
		var entry: Dictionary = events[id]
		at(run, maxi(1, int(entry.get("min_day", 1))))
		run.seen_events = ids.duplicate()
		run.seen_events.erase(id)
		if entry.has("req_flag"): run.flags[entry.req_flag] = true
		if entry.has("not_flag"): run.flags.erase(entry.not_flag)
		if not check(Events.roll(run) == id, id + " not reachable as the only eligible unseen event"): return
		if entry.get("once", false):
			run.seen_events.append(id)
			if not check(Events.roll(run) != id, id + " once event repeated"): return
			run.seen_events.erase(id)
		if int(entry.get("min_day", 1)) > 1:
			at(run, int(entry.min_day) - 1)
			if not check(Events.roll(run) != id, id + " escaped earliest-day condition"): return
		if int(entry.get("max_day", 999)) < 20:
			at(run, int(entry.max_day) + 1)
			if not check(Events.roll(run) != id, id + " escaped last-day condition"): return
		if entry.has("req_flag"):
			at(run, int(entry.get("min_day", 1)))
			run.flags.erase(entry.req_flag)
			if not check(Events.roll(run) != id, id + " ignored required flag"): return
		if entry.has("not_flag"):
			at(run, int(entry.get("min_day", 1)))
			run.flags[entry.not_flag] = true
			if not check(Events.roll(run) != id, id + " ignored blocking flag"): return
	var exhausted := sample()
	exhausted.seen_events = ids.duplicate()
	# Day 1 cannot already have seen all 60 entries; test reachable later-day exhaustion.
	for day in range(2, 21):
		at(exhausted, day)
		var id := Events.roll(exhausted)
		if not check(id != "" and id in ids and not events[id].get("once", false), "day %d exhausted pool has no repeatable fallback" % day): return
	var pre := sample()
	pre.pday = 0
	var cursor := int(pre.rng_n)
	if not check(Events.roll(pre) == "" and int(pre.rng_n) == cursor, "pre-disaster request consumed a random card"): return
	var raid := sample()
	at(raid, 7)
	raid.raid_tonight = true
	raid.seen_events = ids.duplicate()
	raid.seen_events.erase("deserters")
	if not check(Events.roll(raid) != "deserters", "existing raid got a second deserter demand"): return
	finished += 1


func plan(base: int) -> Dictionary:
	var value: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for event in value.days: event.day += base
	return value


func test_clock() -> void:
	for pending in ["refugee", "n_delivery", "world:existing:3"]:
		var locked := sample()
		at(locked, 3, Post.EVENT_AT)
		locked.pending_event = pending
		var untouched := JSON.stringify(locked)
		if not check(Post._checkpoint(locked, Post.EVENT_AT) == "event" and JSON.stringify(locked) == untouched, "08:00 overwrote/mutated pending " + pending): return
	var neighbor := sample()
	Neighbor.state(neighbor).stage = "waiting"
	Director.state(neighbor).enabled = true
	if not check(Director.accept(neighbor, Director.snapshot(neighbor), plan(1)), "could not stage director behind neighbor"): return
	at(neighbor, 2)
	if not check(Post.advance(neighbor, 10) == "event" and neighbor.pending_event == "n_request", "neighbor did not win the 08:00 slot"): return
	if not check(Events.choose(neighbor, 2) == "" and Post.advance(neighbor, 60) == "" and neighbor.pending_event == "", "random event immediately followed the neighbor slot"): return
	var directed := sample()
	# Accept after day 2's actual 08:00 warning has been published. Accepting
	# at 07:50 makes the not-yet-published crisis correctly invalidate the plan.
	at(directed, 2, Post.EVENT_AT)
	Post.trade_refresh(directed)
	Director.state(directed).enabled = true
	if not check(Director.accept(directed, Director.snapshot(directed), plan(2)), "could not accept deterministic director fixture"): return
	at(directed, 3)
	if not check(Post.advance(directed, 10) == "event" and str(directed.pending_event).begins_with("world:"), "accepted director did not precede random fallback"): return
	if not check(Events.choose(directed, 1) == "" and Post.advance(directed, 60) == "" and directed.pending_event == "", "random event immediately followed the director slot"): return
	var daily := sample()
	var previous := ""
	for day in range(1, 21):
		at(daily, day)
		for key in ["hp", "food", "water", "energy", "mood"]: daily.attrs[key] = 80.0
		if not check(Post.advance(daily, 10) == "event" and daily.pending_event in ordinary_ids(), "no ordinary presentation at day %d 08:00" % day): return
		var id := str(daily.pending_event)
		if not check(id != previous, "adjacent day repeated an event while fresh content remained"): return
		previous = id
		var index := free_choice(daily)
		if not check(index >= 0 and Events.choose(daily, index) == "", "presented day %d event had no exit" % day): return
		if not check(Post.advance(daily, 60) == "" and daily.pending_event == "", "day %d produced a second daily-slot popup" % day): return
		daily_presentations += 1
	if not check(daily_presentations == 20, "density counted rolls instead of 20 actual presentations"): return
	var whole := sample()
	at(whole, 7)
	var split := whole.duplicate(true)
	if not check(Post.advance(whole, 10) == "event" and Post.advance(split, 3) == "" and Post.advance(split, 7) == "event", "split advance missed the exact event boundary"): return
	if not check(whole.pending_event == split.pending_event and int(whole.t) == int(split.t) and int(whole.rng_n) == int(split.rng_n), "split advance changed the daily card"): return
	for key in whole.attrs:
		if not check(is_equal_approx(float(whole.attrs[key]), float(split.attrs[key])), "split advance changed attribute " + key): return
	var busy := sample()
	at(busy, 7)
	busy.busy = {"kind": "rest", "start": int(busy.t), "end": int(busy.t) + 30, "data": {}}
	if not check(Post.advance(busy, 20) == "event" and not busy.busy.is_empty() and int(busy.t) % Post.DAY == Post.EVENT_AT, "daily event failed to stop unfinished work at its boundary"): return
	var completed := sample()
	at(completed, 7)
	completed.busy = {"kind": "rest", "start": int(completed.t) - 110, "end": int(completed.t) + 10, "data": {}}
	if not check(Post.advance(completed, 10) == "event" and completed.busy.is_empty() and "rest" in completed.today.actions, "work finishing exactly at 08:00 lost its result"): return
	finished += 1


func test_persistence() -> void:
	var run := sample()
	at(run, 7)
	var id := Events.roll(run)
	run.pending_event = id
	var path := OS.get_temp_dir().path_join("ledger-offline-events-%d.json" % OS.get_process_id())
	if not check(SaveFile.write(path, {"run": run}).ok, "could not write isolated event save"): return
	var read := SaveFile.read(path)
	var cleanup := SaveFile.forget(path)
	if not check(read.source == "main" and cleanup.ok and read.data.get("run") is Dictionary, "event save read/cleanup failed"): return
	var restored: Dictionary = Migrate.upgrade(Data.normalize(read.data.run))
	if not check(restored.pending_event == id and int(restored.rng_n) == int(run.rng_n), "save changed pending event/card cursor"): return
	var index := free_choice(run)
	if not check(index >= 0 and Events.choose(run, index) == "" and Events.choose(restored, index) == "", "restored pending decision could not settle"): return
	var difference := []
	for field in ["home", "attrs", "seen_events", "event_result", "rng_n"]:
		if run[field] != restored[field]:
			difference.append("%s expected=%s restored=%s" % [field, JSON.stringify(run[field]), JSON.stringify(restored[field])])
			if run[field] is Dictionary and restored[field] is Dictionary:
				for key in run[field]:
					if restored[field].has(key):
						difference.append("%s.%s types=%d/%d equal=%s" % [field, key, typeof(run[field][key]), typeof(restored[field][key]), str(run[field][key] == restored[field][key])])
	# JSON integer-valued attributes normalize from float to int; retain all
	# attribute keys and exact values while comparing their canonical form.
	if not check(run.home == restored.home and Data.normalize(run.attrs) == Data.normalize(restored.attrs) and run.seen_events == restored.seen_events and run.event_result == restored.event_result and int(run.rng_n) == int(restored.rng_n), "restored decision consequence diverged: " + "; ".join(difference)): return
	for day in range(8, 21):
		at(run, day)
		at(restored, day)
		var first := Events.roll(run)
		var second := Events.roll(restored)
		if not check(first == second and int(run.rng_n) == int(restored.rng_n), "save changed seeded selection on day %d" % day): return
		run.seen_events.append(first)
		restored.seen_events.append(second)
	var daily := sample()
	daily.flags["daily"] = "2026-11-05"
	daily.erase("director")
	if not check(not Director.state(daily).enabled, "daily challenge enabled an unseeded director"): return
	var clone: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(daily)))
	for day in range(1, 21):
		at(daily, day)
		at(clone, day)
		var first := Events.roll(daily)
		var second := Events.roll(clone)
		if not check(first != "" and first == second and int(daily.rng_n) == int(clone.rng_n), "daily challenge card is not reproducible on day %d" % day): return
		daily.seen_events.append(first)
		clone.seen_events.append(second)
	finished += 1
