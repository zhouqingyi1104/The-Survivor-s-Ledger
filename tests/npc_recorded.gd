extends Node
## Replay an immutable real ARK answer; never generates or retries a model call.
const Export = preload("res://tests/npc_export.gd")
const Data = preload("res://scripts/core/data.gd")
const Director = preload("res://scripts/core/director.gd")
const Dialogue = preload("res://scripts/core/npc_dialogue.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
var checks := 0
var failures := 0
var recorded := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample() -> Dictionary:
	var source := Export.new()
	var run: Dictionary = source.fixture()
	source.free()
	var d := Director.state(run)
	d.session = recorded.snapshot.session
	d.revision = recorded.snapshot.revision
	d.enabled = true
	return run

func accepted() -> Dictionary:
	var run := sample()
	var before := run.duplicate(true)
	check(Director.accept(run, recorded.snapshot, recorded.result.plan), "Actual recorded NPC plan rejected")
	check(run.home == before.home and run.npcs == before.npcs and run.trade == before.trade, "Accepting real speech changed economic state")
	return run

func test_actual_dialogue_and_lock() -> void:
	check(recorded.status == 200 and recorded.result.source == "ark-plan", "Fixture is not an actual successful ARK response")
	check(recorded.result.reasoning_effort == "low" and int(recorded.result.usage.total_tokens) > 0, "Fixture lost actual reasoning/usage attribution")
	check(recorded.result.plan.npc_dialogue.size() == 3, "Real answer omitted one of the three NPC selections")
	check(Director.validate(recorded.result.plan, int(recorded.snapshot.current_day), recorded.snapshot.state.npc_dialogue), "Real recorded output violates strict contract")
	var run := accepted()
	for row in recorded.result.plan.npc_dialogue:
		var speech := Dialogue.render(run, row.actor)
		var phrases: Dictionary = Dialogue.catalogue()[row.actor]
		check(speech.source == "ark-plan" and speech.decision_id == row.decision_id, "Actual selected dialogue was not displayed")
		check(speech.text.begins_with(phrases.openers[row.opener].text) and speech.text.ends_with(phrases.closers[row.closer].text), "Real selected opener/closer did not survive game application")
		check(speech.text.contains(Npc.view(run, row.actor).reason), "AI wording replaced local decision facts")
	check(Dialogue.context(run).slots.is_empty(), "Real read speech was not frozen")
	var again: Dictionary = recorded.result.plan.duplicate(true)
	for row in again.npc_dialogue:
		var slot: Dictionary = {}
		for candidate in recorded.snapshot.state.npc_dialogue.slots:
			if candidate.actor == row.actor: slot = candidate
		row.opener = slot.openers[(slot.openers.find(row.opener) + 1) % slot.openers.size()]
	check(Director.accept(run, recorded.snapshot, again), "Late response could not retain compatible event plan")
	for row in recorded.result.plan.npc_dialogue:
		check(Dialogue.state(run).actors[row.actor].opener == row.opener, "Late response rewrote already read actual AI speech")
	var loaded: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(run)))
	for actor in Dialogue.ACTORS: check(Dialogue.render(loaded, actor).text == Dialogue.render(run, actor).text, "Save/load changed recorded dialogue")
	check(Crisis.view(run).confirmed == "unknown" and not Crisis.view(run).investigated, "AI dialogue disclosed or settled private crisis truth")

func test_same_choices_same_consequences() -> void:
	for action in ["support", "decline"]:
		var local := sample()
		var dynamic := accepted()
		for actor in Dialogue.ACTORS:
			Dialogue.render(local, actor)
			Dialogue.render(dynamic, actor)
			check(Npc.options(local, actor) == Npc.options(dynamic, actor), "Real AI selected dialogue changed options")
			var response: String = action
			if actor == "traveler" and action == "support":
				check(Npc.options(dynamic, actor)[0].block != "", "The actual low-fuel fixture must block unsupported material aid")
				var before: Dictionary = dynamic.duplicate(true)
				check(Npc.act(dynamic, actor, "support", Npc.view(dynamic, actor).token) != "" and dynamic == before, "AI speech bypassed insufficient firewood or consumed failed aid")
				response = "decline"
			check(Npc.act(local, actor, response, Npc.view(local, actor).token) == "", "Offline response unavailable")
			check(Npc.act(dynamic, actor, response, Npc.view(dynamic, actor).token) == "", "Real AI response unavailable")
		local.pday = 2
		dynamic.pday = 2
		local.t = 2040
		dynamic.t = 2040
		Npc.poll(local)
		Npc.poll(dynamic)
		check(local.home == dynamic.home and local.npcs == dynamic.npcs and local.trade == dynamic.trade, "Real AI dialogue altered actual response settlement")
		for actor in Dialogue.ACTORS: check(Dialogue.render(dynamic, actor).text.contains(Npc.view(dynamic, actor).last_result), "Real AI displayed stale future action after settlement")
		check(not Director.accept(dynamic, recorded.snapshot, recorded.result.plan), "Late actual answer altered a completed NPC decision")

func test_malicious_rows_rejected() -> void:
	for field in ["text", "give", "real", "memory", "debug"]:
		var run := sample()
		var hostile: Dictionary = recorded.result.plan.duplicate(true)
		hostile.npc_dialogue[0][field] = "恶意改写"
		var before := run.duplicate(true)
		check(not Director.accept(run, recorded.snapshot, hostile) and run == before, "Real-answer extra field bypassed strict validation: " + field)
	var other := sample()
	Director.state(other).session = "other-runtime-life"
	check(not Director.accept(other, recorded.snapshot, recorded.result.plan), "Real answer crossed runtime sessions")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	recorded = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/npc-ark-recorded.json")))
	test_actual_dialogue_and_lock()
	test_same_choices_same_consequences()
	test_malicious_rows_rejected()
	print("NPC recorded replay: %d checks, %d failures; no network" % [checks, failures])
	get_tree().quit(1 if failures else 0)
