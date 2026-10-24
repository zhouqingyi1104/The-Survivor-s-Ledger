extends Node
const Core = preload("res://scripts/core/crisis.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample(seed_value := 821) -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), seed_value)
	Pre.start_disaster(run)
	run.home = {"rice": 20, "wood": 20, "firewood": 20, "nails": 20, "mugwort": 20, "water": 20}
	return run

func planned(kind := "well_freeze", real := true) -> Dictionary:
	var run := sample()
	check(Core.propose(run, {"kind": kind, "actor": "ning", "warning_day": 2, "real": real}, 1), "Fixture plan rejected")
	at(run, 2)
	check(Core.poll(run) != "", "Fixture warning did not publish")
	return run

func action(run: Dictionary, id: String) -> String:
	return Core.act(run, id, str(Core.view(run).token))

func finish(run: Dictionary) -> String:
	var work: Dictionary = run.busy.duplicate(true)
	run.t = int(work.end)
	run.pday = int(run.t) / 1440 + 1
	run.busy = {}
	return Core.complete(run, work.data)

func test_hidden_and_proposals() -> void:
	var run := sample()
	var base_rng := int(run.rng_n)
	check(Core.view(run).is_empty(), "Unpublished crisis leaked to UI")
	check(Core.context(run).can_plan and Core.context(run).next_warning_day == 2, "Initial local planning slot wrong")
	var dead := sample()
	dead.phase = "dead"
	check(not Core.context(dead).can_plan, "Dead run asked for another AI proposal")
	var proposal := {"kind": "well_freeze", "actor": "ning", "warning_day": 2, "real": false}
	check(Core.valid_proposal(proposal, 1), "Valid proposal rejected")
	check(Core.propose(run, proposal, 1), "Proposal not accepted before warning")
	proposal.kind = "fuel_shortage"
	proposal.real = true
	check(Core.propose(run, proposal, 1), "Unpublished proposal could not be revised")
	check(not JSON.stringify(Core.context(run)).contains("pending") and not JSON.stringify(Core.context(run)).contains('"real"'), "Private planning leaked to known facts")
	at(run, 2)
	check(Core.poll(run) != "", "Planned warning absent")
	var public := Core.view(run)
	check(public.kind == "fuel_shortage" and public.confirmed == "unknown" and public.evidence == "", "Warning exposed hidden truth or lost proposal")
	check(not public.has("real") and not public.has("pending"), "View exposed hidden fields")
	check(public.impact_t == 3 * 1440 + 720 and public.end_t == 5 * 1440 + 120, "Warning deadlines wrong")
	var immutable: Dictionary = Core.state(run).active.duplicate(true)
	check(not Core.propose(run, {"kind": "herb_shortage", "actor": "zhou", "warning_day": 3, "real": false}, 2), "AI rewrote published crisis")
	check(Core.state(run).active == immutable and not Core.context(run).can_plan, "Rejected proposal changed immutable contract")
	check(Core.poll(run) == "", "Repeated poll duplicated warning")
	check(int(run.rng_n) == base_rng, "Crisis consumed main gameplay RNG")
	for invalid in [{}, {"kind": "burn_house", "actor": "ning", "warning_day": 2, "real": true}, {"kind": "well_freeze", "actor": "stranger", "warning_day": 2, "real": true}, {"kind": "well_freeze", "actor": "ning", "warning_day": 2.5, "real": true}, {"kind": "well_freeze", "actor": "ning", "warning_day": 5, "real": true}, {"kind": "well_freeze", "actor": "ning", "warning_day": 2, "real": 1}, {"kind": "well_freeze", "actor": "ning", "warning_day": 2, "real": true, "script": "run"}]:
		check(not Core.valid_proposal(invalid, 1), "Malformed proposal accepted")
	var wrong_slot := sample()
	check(not Core.propose(wrong_slot, {"kind": "well_freeze", "actor": "ning", "warning_day": 3, "real": true}, 1), "AI moved fixed local warning slot")
	var daily := sample()
	daily.flags.daily = "2026-10-24"
	check(not Core.propose(daily, proposal, 1) and not Core.context(daily).can_plan, "Daily run accepted external plan")
	var same_daily := sample()
	same_daily.flags.daily = daily.flags.daily
	at(daily, 2)
	at(same_daily, 2)
	Core.poll(daily)
	Core.poll(same_daily)
	check(Core.state(daily).active == Core.state(same_daily).active, "Same-seed daily crises differed by life identity")
	check(daily.past_lives.trace.is_empty(), "Daily crisis affected future-life memory")

func test_investigation_prepare_truth() -> void:
	for kind in Core.KINDS:
		for real in [true, false]:
			var run := planned(kind, real)
			var energy := State.attr(run, "energy")
			var token := str(Core.view(run).token)
			check(Core.act(run, "investigate", token) == "", "Investigation could not start")
			check(run.busy.kind == "crisis" and int(run.busy.end) - int(run.busy.start) == 30, "Investigation not timed busy work")
			check(State.attr(run, "energy") == energy - 4 and Core.view(run).confirmed == "unknown", "Investigation granted free or immediate knowledge")
			check(Core.act(run, "investigate", token) != "", "Double click started another investigation")
			check(Core.complete(run, run.busy.data) == "" and not Core.view(run).investigated, "Early completion bypassed work time")
			check(finish(run) != "", "Investigation completion absent")
			var v := Core.view(run)
			check(v.investigated and v.confirmed == ("real" if real else "false") and v.evidence != "", "Completed investigation did not establish truth")
			if not real:
				check(v.stage == "resolved" and v.outcome == "false_alarm", "False rumor did not close early")
				check(not Core.context(run).can_plan and Core.state(run).completed.size() == 1, "Early closure created an impossible planning slot or lost final outcome")
				continue
			var before: Dictionary = run.home.duplicate()
			check(action(run, "prepare") == "", "Preparation start rejected")
			for item in Core.CATALOG[kind].prepare: check(Inv.count(run.home, item) == int(before[item]) - int(Core.CATALOG[kind].prepare[item]), "Preparation materials not charged")
			check(not Core.view(run).protected, "Preparation applied before completing work")
			check(finish(run) != "" and Core.view(run).protected, "Finished preparation failed to protect")
			check(action(run, "aid") != "", "Preparation stacked another protection")
			var active: Dictionary = Core.state(run).active
			run.t = int(active.impact_t)
			run.pday = 4
			check(Core.poll(run) != "" and Core.view(run).outcome == "averted", "Prepared true crisis still caused impact")
			check(Core.well_block(run) == "" and Core.market_effect(run, "ning").price_add == 0, "Averted crisis left active system effects")
	var waste := planned("well_freeze", false)
	var wood := Inv.count(waste.home, "wood")
	check(action(waste, "prepare") == "" and finish(waste) != "", "Unverified preparation not possible")
	check(Core.view(waste).confirmed == "unknown", "Prepared rumor leaked private truth")
	at(waste, 4, 720)
	Core.poll(waste)
	check(Core.view(waste).outcome == "false_alarm" and Inv.count(waste.home, "wood") == wood - 1, "False rumor refunded wasted materials")

func test_ignore_impact_and_repair() -> void:
	for kind in Core.KINDS:
		var run := planned(kind)
		var before: Dictionary = run.home.duplicate()
		check(action(run, "ignore") == "" and run.home == before, "Watching charged materials")
		for unavailable in ["investigate", "prepare", "aid"]: check(action(run, unavailable) != "", "Watching did not close future advance choices")
		at(run, 4, 719)
		check(Core.poll(run) == "", "Impact occurred before exact boundary")
		at(run, 4, 720)
		check(Core.poll(run) != "" and Core.view(run).stage == "impact", "Ignored true crisis failed to happen")
		match kind:
			"well_freeze": check(Core.well_block(run) != "", "Real freeze did not block well")
			"fuel_shortage":
				check(Core.market_effect(run, "zhou").price_add == 1 and Core.market_effect(run, "traveler").price_add == 1, "Fuel shortage missed affected contacts")
				check(Core.market_effect(run, "ning").price_add == 0, "Fuel shortage affected wrong contact")
			"herb_shortage": check(Core.market_effect(run, "ning").omit == ["mugwort"] and Core.market_effect(run, "ning").price_add == 1, "Herb shortage did not change real goods")
		check(Core.poll(run) == "", "Impact applied twice")
		before = run.home.duplicate()
		check(action(run, "emergency") == "", "Emergency unavailable after impact")
		for item in Core.CATALOG[kind].emergency: check(Inv.count(run.home, item) == int(before[item]) - int(Core.CATALOG[kind].emergency[item]), "Repair material cost missing")
		check(Core.view(run).stage == "impact", "Repair took effect immediately")
		check(finish(run) != "" and Core.view(run).outcome == "repaired", "Completed repair did not resolve")
		check(Core.well_block(run) == "" and Core.market_effect(run, "ning").omit.is_empty(), "Repair did not lift system effects")
	var enduring := planned()
	at(enduring, 4, 720)
	Core.poll(enduring)
	at(enduring, 6, 119)
	check(Core.poll(enduring) == "" and Core.well_block(enduring) != "", "Natural recovery came early")
	at(enduring, 6)
	check(Core.poll(enduring) != "" and Core.view(enduring).outcome == "endured", "Natural recovery absent")
	check(Core.poll(enduring) == "", "Natural recovery repeated")
	at(enduring, 9)
	check(Core.poll(enduring) != "" and Core.view(enduring).warning_day == 9 and Core.state(enduring).serial == 2, "Next seven-day cycle did not start")

func test_favor_and_interruptions() -> void:
	var run := planned()
	Trade.state(run).actors.ning.favors = 1
	var q := Trade.quote(run, "ning")
	var rice := Inv.count(run.home, "rice")
	check(action(run, "aid") == "", "Favor assistance rejected")
	check(Trade.contact(run, "ning").favors == 0 and Inv.count(run.home, "rice") == rice - 1, "Aid did not atomically spend rice and favor")
	check(Trade.act(run, "ning", "favor", q.id) != "", "Consumed favor left old trade token valid")
	check(not Core.view(run).protected, "Favor aid protected before work completion")
	var paid: Dictionary = run.home.duplicate()
	run.busy = {} # Wave/other interruption clears the real busy action.
	check(Core.poll(run) != "" and not Core.view(run).protected, "Interrupted aid still protected or lacked consequence")
	check(run.home == paid and Trade.contact(run, "ning").favors == 0, "Interrupted work refunded spent materials/favor")
	check(Core.poll(run) == "", "Interruption recorded repeatedly")
	check(action(run, "aid") != "", "Interrupted aid reused already spent favor")
	check(action(run, "prepare") == "" and finish(run) != "", "Interrupted work prevented later valid recovery")
	var aided := planned()
	Trade.state(aided).actors.ning.favors = 1
	check(action(aided, "aid") == "" and finish(aided) != "" and Core.view(aided).protected, "Completed aid failed to protect")
	check(Trade.state(aided).history.back().action == "crisis_aid" and Trade.contact(aided, "ning").last_change.contains("人情 -1"), "Aid trace missing or malformed")
	var lonely := planned()
	lonely.trade = {}
	var before := JSON.stringify(lonely)
	check(action(lonely, "aid") != "" and lonely.trade.is_empty(), "Aid fabricated a favor ledger")
	check(before == JSON.stringify(lonely), "Unaffordable favor aid changed state")

func test_boundaries_guards_and_persistence() -> void:
	for mode in ["away", "travel", "sleep", "busy", "event", "dawn", "plan", "wave", "report", "fight", "night", "dead", "energy", "materials", "invalid", "last_minute"]:
		var run := planned()
		var action_id := "prepare"
		match mode:
			"away": run.explore = {"point": "mortuary"}
			"travel": run.neighbor_travel = true
			"sleep": run.sleeping = true
			"busy": run.busy = {"kind": "cook"}
			"event": run.pending_event = "taoist"
			"dawn": run.dawn_due = true
			"plan": run.plan_due = true
			"wave": run.wave_due = true
			"report": run.wave_report = {"day": 2}
			"fight": run.fight = {"live": 1}
			"night": run.night = {"done": false}
			"dead": run.phase = "dead"
			"energy": run.attrs.energy = 0
			"materials": run.home = {}
			"invalid": action_id = "invent_effect"
			"last_minute": run.t = int(Core.view(run).impact_t) - 60
		var token := str(Core.view(run).token)
		var unchanged := JSON.stringify(run)
		check(Core.act(run, action_id, token) != "" and JSON.stringify(run) == unchanged, "Blocked action mutated state: " + mode)
	var late := planned()
	at(late, 4, 720)
	Core.poll(late)
	late.t = int(Core.view(late).end_t) - 90
	var material: Dictionary = late.home.duplicate()
	check(action(late, "emergency") != "" and late.home == material, "Too-late repair spent materials")
	var first := planned()
	var old_token := str(Core.view(first).token)
	var sibling := planned()
	check(Core.act(sibling, "ignore", old_token) != "", "Previous-life crisis token affected new run")
	var work := planned()
	action(work, "prepare")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(work)))
	check(Core.context(saved) == Core.context(work) and saved.busy == work.busy, "JSON roundtrip lost pending work")
	var before := work.duplicate(true)
	check(finish(saved) != "" and Core.view(saved).protected and not Core.view(before).protected, "Saved work failed or mutated rewind snapshot")
	var data := {"id": str(Core.view(saved).id), "action": "prepare"}
	check(Core.complete(saved, data) == "", "Completed work replayed benefit")
	var legacy := sample()
	legacy.version = 14
	legacy.erase("crisis")
	at(legacy, 12)
	var upgraded := Migrate.save({"run": legacy.duplicate(true), "snapshots": {"11": legacy.duplicate(true)}})
	check(upgraded.run.version == Migrate.VERSION and upgraded.snapshots["11"].version == Migrate.VERSION, "Crisis run/snapshot migration missing")
	check(Core.state(upgraded.run).next_warning_day == 13 and Core.state(upgraded.snapshots["11"]).next_warning_day == 13, "Migration applied a past crisis")
	check(Core.poll(upgraded.run) == "" and Core.view(upgraded.run).is_empty(), "Migrated legacy received retroactive harm")
	for index in 20:
		Core.state(before).active.work = {}
		before.busy = {}
		Core.state(before).active.response = ""
		action(before, "ignore")
	check(Core.context(before).history.size() <= 12, "Crisis history exceeded bound")

func _ready() -> void:
	Game.no_save = true
	test_hidden_and_proposals()
	test_investigation_prepare_truth()
	test_ignore_impact_and_repair()
	test_favor_and_interruptions()
	test_boundaries_guards_and_persistence()
	print("Crisis rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
