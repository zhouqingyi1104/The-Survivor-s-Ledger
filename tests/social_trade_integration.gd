extends Node
## 本地跨系统验收：真实剧情/世情选择、时钟与存档事实，不调用模型或玩家文件。
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Events = preload("res://scripts/core/events.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 9741)
	Pre.start_disaster(run)
	at(run, 2)
	run.home = {"rice": 40, "wood": 8, "nails": 6, "mugwort": 8, "water": 10, "plague_powder": 1}
	Director.state(run).enabled = false
	# This legacy suite measures exactly one trade fact. NPC/world-clock
	# combinations have their own npc_integration scene; keep assertions exact.
	Npcs.state(run).next_day = 100000
	return run

func action(run: Dictionary, actor: String, id: String) -> String:
	return Post.trade_action(run, actor, id, str(Trade.quote(run, actor).id))

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	var helped := sample()
	Neighbor.poll(helped)
	check(helped.pending_event == "n_request", "Real neighbor request absent")
	check(Events.choose(helped, 1) == "", "Real medicine donation failed")
	var distant := sample()
	Neighbor.poll(distant)
	check(Events.choose(distant, 2) == "", "Real neighbor refusal failed")
	check(int(Trade.contact(helped, "ning").trust) > int(Trade.contact(distant, "ning").trust), "Neighbor choices did not affect actual credit")
	check(int(Trade.quote(helped, "ning").req.rice) < int(Trade.quote(distant, "ning").req.rice), "Neighbor choices did not change real quoted cost")
	var had := int(Trade.contact(helped, "ning").trust)
	Trade.observe_neighbor(helped, "donate_home")
	check(int(Trade.contact(helped, "ning").trust) == had, "Neighbor hook replayed a past choice")

	var dynamic := sample()
	var d := Director.state(dynamic)
	d.relations.zhou = 2
	# Clear lazy trade so first influence must seed the old, not already increased, relation.
	dynamic.trade = {}
	d.active = {"uid": "world:trade-integration", "actor": "zhou", "title": "此前帮过的忙", "choices": [{"id": "assist", "text": "交出木料", "result": "老周收下木料。", "req": {"wood": 1}, "relation": 1}]}
	dynamic.pending_event = d.active.uid
	check(Events.choose(dynamic, 0) == "", "Real director choice failed")
	check(int(Trade.contact(dynamic, "zhou").trust) == 3, "First dynamic choice seeded relation twice")
	# Settle a separately observable warning before measuring one trade's revision.
	Post.crisis_refresh(dynamic)
	var sent := Director.snapshot(dynamic)
	check(sent.state.trade.actors.zhou.trust == 3, "Director did not receive executable credit")
	d.queue = [{"sentinel": true}]
	var revision := int(d.revision)
	check(action(dynamic, "zhou", "cash") == "", "Post transaction entry failed")
	check(d.queue.is_empty() and int(d.revision) == revision + 1, "Completed trade did not invalidate unseen AI plan")
	check(not Past.state(dynamic).trace.is_empty(), "Trade facts absent from actual past-life trace")

	var aided := sample()
	Neighbor.state(aided).stage = "closed"
	check(action(aided, "zhou", "aid") == "", "Material aid failed")
	var due: Dictionary = Trade.context(aided).aid[0].duplicate(true)
	at(aided, int(due.due_day), 110)
	aided.sleeping = true
	var before := Inv.count(aided.home, "firewood")
	var expected := int(due.give.get("firewood", 0))
	revision = int(Director.state(aided).revision)
	Post.advance(aided, 10)
	check(Trade.context(aided).aid.is_empty(), "Sleeping/offline time advance missed promised gift")
	check(Inv.count(aided.home, "firewood") == before + expected, "Gift inventory did not match locked promise")
	check(int(Director.state(aided).revision) == revision + 1, "Gift was not added to director facts")
	Post.trade_refresh(aided)
	check(Inv.count(aided.home, "firewood") == before + expected, "Refreshing gift duplicated reward")

	var borrowed := sample()
	Neighbor.state(borrowed).stage = "closed"
	Trade.influence(borrowed, "zhou", 3, "验收：先前帮助")
	check(action(borrowed, "zhou", "credit") == "", "Trusted contact did not lend")
	var debt: Dictionary = Trade.context(borrowed).debt.duplicate(true)
	at(borrowed, int(debt.due_day), 710)
	var grain := Inv.count(borrowed.home, "rice")
	Post.advance(borrowed, 10)
	check(Trade.context(borrowed).debt.overdue, "Actual dusk checkpoint missed credit deadline")
	check(int(Trade.contact(borrowed, "zhou").breach_total) == 1, "Dusk did not record exactly one breach")
	check(Inv.count(borrowed.home, "rice") == grain, "Deadline silently confiscated inventory")
	Post.trade_refresh(borrowed)
	check(int(Trade.contact(borrowed, "zhou").breach_total) == 1, "Repeated polling penalized one debt twice")
	at(borrowed, int(debt.due_day) + 1)
	check(action(borrowed, "zhou", "repay") == "", "Late repayment not executable")
	check(Trade.context(borrowed).debt.is_empty(), "Late repayment left active debt")
	check(int(Trade.contact(borrowed, "zhou").breaches) > 0, "Repayment erased unremedied breach")
	check(action(borrowed, "zhou", "compensate") == "", "Actual material compensation unavailable")
	check(int(Trade.contact(borrowed, "zhou").breach_total) == 1, "Compensation rewrote prior breach history")

	# New random events use the active channel; an already displayed old quote
	# stays payable even when the new contact's credit terms are worse.
	var legacy := sample()
	at(legacy, 4)
	var draws := 0
	for k in 400:
		var id := Events.roll(legacy)
		check(not id in ["paper_crane", "paper_crane_wood"], "Legacy fixed-price draw bypassed new correspondence")
		if id != "": draws += 1
	check(draws > 0, "Legacy migration accidentally disabled all random content")
	legacy.home["jerky"] = 1
	legacy.pending_event = "paper_crane_wood"
	var wood := Inv.count(legacy.home, "wood")
	check(Events.choose(legacy, 0) == "", "Already displayed legacy quote was revoked")
	check(Inv.count(legacy.home, "jerky") == 0 and Inv.count(legacy.home, "wood") == wood + 4, "Legacy pending transaction changed its signed goods")
	print("Social trade integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
