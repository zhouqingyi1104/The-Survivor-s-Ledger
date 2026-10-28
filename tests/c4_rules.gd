extends Node
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 108)
	run.phase = "post"
	run.pday = 1
	run.t = 200
	run.today["actions"] = []
	run.home = {"wood": 10, "nails": 5}
	check(Expansion.stage(run) == "survey" and not Expansion.complete(run), "legacy default")
	var old := Migrate.upgrade(run.duplicate(true))
	check(Expansion.stage(old) == "survey", "old save remains closed")
	var fighting := run.duplicate(true)
	fighting.fight = {"foes": []}
	var unchanged := fighting.duplicate(true)
	check(Post.act_expansion(fighting) != "" and fighting == unchanged, "fight blocks without mutation")
	var energy := float(run.attrs.energy)
	check(Post.act_expansion(run) == "" and run.busy.kind == "expansion_clear" and float(run.attrs.energy) == energy - 5, "start clear")
	check(Post.act_expansion(run) != "", "repeated click while busy")
	var stop := Post.advance(run, 59)
	check(stop == "" and Expansion.stage(run) == "survey" and not run.busy.is_empty(), "clear cannot finish early")
	stop = Post.advance(run, 1)
	check(stop == "" and Expansion.stage(run) == "cleared" and run.busy.is_empty(), "clear takes 60 minutes")
	var poor := run.duplicate(true)
	poor.home.nails = 3
	var poor_before := poor.duplicate(true)
	check(Post.act_expansion(poor) != "" and poor == poor_before, "insufficient cost atomic")
	var snaps := {}
	run.rebirths_left = 1
	Ledger.snapshot(run, snaps)
	check(Post.act_expansion(run) == "" and Expansion.stage(run) == "ready" and int(run.home.wood) == 2 and int(run.home.nails) == 1, "pay once")
	check(Post.act_expansion(run) == "" and run.busy.kind == "expansion_build", "start build")
	stop = Post.advance(run, 30)
	check(stop == "" and Expansion.stage(run) == "ready" and not Expansion.complete(run), "construction incomplete")
	var path := "user://c4-rules-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(path, {"run": run, "snapshots": snaps})
	var loaded := SaveFile.read(path)
	check(bool(saved.ok) and loaded.source == "main", "save write read")
	run = loaded.data.run
	check(Expansion.stage(run) == "ready" and int(run.busy.end) - int(run.t) == 90, "mid-construction save restores remaining time")
	Post.start_fight(run, 1, false)
	check(run.busy.is_empty() and Expansion.stage(run) == "ready" and int(run.home.wood) == 2 and int(run.home.nails) == 1, "fight interruption retains materials")
	check(Post.act_expansion(run) != "", "cannot resume in fight")
	run.fight = {}
	check(Post.act_expansion(run) == "" and int(run.busy.end) - int(run.t) == 120 and int(run.home.wood) == 2 and int(run.home.nails) == 1, "resume without repaying")
	stop = Post.advance(run, 119)
	check(stop == "" and not Expansion.complete(run), "build cannot finish early")
	stop = Post.advance(run, 1)
	check(stop == "" and Expansion.complete(run) and run.busy.is_empty(), "construction takes 120 minutes")
	check(Post.act_expansion(run) != "" and not Expansion.finish(run, "ready"), "completion cannot repeat")
	run.pday = 2
	var rewound := Ledger.rewind(run, snaps, State.new_meta())
	check(Expansion.stage(rewound) == "cleared" and int(rewound.home.wood) == 10 and int(rewound.home.nails) == 5, "rewind restores unpaid earlier state")
	# 旧院先有家具挡住侧院门洞时，不能施工或误宣布完成。
	var blocked := run.duplicate(true)
	blocked.pday = 1
	blocked.fight = {}
	blocked.busy = {}
	blocked.expansion = {"stage": "ready"}
	blocked["furniture"] = []
	blocked.furniture.append({"uid": 900, "id": "armchair", "x": 9.0, "z": 4.5, "rot": 0})
	var blocked_before := blocked.duplicate(true)
	check(Post.act_expansion(blocked) != "" and blocked == blocked_before, "existing furniture blocks construction atomically")
	blocked.furniture.pop_back()
	check(Post.act_expansion(blocked) == "", "unblocked construction starts")
	blocked.furniture.append({"uid": 901, "id": "armchair", "x": 9.0, "z": 4.5, "rot": 0})
	blocked.t = int(blocked.busy.end)
	Post._check_busy(blocked)
	check(Expansion.stage(blocked) == "ready" and blocked.busy.is_empty(), "final check refuses obstructed entrance")
	SaveFile.forget(path)
	print("[C4_RULES] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
