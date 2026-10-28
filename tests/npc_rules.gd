extends Node
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.t = (day - 1) * 1440 + minute
	run.pday = day

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 901)
	Pre.start_disaster(run)
	run.home = {"rice": 20, "mugwort": 20, "wood": 20, "firewood": 20}
	Trade.state(run)
	Npc.state(run)
	# Isolate NPC choices from separately tested randomized crisis clocks.
	Crisis.state(run).next_warning_day = 100
	return run

func publish(run: Dictionary, day := 2) -> void:
	at(run, day)
	check(Npc.poll(run) != "", "Daily decision absent")

func act(run: Dictionary, actor: String, action: String) -> String:
	return Npc.act(run, actor, action, str(Npc.view(run, actor).token))

func due(run: Dictionary, day := 2) -> void:
	at(run, day, 600)
	check(Npc.poll(run) != "", "Daily execution absent")

func set_mode(run: Dictionary, actor: String, mode: String) -> void:
	var person: Dictionary = Npc.state(run).actors[actor]
	person.stock.rice = 4
	person.stock[Npc.FOCAL[actor]] = 4
	var contact: Dictionary = Trade.state(run).actors[actor]
	if mode == "share": contact.trust = 2
	if mode == "guard": contact.trust = -2
	if mode == "stockpile":
		var kind := "herb_shortage" if actor == "ning" else "fuel_shortage"
		Crisis.state(run).next_warning_day = 2
		check(Crisis.propose(run, {"kind": kind, "actor": actor, "warning_day": 2, "real": false}, 1), "Public crisis fixture proposal failed")
		at(run, 2)
		Crisis.poll(run)

func test_initial_and_priorities() -> void:
	var base := sample()
	check(base.version == Migrate.VERSION and Npc.state(base).next_day == 2, "New run NPC version/start day wrong")
	for actor in Npc.ACTORS:
		check(Npc.view(base, actor).stock == {"rice": 3, Npc.FOCAL[actor]: 3}, "Initial finite stock wrong")
	check(Npc.next_boundary(base) == 1560, "First decision boundary wrong")
	for actor in Npc.ACTORS:
		for mode in ["gather", "stockpile", "guard", "share"]:
			var run := sample()
			set_mode(run, actor, mode)
			publish(run)
			var current := Npc.view(run, actor)
			check(current.plan.mode == mode, "Decision priority wrong: " + actor + mode)
			check(current.plan.due_t == 2040 and current.plan.status == "pending", "Execution time/status wrong")
			check(not current.effect.is_empty() and not current.reason.is_empty(), "Visible decision lacks consequences")
			check(current.stock.rice == 3, "Daily meal not deducted exactly once")
			var stable := JSON.stringify(Npc.state(run))
			check(Npc.poll(run) == "" and JSON.stringify(Npc.state(run)) == stable, "Repeated poll ate or decided twice")
			check(Npc.next_boundary(run) == 2040, "Execution boundary wrong")
	var hungry := sample()
	Trade.state(hungry).actors.ning.trust = -5
	Npc.state(hungry).actors.ning.stock = {"rice": 1, "mugwort": 0}
	publish(hungry)
	check(Npc.view(hungry, "ning").plan.mode == "gather" and Npc.view(hungry, "ning").plan.focus == "rice", "Hunger did not outrank guard/scarcity")
	check(Npc.view(hungry, "ning").plan.req == {"rice": 2}, "Hungry support request incorrect")
	var scarce := sample()
	Npc.state(scarce).actors.ning.stock.mugwort = 1
	Trade.state(scarce).actors.ning.favors = 2
	publish(scarce)
	check(Npc.view(scarce, "ning").plan.mode == "gather" and Npc.view(scarce, "ning").plan.focus == "mugwort", "Own low goods did not outrank favor")
	var debt := sample()
	Trade.state(debt).actors.zhou.trust = 5
	Trade.state(debt).actors.zhou.breaches = 1
	publish(debt)
	check(Npc.view(debt, "zhou").plan.mode == "guard", "Unresolved breach did not outrank high trust")

