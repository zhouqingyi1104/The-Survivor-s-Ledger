extends Node
const State = preload("res://scripts/core/state.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Post = preload("res://scripts/core/post.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Events = preload("res://scripts/core/events.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Data = preload("res://scripts/core/data.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
var failures := 0
var completed := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func sample() -> Dictionary:
	var r := State.new_run("escort", State.new_meta(), 1001)
	Pre.start_disaster(r)
	r.home = {"rice": 5, "wood": 3, "plague_powder": 1}
	at(r, 2, 120)
	return r

func at(r: Dictionary, day: int, minute := 120) -> void:
	r.pday = day
	r.t = (day - 1) * 1440 + minute

func pick(r: Dictionary, action: String) -> void:
	var event: Dictionary = Data.table("events").get(r.pending_event, {})
	var index := -1
	for k in event.get("choices", []).size():
		if event.choices[k].id == action:
			index = k
	check(index >= 0, "Missing choice %s / %s" % [r.pending_event, action])
	if index >= 0:
		check(Events.choose(r, index) == "", "Choice blocked: " + action)

func request(r: Dictionary, action := "promise") -> void:
	check(Neighbor.poll(r) == "n_request", "Guaranteed request missing")
	pick(r, action)

func fetch(r: Dictionary, quiet := false) -> void:
	if quiet:
		check(Neighbor.prepare_pry(r) == "", "Prepare pry failed")
	check(Post.act_explore(r, "pharmacy_ruin") == "", "Cannot depart")
	check(r.explore.spots[0].name == Neighbor.CABINET, "Fixed cabinet missing")
	var before := int(r.t)
	Post.search(r, 0)
	check(int(r.t) == before + 20, "Searching cabinet must cost 20 minutes")
	check(r.pending_event == "n_cabinet", "Cabinet choice missing")
	pick(r, "pry" if quiet else "force")
	check(r.neighbor.medicine, "Task medicine not reserved")
	Post.finish_explore(r)
	check(r.pending_event == "n_delivery", "Return must offer medicine choice")

func test_delivery_and_reward() -> void:
	for quiet in [false, true]:
		var r := sample()
		request(r)
		var wood := Inv.count(r.home, "wood")
		fetch(r, quiet)
		check(Inv.count(r.home, "wood") == wood - (1 if quiet else 0), "Pry resource mismatch")
		pick(r, "deliver")
		check(Inv.count(r.home, "plague_powder") == 1, "Dedicated medicine entered regular inventory")
		check(not r.neighbor.medicine, "Donated medicine still held")
		at(r, 3, 400)
		check(Neighbor.poll(r) == "n_thanks", "Delayed thanks missing")
		var before: Dictionary = r.home.duplicate()
		pick(r, "supplies" if quiet else "food")
		check(Inv.count(r.home, "wood") == int(before.wood) + (3 if quiet else 0), "Supplies consequence missing")
		check(Inv.count(r.home, "rice") == int(before.rice) + (0 if quiet else 2), "Food consequence missing")
		var claimed := JSON.stringify(r.home)
		Events.choose(r, 0)
		check(JSON.stringify(r.home) == claimed, "Duplicate callback awarded again")
	completed += 1

func test_refuse_keep_and_late() -> void:
	for outcome in ["refuse", "keep", "late"]:
		var r := sample()
		request(r, "refuse" if outcome == "refuse" else "promise")
		if outcome == "keep":
			fetch(r)
			pick(r, "keep")
		if outcome == "late":
			at(r, 4, 720)
			Neighbor.poll(r)
		check(r.neighbor.resolution == {"refuse": "refused", "keep": "kept", "late": "late"}[outcome], "Wrong resolution")
		at(r, 5)
		check(Neighbor.poll(r) == "n_distance", "No refusal/late followup")
		var rice := Inv.count(r.home, "rice")
		pick(r, "buy_lead")
		check(Inv.count(r.home, "rice") == rice - 1, "Refusal must pay for route")
		check(r.neighbor.stage == "lead", "Paid route missing")
	var r := sample()
	request(r, "refuse")
	at(r, 5)
	Neighbor.poll(r)
	pick(r, "stay_apart")
	check(r.neighbor.stage == "closed" and r.neighbor.ending == "各守门户", "Refusal closure missing")
	completed += 1

func test_investigation_endings() -> void:
	for ending in ["share", "seal", "fortify"]:
		var r := sample()
		request(r, "donate_home")
		check(Inv.count(r.home, "plague_powder") == 0, "Home medicine not consumed")
		at(r, 3)
		Neighbor.poll(r)
		pick(r, "supplies")
		at(r, 6)
		check(Neighbor.poll(r) == "n_lead", "Day 6 lead missing")
		pick(r, "fortify" if ending == "fortify" else "investigate")
		if ending != "fortify":
			Post.act_explore(r, "mortuary")
			check(r.explore.spots[0].name == Neighbor.ACCOUNT, "Mortuary unique target missing")
			Post.search(r, 0)
			check(r.neighbor.stage == "report", "Searching ledger did not advance")
			Post.finish_explore(r)
			check(r.pending_event == "n_evidence", "Ledger return event missing")
			pick(r, ending)
			check("c_mortuary" in r.known_clues, "Investigation did not yield clue")
			check(State.flag(r, "temple_open") == (ending == "share"), "Share/seal route not different")
			check(Inv.count(r.home, "talisman") == (1 if ending == "seal" else 0), "Seal reward mismatch")
		else:
			check(not "c_mortuary" in r.known_clues, "Fortify should not invent a clue")
		check(r.neighbor.stage == "closed", "Ending remains open")
		var stable := JSON.stringify(r.home)
		Neighbor.poll(r)
		Events.choose(r, 0)
		check(JSON.stringify(r.home) == stable, "Ending replay awarded twice")
	completed += 1

func test_requirements_and_invalid() -> void:
	var r := sample()
	r.home = {}
	Neighbor.poll(r)
	var snapshot := JSON.stringify(r)
	check(Events.choose(r, 1) != "", "No medicine must block donation")
	check(Events.choose(r, -1) != "" and Events.choose(r, 99) != "", "Invalid indices accepted")
	check(JSON.stringify(r) == snapshot, "Rejected choices mutated save")
	pick(r, "promise")
	check(Neighbor.prepare_pry(r) != "", "Free pry tool")
	Post.act_explore(r, "pharmacy_ruin")
	Post.search(r, 0)
	check(Post.finish_explore(r).is_empty() and not r.explore.is_empty(), "Cabinet choice was abandoned by return")
	check(Events.choose(r, 1) != "", "Quiet entry without tool")
	check(Explore.search(r, -1).is_empty(), "Negative search index accepted")
	check(Explore.search(r, 0).is_empty(), "Cabinet repeat allowed")
	completed += 1

func test_chase_and_capacity() -> void:
	var r := sample()
	request(r)
	Post.act_explore(r, "pharmacy_ruin")
	r.explore.bag = {"wood": 100}
	r.explore.exposure = 90
	Post.search(r, 0)
	pick(r, "force")
	check(r.explore.caught, "Loud cabinet must trigger capture at 100")
	check(r.neighbor.medicine, "Capture lost quest medicine")
	check(Inv.count(r.explore.bag, "wood") < 100, "Capture lost no regular items")
	Post.finish_explore(r)
	pick(r, "deliver")
	check(r.neighbor.resolution == "donated", "Full bag/chase prevented task")
	var dying := sample()
	request(dying)
	Post.act_explore(dying, "pharmacy_ruin")
	Post.search(dying, 0)
	dying.attrs.hp = 1
	dying.explore.exposure = 90
	pick(dying, "force")
	check(dying.phase == "dead", "Fatal cabinet chase must resolve death immediately")
	completed += 1

func test_deadline_and_travel() -> void:
	var r := sample()
	request(r)
	Post.act_explore(r, "pharmacy_ruin")
	Post.search(r, 0)
	pick(r, "force")
	at(r, 4, 690)
	Post.finish_explore(r)
	check(int(r.t) == 3 * 1440 + 750, "Return travel time not charged")
	check(r.neighbor.resolution == "late" and r.pending_event == "", "Arrival after deadline incorrectly delivered")
	check(Inv.count(r.home, "plague_powder") == 2 and not r.neighbor.medicine, "Late medicine not converted exactly once")
	Neighbor.poll(r)
	check(Inv.count(r.home, "plague_powder") == 2, "Late medicine duplicated")
	var ontime := sample()
	request(ontime)
	fetch(ontime)
	at(ontime, 4, 719)
	pick(ontime, "deliver")
	check(ontime.neighbor.resolution == "donated", "Last minute donation rejected")
	completed += 1

func test_save_migration_rewind() -> void:
	var r := sample()
	request(r)
	var snapshots := {}
	Ledger.snapshot(r, snapshots)
	fetch(r, true)
	var restored: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(r)))
	check(restored.neighbor.medicine and restored.pending_event == "n_delivery", "Save lost pending delivery")
	pick(restored, "deliver")
	check(restored.neighbor.stage == "aftermath", "Reload choice failed")
	r.pday = 3
	var back := Ledger.rewind(r, snapshots, State.new_meta())
	check(back.neighbor.stage == "fetch" and not back.neighbor.medicine, "Rewind failed to restore story")
	check(Inv.count(back.home, "wood") == 3, "Rewind failed to restore tool cost")
	for day in [1, 8]:
		var old := sample()
		old.version = 9
		old.erase("neighbor")
		at(old, day)
		var old_inventory := JSON.stringify(old.home)
		Migrate.upgrade(old)
		check(old.version == Migrate.VERSION and old.neighbor.stage == ("waiting" if day == 1 else "closed"), "Migration start policy wrong")
		check(JSON.stringify(old.home) == old_inventory, "Migration changed inventory")
	var legacy := sample()
	legacy.version = 9
	legacy.flags.girl_helped = true
	Migrate.upgrade(legacy)
	check(legacy.neighbor.stage == "lead" and legacy.neighbor.reward == "legacy", "Existing help not preserved")
	completed += 1

