extends Node
## Real first warnings, contracts, NPC decisions and Game.new_game boundary.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Opening = preload("res://scripts/core/opening.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Director = preload("res://scripts/core/director.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute
	for attr in ["food", "water", "warmth", "energy", "mood"]: run.attrs[attr] = 100

func prepared(role: String, choice: String, meta: Dictionary = {}, seed_value := 6213) -> Dictionary:
	var run := State.new_run(role, State.new_meta() if meta.is_empty() else meta, seed_value)
	check(Opening.apply(run, choice, str(Opening.view(run).token)) == "", "Could not apply real opening " + choice)
	Director.state(run).enabled = false
	Neighbor.state(run).stage = "closed"
	Past.state(run).schedule = []
	Pre.start_disaster(run)
	return run

func true_opening(role: String, choice: String) -> Dictionary:
	for seed_value in range(40, 80):
		var run := prepared(role, choice, {}, seed_value)
		if run.crisis.opening_reservation.real: return run
	check(false, "Fixture could not find a seeded real first warning")
	return {}

func test_game_and_atomicity() -> void:
	Game.meta = State.new_meta()
	check(Game.new_game("scholar", "normal", [], [], [], false, false, [], "scholar_neighbors") == "", "Game failed actual opening")
	check(Game.run.phase == "pre" and Game.run.hour == State.OPEN_HOUR + 1 and Game.run.silver == 22000 - 1200, "Game did not charge actual opening silver/hour")
	check(Inv.count(Game.run.home, "flatbread") == 2 and Inv.count(Game.run.home, "rice") == 2, "Game did not spend/give the actual stock")
	check(Trade.contact(Game.run, "ning").trust == 2 and Trade.contact(Game.run, "ning").favors == 0, "Opening relation did not enter real Trade")
	var old: Dictionary = Game.run.duplicate(true)
	check(Game.new_game("scholar", "normal", [], [], [], false, true, [], "scholar_neighbors") != "" and Game.run == old, "Invalid daily candidate replaced existing life")
	check(Game.new_game("scholar", "normal", [], [], ["bare"], false, false, [], "scholar_stock") != "" and Game.run == old, "Bare vow opening bypass replaced existing life")
	check(Game.new_game("scholar", "normal", [], [], ["bare"], false, false, [], "plain") == "" and Game.run.home.is_empty(), "Ordinary bare opening no longer empty")
	check(Game.new_game("scholar", "normal", [], [], [], false, true) == "", "Daily ordinary candidate rejected")
	check(Past.daily(Game.run) and Opening.context(Game.run).choice == "plain" and Game.run.opening.inherited.is_empty() and Game.run.crisis.get("opening_reservation", {}).is_empty(), "Daily start retained variable opening or private source")

func test_first_warning_and_npcs() -> void:
	var aid := prepared("escort", "escort_neighbors")
	var stock := prepared("escort", "escort_stock")
	var aid_rng := int(aid.rng_n)
	check(not Crisis.context(aid).can_plan, "AI may overwrite reserved first warning")
	check(not Crisis.propose(aid, {"kind": "herb_shortage", "actor": "ning", "warning_day": 2, "real": false}, 0), "AI overwrote reserved first warning")
	at(aid, 2, 119)
	Post.trade_refresh(aid)
	check(Crisis.state(aid).active.is_empty(), "Reserved warning published early")
	at(aid, 2)
	at(stock, 2)
	Post.trade_refresh(aid)
	Post.trade_refresh(stock)
	check(aid.crisis.active.kind == "well_freeze" and stock.crisis.active.kind == "fuel_shortage", "Choice did not change real crisis trajectory")
	check(aid.crisis.active.confirmed == "unknown" and not aid.crisis.active.protected, "Opening fabricated investigation or protection")
	check(aid.crisis.opening_reservation.is_empty(), "First reservation never released")
	check(Npcs.state(aid).actors.zhou.plan.mode == "share" and Npcs.state(stock).actors.zhou.plan.mode == "stockpile", "Opening relationships/crisis did not change actual NPC decision")
	check(int(aid.rng_n) == aid_rng, "Opening warning/NPC decision consumed shared loot RNG")
	var before := Inv.count(aid.home, "wood")
	Post.advance(aid, 480) # Real 08:00 ->16:00 NPC delivery.
	Post.advance(stock, 480)
	check(Npcs.state(aid).actors.zhou.plan.status == "done" and Inv.count(aid.home, "wood") > before, "Opening-triggered NPC share was prose only")
	check(Npcs.state(stock).actors.zhou.policy.price_add == 1, "Self-stockpile choice did not tighten subsequent terms")
	check(Trade.quote(stock, "zhou").req.rice > Trade.quote(aid, "zhou").req.rice, "Actual quotes ignored resulting NPC policies")
	check(Past.public_memories(aid).is_empty() and Past.public_memories(stock).is_empty(), "Current relation change granted NPC old-life knowledge")