func test_support_and_resources() -> void:
	for actor in Npc.ACTORS:
		for mode in ["gather", "stockpile", "guard", "share"]:
			var run := sample()
			set_mode(run, actor, mode)
			publish(run)
			var focal := str(Npc.FOCAL[actor])
			var before := int(run.home[focal])
			var trust := int(Trade.contact(run, actor).trust)
			check(act(run, actor, "support") == "", "Support failed: " + actor + mode)
			check(int(run.home[focal]) == before - 1 and int(Npc.view(run, actor).stock[focal]) == 5, "Support did not transfer real stock")
			check(Trade.contact(run, actor).trust == trust + 1 and Trade.contact(run, actor).favors == 1, "Support did not earn real trust/favor")
			var transferred: Dictionary = run.home.duplicate(true)
			check(act(run, actor, "support") != "" and run.home == transferred, "Repeated support consumed twice")
			due(run)
			var stock: Dictionary = Npc.view(run, actor).stock
			if mode == "gather": check(stock[focal] == 8 and stock.rice == 2, "Supported gather did not consume rice/gain 3")
			if mode == "share": check(stock[focal] == 3 and int(run.home[focal]) == before + 1, "Supported share did not debit NPC2/pay player2")
			if mode == "stockpile": check(stock[focal] == 4 and Npc.market_effect(run, actor).price_add == 0, "Supported stockpile did not consume1/remove surcharge")
			if mode == "guard": check(Npc.market_effect(run, actor).credit_allowed and Npc.market_effect(run, actor).price_add == 0, "Support did not relieve guard")
			var after := JSON.stringify(run.home)
			check(Npc.poll(run) == "" and JSON.stringify(run.home) == after, "Repeated execution duplicated gift")
	var hungry := sample()
	Npc.state(hungry).actors.ning.stock.rice = 1
	publish(hungry)
	check(act(hungry, "ning", "support") == "" and Npc.view(hungry, "ning").stock.rice == 2 and hungry.home.rice == 18, "Hungry support failed exact rice transfer")
	due(hungry)
	check(Npc.view(hungry, "ning").stock.rice == 5, "Supported hungry gather did not add3")
	var capped := sample()
	Npc.state(capped).actors.ning.stock.mugwort = 20
	publish(capped)
	var original: Dictionary = capped.home.duplicate(true)
	check(act(capped, "ning", "support") != "" and capped.home == original, "Full stock accepted wasted support")
	Trade.state(capped).actors.ning.favors = 3
	Npc.state(capped).actors.ning.stock.mugwort = 4
	check(act(capped, "ning", "support") != "" and capped.home == original, "Full favor cap accepted wasted support")
	var cap_gather := sample()
	Npc.state(cap_gather).actors.ning.stock.mugwort = 19
	publish(cap_gather)
	due(cap_gather)
	check(Npc.view(cap_gather, "ning").stock.mugwort == 20, "Gather exceeded stock cap")

