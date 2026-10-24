extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Director = preload("res://scripts/core/director.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 90973)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	run.home = {"rice": 50, "mugwort": 10, "wood": 10, "firewood": 10, "water": 10, "nails": 10}
	Director.state(run).enabled = false
	Crisis.state(run).next_warning_day = 50
	Trade.state(run)
	Npcs.state(run)
	return run

func person(run: Dictionary, actor: String, rice: int, goods: int, trust: int) -> void:
	var focal := {"ning": "mugwort", "zhou": "wood", "traveler": "firewood"}
	Npcs.state(run).actors[actor].stock = {"rice": rice, focal[actor]: goods}
	Trade.state(run).actors[actor].trust = trust

func act(run: Dictionary, actor: String, action: String) -> String:
	return Post.npc_action(run, actor, action, str(Npcs.view(run, actor).token))

func test_real_clock_and_future() -> void:
	var run := sample()
	person(run, "ning", 5, 4, 3)
	person(run, "zhou", 5, 4, -3)
	person(run, "traveler", 1, 4, 0)
	at(run, 2, 120)
	var d := Director.state(run)
	d.queue = [{"not_seen": true}]
	var revision := int(d.revision)
	Post.trade_refresh(run)
	check(d.queue.is_empty() and int(d.revision) > revision, "NPC real announcements did not invalidate unseen planning")
	check(Npcs.view(run, "ning").plan.mode == "share", "Generous neighbor did not choose a real gift")
	check(Npcs.view(run, "zhou").plan.mode == "guard", "Distrustful merchant did not choose restricted terms")
	check(Npcs.view(run, "traveler").plan.mode == "gather" and Npcs.view(run, "traveler").plan.focus == "rice", "Hungry traveler ignored personal needs")
	var gift_before := Inv.count(run.home, "mugwort")
	at(run, 2, 599)
	check(Post.advance(run, 1) == "", "NPC clock could not reach exact afternoon boundary")
	check(Inv.count(run.home, "mugwort") == gift_before + 1, "Autonomous actual clock gift never reached home")
	check(int(Npcs.view(run, "ning").stock.mugwort) == 3, "Autonomous gift had no real NPC inventory source")
	check(Npcs.view(run, "ning").plan.status == "done", "Afternoon plan was not settled")
	check(not Npcs.market_effect(run, "zhou").credit_allowed, "Autonomous guarding did not change new credit conditions")
	check(int(Npcs.view(run, "traveler").stock.rice) == 2, "Foraging did not actually restore NPC food")
	var home: Dictionary = run.home.duplicate(true)
	var stock := Npcs.state(run).duplicate(true)
	Post.trade_refresh(run)
	check(run.home == home and Npcs.state(run) == stock, "Repeated refresh duplicated gifts, food, or plans")
	check(Past.state(run).trace.any(func(f): return f.actor == "ning" and f.fact.contains("阿宁")), "Actual NPC consequences absent from future-life facts")
	var s := Director.snapshot(run)
	check(s.state.has("npcs") and s.state.npcs.actors.ning.stock.mugwort == 3, "Future AI events cannot see actual NPC consequences")
	at(run, 3, 120)
	Post.trade_refresh(run)
	check(Npcs.view(run, "traveler").plan.focus == "rice", "Restored resources failed to affect the next autonomous day")

func test_support_and_wait_diverge() -> void:
	var supported := sample()
	person(supported, "zhou", 5, 4, -3)
	at(supported, 2, 120)
	Post.trade_refresh(supported)
	var waiting := supported.duplicate(true)
	var before := Inv.count(supported.home, "wood")
	var npc_before := int(Npcs.view(supported, "zhou").stock.wood)
	check(act(supported, "zhou", "support") == "", "Real player support was unavailable")
	check(Inv.count(supported.home, "wood") == before - 1 and int(Npcs.view(supported, "zhou").stock.wood) == npc_before + 1, "Support did not move real supplies between owners")
	check(int(Trade.contact(supported, "zhou").trust) == -2 and int(Trade.contact(supported, "zhou").favors) == 1, "Support failed to affect actual trade trust and favors")
	check(act(waiting, "zhou", "decline") == "", "Free autonomous arrangement unavailable")
	var wait_home: Dictionary = waiting.home.duplicate(true)
	check(act(waiting, "zhou", "support") != "", "Decline did not lock later intervention")
	check(waiting.home == wait_home, "Decline or stale intervention consumed supplies")
	at(supported, 2, 600)
	at(waiting, 2, 600)
	Post.trade_refresh(supported)
	Post.trade_refresh(waiting)
	check(int(Npcs.market_effect(supported, "zhou").price_add) == 0 and Npcs.market_effect(supported, "zhou").credit_allowed, "Supported guarded route did not improve future terms")
	check(int(Npcs.market_effect(waiting, "zhou").price_add) == 1 and not Npcs.market_effect(waiting, "zhou").credit_allowed, "Unassisted guarded route lost its actual consequence")

func test_quotes_and_signed_promises_lock() -> void:
	var run := sample()
	person(run, "zhou", 5, 4, 2)
	# Only a genuinely public awakened memory can lead this friendly actor to guard.
	Past.state(run).awakenings = [{"actor": "zhou", "life": 1, "age": 1, "fact_id": "old", "fact": "旧世你曾婉拒老周。", "response": "dismiss"}]
	at(run, 2, 120)
	Post.trade_refresh(run)
	check(Npcs.view(run, "zhou").plan.mode == "guard", "Awakened and dismissed memory did not affect own decision")
	var old := Trade.quote(run, "zhou")
	check(old.get("credit_allowed", true), "Future autonomous policy leaked into a previously published quote")
	at(run, 2, 600)
	Post.trade_refresh(run)
	var unchanged := Trade.quote(run, "zhou")
	check(unchanged.req == old.req and unchanged.give == old.give and unchanged.credit_allowed == old.credit_allowed, "Executed NPC plan rewrote displayed quote terms")
	check(Post.trade_action(run, "zhou", "credit", unchanged.id) == "", "NPC restriction revoked old frozen credit offer")
	var debt: Dictionary = Trade.state(run).debt.duplicate(true)
	var ning_quote := Trade.quote(run, "ning")
	check(Post.trade_action(run, "ning", "aid", ning_quote.id) == "", "Old exchange aid could not be signed")
	var promise: Dictionary = Trade.state(run).aid[0].duplicate(true)
	at(run, 3, 120)
	var water_before := Inv.count(run.home, "water")
	Post.trade_refresh(run)
	check(Inv.count(run.home, "water") == water_before + int(promise.give.water), "NPC autonomy stole previously reserved aid delivery")
	check(Trade.state(run).debt == debt, "NPC next day rewrote signed debt or its material price")
	var next := Trade.quote(run, "zhou")
	check(not next.credit_allowed and int(next.req.rice) == int(old.req.rice) + 1, "Fresh quote did not sample real guarded policy")
	check(Trade.options(run, "zhou").filter(func(row): return row.id == "credit")[0].block != "", "Fresh restricted quote still allowed credit")

func test_genuine_favor_and_save_resume() -> void:
	var run := sample()
	person(run, "ning", 5, 4, 0)
	at(run, 2, 120)
	Post.trade_refresh(run)
	var q := Trade.quote(run, "ning")
	check(Post.trade_action(run, "ning", "aid", q.id) == "", "Could not earn an actual favor through trade")
	var own_before := int(Npcs.view(run, "ning").stock.mugwort)
	var home_before := Inv.count(run.home, "mugwort")
	check(act(run, "ning", "favor") == "", "Real favor cannot redirect neighbor")
	check(int(Trade.contact(run, "ning").favors) == 0, "Redirect created or failed to spend a real favor")
	check(int(Npcs.view(run, "ning").stock.mugwort) == own_before - 1, "Redirect failed to reserve from NPC supplies")
	check(Inv.count(run.home, "mugwort") == home_before, "Reserved parcel arrived before promised execution")
	var json := JSON.stringify({"run": run, "snapshots": {"2": run.duplicate(true)}})
	var loaded: Dictionary = Migrate.save(JSON.parse_string(json))
	at(loaded.run, 2, 599)
	check(Post.advance(loaded.run, 9) == "", "Resumed plan failed through a split clock advance")
	check(Inv.count(loaded.run.home, "mugwort") == home_before + 1, "Saved reserved parcel lost or duplicated")
	check(loaded.snapshots["2"].npcs.actors.ning.plan.status == "pending", "Live plan settlement mutated rewind snapshot")
	var before: Dictionary = loaded.run.home.duplicate(true)
	Post.trade_refresh(loaded.run)
	check(loaded.run.home == before, "Loaded settled parcel duplicated")
	var rewound: Dictionary = loaded.snapshots["2"].duplicate(true)
	at(rewound, 2, 600)
	Post.trade_refresh(rewound)
	check(Inv.count(rewound.home, "mugwort") == home_before + 1, "Rewind did not restore its own still-pending delivery exactly once")

func test_morning_keeps_prepared_event() -> void:
	var run := sample()
	var d := Director.state(run)
	d.enabled = true
	var sent := Director.snapshot(run)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for event in plan.days: event.day += 1
	plan.days[0].text = "UNSAFE_OLD_NPC_CLAIM"
	check(Director.accept(run, sent, plan), "Could not prepare a real next-day AI plan")
	at(run, 2, 110)
	check(Post.advance(run, 20) == "event", "Daily NPC announcements starved a prepared same-day event")
	check(str(run.pending_event).begins_with("world:") and d.active.day == 2, "Morning did not activate the prepared event")
	check(d.queue.size() == 1 and int(d.queue[0].day) == 2, "Background update retained stale future days")
	check(not Director.entry(run).text.contains("UNSAFE_OLD_NPC_CLAIM"), "Retained daily event displayed obsolete NPC facts")
	var economics: Array = plan.days[0].choices
	check(Director.entry(run).choices[0].get("req", {}) == economics[0].get("req", {}) and Director.entry(run).choices[0].get("give", {}) == economics[0].get("give", {}), "Keeping today's letter rewrote its economics")
	var active: Dictionary = d.active.duplicate(true)
	Director.note_world(run, "Later background", "Only a public world update")
	check(d.active == active and d.queue.is_empty(), "Background update duplicated or replaced active letter")
	check(Director.choose(run, 0) == "", "Buffered current-day choice became unplayable")
	check(d.queue.is_empty() and d.active.is_empty(), "Player choice failed to clear unseen plans")
	check(not Director.accept(run, sent, plan), "An old AI reply survived the real morning revision and player choice")
	var locked := sample()
	Director.state(locked).enabled = true
	var locked_plan: Dictionary = plan.duplicate(true)
	locked_plan.days[0].text = "ordinary letter"
	check(Director.accept(locked, Director.snapshot(locked), locked_plan), "Could not prepare busy-event fixture")
	at(locked, 2, 120)
	locked.busy = {"kind": "rest", "label": "小憩", "start": int(locked.t), "end": int(locked.t) + 120, "data": {}}
	Post.trade_refresh(locked)
	check(Director.state(locked).active.is_empty() and locked.pending_event == "" and Director.poll(locked) == "", "NPC world update activated a letter during work")
	locked.busy = {}
	locked.pending_event = "taoist"
	Director.note_world(locked, "Background", "Another public fact")
	check(Director.poll(locked) == "" and locked.pending_event == "taoist", "NPC world update overwrote another event")
	check(Director.state(locked).queue.size() == 1 and int(Director.state(locked).queue[0].day) == 2, "Busy and event locks lost today's prepared letter")
	locked.pending_event = ""
	check(Director.poll(locked) != "", "Deferred letter failed after work and event locks cleared")

func test_crisis_and_npc_supply_stack() -> void:
	for kind in ["fuel_shortage", "herb_shortage"]:
		var run := sample()
		var actor := "zhou" if kind == "fuel_shortage" else "ning"
		person(run, actor, 8, 8, 0)
		Crisis.state(run).next_warning_day = 2
		check(Crisis.propose(run, {"kind": kind, "actor": actor, "warning_day": 2, "real": true}, 1), "Could not set up actual joint crisis")
		at(run, 2, 120)
		Post.trade_refresh(run)
		check(Npcs.view(run, actor).plan.mode == "stockpile", "NPC ignored published relevant crisis")
		var frozen := Trade.quote(run, actor)
		at(run, 2, 600)
		Post.trade_refresh(run)
		check(Trade.quote(run, actor).req == frozen.req, "NPC stockpile repriced an already shown quote")
		at(run, 4, 720)
		Post.trade_refresh(run)
		check(Crisis.view(run).stage == "impact" and int(Npcs.market_effect(run, actor).price_add) == 1, "Joint crisis or actual NPC self-preservation did not execute")
		var q := Trade.quote(run, actor)
		check(int(q.req.rice) == int(Trade.OFFERS[actor].price) + 2, "Crisis and autonomous supply surcharges did not stack exactly")
		check(q.reason.contains("自主备货") and q.reason.contains("米 1"), "Fresh quote concealed its actual price causes")
		if kind == "herb_shortage": check(not q.give.has("mugwort"), "NPC autonomy bypassed crisis herb supply restriction")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	test_real_clock_and_future()
	test_support_and_wait_diverge()
	test_quotes_and_signed_promises_lock()
	test_genuine_favor_and_save_resume()
	test_morning_keeps_prepared_event()
	test_crisis_and_npc_supply_stack()
	print("NPC integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
