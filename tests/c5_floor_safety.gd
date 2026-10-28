extends Node
const Floors = preload("res://scripts/core/home_floor.gd")
const Home = preload("res://scripts/core/home.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)
func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 131)
	run.phase = "post"
	run.pday = 1
	run.t = 250
	run.today.actions = []
	run.facilities = ["cellar"]
	run.attic = {"stage": "complete"}
	run.furniture = []
	run.plots = [{"crop": "", "days": 0.0, "watered_t": 0}]
	run.home = {"wood": 10, "water": 5, "seed_cabbage": 3}
	run.home_floor = "cellar"
	var pot := Home.add(run, "planter", -2.0, 0.0, 0)
	var orphan := {"pot": 999999, "crop": "", "days": 0.0, "watered_t": 0}
	run.plots.append(orphan)
	check(not Post.plot_on_floor(run, run.plots[0]) and Post.plot_on_floor(run, run.plots[1]) and not Post.plot_on_floor(run, orphan), "only same floor and no orphan")
	var before := run.duplicate(true)
	check(Post.sleep(run) != "" and Post.act_rest(run) != "" and Post.plant(run, 0, "cabbage") != "" and Post.plant(run, 2, "cabbage") != "" and run == before, "remote sleep and planting rejected atomically")
	check(Post.plant(run, 1, "cabbage") == "" and run.plots[1].crop == "cabbage" and int(run.home.seed_cabbage) == 2, "local planter planting succeeds")
	run.plots[0].crop = "cabbage"
	run.plots[0].days = 4.0
	run.plots[1].days = 4.0
	run.plots[0].watered_t = 5
	run.plots[1].watered_t = 5
	check(Post.act_garden(run) == "" and Post.advance(run, 45) == "", "local gardening completes through global time")
	check(run.plots[0].crop == "cabbage" and float(run.plots[0].days) >= 4.0 and int(run.plots[0].watered_t) == 5 and run.plots[1].crop == "" and int(run.plots[1].watered_t) == int(run.t), "only current floor harvested and watered")
	check(int(run.home.water) == 4 and int(run.home.cabbage) >= 2, "one local harvest and one water cost")
	run.home_floor = "attic"
	before = run.duplicate(true)
	check(Post.act_garden(run) != "" and run == before, "no remote gardening from empty attic")
	var saved := run.duplicate(true)
	saved.home_floor = "cellar"
	saved.fight = {"foes": []}
	saved.home = {"wood": 8}
	saved.busy = {"kind": "furnish", "label": "安放家具", "start": saved.t, "end": int(saved.t) + 30, "data": {"id": "armchair", "x": -2.0, "z": 0.0, "rot": 0, "floor": "cellar", "paid_cost": {"wood": 2}}}
	var path := "user://c5-load-safety-%d.json" % OS.get_process_id()
	var written := SaveFile.write(path, {"run": saved, "snapshots": {"1": saved.duplicate(true)}})
	var loaded := SaveFile.read(path)
	var upgraded := Migrate.save(loaded.data)
	var restored: Dictionary = upgraded.run
	var snap: Dictionary = upgraded.snapshots["1"]
	check(bool(written.ok) and loaded.source == "main" and Floors.current(restored) == "courtyard" and restored.busy.is_empty() and int(restored.home.wood) == 10, "load during fight returns and interrupts with refund")
	check(Floors.current(snap) == "courtyard" and snap.busy.is_empty() and int(snap.home.wood) == 10, "snapshot receives same safety migration")
	Migrate.upgrade(restored)
	Post._check_busy(restored)
	check(int(restored.home.wood) == 10 and Home.count(restored, "armchair") == 0, "reload cannot duplicate refund or finish")
	var invalid := saved.duplicate(true)
	invalid.fight = {}
	invalid.facilities = []
	Migrate.upgrade(invalid)
	check(Floors.current(invalid) == "courtyard" and invalid.busy.is_empty() and int(invalid.home.wood) == 10, "lost room eligibility interrupts and refunds")
	var sleep_saved := run.duplicate(true)
	sleep_saved.home_floor = "cellar"
	sleep_saved.sleeping = true
	Migrate.upgrade(sleep_saved)
	check(not sleep_saved.sleeping and Floors.current(sleep_saved) == "cellar", "legacy room sleep is stopped")
	SaveFile.forget(path)
	print("[C5_FLOOR_SAFETY] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
