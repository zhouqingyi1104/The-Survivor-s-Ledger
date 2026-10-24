extends Node
const Core = preload("res://scripts/core/identity_paths.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Past = preload("res://scripts/core/past_lives.gd")
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

func sample(role := "scholar", legacy := true) -> Dictionary:
	var run := State.new_run(role, State.new_meta(), 829)
	Pre.start_disaster(run)
	at(run, 6)
	run.home = {"talisman_paper": 30, "cinnabar": 30, "lamp_oil": 30, "caltrops": 30, "rice": 30, "water": 30, "wood": 30, "plague_powder": 30, "mugwort": 30}
	var main := Mainline.state(run)
	main.stage = "mortuary_choice"
	main.evidence.mortuary = true
	Past.state(run).generation = 5
	var s := Core.state(run)
	if legacy:
		for tag in Core.TAGS:
			s.inherited.append({"tag": tag, "source_life": 2, "source_id": "old-life-" + tag})
	return run

func action(run: Dictionary, id: String) -> String:
	return Core.act(run, id, str(Core.view(run).token))

func finish(run: Dictionary) -> String:
	var data: Dictionary = run.busy.get("data", {}).duplicate(true)
	run.t = int(run.busy.get("end", run.t))
	run.pday = int(run.t) / 1440 + 1
	run.busy = {}
	return Core.complete(run, data)

func test_actions_and_costs() -> void:
	for id in Core.ORDER:
		var a: Dictionary = Core.ACTIONS[id]
		var fraction := sample(str(a.role))
		fraction.attrs.energy = float(a.energy) - 0.25
		var fraction_home: Dictionary = fraction.home.duplicate(true)
		check(action(fraction, id) != "" and fraction.home == fraction_home and fraction.busy.is_empty(), "Rounded fractional energy started identity work or charged supplies: " + id)
		check(fraction.attrs.energy == float(a.energy) - 0.25, "Rejected fractional energy attempt spent energy: " + id)
		var run := sample(str(a.role))
		check(Core.options(run).size() == 2, "Identity should expose two choices per role: " + id)
		var initial: Dictionary = run.home.duplicate(true)
		var hp := State.attr(run, "hp")
		var energy := State.attr(run, "energy")
		var before := int(run.t)
		check(action(run, id) == "", "Could not start identity method: " + id)
		check(run.busy.kind == "identity" and int(run.busy.end) == before + int(a.minutes), "Identity lacks actual timed work: " + id)
		for item in a.cost: check(int(run.home.get(item, 0)) == int(initial[item]) - int(a.cost[item]), "Incorrect material cost: " + id + "/" + item)
		check(State.attr(run, "hp") == hp - int(a.hp) and State.attr(run, "energy") == energy - int(a.energy), "Incorrect energy/hp cost: " + id)
		check(Core.state(run).chosen == "" and Core.state(run).learned.is_empty() and Core.state(run).completed_t == -1, "Ability granted on start: " + id)
		var data: Dictionary = run.busy.data.duplicate(true)
		check(Core.complete(run, data) == "", "Identity work completed before actual time: " + id)
		check(action(run, id) != "", "Duplicate identity work accepted: " + id)
		run.t = int(run.busy.end) - 1
		check(Core.complete(run, data) == "" and Core.state(run).chosen == "", "Identity completed one minute early: " + id)
		check(finish(run) != "", "Identity work failed at end: " + id)
		check(Core.state(run).chosen == id and Core.state(run).completed_t == before + int(a.minutes), "Completed identity not preserved: " + id)
		check(Mainline.state(run).stage == "temple" and Mainline.state(run).evidence.mortuary and not Mainline.state(run).evidence.temple, "Identity skipped current temple proof: " + id)
		check(run.flags.get("temple_open", false), "Identity did not open real temple route: " + id)
		if str(a.cap) != "": check(Core.has(run, str(a.cap)), "Completed capability missing: " + id)
		check(Core.complete(run, data) == "", "Completed callback replayed: " + id)
		for other in Core.options(run): check(action(run, str(other.id)) != "", "Second method accepted after completion: " + id)
		check((int(Mainline.state(run).interventions.disrupt_t) >= 0) == (id == "escort_intercept"), "Identity granted unintended disruption: " + id)

func test_proof_and_access() -> void:
	var run := sample()
	Mainline.state(run).evidence.mortuary = false
	run.known_clues = ["c_taoist", "c_mortuary", "c_temple"]
	check(action(run, "scholar_collate") != "" and run.busy.is_empty(), "Inherited clues substituted for current proof")
	Mainline.state(run).evidence.mortuary = true
	for stage in ["waiting", "contact", "mortuary", "temple", "routes", "hold", "failed", "closed"]:
		Mainline.state(run).stage = stage
		check(action(run, "scholar_collate") != "", "Wrong mainline stage accepted: " + stage)
	Mainline.state(run).stage = "mortuary_choice"
	var cases := [
		["phase", "pre"], ["phase", "dead"], ["pending_event", "test"], ["dawn_due", true], ["plan_due", true], ["wave_due", true],
		["wave_report", {"done": true}], ["sleeping", true], ["busy", {"kind": "craft"}], ["explore", {"point": "mortuary"}],
		["neighbor_travel", true], ["fight", {"count": 1}], ["night", {"done": false}]]
	for condition in cases:
		var blocked := sample()
		blocked[condition[0]] = condition[1]
		check(action(blocked, "scholar_collate") != "" and Core.state(blocked).work.is_empty(), "Access condition allowed identity work: " + str(condition[0]))
	var orphan := sample()
	Mainline.state(orphan).work = {"id": "old-work"}
	check(action(orphan, "scholar_collate") != "", "Orphaned mainline work allowed parallel identity work")
	var dead := sample()
	dead.attrs.hp = 0
	check(action(dead, "scholar_collate") != "", "Zero-hp post player could start work")
	check(action(run, "escort_intercept") != "", "Cross-role method accepted")
	check(action(run, "not_a_method") != "", "Unknown identity method accepted")
	var no_supply := sample()
	no_supply.home.erase("cinnabar")
	var before: Dictionary = no_supply.home.duplicate(true)
	check(action(no_supply, "scholar_collate") != "" and no_supply.home == before and no_supply.busy.is_empty(), "Missing resource paid partial costs")
	var tired := sample()
	tired.attrs.energy = 5
	check(action(tired, "scholar_collate") != "", "Insufficient energy accepted")
	var frail := sample("escort")
	frail.attrs.hp = 12
	check(action(frail, "escort_intercept") != "" and frail.attrs.hp == 12, "Strong intercept killed player on start")
	frail.attrs.hp = 13
	check(action(frail, "escort_intercept") == "" and frail.attrs.hp == 1, "Minimum surviving intercept hp rejected")

func test_interrupt_stale_and_save() -> void:
	var run := sample()
	var stale := str(Core.view(run).token)
	check(Core.act(run, "scholar_collate", "identity:wrong-life:scholar:0") != "", "Cross-life token accepted")
	check(Core.act(run, "scholar_collate", stale) == "", "Current token rejected")
	var data: Dictionary = run.busy.data.duplicate(true)
	var paid: Dictionary = run.home.duplicate(true)
	run.busy = {}
	check(Core.poll(run) != "", "Interrupted identity work not reported")
	check(Core.state(run).work.is_empty() and Core.state(run).learned.is_empty() and run.home == paid, "Interrupted work refunded or granted skill")
	check(Core.poll(run) == "", "Interrupted work reported twice")
	check(Core.act(run, "scholar_collate", stale) != "", "Stale token survived interruption")
	run.t += 500
	check(Core.complete(run, data) == "" and not Core.has(run, "scribe_talisman"), "Cancelled callback granted capability")
	check(action(run, "scholar_diagram") == "", "Could not choose different method after interruption")
	var saved: Dictionary = str_to_var(var_to_str(run))
	check(Core.state(saved).work == Core.state(run).work and saved.busy == run.busy, "Save roundtrip changed ongoing work")
	check(finish(saved) != "" and Core.has(saved, "paper_ritual") and not Core.has(saved, "scribe_talisman"), "Restored work failed or granted both choices")
	check(not Core.has(run, "paper_ritual"), "Finishing restored copy mutated original")
	var death := sample()
	check(action(death, "scholar_collate") == "", "Death test failed to start")
	death.phase = "dead"
	check(finish(death) == "" and not Core.has(death, "scribe_talisman"), "Dead player completed identity work")
	var changed := sample()
	check(action(changed, "scholar_collate") == "", "Changed-stage test failed to start")
	Mainline.state(changed).stage = "hold"
	check(finish(changed) != "" and Core.state(changed).chosen == "", "Changed mainline phase granted identity capability")

func test_legacy_daily_and_capability_integrity() -> void:
	for id in Core.ORDER:
		var a: Dictionary = Core.ACTIONS[id]
		var run := sample(str(a.role), false)
		if str(a.legacy) != "":
			check(action(run, id) != "", "Legacy method available without actual inheritance: " + id)
			Core.state(run).inherited = [{"tag": a.legacy, "source_life": 5, "source_id": "future-source"}]
			check(action(run, id) != "", "Current/future source ordinal accepted: " + id)
			Core.state(run).inherited = [{"tag": a.legacy, "source_life": 2, "source_id": Past.state(run).id}]
			check(action(run, id) != "", "Current life pretended to be past source: " + id)
			Core.state(run).inherited = [{"tag": a.legacy, "source_life": 2, "source_id": "actual-past"}]
			check(action(run, id) == "" and finish(run) != "", "Valid legacy option failed: " + id)
			run.flags.daily = "2026-10-24"
			check(not Core.has(run, str(a.cap)) and Core.context(run).chosen == "" and Core.context(run).learned.is_empty() and Core.context(run).legacy_tags.is_empty(), "Daily restored legacy method remains active: " + id)
			var daily := sample(str(a.role))
			daily.flags.daily = "2026-10-24"
			check(action(daily, id) != "", "Daily API accepted inherited action: " + id)
		else:
			run.flags.daily = "2026-10-24"
			check(action(run, id) == "" and finish(run) != "", "Daily blocked current-role base method: " + id)
	var forged := sample()
	Core.state(forged).learned = ["scribe_talisman"]
	check(not Core.has(forged, "scribe_talisman"), "Learned flag alone granted capability")
	Core.state(forged).chosen = "scholar_collate"
	Core.state(forged).completed_t = int(forged.t) + 1
	check(not Core.has(forged, "scribe_talisman"), "Future completion granted capability")
	Core.state(forged).completed_t = int(forged.t)
	forged.role = "escort"
	check(not Core.has(forged, "scribe_talisman"), "Cross-role forged skill active")
	forged.role = "scholar"
	Core.state(forged).learned = ["scribe_talisman", "paper_ritual"]
	check(not Core.has(forged, "scribe_talisman") and not Core.has(forged, "paper_ritual"), "Two capabilities accepted from one method")
	check(Core.craft_block(forged, "scribe_talisman") != "" and Core.craft_block(forged, "efficient_plague") != "", "Locked recipes lack server rule gate")
	check(Core.craft_block(forged, "press_charcoal") == "", "Identity blocked unrelated public recipe")

func test_deadline_and_waves() -> void:
	var edge := sample()
	edge.t = Mainline.FINAL_END - 90 - 140
	var before: Dictionary = edge.home.duplicate(true)
	check(action(edge, "scholar_collate") != "" and edge.home == before, "Exact too-late work consumed resources")
	edge.t -= 1
	check(action(edge, "scholar_collate") == "", "One-minute legal work blocked")
	check(finish(edge) != "" and Core.has(edge, "scribe_talisman"), "One-minute legal completion failed")
	var late := sample()
	check(action(late, "scholar_collate") == "", "Late completion fixture start failed")
	late.busy.end = Mainline.FINAL_END - 140
	check(finish(late) != "" and Core.state(late).chosen == "", "Delayed completion granted ability after return window")
	var run := sample("herbalist")
	check(Core.wave_effect(run, 11).count_mul == 1.0, "Unfinished lure changed waves")
	check(action(run, "herbalist_lure") == "", "Lure fixture start failed")
	check(Core.wave_effect(run, 11).count_mul == 1.0, "Lure changed waves on start")
	check(finish(run) != "", "Lure fixture completion failed")
	for day in [11, 17]:
		var effect := Core.wave_effect(run, day)
		check(is_equal_approx(float(effect.count_mul), 0.9) and effect.remove_mods.is_empty(), "Lure failed reduction or removed copper armor")
	for day in [2, 5, 8, 14, 20, 23]: check(Core.wave_effect(run, day).count_mul == 1.0, "Lure affected unintended wave")
	run.wave_day = 11
	check(Core.wave_effect(run, 11).count_mul == 1.0, "Lure rewrote already opened wave")
	run.wave_day = 0
	run.night = {"wave": {"day": 17}}
	check(Core.wave_effect(run, 17).count_mul == 1.0, "Lure rewrote active locked wave")
	run.night = {}
	Core.state(run).completed_t = (11 - 1) * 1440 + 960
	run.t = Core.state(run).completed_t
	check(Core.wave_effect(run, 11).count_mul == 1.0 and Core.wave_effect(run, 17).count_mul == 0.9, "Lure accepted exact-open completion or lost future effect")

func test_public_boundary_and_history() -> void:
	var run := sample()
	var context := Core.context(run)
	var keys := context.keys()
	keys.sort()
	check(keys == ["chosen", "completed_t", "history", "learned", "legacy_tags", "role", "schema"], "Identity public context added private keys")
	check(not var_to_str(context).contains("source_id") and not context.has("work"), "Identity context leaked archive IDs/work")
	var raw: Array = Core.state(run).inherited.duplicate(true)
	Core.state(run).inherited.append({"tag": "unknown", "source_life": 1, "source_id": "bad"})
	Core.state(run).inherited.append({"tag": "sealed_lamps", "source_life": 1, "source_id": "duplicate"})
	check(Core.state(run).inherited == raw, "Malformed or duplicate legacy entry retained")
	for i in 8:
		check(action(run, "scholar_collate") == "", "Repeated interrupted work failed to restart")
		run.busy = {}
		check(Core.poll(run) != "", "Repeated work interruption missing")
	check(Core.state(run).history.size() == 12, "Identity history unbounded")
	var view := Core.view(run)
	view.history.clear()
	view.inheritance.clear()
	check(Core.state(run).history.size() == 12 and Core.state(run).inherited.size() == 4, "View exposed mutable core state")
	check(Mainline.identity_resolution(sample(), "escort_intercept") == "", "Direct free identity resolution accepted without paid work")
	var shown := Core.preview("scholar", State.new_meta())
	check(shown.headline != "" and shown.inheritance.is_empty(), "Preview falsely promised inherited option")

func _ready() -> void:
	test_actions_and_costs()
	test_proof_and_access()
	test_interrupt_stale_and_save()
	test_legacy_daily_and_capability_integrity()
	test_deadline_and_waves()
	test_public_boundary_and_history()
	print("Identity rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
