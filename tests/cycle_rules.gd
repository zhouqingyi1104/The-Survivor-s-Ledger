extends Node
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const State = preload("res://scripts/core/state.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func source(actor := "ning", kind := "rescue", life := 1) -> Dictionary:
	var status: String = {"promise": "kept", "breach": "broken", "rescue": "helped"}[kind]
	var fact_id: String = {"promise": "trade_2_repay", "breach": "trade_overdue_4", "rescue": "medicine"}[kind]
	return {"actor": actor, "kind": kind, "status": status, "source_life": life, "source_id": "sealed-old-%s-%s" % [actor, kind], "fact_id": fact_id, "fact": Past._cycle_fact(actor, kind, status), "day": 4}

func sample(kind := "rescue", actor := "ning", seed_value := 19001) -> Dictionary:
	var run := State.new_run("scholar", State.new_meta(), seed_value)
	Past.state(run).generation = 4
	run.cycle_inquiry = {"schema": 1, "sources": [source(actor, kind)]}
	run.phase = "post"
	run.pday = 3
	run.t = 2 * 1440 + 120
	run.home = {"rice": 20, "water": 20, "wood": 20, "firewood": 20, "mugwort": 20}
	run.silver = 10000
	run.attrs.energy = 100
	Cycle.poll(run)
	return run

func current(run: Dictionary) -> Dictionary:
	return Cycle.state(run).cases[0]

func choose(run: Dictionary, action: String) -> String:
	return Cycle.act(run, str(current(run).id), action, str(Cycle.view(run).token))

func finish(run: Dictionary) -> String:
	var b: Dictionary = run.busy.duplicate(true)
	run.t = int(b.end)
	run.pday = int(run.t) / 1440 + 1
	# Same order as Post.advance: clocks, then completed busy is removed.
	Cycle.poll(run)
	run.busy = {}
	return Cycle.complete(run, b.data)

func verified(kind := "rescue", actor := "ning", seed_value := 19001) -> Dictionary:
	var run := sample(kind, actor, seed_value)
	check(choose(run, "inquire") == "", "Could not start actual inquiry")
	check(finish(run) != "" and current(run).stage == "interviewed", "Inquiry did not finish before verification")
	check(choose(run, "verify") == "", "Could not start paid verification")
	check(finish(run) != "" and current(run).stage == "verified", "Actual verification did not create current evidence")
	return run

func protected(run: Dictionary) -> Dictionary:
	return {"home": run.home.duplicate(true), "silver": run.silver, "energy": run.attrs.energy, "trade": run.trade.duplicate(true), "busy": run.busy.duplicate(true), "cycle": run.cycle_inquiry.duplicate(true)}

func test_sources_and_publication() -> void:
	var run := sample()
	check(Cycle.state(run).cases.size() == 1 and current(run).stage == "lead", "Source did not become one born inquiry")
	check(current(run).deadline_t == 7 * 1440 + 720, "Five-day publication window is wrong")
	check(Past.public_memories(run).is_empty(), "Player dream awakened an NPC")
	check(current(run).evidence.is_empty(), "Publication granted current proof")
	var newborn := State.new_run("scholar", State.new_meta(), 3)
	Past.state(newborn).generation = 4
	newborn.cycle_inquiry = {"schema": 1, "sources": [source(), source("ning", "promise"), source("zhou", "promise"), source("traveler", "breach")]}
	var rng_before: int = newborn.rng_n
	check(Cycle.state(newborn).cases.size() == 2, "Birth sources exceeded two unique actors")
	check(newborn.rng_n == rng_before, "Inquiry consumed shared gameplay RNG")
	check(Cycle.context(newborn).published.is_empty() and Cycle.context(newborn).history.is_empty(), "Private sources leaked before publication")
	check(not JSON.stringify(Cycle.context(newborn)).contains("private_condition") and not JSON.stringify(Cycle.context(newborn)).contains("sealed-old"), "Public AI context contains private provenance or condition")
	var sealed: Dictionary = Cycle.view(newborn).cases[0]
	check(not str(sealed.clue).contains(source().fact) and sealed.options.is_empty(), "Unpublished clue was already revealed")
	var original: Dictionary = Cycle.state(newborn).cases[0].source.duplicate(true)
	newborn.cycle_inquiry.sources.clear()
	check(Cycle.state(newborn).cases[0].source == original, "Born source changed after meta/input changed")
	for mutation in ["future", "self", "text", "fact_id", "status", "fraction", "extra"]:
		var bad := State.new_run("scholar", State.new_meta(), 3)
		Past.state(bad).generation = 4
		var entry := source()
		match mutation:
			"future": entry.source_life = 4
			"self": entry.source_id = Past.state(bad).id
			"text": entry.fact = "AI invented a rescue"
			"fact_id": entry.fact_id = "generic_relation"
			"status": entry.status = "kept"
			"fraction": entry.source_life = 1.5
			"extra": entry["give"] = {"rice": 999}
		bad.cycle_inquiry = {"schema": 1, "sources": [entry]}
		check(Cycle.state(bad).cases.is_empty(), "Rejected provenance accepted: " + mutation)
	var quiet := sample()
	current(quiet).stage = "sealed"
	current(quiet).deadline_t = -1
	quiet.pending_event = "an-existing-scene"
	check(Cycle.poll(quiet) == "" and current(quiet).stage == "sealed" and quiet.pending_event == "an-existing-scene", "Publication overwrote another scene")
	quiet.pending_event = ""
	quiet.t = 3 * 1440 + 120
	quiet.pday = 4
	Cycle.poll(quiet)
	check(current(quiet).stage == "lead" and current(quiet).publish_day == 4 and current(quiet).deadline_t == 8 * 1440 + 720, "Delayed quiet publication shortened promised window")

func test_real_work_and_fragments() -> void:
	var run := sample()
	var before := protected(run)
	check(choose(run, "verify") != "" and protected(run) == before, "Verification skipped actual inquiry")
	check(choose(run, "inquire") == "", "Inquire rejected")
	var work: Dictionary = run.busy.duplicate(true)
	check(current(run).stage == "lead" and current(run).evidence.is_empty(), "Starting inquiry granted free completion")
	run.t = int(work.end) - 1
	check(Cycle.complete(run, work.data) == "" and current(run).stage == "lead", "Early work completion succeeded")
	run.t += 1
	check(Cycle.complete(run, {"id": "wrong", "case_id": current(run).id, "action": "inquire"}) == "", "Wrong work id completed")
	run.busy = {}
	check(Cycle.complete(run, work.data) != "" and current(run).stage == "interviewed", "Completed inquiry produced no local record")
	check(choose(run, "verify_fragment") != "", "Unawakened actor gave fragment shortcut")
	var public := {"actor": "ning", "life": 1, "age": 3, "fact_id": "medicine", "fact": source().fact, "response": ""}
	for key in ["actor", "life", "fact_id"]:
		var fake: Dictionary = public.duplicate(true)
		fake[key] = "zhou" if key == "actor" else (2 if key == "life" else "account")
		Past.state(run).awakenings = [fake]
		before = protected(run)
		check(choose(run, "verify_fragment") != "" and protected(run) == before, "Mismatched public fragment accepted: " + key)
	Past.state(run).awakenings = [public]
	var water := Inv.count(run.home, "water")
	check(choose(run, "verify_fragment") == "" and int(run.busy.end) - int(run.busy.start) == 30 and Inv.count(run.home, "water") == water - 1, "Real matching fragment failed to pay water/time")
	check(current(run).evidence.is_empty(), "Fragment starting work granted proof")
	check(finish(run) != "" and current(run).stage == "verified" and current(run).evidence.condition in ["need", "stable"], "Fragment did not require actual completion")
	check(Past.state(run).get("cycle_receipts", []).is_empty(), "Mere investigation became a prior-life promise or rescue")
	var normal := sample()
	choose(normal, "inquire")
	finish(normal)
	var rice := Inv.count(normal.home, "rice")
	check(choose(normal, "verify") == "" and int(normal.busy.end) - int(normal.busy.start) == 45 and Inv.count(normal.home, "rice") == rice - 1, "Default verification did not pay actual 45m/rice")
	var spent := Inv.count(normal.home, "rice")
	normal.busy = {}
	check(Cycle.poll(normal) != "" and Cycle.state(normal).work.is_empty() and current(normal).stage == "interviewed" and current(normal).evidence.is_empty() and Inv.count(normal.home, "rice") == spent, "Interrupted verification refunded or minted proof")
	check(choose(normal, "verify") == "", "Interrupted verification cannot be retried")
	normal.phase = "dead"
	check(Cycle.poll(normal) != "" and current(normal).evidence.is_empty() and normal.busy.is_empty(), "Death completed/retained investigation work")

func test_every_route_and_delivery() -> void:
	var expected := [
		["promise", "renew", {"rice": 1, "wood": 1}, 0, 60, 6, 2, 1, 1],
		["promise", "small_pact", {"rice": 1}, 0, 30, 4, 1, 0, 2],
		["breach", "pay_repair", {"rice": 2, "water": 1}, 0, 60, 6, 2, 1, 2],
		["breach", "cash_restart", {"rice": 1}, 300, 30, 4, 1, 0, 1],
		["rescue", "help_again", {"mugwort": 2, "water": 1}, 0, 60, 6, 2, 1, 1],
		["rescue", "mutual_help", {"rice": 1, "firewood": 1}, 0, 45, 5, 1, 1, 2],
	]
	for row in expected:
		var run := verified(row[0])
		var c := current(run)
		var actor := str(c.actor)
		var condition: String = c.evidence.condition
		var expected_give: Dictionary = {
			"renew": {"need": {"water": 2}, "stable": {"firewood": 1}},
			"small_pact": {"need": {"water": 1}, "stable": {"wood": 1}},
			"pay_repair": {"need": {"wood": 1}, "stable": {"firewood": 1}},
			"cash_restart": {"need": {"nails": 1}, "stable": {"water": 1}},
			"help_again": {"need": {"rice": 2}, "stable": {"wood": 1}},
			"mutual_help": {"need": {"mugwort": 2}, "stable": {"water": 2}},
		}[row[1]][condition]
		var inv_before: Dictionary = run.home.duplicate(true)
		var silver: int = run.silver
		var energy: int = run.attrs.energy
		var person: Dictionary = Trade.state(run).actors[actor]
		var npc: Dictionary = Npcs.state(run).actors[actor]
		var npc_before: Dictionary = npc.stock.duplicate(true)
		check(choose(run, row[1]) == "", "Actual route failed: " + row[1])
		check(c.stage == "working" and c.delivery.is_empty() and person.trust == 0, "Route granted trust or delivery before finish: " + row[1])
		for item in row[2]: check(Inv.count(run.home, item) == int(inv_before[item]) - int(row[2][item]), "Route material debit wrong: " + row[1] + "/" + item)
		check(run.silver == silver - int(row[3]) and int(run.busy.end) - int(run.busy.start) == int(row[4]) and run.attrs.energy == energy - int(row[5]), "Route cash/time/energy wrong: " + row[1])
		check(finish(run) != "" and c.stage == "resolved" and c.route == row[1], "Actual route did not finish: " + row[1])
		check(person.trust == row[6] and person.favors == row[7], "Route trust/favor wrong: " + row[1])
		for item in row[2]:
			if npc_before.has(item): check(npc.stock[item] == mini(20, int(npc_before[item]) + int(row[2][item])), "Actual gifted focal stock missing: " + row[1])
		check(c.delivery.give == expected_give and int(c.delivery.due_t) == (_day(run) + int(row[8]) - 1) * 1440 + 120, "Locked current-life return wrong: " + row[1])
		check(not Past.state(run).cycle_receipts.is_empty(), "Completed real route left no later-life receipt")
		var after := protected(run)
		check(choose(run, row[1]) != "" and choose(run, "decline") != "" and protected(run) == after, "Resolved route could double/overwrite choice")
		run.t = int(c.delivery.due_t) - 1
		run.pday = int(run.t) / 1440 + 1
		var pre_delivery: Dictionary = run.home.duplicate(true)
		check(Cycle.poll(run) == "" and run.home == pre_delivery and not c.delivery.done, "Return delivered before locked time")
		run.t += 1
		run.pday = int(run.t) / 1440 + 1
		check(Cycle.poll(run) != "" and c.delivery.done, "Return failed with no Director needed")
		for item in expected_give: check(Inv.count(run.home, item) == Inv.count(pre_delivery, item) + int(expected_give[item]), "Return material wrong: " + row[1])
		var delivered: Dictionary = run.home.duplicate(true)
		check(Cycle.poll(run) == "" and run.home == delivered, "Return was awarded twice")
	for kind in ["promise", "breach", "rescue"]:
		var run := sample(kind)
		var before: Dictionary = run.home.duplicate(true)
		var mood: int = run.attrs.mood
		check(choose(run, "decline") == "" and run.home == before and current(run).stage == "resolved", "Explicit decline did not close " + kind)
		check(Trade.state(run).actors.ning.trust == -1 and run.attrs.mood == mood + 2 and current(run).delivery.is_empty(), "Decline lacked declared consequences")

func _day(run: Dictionary) -> int:
	return int(run.t) / 1440 + 1

func test_deadlines_tokens_and_restrictions() -> void:
	var run := verified("promise")
	var c := current(run)
	var stale: String = Cycle.view(run).token
	check(choose(run, "small_pact") == "", "Could not start deadline fixture")
	var b: Dictionary = run.busy.duplicate(true)
	run.busy = {"kind": "something_else", "data": {}}
	run.t = int(b.end)
	check(Cycle.complete(run, b.data) == "", "Wrong busy slot allowed direct completion")
	Cycle.poll(run)
	check(c.stage == "verified" and c.delivery.is_empty(), "Interrupted route granted return")
	check(Cycle.act(run, c.id, "renew", stale) != "", "Stale revision selected another route")
	run.busy = {} # The competing rest/work slot has actually ended before retry.
	run.t = int(c.deadline_t) - 60
	run.pday = _day(run)
	check(choose(run, "renew") == "", "End exactly deadline should be allowed")
	check(finish(run) != "" and c.stage == "resolved", "Exact deadline completion expired early")
	var idle := sample("breach")
	var idle_c := current(idle)
	idle.t = int(idle_c.deadline_t)
	idle.pday = _day(idle)
	Cycle.poll(idle)
	check(idle_c.stage == "expired" and Trade.state(idle).actors.ning.trust == 0 and Past.state(idle).get("cycle_receipts", []).is_empty(), "Uncontacted private dream became NPC resentment or promise breach")
	var contacted := sample("breach")
	choose(contacted, "inquire")
	finish(contacted)
	contacted.t = int(current(contacted).deadline_t)
	contacted.pday = _day(contacted)
	Cycle.poll(contacted)
	check(current(contacted).stage == "expired" and Trade.state(contacted).actors.ning.trust == -1 and Past.state(contacted).get("cycle_receipts", []).is_empty(), "Contacted timeout lacked honest limited consequences")
	var late := verified("promise")
	late.t = int(current(late).deadline_t) - 29
	late.pday = _day(late)
	var before := protected(late)
	check(choose(late, "small_pact") != "" and protected(late) == before, "Too-late route charged resources")
	for key in ["daily", "legacy", "busy", "outside", "sleeping", "pending", "night", "low_energy", "low_material", "low_cash"]:
		var blocked := verified("breach")
		match key:
			"daily": blocked.flags.daily = "2026-10-24"
			"legacy": blocked.cycle_inquiry.legacy = true
			"busy": blocked.busy = {"kind": "rest"}
			"outside": blocked.explore = {"point": "school"}
			"sleeping": blocked.sleeping = true
			"pending": blocked.pending_event = "other-event"
			"night": blocked.t = 2 * 1440 + 721
			"low_energy": blocked.attrs.energy = 0
			"low_material": blocked.home.rice = 0
			"low_cash": blocked.silver = 0
		before = protected(blocked)
		check(choose(blocked, "cash_restart") != "" and protected(blocked) == before, "Blocked route changed state: " + key)
		if key in ["daily", "legacy"]: check(Cycle.context(blocked).published.is_empty() and Cycle.planning(blocked).slots.is_empty(), "Disabled inquiry leaked to AI")
	for disabled in ["daily", "legacy", "closed"]:
		var pending := verified("promise")
		check(choose(pending, "renew") == "", "Could not construct pending completion boundary")
		var callback: Dictionary = pending.busy.data.duplicate(true)
		pending.t = int(pending.busy.end)
		pending.busy = {}
		if disabled == "daily": pending.flags.daily = "2026-10-24"
		else: pending.cycle_inquiry[disabled] = true
		var person: Dictionary = Trade.state(pending).actors.ning.duplicate(true)
		var paid: Dictionary = pending.home.duplicate(true)
		check(Cycle.complete(pending, callback) == "" and Trade.state(pending).actors.ning == person and current(pending).delivery.is_empty(), "Disabled completion granted influence or return: " + disabled)
		check(pending.home == paid and Cycle.state(pending).work.is_empty(), "Disabled completion refunded or retained awardable work: " + disabled)
	var dead := sample("promise")
	dead.attrs.hp = 0
	var dead_before := protected(dead)
	check(choose(dead, "inquire") != "" and protected(dead) == dead_before, "A zero-health caller started investigation")

func test_planning_and_save() -> void:
	var run := sample("promise")
	var c := current(run)
	c.stage = "sealed"
	c.deadline_t = -1
	var slot: Dictionary = Cycle.planning(run).slots[0]
	var row := {"case_id": c.id, "day": 5, "cue": "familiar_dream"}
	check(slot.earliest_day == 4 and slot.latest_day == 6 and Cycle.valid_rows(run, [row]), "Future bounded AI schedule refused")
	for bad in [{"case_id": c.id, "day": 3, "cue": "old_note"}, {"case_id": c.id, "day": 7, "cue": "old_note"}, {"case_id": c.id, "day": 5, "cue": "invented_truth"}, {"case_id": c.id, "day": 5, "cue": "old_note", "truth": "stable"}, {"case_id": "another-life", "day": 5, "cue": "old_note"}]:
		var before: Dictionary = run.cycle_inquiry.duplicate(true)
		check(not Cycle.accept(run, [bad]) and run.cycle_inquiry == before, "AI invalid schedule mutated contract")
	check(not Cycle.valid_rows(run, [row, row]), "AI could schedule same case twice")
	check(Cycle.accept(run, [row]) and c.publish_day == 5 and c.cue == "familiar_dream", "Legal AI planning was discarded")
	check(Cycle.planning(run).slots.is_empty() and not Cycle.accept(run, [{"case_id": c.id, "day": 6, "cue": "old_note"}]), "AI could repeatedly delay a scheduled private case")
	run.t = 4 * 1440 + 120
	run.pday = 5
	Cycle.poll(run)
	var deadline: int = c.deadline_t
	check(not Cycle.accept(run, [{"case_id": c.id, "day": 6, "cue": "old_note"}]) and c.deadline_t == deadline, "AI rewrote published deadline")
	var active := verified("rescue")
	choose(active, "help_again")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(active)))
	check(Cycle.context(saved) == Cycle.context(active), "Actual normalized save changed work or public clue")
	check(finish(saved) != "" and current(saved).stage == "resolved", "Saved work could not finish")
	var due: int = current(saved).delivery.due_t
	var saved_again: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(saved)))
	saved_again.t = due
	saved_again.pday = _day(saved_again)
	check(Cycle.poll(saved_again) != "", "Saved locked return did not deliver")
	var home: Dictionary = saved_again.home.duplicate(true)
	check(Cycle.poll(saved_again) == "" and saved_again.home == home, "Saved delivered return duplicated")
	var ctx := Cycle.context(saved_again)
	check(ctx.size() == 7 and ctx.published.size() == 1 and ctx.published[0].size() == 12 and not JSON.stringify(ctx).contains("private_condition"), "Public context changed closed shape/private truth")
	check(not JSON.stringify(Cycle.context(sample())).contains("need") and not JSON.stringify(Cycle.context(sample())).contains("stable"), "Unknown case truth leaked before verification")

func _ready() -> void:
	Game.no_save = true
	Game.run = {}
	for test in [test_sources_and_publication, test_real_work_and_fragments, test_every_route_and_delivery, test_deadlines_tokens_and_restrictions, test_planning_and_save]:
		test.call()
		if failures > 0: break
	print("Cycle rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
