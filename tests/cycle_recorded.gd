extends Node
## Replay one authorized low-reasoning ARK answer. No network or second model call.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Director = preload("res://scripts/core/director.gd")
const Cycle = preload("res://scripts/core/cycle_inquiry.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
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
	for attr in ["food", "water", "energy", "mood", "warmth"]: run.attrs[attr] = 100

func disable_other_local_events(run: Dictionary) -> void:
	Neighbor.state(run).stage = "closed"
	Npcs.state(run).next_day = 100000
	Crisis.state(run).next_warning_day = 100000
	Past.state(run).schedule = []

func _ready() -> void:
	Game.no_save = true
	var recorded: Dictionary = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cycle-ark-recorded.json")))
	check(recorded.result.source == "ark-plan" and recorded.result.reasoning_effort == "low", "Recorded answer lacks actual provider identity")
	check(recorded.result.plan.days.size() == 3 and recorded.result.plan.cycle_plan.size() == 1, "Actual model answer lost event or cycle plan")
	var meta := State.new_meta()
	var previous := State.new_run("herbalist", meta, 719)
	Pre.start_disaster(previous)
	disable_other_local_events(previous)
	previous.home = {"rice": 20}
	at(previous, 2)
	Trade.influence(previous, "zhou", 3, "本世真实往来")
	check(Post.trade_action(previous, "zhou", "credit", str(Trade.quote(previous, "zhou").id)) == "", "Replay could not create actual old debt")
	at(previous, 4, 720)
	Post.trade_refresh(previous)
	previous.phase = "dead"
	check(Past.archive(previous, meta), "Replay could not seal actual breach")
	var run := State.new_run("herbalist", meta, 719)
	# Bind only ephemeral session/life IDs to the recorded synthetic game;
	# economics, timing, approved cue and all model text remain byte-for-byte.
	Past.state(run).id = str(recorded.result.plan.cycle_plan[0].case_id).get_slice(":", 1)
	Pre.start_disaster(run)
	disable_other_local_events(run)
	run.home = {"rice": 20, "water": 20, "wood": 10, "firewood": 10, "mugwort": 10}
	at(run, int(recorded.snapshot.current_day))
	var d := Director.state(run)
	d.session = recorded.snapshot.session
	d.revision = int(recorded.snapshot.revision)
	d.enabled = true
	var sent := Director.snapshot(run)
	var c: Dictionary = Cycle.state(run).cases[0]
	check(c.id == recorded.result.plan.cycle_plan[0].case_id, "Replay failed to bind original candidate ID")
	check(Director.validate(recorded.result.plan, int(sent.current_day), sent.state.npc_dialogue, sent.state.cycle_inquiry.planning), "Actual model output failed game-side contract")
	var inventory: Dictionary = run.home.duplicate(true)
	var trade := Trade.context(run).duplicate(true)
	check(Director.accept(run, sent, recorded.result.plan), "Actual model plan was rejected by runtime")
	check(c.stage == "sealed" and c.evidence.is_empty() and c.delivery.is_empty() and run.busy.is_empty() and run.home == inventory and Trade.context(run) == trade, "Model planned cue executed resources, investigation or old debt")
	check(c.publish_day == recorded.result.plan.cycle_plan[0].day and c.cue == recorded.result.plan.cycle_plan[0].cue, "Actual AI scheduling did not buffer exactly")
	check(Cycle.planning(run).slots.is_empty(), "Accepted answer can be postponed by another plan")
	for event in d.queue:
		d.active = event.duplicate(true)
		check(Director.entry(run).text.begins_with("纸鹤捎来"), "Recorded free prose bypassed local old-knowledge guard")
	d.active = {}
	d.enabled = false
	at(run, int(c.publish_day), 119)
	Post.trade_refresh(run)
	check(c.stage == "sealed", "Actual AI cue published before its date")
	run.t += 1
	Post.trade_refresh(run)
	check(c.stage == "lead" and c.evidence.is_empty() and Past.public_memories(run).is_empty(), "Buffered cue failed local timing or manufactured NPC memory/proof")
	check(Post.cycle_action(run, c.id, "inquire", str(Cycle.view(run).token)) == "", "Actual planned cue could not enter local interview")
	Post.advance(run, 30)
	check(c.stage == "interviewed" and c.evidence.is_empty(), "Actual recorded cue skipped verification")
	check(Post.cycle_action(run, c.id, "verify", str(Cycle.view(run).token)) == "", "Recorded cue could not enter actual verification")
	Post.advance(run, 45)
	check(c.stage == "verified" and not c.evidence.is_empty() and run.home.rice == inventory.rice - 1 and c.delivery.is_empty(), "Actual recorded cue did not require paid current-life work")
	print("Cycle recorded ARK replay: %d checks, %d failures; zero network/model calls" % [checks, failures])
	get_tree().quit(1 if failures else 0)
