extends Node
const Trade = preload("res://scripts/core/social_trade.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
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

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 642)
	Pre.start_disaster(run)
	at(run, 2)
	run.home = {"rice": 30, "wood": 10, "mugwort": 10, "flatbread": 10}
	return run

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func choice(run: Dictionary, actor: String, action: String) -> String:
	return Trade.act(run, actor, action, str(Trade.quote(run, actor).id))

func block(run: Dictionary, actor: String, action: String) -> String:
	for row in Trade.options(run, actor):
		if row.id == action: return row.block
	return "missing"

func test_prices_and_influence() -> void:
	var neutral := sample()
	var fair := Trade.quote(neutral, "ning")
	check(fair.req == {"rice": 2}, "Neutral price incorrect")
	Trade.influence(neutral, "ning", 4, "First contact")
	check(Trade.quote(neutral, "ning").req == fair.req, "Reopening rerolled frozen same-day price")
	at(neutral, 3)
	check(Trade.quote(neutral, "ning").req == {"rice": 1}, "High trust did not discount next-day offer")
	var low := sample()
	Trade.influence(low, "ning", -3, "Distrust")
	check(Trade.quote(low, "ning").req.rice == 3, "Distrust did not increase price")
	check(block(low, "ning", "credit") != "", "Distrust still allowed credit")
	var donated := sample()
	Trade.observe_neighbor(donated, "donate_home")
	check(Trade.quote(donated, "ning").req.rice == 1, "Actual medicine donation did not earn discount")
	check(Trade.contact(donated, "ning").favors == 1, "Medicine donation did not earn favor")
	var stable := JSON.stringify(donated)
	Trade.observe_neighbor(donated, "donate_home")
	check(JSON.stringify(donated) == stable, "Repeated neighbor observation farmed favors")
	var broken := sample()
	Trade.observe_neighbor(broken, "keep")
	check(Trade.quote(broken, "ning").req.rice == 4, "Broken medicine promise did not increase price")
	check(Trade.contact(broken, "ning").breaches == 1 and Trade.contact(broken, "ning").breach_total == 1, "Broken promise not tracked")
	var refused := sample()
	Trade.observe_neighbor(refused, "refuse")
	check(Trade.contact(refused, "ning").breaches == 0, "Unaccepted request fabricated a debt breach")
	var seeded := sample()
	seeded.director = {"relations": {"ning": 2}}
	seeded.trade = {} # Simulate first contact with an older director-only save.
	Trade.influence(seeded, "ning", 1, "Real new choice")
	check(Trade.contact(seeded, "ning").trust == 3, "Director initialization lost or double-counted first influence")
	Trade.influence(seeded, "ning", 99, "Clamp")
	check(Trade.contact(seeded, "ning").trust == 5, "Trust exceeded cap")
	Trade.influence(seeded, "ning", -99, "Clamp")
	check(Trade.contact(seeded, "ning").trust == -5, "Trust fell below cap")

func test_cash_favor_decline() -> void:
	for actor in Trade.ACTORS:
		var run := sample()
		var q := Trade.quote(run, actor)
		var before: Dictionary = run.home.duplicate()
		check(Trade.act(run, actor, "cash", q.id) == "", "Cash failed for " + actor)
		check(Inv.count(run.home, "rice") == int(before.rice) - int(q.req.rice), "Cash price not paid for " + actor)
		for item in q.give: check(Inv.count(run.home, item) == int(before.get(item, 0)) + int(q.give[item]), "Cash goods missing " + actor + item)
		check(Trade.contact(run, actor).trust == 1, "Cash did not earn trust")
		var after := JSON.stringify(run)
		check(Trade.act(run, actor, "cash", q.id) != "" and JSON.stringify(run) == after, "Double click changed transaction")
		check(choice(run, actor, "aid") != "", "Reopening spent cash quote enabled second daily action")
	var favors := sample()
	Trade.observe_neighbor(favors, "donate_home")
	var rice := Inv.count(favors.home, "rice")
	var trust := int(Trade.contact(favors, "ning").trust)
	check(choice(favors, "ning", "favor") == "", "Favor redemption failed")
	check(Trade.contact(favors, "ning").favors == 0 and Trade.contact(favors, "ning").trust == trust, "Favor redemption created trust or failed to spend favor")
	check(Inv.count(favors.home, "rice") == rice and Inv.count(favors.home, "water") == 2, "Favor charged cash or lost goods")
	check(choice(sample(), "ning", "favor") != "", "Missing favor still granted goods")
	var declined := sample()
	var before: Dictionary = declined.home.duplicate()
	check(choice(declined, "zhou", "decline") == "", "Decline failed")
	check(declined.home == before and Trade.contact(declined, "zhou").trust == 0, "Decline charged goods or trust")
	check(choice(declined, "zhou", "cash") != "", "Decline reopened same-day opportunity")
	at(declined, 3)
	check(choice(declined, "zhou", "cash") == "", "Decline blocked following day")

