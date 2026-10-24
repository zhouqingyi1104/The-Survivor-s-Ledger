extends Node
## Actual executed old choices -> new-life inquiry -> fixed new contracts.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Director = preload("res://scripts/core/director.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
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

func life(meta: Dictionary, seed_value := 719) -> Dictionary:
	var run := State.new_run("herbalist", meta, seed_value)
	Pre.start_disaster(run)
	Director.state(run).enabled = false
	Neighbor.state(run).stage = "closed"
	Past.state(run).schedule = []
	Npcs.state(run).next_day = 100000
	Crisis.state(run).next_warning_day = 100000
	run.home = {"rice": 20, "wood": 10, "water": 20, "mugwort": 10, "firewood": 10, "plague_powder": 1}
	return run

func old_trade(kind: String) -> Dictionary:
	var meta := State.new_meta()
	var previous := life(meta)
	at(previous, 2)
	Trade.influence(previous, "zhou", 3, "本世真实信用准备")
	check(Post.trade_action(previous, "zhou", "credit", str(Trade.quote(previous, "zhou").id)) == "", "Old life could not sign actual credit")
	if kind == "breach":
		at(previous, 4, 720)
		Post.trade_refresh(previous)
		check(previous.trade.debt.overdue, "Actual old debt never became overdue")
	elif kind == "kept":
		check(Post.trade_action(previous, "zhou", "repay", str(Trade.quote(previous, "zhou").id)) == "", "Actual on-time repayment failed")
	previous.phase = "dead"
	check(Past.archive(previous, meta), "Could not seal executed trade life")
	return meta

func old_rescue() -> Dictionary:
	var meta := State.new_meta()
	var previous := life(meta)
	Neighbor.state(previous).stage = "waiting"
	at(previous, 2)
	check(Neighbor.poll(previous) == "n_request", "Actual neighbor request did not open")
	check(Neighbor.choose(previous, 1) == "", "Actual old medicine donation failed")
	check(Inv.count(previous.home, "plague_powder") == 0, "Old rescue did not consume actual medicine")
	previous.phase = "dead"
	check(Past.archive(previous, meta), "Could not seal executed rescue life")
	return meta

func act(run: Dictionary, c: Dictionary, action: String) -> String:
	return Post.cycle_action(run, str(c.id), action, str(Cycle.view(run).token))

func publish(run: Dictionary) -> Dictionary:
	var c: Dictionary = Cycle.state(run).cases[0]
	at(run, int(c.publish_day))
	Post.trade_refresh(run)
	check(c.stage == "lead", "Default local old-dream chain did not publish")
	return c

func verify(run: Dictionary, c: Dictionary) -> void:
	check(act(run, c, "inquire") == "", "Could not begin actual interview")
	Post.advance(run, 29)
	check(c.stage == "lead" and c.evidence.is_empty(), "Interview completed early")
	Post.advance(run, 1)
	check(c.stage == "interviewed", "Actual Post callback did not complete interview")
	var rice := Inv.count(run.home, "rice")
	check(act(run, c, "verify") == "", "Could not begin actual current-life verification")
	check(Inv.count(run.home, "rice") == rice - 1 and c.evidence.is_empty(), "Verification cost or deferred proof wrong")
	Post.advance(run, 44)
	check(c.evidence.is_empty(), "Verification granted proof before work ended")
	Post.advance(run, 1)
	check(c.stage == "verified" and not c.evidence.is_empty(), "Real Post completion did not grant current proof")

