extends Node
const State = preload("res://scripts/core/state.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
const Director = preload("res://scripts/core/director.gd")
const OpeningFixture = preload("res://tests/opening_memory.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day; run.t = (day - 1) * 1440 + minute

func sample(meta: Dictionary, day := 6) -> Dictionary:
	var run := State.new_run("scholar", meta, 907)
	Pre.start_disaster(run)
	at(run, day)
	return run

func seal(meta: Dictionary, actor: String, kind: String, status: String, id: String) -> Dictionary:
	var run := sample(meta)
	Past.record_cycle(run, actor, kind, status, id)
	run.phase = "dead"
	check(Past.archive(run, meta), "Could not seal a real structured receipt")
	return run

func test_sources() -> Dictionary:
	var meta := State.new_meta()
	var earlier := State.new_run("scholar", meta, 1)
	check(Past.cycle_inheritance(meta).is_empty(), "Empty history invented a case")
	seal(meta, "ning", "rescue", "helped", "medicine")
	seal(meta, "zhou", "promise", "pledged", "trade_6_credit")
	seal(meta, "traveler", "breach", "broken", "trade_overdue_6")
	var sources := Past.cycle_inheritance(meta)
	check(sources.size() == 3, "Three actual actors did not retain distinct causes")
	for source in sources:
		check(source.size() == 8 and source.source_id in meta.past_lives.sealed_ids, "Source lacks exact sealed provenance")
		check(not source.fact.contains("已经康复") or source.fact.contains("不证明"), "Actual aid invented a cure")
	var born := State.new_run("herbalist", meta, 2)
	check(born.cycle_inquiry.sources.size() == 2 and born.cycle_inquiry.sources[0].actor == "traveler" and born.cycle_inquiry.sources[1].actor == "zhou", "Birth did not pin the two newest unique actors")
	check(earlier.cycle_inquiry.sources.is_empty() and Past.public_memories(born).is_empty(), "Later history changed an old birth or awakened an NPC")
	var fixed: Array = born.cycle_inquiry.sources.duplicate(true)
	seal(meta, "ning", "promise", "kept", "cycle_promise_kept")
	check(born.cycle_inquiry.sources == fixed, "A live case learned a later sealed source")
	check(meta.past_lives.lives.back().facts[0].fact_id == "cycle_promise_kept", "Real current-life continuation cannot naturally awaken next life")
	return meta

func test_invalid(meta: Dictionary) -> void:
	for variant in ["unsealed", "future", "duplicate", "daily", "role", "status", "id", "time", "fraction", "prose", "trust"]:
		var bad := meta.duplicate(true)
		bad.past_lives.erase("cycle_legacy")
		match variant:
			"unsealed": bad.past_lives.sealed_ids = []
			"future": bad.past_lives.count = 0
			"duplicate": bad.past_lives.lives.append_array(bad.past_lives.lives.duplicate(true))
			_:
				for life in bad.past_lives.lives:
					match variant:
						"daily": life.summary.mode = "每日一局"
						"role": life.summary.role = "wizard"
						"prose", "trust":
							life.summary.cycle_receipts = []
							life.facts = [{"actor": "ning", "fact_id": "random", "fact": "你曾救活所有人并履行全部承诺。", "valence": 1, "day": 1}]
						_:
							for receipt in life.summary.get("cycle_receipts", []):
								match variant:
									"status": receipt.status = "cured"
									"id": receipt.fact_id = "AI_SAYS_SO"
									"time": receipt.t = -1
									"fraction": receipt.day = 1.5
		check(Past.cycle_inheritance(bad).is_empty(), "Invalid provenance invented a case: " + variant)
	for variant in ["unknown", "future", "self", "duplicate", "prose"]:
		var bad := meta.duplicate(true)
		match variant:
			"unknown": bad.past_lives.cycle_legacy[0].source_id = "unknown"
			"future": bad.past_lives.cycle_legacy[0].source_life = 100
			"self": bad.past_lives.cycle_legacy[0].source_id = bad.past_lives.cycle_legacy[1].source_id
			"duplicate": bad.past_lives.cycle_legacy.append(bad.past_lives.cycle_legacy[0].duplicate(true))
			"prose": bad.past_lives.cycle_legacy[0].fact = "赠送无限物资"
		check(Past.cycle_inheritance(bad) == Past.cycle_inheritance(meta), "Bad cache overrode verifiable detail: " + variant)

func test_legacy() -> void:
	var meta := State.new_meta()
	var run := sample(meta)
	Past.record(run, "ning", "medicine", "你曾把药交给阿宁。", 1)
	Past.record(run, "zhou", "trade_overdue_4", "你曾未能按期向木料场老周清偿米粮。", -1)
	var trade := Trade.state(run)
	trade.actors.zhou.breach_total = 1
	run.phase = "dead"
	check(Past.archive(run, meta), "Could not seal old exact medicine and final ledger")
	check(Past.cycle_inheritance(meta).size() == 2, "Conservative old sources did not migrate")
	for source in Past.cycle_inheritance(meta):
		if source.actor == "zhou": check(source.fact_id == "trade_overdue_4" and source.day == 6, "Structured breach ignored a precise matching old NPC fragment")
	var old := meta.duplicate(true)
	old.past_lives.erase("cycle_legacy")
	old.past_lives.lives[0].facts[0].fact = "你救活了阿宁父亲。"
	check(Past.cycle_inheritance(old).size() == 1, "Free old prose invented a medicine rescue")
	var fixed := State.new_run("scholar", meta, 99)
	for k in 9:
		var next := sample(meta)
		next.flags.daily = "fixed"
		Past.record_cycle(next, "ning", "rescue", "helped", "medicine")
		next.phase = "dead"
		check(Past.archive(next, meta), "Daily archive failed")
	check(Past.cycle_inheritance(meta).size() == 2 and meta.past_lives.lives.size() == 8, "Trimming eight detailed lives erased permanent causes or daily supplied a new one")
	check(fixed.cycle_inquiry.sources.size() == 2, "Existing birth changed when detailed source was trimmed")
	var repeated := sample(State.new_meta())
	Past.record_cycle(repeated, "ning", "rescue", "helped", "medicine")
	for k in 20: Past.record_cycle(repeated, "zhou", "promise", "pledged", "trade_6_credit")
	check(repeated.past_lives.cycle_receipts.size() == 2 and repeated.past_lives.cycle_receipts[0].actor == "ning", "Repeated same-actor choices erased another person's actual aid")

func complete(run: Dictionary, id: String, action: String) -> void:
	check(Cycle.act(run, id, action, str(Cycle.view(run).token)) == "", "Could not begin actual investigation " + action)
	var busy: Dictionary = run.busy.duplicate(true)
	run.t = int(busy.end); run.busy = {}
	check(Cycle.complete(run, busy.data) != "", "Could not finish actual investigation " + action)

func test_file(meta: Dictionary) -> Dictionary:
	var run := sample(meta, 3)
	for item in ["rice", "wood", "water", "mugwort", "firewood"]: run.home[item] = 20
	check(Cycle.poll(run) != "", "Natural local old dream did not publish")
	var c: Dictionary = Cycle.state(run).cases[0]
	var contexts := [Director.snapshot(run)]
	check(Past.public_memories(run).is_empty(), "Player dream became NPC knowledge")
	complete(run, c.id, "inquire")
	contexts.append(Director.snapshot(run))
	complete(run, c.id, "verify")
	contexts.append(Director.snapshot(run))
	var route: String = {"promise": "renew", "breach": "pay_repair", "rescue": "help_again"}[c.kind]
	check(Cycle.act(run, c.id, route, str(Cycle.view(run).token)) == "", "Could not start new local continuation")
	contexts.append(Director.snapshot(run))
	var safe := Past.cycle_snapshot(run.cycle_inquiry)
	check(not safe.is_empty() and not safe.work.is_empty() and safe.published[0].stage == "working", "Unfinished current work disappeared from archive")
	var raw := JSON.stringify(safe)
	for hidden in ["private_condition", "source_id", "paid", "sources", "source\""]:
		check(not raw.contains('"' + hidden), "Private case data leaked into writer archive: " + hidden)
	var finished := run.duplicate(true)
	var busy: Dictionary = finished.busy.duplicate(true)
	finished.t = int(busy.end); finished.busy = {}
	check(Cycle.complete(finished, busy.data) != "", "Actual selected route did not complete")
	contexts.append(Director.snapshot(finished))
	check(finished.past_lives.cycle_receipts.size() == 1 and finished.past_lives.trace.back().fact_id == "cycle_promise_kept", "Actual finished continuation did not become one truthful next-life cause")
	finished.t = int(Cycle.state(finished).cases[0].delivery.due_t); finished.pday = int(finished.t) / 1440 + 1
	check(Cycle.poll(finished) != "", "Fixed current-life delivery did not execute")
	contexts.append(Director.snapshot(finished))
	for mode in ["decline", "expired"]:
		var alternative := sample(meta, 3)
		Cycle.poll(alternative)
		var first: Dictionary = Cycle.state(alternative).cases[0]
		if mode == "decline": check(Cycle.act(alternative, first.id, "decline", str(Cycle.view(alternative).token)) == "", "Decline before proof failed")
		else:
			alternative.t = int(first.deadline_t); alternative.pday = int(alternative.t) / 1440 + 1
			Cycle.poll(alternative)
		check(not Past.cycle_snapshot(alternative.cycle_inquiry).is_empty(), "Actual unverified closed case was omitted: " + mode)
		check(not alternative.past_lives.has("cycle_receipts"), "Private dream alone was archived as a new broken promise")
		contexts.append(Director.snapshot(alternative))
	var book := meta.duplicate(true)
	run.phase = "dead"
	check(Past.archive(run, book), "Could not seal unfinished current case")
	var file := "user://cycle-memory-%d.md" % OS.get_process_id()
	check(Archive.sync(book, file) == OK, "Could not write actual temporary Memory.md")
	var actual := Archive.read_context(file)
	for phrase in ["旧世轮回调查", "尚未完工", "不等于NPC觉醒", "未完成", "不代表已生效"]: check(str(actual.get("markdown", "")).contains(phrase), "Memory omitted actual uncertainty: " + phrase)
	check(not actual.markdown.contains("private_condition") and not actual.markdown.contains(c.source.source_id), "File disclosed private case source")
	check(actual.sha256 == actual.markdown.sha256_text(), "Read-back Memory hash is not actual file body")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK, "Could not remove isolated Memory fixture")
	var output := FileAccess.open(OS.get_environment("TEMP").path_join("ledger-cycle-public-fixtures.json"), FileAccess.WRITE)
	check(output != null, "Could not export actual Godot public case snapshots")
	if output != null: output.store_string(JSON.stringify(contexts)); output.close()
	return safe

func test_budget(cycle: Dictionary) -> void:
	var fixture := OpeningFixture.new()
	var meta := State.new_meta()
	fixture.genuine(meta)
	var latest: Dictionary = meta.past_lives.lives.back()
	var run := sample(meta)
	latest.summary.npcs = Past.npc_snapshot(preload("res://scripts/core/npc_autonomy.gd").state(run))
	latest.summary.identity = {"schema": 1, "chosen": "scholar_collate", "completed_t": int(run.t), "learned": ["scribe_talisman"], "work": {}, "history": []}
	latest.summary.opening = {"schema": 1, "choice": "plain", "applied": true, "effects": {"silver_cost": 0, "hours": 0, "spent": {}, "gained": {}, "contacts": {}, "first_warning": {}}, "history": []}
	latest.summary.cycle_inquiry = cycle.duplicate(true)
	var other: Dictionary = latest.summary.cycle_inquiry.published[0].duplicate(true)
	other.id += "-second"; other.actor = "zhou"
	latest.summary.cycle_inquiry.published.append(other)
	latest.summary.cycle_inquiry.history = []
	for k in 12: latest.summary.cycle_inquiry.history.append({"day": 3, "actor": "ning", "case_id": "dense", "action": "actual", "result": "𠮷".repeat(240)})
	latest.facts = []
	for k in 12: latest.facts.append({"actor": "ning", "fact_id": "dense%d" % k, "fact": "𠮷".repeat(160), "valence": 0, "day": 1})
	latest.summary.choices = []
	for k in 8: latest.summary.choices.append({"day": 1, "title": "题".repeat(40), "result": "𠮷".repeat(240)})
	latest.summary.trade.debt = {"id": "dense-debt", "actor": "zhou", "req": {"rice": 8, "water": 8, "mugwort": 8}, "give": {"wood": 8, "nails": 8, "firewood": 8}, "due_day": 6, "due_t": 7920, "overdue": false}
	latest.summary.trade.aid = []
	for actor in Past.ACTORS: latest.summary.trade.aid.append({"id": "dense-" + actor, "actor": actor, "req": {"rice": 8, "water": 8, "mugwort": 8}, "give": {"wood": 8, "nails": 8, "firewood": 8}, "due_day": 7, "due_t": 8760})
	while latest.summary.crisis.completed.size() < 6:
		var event: Dictionary = latest.summary.crisis.completed[0].duplicate(true)
		event.id = "dense-%d" % latest.summary.crisis.completed.size()
		latest.summary.crisis.completed.append(event)
	latest.summary.crisis.history = []
	for k in 12: latest.summary.crisis.history.append({"day": 1, "kind": "well_freeze", "actor": "ning", "action": "actual", "result": "𠮷".repeat(160)})
	for section in ["identity", "mainline", "npcs"]:
		latest.summary[section].history = []
		for k in (16 if section == "mainline" else 12):
			var fact := {"day": k + 1, "t": k * 1440, "action": "actual", "result": "𠮷".repeat(240)}
			if section == "npcs": fact.actor = "ning"
			latest.summary[section].history.append(fact)
	var before := meta.duplicate(true)
	var text := Archive.render(meta)
	check(text.to_utf16_buffer().size() <= 16000, "Newest seven systems exceed 8000 UTF16")
	check(meta == before, "Markdown budget mutated structured truth")
	for heading in ["旧世交易结算", "旧世风声与危机结算", "旧世邻人自主行动", "旧世主线与结局", "旧世身份专属解法", "旧世可变开局", "旧世轮回调查"]: check(text.contains(heading), "Newest dense life lost system " + heading)
	fixture.free()

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var path := ProjectSettings.globalize_path("res://Memory.md")
	var before := FileAccess.get_file_as_bytes(path).hex_encode() if FileAccess.file_exists(path) else ""
	var meta := test_sources()
	if not failures: test_invalid(meta)
	if not failures: test_legacy()
	var cycle := {}
	if not failures: cycle = test_file(meta)
	if not failures: test_budget(cycle)
	check((FileAccess.get_file_as_bytes(path).hex_encode() if FileAccess.file_exists(path) else "") == before, "Cycle tests touched the real player Memory.md")
	print("Cycle memory/AI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
