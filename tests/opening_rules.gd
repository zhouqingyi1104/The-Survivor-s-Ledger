extends Node
const Core = preload("res://scripts/core/opening.gd")
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Past = preload("res://scripts/core/past_lives.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample(role := "scholar", inherited := true) -> Dictionary:
	var run := State.new_run(role, State.new_meta(), 87320)
	Past.state(run).generation = 20
	var s := Core.state(run)
	# Unit fixture pins the same immutable ledger that Past.begin produces.
	s.birth = {"silver": int(run.silver), "home": run.home.duplicate(true), "role": role, "seed": int(run.seed)}
	s.inherited = []
	if inherited:
		for i in Core.TAGS.size(): s.inherited.append({"tag": Core.TAGS[i], "source_life": i + 2, "source_id": "sealed-source-" + Core.TAGS[i]})
	return run

func apply(run: Dictionary, id: String) -> String:
	return Core.apply(run, id, str(Core.view(run).token))

func protected_state(run: Dictionary) -> Dictionary:
	return {"silver": run.silver, "home": run.home.duplicate(true), "hour": run.hour, "t": run.t, "rng_n": run.rng_n, "trade": run.trade.duplicate(true), "crisis": run.crisis.duplicate(true)}

func refusal(run: Dictionary, id: String, label: String) -> void:
	var before := protected_state(run)
	check(apply(run, id) != "", label + " was accepted")
	check(protected_state(run) == before, label + " changed money, goods, relationships, clock or crisis")
	check(not Core.state(run).applied and Core.state(run).choice == "", label + " consumed opening choice")

func test_real_costs_and_mutual_exclusion() -> void:
	# Independent acceptance data for all twelve identity preparations.
	var expected := [
		["scholar_stock", "scholar", 1800, 0, {}, {"talisman_paper": 2, "cinnabar": 1, "wood": 1}, "zhou", -1, 0, "fuel_shortage", 2],
		["scholar_neighbors", "scholar", 1200, 1, {"flatbread": 1}, {"water": 3, "rice": 2}, "ning", 2, 0, "herb_shortage", 2],
		["scholar_lamps", "scholar", 2400, 1, {}, {"talisman_paper": 3, "lamp_oil": 1, "wood": 1}, "zhou", 1, 0, "well_freeze", 3],
		["escort_stock", "escort", 1600, 0, {}, {"rice": 3, "firewood": 3, "caltrops": 1}, "traveler", -1, 0, "fuel_shortage", 2],
		["escort_neighbors", "escort", 1400, 1, {"flatbread": 1}, {"wood": 2, "water": 2}, "zhou", 1, 1, "well_freeze", 2],
		["escort_oldroad", "escort", 2300, 1, {"flatbread": 1}, {"wood": 1, "nails": 2, "rice": 2}, "traveler", 2, 0, "fuel_shortage", 3],
		["herbalist_stock", "herbalist", 1000, 0, {}, {"plague_powder": 1, "mugwort": 3, "water": 2}, "ning", -1, 0, "herb_shortage", 2],
		["herbalist_neighbors", "herbalist", 1200, 1, {"salve": 1}, {"firewood": 2, "water": 2}, "ning", 2, 1, "well_freeze", 2],
		["herbalist_oldcase", "herbalist", 2000, 1, {"plague_powder": 1}, {"mugwort": 4, "water": 3}, "ning", 2, 1, "herb_shortage", 3],
		["watchman_stock", "watchman", 1000, 0, {}, {"firewood": 4, "lamp_oil": 1}, "zhou", 1, 0, "fuel_shortage", 2],
		["watchman_neighbors", "watchman", 1200, 1, {"lamp_oil": 1}, {"water": 4, "wood": 1}, "ning", 1, 1, "well_freeze", 2],
		["watchman_oldledger", "watchman", 2200, 1, {"lamp_oil": 1}, {"wood": 2, "nails": 1, "water": 2}, "traveler", 2, 0, "well_freeze", 3],
	]
	for e in expected:
		var run := sample(str(e[1]))
		var home: Dictionary = run.home.duplicate(true)
		var silver := int(run.silver)
		var old_token := str(Core.view(run).token)
		check(apply(run, str(e[0])) == "", "Cannot choose " + str(e[0]))
		Inv.take_all(home, e[4])
		Inv.add_all(home, e[5])
		check(run.home == home and int(run.silver) == silver - int(e[2]), "Incorrect real resources: " + str(e[0]))
		check(int(run.hour) == State.OPEN_HOUR + int(e[3]) and int(run.t) == 0, "Preparation did not spend pre-disaster hours: " + str(e[0]))
		var person := Trade.contact(run, str(e[6]))
		check(person.trust == e[7] and person.favors == e[8] and person.breaches == 0, "Current deed did not establish real trust/favor: " + str(e[0]))
		var first: Dictionary = Crisis.state(run).opening_reservation
		check(first.kind == e[9] and first.actor == e[6] and first.warning_day == e[10], "Incorrect first-crisis reservation: " + str(e[0]))
		check(first.real is bool and int(run.rng_n) == 0 and Crisis.context(run).can_plan == false, "Crisis is not independently seeded/locked: " + str(e[0]))
		check(Crisis.state(run).active.is_empty() and not Core.context(run).effects.has("real"), "Opening prematurely published or leaked true/false: " + str(e[0]))
		check(Core.state(run).choice == e[0] and Core.state(run).applied, "Opening decision was not saved: " + str(e[0]))
		var effect: Dictionary = Core.context(run).effects
		check(effect.silver_cost == e[2] and effect.hours == e[3] and effect.spent == e[4] and effect.gained == e[5], "Public effects disagree with payment: " + str(e[0]))
		check(effect.contacts == {e[6]: {"trust": e[7], "favors": e[8]}} and effect.first_warning == {"kind": e[9], "actor": e[6], "warning_day": e[10]}, "Public contact/crisis effects disagree: " + str(e[0]))
		var paid := protected_state(run)
		check(Core.apply(run, str(e[0]), old_token) != "", "Old same-life token replayed: " + str(e[0]))
		check(apply(run, "plain") != "" and protected_state(run) == paid, "Decision could be reset for another choice: " + str(e[0]))
		for row in Core.view(run).options: check(row.block != "", "A second option remains available: " + str(e[0]))
		check(run.known_clues.is_empty() and run.mainline.is_empty() and not run.flags.get("learned_talisman", false), "Preparation fabricated current proof, mainline or recipe: " + str(e[0]))
		check(Past.public_memories(run).is_empty(), "NPC gained omniscient memories from opening: " + str(e[0]))
		check(not Crisis.propose(run, {"kind": "well_freeze", "actor": "ning", "warning_day": int(e[10]), "real": true}, 0), "AI replaced reserved first crisis: " + str(e[0]))

func test_neutral_and_previews() -> void:
	for role in ["scholar", "escort", "herbalist", "watchman"]:
		var run := sample(role, false)
		var before := protected_state(run)
		check(apply(run, "plain") == "" and protected_state(run) == before, "Plain opening changed baseline for " + role)
		check(Core.context(run).effects == {"silver_cost": 0, "hours": 0, "spent": {}, "gained": {}, "contacts": {}, "first_warning": {}}, "Plain opening exported fabricated effects")
		check(Core.state(run).applied and Core.state(run).choice == "plain", "Plain did not fix mutually exclusive decision")
		var choices := Core.options(role, State.new_meta())
		check(choices.size() == 6, "Each role should show plain, three role paths and two memories")
		var blocked := 0
		for row in choices:
			check(row.keys().size() == 4 and row.has("id") and row.has("text") and row.has("hint") and row.has("block"), "Preview row changed public shape")
			check(not row.text.is_empty() and not row.hint.is_empty(), "Choice has no meaningful preview")
			# 不占时辰的不提时辰（不写「花 0 个时辰」），占时辰的写明花几个
			var hours := int(Core.ACTIONS[row.id].hours)
			check(row.hint.contains("花 %d 个时辰" % hours) if hours > 0 else not row.hint.contains("个时辰"), "Preview misstates preparation hours: " + str(row.id))
			if row.block != "": blocked += 1
		check(blocked == 3, "Fresh preview must allow exactly plain and two base preparations")
		for mode in [[true, []], [false, ["bare"]]]:
			for row in Core.options(role, State.new_meta(), mode[0], mode[1], "normal"):
				check((row.block == "") == (row.id == "plain"), "Daily/bare preview offers alternate resources")
	check(Core.ORDER.size() == 15 and Core.ACTIONS.size() == 15, "Preparation catalog must contain exactly fifteen decisions")
	check(Core.options("unknown", State.new_meta()).is_empty(), "Unknown role has usable preparation options")
	var no_birth := sample()
	Core.state(no_birth).birth = {}
	refusal(no_birth, "scholar_stock", "Nonplain without birth proof")
	check(apply(no_birth, "plain") == "", "Missing old birth proof blocked neutral play")

func test_failures_are_atomic() -> void:
	var changes := [
		["phase", "post"], ["phase", "dead"], ["day", 2], ["day", 1.25], ["hour", 4], ["hour", 2], ["hour", 3.25], ["loc", "rice_shop"], ["t", 1], ["t", 0.25],
		["cart", {"rice": 1}], ["orders", ["iron_door"]], ["busy", {"kind": "craft"}], ["sleeping", true], ["pending_event", "event"]
	]
	for mutation in changes:
		var run := sample()
		run[mutation[0]] = mutation[1]
		refusal(run, "scholar_stock", "Changed " + str(mutation[0]) + ": " + str(mutation[1]))
	for pair in [["bought", {"rice": 1}], ["home_trips", 1], ["orders", 1], ["repair_door", 1]]:
		var run := sample()
		run.tally[pair[0]] = pair[1]
		refusal(run, "scholar_stock", "Prior tally " + str(pair[0]))
	for key in ["quotes", "debt", "aid"]:
		var run := sample()
		var trade := Trade.state(run)
		trade[key] = [{"keep": "promise"}] if key == "aid" else {"keep": "promise"}
		refusal(run, "scholar_stock", "Existing signed/displayed " + key)
	for pair in [["pending", {"kind": "well_freeze"}], ["active", {"id": "old-warning"}], ["serial", 1], ["opening_reservation", {"kind": "herb_shortage"}]]:
		var run := sample()
		Crisis.state(run)[pair[0]] = pair[1]
		refusal(run, "scholar_stock", "Existing crisis " + str(pair[0]))
	var changed := sample()
	changed.silver = int(changed.silver) - 1
	refusal(changed, "scholar_stock", "Money already changed")
	changed = sample()
	Inv.add(changed.home, "rice", 1)
	refusal(changed, "scholar_stock", "Inventory already changed")
	changed = sample()
	changed.seed = int(changed.seed) + 1
	refusal(changed, "scholar_stock", "Birth seed changed")
	changed = sample()
	Core.state(changed).birth.role = "escort"
	refusal(changed, "scholar_stock", "Birth role mismatch")
	var poor := sample()
	poor.silver = 1799
	Core.state(poor).birth.silver = 1799
	refusal(poor, "scholar_stock", "Insufficient silver")
	var no_bread := sample()
	no_bread.home.erase("flatbread")
	Core.state(no_bread).birth.home = no_bread.home.duplicate(true)
	refusal(no_bread, "scholar_neighbors", "Insufficient promised gift")
	var cross_role := sample("escort")
	refusal(cross_role, "scholar_stock", "Cross-role preparation")
	var no_hp := sample()
	no_hp.attrs.hp = 0
	refusal(no_hp, "scholar_stock", "Zero-hp opening")
	refusal(sample(), "unknown", "Unknown preparation")
	var fresh := sample()
	var stale := str(Core.view(sample()).token)
	var before := protected_state(fresh)
	check(Core.apply(fresh, "scholar_stock", stale) != "" and protected_state(fresh) == before, "Previous-life token changed new life")

func test_legacy_and_daily_boundaries() -> void:
	for pair in [["scholar", "scholar_lamps", "sealed_lamps"], ["escort", "escort_oldroad", "escaped_city"], ["herbalist", "herbalist_oldcase", "gave_medicine"], ["watchman", "watchman_oldledger", "returned_evidence"]]:
		var run := sample(str(pair[0]), false)
		refusal(run, str(pair[1]), "No genuine inherited " + str(pair[2]))
		Core.state(run).inherited = [{"tag": pair[2], "source_life": 20, "source_id": "future"}]
		refusal(run, str(pair[1]), "Same-generation legacy " + str(pair[2]))
		Core.state(run).inherited = [{"tag": pair[2], "source_life": 21, "source_id": "future"}]
		refusal(run, str(pair[1]), "Future-generation legacy " + str(pair[2]))
		Core.state(run).inherited = [{"tag": pair[2], "source_life": 2, "source_id": Past.state(run).id}]
		refusal(run, str(pair[1]), "Own-life legacy " + str(pair[2]))
		Core.state(run).inherited = [{"tag": pair[2], "source_life": 2, "source_id": "confirmed-old-life"}]
		check(apply(run, str(pair[1])) == "", "Valid fixed legacy failed: " + str(pair[2]))
	for id in Core.ORDER:
		var a: Dictionary = Core.ACTIONS[id]
		var role: String = "scholar" if a.role == "" else str(a.role)
		var daily := sample(role)
		daily.flags["daily"] = "2026-10-24"
		check(Core.context(daily).legacy_tags.is_empty(), "Daily opening exposed private legacy tags")
		if id == "plain": check(apply(daily, id) == "", "Daily plain opening failed")
		else: refusal(daily, id, "Direct daily " + id)
		var bare := sample(role)
		bare.tally.vows = ["bare"]
		if id == "plain": check(apply(bare, id) == "", "Bare plain opening failed")
		else: refusal(bare, id, "Direct bare " + id)
	var lost := sample()
	Core.state(lost).inherited = [{"tag": "gave_medicine", "source_life": "2", "source_id": "bad"}, {"tag": "new_effect", "source_life": 2, "source_id": "bad"}]
	check(Core.context(lost).legacy_tags.is_empty(), "Malformed source conferred opening eligibility")
	var legacy := sample()
	legacy.opening = {"schema": 1, "legacy": true, "choice": "plain", "applied": true}
	var before := protected_state(legacy)
	check(Core.view(legacy).summary.contains("照原来的开局") and Core.context(legacy).effects.gained.is_empty(), "Old saves claimed a newly given opening")
	check(apply(legacy, "scholar_stock") != "" and protected_state(legacy) == before, "Old save retroactively claimed starting goods")

func test_generic_sources_and_tie_order() -> void:
	var cash := sample()
	check(apply(cash, "cash_account") == "", "Known old breach did not permit a new cash deed")
	check(Core.context(cash).effects.contacts == {"traveler": {"trust": 2, "favors": 0}} and Core.context(cash).effects.first_warning == {"kind": "well_freeze", "actor": "traveler", "warning_day": 2}, "Cash deed did not use latest fixed breach source")
	check(Trade.state(cash).debt.is_empty() and Trade.contact(cash, "traveler").breaches == 0, "Old breach became a new debt or NPC remembered accusation")
	var old_crisis := sample()
	check(apply(old_crisis, "old_crisis") == "", "Known endured crisis did not unlock generic reserve")
	check(Core.context(old_crisis).effects.first_warning == {"kind": "herb_shortage", "actor": "ning", "warning_day": 3}, "Old crisis did not use latest fixed genuine source")
	for id in ["cash_account", "old_crisis"]:
		refusal(sample("scholar", false), id, "Generic without confirmed source " + id)
	var tied := sample()
	Core.state(tied).inherited = [{"tag": "breach_traveler", "source_life": 3, "source_id": "same-life"}, {"tag": "breach_ning", "source_life": 3, "source_id": "same-life"}, {"tag": "breach_zhou", "source_life": 3, "source_id": "same-life"}]
	check(apply(tied, "cash_account") == "" and Core.context(tied).effects.contacts.has("ning"), "Archive enumeration changed tie-break source")
	var only_fuel := sample()
	Core.state(only_fuel).inherited = [{"tag": "crisis_fuel_shortage", "source_life": 3, "source_id": "old-fuel"}]
	check(apply(only_fuel, "old_crisis") == "" and Core.context(only_fuel).effects.first_warning.kind == "fuel_shortage" and Core.context(only_fuel).effects.contacts.has("zhou"), "Old fuel crisis did not affect current local path")
	var no_meta := sample("scholar", false)
	var unrelated_meta := State.new_meta()
	unrelated_meta.past_lives.count = 100
	unrelated_meta.past_lives.sealed_ids = ["later-sealed"]
	unrelated_meta.past_lives.opening_legacy = [{"tag": "sealed_lamps", "source_life": 99, "source_id": "later-sealed"}]
	Core.options("scholar", unrelated_meta)
	refusal(no_meta, "scholar_lamps", "Later metadata query conferred source to existing birth")

func test_save_query_and_public_boundaries() -> void:
	var run := sample("herbalist")
	var fixed: Dictionary = Core.state(run).birth.duplicate(true)
	var view := Core.view(run)
	var ctx := Core.context(run)
	check(ctx.keys().size() == 6 and ctx.has("schema") and ctx.has("role") and ctx.has("choice") and ctx.has("applied") and ctx.has("effects") and ctx.has("legacy_tags"), "Public opening context shape changed")
	check(not var_to_str(ctx).contains("source_id") and not var_to_str(ctx).contains("source_life") and not var_to_str(ctx).contains("birth") and not var_to_str(ctx).contains('"real"'), "Public opening context leaked provenance or true/false")
	check(view.source_label.contains("第") and not view.source_label.contains("sealed-source"), "Player source label is private ID or lacks usable provenance")
	view.options.clear()
	view.history.append({"day": 1, "action": "bad", "result": "injected"})
	view.effects.gained["rice"] = 999
	ctx.legacy_tags.clear()
	check(Core.state(run).birth == fixed and Core.state(run).history.is_empty() and Core.context(run).legacy_tags.size() == 10 and Core.view(run).options.size() == 6, "Read views mutate core state")
	check(apply(run, "herbalist_oldcase") == "", "Cannot apply before save/rewind comparison")
	# Match Game._read_json: real saves normalize integral JSON numbers.
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	check(Core.context(saved) == Core.context(run) and Core.view(saved).effects == Core.view(run).effects, "Save/load changed real opening effects")
	var after := protected_state(saved)
	check(apply(saved, "herbalist_neighbors") != "" and protected_state(saved) == after, "Reloaded paid opening could be claimed again")
	var same := sample("herbalist")
	check(apply(same, "herbalist_oldcase") == "" and same.home == run.home and same.hour == run.hour and Crisis.state(same).opening_reservation == Crisis.state(run).opening_reservation, "Same seed/role/choice changed goods, hours or independent crisis")
	var clamped := sample("escort")
	Trade.state(clamped).actors.zhou.favors = 3
	Trade.state(clamped).actors.zhou.trust = 5
	check(apply(clamped, "escort_neighbors") == "" and Trade.contact(clamped, "zhou").favors == 3 and Trade.contact(clamped, "zhou").trust == 5, "Opening bypassed relationship caps")
	check(Core.context(clamped).effects.contacts == {"zhou": {"trust": 0, "favors": 0}}, "Clamped context falsely claimed unreceived relationship increments")
	var corrupt := run.duplicate(true)
	corrupt.opening.effects["real"] = true
	corrupt.opening.effects["source_id"] = "private-hidden-id"
	check(not var_to_str(Core.context(corrupt)).contains("private-hidden-id") and not Core.context(corrupt).effects.has("real"), "Saved private or unknown effects leaked through context")
	for i in 20: Core.state(clamped).history.append({"day": 1, "action": "fixture", "result": "history"})
	check(Core.state(clamped).history.size() == 8, "Opening history is unbounded")

func _ready() -> void:
	test_real_costs_and_mutual_exclusion()
	test_neutral_and_previews()
	test_failures_are_atomic()
	test_legacy_and_daily_boundaries()
	test_generic_sources_and_tie_order()
	test_save_query_and_public_boundaries()
	print("Opening rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
