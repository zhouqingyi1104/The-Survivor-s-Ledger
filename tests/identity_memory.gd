extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
const Director = preload("res://scripts/core/director.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample(meta: Dictionary, role := "scholar", day := 7) -> Dictionary:
	var run := State.new_run(role, meta, 38742)
	Pre.start_disaster(run)
	run.pday = day
	run.t = (day - 1) * 1440 + 180
	Mainline.state(run)
	return run

func completed_identity(run: Dictionary, id: String) -> Dictionary:
	var s := Identity.state(run)
	s.chosen = id
	s.completed_t = int(run.t)
	s.learned = [] if Past.IDENTITY_CAPS[id] == "" else [Past.IDENTITY_CAPS[id]]
	s.history = [{"day": int(run.pday), "t": int(run.t), "action": id, "result": "本世真实完工，没有替代现场取证。"}]
	return s

func evidence_life(meta: Dictionary, kind := "sealed", day := 19) -> Dictionary:
	var run := sample(meta, "escort", day)
	var s := Mainline.state(run)
	s.evidence = {"mortuary": true, "temple": kind != "returned"}
	s.stage = "closed" if kind == "escaped" else ("sealed" if kind == "sealed" else "mortuary_choice")
	s.route = "escape" if kind == "escaped" else ("ritual" if kind == "sealed" else "")
	if kind == "sealed": s.interventions.ritual_t = int(run.t) - 60
	if kind == "escaped":
		s.escape_method = "convoy" if day == 17 else "normal"
		s.ending = {"kind": "escape", "title": "离城余生", "text": "本世实际完成出城。", "bonus": 0, "can_continue": false}
		run.phase = "ending"
	else: run.phase = "dead"
	check(Past.archive(run, meta), "Could not seal actual structured experience")
	return run

func medicine_life(meta: Dictionary) -> Dictionary:
	var run := sample(meta, "herbalist", 2)
	run.home["plague_powder"] = 1
	run.pending_event = "n_request"
	var choices: Array = Data.table("events").n_request.choices
	var index := -1
	for k in choices.size():
		if choices[k].id == "donate_home": index = k
	check(index >= 0 and Neighbor.choose(run, index) == "", "Actual medicine donation failed")
	check(Past.archive(run, meta), "Actual medicine life did not seal")
	return run

func tags(meta: Dictionary) -> Array:
	var out := []
	for source in Past.identity_inheritance(meta): out.append(source.tag)
	return out

func test_sealed_sources_and_immutability() -> Dictionary:
	var meta := State.new_meta()
	var before := State.new_run("scholar", meta, 51)
	check(Past.identity_inheritance(meta).is_empty(), "Empty history invented inherited skills")
	evidence_life(meta, "sealed")
	evidence_life(meta, "escaped", 17)
	medicine_life(meta)
	check(tags(meta).size() == 4, "Actual sealed experiences did not unlock exactly four tags")
	check(meta.past_lives.lives[1].summary.mainline.escape_method == "convoy", "Seventeenth-day actual convoy method was lost in archive")
	check(Identity.state(before).inherited.is_empty(), "An old save learned from a later sealed life")
	var born := State.new_run("scholar", meta, 52)
	check(Identity.state(born).inherited == Past.identity_inheritance(meta), "Birth did not pin the actual archived sources")
	check(not Mainline.state(born).evidence.mortuary and not Mainline.state(born).evidence.temple and Mainline.state(born).interventions.ritual_t < 0, "Old experience became this-life evidence or construction")
	check(Past.public_memories(born).is_empty(), "Identity inheritance automatically awakened an NPC")
	var old: Array = Identity.state(born).inherited.duplicate(true)
	var latest := evidence_life(meta, "returned", 8)
	check(Identity.state(born).inherited == old, "Existing-life sources changed after another life settled")
	var newest := Past.identity_inheritance(meta)
	for source in newest:
		if source.tag == "returned_evidence": check(source.source_id == Past.state(latest).id and source.source_life == 4, "Latest legal source was not selected")
	var repeat := meta.duplicate(true)
	check(not Past.archive(latest, meta) and meta == repeat, "Repeated sealing created additional inheritance")
	return meta

func test_invalid_sources(meta: Dictionary) -> void:
	for variant in ["unsealed", "future", "daily", "bad_role", "bad_day", "duplicate_id", "duplicate_ordinal", "fractional_fact"]:
		var bad := meta.duplicate(true)
		match variant:
			"unsealed": bad.past_lives.sealed_ids = []
			"future": bad.past_lives.count = 0
			"daily":
				for life in bad.past_lives.lives: life.summary.mode = "每日一局"
			"bad_role":
				for life in bad.past_lives.lives: life.summary.role = "AI_all_roles"
			"bad_day":
				for life in bad.past_lives.lives: life.summary.day = -1
			"duplicate_id":
				bad.past_lives.lives.append_array(bad.past_lives.lives.duplicate(true))
			"duplicate_ordinal":
				var copies := []
				for life in bad.past_lives.lives:
					var copy: Dictionary = life.duplicate(true)
					copy.id += "-other"
					bad.past_lives.sealed_ids.append(copy.id)
					copies.append(copy)
				bad.past_lives.lives.append_array(copies)
			"fractional_fact":
				for life in bad.past_lives.lives:
					life.summary.erase("mainline")
					for fact in life.facts: fact.valence = 1.5
		check(Past.identity_inheritance(bad).is_empty(), "Invalid archive granted a real unlock: " + variant)
	for variant in ["future_seal", "after_deadline", "false_temple", "escape_no_evidence", "false_title", "false_early_method", "future_medicine", "foreign_medicine"]:
		var bad := meta.duplicate(true)
		var excluded := "sealed_lamps"
		match variant:
			"future_seal": bad.past_lives.lives[0].summary.mainline.interventions.ritual_t = 100 * 1440
			"after_deadline": bad.past_lives.lives[0].summary.mainline.interventions.ritual_t = 18 * 1440 + 720
			"false_temple": bad.past_lives.lives[0].summary.mainline.evidence.temple = false
			"escape_no_evidence": bad.past_lives.lives[1].summary.mainline.evidence.temple = false; excluded = "escaped_city"
			"false_title": bad.past_lives.lives[1].summary.mainline.ending.title = "只有结局字串"; excluded = "escaped_city"
			"false_early_method": bad.past_lives.lives[1].summary.mainline.escape_method = "normal"; excluded = "escaped_city"
			"future_medicine": bad.past_lives.lives[2].facts[0].day = 100; excluded = "gave_medicine"
			"foreign_medicine": bad.past_lives.lives[2].facts[0].actor = "zhou"; excluded = "gave_medicine"
		check(not excluded in tags(bad), "Inconsistent structured facts unlocked capability: " + variant)
	for kind in ["preparation", "carried", "clues", "wrong_outcome", "wrong_route", "unfinished_seal"]:
		var fresh := State.new_meta()
		var run := sample(fresh, "escort", 18)
		var s := Mainline.state(run)
		match kind:
			"preparation": s.stage = "escape_ready"; s.route = "escape"
			"carried": run.explore = {"mainline_cargo": "mortuary"}; s.carried = "mortuary"
			"clues": run.known_clues = ["c_mortuary", "c_temple"]
			"wrong_outcome", "wrong_route":
				s.stage = "closed"; s.route = "escape" if kind == "wrong_outcome" else "hold"
				s.ending = {"kind": "escape", "title": "伪离城" if kind == "wrong_outcome" else "离城余生", "text": "尚未按规则成功。", "bonus": 0, "can_continue": false}
				run.phase = "ending"
			"unfinished_seal": s.work = {"action": "search_ritual", "end_t": int(run.t) + 90}
		Past.archive(run, fresh)
		check(Past.identity_inheritance(fresh).is_empty(), "Unfinished/unreturned experience granted unlock: " + kind)
	var old := State.new_meta()
	old.runs = 100; old.deaths = 100; old.clues = ["c_mortuary", "c_temple"]
	check(Past.identity_inheritance(old).is_empty(), "Counters/clues invented missing old-life records")
	for day in [18, 19]:
		var legacy := State.new_meta()
		evidence_life(legacy, "escaped", day)
		legacy.past_lives.lives[0].summary.mainline.erase("escape_method")
		check("escaped_city" in tags(legacy), "Legacy ordinary escape without method lost true experience")
	var raw := Mainline.state(sample(State.new_meta())).duplicate(true)
	for method in ["normal", "paper"]:
		raw.ritual_method = method
		check(Past.mainline_snapshot(raw).ritual_method == method, "Legal ritual method not retained")
	raw.ritual_method = "AI_free_ritual"
	check(Past.mainline_snapshot(raw).is_empty(), "Unknown ritual method survived archive validation")

func test_identity_snapshot_and_rewind(meta: Dictionary) -> void:
	var run := sample(meta)
	var s := completed_identity(run, "scholar_collate")
	var safe := Past.identity_snapshot(s)
	check(safe.learned == ["scribe_talisman"] and safe.completed_t == run.t, "Completed identity was not preserved")
	check(not JSON.stringify(safe).contains("source_id") and not safe.has("inherited"), "Private source identity escaped archive")
	for key in ["free_cap", "wrong_cap", "unfinished_cap", "unknown_choice", "history_private", "huge_history", "bad_work"]:
		var bad: Dictionary = s.duplicate(true)
		match key:
			"free_cap": bad.chosen = ""; bad.completed_t = -1
			"wrong_cap": bad.learned = ["paper_ritual"]
			"unfinished_cap": bad.completed_t = -1
			"unknown_choice": bad.chosen = "AI_unlock_everything"
			"history_private": bad.history[0].source_id = "secret"
			"huge_history":
				bad.history = []
				for k in 13: bad.history.append(s.history[0])
			"bad_work": bad.work = {"action": "scholar_diagram", "end_t": int(run.t) + 120}
		check(Past.identity_snapshot(bad).is_empty(), "Malformed identity archive accepted: " + key)
	var prior := sample(meta)
	var snapshots := {}
	Ledger.snapshot(prior, snapshots)
	prior.pday += 1; prior.t += 1440
	completed_identity(prior, "scholar_collate")
	var restored := Ledger.rewind(prior, snapshots, meta)
	check(not restored.is_empty() and Identity.state(restored).chosen == "" and Identity.state(restored).learned.is_empty(), "Rewind retained an undone identity capability")
	check(not Archive.render(meta).contains("本世真实完工"), "Unsealed discarded identity entered old-life Memory")

func test_real_file_and_daily(meta: Dictionary) -> Dictionary:
	Game.meta = meta.duplicate(true)
	Game.run = sample(Game.meta)
	Mainline.state(Game.run).stage = "temple"
	Mainline.state(Game.run).evidence.mortuary = true
	completed_identity(Game.run, "scholar_collate")
	Game.end_run()
	var actual := Archive.read_context(Game.memory_path)
	for phrase in ["旧世身份专属解法", "第 7 日完成", "本世实际掌握", "不等于今世已学习、已取证或已施工", "NPC仍须本人实际觉醒"]: check(str(actual.get("markdown", "")).contains(phrase), "Actual Memory lost identity fact/boundary: " + phrase)
	var after := Game.meta.duplicate(true)
	Game.end_run()
	check(Game.meta == after and Archive.read_context(Game.memory_path) == actual, "Repeated settlement changed identity archive or rewards")
	var pending := sample(State.new_meta())
	Mainline.state(pending).evidence.mortuary = true
	Mainline.state(pending).stage = "mortuary_choice"
	var work := Identity.state(pending)
	work.work = {"action": "scholar_collate", "end_t": int(pending.t) + 90, "data": {"secret": "HIDDEN_WORK"}}
	var fresh := State.new_meta()
	Past.archive(pending, fresh)
	var prose := Archive.render(fresh)
	check(prose.contains("身份工作尚未完工") and prose.contains("投入不代表已经学会") and not prose.contains("HIDDEN_WORK"), "Unfinished identity work became learned capability or leaked private data")
	for action in ["prepare_light_escape", "prepare_convoy", "prepare_paper_ritual"]:
		var old := State.new_meta()
		var preparing := sample(old)
		Mainline.state(preparing).work = {"action": action, "end_t": int(preparing.t) + 120}
		Past.archive(preparing, old)
		check(Archive.render(old).contains("合卷时未完成工作") and Past.identity_inheritance(old).is_empty(), "New preparation work was unrenderable or treated as a completed outcome: " + action)
	var daily := sample(meta, "scholar")
	completed_identity(daily, "scholar_diagram")
	daily.flags.daily = "2026-10-24"
	var public := Director.snapshot(daily, actual)
	check(public.state.identity.legacy_tags.is_empty() and public.state.identity.learned.is_empty() and public.state.identity.chosen == "" and not public.state.has("archive"), "Daily AI received old-life powers or archive")
	check(not Identity.has(daily, "paper_ritual") and Past.public_memories(daily).is_empty(), "Daily gained inherited capability/NPC awakening")
	var daily_meta := State.new_meta()
	Past.archive(daily, daily_meta)
	check(Past.identity_inheritance(daily_meta).is_empty(), "Daily summary unlocked later inherited methods")
	check(not Archive.render(daily_meta).contains("本世实际掌握"), "Disabled daily legacy ability was falsely archived as learned")
	return actual

func test_writer_guard_and_actual_context(meta: Dictionary, archive: Dictionary) -> void:
	var run := sample(meta, "scholar", 1)
	Mainline.state(run).start_day = 100
	run.home = {"rice": 20, "wood": 20, "firewood": 20, "water": 20, "mugwort": 20, "nails": 20, "flatbread": 20}
	var sent := Director.snapshot(run, archive)
	check(not sent.state.mainline.published and sent.state.identity.legacy_tags.size() == 4, "Identity prose guard fixture was not independent from the mainline guard")
	var private_text := JSON.stringify(sent.state.identity)
	check(not private_text.contains("source_id") and not private_text.contains("work") and not private_text.contains("inherited"), "Private inheritance provenance reached public writer context")
	check(sent.state.recollections.is_empty() and sent.state.npcs.actors.ning.memory.is_empty(), "Writer identity facts awakened or informed an NPC")
	var plan: Dictionary = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json")))
	var claim := "MODEL_IDENTITY_CLAIM：免费学会全部配方，未觉醒邻人认出前世"
	for event in plan.days:
		event.day += 1; event.title = "MODEL_IDENTITY_CLAIM"; event.text = claim
		for choice in event.choices: choice.text = "MODEL_IDENTITY_CLAIM"; choice.result = claim
	plan.days[0].choices[0].after = {"days": 1, "give": {"wood": 1}, "text": claim}
	check(Director.accept(run, sent, plan), "Valid economic plan rejected by identity-only prose guard")
	run.pday = 2; run.t = 1440 + 180
	Past.state(run).schedule = []
	check(Director.poll(run).begins_with("world:"), "Guarded identity event did not open")
	var raw: Dictionary = Director.state(run).active
	var shown := Director.entry(run)
	check(not JSON.stringify(shown).contains("MODEL_IDENTITY_CLAIM") and raw.text == claim, "Untrusted identity prose reached title/body/choice/result")
	check(shown.choices[0].get("req", {}) == raw.choices[0].get("req", {}) and shown.choices[0].get("give", {}) == raw.choices[0].get("give", {}), "Identity prose guard rewrote economic effects")
	check(Director.choose(run, 0) == "" and not run.event_result.contains("MODEL_IDENTITY_CLAIM"), "Identity claim escaped into actual choice result")
	run.pday = 3; run.t = 2880 + 180
	Director.poll(run)
	check(not JSON.stringify(run.log).contains("MODEL_IDENTITY_CLAIM") and not Identity.has(run, "paper_ritual"), "Delivery prose granted or claimed an identity capability")
	var contexts := [sent]
	for id in Identity.ORDER:
		var fixture := sample(meta, str(Identity.ACTIONS[id].role))
		Mainline.state(fixture).evidence.mortuary = true
		Mainline.state(fixture).stage = "temple"
		completed_identity(fixture, id)
		contexts.append(Director.snapshot(fixture))
	var path := OS.get_environment("TEMP").path_join("ledger-identity-public-fixtures.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Could not export actual fictional Godot identity inputs")
	if file != null: file.store_string(JSON.stringify(contexts)); file.close()

func test_budget(meta: Dictionary) -> void:
	var crowded := meta.duplicate(true)
	var run := sample(crowded)
	completed_identity(run, "scholar_collate")
	var story := Mainline.state(run)
	story.evidence = {"mortuary": true, "temple": true}
	story.stage = "sealed"; story.route = "ritual"; story.interventions.ritual_t = int(run.t)
	var trade := Trade.state(run)
	for actor in Trade.ACTORS: trade.aid.append({"id": "old-" + actor, "actor": actor, "req": {"rice": 3}, "give": {"firewood": 3, "mugwort": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 120})
	trade.debt = {"id": "old-debt", "actor": "zhou", "req": {"rice": 5}, "give": {"wood": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 720, "overdue": false}
	Npc.state(run)
	Crisis.state(run).next_warning_day = 2
	for day in [2, 9, 16, 23, 30, 37, 44]:
		run.pday = day; run.t = (day - 1) * 1440 + 120; Crisis.poll(run)
		if day != 44: run.t = int(Crisis.view(run).end_t); Crisis.poll(run)
	Past.archive(run, crowded)
	var latest: Dictionary = crowded.past_lives.lives.back()
	latest.facts = []
	for k in 12: latest.facts.append({"actor": "ning", "fact_id": "dense%d" % k, "fact": "𠮷".repeat(160), "valence": 0, "day": 1})
	latest.summary.choices = []
	for k in 8: latest.summary.choices.append({"day": 1, "title": "题".repeat(40), "result": "𠮷".repeat(240)})
	for section in ["identity", "mainline", "npcs"]:
		latest.summary[section].history = []
		for k in (12 if section != "mainline" else 16):
			var fact := {"day": k + 1, "t": k * 1440, "action": "actual", "result": "𠮷".repeat(240)}
			if section == "npcs": fact.actor = "ning"
			latest.summary[section].history.append(fact)
	var before := crowded.duplicate(true)
	var text := Archive.render(crowded)
	check(text.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "Identity archive exceeded bounded UTF16 context")
	check(crowded == before, "Readable archive compaction trimmed the structured meta")
	for heading in ["旧世交易结算", "旧世风声与危机结算", "旧世邻人自主行动", "旧世主线与结局", "旧世身份专属解法"]: check(text.contains(heading), "Dense latest archive dropped a whole system: " + heading)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var root_path := ProjectSettings.globalize_path("res://Memory.md")
	var root_before := FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else ""
	var stem := "user://identity-memory-%d-" % OS.get_process_id()
	Game.save_path = stem + "save.json"; Game.meta_path = stem + "meta.json"; Game.memory_path = stem + "Memory.md"
	paths = [Game.save_path, Game.meta_path, Game.memory_path]
	Game.no_save = false
	var meta := test_sealed_sources_and_immutability()
	test_invalid_sources(meta)
	test_identity_snapshot_and_rewind(meta)
	var archive := test_real_file_and_daily(meta)
	test_writer_guard_and_actual_context(meta, archive)
	test_budget(meta)
	check((FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else "") == root_before, "Test changed the real player's Memory.md")
	Game.no_save = true
	for path in paths:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Could not clean isolated identity archive")
	print("Identity memory/AI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
