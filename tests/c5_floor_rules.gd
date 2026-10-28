extends Node
const Floors = preload("res://scripts/core/home_floor.gd")
const Home = preload("res://scripts/core/home.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)
func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 109)
	run.phase = "post"
	run.pday = 1
	run.t = 200
	run.today["actions"] = []
	run.home = {"wood": 10, "nails": 5}
	check(Floors.current(run) == "courtyard" and not Floors.unlocked(run, "cellar"), "legacy default")
	var before := run.duplicate(true)
	check(Post.change_floor(run, "cellar") != "" and run == before, "cellar requires facility and failure atomic")
	run.facilities.append("cellar")
	before = run.duplicate(true)
	check(Post.change_floor(run, "cellar") == "" and Floors.current(run) == "cellar" and run.home == before.home and run.facilities == before.facilities, "existing cellar enters free")
	var cold_ground := run.duplicate(true)
	var cold_below := run.duplicate(true)
	cold_ground.home_floor = "courtyard"
	Post._tick(cold_ground, 1.0)
	Post._tick(cold_below, 1.0)
	check(cold_ground.attrs.warmth == cold_below.attrs.warmth, "floor does not stack facility warmth")
	check(Post.change_floor(run, "courtyard") == "", "return")
	var poor := run.duplicate(true)
	poor.home.nails = 3
	before = poor.duplicate(true)
	check(Post.act_attic(poor) != "" and poor == before, "insufficient materials atomic")
	var snaps := {}
	run.rebirths_left = 1
	Ledger.snapshot(run, snaps)
	check(Post.act_attic(run) == "" and Floors.attic_stage(run) == "ready" and int(run.home.wood) == 2 and int(run.home.nails) == 1, "one payment")
	check(Post.act_attic(run) == "" and run.busy.kind == "attic_build", "construction started")
	check(Post.change_floor(run, "cellar") != "" and Post.act_attic(run) != "", "busy blocks changes and duplicate")
	Post.advance(run, 30)
	var path := "user://c5-floor-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(path, {"run": run, "snapshots": snaps})
	var loaded := SaveFile.read(path)
	check(bool(saved.ok) and loaded.source == "main" and int(loaded.data.run.busy.end) - int(loaded.data.run.t) == 90, "mid construction persists")
	run = loaded.data.run
	Post.start_fight(run, 1, false)
	check(run.busy.is_empty() and Floors.attic_stage(run) == "ready" and int(run.home.wood) == 2, "fight interrupts but retains materials")
	run.fight = {}
	check(Post.act_attic(run) == "" and int(run.home.wood) == 2, "resume without repaying")
	Post.advance(run, 119)
	check(not Floors.unlocked(run, "attic"), "no early completion")
	Post.advance(run, 1)
	check(Floors.unlocked(run, "attic") and Post.act_attic(run) != "", "complete once")
	check(Post.change_floor(run, "attic") == "" and Floors.current(run) == "attic", "enter attic")
	var loaded_floor := Migrate.upgrade(run.duplicate(true))
	check(Floors.current(loaded_floor) == "attic", "saved valid floor restored")
	loaded_floor.attic = {}
	check(Floors.current(Migrate.upgrade(loaded_floor)) == "courtyard", "invalid floor returns safely")
	run.pday = 2
	var rewound := Ledger.rewind(run, snaps, State.new_meta())
	check(Floors.current(rewound) == "courtyard" and Floors.attic_stage(rewound) == "unprepared" and int(rewound.home.wood) == 10, "rewind earlier resources and floor")
	var raid := run.duplicate(true)
	raid.pday = 1
	raid.t = Post.RAID_AT - 1
	raid.raid_tonight = true
	raid.home_floor = "cellar"
	check(Post.advance(raid, 1) == "raid" and Floors.current(raid) == "courtyard", "raid forces return while time advances")
	var wave := run.duplicate(true)
	wave.pday = 2
	wave.t = (wave.pday - 1) * Post.DAY + Post.WAVE_AT - 1
	wave.wave_day = 0
	wave.home_floor = "attic"
	var wave_stop := Post._checkpoint(wave, Post.WAVE_AT)
	check(wave_stop == "wave" and Floors.current(wave) == "courtyard", "wave forces return")
	var room := run.duplicate(true)
	room.home_floor = "cellar"
	room.furniture = []
	var chair := Home.add(room, "armchair", -2.0, 0.0, 0)
	check(chair.floor == "cellar" and Home.spot_block(room, "armchair", -2.0, 0.0, 0) != "", "same floor blocks overlap")
	room.home_floor = "attic"
	check(Home.spot_block(room, "armchair", -2.0, 0.0, 0) == "", "different floors do not collide")
	check(Home.spot_block(room, "armchair", 0.0, 0.0, 0) != "", "room exit stays clear")
	before = room.duplicate(true)
	check(Post.act_unfurnish(room, int(chair.uid)) != "" and room == before and Home.move_block(room, int(chair.uid)) != "", "cannot remove or move other floor")
	var legacy := {"furniture": [{"uid": 7, "id": "bed", "x": -4, "z": -7, "rot": 0}]}
	check(not Home.core(legacy, "bed").is_empty(), "legacy furniture belongs to courtyard")
	Migrate.upgrade(legacy)
	check(legacy.furniture[0].floor == "courtyard", "legacy furniture migration labels floor")
	check(Post.change_floor(room, "cellar") != "", "rooms require courtyard return")
	var night_plain := run.duplicate(true)
	night_plain.pday = 1
	night_plain.t = Post.DUSK_AT + 1
	night_plain.home_floor = "courtyard"
	night_plain.facilities = []
	night_plain.heated = false
	night_plain.powered = false
	night_plain.attrs.warmth = 50.0
	var night_cellar := night_plain.duplicate(true)
	night_cellar.facilities = ["cellar"]
	var night_inside := night_cellar.duplicate(true)
	night_inside.home_floor = "cellar"
	Post._tick(night_plain, 1.0)
	Post._tick(night_cellar, 1.0)
	Post._tick(night_inside, 1.0)
	check(is_equal_approx(float(night_plain.attrs.warmth), 49.0) and is_equal_approx(float(night_cellar.attrs.warmth), 49.5) and night_cellar.attrs.warmth == night_inside.attrs.warmth, "one existing night cold reduction")
	var day_plain := night_plain.duplicate(true)
	day_plain.t = 200
	day_plain.attrs.warmth = 74.0
	var day_cellar := day_plain.duplicate(true)
	day_cellar.facilities = ["cellar"]
	Post._tick(day_plain, 1.0)
	Post._tick(day_cellar, 1.0)
	check(day_plain.attrs.warmth == 60.0 and day_cellar.attrs.warmth == 75.0, "existing daytime cap unchanged")
	var raid_plain := run.duplicate(true)
	raid_plain.facilities = []
	raid_plain.door.cur = 0
	raid_plain.home = {"rice": 100}
	raid_plain.prof.guard = 0
	var raid_cellar := raid_plain.duplicate(true)
	raid_cellar.facilities = ["cellar"]
	var raid_inside := raid_cellar.duplicate(true)
	raid_inside.home_floor = "cellar"
	var theft_plain := Defense.resolve_raid(raid_plain)
	var theft_cellar := Defense.resolve_raid(raid_cellar)
	var theft_inside := Defense.resolve_raid(raid_inside)
	check(int(theft_plain.stolen.get("rice", 0)) == 30 and int(theft_cellar.stolen.get("rice", 0)) == 15 and theft_cellar.stolen == theft_inside.stolen, "existing raid loss reduction once")
	# Drive a real 23:40 checkpoint while furniture is being installed in the cellar.
	var installing := raid.duplicate(true)
	installing.raid_tonight = true
	installing.t = Post.RAID_AT - 1
	installing.home_floor = "cellar"
	installing.furniture = []
	installing.home = {"wood": 10}
	installing.busy = {}
	check(Post.act_furnish(installing, "armchair", -2.0, 0.0, 0) == "" and int(installing.home.wood) == 8, "cellar installation prepaid")
	check(Post.advance(installing, 1) == "raid" and Floors.current(installing) == "courtyard" and installing.busy.is_empty() and int(installing.home.wood) == 10 and installing.furniture.is_empty(), "raid interrupts room installation and refunds")
	Post._interrupt_room_work(installing)
	Post._check_busy(installing)
	check(int(installing.home.wood) == 10 and installing.furniture.is_empty(), "interruption cannot refund or finish twice")
	# A non-prepaid action must not be completed or spuriously grant materials.
	var reading := raid.duplicate(true)
	reading.raid_tonight = true
	reading.t = Post.RAID_AT - 1
	reading.home_floor = "cellar"
	reading.home = {"wood": 9}
	reading.busy = {"kind": "read", "label": "读书", "start": reading.t, "end": int(reading.t) + 30, "data": {"book": "test"}}
	var read_before: Array = reading.read.duplicate(true)
	check(Post.advance(reading, 1) == "raid" and reading.busy.is_empty() and reading.read == read_before and int(reading.home.wood) == 9, "raid interrupts unpaid work without completion or invented refund")
	Post._check_busy(reading)
	check(reading.read == read_before and int(reading.home.wood) == 9, "interrupted work cannot complete later")
	var identity_run := raid.duplicate(true)
	identity_run.raid_tonight = true
	identity_run.t = Post.RAID_AT - 1
	identity_run.home_floor = "cellar"
	var identity_state := Identity.state(identity_run)
	identity_state.work = {"id": "test-work", "action": "scholar_collate", "label": "校勘", "end_t": identity_run.t + 30}
	identity_run.busy = {"kind": "identity", "label": "校勘", "start": identity_run.t, "end": identity_run.t + 30, "data": {"id": "test-work", "action": "scholar_collate"}}
	check(Post.advance(identity_run, 1) == "raid" and identity_run.busy.is_empty() and identity_state.work.is_empty() and identity_state.chosen == "", "raid reconciles interrupted identity work without benefit")
	SaveFile.forget(path)
	print("[C5_FLOOR_RULES] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