func test_favor_decline_and_natural_results() -> void:
	for actor in Npc.ACTORS:
		for mode in ["gather", "stockpile", "guard", "share"]:
			var run := sample()
			set_mode(run, actor, mode)
			# A real ledger favor can also determine share; override only after intent locks.
			publish(run)
			Trade.state(run).actors[actor].favors = 1
			var focal := str(Npc.FOCAL[actor])
			var stock := int(Npc.view(run, actor).stock[focal])
			var home := int(run.home[focal])
			check(act(run, actor, "favor") == "", "Favor could not reserve gift")
			check(Trade.contact(run, actor).favors == 0 and Npc.view(run, actor).stock[focal] == stock - 1, "Favor did not debit/reserve immediately")
			check(run.home[focal] == home and Npc.view(run, actor).plan.reserved == {focal: 1}, "Favor delivered early or failed reservation")
			due(run)
			check(Npc.view(run, actor).stock[focal] == stock - 1 and run.home[focal] == home + 1, "Original action consumed reserved favor stock or paid twice")
			check(Npc.market_effect(run, actor).price_add == 0 and Npc.market_effect(run, actor).credit_allowed, "Favor did not normalize future policy")
			check(Npc.view(run, actor).plan.reserved.is_empty(), "Delivered favor remained reserved")
	for mode in ["gather", "stockpile", "guard", "share"]:
		var run := sample()
		set_mode(run, "ning", mode)
		publish(run)
		var ledger := Trade.state(run).duplicate(true)
		var home: Dictionary = run.home.duplicate(true)
		check(act(run, "ning", "decline") == "", "Decline failed")
		check(Trade.state(run) == ledger and run.home == home, "Decline caused a penalty")
		check(act(run, "ning", "support") != "", "Decline left intervention open")
		due(run)
		if mode == "stockpile": check(Npc.market_effect(run, "ning").price_add == 1 and Npc.view(run, "ning").stock.mugwort == 3, "Unassisted stockpile did not consume stock/surcharge")
		if mode == "guard": check(Npc.market_effect(run, "ning").price_add == 1 and not Npc.market_effect(run, "ning").credit_allowed, "Guard did not tighten next quote")
		if mode == "share": check(run.home.mugwort == int(home.mugwort) + 1 and Npc.view(run, "ning").stock.mugwort == 3, "Natural share not funded by NPC")
	var no_favor := sample()
	publish(no_favor)
	check(act(no_favor, "ning", "favor") != "", "Invented favor accepted")
	Trade.state(no_favor).actors.ning.favors = 1
	Npc.state(no_favor).actors.ning.stock.mugwort = 0
	check(act(no_favor, "ning", "favor") != "", "Favor promised absent stock")

func test_public_knowledge_and_time() -> void:
	for real in [false, true]:
		var run := sample()
		Crisis.state(run).next_warning_day = 2
		check(Crisis.propose(run, {"kind": "herb_shortage", "actor": "ning", "warning_day": 2, "real": real}, 1), "Knowledge fixture rejected")
		at(run, 2)
		Crisis.poll(run)
		Npc.poll(run)
		check(Npc.view(run, "ning").plan.mode == "stockpile", "NPC read hidden crisis truth")
		check(not JSON.stringify(Npc.context(run)).contains('"real":') and not JSON.stringify(Npc.context(run)).contains('"pending":'), "NPC context leaked private crisis proposal")
	var private_run := sample()
	Past.state(private_run).inherited = [{"actor": "ning", "fact": "私有前世", "response": "dismiss"}]
	Past.state(private_run).schedule = [{"actor": "ning", "fact": "私有未来觉醒"}]
	publish(private_run)
	check(Npc.view(private_run, "ning").plan.mode == "gather" and Npc.view(private_run, "ning").memory.is_empty(), "Unawakened memory changed decision")
	check(not JSON.stringify(Npc.context(private_run)).contains("私有"), "Unawakened memory leaked to public context")
	for response in ["", "dismiss", "acknowledge", "compensate"]:
		var run := sample()
		Past.state(run).awakenings = [{"actor": "ning", "fact": "你前世送过药。", "response": response}]
		publish(run)
		var expected := "guard" if response == "dismiss" else ("share" if response in ["acknowledge", "compensate"] else "gather")
		check(Npc.view(run, "ning").plan.mode == expected, "Awakened response did not affect own decision: " + response)
		check(Npc.view(run, "zhou").plan.mode == "gather" and Npc.view(run, "zhou").memory.is_empty(), "Memory teleported to another actor")
	var clock := sample()
	at(clock, 2, 119)
	clock.pday = 99
	check(Npc.poll(clock) == "", "Untrusted pday published early")
	clock.t += 1
	check(Npc.poll(clock) != "" and Npc.view(clock, "ning").plan.day == 2, "Actual clock did not control decision")
	var token := str(Npc.view(clock, "ning").token)
	var before: Dictionary = clock.home.duplicate(true)
	clock.t = 2040
	check(Npc.act(clock, "ning", "support", token) != "" and clock.home == before, "At-deadline response spent goods")
	check(Npc.poll(clock) != "" and Npc.view(clock, "ning").plan.status == "done", "Clock did not execute with untrusted pday")
	check(Npc.state(clock).history[-1].day == 2, "History used untrusted pday")
	var locked := sample()
	publish(locked)
	var original: Dictionary = Npc.view(locked, "ning").plan.duplicate(true)
	Trade.state(locked).actors.ning.trust = -5
	check(Npc.poll(locked) == "" and Npc.view(locked, "ning").plan == original, "Changing trust rewrote published intent")
	due(locked)
	publish(locked, 3)
	# Day3 rice is1: actual needs outrank hatred; it does not stay on yesterday's plan.
	check(Npc.view(locked, "ning").plan.mode == "gather" and Npc.view(locked, "ning").plan.focus == "rice", "Next-day decision ignored actual depleted rice")

