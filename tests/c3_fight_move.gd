extends Node
const State = preload("res://scripts/core/state.gd")
const Home = preload("res://scripts/core/home.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
var checks := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	var bench := Home.core(run, "bench")
	var planter := Home.add(run, "planter", -4.5, 3.5, 0)
	var uid := int(bench.uid)
	var pot_uid := int(planter.uid)
	check(Home.move_block(run, uid) == "", "bench blocked before fight")
	check(Home.spot_block(run, "bench", 5.25, -5.5, 270, uid) == "", "fixture destination invalid")
	var original := bench.duplicate(true)
	var pot_original := planter.duplicate(true)
	run.fight = NightFight.begin(3, false, run)
	var targets: Array = run.fight.targets.duplicate(true)
	check(Home.move_block(run, uid) != "", "preview allowed during fight")
	check(Home.move(run, uid, 5.25, -5.5, 270) != "", "confirm after fight start allowed")
	check(bench == original, "blocked bench move changed saved state")
	check(run.fight.targets == targets and int(targets[4][5]) == uid and float(targets[4][1]) == float(bench.x) and float(targets[4][2]) == float(bench.z), "blocked move changed or desynchronized target snapshot")
	check(Home.move_block(run, pot_uid) != "", "additional furniture allowed in fight")
	check(Home.move(run, pot_uid, -5.5, 3.5, 90) != "" and planter == pot_original, "additional furniture changed in fight")
	run.fight = {}
	check(Home.move_block(run, uid) == "", "bench blocked after fight")
	check(Home.move(run, uid, 5.25, -5.5, 270) == "", "bench did not move after fight")
	run.broken = ["bench"]
	check(Home.move_block(run, uid) != "" and Home.move(run, uid, 4.5, -5.0, 0) != "", "broken core furniture moved")
	check(Home.move_block(run, -1) != "", "missing furniture accepted")
	print("[C3_FIGHT_MOVE] ", checks - failures, "/", checks, " failed=", failures)
	get_tree().quit(1 if failures else 0)
