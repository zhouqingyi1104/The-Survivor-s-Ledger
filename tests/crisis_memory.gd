extends Node
## Public crisis facts survive history eviction; hidden proposals never enter old-life context.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
var checks := 0
var failures := 0
var archive_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample(meta: Dictionary, daily := false) -> Dictionary:
	var run := State.new_run("escort", meta, 36581)
	if daily: run.flags.daily = "2026-10-24"
	Pre.start_disaster(run)
	run.home = {"rice": 100, "wood": 30, "nails": 30, "mugwort": 30, "water": 30, "firewood": 30}
	at(run, 1)
	return run

func publish(run: Dictionary, day: int, kind: String, real: bool, actor: String) -> void:
	at(run, day - 1)
	check(Crisis.propose(run, {"kind": kind, "actor": actor, "warning_day": day, "real": real}, day - 1), "Could not plan actual crisis slot")
	at(run, day)
	check(Crisis.poll(run) != "", "Planned warning was not published")

func choose(run: Dictionary, action: String, finish := true) -> void:
	check(Crisis.act(run, action, str(Crisis.view(run).token)) == "", "Actual crisis action failed: " + action)
	if not run.busy.is_empty() and finish:
		var data: Dictionary = run.busy.data.duplicate(true)
		run.t = int(run.busy.end)
		run.pday = int(run.t) / 1440 + 1
		check(Crisis.complete(run, data) != "", "Actual crisis work did not complete")
		run.busy = {}

func test_actual_public_history() -> Dictionary:
	var meta := State.new_meta()
	var run := sample(meta)
	publish(run, 2, "well_freeze", false, "ning")
	choose(run, "investigate")
	check(Crisis.state(run).completed.size() == 1, "Investigated false alarm was not retained")
	publish(run, 9, "fuel_shortage", true, "zhou")
	choose(run, "prepare")
	run.t = int(Crisis.view(run).impact_t)
	run.pday = 11
	Crisis.poll(run)
	check(Crisis.state(run).completed.size() == 2, "Averted real crisis was not retained")
	publish(run, 16, "herb_shortage", true, "traveler")
	choose(run, "ignore")
	run.t = int(Crisis.view(run).impact_t)
	run.pday = 18
	Crisis.poll(run)
	choose(run, "emergency")
	check(Crisis.state(run).completed.size() == 3, "Repaired crisis was not retained")
	publish(run, 23, "well_freeze", false, "ning")
	# Real paid starts and interruptions evict all previous crisis history without revealing truth.
	for k in 7:
		choose(run, "investigate", false)
		run.busy = {}
		run.t += 1
		check(Crisis.poll(run) != "", "Interrupted work was not recorded")
	check(not Crisis.state(run).history.any(func(h): return h.kind == "fuel_shortage"), "Fixture did not evict early crisis history")
	var expected := Past.crisis_snapshot(run.crisis)
	check(expected.completed.size() == 3 and expected.active.confirmed == "unknown", "Public final summary dropped completed crises or revealed unverified truth")
	check(not JSON.stringify(expected).contains('"real":') and not expected.has("pending"), "Private truth or proposal escaped the public snapshot")
	run.phase = "dead"
	Ledger.end_run(run, meta)
	var life: Dictionary = Past.book(meta).lives.back()
	check(life.summary.crisis == expected, "Settlement failed to preserve public crisis facts")
	var markdown := Archive.render(meta)
	for phrase in ["旧世风声与危机结算", "井口冻裂", "运柴中断", "药草挤兑", "虚惊结案", "危机成真但影响被防住", "补救后提前恢复", "第 23 日公开：尚未核实，真假未知", "旧世危机不是本世处罚"]:
		check(markdown.contains(phrase), "Markdown omitted or overstated crisis facts: " + phrase)
	check(Archive.sync(meta, archive_path) == OK, "Could not write isolated crisis Memory.md")
	var actual := Archive.read_context(archive_path)
	check(actual.get("markdown", "") == markdown and actual.get("sha256", "") == markdown.sha256_text(), "AI context did not read the actual crisis Markdown file")
	var next := State.new_run("escort", meta, 98374)
	check(next.crisis.is_empty(), "New life inherited old crisis penalties")
	check(Crisis.context(next).active.is_empty() and Crisis.state(next).completed.is_empty(), "Old resolved or unverified crises became new-world facts")
	run.crisis.completed.clear()
	check(life.summary.crisis == expected, "Archived crisis summary aliases the mutable current state")
	return meta

