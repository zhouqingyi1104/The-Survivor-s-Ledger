extends Node
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Home = preload("res://scripts/core/home.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)

func fresh() -> Dictionary:
	var run := State.new_run("scholar", State.new_meta(), 812)
	run.phase = "post"
	run.pday = 2
	run.t = Post.DAY + 950
	run.today["actions"] = []
	run.home = {"wood": 10, "nails": 4}
	run.expansion = {"stage": "complete"}
	return run

func _ready() -> void:
	Game.no_save = true
	var run := fresh()
	check(Post.act_furnish(run, "armchair", 14, 4, 0) == "" and int(run.home.wood) == 8, "cost deducted once")
	var snapshots := {}
	run.rebirths_left = 1
	Ledger.snapshot(run, snapshots)
	var stop := Post.advance(run, 10)
	check(stop == "wave" and run.busy.is_empty() and int(run.home.wood) == 10 and Home.count(run, "armchair") == 0, "wave interrupts and refunds")
	Post._interrupt_furnish(run)
	check(int(run.home.wood) == 10, "repeat interruption no duplicate refund")
	var rewound := Ledger.rewind(run, snapshots, State.new_meta())
	check(int(rewound.home.wood) == 8 and rewound.busy.kind == "furnish", "rewind restores unpaid in-flight snapshot")
	Post._interrupt_furnish(rewound)
	check(int(rewound.home.wood) == 10 and Home.count(rewound, "armchair") == 0, "rewind interruption cannot duplicate materials")
	var done := fresh()
	done.t = Post.DAY + 500
	check(Post.act_furnish(done, "armchair", 14, 4, 0) == "", "start completed test")
	stop = Post.advance(done, 45)
	if Home.count(done, "armchair") != 1 or int(done.home.wood) != 8:
		print("completion diagnostic: stop=", stop, " t=", done.t, " furniture=", Home.count(done, "armchair"), " wood=", done.home.wood, " busy=", done.busy)
	check(Home.count(done, "armchair") == 1 and int(done.home.wood) == 8, "finished furniture remains paid")
	Post.start_fight(done, 1, false)
	check(Home.count(done, "armchair") == 1 and int(done.home.wood) == 8, "finished furniture not refunded by fight")
	var fight := fresh()
	check(Post.act_furnish(fight, "armchair", 14, 4, 0) == "", "start fight interruption")
	Post.start_fight(fight, 1, false)
	check(fight.busy.is_empty() and int(fight.home.wood) == 10, "direct fight interruption refunded")
	Post._interrupt_furnish(fight)
	check(int(fight.home.wood) == 10, "direct interruption idempotent")
	# 05:50 开始的家具安放跨过天亮，应只退款一次。
	var dawn := fresh()
	dawn.t = Post.DAY * 2 - 10
	check(Post.act_furnish(dawn, "armchair", 14, 4, 0) == "", "start dawn interruption")
	stop = Post.advance(dawn, 10)
	check(stop == "dawn" and dawn.busy.is_empty() and int(dawn.home.wood) == 10 and Home.count(dawn, "armchair") == 0, "dawn interruption refunds")
	check(str(dawn.log[-1]).contains("天亮") or str(dawn.log).contains("天亮打断了家具安放"), "dawn notice names actual reason")
	Post._interrupt_furnish(dawn, "天亮")
	check(int(dawn.home.wood) == 10, "dawn repeat does not refund twice")
	var dawn_done := fresh()
	dawn_done.t = Post.DAY * 2 - 45
	check(Post.act_furnish(dawn_done, "armchair", 14, 4, 0) == "", "start completion at dawn")
	stop = Post.advance(dawn_done, 45)
	check(stop == "dawn" and Home.count(dawn_done, "armchair") == 1 and int(dawn_done.home.wood) == 8, "completion at dawn keeps furniture and cost")
	print("[FURNISH_INTERRUPT] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)