func test_crisis_costs_and_contracts() -> void:
	var frozen := true_opening("watchman", "watchman_neighbors")
	at(frozen, 2)
	Post.trade_refresh(frozen)
	check(Post.crisis_action(frozen, "investigate", str(Crisis.view(frozen).token)) == "", "Could not investigate opening warning")
	Post.advance(frozen, 30)
	check(frozen.crisis.active.confirmed == "real", "Real investigation did not confirm seeded risk")
	# The player still buys construction materials; this fixture supplies them.
	Inv.add(frozen.home, "firewood", 2)
	check(Post.crisis_action(frozen, "prepare", str(Crisis.view(frozen).token)) == "", "Could not prepare first crisis")
	Post.advance(frozen, 59)
	check(not frozen.crisis.active.protected, "Opening protection completed early")
	Post.advance(frozen, 1)
	check(frozen.crisis.active.protected, "Completed actual work failed to protect")
	at(frozen, 4, 720)
	Post.trade_refresh(frozen)
	check(frozen.crisis.active.outcome == "averted" and Crisis.well_block(frozen) == "", "Actual preparation failed to avert first impact")
	var later_day := int(frozen.crisis.next_warning_day) - 3
	at(frozen, later_day)
	check(Crisis.context(frozen).can_plan and Crisis.propose(frozen, {"kind": "herb_shortage", "actor": "ning", "warning_day": frozen.crisis.next_warning_day, "real": false}, later_day), "Opening locked out later rolling AI crises")
	var fuel := true_opening("watchman", "watchman_stock")
	Npcs.state(fuel).next_day = 100000 # Isolate signed contracts from NPC market changes.
	at(fuel, 2)
	Post.trade_refresh(fuel)
	var warning: Dictionary = Crisis.view(fuel).duplicate(true)
	check(Post.crisis_action(fuel, "ignore", str(warning.token)) == "", "Could not leave first risk unprepared")
	at(fuel, 4, 700)
	Post.trade_refresh(fuel)
	var quoted := Trade.quote(fuel, "zhou")
	check(Post.trade_action(fuel, "zhou", "credit", str(quoted.id)) != "", "Untrusted opening should not grant free credit")
	Trade.influence(fuel, "zhou", 2, "本世额外真实往来")
	check(Post.trade_action(fuel, "zhou", "credit", str(Trade.quote(fuel, "zhou").id)) == "", "Opening player could not sign actual later debt")
	var debt: Dictionary = fuel.trade.debt.duplicate(true)
	var signed_quote := Trade.quote(fuel, "zhou")
	check(signed_quote.req == quoted.req and signed_quote.give == quoted.give, "Current trust rewrote today's quoted goods")
	Post.advance(fuel, 20)
	check(fuel.crisis.active.stage == "impact", "Ignored real first risk had no actual impact")
	check(Trade.quote(fuel, "zhou") == signed_quote and fuel.trade.debt == debt, "Opening crisis rewrote frozen quote or signed debt")
	var inventory: Dictionary = fuel.home.duplicate(true)
	check(Opening.apply(fuel, "watchman_neighbors", str(Opening.view(fuel).token)) != "" and fuel.trade.debt == debt and fuel.home == inventory, "Late opening changed contract or awarded new stock")
	at(fuel, 5)
	Post.trade_refresh(fuel)
	var no_shortage := fuel.duplicate(true)
	no_shortage.crisis.active.stage = "resolved" # Hold current trust constant to isolate shortage pricing.
	check(Trade.quote(fuel, "zhou").req.rice == Trade.quote(no_shortage, "zhou").req.rice + 1 and fuel.trade.debt == debt, "Impact did not change new quotes or mutated signed debt")

