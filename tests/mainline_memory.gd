extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Core = preload("res://scripts/core/mainline.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
const Director = preload("res://scripts/core/director.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0
var scratch: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample(meta: Dictionary) -> Dictionary:
	var run := State.new_run("escort", meta, 144065)
	Pre.start_disaster(run)
	Core.state(run)
	Trade.state(run)
	Npcs.state(run)
	Crisis.state(run).next_warning_day = 100
	return run

func ended(meta: Dictionary, kind: String) -> Dictionary:
	var run := sample(meta)
	run.phase = "ending"
	run.pday = 18 if kind == "escape" else 20
	run.t = 17 * 1440 + 300 if kind == "escape" else 20 * 1440
	var s := Core.state(run)
	s.stage = "closed"
	s.route = kind
	s.evidence = {"mortuary": kind != "hold", "temple": kind != "hold"}
	s.interventions = {"disrupt_t": 10 * 1440 if kind == "ritual" else -1, "ritual_t": 18 * 1440 if kind == "ritual" else -1}
	s.ending = {"kind": kind, "title": {"hold": "坚守余生", "escape": "离城余生", "ritual": "七灯俱熄"}[kind], "text": "本世实际结案。", "bonus": 0 if kind == "escape" else 10, "can_continue": kind == "hold"}
	s.history = [{"day": int(run.pday), "t": int(run.t), "action": "finish_" + kind, "result": "本世实际完成" + kind}]
	return run

func test_three_endings_and_settlement() -> void:
	for kind in ["hold", "escape", "ritual"]:
		var meta := State.new_meta()
		var run := ended(meta, kind)
		State.tally(run).goals = ["survive"]
		var expected := 0 if kind == "escape" else 10
		check(Ledger.ending_bonus(run) == expected, "Wrong actual ending bonus: " + kind)
		var preview := Ledger.daoxin_gain(run, Ledger.ending_bonus(run))
		check(Ledger.goal_results(run)[0].met == (kind != "escape"), "Early escape claimed twentieth-night challenge: " + kind)
		check(Ledger.daoxin_gain(run, 999).total == preview.total, "Caller-injected ending bonus exceeded real entitlement: " + kind)
		var stale := run.duplicate(true)
		var paid := Ledger.end_run(run, meta)
		check(paid.total == preview.total and paid.settled, "Actual settlement differs from preview: " + kind)
		var before := meta.duplicate(true)
		check(Ledger.end_run(run, meta).total == 0 and Ledger.end_run(stale, meta).total == 0 and meta == before, "Same life rewarded again through repeat/old save: " + kind)
		var summary: Dictionary = Past.book(meta).lives.back().summary
		check(summary.outcome == Core.ending(run).title and summary.mainline.ending.kind == kind, "Archive mislabeled a real ending as generic victory: " + kind)
		check(Past.mainline_snapshot(summary.mainline) == summary.mainline, "Archived story no longer satisfies public bounded schema")
	var legacy := sample(State.new_meta())
	legacy.erase("mainline")
	legacy.phase = "ending"
	legacy.pday = 20
	legacy.t = 20 * 1440
	check(Ledger.ending_bonus(legacy) == 10 and Core.ending(legacy).kind == "hold", "Legacy ending lost ordinary hold victory")
	check(Ledger.end_run({}, State.new_meta()).total == 0, "Empty callback generated a new reward")

func test_game_continue_callbacks_and_manual_close() -> void:
	for kind in ["escape", "ritual"]:
		Game.meta = State.new_meta()
		Game.run = ended(Game.meta, kind)
		Game.snapshots = {}
		var before := Game.run.duplicate(true)
		Game.keep_living(str(Past.state(Game.run).id))
		check(Game.run == before and not Game.run.endless, "Disallowed ending continued or advanced time: " + kind)
	Game.meta = State.new_meta()
	Game.run = ended(Game.meta, "hold")
	Game.snapshots = {}
	var day: int = Game.run.pday
	var identity: String = Past.state(Game.run).id
	Game.keep_living(identity)
	check(Game.run.phase == "post" and Game.run.endless and int(Game.run.pday) == day + 1 and Core.state(Game.run).stage == "endless", "Hold ending did not enter actual endless day")
	var after := Game.run.duplicate(true)
	Game.keep_living(identity)
	check(Game.run == after, "Repeated continue skipped another day")
	Game.close_book(identity)
	check(Game.run.is_empty(), "Normal manual close from active endless game was blocked")
	var count: int = Game.meta.runs
	Game.close_book(identity)
	check(Game.meta.runs == count, "Empty double-close repeated settlement")
	Game.run = sample(Game.meta)
	Game.snapshots = {}
	var old_id: String = Past.state(Game.run).id
	Game.restart_from_cover(old_id)
	var new_id: String = Past.state(Game.run).id
	var runs: int = Game.meta.runs
	check(new_id != old_id and Game.run.phase == "pre", "Manual restart from a live game was blocked")
	Game.restart_from_cover(old_id)
	Game.close_book(old_id)
	check(Past.state(Game.run).id == new_id and Game.meta.runs == runs, "Old UI callback closed or restarted a new life")

func test_actual_file_and_hidden_boundaries() -> Dictionary:
	# A new isolated book must not overwrite the higher-count archive created by
	# the earlier callback test; production intentionally preserves such files.
	Game.memory_path = "user://mainline-memory-%d-second-Memory.md" % OS.get_process_id()
	scratch.append(Game.memory_path)
	Game.meta = State.new_meta()
	Game.run = ended(Game.meta, "escape")
	var story := Core.state(Game.run)
	story["private"] = "PRIVATE_STORY"
	story.work = {"id": "old-work", "action": "prepare_ritual", "start_t": 200, "end_t": 320, "data": {"secret": "PRIVATE_WORK"}}
	Past.state(Game.run).inherited = [{"fact": "PRIVATE_UNAWAKENED"}]
	Crisis.state(Game.run).pending = {"kind": "well_freeze", "actor": "ning", "warning_day": 100, "real": false}
	var public := Past.mainline_snapshot(story)
	check(not public.is_empty() and not JSON.stringify(public).contains("PRIVATE"), "Private working data escaped story archive")
	check(public.work == {"action": "prepare_ritual", "end_t": 320}, "Unfinished construction was falsely stored as completed intervention")
	Game.end_run()
	check(FileAccess.file_exists(Game.memory_path), "Actual Game settlement did not write isolated Memory.md")
	var context := Archive.read_context(Game.memory_path)
	var text: String = context.get("markdown", "")
	for phrase in ["旧世主线与结局", "离城余生", "青云观已取回", "合卷时未完成工作", "不能记作已经生效", "旧残卷、旧路线与旧施工不等于新世已完成"]:
		check(text.contains(phrase), "Written archive lost actual story distinction: " + phrase)
	check(not text.contains("PRIVATE"), "Actual Memory leaked hidden state")
	var before := Game.meta.duplicate(true)
	Game.end_run()
	check(Game.meta == before and Archive.read_context(Game.memory_path).markdown == text, "Repeat Game settlement changed rewards/actual Memory")
	var next := State.new_run("escort", Game.meta, 9291)
	var next_state := Core.state(next)
	check(not next_state.evidence.mortuary and not next_state.evidence.temple and next_state.interventions.ritual_t < 0 and next_state.route == "", "New life inherited completed old investigation or construction")
	check(Past.public_memories(next).is_empty(), "Mainline archive automatically awakened NPCs")
	check(Director.snapshot(next, context).state.archive == context, "AI did not read actual saved story Markdown")
	return Game.meta.duplicate(true)

func test_daily_legacy_and_invalid(meta: Dictionary) -> void:
	var legacy := meta.duplicate(true)
	legacy.past_lives.lives[0].summary.erase("mainline")
	check(not Archive.render(legacy).contains("旧世主线与结局"), "Old meta invented new story history")
	for kind in ["stage", "evidence", "intervention", "ending", "work", "history"]:
		var bad: Dictionary = meta.past_lives.lives[0].summary.mainline.duplicate(true)
		match kind:
			"stage": bad.stage = "AI_complete"
			"evidence": bad.evidence.temple = "yes"
			"intervention": bad.interventions.ritual_t = -2
			"ending": bad.ending.bonus = 10
			"work": bad.work.action = "reveal_all"
			"history": bad.history[0].result = "果".repeat(241)
		check(Past.mainline_snapshot(bad).is_empty(), "Invalid story archive accepted: " + kind)
	var daily_meta := State.new_meta()
	var daily := ended(daily_meta, "hold")
	daily.flags.daily = "2026-10-24"
	Ledger.end_run(daily, daily_meta)
	var life: Dictionary = Past.book(daily_meta).lives.back()
	check(life.facts.is_empty() and life.summary.mainline.ending.kind == "hold", "Daily recap lost story or created inherited actor facts")
	check(not Director.snapshot(State.new_run("escort", daily_meta, 101)).state.mainline.evidence.mortuary, "Daily archived evidence became next-life proof")

func test_all_system_budget(meta: Dictionary) -> void:
	var crowded := meta.duplicate(true)
	var latest: Dictionary = crowded.past_lives.lives.back()
	latest.facts = []
	for k in 12: latest.facts.append({"actor": "ning", "fact_id": "dense%d" % k, "fact": "忆".repeat(160), "valence": 0, "day": 1})
	latest.summary.choices = []
	for k in 8: latest.summary.choices.append({"day": k + 1, "title": "题".repeat(40), "result": "果".repeat(240)})
	var run := sample(State.new_meta())
	Crisis.state(run).next_warning_day = 2
	for day in [2, 9, 16, 23, 30, 37, 44]:
		run.pday = day
		run.t = (day - 1) * 1440 + 120
		Crisis.poll(run)
		if day != 44:
			run.t = int(Crisis.view(run).end_t)
			Crisis.poll(run)
	latest.summary.crisis = Past.crisis_snapshot(run.crisis)
	var trade := Trade.state(run)
	for actor in Trade.ACTORS: trade.aid.append({"id": "old-" + actor, "actor": actor, "req": {"rice": 3}, "give": {"firewood": 3, "mugwort": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 120})
	trade.debt = {"id": "old-debt", "actor": "zhou", "req": {"rice": 5}, "give": {"wood": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 720, "overdue": false}
	latest.summary.trade = Past.trade_snapshot(trade)
	latest.summary.npcs = Past.npc_snapshot(Npcs.state(run))
	latest.summary.mainline.history = []
	for k in 16: latest.summary.mainline.history.append({"day": k + 1, "t": k * 1440, "action": "fact", "result": "结".repeat(240)})
	for unicode in [false, true]:
		if unicode:
			for fact in latest.facts: fact.fact = "𠮷".repeat(160)
			for choice in latest.summary.choices: choice.result = "𠮷".repeat(240)
		var text := Archive.render(crowded)
		check(text.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "All-system mainline archive exceeded UTF16 bound")
		for heading in ["第 1 世", "旧世交易结算", "旧世风声与危机结算", "旧世邻人自主行动", "旧世主线与结局"]: check(text.contains(heading), "Dense latest life lost whole system: " + heading)

func test_public_director_guard() -> void:
	var run := sample(State.new_meta())
	run.pday = 7
	run.t = 6 * 1440 + 180
	run.home = {"rice": 10, "wood": 10, "water": 10, "firewood": 10, "nails": 10, "mugwort": 10, "flatbread": 10}
	var story := Core.state(run)
	story.stage = "mortuary"
	story["private"] = "HIDDEN_STORY_WORK"
	story.work = {"id": "private-work", "action": "copy", "start_t": 100, "end_t": 130, "data": {"secret": "HIDDEN_STORY_WORK"}}
	Past.state(run).inherited = [{"fact": "HIDDEN_UNAWAKENED"}]
	var sent := Director.snapshot(run)
	check(sent.state.mainline.published and not JSON.stringify(sent.state.mainline).contains("HIDDEN"), "Public writer context leaked construction data or unawakened facts")
	check(not sent.state.mainline.has("work") and sent.state.mainline.evidence == {"mortuary": false, "temple": false}, "AI context turned ongoing work into current-life proof")
	var plan: Dictionary = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json")))
	var claim := "MODEL_FALSE_CLAIM：已取证已破阵已离城"
	for event in plan.days:
		event.day += int(run.pday)
		event.title = "MODEL_FALSE_CLAIM"
		event.text = claim
		for choice in event.choices:
			choice.text = "MODEL_FALSE_CLAIM"
			choice.result = claim
			if not choice.get("after", {}).is_empty(): choice.after.text = claim
	plan.days[0].choices[0].after = {"days": 1, "give": {"wood": 1}, "text": claim}
	check(Director.accept(run, sent, plan), "Mainline guard rejected a structurally valid economic plan")
	run.pday = 8
	run.t = 7 * 1440 + 180
	check(Director.poll(run).begins_with("world:"), "Buffered event did not open for real mainline prose guard")
	var display := Director.entry(run)
	var raw: Dictionary = Director.state(run).active
	check(not JSON.stringify(display).contains("MODEL_FALSE_CLAIM") and raw.text == claim, "Mainline model claims reached title/body/options/results or raw answer was rewritten")
	check(display.choices[0].get("req", {}) == raw.choices[0].get("req", {}) and display.choices[0].get("give", {}) == raw.choices[0].get("give", {}), "Mainline prose guard altered actual costs and rewards")
	check(Director.choose(run, 0) == "", "Guarded economic event became unplayable")
	check(not str(run.event_result).contains("MODEL_FALSE_CLAIM") and not JSON.stringify(run.log).contains("MODEL_FALSE_CLAIM"), "False mainline claims escaped through result or history")
	check(not story.evidence.mortuary and story.interventions.ritual_t == -1 and story.ending.is_empty(), "Ordinary AI dialogue performed a real quest action")
	run.pday = 9
	run.t = 8 * 1440 + 180
	Director.poll(run)
	check(not JSON.stringify(run.log).contains("MODEL_FALSE_CLAIM"), "False mainline claims escaped through promised delivery")
	Director.state(run).active = {"past_memory": true, "text": "LOCAL_WITNESSED_FRAGMENT"}
	check(Director.entry(run).text == "LOCAL_WITNESSED_FRAGMENT", "Local actual memory awakening was censored as untrusted AI prose")
	var fixtures := [Director.snapshot(sample(State.new_meta()))]
	for kind in ["hold", "escape", "ritual"]: fixtures.append(Director.snapshot(ended(State.new_meta(), kind)))
	fixtures.append(sent)
	var path := OS.get_environment("TEMP").path_join("ledger-mainline-public-fixtures.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Could not export fictional actual Godot contexts")
	if file != null:
		file.store_string(JSON.stringify(fixtures))
		file.close()

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var root_path := ProjectSettings.globalize_path("res://Memory.md")
	var root_before := FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else ""
	var suffix := str(OS.get_process_id())
	Game.save_path = "user://mainline-memory-" + suffix + "-save.json"
	Game.meta_path = "user://mainline-memory-" + suffix + "-meta.json"
	Game.memory_path = "user://mainline-memory-" + suffix + "-Memory.md"
	scratch = [Game.save_path, Game.meta_path, Game.memory_path]
	Game.no_save = false
	test_three_endings_and_settlement()
	test_game_continue_callbacks_and_manual_close()
	var archived := test_actual_file_and_hidden_boundaries()
	test_daily_legacy_and_invalid(archived)
	test_all_system_budget(archived)
	test_public_director_guard()
	check((FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else "") == root_before, "Fixture changed real player's Memory.md")
	Game.no_save = true
	for path in scratch:
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Could not clean isolated file")
	print("Mainline memory/endings: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
