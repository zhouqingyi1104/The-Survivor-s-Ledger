extends Node
## Explicit developer fixture export. No model calls or player save/meta/Memory I/O.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	var run := State.new_run("escort", State.new_meta(), 824103)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	run.home = {"rice": 12, "wood": 2, "water": 2, "firewood": 0, "nails": 1, "mugwort": 1, "flatbread": 2}
	var snapshot := Director.snapshot(run)
	# Stable request identity makes an explicit rerun recover the same paid response.
	snapshot.session = "crisis-explicit-probe-20261024"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-session="):
			snapshot.session = argument.trim_prefix("--probe-session=")
	snapshot.request_id = "%s-%d-%d" % [snapshot.session, int(snapshot.revision), int(snapshot.current_day)]
	var path := OS.get_environment("TEMP").path_join("ledger-crisis-runtime-snapshot.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write isolated crisis snapshot")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	print("Crisis runtime fixture exported: ", path)
	get_tree().quit(0)