func test_previous_choice_and_next_life() -> void:
	var meta := State.new_meta()
	var previous := State.new_run("escort", meta, 513)
	Pre.start_disaster(previous)
	Neighbor.state(previous).stage = "closed"
	Director.state(previous).enabled = false
	Past.state(previous).schedule = []
	Npcs.state(previous).next_day = 100000
	Crisis.state(previous).next_warning_day = 100000
	previous.home = {"rice": 20, "water": 20}
	at(previous, 2)
	Trade.influence(previous, "zhou", 3, "本世真实信用测试")
	check(Post.trade_action(previous, "zhou", "credit", str(Trade.quote(previous, "zhou").id)) == "", "Prior life could not borrow")
	at(previous, 4, 720)
	Post.trade_refresh(previous)
	check(previous.trade.debt.overdue and previous.trade.actors.zhou.breach_total == 1, "Actual old choice did not produce a breach")
	check(Past.archive(previous, meta), "Could not seal actual breach life")
	var next := State.new_run("escort", meta, 513)
	check(Opening.apply(next, "cash_account", str(Opening.view(next).token)) == "", "Real prior breach did not unlock current cash plan")
	check(Trade.state(next).debt.is_empty() and Trade.contact(next, "zhou").breaches == 0 and Trade.contact(next, "zhou").trust == 2, "Old debt carried over instead of current paid trust")
	check(Past.public_memories(next).is_empty() and Mainline.state(next).evidence == {"mortuary": false, "temple": false}, "Opening gave old NPC knowledge or current evidence")
	Game.meta = meta
	check(Game.new_game("escort", "normal", [], [], [], true, false, ["carpenter"], "cash_account") == "", "Real Game could not apply inherited opening")
	var prior_id := str(Past.state(Game.run).id)
	Game.run.phase = "dead"
	var before_count := int(Past.book(Game.meta).count)
	Game.choose_next_opening(prior_id)
	check(Game.run.is_empty() and Game.pending_role == "escort" and Game.pending_opening_setup == {"endless": true, "daily": false, "mates": ["carpenter"]}, "Next-opening action lost modes or did not return to selection")
	check(Past.book(Game.meta).count == before_count + 1, "Next-opening action did not settle exactly once")
	Game.choose_next_opening(prior_id)
	check(Past.book(Game.meta).count == before_count + 1, "Old next-life button duplicated settlement")
	check(Game.new_game("scholar", "normal", [], [], [], false, false, [], "scholar_stock") == "", "Could not create restart example")
	prior_id = str(Past.state(Game.run).id)
	Game.run.phase = "dead"
	Game.restart_from_cover(prior_id)
	check(Game.run.opening.choice == "scholar_stock" and Game.run.silver == 22000 - 1800, "Restart failed to preserve and pay selected opening")
	var restarted: Dictionary = Game.run.duplicate(true)
	Game.restart_from_cover(prior_id)
	check(Game.run == restarted, "Old restart callback replaced the next life")

func test_migration_and_load() -> void:
	var old := State.new_run("scholar", State.new_meta(), 31)
	old.version = 18
	var silver := int(old.silver)
	var data := Migrate.save({"run": old.duplicate(true), "snapshots": {"1": old.duplicate(true)}})
	check(data.run.version == Migrate.VERSION and data.run.opening.applied and data.snapshots["1"].opening.applied and int(data.run.silver) == silver, "v19 migration replayed opening or missed snapshot")
	check(not Past.opening_snapshot(data.run.opening).is_empty() and Past.opening_snapshot(data.run.opening).effects.silver_cost == 0, "Migrated neutral opening could not be archived without inventing a grant")
	check(Opening.apply(data.run, "scholar_stock", str(Opening.view(data.run).token)) != "", "Old save acquired a new paid opening")
	var run := prepared("herbalist", "herbalist_neighbors")
	var loaded: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	var before: Dictionary = loaded.duplicate(true)
	check(Opening.apply(loaded, "herbalist_stock", str(Opening.view(loaded).token)) != "" and loaded == before, "Loading an applied opening awarded resources twice")
	check(Opening.context(loaded) == Opening.context(run), "Load lost applied opening facts")

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	test_game_and_atomicity()
	if failures: get_tree().quit(1); return
	test_first_warning_and_npcs()
	if failures: get_tree().quit(1); return
	test_crisis_costs_and_contracts()
	if failures: get_tree().quit(1); return
	test_previous_choice_and_next_life()
	if failures: get_tree().quit(1); return
	test_migration_and_load()
	print("Opening integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
