extends Node
const Core = preload("res://scripts/core/director.gd")
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Events = preload("res://scripts/core/events.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample() -> Dictionary:
	var r := State.new_run("escort", State.new_meta(), 555)
	Pre.start_disaster(r)
	r.home = {"wood": 1, "rice": 5}
	return r

func plan(base: int) -> Dictionary:
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for e in p.days: e.day += base
	return p

func at(r: Dictionary, day: int) -> void:
	r.pday = day
	r.t = (day - 1) * 1440 + 120

func _ready() -> void:
	Game.no_save = true
	var r := sample()
	var sent := Core.snapshot(r)
	check(Core.validate(plan(1), 1), "Valid plan rejected")
	check(Core.accept(r, sent, plan(1)), "Plan not accepted")
	at(r, 2)
	check(Core.poll(r).begins_with("world:"), "Prepared event missing on next day")
	check(Events.entry(r).title == "工棚的缺口", "Dynamic UI lookup missing")
	var active := Core.entry(r).duplicate(true)
	check(Core.accept(r, sent, plan(1)), "Refresh while active rejected")
	check(Core.entry(r) == active, "Refresh replaced active event")
	check(Events.choose(r, 0) == "", "Dynamic choice failed")
	check(Inv.count(r.home, "wood") == 0 and int(r.director.relations.zhou) == 1, "Cost/relation not applied")
	check(r.director.queue.is_empty() and int(r.director.revision) == 1, "Choice did not invalidate future plan")
	check(not Core.accept(r, sent, plan(1)), "Old-choice response applied")
	check(r.director.promises.size() == 1, "Promised consequence absent")
	Events.choose(r, 0)
	check(r.director.promises.size() == 1, "Double click duplicated promise")
	# New AI planning can neither remove nor modify a committed promise.
	var next := Core.snapshot(r)
	check(Core.accept(r, next, plan(2)), "Replan not accepted")
	check(r.director.promises.size() == 1, "Replan erased commitment")
	var restored: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(r)))
	restored.director.enabled = false
	at(restored, 3)
	Core.poll(restored)
	check(Inv.count(restored.home, "firewood") == 2, "Disabled/offline director broke promised delivery")
	Core.poll(restored)
	check(Inv.count(restored.home, "firewood") == 2, "Delivery duplicated")
	check(restored.director.promises.is_empty(), "Completed promise not pruned")
	var old := sample()
	old.version = 10
	old.erase("director")
	Migrate.upgrade(old)
	check(old.version == Migrate.VERSION and old.has("director"), "v11 migration failed")
	var other := sample()
	check(not Core.accept(other, sent, plan(1)), "Response contaminated new run")
	var back := sample()
	var before := Core.snapshot(back)
	back.t -= 1
	check(not Core.accept(back, before, plan(1)), "Response crossed rewind time")
	for index in 7:
		var invalid := plan(1)
		match index:
			0: invalid.days[0].choices[0].give = {"gold": 2}
			1: invalid.days[0].choices[0].give = {"rice": 100}
			2: invalid.days[0].script = "execute"
			3: invalid.days[1].day = invalid.days[0].day
			4: invalid.days[0].choices[1].req = {"water": 1}
			5: invalid.days[0].choices[0].after.days = 0
			6: invalid.days[2].choices[1].mood = 0
		check(not Core.validate(invalid, 1), "Invalid plan accepted case %d" % index)
	var poor := sample()
	var poor_sent := Core.snapshot(poor)
	Core.accept(poor, poor_sent, plan(1))
	at(poor, 2)
	poor.home = {}
	Core.poll(poor)
	var unchanged := JSON.stringify(poor)
	check(Events.choose(poor, 0) != "" and JSON.stringify(poor) == unchanged, "Unaffordable choice mutated state")
	check(Events.choose(poor, 1) == "", "Resource-free exit unavailable")
	var collision := sample()
	var s := Core.snapshot(collision)
	Core.accept(collision, s, plan(1))
	at(collision, 2)
	collision.pending_event = "taoist"
	check(Core.poll(collision) == "" and collision.pending_event == "taoist", "Director overwrote another event")
	collision.pending_event = ""
	collision.plan_due = true
	check(Core.poll(collision) == "", "Director interrupted night planning")
	var daily := sample()
	daily.flags["daily"] = "2026-10-24"
	check(not Core.state(daily).enabled, "Daily challenge received unseeded AI events")
	var dead := sample()
	var dead_sent := Core.snapshot(dead)
	dead.phase = "dead"
	check(not Core.accept(dead, dead_sent, plan(1)), "Dead run accepted future events")
	var clocked := sample()
	Neighbor.state(clocked).stage = "closed"
	at(clocked, 2)
	# Publish the new world fact before preparing this fixture's next-day plan.
	# A warning must invalidate an older plan, rather than weakening that rule.
	Post.crisis_refresh(clocked)
	Core.accept(clocked, Core.snapshot(clocked), plan(2))
	at(clocked, 3)
	clocked.t -= 10
	check(Post.advance(clocked, 20) == "event" and str(clocked.pending_event).begins_with("world:"), "Game clock did not open buffered event at 08:00")
	print("Director rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
