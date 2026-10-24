extends Node
## Real local trading -> settlement -> Markdown readback, without player files or models.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Archive = preload("res://scripts/core/life_memory_file.gd")
const Director = preload("res://scripts/core/director.gd")
var checks := 0
var failures := 0
var archive_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func at(run: Dictionary, day: int) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + 180

func sample(meta: Dictionary, daily := false) -> Dictionary:
	var run := State.new_run("escort", meta, 7184)
	if daily: run.flags.daily = "2026-10-24"
	Pre.start_disaster(run)
	at(run, 2)
	run.home = {"rice": 200, "wood": 20, "mugwort": 20, "flatbread": 20}
	Director.state(run).enabled = false
	return run

func choose(run: Dictionary, actor: String, action: String) -> void:
	Post.trade_refresh(run)
	check(Post.trade_action(run, actor, action, str(Trade.quote(run, actor).id)) == "", "Real trade failed: " + actor + "/" + action)

func test_final_ledger_survives_bounded_histories() -> Dictionary:
	var meta := State.new_meta()
	var run := sample(meta)
	choose(run, "zhou", "cash")
	at(run, 3)
	choose(run, "zhou", "cash")
	at(run, 4)
	choose(run, "zhou", "credit")
	choose(run, "ning", "aid")
	for day in range(5, 25):
		at(run, day)
		choose(run, "ning", "cash")
	choose(run, "traveler", "aid")
	check(not Past.state(run).trace.any(func(f): return f.fact_id == "trade_4_credit"), "Fixture did not evict the early loan fact")
	check(not Director.state(run).history.any(func(h): return str(h.result).contains("赊得")), "Fixture did not evict the early loan event")
	var expected := Past.trade_snapshot(run.trade)
	check(expected.actors.ning.trust == 5 and expected.actors.zhou.trust == 0, "Actual trust/default setup incorrect")
	check(expected.debt.actor == "zhou" and expected.debt.overdue and expected.aid.size() == 1, "Actual final commitments missing")
	run.phase = "dead"
	Ledger.end_run(run, meta)
	var life: Dictionary = Past.book(meta).lives.back()
	check(life.summary.trade == expected, "Settlement omitted or changed actual final trading facts")
	check(life.summary.relations.ning == 0, "Fixture no longer distinguishes trading trust from director relation")
	var markdown := Archive.render(meta)
	check(markdown.contains("旧世交易结算") and markdown.contains("阿宁：信任 +5"), "Markdown omitted final trust independent of old event history")
	check(markdown.contains("未清旧债：欠木料场老周米 ×4") and markdown.contains("当时已逾期"), "Markdown lost an unresolved early loan after history eviction")
	check(markdown.contains("待收旧世回礼：过路客约定第 25 日 08:00"), "Markdown omitted outstanding fixed return gift")
	check(markdown.contains("旧债和待收回礼不带入新世"), "Old commitments were not explicitly separated from current-life obligations")
	check(Archive.sync(meta, archive_path) == OK, "Could not write isolated runtime Markdown")
	var actual := Archive.read_context(archive_path)
	check(actual.get("markdown", "") == markdown and actual.get("sha256", "") == markdown.sha256_text(), "Planner context did not read the actual archived file")
	var next := State.new_run("escort", meta, 9944)
	check(next.trade.is_empty(), "A new life inherited the old trading ledger")
	var new_context := Trade.context(next)
	check(new_context.debt.is_empty() and new_context.aid.is_empty() and new_context.actors.ning.trust == 0, "Old debt, gifts or credit became new-life advantages")
	run.trade.actors.ning.trust = -5
	run.trade.debt.clear()
	check(life.summary.trade == expected, "Archived ledger aliases the mutable run")
	return meta

func test_old_books_daily_and_bounds(meta: Dictionary) -> void:
	var old := meta.duplicate(true)
	old.past_lives.lives[0].summary.erase("trade")
	check(not Archive.render(old).contains("旧世交易结算"), "Legacy metadata fabricated trading facts")
	var daily_meta := State.new_meta()
	var daily := sample(daily_meta, true)
	choose(daily, "ning", "cash")
	daily.phase = "dead"
	Ledger.end_run(daily, daily_meta)
	var daily_life: Dictionary = Past.book(daily_meta).lives.back()
	check(daily_life.facts.is_empty(), "Daily trading became NPC past-life recollections")
	check(daily_life.summary.trade.actors.ning.trust == 1 and Archive.render(daily_meta).contains("阿宁：信任 +1"), "Daily summary omitted its real final trading state")
	var value: Dictionary = meta.past_lives.lives[0].summary.trade
	for field in ["trust", "favors", "breaches", "breach_total"]:
		var bad := value.duplicate(true)
		bad.actors.ning[field] = 100001
		check(Past.trade_snapshot(bad).is_empty(), "Unbounded person field accepted: " + field)
	var oversized := value.duplicate(true)
	oversized.aid = [value.aid[0], value.aid[0], value.aid[0], value.aid[0]]
	check(Past.trade_snapshot(oversized).is_empty(), "Oversized gift list reached Markdown")
	var invented := value.duplicate(true)
	invented.debt.req = {"gold": 1}
	check(Past.trade_snapshot(invented).is_empty(), "Unknown goods reached Markdown")
	var invalid := value.duplicate(true)
	invalid.debt.due_t += 1
	check(Past.trade_snapshot(invalid).is_empty(), "Inconsistent signed deadline reached Markdown")
	var extra := value.duplicate(true)
	extra.quotes = {"unbounded": "x".repeat(20000)}
	extra.actors.ning.last_change = "x".repeat(20000)
	check(Past.trade_snapshot(extra) == value, "Quote/history fields leaked into the bounded archive")
	var many := meta.duplicate(true)
	many.past_lives.count = 8
	many.past_lives.lives = []
	for ordinal in range(1, 9):
		var life: Dictionary = meta.past_lives.lives[0].duplicate(true)
		life.life = ordinal
		life.facts = []
		for k in 12:
			life.facts.append({"actor": "ning", "fact_id": "f%d" % k, "fact": "事".repeat(160), "valence": 0, "day": 1})
		many.past_lives.lives.append(life)
	var bounded := Archive.render(many)
	check(bounded.to_utf16_buffer().size() <= Archive.MAX_CHARS * 2, "Trading summaries exceeded the existing UTF-16 archive budget")
	check(bounded.contains("第 8 世") and bounded.contains("阿宁：信任 +5") and bounded.contains("欠木料场老周米 ×4"), "Archive truncation lost the latest settled trading state")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	archive_path = "user://social-trade-memory-%d.md" % OS.get_process_id()
	var meta := test_final_ledger_survives_bounded_histories()
	test_old_books_daily_and_bounds(meta)
	if FileAccess.file_exists(archive_path):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path)) == OK, "Isolated Markdown cleanup failed")
	print("Social trade memory: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