func test_receipts_and_birth() -> void:
	var empty := life(State.new_meta())
	at(empty, 2)
	check(Post.trade_action(empty, "zhou", "cash", str(Trade.quote(empty, "zhou").id)) == "", "Cash fixture did not transact")
	check(Past.state(empty).get("cycle_receipts", []).is_empty(), "Cash transaction manufactured a promise")
	check(Cycle.state(empty).cases.is_empty(), "First life manufactured an old case")
	for kind in ["promise", "breach", "kept"]:
		var meta := old_trade(kind)
		var run := life(meta)
		var c: Dictionary = Cycle.state(run).cases[0]
		check(c.kind == ("breach" if kind == "breach" else "promise"), "Executed old trade choice produced wrong case")
		check(c.status == ("kept" if kind == "kept" else ("broken" if kind == "breach" else "pledged")), "Old kept/pending/broken status was flattened")
		check(Trade.state(run).debt.is_empty() and Trade.contact(run, "zhou").trust == 0, "Birth copied old debt or trust")
		check(Past.public_memories(run).is_empty() and Cycle.context(run).published.is_empty(), "Birth exposed old facts to NPC or public case context")
		check(not JSON.stringify(Cycle.context(run)).contains("private_condition"), "Unverified current condition leaked")
	var saved := life(old_rescue())
	check(Cycle.state(saved).cases[0].kind == "rescue", "Actual medicine did not create rescue inquiry")
	check(Mainline.state(saved).evidence == {"mortuary": false, "temple": false}, "Old rescue granted mainline evidence")

func test_work_and_new_contracts() -> void:
	var run := life(old_rescue())
	var c := publish(run)
	check(Past.public_memories(run).is_empty(), "Private dream forced NPC awakening")
	verify(run, c)
	var frozen_quote := Trade.quote(run, "ning")
	var trust := int(Trade.contact(run, "ning").trust)
	var npc_rice := int(Npcs.state(run).actors.ning.stock.rice)
	check(act(run, c, "mutual_help") == "", "Could not choose actual current mutual aid")
	var stale := str(Cycle.view(run).token)
	check(c.stage == "working" and c.delivery.is_empty() and int(Trade.contact(run, "ning").trust) == trust, "Starting work granted completed favor or delivery")
	Post.advance(run, 44)
	check(c.delivery.is_empty(), "New pact was promised before actual work completed")
	Post.advance(run, 1)
	check(c.stage == "resolved" and c.route == "mutual_help" and not c.delivery.done, "Actual work did not lock a new promise")
	check(Trade.contact(run, "ning").trust == trust + 1 and Trade.contact(run, "ning").favors == 1, "Actual relationship did not change")
	check(Npcs.state(run).actors.ning.stock.rice == npc_rice + 1, "Actual gift did not enter NPC working stock")
	check(Trade.quote(run, "ning").req == frozen_quote.req and Trade.quote(run, "ning").give == frozen_quote.give, "Inquiry rewrote current quote")
	var before: Dictionary = run.home.duplicate(true)
	check(Post.cycle_action(run, c.id, "help_again", stale) != "" and run.home == before, "Stale route duplicated cost or gain")
	var delivered: Dictionary = c.delivery.duplicate(true)
	run.t = int(delivered.due_t) - 1
	run.pday = int(run.t) / 1440 + 1
	Post.trade_refresh(run)
	check(not c.delivery.done, "New pact delivered early")
	run.t += 1
	Post.trade_refresh(run)
	check(c.delivery.done, "Disabled AI prevented a locked new delivery")
	for item in delivered.give: check(Inv.count(run.home, item) == int(before.get(item, 0)) + int(delivered.give[item]), "Wrong actual delayed stock")
	var after: Dictionary = run.home.duplicate(true)
	Post.trade_refresh(run)
	check(run.home == after, "Repeated poll duplicated new delivery")
	var loaded: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	Post.trade_refresh(loaded)
	check(loaded.home == run.home and loaded.cycle_inquiry.cases[0].delivery.done, "Save/load replayed a paid promise")
	# The trust and received stocks participate in an actual later NPC decision.
	Npcs.state(run).next_day = int(run.pday) + 1
	var without_pact := run.duplicate(true)
	Trade.state(without_pact).actors.ning.trust = trust
	Trade.state(without_pact).actors.ning.favors = 0
	Npcs.state(without_pact).actors.ning.stock.rice = npc_rice
	at(run, int(run.pday) + 1)
	at(without_pact, int(run.pday))
	Post.trade_refresh(run)
	Post.trade_refresh(without_pact)
	check(Npcs.state(run).actors.ning.plan.mode == "share" and Npcs.state(without_pact).actors.ning.plan.mode != "share", "Actual inquiry favor did not change later NPC decision")