func test_credit_and_repair() -> void:
	var run := sample()
	Trade.influence(run, "zhou", 3, "Prior fulfilled exchange")
	var q := Trade.quote(run, "zhou")
	var rice := Inv.count(run.home, "rice")
	check(Trade.act(run, "zhou", "credit", q.id) == "", "Credit failed at enough trust")
	check(Inv.count(run.home, "rice") == rice and Inv.count(run.home, "wood") == 12, "Credit deducted upfront payment or lost goods")
	var debt: Dictionary = Trade.state(run).debt.duplicate(true)
	check(debt.req == {"rice": 3} and debt.due_day == 4 and debt.due_t == 3 * 1440 + 720, "Signed repayment or deadline incorrect")
	Trade.influence(run, "ning", 5, "Another contact")
	check(choice(run, "ning", "credit") != "", "Borrowing from another person bypassed global debt limit")
	at(run, 3)
	Trade.influence(run, "zhou", -5, "Changed relation")
	Trade.quote(run, "zhou")
	check(Trade.state(run).debt == debt, "New price or changed relation rewrote signed debt")
	check(choice(run, "zhou", "compensate") != "", "Compensation before clearing debt was allowed")
	at(run, 4, 719)
	check(Trade.poll(run) == "" and not Trade.state(run).debt.overdue, "Debt defaulted before exact deadline")
	at(run, 4, 720)
	check(Trade.poll(run) != "", "Debt did not default at 18:00")
	var p := Trade.contact(run, "zhou")
	check(p.breaches == 1 and p.breach_total == 1, "Deadline failed to count one breach")
	check(Inv.count(run.home, "rice") == rice, "Deadline automatically took repayment inventory")
	var after := JSON.stringify(run)
	check(Trade.poll(run) == "" and JSON.stringify(run) == after, "Repeated deadline poll punished twice")
	at(run, 5)
	var next := Trade.quote(run, "zhou")
	check(int(next.req.rice) > int(q.req.rice), "Default did not worsen future price")
	check(block(run, "zhou", "credit") != "", "Default preserved new borrowing")
	check(choice(run, "zhou", "compensate") != "", "Debtor apologized without first repaying")
	check(choice(run, "zhou", "repay") == "", "Overdue repayment failed")
	check(Trade.state(run).debt.is_empty() and Trade.contact(run, "zhou").breaches == 1, "Repayment erased default without compensation")
	var trust_before := int(Trade.contact(run, "zhou").trust)
	check(choice(run, "zhou", "compensate") == "", "Paid compensation failed")
	p = Trade.contact(run, "zhou")
	check(p.breaches == 0 and p.breach_total == 1 and p.trust == trust_before + 1, "Compensation erased history or failed to restore trust")
	var no_repeat: Dictionary = run.home.duplicate()
	check(choice(run, "zhou", "compensate") != "", "Repeated compensation farmed trust")
	check(run.home == no_repeat and Trade.contact(run, "zhou").breach_total == 1, "Rejected repeated apology still took goods or erased history")
	check(Inv.count(run.home, "rice") == rice - int(debt.req.rice) - 1, "Repayment and compensation costs wrong")
	check(choice(run, "zhou", "decline") == "", "Repayment consumed daily trade opportunity")
	var early := sample()
	Trade.influence(early, "ning", 2, "Enough trust")
	choice(early, "ning", "credit")
	var before_trust := int(Trade.contact(early, "ning").trust)
	check(choice(early, "ning", "repay") == "", "Early repayment failed despite used daily offer")
	check(Trade.contact(early, "ning").trust == before_trust + 1 and Trade.state(early).debt.is_empty(), "Early payment did not restore credit")
	at(early, 6)
	check(Trade.poll(early) == "" and Trade.contact(early, "ning").breach_total == 0, "Paid debt defaulted later")
	var direct := sample()
	Trade.influence(direct, "ning", 2, "Enough trust")
	choice(direct, "ning", "credit")
	at(direct, 5)
	check(choice(direct, "ning", "repay") == "" and Trade.contact(direct, "ning").breach_total == 1, "Direct repayment skipped elapsed deadline")

