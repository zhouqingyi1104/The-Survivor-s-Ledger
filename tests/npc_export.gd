extends Node
## Explicit fictional fixture. Never reads player saves, meta or Memory.md.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Director = preload("res://scripts/core/director.gd")
const Npc = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")

func fixture() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 824104)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	run.home = {"rice": 12, "wood": 2, "water": 2, "firewood": 0, "nails": 1, "mugwort": 1, "flatbread": 2}
	Past.state(run).id = "npc-fictional-probe-life"
	Past.state(run).awakenings = [{"actor": "ning", "life": 1, "age": 1, "fact_id": "ning:medicine", "fact": "你前世交过艾草，后续病情尚未确认。", "response": "acknowledge"}]
	Trade.state(run).actors.zhou.trust = -3
	Trade.state(run).actors.traveler.trust = 3
	Npc.state(run)
	Crisis.propose(run, {"kind": "well_freeze", "actor": "ning", "warning_day": 2, "real": false}, 1)
	run.pday = 2
	run.t = 1560
	Crisis.poll(run)
	Npc.poll(run)
	return run

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var run := fixture()
	var snapshot := Director.snapshot(run)
	snapshot.session = "npc-dialogue-explicit-probe-20261024"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-session="): snapshot.session = argument.trim_prefix("--probe-session=")
	snapshot.request_id = "%s-%d-%d" % [snapshot.session, int(snapshot.revision), int(snapshot.current_day)]
	var target := OS.get_environment("TEMP").path_join("ledger-npc-runtime-snapshot.json")
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Could not write isolated NPC fixture snapshot")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	print("NPC runtime fixture exported: ", target)
	get_tree().quit(0)
