extends Node
## Offline replay of an explicitly authorized real answer. Never generates/retries.
const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Director = preload("res://scripts/core/director.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Inv = preload("res://scripts/core/inv.gd")
var checks := 0
var failures := 0
var recorded := {}
const SPOILER := "泄密标记：已确认是假且已修复"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample(pre := false) -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 824103)
	if not pre: Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	run.home = {"rice": 30, "wood": 10, "water": 10, "firewood": 10, "nails": 10, "mugwort": 10, "flatbread": 10}
	return run

func accepted() -> Dictionary:
	var run := sample()
	var sent: Dictionary = recorded.snapshot
	var d := Director.state(run)
	d.session = sent.session
	d.revision = sent.revision
	d.enabled = true
	at(run, int(sent.current_day), int(sent.time) % 1440)
	check(Director.accept(run, sent, recorded.result.plan), "Real complete plan was not accepted")
	check(Crisis.state(run).pending == recorded.result.plan.crisis, "Accept passed without installing actual real crisis proposal")
	at(run, int(recorded.result.plan.crisis.warning_day))
	Post.crisis_refresh(run)
	check(Crisis.view(run).kind == recorded.result.plan.crisis.kind and Crisis.view(run).confirmed == "unknown", "Real proposed warning did not publish without exposing hidden truth")
	check(not Crisis.propose(run, {"kind": "well_freeze", "actor": "ning", "warning_day": int(run.pday) + 1, "real": false}, int(run.pday)), "Replanning replaced a public real proposal")
	return run

func action(run: Dictionary, id: String) -> String:
	return Post.crisis_action(run, id, str(Crisis.view(run).token))

func test_real_proposal_branches() -> void:
	check(recorded.status == 200 and recorded.result.source == "ark-plan", "Fixture is not a successful real answer")
	check(recorded.result.reasoning_effort == "low", "Real test did not use low reasoning")
	check(Director.validate(recorded.result.plan, int(recorded.snapshot.current_day)), "Real answer no longer satisfies strict plan contract")
	var prepared := accepted()
	check(action(prepared, "investigate") == "", "Real-proposal inspection did not start")
	Post.advance(prepared, 30)
	var is_real := bool(recorded.result.plan.crisis.real)
	check(Crisis.view(prepared).confirmed == ("real" if is_real else "false"), "Actual inspection did not match locked real proposal")
	if not is_real:
		check(Crisis.view(prepared).outcome == "false_alarm", "False real proposal did not resolve through inspection")
		return
	check(action(prepared, "prepare") == "", "Real-proposal preparation did not start")
	Post.advance(prepared, 60)
	var impact := int(Crisis.view(prepared).impact_t)
	at(prepared, impact / 1440 + 1, impact % 1440)
	Post.crisis_refresh(prepared)
	check(Crisis.view(prepared).outcome == "averted", "Real proposal's prepared branch failed to avert actual impact")
	var observed := accepted()
	check(action(observed, "ignore") == "", "Real-proposal observation branch unavailable")
	at(observed, impact / 1440 + 1, impact % 1440)
	Post.crisis_refresh(observed)
	check(Crisis.view(observed).stage == "impact", "Real proposal's observation branch converged with prepared branch")
	check(int(Crisis.market_effect(observed, "zhou").price_add) == 1, "Recorded fuel proposal had no actual market consequence")
	check(action(observed, "emergency") == "", "Real-proposal emergency could not start")
	Post.advance(observed, 90)
	check(Crisis.view(observed).outcome == "repaired" and int(Crisis.market_effect(observed, "zhou").price_add) == 0, "Real-proposal emergency failed to restore supply")
	var helped := accepted()
	# Earn a genuine favor with an actual local material transfer to this actor.
	var actor: String = recorded.result.plan.crisis.actor
	check(Post.trade_action(helped, actor, "aid", str(Trade.quote(helped, actor).id)) == "", "Could not earn real favor for recorded response")
	var favors := int(Trade.contact(helped, actor).favors)
	check(action(helped, "aid") == "", "Real-proposal favor response could not start")
	Post.advance(helped, 30)
	check(Crisis.view(helped).protected and int(Trade.contact(helped, actor).favors) == favors - 1, "Recorded favor branch lacked protection or actual cost")

func test_adversarial_prose_cannot_disclose_or_repair() -> void:
	var run := sample(true)
	var sent := Director.snapshot(run)
	var plan: Dictionary = recorded.result.plan.duplicate(true)
	for event in plan.days:
		event.day -= int(recorded.snapshot.current_day)
		event.title = SPOILER
		event.text = SPOILER
		for choice in event.choices:
			choice.text = SPOILER
			choice.result = SPOILER
			if not choice.get("after", {}).is_empty(): choice.after.text = SPOILER
	plan.days[0].choices[0].after = {"days": 1, "give": {"firewood": 1}, "text": SPOILER}
	check(Director.validate(plan, 0), "Adversarial fixture failed structure before testing gameplay isolation")
	check(Director.accept(run, sent, plan), "Adversarial numerical plan was not installed")
	Pre.start_disaster(run)
	at(run, 1)
	check(Director.poll(run).begins_with("world:"), "Pre-warning model event did not open for guard test")
	var safe := Director.entry(run)
	check(not JSON.stringify(safe).contains(SPOILER), "Private proposal leaked through visible title/body/choice/result/delivery text")
	check(safe.title.contains("第1日"), "Guarded letters lost their distinct day in journal and past-life fact identity")
	var raw: Dictionary = Director.state(run).active
	check(raw.text == SPOILER, "Fixture did not preserve an actually malicious source answer")
	check(safe.choices[0].req == raw.choices[0].req and safe.choices[0].give == raw.choices[0].give, "Prose guard changed validated choice costs or rewards")
	check(Director.choose(run, 0) == "", "Guarded numerical choice became unplayable")
	check(not str(run.event_result).contains(SPOILER) and not JSON.stringify(run.log).contains(SPOILER), "Model spoiler escaped through result or game log")
	check(not Crisis.state(run).pending.is_empty() and Crisis.view(run).is_empty(), "Ordinary model choice investigated or repaired hidden crisis")
	at(run, 2)
	Director.poll(run)
	check(not JSON.stringify(run.log).contains(SPOILER), "Model spoiler escaped through a promised delivery")
	Post.crisis_refresh(run)
	var d := Director.state(run)
	d.active = raw.duplicate(true)
	d.active.erase("crisis_rules_text") # Guard must also cover plans that omitted a proposal.
	run.pending_event = d.active.uid
	check(not JSON.stringify(Director.entry(run)).contains(SPOILER), "Unknown public crisis leaked through an unflagged model event")
	check(not Crisis.view(run).investigated and Crisis.view(run).confirmed == "unknown", "Model text changed rule-owned investigation facts")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	recorded = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/crisis-ark-recorded.json")))
	test_real_proposal_branches()
	test_adversarial_prose_cannot_disclose_or_repair()
	print("Crisis recorded replay: %d checks, %d failures; no network" % [checks, failures])
	get_tree().quit(1 if failures else 0)