func test_legacy_daily_and_bounds(meta: Dictionary) -> void:
	var old := meta.duplicate(true)
	old.past_lives.lives[0].summary.erase("crisis")
	check(not Archive.render(old).contains("旧世风声与危机结算"), "Old metadata fabricated a crisis summary")
	var legacy: Dictionary = meta.past_lives.lives[0].summary.crisis.duplicate(true)
	legacy.erase("completed")
	check(Past.crisis_snapshot(legacy).active.confirmed == "unknown", "A legacy public snapshot without completed records stopped working")
	check(Past.crisis_snapshot({"schema": 1, "active": {}, "completed": [], "history": [], "pending": {"kind": "well_freeze", "real": true}}).is_empty(), "An unpublished pending crisis became an old-life fact")
	var private_copy: Dictionary = meta.past_lives.lives[0].summary.crisis.duplicate(true)
	private_copy.active.real = false
	private_copy.active.work = {"private": "ignored"}
	private_copy.pending = {"real": true}
	check(Past.crisis_snapshot(private_copy) == meta.past_lives.lives[0].summary.crisis, "Private fields contaminated persisted crisis facts")
	for mode in ["count", "truth", "clock", "kind", "history"]:
		var bad: Dictionary = meta.past_lives.lives[0].summary.crisis.duplicate(true)
		match mode:
			"count":
				bad.completed = []
				for k in 7: bad.completed.append(meta.past_lives.lives[0].summary.crisis.completed[0])
			"truth": bad.active.investigated = true
			"clock": bad.active.end_t += 1
			"kind": bad.active.kind = "blood_moon"
			"history":
				bad.history = []
				for k in 13: bad.history.append(meta.past_lives.lives[0].summary.crisis.history[0])
		check(Past.crisis_snapshot(bad).is_empty(), "Malformed crisis summary accepted: " + mode)
	var daily_meta := State.new_meta()
	var daily := sample(daily_meta, true)
	at(daily, 2)
	Crisis.poll(daily)
	daily.phase = "dead"
	Ledger.end_run(daily, daily_meta)
	var daily_life: Dictionary = Past.book(daily_meta).lives.back()
	check(daily_life.facts.is_empty() and daily_life.summary.crisis.active.confirmed == "unknown", "Daily summary either seeded recollections or leaked truth")
	var many := meta.duplicate(true)
	many.past_lives.count = 8
	many.past_lives.lives = []
	for ordinal in range(1, 9):
		var life: Dictionary = meta.past_lives.lives[0].duplicate(true)
		life.life = ordinal
		life.facts = []
		for k in 12: life.facts.append({"actor": "ning", "fact_id": "f%d" % k, "fact": "事".repeat(160), "valence": 0, "day": 1})
		many.past_lives.lives.append(life)
	var bounded := Archive.render(many)
	check(bounded.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "Crisis details exceeded the existing UTF-16 archive budget")
	check(bounded.contains("第 8 世") and bounded.contains("运柴中断") and bounded.contains("第 23 日公开：尚未核实，真假未知"), "Archive truncation lost the latest public crisis facts")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	archive_path = "user://crisis-memory-%d.md" % OS.get_process_id()
	var meta := test_actual_public_history()
	test_legacy_daily_and_bounds(meta)
	if FileAccess.file_exists(archive_path):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path)) == OK, "Fixture crisis Markdown cleanup failed")
	print("Crisis memory: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
