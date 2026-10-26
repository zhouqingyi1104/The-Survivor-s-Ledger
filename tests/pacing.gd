extends SceneTree
## 节奏规则测试：时间流速表、「等一刻」能跳到哪、什么时候不该跳。
## 运行：godot --headless --path . --script res://tests/pacing.gd
##
## 这批的出发点是量出来的：一局二十天里，醒着的约 850 分钟有 600 多分钟"没该做的事"，
## 1x 下一天要 6 分钟真实时间。所以给「等一刻」——只跳到节点，不跳过夜战轮次与事件。
## 这里的断言盯三件事：跳得对、不该跳时不跳、流速数值与文档一致。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_rate_table()
	test_next_stop()
	test_refuses_when_busy()
	test_waits_land_on_node()
	test_night_round()
	print("[pacing] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、流速表 ----------

func test_rate_table() -> void:
	# 三档：4 / 10 / 24 游戏分钟每秒。改了这几个数就得同步 docs/27。
	check(Post.SPEEDS == [0.0, 4.0, 10.0, 24.0], "流速表变了：%s" % str(Post.SPEEDS))
	check(Post.rate(_run(), 0) == 0.0, "暂停档还在走时间")
	check(Post.rate(_run(), 1) == 4.0, "1x 不是 4 分钟/秒")
	check(Post.rate(_run(), 2) == 10.0, "2x 不是 10 分钟/秒")
	check(Post.rate(_run(), 3) == 24.0, "3x 不是 24 分钟/秒")
	# 越界档位夹紧，别让坏设置把时间跑飞
	check(Post.rate(_run(), 9) == 24.0, "超出档位没夹到 3x")
	check(Post.rate(_run(), -3) == 0.0, "负档位没夹到暂停")

	# 睡着：一路滑到天亮；做事：至少 BUSY_RATE（做一件事只用等一两秒）
	var sleeping := _run()
	sleeping.sleeping = true
	check(Post.rate(sleeping, 1) == Post.SLEEP_RATE, "睡眠没走快档")
	var busy := _run()
	busy.busy = {"kind": "cook", "label": "做饭", "start": 0, "end": 60}
	check(Post.rate(busy, 1) == Post.BUSY_RATE, "做事时没加速")
	# 做事时不管哪档都走 BUSY_RATE（40 比 3x 的 24 还快）
	check(Post.rate(busy, 3) == Post.BUSY_RATE, "做事时 3x 没被提到 BUSY_RATE")

	# 一天的真实时长：1x 6 分钟、2x 2.4 分钟、3x 1 分钟（1440 分钟 ÷ 每档速度）
	for pair in [[1, 360.0], [2, 144.0], [3, 60.0]]:
		var secs := 1440.0 / Post.rate(_run(), int(pair[0]))
		check(absf(secs - float(pair[1])) < 0.01, "%dx 一天要 %.0f 秒，不是 %.0f 秒" % [int(pair[0]), secs, float(pair[1])])


# ---------- 二、下个节点在哪 ----------

func test_next_stop() -> void:
	var cases := [
		[0, 120, "06:00 该等到 08:00 的第一桩闲话"],
		[150, 570, "08:30 之后最近的节点是天黑 18:00"],
		[780, 60, "19:00 之后是 20:00 烧炭"],
		[930, 30, "21:30 之后是 22:00 尸潮"],
		[1040, 20, "23:20 之后是 23:40 溃兵"],
		[1380, 60, "05:00 之后是天亮"],
	]
	for c in cases:
		var run := _day()
		run.t = int(c[0])
		check(Post.minutes_to_next_stop(run) == int(c[1]),
			"%s：算出 %d 分钟，应为 %d" % [c[2], Post.minutes_to_next_stop(run), int(c[1])])

	# 正好站在节点上：不该算出 0 分钟原地不动，要算到下一个节点
	var on_node := _day()
	on_node.t = 720
	check(Post.minutes_to_next_stop(on_node) == 120, "站在 18:00 上该算到 20:00 的 120 分钟")


# ---------- 三、不该跳的时候不跳 ----------

func test_refuses_when_busy() -> void:
	var busy := _day()
	busy.busy = {"kind": "cook", "label": "做饭", "start": 0, "end": 60}
	check(Post.minutes_to_next_stop(busy) == 0, "正在做事还在等一刻")

	var sleeping := _day()
	sleeping.sleeping = true
	check(Post.minutes_to_next_stop(sleeping) == 0, "睡着的还在等一刻")

	var event := _day()
	event.pending_event = "some_event"
	check(Post.minutes_to_next_stop(event) == 0, "事件还没处理就跳过去了")

	var dawn := _day()
	dawn.dawn_due = true
	check(Post.minutes_to_next_stop(dawn) == 0, "天亮还没结算就跳过去了")

	var away := _day()
	away.explore = {"point": "pharmacy", "spots": []}
	check(Post.minutes_to_next_stop(away) > 0, "人在外面时也算空档（回来是另一件事）")

	var pre := State.new_run("scholar", State.new_meta(), 20261026)
	check(Post.minutes_to_next_stop(pre) == 0, "备劫阶段不该有等一刻")


# ---------- 四、跳完真的落在节点上 ----------

func test_waits_land_on_node() -> void:
	# 06:00 起等一刻：8:00 有个事件检查点，跳完应停在 8:00（或更早，如果先出了事）
	var run := _day()
	var mins := Post.minutes_to_next_stop(run)
	Post.advance(run, mins)
	check(int(run.t) <= 120, "从 06:00 等一刻冲过了 08:00：停在 %d" % int(run.t))
	check(int(run.t) >= 110 or not run.pending_event.is_empty(), "06:00 等一刻没停在 08:00 附近：%d" % int(run.t))

	# 跳过上午的琐事之后，18:00 天黑是下一个节点，跳完必定在天黑
	var run2 := _day()
	run2.t = 200
	run2.busy = {}
	run2.pending_event = ""
	Post.advance(run2, Post.minutes_to_next_stop(run2))
	check(int(run2.t) >= 710, "从 10:20 等一刻没走到天黑：停在 %d" % int(run2.t))
	check(int(run2.t) <= 730, "从天黑又往前多跑了：停在 %d" % int(run2.t))


# ---------- 五、夜战轮次也算节点 ----------

func test_night_round() -> void:
	var run := _day()
	run.t = 960
	run.night = {"wave": {}, "round": 0, "rounds": 3, "sortie": {}, "done": false}
	var cps: Array = Post.checkpoints(run)
	check(cps.size() == 8, "开夜后检查点应多出夜战轮次：%d 个" % cps.size())
	var next := 99999
	for c in cps:
		if int(c) > 960:
			next = mini(next, int(c))
	check(next > 960, "第一轮结算点不该在开夜之前：%d" % next)
	check(Post.minutes_to_next_stop(run) == next - 960,
		"夜里的等一刻没把下一轮算成节点：%d" % Post.minutes_to_next_stop(run))


# ---------- 小工具 ----------

## 一局刚进劫后、第一日 06:00 的干净局面（没有事件、没有夜战）。
func _day() -> Dictionary:
	var run: Dictionary = State.new_run("scholar", State.new_meta(), 20261026)
	Pre.start_disaster(run)
	# start_disaster 已经把第一日的 pday/t 摆好了；再调 begin_day 会跳到第二日，
	# 之后往 run.t 里写分钟数就会算出负的"当天第几分钟"（踩过一次：1560 分钟）
	run.pday = maxi(1, int(run.pday))
	run.t = (int(run.pday) - 1) * Post.DAY
	run.pending_event = ""
	run.busy = {}
	run.night = {}
	run.fight = {}
	run.wave_due = false
	run.dawn_due = false
	run.wave_report = {}
	run.plan_due = false
	return run


func _run() -> Dictionary:
	return State.new_run("scholar", State.new_meta(), 20261026)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)