func test_planning_and_migration() -> void:
	var meta := old_trade("breach")
	var run := life(meta)
	at(run, 1)
	run.opening.inherited = [] # Isolate cycle protection from other text guards.
	run.identity.inherited = []
	Director.state(run).enabled = true
	var sent := Director.snapshot(run)
	# Isolated game snapshot for an explicitly separate live-provider contract check.
	var export_file := FileAccess.open(OS.get_environment("TEMP").path_join("ledger-cycle-live-input.json"), FileAccess.WRITE)
	if export_file != null: export_file.store_string(JSON.stringify(sent)); export_file.close()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for row in plan.days: row.day += int(sent.current_day)
	plan.days[0].text = "前世秘密已变成今世证据"
	var c: Dictionary = Cycle.state(run).cases[0]
	plan.cycle_plan = [{"case_id": c.id, "day": 2, "cue": "folded_page"}]
	check(Director.accept(run, sent, plan), "Real Director could not accept preplanned inquiry cue")
	check(c.stage == "sealed" and c.publish_day == 2 and c.cue == "folded_page" and c.evidence.is_empty(), "AI proposal executed work or failed to buffer cue")
	Director.state(run).active = Director.state(run).queue[0].duplicate(true)
	check(not Director.entry(run).text.contains("前世秘密") and Cycle.planning(run).slots.is_empty(), "Accepted unpublished cue leaked model prose after leaving planning slots")
	Director.state(run).active = {}
	check(not Director.accept(run, sent, plan), "Repeated preplan rewrote already selected schedule")
	at(run, 2)
	Post.trade_refresh(run)
	check(c.stage == "lead", "Buffered AI schedule did not reach actual world clock")
	var public_before := c.duplicate(true)
	var newer := Director.snapshot(run)
	for row in plan.days: row.day += 1
	plan.cycle_plan[0].day = 3
	check(not Director.accept(run, newer, plan) and c == public_before, "AI changed a published case")
	var old := State.new_run("scholar", meta, 13)
	old.version = 19
	var silver := int(old.silver)
	var migrated := Migrate.save({"run": old.duplicate(true), "snapshots": {"1": old.duplicate(true)}})
	check(migrated.run.version == 20 and Cycle.state(migrated.run).cases.is_empty() and Cycle.state(migrated.snapshots["1"]).cases.is_empty() and migrated.run.silver == silver, "v20 migration granted cases or changed old stock")
	Game.meta = meta
	check(Game.new_game("scholar", "normal", [], [], [], false, true) == "", "Daily Game candidate failed")
	check(Cycle.state(Game.run).sources.is_empty() and Cycle.planning(Game.run).slots.is_empty() and Cycle.view(Game.run).cases.is_empty(), "Daily birth retained private inquiry sources")
	check(Post.cycle_action(Game.run, c.id, "inquire", str(Cycle.view(Game.run).token)) != "", "Daily API granted cross-life inquiry")
	var born := life(meta)
	var born_sources: Array = born.cycle_inquiry.sources.duplicate(true)
	var later := life(meta)
	at(later, 2)
	Past.record_cycle(later, "traveler", "promise", "kept", "trade_2_repay")
	later.phase = "dead"
	Past.archive(later, meta)
	check(born.cycle_inquiry.sources == born_sources, "Later archive retroactively changed birth sources")

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	test_receipts_and_birth()
	if failures: get_tree().quit(1); return
	test_work_and_new_contracts()
	if failures: get_tree().quit(1); return
	test_planning_and_migration()
	print("Cycle integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
