extends Node
const Dialogue = preload("res://scripts/core/npc_dialogue.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 901)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Trade.state(run)
	Npc.state(run)
	Crisis.state(run).next_warning_day = 100
	at(run, 2)
	Npc.poll(run)
	return run

func rows(candidates: Dictionary, index := 0) -> Array:
	var out := []
	for slot in candidates.slots:
		out.append({"actor": slot.actor, "decision_id": slot.decision_id,
			"opener": slot.openers[index % slot.openers.size()], "closer": slot.closers[index % slot.closers.size()]})
	return out

func plan(run: Dictionary, choices: Array) -> Dictionary:
	var out: Dictionary = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json")))
	for event in out.days: event.day += int(run.pday)
	out["npc_dialogue"] = choices.duplicate(true)
	return out

func test_catalogue_and_freeze() -> void:
	var run := sample()
	var candidates := Dialogue.context(run)
	check(candidates.slots.size() == 3, "Every pending NPC has a dialogue candidate")
	check(Dialogue.state(run).actors.is_empty(), "Snapshot froze dialogue before the player read it")
	var before := run.duplicate(true)
	var changed_text := []
	for actor in Dialogue.ACTORS:
		var expressions: Dictionary = Dialogue.catalogue()[actor]
		check(expressions.openers.size() >= 6 and expressions.closers.size() >= 6, "Dialogue catalogue lacks per-actor variety")
		var text := Dialogue.render(run, actor)
		check(text.changed and text.source == "local" and not text.text.is_empty(), "Offline first read did not freeze reviewed speech")
		check(text.text.contains(Npc.view(run, actor).reason), "Dialogue omitted actual rule-owned motive")
		check(not Dialogue.render(run, actor).changed and Dialogue.render(run, actor).text == text.text, "Repeated read changed dialogue")
		changed_text.append(text.text)
	check(Dialogue.context(run).slots.is_empty(), "Read dialogue remained editable in future prompts")
	check(before.home == run.home and before.npcs == run.npcs and before.trade == run.trade, "Dialogue changed inventory, decisions or social balances")
	var loaded: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	for actor in Dialogue.ACTORS: check(Dialogue.render(loaded, actor).text == Dialogue.render(run, actor).text, "Save/load changed already read dialogue")
	var variants := {}
	for day in range(2, 15):
		var alternate := sample()
		for actor in Npc.ACTORS:
			alternate.npcs.actors[actor].plan.day = day
			alternate.npcs.actors[actor].plan.id += "-" + str(day)
		variants[Dialogue.render(alternate, "ning").text] = true
	check(variants.size() >= 6, "Seeded offline dialogue repeats a single canned expression")
	var first := sample()
	var second := first.duplicate(true)
	check(Dialogue.render(first, "zhou").text == Dialogue.render(second, "zhou").text, "Offline output is not deterministic")
	check(Dialogue.render(first, "missing").text == "", "Unknown contact generated speech")
	var corrupt := sample()
	Dialogue.state(corrupt).actors.ning = {"decision_id": Npc.view(corrupt, "ning").plan.id, "opener": "unknown", "closer": "unknown", "frozen": true, "source": "ark-plan"}
	check(Dialogue.render(corrupt, "ning").source == "local", "Malformed saved phrase IDs did not recover to reviewed local dialogue")

func test_strict_rows_and_tones() -> void:
	var run := sample()
	Trade.state(run).actors.ning.trust = -3
	Trade.state(run).actors.zhou.trust = 3
	Npc.state(run).actors.ning.plan.reason_codes = ["distrust"]
	Npc.state(run).actors.zhou.plan.reason_codes = ["trust"]
	var candidates := Dialogue.context(run)
	var selected := rows(candidates)
	check(Dialogue.valid_rows(selected, candidates), "Valid dialogue IDs rejected")
	check(candidates.slots[0].tone == "guarded" and candidates.slots[1].tone == "warm", "Local known motives did not constrain tone")
	for index in range(10):
		var bad := selected.duplicate(true)
		match index:
			0: bad[0].actor = "secret"
			1: bad[0].decision_id = "old-life"
			2: bad[0].opener = "z_o1"
			3: bad[0].closer = "n_c7"
			4: bad[0].text = "前世秘密、危机已修好"
			5: bad[0].give = {"rice": 3}
			6: bad[0].opener = "arbitrary dialogue"
			7: bad.append(bad[0].duplicate())
			8: bad[0].erase("closer")
			9: bad[0].opener = 1
		check(not Dialogue.valid_rows(bad, candidates), "Malformed/model-authored dialogue escaped case %d" % index)
	check(not Dialogue.valid_rows(null, candidates) and not Dialogue.valid_rows({}, candidates), "Non-array dialogue accepted")
	check(Dialogue.accept(run, candidates, selected), "Unread rule-bound AI speech rejected")
	check(Dialogue.render(run, "ning").source == "ark-plan", "Actual AI-selected IDs were not used")
	var frozen: String = Dialogue.render(run, "ning").text
	var next := rows(candidates, 1)
	check(Dialogue.accept(run, candidates, next), "Other unread dialogue could not be enriched")
	check(Dialogue.render(run, "ning").text == frozen, "Late AI reply changed already read speech")
	check(Dialogue.render(run, "zhou").text.contains(Dialogue.catalogue().zhou.openers[next[1].opener].text), "Unread AI reply was ignored")

func test_director_boundary() -> void:
	var run := sample()
	var sent := Director.snapshot(run)
	var selected := rows(sent.state.npc_dialogue, 1)
	var generated := plan(run, selected)
	var revision: int = Director.state(run).revision
	check(Director.accept(run, sent, generated), "Director did not accept actual bounded NPC speech")
	check(Director.state(run).revision == revision, "Dialogue acceptance invalidated itself or replanned")
	check(Dialogue.render(run, "ning").source == "ark-plan", "Director did not install selected speech")
	var old_text: String = Dialogue.render(run, "ning").text
	var alternate := generated.duplicate(true)
	alternate.npc_dialogue = rows(sent.state.npc_dialogue, 2)
	check(Director.accept(run, sent, alternate) and Dialogue.render(run, "ning").text == old_text, "Same-revision late response replaced frozen dialogue")
	var stale := sample()
	var old := Director.snapshot(stale)
	Director.note_choice(stale, "Actual response", "支援已发生")
	check(not Director.accept(stale, old, plan(stale, rows(old.state.npc_dialogue))), "Reply survived a real choice revision")
	var other := sample()
	check(not Director.accept(other, sent, generated), "Dialogue crossed runtime sessions")
	var rewound := sample()
	var future := Director.snapshot(rewound)
	rewound.t -= 1
	check(not Director.accept(rewound, future, plan(rewound, rows(future.state.npc_dialogue))), "Dialogue crossed a rewind")
	var finished := sample()
	var active := Director.snapshot(finished)
	at(finished, 2, 600)
	Npc.poll(finished)
	check(not Director.accept(finished, active, plan(finished, rows(active.state.npc_dialogue))), "Finished decision accepted stale speech")
	var daily := sample()
	var daily_sent := Director.snapshot(daily)
	daily.flags.daily = "2026-10-24"
	Director.state(daily).enabled = true
	check(not Director.accept(daily, daily_sent, plan(daily, rows(daily_sent.state.npc_dialogue))), "Daily game accepted model-selected speech")
	var malformed := sample()
	var valid := Director.snapshot(malformed)
	var unsafe := plan(malformed, rows(valid.state.npc_dialogue))
	unsafe.npc_dialogue[0].give = {"mugwort": 3}
	var before := malformed.duplicate(true)
	check(not Director.accept(malformed, valid, unsafe) and before == malformed, "Malformed dialogue partially mutated plans or inventory")

func test_knowledge_and_numeric_invariance() -> void:
	var run := sample()
	Past.state(run).inherited = [{"actor": "ning", "fact": "PRIVATE_UNAWAKENED"}]
	Past.state(run).schedule = [{"day": 9, "fact": {"fact": "PRIVATE_SCHEDULE"}}]
	Crisis.state(run).pending = {"kind": "well_freeze", "actor": "ning", "warning_day": 9, "real": false}
	check(not JSON.stringify(Dialogue.context(run)).contains("PRIVATE"), "Dialogue exposed inherited or future memories")
	var public: Dictionary = Director.snapshot(run).state.npcs
	check(not JSON.stringify(public).contains("PRIVATE") and not JSON.stringify(public).contains('"real"'), "NPC context exposed private memory or crisis truth")
	for actor in Dialogue.ACTORS: check(not Dialogue.render(run, actor).text.contains("PRIVATE"), "Unawakened private memory reached dialogue")
	var awake := sample()
	Past.state(awake).awakenings = [{"actor": "ning", "life": 1, "age": 1, "fact_id": "ning:medicine", "fact": "本人已觉醒事实", "response": "acknowledge"}]
	check(Dialogue.render(awake, "ning").text.contains("本人已觉醒事实"), "Actor cannot refer to its real awakened fragment")
	check(not Dialogue.render(awake, "zhou").text.contains("本人已觉醒事实"), "Other actor learned someone else's fragment")
	var baseline := sample()
	var ai := baseline.duplicate(true)
	var candidates := Dialogue.context(ai)
	check(Dialogue.accept(ai, candidates, rows(candidates, 1)), "Could not set up AI numeric invariance")
	for actor in Dialogue.ACTORS:
		Dialogue.render(ai, actor)
		Dialogue.render(baseline, actor)
		check(Npc.options(ai, actor) == Npc.options(baseline, actor), "AI speech changed choice costs or blockers")
	at(ai, 2, 600)
	at(baseline, 2, 600)
	Npc.poll(ai)
	Npc.poll(baseline)
	check(ai.home == baseline.home and ai.npcs == baseline.npcs and ai.trade == baseline.trade, "AI speech changed actual NPC/player balances or later decisions")
	var daily_a := sample()
	daily_a.flags.daily = "2026-10-24"
	var daily_b := daily_a.duplicate(true)
	Past.state(daily_b).id = "other-random-life"
	check(Dialogue.render(daily_a, "ning").text == Dialogue.render(daily_b, "ning").text, "Daily dialogue varies with random life identity")

func test_frozen_phrasing_live_facts() -> void:
	for action in ["support", "favor", "decline"]:
		var run := sample()
		run.home = {"rice": 20, "mugwort": 20, "wood": 20, "firewood": 20}
		Trade.state(run).actors.ning.favors = 1
		var before := Dialogue.render(run, "ning")
		var phrasing: Dictionary = Dialogue.state(run).actors.ning.duplicate(true)
		check(Npc.act(run, "ning", action, str(Npc.view(run, "ning").token)) == "", "Could not set up live dialogue response " + action)
		var after := Dialogue.render(run, "ning")
		check(after.text != before.text and not after.changed, "Frozen phrasing prevented real response facts from updating " + action)
		check(Dialogue.state(run).actors.ning == phrasing, "Real response changed frozen AI phrasing " + action)
		if action == "favor": check(after.text.contains("原自主行动取消") and not after.text.contains("我的打算：筹措周转"), "Favor dialogue still claimed canceled autonomous action")
		at(run, 2, 600)
		Npc.poll(run)
		var done := Dialogue.render(run, "ning")
		check(done.text.contains("本次已经执行") and done.text.contains(Npc.view(run, "ning").last_result), "Finished dialogue omitted actual settlement " + action)
		check(not done.text.contains("我会") and Dialogue.state(run).actors.ning == phrasing, "Finished dialogue still promised future action or changed phrasing " + action)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	test_catalogue_and_freeze()
	test_strict_rows_and_tones()
	test_director_boundary()
	test_knowledge_and_numeric_invariance()
	test_frozen_phrasing_live_facts()
	print("NPC dialogue: %d checks, %d failures; offline" % [checks, failures])
	get_tree().quit(1 if failures else 0)
