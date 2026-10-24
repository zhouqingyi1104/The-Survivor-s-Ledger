extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Director = preload("res://scripts/core/director.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
var checks := 0
var failures := 0
var path := ""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func at(run: Dictionary, day: int, minute: int) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute
func sample(meta: Dictionary, daily := false) -> Dictionary:
	var run := State.new_run("escort", meta, 591246)
	if daily: run.flags.daily = "2026-10-24"
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	Crisis.state(run).next_warning_day = 100
	Trade.state(run)
	Npcs.state(run)
	run.home = {"rice": 40, "wood": 10, "mugwort": 10, "firewood": 10}
	return run
func test_archive() -> Dictionary:
	var meta := State.new_meta()
	var run := sample(meta)
	Trade.influence(run, "ning", 3, "曾经互助")
	Trade.influence(run, "zhou", -3, "曾经失信")
	at(run, 2, 120)
	Post.trade_refresh(run)
	check(Post.npc_action(run, "zhou", "support", str(Npcs.view(run, "zhou").token)) == "", "Could not record actual support")
	at(run, 2, 600)
	Post.trade_refresh(run)
	at(run, 3, 120)
	Post.trade_refresh(run)
	Trade.state(run).actors.ning.favors = 1
	check(Post.npc_action(run, "ning", "favor", str(Npcs.view(run, "ning").token)) == "", "Could not record an actual reserved parcel")
	# Free dialogue, hidden archives and unawakened fact schedules are never NPC facts.
	run["npc_dialogue"] = {"secret": "SPOILER_RAW_DIALOGUE"}
	run.npcs["private"] = {"secret": "SPOILER_PRIVATE_NPC"}
	Past.state(run).inherited = [{"fact": "UNAWAKENED_SECRET"}]
	var expected := Past.npc_snapshot(run.npcs)
	check(not expected.is_empty(), "Public NPC snapshot rejected actual state")
	check(not JSON.stringify(expected).contains("SPOILER") and not JSON.stringify(expected).contains("UNAWAKENED"), "Private dialogue or unawakened facts escaped public snapshot")
	check(expected.actors.ning.plan.status == "pending", "Pending reserved parcel was falsely archived as delivered")
	run.phase = "dead"
	Ledger.end_run(run, meta)
	var life: Dictionary = Past.book(meta).lives.back()
	check(life.summary.npcs == expected, "Final run did not archive public autonomous consequences")
	var markdown := Archive.render(meta)
	for phrase in ["旧世邻人自主行动", "阿宁", "木料场老周", "过路客", "周转", "玩家凭情改托", "合卷时尚未执行，不等于已兑现", "旧计划、库存和待送物资不带入新世"]:
		check(markdown.contains(phrase), "Markdown lost or overstated NPC facts: " + phrase)
	check(not markdown.contains("SPOILER") and not markdown.contains("UNAWAKENED_SECRET"), "Private data reached real Markdown")
	check(Archive.sync(meta, path) == OK, "Isolated actual Memory file write failed")
	var context := Archive.read_context(path)
	check(context.get("markdown", "") == markdown and context.get("sha256", "") == markdown.sha256_text(), "AI context did not read actual new Memory text")
	var next := State.new_run("escort", meta, 182934)
	check(Past.public_memories(next).is_empty(), "Archived NPC story became automatic next-life knowledge")
	var next_context := Npcs.context(next)
	check(next_context.history.is_empty(), "New life inherited old NPC history or stock effects")
	for actor in ["ning", "zhou", "traveler"]:
		check(next_context.actors[actor].stock.rice == 3, "Old resource shortage became a new-life penalty")
	run.npcs.actors.ning.stock.rice = 0
	check(life.summary.npcs == expected, "Archived NPC final stock aliases mutable current run")
	return meta
func test_legacy_invalid_and_daily(meta: Dictionary) -> void:
	var legacy := meta.duplicate(true)
	legacy.past_lives.lives[0].summary.erase("npcs")
	check(not Archive.render(legacy).contains("旧世邻人自主行动"), "Old metadata invented autonomous NPC history")
	for kind in ["stock", "policy", "clock", "mode", "history"]:
		var bad: Dictionary = meta.past_lives.lives[0].summary.npcs.duplicate(true)
		match kind:
			"stock": bad.actors.ning.stock.rice = -1
			"policy": bad.actors.ning.policy.credit_allowed = "yes"
			"clock": bad.actors.ning.plan.due_t += 1
			"mode": bad.actors.ning.plan.mode = "AI_free_reward"
			"history": bad.history[0].result = "字".repeat(241)
		check(Past.npc_snapshot(bad).is_empty(), "Malformed public NPC summary accepted: " + kind)
	var daily_meta := State.new_meta()
	var daily := sample(daily_meta, true)
	at(daily, 2, 120)
	Post.trade_refresh(daily)
	at(daily, 2, 600)
	Post.trade_refresh(daily)
	daily.phase = "dead"
	Ledger.end_run(daily, daily_meta)
	var daily_life: Dictionary = Past.book(daily_meta).lives.back()
	check(daily_life.facts.is_empty() and daily_life.summary.has("npcs"), "Daily NPC recap either creates recollections or loses factual results")
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
	check(bounded.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "NPC archive exceeded existing UTF16 budget")
	check(bounded.contains("第 8 世") and bounded.contains("旧世邻人自主行动"), "Archive bound lost latest-life NPC section")
	# A real end-of-run archive may contain all three systems at once. Keep the
	# newest life even at each bounded field's maximum, rather than drop it whole.
	var crowded := meta.duplicate(true)
	var latest: Dictionary = crowded.past_lives.lives.back()
	latest.facts = []
	for k in 12: latest.facts.append({"actor": "ning", "fact_id": "m%d" % k, "fact": "事".repeat(160), "valence": 0, "day": 1})
	latest.summary.choices = []
	for k in 8: latest.summary.choices.append({"day": k + 1, "title": "题".repeat(40), "result": "果".repeat(240)})
	var crun := sample(State.new_meta())
	Crisis.state(crun).next_warning_day = 2
	for day in [2, 9, 16, 23, 30, 37, 44]:
		at(crun, day, 120)
		Crisis.poll(crun)
		if day != 44:
			crun.t = int(Crisis.view(crun).end_t)
			Crisis.poll(crun)
	latest.summary.crisis = Past.crisis_snapshot(crun.crisis)
	var tstate := Trade.state(crun)
	for actor in Trade.ACTORS:
		tstate.aid.append({"id": "old-" + actor, "actor": actor, "req": {"rice": 3}, "give": {"firewood": 3, "mugwort": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 120})
	tstate.debt = {"id": "old-debt", "actor": "zhou", "req": {"rice": 5}, "give": {"wood": 3, "nails": 3}, "due_day": 45, "due_t": 44 * 1440 + 720, "overdue": false}
	latest.summary.trade = Past.trade_snapshot(tstate)
	var dense := Archive.render(crowded)
	check(dense.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "All-system latest archive exceeded budget")
	check(dense.contains("第 1 世") and dense.contains("旧世邻人自主行动") and dense.contains("旧世风声与危机结算") and dense.contains("旧世交易结算"), "Dense latest life was silently dropped or lost a whole system")
func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	path = "user://npc-memory-%d.md" % OS.get_process_id()
	var root_path := ProjectSettings.globalize_path("res://Memory.md")
	var old_root := FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else ""
	var meta := test_archive()
	test_legacy_invalid_and_daily(meta)
	check((FileAccess.get_file_as_bytes(root_path).hex_encode() if FileAccess.file_exists(root_path) else "") == old_root, "Fixture changed player's real Memory.md")
	if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Isolated archive cleanup failed")
	print("NPC memory: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