func test_event_conflicts_and_rng() -> void:
	var r := sample()
	r.pending_event = "taoist"
	Neighbor.poll(r)
	check(r.pending_event == "taoist", "Story overwrote random event")
	r.pending_event = ""
	r.plan_due = true
	Neighbor.poll(r)
	check(r.pending_event == "", "Story interrupted night plan")
	r.plan_due = false
	r.sleeping = true
	Neighbor.poll(r)
	check(r.pending_event == "", "Story interrupted sleep")
	r.sleeping = false
	request(r)
	var count := int(r.rng_n)
	for tick in 300:
		Neighbor.poll(r)
	check(int(r.rng_n) == count, "Story polling consumed RNG")
	for roll in 200:
		var event := Events.roll(r)
		check(not event.begins_with("n_") and not event in ["neighbor_girl", "girl_gift"], "Story leaked into random pool")
	completed += 1

func _ready() -> void:
	Game.no_save = true
	var cases := [test_delivery_and_reward, test_refuse_keep_and_late, test_investigation_endings,
		test_requirements_and_invalid, test_chase_and_capacity, test_deadline_and_travel,
		test_save_migration_rewind, test_event_conflicts_and_rng]
	for test in cases:
		test.call()
	check(completed == cases.size(), "A test crashed before completion")
	print("Neighbor story: %d/%d completed, %d checks, %d failures" % [completed, cases.size(), checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
