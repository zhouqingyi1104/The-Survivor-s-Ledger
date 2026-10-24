extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Opening = preload("res://scripts/core/opening.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
const Director = preload("res://scripts/core/director.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func sample(meta: Dictionary, role := "scholar", day := 6) -> Dictionary:
	var run := State.new_run(role, meta, 28901)
	Pre.start_disaster(run)
	run.pday = day; run.t = (day - 1) * 1440 + 180
	return run

func resolved(kind: String, outcome := "averted") -> Dictionary:
	return {"id": "old-" + kind, "kind": kind, "actor": "ning", "stage": "resolved", "warning_day": 2, "impact_t": 5040, "end_t": 7320, "investigated": true, "confirmed": "real", "response": "emergency" if outcome == "repaired" else "prepare", "protected": outcome != "repaired", "outcome": outcome}

func genuine(meta: Dictionary) -> Dictionary:
	var run := sample(meta)
	var trade := Trade.state(run)
	for actor in Past.ACTORS:
		trade.actors[actor].breaches = 1
		trade.actors[actor].breach_total = 1
	var crisis := Crisis.state(run)
	crisis.completed = []
	for kind in Past.CRISIS_KINDS: crisis.completed.append(resolved(kind, "repaired" if kind == "fuel_shortage" else "averted"))
	var story := Mainline.state(run)
	story.evidence = {"mortuary": true, "temple": true}; story.stage = "sealed"; story.route = "ritual"; story.interventions.ritual_t = int(run.t) - 60
	Past.record(run, "ning", "medicine", "本世实际给过药，未确认疗效。", 1)
	run.phase = "dead"
	check(Past.archive(run, meta), "Could not archive structured old-life source")
	return run

func tags(meta: Dictionary) -> Array:
	var out := []
	for source in Past.opening_inheritance(meta): out.append(source.tag)
	return out

func test_sources() -> Dictionary:
	var meta := State.new_meta()
	var before := State.new_run("scholar", meta, 22)
	check(tags(meta).is_empty(), "Fresh history invented an opening source")
	var source := genuine(meta)
	var actual := tags(meta)
	for tag in Past.OPENING_TAGS: check(tag in actual, "Genuine outcome did not unlock " + tag)
	for tag in ["sealed_lamps", "returned_evidence", "gave_medicine"]: check(tag in actual, "Identity experience omitted from opening inheritance: " + tag)
	check(meta.past_lives.opening_legacy.size() == 6 and actual.size() == 9, "Opening cache duplicated identity sources or exceeded its six-tag bound")
	var after := State.new_run("herbalist", meta, 23)
	check(before.opening.inherited.is_empty() and after.opening.inherited == Past.opening_inheritance(meta), "Birth did not pin exactly the then-sealed opening sources")
	check(after.opening.birth.home == after.home and after.opening.birth.silver == after.silver and after.opening.birth.role == after.role and after.opening.birth.seed == after.seed, "Birth did not pin original resources")
	after.home["rice"] = 99
	check(after.opening.birth.home.get("rice", 0) != 99, "Birth inventory aliases mutable home")
	check(Past.public_memories(after).is_empty() and Past.state(after).awakenings.is_empty(), "Player opening experience automatically awakened an NPC")
	check(Trade.state(after).debt.is_empty() and Trade.state(after).aid.is_empty(), "Old breach created a new debt or claimable gift")
	var fixed: Array = after.opening.inherited.duplicate(true)
	genuine(meta)
	check(after.opening.inherited == fixed and before.opening.inherited.is_empty(), "An existing life learned from a later sealed source")
	for entry in Past.opening_inheritance(meta): check(entry.source_id != Past.state(source).id, "Latest structured source was not selected")
	var stable := meta.duplicate(true)
	check(not Past.archive(source, meta) and meta == stable, "Repeated sealing duplicated opening legacy")
	var escaped := sample(meta, "escort", 18)
	var route := Mainline.state(escaped)
	route.evidence = {"mortuary": true, "temple": true}; route.stage = "closed"; route.route = "escape"; route.escape_method = "normal"
	route.ending = {"kind": "escape", "title": "离城余生", "text": "实际离城而非筹备。", "bonus": 0, "can_continue": false}
	escaped.phase = "ending"
	check(Past.archive(escaped, meta) and tags(meta).size() == 10, "Actual escape did not complete ten bounded qualification tags")
	return meta

func test_invalid_sources(meta: Dictionary) -> void:
	for variant in ["unsealed", "future", "daily", "bad_role", "bad_day", "duplicate_id", "duplicate_ordinal", "fractional_breach", "negative_breach", "trust_only"]:
		var bad := meta.duplicate(true)
		match variant:
			"unsealed": bad.past_lives.sealed_ids = []
			"future": bad.past_lives.count = 0
			"daily":
				for life in bad.past_lives.lives: life.summary.mode = "每日一局"
			"bad_role":
				for life in bad.past_lives.lives: life.summary.role = "wizard"
			"bad_day":
				for life in bad.past_lives.lives: life.summary.day = -1
			"duplicate_id", "duplicate_ordinal": bad.past_lives.lives.append_array(bad.past_lives.lives.duplicate(true))
			"fractional_breach", "negative_breach", "trust_only":
				for life in bad.past_lives.lives:
					for actor in Past.ACTORS:
						life.summary.trade.actors[actor].breach_total = 1.5 if variant == "fractional_breach" else (-1 if variant == "negative_breach" else 0)
						life.summary.trade.actors[actor].breaches = 0
						life.summary.trade.actors[actor].trust = -5
		var found := tags(bad)
		if variant in ["fractional_breach", "negative_breach", "trust_only"]:
			for actor in Past.ACTORS: check(not "breach_" + actor in found, "Trust or malformed total invented an actual old breach: " + variant)
		else: check(found.is_empty(), "Malformed or unsealed source unlocked opening: " + variant)
	for variant in ["false_alarm", "start_only", "unfinished", "unprotected", "wrong_response", "future_impact", "private_pending", "natural_end"]:
		var bad := meta.duplicate(true)
		for life in bad.past_lives.lives:
			if not life.summary.has("crisis"): continue
			for a in life.summary.crisis.completed:
				match variant:
					"false_alarm": a.confirmed = "false"; a.outcome = "false_alarm"
					"start_only": a.stage = "warning"; a.confirmed = "unknown"; a.investigated = false; a.outcome = ""
					"unfinished": a.outcome = ""; a.protected = false
					"unprotected": a.outcome = "averted"; a.protected = false
					"wrong_response": a.response = "ignore"
					"future_impact": life.summary.day = 2
					"natural_end": a.outcome = "endured"; a.response = "ignore"
					"private_pending": pass
			if variant == "private_pending": life.summary.crisis = {"schema": 1, "active": {}, "completed": [], "history": [], "pending": {"kind": "well_freeze", "real": true}}
		for kind in Past.CRISIS_KINDS: check(not "crisis_" + kind in tags(bad), "Uncompleted/false/private crisis granted experience: " + variant)
	var text_only := State.new_meta()
	var empty := sample(text_only)
	Past.record(empty, "ning", "story", "我处理过所有危机，并已欠过所有人债。", 1)
	empty.phase = "dead"; Past.archive(empty, text_only)
	check(tags(text_only).is_empty(), "Narrative prose invented structured opening qualification")

func test_permanent_index(meta: Dictionary) -> void:
	var old := meta.duplicate(true)
	var expected := Past.opening_inheritance(old)
	for k in 10:
		var quiet := sample(old, "watchman", 1)
		quiet.flags["daily"] = "2026-10-24"
		# Even misleading daily state is never a qualification source.
		var trade := Trade.state(quiet)
		trade.actors.ning.breach_total = 5
		quiet.phase = "dead"; check(Past.archive(quiet, old), "Could not seal a daily life while retaining old index")
	check(old.past_lives.lives.size() == 8 and old.past_lives.opening_legacy.size() == 6 and Past.opening_inheritance(old) == expected, "Trim/daily play erased genuine permanent opening experience")
	check(State.new_run("escort", old, 88).opening.inherited == expected, "Future birth lost distant confirmed experience")
	var missing := old.duplicate(true)
	missing.past_lives.erase("opening_legacy")
	for kind in Past.CRISIS_KINDS: check(not "crisis_" + kind in tags(missing), "Missing index reconstructed forgotten distant outcomes")
	var malformed := old.duplicate(true)
	malformed.past_lives.opening_legacy = [{"tag": "breach_ning", "source_life": 1000, "source_id": "unknown"}]
	check(not "breach_ning" in tags(malformed), "Unknown or future cached source survived")
	var repeated := old.duplicate(true)
	var first: Dictionary = repeated.past_lives.opening_legacy[0].duplicate(true)
	repeated.past_lives.opening_legacy = [first, first.duplicate()]
	check(not first.tag in tags(repeated), "Duplicate cached tags granted a trimmed source")
	var upgrade := meta.duplicate(true)
	upgrade.past_lives.erase("opening_legacy")
	for k in 10:
		var daily := sample(upgrade, "watchman", 1); daily.flags["daily"] = "fixed"; daily.phase = "dead"; Past.archive(daily, upgrade)
	check(Past.opening_inheritance(upgrade) == expected, "Daily-only play erased pre-index genuine normal experiences during upgrade")

func neutral() -> Dictionary:
	return {"silver_cost": 0, "hours": 0, "spent": {}, "gained": {}, "contacts": {}, "first_warning": {}}

func test_snapshot_and_actual_file(meta: Dictionary) -> Dictionary:
	var run := sample(meta)
	var sources: Array = run.opening.inherited.duplicate(true)
	run.opening = {"schema": 1, "choice": "cash_account", "applied": true, "effects": {"silver_cost": 1200, "hours": 1, "spent": {"rice": 1}, "gained": {"wood": 2}, "contacts": {"ning": {"trust": 1, "favors": 0}}, "first_warning": {"kind": "herb_shortage", "actor": "ning", "warning_day": 3}}, "history": [{"day": 1, "action": "cash_account", "result": "今世主动采用现钱往来，付出开局物资，不搬来旧债。"}], "birth": {"secret": "PRIVATE_BIRTH"}, "inherited": [{"source_id": "PRIVATE_SOURCE"}]}
	run.opening.inherited = sources
	var safe := Past.opening_snapshot(run.opening)
	check(not safe.is_empty() and not JSON.stringify(safe).contains("PRIVATE"), "Opening archive leaked private birth/source")
	for variant in ["applied", "choice", "silver_cost", "hours", "quantity", "contact", "real", "extra_effect", "history"]:
		var bad: Dictionary = run.opening.duplicate(true)
		match variant:
			"applied": bad.applied = false
			"choice": bad.choice = "invented"
			"silver_cost": bad.effects.silver_cost = 3001
			"hours": bad.effects.hours = 1.5
			"quantity": bad.effects.gained.wood = 5
			"contact": bad.effects.contacts.ning.trust = 3
			"real": bad.effects.first_warning.real = true
			"extra_effect": bad.effects.recipe = "free"
			"history": bad.history[0].day = 99
		check(Past.opening_snapshot(bad).is_empty(), "Malformed opening archive accepted: " + variant)
	run.phase = "dead"
	var book := meta.duplicate(true)
	check(Past.archive(run, book), "Could not seal actual opening archive")
	var file := "user://opening-memory-%d.md" % OS.get_process_id()
	check(Archive.sync(book, file) == OK, "Actual opening Memory write failed")
	var actual := Archive.read_context(file)
	for phrase in ["旧世可变开局", "实际付银 1200 文", "原资源支出", "今世开局往来", "首场未核实方向", "不表示已成真、已核实或已防住", "不是新世债务"]: check(str(actual.get("markdown", "")).contains(phrase), "Actual Memory omitted choice consequence or boundary: " + phrase)
	check(not actual.get("markdown", "").contains("PRIVATE"), "Actual Memory leaked source identity")
	var before := actual.duplicate(true)
	check(Archive.sync(book, file) == OK and Archive.read_context(file) == before, "Repeated sync changed same-generation opening archive")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK, "Could not remove isolated opening archive")
	return actual

func test_daily_legacy_and_archive_gate(meta: Dictionary) -> void:
	var legacy := State.new_run("scholar", meta, 83)
	legacy.opening = {"schema": 1, "legacy": true, "choice": "plain", "applied": true, "effects": {}, "history": [], "inherited": []}
	check(Opening.context(legacy).effects == neutral() and Past.opening_snapshot(legacy.opening).effects == neutral(), "Migrated neutral legacy receipt was not normalized without new grants")
	var inventory: Dictionary = legacy.home.duplicate(true)
	check(Opening.apply(legacy, "scholar_stock", str(Opening.view(legacy).token)) != "" and legacy.home == inventory, "Legacy save accepted a new opening grant")
	var daily := State.new_run("scholar", meta, 84)
	daily.flags["daily"] = "2026-10-24"
	check(Opening.context(daily).legacy_tags.is_empty(), "Daily public context disclosed inherited source tags")
	check(Opening.apply(daily, "scholar_lamps", str(Opening.view(daily).token)) != "", "Daily accepted an inherited opening")
	check(Opening.apply(daily, "plain", str(Opening.view(daily).token)) == "" and Opening.context(daily).effects == neutral(), "Daily did not retain neutral plain opening")
	for variant in ["daily_nonplain", "wrong_role", "missing_source", "future_source", "same_life"]:
		var book := meta.duplicate(true)
		var run := sample(book, "scholar")
		run.opening.choice = "scholar_lamps"; run.opening.applied = true
		run.opening.effects = {"silver_cost": 2400, "hours": 1, "spent": {}, "gained": {"talisman_paper": 3}, "contacts": {"zhou": {"trust": 1, "favors": 0}}, "first_warning": {"kind": "well_freeze", "actor": "zhou", "warning_day": 3}}
		match variant:
			"daily_nonplain": run.flags["daily"] = "fixed"
			"wrong_role": run.role = "escort"
			"missing_source": run.opening.inherited = []
			"future_source":
				for source in run.opening.inherited: source.source_life = Past.state(run).generation
			"same_life":
				for source in run.opening.inherited: source.source_id = Past.state(run).id
		run.phase = "dead"
		check(Past.archive(run, book) and not book.past_lives.lives.back().summary.has("opening"), "Damaged opening was archived as actual grants: " + variant)

func test_public_context_and_guard(meta: Dictionary) -> void:
	var contexts := []
	for id in Past.OPENING_CHOICES:
		var role := "escort"
		for candidate in Past.IDENTITY_ROLES:
			if id.begins_with(candidate + "_"): role = candidate
		var run := State.new_run(role, meta, 907)
		# Sources were genuinely sealed above. All fifteeen context choices are
		# actual local rule applications, not invented model effects.
		var result: String = Opening.apply(run, id, str(Opening.view(run).token))
		check(result == "", "Actual opening apply failed for public fixture " + id + ": " + result)
		var context := Director.snapshot(run)
		contexts.append(context)
		var raw := JSON.stringify(context.state.opening)
		for hidden in ["source_id", "source_life", "birth", "inherited", "real", "protected", "history"]: check(not raw.contains('"' + hidden + '"'), "Opening public context leaked " + hidden)
		check(context.state.recollections.is_empty() and context.state.npcs.actors.ning.memory.is_empty(), "Opening informed an unawakened NPC")
	var output := FileAccess.open(OS.get_environment("TEMP").path_join("ledger-opening-public-fixtures.json"), FileAccess.WRITE)
	check(output != null, "Could not export actual fictional Godot opening contexts")
	if output != null: output.store_string(JSON.stringify(contexts)); output.close()
	var run := sample(meta, "scholar", 1)
	for item in Director.GOODS: run.home[item] = 20
	Mainline.state(run).start_day = 100
	run.identity = {"schema": 1, "inherited": []}
	run.opening = {"schema": 1, "choice": "scholar_stock", "applied": true, "effects": {"silver_cost": 1000, "hours": 1, "spent": {}, "gained": {"talisman_paper": 2}, "contacts": {}, "first_warning": {}}, "inherited": []}
	var sent := Director.snapshot(run)
	check(not sent.state.mainline.published and sent.state.identity.legacy_tags.is_empty(), "Opening guard fixture was masked by other guards")
	var plan: Dictionary = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json")))
	var claim := "MODEL_OPENING_CLAIM：重复发开局赠礼，旧债转世，邻人认出前世，首危机已免疫。"
	for e in plan.days:
		e.day += 1; e.title = "MODEL_OPENING_CLAIM"; e.text = claim
		for choice in e.choices: choice.text = "MODEL_OPENING_CLAIM"; choice.result = claim
	plan.days[0].choices[0].after = {"days": 1, "give": {"wood": 1}, "text": claim}
	check(Director.accept(run, sent, plan), "Opening prose guard rejected valid economic plan")
	run.pday = 2; run.t = 1620; Past.state(run).schedule = []
	check(Director.poll(run).begins_with("world:"), "Opening-guarded economic event did not open")
	var raw: Dictionary = Director.state(run).active
	var shown := Director.entry(run)
	check(not JSON.stringify(shown).contains("MODEL_OPENING_CLAIM") and raw.text == claim, "Model opening claim reached player-facing event")
	check(shown.choices[0].get("give", {}) == raw.choices[0].get("give", {}), "Opening guard changed promised economics")
	check(Director.choose(run, 0) == "" and not run.event_result.contains("MODEL_OPENING_CLAIM"), "Opening claim reached real choice result")
	run.pday = 3; run.t = 3060; Director.poll(run)
	check(not JSON.stringify(run.log).contains("MODEL_OPENING_CLAIM"), "Opening model claim reached delayed delivery")
	# The exception for real local awakenings must stay intact.
	Director.state(run).active = {"past_memory": true, "title": "真实本人觉醒", "text": "LOCAL_MEMORY", "choices": []}
	check(Director.entry(run).text == "LOCAL_MEMORY", "Opening guard suppressed an actual local awakening")

func test_budget(meta: Dictionary) -> void:
	var book := meta.duplicate(true)
	var run := genuine(book)
	var latest: Dictionary = book.past_lives.lives.back()
	latest.summary.opening = {"schema": 1, "choice": "cash_account", "applied": true, "effects": {"silver_cost": 1200, "hours": 1, "spent": {"rice": 1}, "gained": {"wood": 2}, "contacts": {"ning": {"trust": 1, "favors": 1}, "zhou": {"trust": -1, "favors": 0}, "traveler": {"trust": 2, "favors": 1}}, "first_warning": {"kind": "well_freeze", "actor": "zhou", "warning_day": 3}}, "history": []}
	for k in 8: latest.summary.opening.history.append({"day": 1, "action": "actual", "result": "𠮷".repeat(240)})
	latest.facts = []
	for k in 12: latest.facts.append({"actor": "ning", "fact_id": "dense%d" % k, "fact": "𠮷".repeat(160), "valence": 0, "day": 1})
	latest.summary.choices = []
	for k in 8: latest.summary.choices.append({"day": 1, "title": "题".repeat(40), "result": "𠮷".repeat(240)})
	latest.summary.npcs = Past.npc_snapshot(Npc.state(run))
	latest.summary.identity = {"schema": 1, "chosen": "scholar_collate", "completed_t": int(run.t), "learned": ["scribe_talisman"], "work": {}, "history": []}
	for section in ["identity", "mainline", "npcs"]:
		latest.summary[section].history = []
		for k in (12 if section != "mainline" else 16):
			var fact := {"day": k + 1, "t": k * 1440, "action": "actual", "result": "𠮷".repeat(240)}
			if section == "npcs": fact.actor = "ning"
			latest.summary[section].history.append(fact)
	var before := book.duplicate(true)
	var text := Archive.render(book)
	check(text.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "Opening archive exceeded 8000 UTF16 characters")
	check(book == before, "Markdown compaction modified raw structured archive")
	for heading in ["旧世交易结算", "旧世风声与危机结算", "旧世邻人自主行动", "旧世主线与结局", "旧世身份专属解法", "旧世可变开局"]: check(text.contains(heading), "Dense newest life lost a whole system: " + heading)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var path := ProjectSettings.globalize_path("res://Memory.md")
	var before := FileAccess.get_file_as_bytes(path).hex_encode() if FileAccess.file_exists(path) else ""
	var meta := test_sources()
	test_invalid_sources(meta)
	test_permanent_index(meta)
	test_snapshot_and_actual_file(meta)
	test_daily_legacy_and_archive_gate(meta)
	test_public_context_and_guard(meta)
	test_budget(meta)
	check((FileAccess.get_file_as_bytes(path).hex_encode() if FileAccess.file_exists(path) else "") == before, "Opening tests changed real player Memory.md")
	print("Opening memory/AI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