func test_aid_and_persistence() -> void:
	var run := sample()
	for actor in Trade.ACTORS:
		var before: Dictionary = run.home.duplicate()
		check(choice(run, actor, "aid") == "", "Aid failed for " + actor)
		for item in Trade.OFFERS[actor].aid_req: check(Inv.count(run.home, item) == int(before.get(item, 0)) - int(Trade.OFFERS[actor].aid_req[item]), "Aid did not pay cost")
		check(Trade.contact(run, actor).favors == 1 and Trade.contact(run, actor).trust == 1, "Aid did not affect relation/favor")
	check(Trade.context(run).aid.size() == 3, "Three aid commitments not exposed")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	check(Trade.context(saved) == Trade.context(run), "JSON roundtrip changed commitments")
	var snapshot := run.duplicate(true)
	at(saved, 3, 119)
	check(Trade.poll(saved) == "", "Aid delivered before next-day 08:00")
	at(saved, 5)
	saved.sleeping = true
	saved.explore = {"point": "mortuary"}
	saved.pending_event = "taoist"
	saved.director = {"enabled": false}
	var water := Inv.count(saved.home, "water")
	var firewood := Inv.count(saved.home, "firewood")
	check(Trade.poll(saved) != "", "Offline/busy/cross-day aid did not deliver")
	check(Inv.count(saved.home, "water") == water + 3 and Inv.count(saved.home, "firewood") == firewood + 3, "Delayed aid reward incorrect")
	check(Trade.state(saved).aid.is_empty(), "Delivered aid remained pending")
	var delivered := JSON.stringify(saved)
	check(Trade.poll(saved) == "" and JSON.stringify(saved) == delivered, "Aid delivered twice")
	check(Trade.context(snapshot).aid.size() == 3 and snapshot.home == run.home, "Rewind snapshot was mutated by later delivery")
	var restored: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(snapshot)))
	at(restored, 3)
	check(Trade.poll(restored) != "" and Trade.state(restored).aid.is_empty(), "Restored commitment failed to deliver")
	var daily := sample()
	daily.flags.daily = "2026-10-24"
	check(choice(daily, "ning", "aid") == "", "Daily mode blocked local aid")
	check(daily.past_lives.trace.is_empty(), "Daily trade polluted cross-life memory")
	var full := sample()
	Trade.state(full).actors.ning.favors = 3
	check(choice(full, "ning", "aid") != "", "Capped favor still spent aid materials")

func test_invalid_and_migration() -> void:
	for mode in ["early_day", "early_time", "night", "pre", "away", "travel", "sleep", "busy", "event", "dawn", "plan", "wave", "report", "fight", "night_fight", "dead", "poor", "invalid", "stale_day", "stale_revision"]:
		var run := sample()
		var q := Trade.quote(run, "ning")
		var action := "cash"
		match mode:
			"early_day": at(run, 1)
			"early_time": at(run, 2, 119)
			"night": at(run, 2, 720)
			"pre": run.phase = "pre"
			"away": run.explore = {"point": "mortuary"}
			"travel": run.neighbor_travel = true
			"sleep": run.sleeping = true
			"busy": run.busy = {"label": "cook"}
			"event": run.pending_event = "taoist"
			"dawn": run.dawn_due = true
			"plan": run.plan_due = true
			"wave": run.wave_due = true
			"report": run.wave_report = {"day": 2}
			"fight": run.fight = {"live": 1}
			"night_fight": run.night = {"done": false}
			"dead": run.phase = "dead"
			"poor": run.home = {}
			"invalid": action = "invent_gold"
			"stale_day": at(run, 3)
			"stale_revision": Trade.influence(run, "zhou", 1, "Another choice")
		var unchanged := JSON.stringify(run)
		check(Trade.act(run, "ning", action, q.id) != "", "Invalid action accepted: " + mode)
		check(JSON.stringify(run) == unchanged, "Blocked action changed state: " + mode)
	var capped := sample()
	for index in 30: Trade.influence(capped, "ning", 1 if index % 2 == 0 else -1, "Long local history")
	check(Trade.state(capped).history.size() == 24, "History grew without bound")
	var first := sample()
	var old_quote := Trade.quote(first, "ning")
	var next_life := sample()
	Trade.quote(next_life, "ning")
	check(Trade.act(next_life, "ning", "cash", old_quote.id) != "", "Previous-life button token affected a new run")
	var legacy := sample()
	legacy.version = 13
	legacy.erase("trade")
	legacy.director = {"relations": {"ning": 2, "zhou": -3}}
	legacy.neighbor = {"resolution": "late"}
	var payload := {"run": legacy.duplicate(true), "snapshots": {"1": legacy.duplicate(true)}}
	var upgraded := Migrate.save(payload)
	check(upgraded.run.version == 14 and upgraded.snapshots["1"].version == 14, "Run/snapshot migration not applied")
	check(upgraded.run.trade.is_empty() and upgraded.snapshots["1"].trade.is_empty(), "Legacy migration fabricated a trade history")
	var context := Trade.context(upgraded.run)
	check(context.actors.ning.trust == 2 and context.actors.zhou.trust == -3, "Legacy actual relations not folded into trust")
	check(context.debt.is_empty() and context.aid.is_empty() and context.actors.ning.breach_total == 0, "Old narrative inferred a trade debt/default")
	var replay: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(upgraded.run)))
	check(Trade.context(replay) == context, "Migration or readback changed trade state")

func _ready() -> void:
	Game.no_save = true
	test_prices_and_influence()
	test_cash_favor_decline()
	test_credit_and_repair()
	test_aid_and_persistence()
	test_invalid_and_migration()
	print("Social trade rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