func test_guards_saves_and_daily() -> void:
	var run := sample()
	publish(run)
	for change in ["busy", "sleeping", "explore", "neighbor_travel", "pending_event", "dawn_due", "plan_due", "wave_due", "wave_report", "fight", "night"]:
		var blocked: Dictionary = run.duplicate(true)
		if change in ["sleeping", "neighbor_travel", "dawn_due", "plan_due", "wave_due"]: blocked[change] = true
		elif change == "pending_event": blocked[change] = "world:fixture"
		else: blocked[change] = {"fixture": true}
		var before: Dictionary = blocked.home.duplicate(true)
		check(act(blocked, "ning", "support") != "" and blocked.home == before, "Action access bypass: " + change)
	var poor: Dictionary = run.duplicate(true)
	poor.home = {}
	check(act(poor, "ning", "support") != "", "Missing player material ignored")
	check(Npc.act(run, "stranger", "support", "") != "" and Npc.view(run, "stranger").is_empty() and Npc.options(run, "stranger").is_empty(), "Unknown actor accepted")
	check(act(run, "ning", "script") != "", "Unknown action accepted")
	var sibling := sample()
	publish(sibling)
	check(Npc.act(sibling, "ning", "decline", str(Npc.view(run, "ning").token)) != "", "Previous-life token accepted")
	var token := str(Npc.view(run, "ning").token)
	check(act(run, "zhou", "decline") == "" and Npc.act(run, "ning", "support", token) != "", "Stale revision token accepted")
	Trade.state(run).actors.ning.favors = 1
	check(act(run, "ning", "favor") == "", "Save fixture favor failed")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	check(Npc.context(saved) == Npc.context(run), "NPC JSON roundtrip lost facts")
	var rewind: Dictionary = run.duplicate(true)
	due(saved)
	check(Npc.view(rewind, "ning").plan.status == "pending" and Npc.view(saved, "ning").plan.status == "done", "Executing save mutated rewind snapshot")
	check(Npc.poll(saved) == "", "Reload duplicated execution")
	var legacy := sample()
	legacy.version = 15
	legacy.erase("npcs")
	at(legacy, 12)
	legacy.pday = 1
	var upgraded := Migrate.save({"run": legacy.duplicate(true), "snapshots": {"11": legacy.duplicate(true)}})
	check(upgraded.run.version == Migrate.VERSION and upgraded.snapshots["11"].version == Migrate.VERSION, "NPC migration missing current/snapshot")
	check(Npc.state(upgraded.run).next_day == 13 and Npc.state(upgraded.snapshots["11"]).next_day == 13, "Legacy migration trusted pday or backfilled history")
	check(Npc.poll(upgraded.run) == "" and Npc.view(upgraded.run, "ning").plan.is_empty(), "Legacy archive got retroactive autonomous action")
	var daily_a := sample()
	var daily_b := sample()
	daily_a.flags.daily = "2026-10-24"
	daily_b.flags.daily = "2026-10-24"
	Past.state(daily_a).awakenings = [{"actor": "ning", "fact": "旧世", "response": "dismiss"}]
	var rng_before := int(daily_a.rng_n)
	publish(daily_a)
	publish(daily_b)
	for actor in Npc.ACTORS:
		var left: Dictionary = Npc.view(daily_a, actor).plan.duplicate(true)
		var right: Dictionary = Npc.view(daily_b, actor).plan.duplicate(true)
		left.erase("id")
		right.erase("id")
		check(left == right, "Daily seed changed with past-life knowledge")
	check(int(daily_a.rng_n) == rng_before and Past.state(daily_a).trace.is_empty(), "NPC consumed shared RNG or daily past facts")
	var long_run := sample()
	at(long_run, 30, 600)
	check(Npc.poll(long_run) != "" and Npc.poll(long_run) == "", "Skipped-time catchup duplicated/lost work")
	check(Npc.context(long_run).history.size() <= 12 and Npc.state(long_run).next_day == 31, "Bounded history/catchup wrong")
	for actor in Npc.ACTORS:
		for amount in Npc.view(long_run, actor).stock.values(): check(int(amount) >= 0 and int(amount) <= 20, "NPC stock escaped bounds after long progression")

