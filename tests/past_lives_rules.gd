extends Node
## Rule-only regression: no network, no player save paths, no forced awakenings.
const Past = preload("res://scripts/core/past_lives.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Core = preload("res://scripts/core/director.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Events = preload("res://scripts/core/events.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
var failures := 0
var checks := 0
var completed := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample(meta: Dictionary, seed_value := 555) -> Dictionary:
	var run := State.new_run("escort", meta, seed_value)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	at(run, 1)
	return run

func finish(run: Dictionary, meta: Dictionary) -> bool:
	run.phase = "dead"
	return Past.archive(run, meta)

func archive_fact(meta: Dictionary, actor: String, fact_id: String, fact: String, valence := 1) -> void:
	var run := sample(meta)
	Past.record(run, actor, fact_id, fact, valence)
	check(finish(run, meta), "A completed new life did not archive")

func known_book() -> Dictionary:
	var meta := State.new_meta()
	archive_fact(meta, "ning", "medicine_choice", "前世事实甲：你曾把家中的避瘟散交给阿宁。")
	archive_fact(meta, "zhou", "wood_trade", "前世事实乙：你曾借给老周一根木料。")
	return meta

func scheduled(meta: Dictionary, actor := "") -> Dictionary:
	for seed_value in range(1, 201):
		var run := sample(meta, seed_value)
		for item in run.past_lives.schedule:
			if actor == "": return run
			if str(item.fact.actor) == actor:
				# Select a natural appointment where an earlier due actor does not
				# take this poll. Do not reorder or force the product's schedule.
				var probe: Dictionary = run.duplicate(true)
				at(probe, int(item.day))
				if str(Past.awakening(probe).get("actor", "")) == actor: return run
	check(false, "No naturally scheduled memory found among seeds 1..200 for " + actor)
	return {}

func appointment(run: Dictionary, actor := "") -> Dictionary:
	for item in run.past_lives.schedule:
		if actor == "" or str(item.fact.actor) == actor:
			return item
	return {}

func test_empty_and_legacy() -> void:
	var fresh := Past.fresh_book()
	check(int(fresh.version) == 1 and int(fresh.count) == 0 and fresh.lives.is_empty(), "Fresh memory book is not empty/versioned")
	var old := {"runs": 37, "deaths": 51, "clues": ["c_mortuary"]}
	var legacy := Past.book(old)
	check(int(legacy.count) == 0 and legacy.lives.is_empty(), "Old counters fabricated specific previous lives")
	var run := sample(old)
	check(int(run.past_lives.generation) == 1 and run.past_lives.trace.is_empty(), "Legacy meta did not start with an unproven first life")
	check(run.past_lives.inherited.is_empty() and run.past_lives.schedule.is_empty(), "No-evidence history scheduled a memory fragment")
	check(Past.public_memories(run).is_empty(), "Dormant/empty history leaked into public memories")
	check(Past.awakening(run).is_empty(), "A first life awakened a fabricated memory")
	check(finish(run, old), "An empty first life could not be sealed")
	var next := sample(old)
	check(next.past_lives.schedule.is_empty(), "A life without facts fabricated remembered actions")
	var saved := sample(State.new_meta())
	saved.version = 11
	saved.erase("past_lives")
	var legacy_copy: Dictionary = saved.duplicate(true)
	var migrated := Migrate.upgrade(saved)
	check(int(migrated.version) == Migrate.VERSION and migrated.get("past_lives", null) is Dictionary, "v11 run did not migrate safely")
	check(migrated.past_lives.trace.is_empty() and migrated.past_lives.inherited.is_empty() and migrated.past_lives.schedule.is_empty(), "Migration inferred actions from a pre-feature run")
	check(str(migrated.past_lives.id).begins_with("legacy-") and Migrate.upgrade(legacy_copy).past_lives.id == migrated.past_lives.id, "Migrating the same old save rerolled its life identity")
	completed += 1

func test_identity_archive_and_bounds() -> void:
	var meta := State.new_meta()
	var run := sample(meta, 99)
	var sibling := sample(meta, 99)
	check(str(run.past_lives.id) != "" and run.past_lives.id != sibling.past_lives.id, "Same seed reused the same life identity")
	check(int(run.past_lives.generation) == int(sibling.past_lives.generation), "Unsealed siblings unexpectedly advanced generation")
	var rng_before := int(run.rng_n)
	Past.record(run, "ning", "medicine_choice", "你曾给过药。", 1)
	Past.record(run, "ning", "medicine_choice", "你曾拒绝求药。", -1)
	check(run.past_lives.trace.size() == 1 and str(run.past_lives.trace[0].fact) == "你曾拒绝求药。", "Same semantic fact appended contradictory duplicates")
	Past.record(run, "zhou", "medicine_choice", "你曾拒绝老周的请求。", -1)
	check(run.past_lives.trace.size() == 2, "Same fact ID for different actors collided")
	check(int(run.rng_n) == rng_before, "Recording facts consumed gameplay RNG")
	var before_settlement := JSON.stringify(run)
	var old_save: Dictionary = Data.normalize(JSON.parse_string(before_settlement))
	check(finish(run, meta), "First completed life did not archive")
	check(int(Past.book(meta).count) == 1 and Past.book(meta).lives.size() == 1, "First archive count is wrong")
	check(not Past.archive(run, meta), "Repeated settlement archived the same run twice")
	check(not finish(old_save, meta), "Reloading a pre-settlement save duplicated a sealed life")
	check(not finish(sibling, meta), "An old generation with another ID duplicated the current life")
	check(int(Past.book(meta).count) == 1, "Rejected duplicate advanced the archive count")
	var capped := sample(State.new_meta())
	for i in 18:
		Past.record(capped, "ning", "fact_%d" % i, "你曾作出第 %d 个选择。" % i, 1)
	check(capped.past_lives.trace.size() <= 12, "Per-life fact count grew beyond 12")
	for i in 10:
		archive_fact(meta, "zhou", "life_%d" % i, "你曾在第 %d 次往事中帮助老周。" % i)
	check(int(Past.book(meta).count) == 11, "Lifetime count was lost when pruning archives")
	check(Past.book(meta).lives.size() <= 8, "Previous-life archive grew beyond eight lives")
	var ancient_save: Dictionary = Data.normalize(JSON.parse_string(before_settlement))
	check(not finish(ancient_save, meta) and int(Past.book(meta).count) == 11, "A pruned ancient save re-archived an old generation")
	completed += 1

func test_inheritance_visibility_and_multi_life() -> void:
	var meta := known_book()
	var run := scheduled(meta, "ning")
	if run.is_empty(): return
	check(int(run.past_lives.generation) == 3, "New life did not follow the sealed archive generation")
	check(run.past_lives.schedule.size() <= 2, "More than two actors scheduled fragments in one life")
	var actors := []
	for item in run.past_lives.schedule:
		check(not item.fact.actor in actors, "Same actor scheduled twice in one life")
		actors.append(item.fact.actor)
	check(Past.public_memories(run).is_empty(), "Unawakened archive exposed a remembered action")
	var before := JSON.stringify(Core.snapshot(run))
	check(not before.contains("前世事实甲") and not before.contains("前世事实乙"), "Director snapshot disclosed dormant previous lives")
	check(Core.snapshot(run).state.get("recollections", null) is Array, "Director snapshot omitted the recollections contract")
	var slot := appointment(run, "ning")
	at(run, int(slot.day))
	var rng_before := int(run.rng_n)
	var event := Past.awakening(run)
	check(not event.is_empty() and event.get("past_memory") is Dictionary and not event.past_memory.is_empty(), "Scheduled local memory did not awaken")
	check(str(event.get("uid", "")).begins_with("world:memory"), "Memory event cannot use the shared event lookup")
	check(run.pending_event == "", "Past.awakening unexpectedly claimed the event UI")
	var public := Past.public_memories(run)
	check(public.size() == 1 and str(public[0].actor) == "ning", "Awakening exposed the wrong actor or multiple private facts")
	if not public.is_empty():
		check(int(public[0].life) == 1 and int(public[0].age) == 2, "A memory from two lives ago lost its provenance/age")
		check(str(public[0].fact).contains("前世事实甲"), "Awakened fact did not come from its archived source")
	check(Core.snapshot(run).state.recollections == public, "AI recollections differ from already awakened facts")
	check(not JSON.stringify(Core.snapshot(run)).contains("前世事实乙"), "Another actor learned a dormant private memory")
	check(int(run.rng_n) == rng_before, "Awakening consumed gameplay RNG")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	check(saved.past_lives.id == run.past_lives.id and saved.past_lives.schedule == run.past_lives.schedule, "Save roundtrip rerolled life identity or appointments")
	check(Past.public_memories(saved) == public, "Save roundtrip forgot which fragment awakened")
	# A later poll may awaken another actor, but can never awaken Ning twice.
	for day in range(int(slot.day), int(slot.day) + 5):
		at(saved, day)
		Past.awakening(saved)
	var count := 0
	for memory in Past.public_memories(saved):
		if memory.actor == "ning": count += 1
	check(count == 1 and Past.public_memories(saved).size() <= 2, "Save/load or repeated polling duplicated a character's fragment")
	completed += 1

func test_safe_appointment() -> void:
	var base := scheduled(known_book())
	if base.is_empty(): return
	var slot := appointment(base)
	for reason in ["pre", "night", "early", "event", "sleep", "busy", "explore", "travel", "dawn", "plan", "wave", "report", "fight"]:
		var run: Dictionary = base.duplicate(true)
		at(run, int(slot.day))
		match reason:
			"pre": run.phase = "pre"
			"night": at(run, int(slot.day), 840)
			"early": at(run, int(slot.day), 60)
			"event": run.pending_event = "taoist"
			"sleep": run.sleeping = true
			"busy": run.busy = {"kind": "rest"}
			"explore": run.explore = {"point": "temple"}
			"travel": run["neighbor_travel"] = true
			"dawn": run.dawn_due = true
			"plan": run.plan_due = true
			"wave": run.wave_due = true
			"report": run.wave_report = {"pending": true}
			"fight": run.fight = {"pending": true}
		var before := JSON.stringify(run)
		check(Past.awakening(run).is_empty(), "Memory interrupted unsafe state: " + reason)
		check(JSON.stringify(run) == before, "Blocked appointment consumed/changed a memory: " + reason)
	completed += 1

func test_offline_choice_and_promises() -> void:
	var run := scheduled(known_book())
	if run.is_empty(): return
	var slot := appointment(run)
	at(run, int(slot.day))
	run.home = {}
	var director := Core.state(run)
	director.enabled = false
	director.promises = [{"day": int(slot.day) + 1, "actor": "zhou", "give": {"firewood": 2}, "text": "原先许下的柴仍会送到。", "done": false}]
	var trace_before: Array = run.past_lives.trace.duplicate(true)
	check(str(Core.poll(run)).begins_with("world:memory"), "Offline/disabled AI prevented a local fragment")
	var event := Core.entry(run)
	check(event.get("past_memory") is Dictionary and not event.past_memory.is_empty() and Events.entry(run) == event, "Shared event UI did not resolve local memory")
	var free := -1
	var paid := -1
	for i in event.get("choices", []).size():
		if event.choices[i].get("req", {}).is_empty():
			if free < 0: free = i
		else:
			paid = i
	check(free >= 0, "Poor player has no resource-free exit from memory")
	if free < 0: return
	if paid >= 0:
		var unavailable := JSON.stringify(run)
		check(Core.choose(run, paid) != "" and JSON.stringify(run) == unavailable, "Unaffordable memory response changed state")
	var revision := int(director.revision)
	check(Core.choose(run, free) == "", "Resource-free fragment response was blocked")
	check(run.pending_event == "" and Core.entry(run).is_empty(), "Responding did not close the memory scene")
	check(int(director.revision) > revision, "Response did not invalidate outdated AI planning")
	check(run.past_lives.trace == trace_before, "A remembered fragment fabricated a new real past-life fact")
	check(director.promises.size() == 1, "Memory response erased an existing promise")
	var public := Past.public_memories(run)
	check(not public.is_empty() and str(public[0].response) != "", "Fragment response was absent from future planning context")
	var saved := JSON.stringify(run)
	check(Core.choose(run, free) != "" and JSON.stringify(run) == saved, "Repeated response applied fragment effects twice")
	var restored: Dictionary = Data.normalize(JSON.parse_string(saved))
	at(restored, int(slot.day) + 1)
	Core.poll(restored)
	check(Inv.count(restored.home, "firewood") == 2, "Existing delayed promise did not survive memory/save/load")
	Core.poll(restored)
	check(Inv.count(restored.home, "firewood") == 2, "Promise delivered twice after a memory")
	completed += 1

func test_rewind_rolls_back_facts() -> void:
	var meta := known_book()
	var run := scheduled(meta)
	if run.is_empty(): return
	Past.record(run, "ning", "before_page", "这一页之前，你已同阿宁说过话。", 1)
	at(run, 1)
	var snapshots := {"1": run.duplicate(true)}
	var stable_id := str(run.past_lives.id)
	var plan: Array = run.past_lives.schedule.duplicate(true)
	Past.record(run, "zhou", "discarded_branch", "后来那一页，你曾交给老周木料。", 1)
	at(run, 2)
	var count_before := int(Past.book(meta).count)
	var restored := Ledger.rewind(run, snapshots, meta)
	check(not restored.is_empty(), "Rewind fixture could not return to an earlier page")
	if restored.is_empty(): return
	check(str(restored.past_lives.id) == stable_id and restored.past_lives.schedule == plan, "Rewind rerolled this life's identity or appointments")
	check(restored.past_lives.trace.size() == 1 and str(restored.past_lives.trace[0].fact_id) == "before_page", "Discarded timeline remained a remembered real action")
	check(int(Past.book(meta).count) == count_before, "Turning a page was archived as another life")
	check(finish(restored, meta), "Rewound completed life could not archive once")
	check(not JSON.stringify(Past.book(meta)).contains("discarded_branch"), "Archived book retained an undone choice")
	completed += 1

func test_daily_fairness() -> void:
	var meta := known_book()
	var run := scheduled(meta)
	if run.is_empty(): return
	run.flags["daily"] = "2026-10-24"
	at(run, int(appointment(run).day))
	var state_before := {"home": run.home.duplicate(), "attrs": run.attrs.duplicate(), "rng": run.rng_n}
	var count_before := int(Past.book(meta).count)
	check(Past.awakening(run).is_empty(), "Daily challenge awakened account-specific history")
	check(Past.public_memories(run).is_empty(), "Daily challenge sent personal history into AI context")
	check(Core.snapshot(run).state.recollections.is_empty(), "Daily director snapshot exposed private prior lives")
	check(run.home == state_before.home and run.attrs == state_before.attrs and run.rng_n == state_before.rng, "Daily memory guard changed resources, attributes, or RNG")
	Past.record(run, "ning", "daily_choice", "每日局里的选择。", 1)
	check(finish(run, meta) and int(Past.book(meta).count) == count_before + 1, "Completed daily run did not update the shared life archive")
	check(Past.book(meta).lives[-1].facts.is_empty() and Past.book(meta).lives[-1].summary.mode == "每日一局", "Daily run fabricated NPC memories instead of a summary")
	completed += 1

func test_real_choice_and_settlement_hooks() -> void:
	var meta := State.new_meta()
	var run := sample(meta)
	Neighbor.state(run).stage = "waiting"
	run.home = {"plague_powder": 1}
	at(run, 2)
	check(Neighbor.poll(run) == "n_request", "Neighbor memory hook fixture failed to open request")
	var choices: Array = Data.table("events").n_request.choices
	var selected := -1
	for i in choices.size():
		if choices[i].id == "donate_home": selected = i
	check(selected >= 0 and Events.choose(run, selected) == "", "Real neighbor donation could not execute")
	check(run.past_lives.trace.any(func(f): return f.actor == "ning"), "Real neighbor choice was not recorded as witnessed fact")
	var before := int(Past.book(meta).count)
	run.phase = "dead"
	Ledger.end_run(run, meta)
	check(int(Past.book(meta).count) == before + 1, "Ledger settlement omitted memory archive")
	Ledger.end_run(run, meta)
	check(int(Past.book(meta).count) == before + 1, "Repeated ledger settlement duplicated memory archive")
	var dynamic := sample(State.new_meta())
	var director := Core.state(dynamic)
	director.active = {"uid": "world:test-choice", "actor": "zhou", "title": "借木", "text": "老周需要一根木料。", "choices": [{"id": "lend", "text": "借木", "result": "你借给老周一根木料。", "req": {"wood": 1}, "relation": 1}]}
	dynamic.pending_event = director.active.uid
	dynamic.home = {"wood": 1}
	check(Core.choose(dynamic, 0) == "", "Real dynamic trade could not execute")
	check(dynamic.past_lives.trace.any(func(f): return f.actor == "zhou"), "Dynamic actor choice was not recorded as a witnessed fact")
	completed += 1

func _ready() -> void:
	Game.no_save = true
	Data.ensure()
	for test in [test_empty_and_legacy, test_identity_archive_and_bounds, test_inheritance_visibility_and_multi_life,
		test_safe_appointment, test_offline_choice_and_promises, test_rewind_rolls_back_facts,
		test_daily_fairness, test_real_choice_and_settlement_hooks]:
		test.call()
	check(completed == 8, "A test group aborted before its completion sentinel (%d/8)" % completed)
	print("Past lives rules: %d/8 completed, %d checks, %d failures" % [completed, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
