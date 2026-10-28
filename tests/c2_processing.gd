extends Node

const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 3117)
	Home.ensure_layout(run)
	run.t = 200
	Inv.add(run.home, "cabbage", 3)
	Inv.add(run.home, "salt", 1)
	Inv.add(run.home, "rat", 2)
	Inv.add(run.home, "firewood", 1)
	var jar := Home.add(run, "pickle_jar", -4.0, 3.0, 0)
	var rack := Home.add(run, "smoke_rack", 4.0, -1.0, 0)
	var jar_uid := int(jar.uid)
	var rack_uid := int(rack.uid)
	check(Home.pickle(run, jar_uid, "cabbage", 3) == "", "pickle job could not start")
	check(Home.smoke(run, rack_uid, "rat", 2) == "", "smoke job could not start")
	var jar_job: Dictionary = jar.job.duplicate(true)
	var rack_job: Dictionary = rack.job.duplicate(true)
	var inventory := JSON.stringify(run.home)
	check(Home.move(run, jar_uid, -4.5, 1.0, 90) == "", "jar move failed")
	check(Home.move(run, rack_uid, 4.5, 4.5, 90) == "", "rack move failed")
	check(int(Home.find(run, jar_uid).uid) == jar_uid and Home.find(run, jar_uid).job == jar_job, "jar identity or job changed")
	check(int(Home.find(run, rack_uid).uid) == rack_uid and Home.find(run, rack_uid).job == rack_job, "rack identity or job changed")
	check(JSON.stringify(run.home) == inventory, "move changed inventory")
	check(int(jar.job.done_t) == 200 + 2 * Home.DAY and int(rack.job.done_t) == 200 + Home.DAY, "completion time changed")
	var path := "user://c2-processing-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(path, {"run": run, "snapshots": {}})
	check(bool(saved.ok), "save write failed")
	var loaded := SaveFile.read(path)
	check(not loaded.data.is_empty(), "save read failed")
	if loaded.data.is_empty():
		SaveFile.forget(path)
		_finish()
		return
	run = loaded.data.run
	jar = Home.find(run, jar_uid)
	rack = Home.find(run, rack_uid)
	check(not jar.is_empty() and int(jar.uid) == jar_uid and int(jar.job.done_t) == int(jar_job.done_t) and int(jar.job["in"].cabbage) == 3 and int(jar.job.out.pickles) == 3, "jar job did not survive save")
	check(not rack.is_empty() and int(rack.uid) == rack_uid and int(rack.job.done_t) == int(rack_job.done_t) and int(rack.job["in"].rat) == 2 and int(rack.job.out.smoked_rat) == 2, "rack job did not survive save")
	check(int(jar.rot) == 90 and int(rack.rot) == 90 and absf(float(jar.x) + 4.5) < 0.01 and absf(float(rack.x) - 4.5) < 0.01, "position did not survive save")
	var pickles_before := Inv.count(run.home, "pickles")
	var smoked_before := Inv.count(run.home, "smoked_rat")
	run.t = int(rack_job.done_t) - 1
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before and Inv.count(run.home, "smoked_rat") == smoked_before, "early processing payout")
	run.t = int(rack_job.done_t)
	Home.dawn(run)
	check(Inv.count(run.home, "smoked_rat") == smoked_before + 2 and Inv.count(run.home, "pickles") == pickles_before, "smoke completion wrong")
	check(Home.find(run, rack_uid).job.is_empty() and not Home.find(run, jar_uid).job.is_empty(), "completion cleared wrong jobs")
	Home.dawn(run)
	check(Inv.count(run.home, "smoked_rat") == smoked_before + 2, "duplicate smoked payout")
	run.t = int(jar_job.done_t)
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before + 3, "pickle completion wrong")
	Home.dawn(run)
	check(Inv.count(run.home, "pickles") == pickles_before + 3 and Inv.count(run.home, "smoked_rat") == smoked_before + 2, "duplicate processing payout")
	check(Home.find(run, jar_uid).job.is_empty(), "completed jar job not cleared")
	SaveFile.forget(path)
	_finish()

func _finish() -> void:
	print("[C2_PROCESSING] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