func test_capacity_early_clock_and_fact_budget() -> void:
	for amount in [18, 19, 20]:
		var run := sample()
		Npc.state(run).actors.ning.stock.mugwort = amount
		publish(run)
		var current := Npc.view(run, "ning")
		var rice := int(current.stock.rice)
		if amount == 20:
			check(current.effect.contains("存货已满") and current.effect.contains("不再花米"), "Full-store effect promised wasted work")
		else:
			check(current.effect.contains("艾草 %d" % (20 - amount)), "Gather effect ignored finite remaining capacity")
		var before: Dictionary = run.home.duplicate(true)
		var ledger := Trade.state(run).duplicate(true)
		var hint := str(Npc.options(run, "ning")[0].hint)
		if amount >= 19:
			check(act(run, "ning", "support") != "" and run.home == before and Trade.state(run) == ledger, "Support accepted zero-growth capacity or consumed goods/favor")
			check(hint.contains("艾草 0") and not hint.contains("增加 3"), "Blocked support promised nonexistent +3")
		else:
			check(hint.contains("艾草 1"), "Limited support did not disclose actual +1")
			check(act(run, "ning", "support") == "", "Limited-capacity honest +1 support rejected")
			check(Npc.view(run, "ning").effect.contains("艾草 1"), "Supported limited gather effect did not match capacity")
		due(run)
		check(Npc.view(run, "ning").stock.mugwort == 20, "Capacity-aware actual gather output mismatch")
		check(Npc.view(run, "ning").stock.rice == (rice if amount == 20 else rice - 1), "Full stock consumed rice or partial gather did not pay")
	var future := sample()
	publish(future)
	var token := str(Npc.view(future, "ning").token)
	var original: Dictionary = future.home.duplicate(true)
	future.t = 1559
	check(Npc.act(future, "ning", "support", token) != "" and future.home == original, "Future-announced plan accepted intervention on an old clock")
	var routine := sample()
	Past.record(routine, "ning", "player_key", "你曾按约送药，这是关键选择。", 1)
	publish(routine)
	check(Past.state(routine).trace.size() == 1 and Past.state(routine).trace[0].fact_id == "player_key", "Announced intention became an executed previous-life fact")
	due(routine)
	check(Past.state(routine).trace.size() == 1, "Routine production consumed past-life fact budget")
	var meaningful := sample()
	Past.record(meaningful, "ning", "player_key", "你曾按约送药，这是关键选择。", 1)
	publish(meaningful)
	check(act(meaningful, "ning", "support") == "", "Meaningful memory fixture support failed")
	due(meaningful)
	at(meaningful, 30, 600)
	Npc.poll(meaningful)
	var facts: Array = Past.state(meaningful).trace
	check(facts.any(func(f): return f.fact_id == "player_key"), "Autonomous everyday facts evicted a key player choice")
	check(facts.filter(func(f): return f.actor == "ning" and f.fact_id == "npc_autonomy").size() == 1, "NPC latest meaningful consequence did not overwrite its bounded fact")
	check(facts.size() <= 4 and Npc.state(meaningful).history.size() == 12, "Fact budget/history did not keep separate bounds")

func _ready() -> void:
	Game.no_save = true
	test_initial_and_priorities()
	test_support_and_resources()
	test_favor_decline_and_natural_results()
	test_public_knowledge_and_time()
	test_guards_saves_and_daily()
	test_capacity_early_clock_and_fact_budget()
	print("NPC rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
