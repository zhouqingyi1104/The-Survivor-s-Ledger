extends RefCounted
## 截图用的演示场景：把 Game 直接摆到某个状态。只在命令行带 --demo=xxx 时用，不碰玩家存档。

const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")


static func setup(scene: String) -> void:
	match scene:
		"title", "credits":
			Game.meta.runs = 2
			Game.meta.best_day = 14
			Game.meta.daoxin = 23
			Game.go("title")
		"roles":
			Game.go("roles")
		"talents":
			Game.meta.daoxin = 40
			Game.meta.talents = ["tuna", "lingjue"]
			Game.go("talents")
		"pre":
			Game.new_game("scholar")
			var run: Dictionary = Game.run
			Pre.travel(run, "builder")
			Pre.order(run, "door_bar")
			Pre.travel(run, "rice_shop")
			Pre.buy(run, "rice", 2)
			Pre.buy(run, "flatbread", 4)
			Game.act(func(): return "")
		"crowd":
			Game.new_game("scholar")
			var run: Dictionary = Game.run
			Pre.end_day(run)
			Pre.end_day(run)
			Pre.travel(run, "market")
			Game.act(func(): return "")
		"sleep":
			_to_post()
			var run: Dictionary = Game.run
			run.pending_event = ""
			run.t = int(run.t) + 14 * 60 + 30
			Post.sleep(run)
			Game.act(func(): return "")
		"post", "cook", "garden", "build", "omens", "inventory", "explore_pick", "menu", "closeup", "hall", "kitchen", "settings":
			_to_post()
			var run: Dictionary = Game.run
			Post.plant(run, 0, "radish")
			Post.plant(run, 1, "cabbage")
			run.plots[0].days = 2.6
			run.t = int(run.t) + 9 * 60 + 40
			Post.act_cook(run, "congee")
			run.t = int(run.t) + 25
			run.merit = 12
			Game.act(func(): return "")
			match scene:
				"cook":
					Dialogs.cook()
				"garden":
					Dialogs.garden()
				"build":
					Dialogs.build()
				"omens":
					Dialogs.omens()
				"inventory":
					Dialogs.inventory()
				"settings":
					Dialogs.settings(true)
				"explore_pick":
					run.busy = {}
					Dialogs.explore_pick()
		"explore":
			_to_post()
			var run: Dictionary = Game.run
			Post.act_explore(run, "rice_ruin")
			Post.search(run, 0)
			Post.search(run, 1)
			Game.act(func(): return "")
		"plan":
			_to_post()
			var run: Dictionary = Game.run
			run.pday = 14
			run.t = (int(run.pday) - 1) * Post.DAY + Post.CURFEW_AT - 20
			run.sleeping = false
			run.pending_event = ""
			run.plan_due = true
			Game.act(func(): return "")
			Dialogs.night_plan()
		"night_panel":
			_to_post()
			var run: Dictionary = Game.run
			run.pday = 14
			run.t = (int(run.pday) - 1) * Post.DAY + Post.WAVE_AT
			run.sleeping = false
			run.pending_event = ""
			run.plan_due = true
			Post.choose_policy(run, "manual")
			run.wave_due = true
			Post.resolve_wave(run)
			run.wave_report = {}
			Game.act(func(): return "")
			Dialogs.night_panel()
		"gate_fight":
			_to_post()
			var run: Dictionary = Game.run
			run.pday = 14
			run.t = (int(run.pday) - 1) * Post.DAY + Post.WAVE_AT
			run.sleeping = false
			run.pending_event = ""
			run.door_open = true
			run.plan_due = true
			Post.choose_policy(run, "manual")
			run.wave_due = true
			Post.resolve_wave(run)
			run.wave_report = {}
			for k in 110:
				NightFight.step(run.fight, 0.05, 0.0, 4.2, true)
			Game.act(func(): return "")
		"event":
			_to_post()
			Game.run.pending_event = "taoist"
			Game.act(func(): return "")
		"wave", "wave_blood", "night", "dawn":
			_to_post()
			var run: Dictionary = Game.run
			if scene == "wave_blood":
				run.pday = 19
			if run.dawn_due:
				Post.ack_dawn(run)
			else:
				Post.begin_day(run)
			run.pending_event = ""
			Inv.add_all(run.home, {"talisman": 3, "glutinous": 1, "wood": 4, "nails": 2, "caltrops": 1})
			for dev in ["peach_stake", "talisman_wall", "rice_scatter", "caltrop_field"]:
				run.busy = {}
				Post.act_build(run, dev)
			run.busy = {}
			match scene:
				"night":
					run.t = int(run.t) + 14 * 60 + 30
				"dawn":
					run.t = int(run.t) + Post.DAY - 30
					Post.advance(run, 40)
				_:
					run.t = int(run.t) + Post.WAVE_AT
					run.wave_due = true
			Game.act(func(): return "")
		"dead":
			_to_post()
			var run: Dictionary = Game.run
			Ledger.snapshot(run, Game.snapshots)
			run.attrs.hp = 0
			State.check_death(run, "尸潮破门，死在第 %d 夜。" % run.pday)
			Game.act(func(): return "")
		"ending":
			_to_post()
			var run: Dictionary = Game.run
			run.pday = 20
			run.waves_survived = 7
			run.kills = 156
			run.phase = "ending"
			Game.act(func(): return "")


## 界面建好以后再做的事（比如入夜演出、在宅院里走到某处）。
static func after_screen(scene: String, screen: Node) -> void:
	match scene:
		"credits":
			screen._show_credits()
		"night":
			screen.player.position = Vector3(-1.5, 0, 1.0)
		"post":
			screen.player.position = Vector3(-6.6, 0, -1.6)
		"sleep":
			screen.rig.goto(Vector3(-2.2, 2.6, -4.6), Vector3(-4.0, 0.4, -7.25))
			screen.rig.cam.global_position = Vector3(-2.2, 2.6, -4.6)
		"hall":
			screen.player.position = Vector3(-0.8, 0, -5.4)
			screen.rig.dist = 8.0
			screen.rig.pitch = -32.0
			screen.rig.snap()
		"kitchen":
			screen.player.position = Vector3(-7.4, 0, 0.0)
			screen.rig.dist = 7.0
			screen.rig.pitch = -38.0
			screen.rig.yaw = -0.9
			screen.rig.snap()
		"closeup":
			screen.player.position = Vector3(0.5, 0, 0.2)
			screen.player.figure.rotation.y = 0.6
			screen.rig.dist = 6.5
			screen.rig.pitch = -36.0
			screen.rig.snap()
		"menu":
			screen.open_menu("garden", screen.rig.cam.unproject_position(Vector3(3.5, 1.4, 2.3)))
		"gate_fight":
			screen.player.position = Vector3(0, 0, 4.2)
			screen.rig.dist = 12.0
			screen.rig.pitch = -46.0
			screen.rig.snap()


## 按一份像样的采购单买完三日，进入劫中第一日。
static func _to_post() -> void:
	Game.new_game("escort")
	var run: Dictionary = Game.run
	Pre.travel(run, "builder")
	for f in ["door_bar", "water_vat", "stove"]:
		Pre.order(run, f)
	Pre.travel(run, "grocery")
	for pair in [["cart", 1], ["firewood", 6], ["charcoal", 2], ["lamp_oil", 1]]:
		Pre.buy(run, pair[0], pair[1])
	Pre.travel(run, "home")
	Pre.end_day(run)
	Pre.travel(run, "rice_shop")
	for pair in [["rice", 5], ["millet", 2], ["flatbread", 6]]:
		Pre.buy(run, pair[0], pair[1])
	Pre.travel(run, "home")
	Pre.travel(run, "temple")
	for pair in [["glutinous", 1], ["talisman", 3]]:
		Pre.buy(run, pair[0], pair[1])
	Pre.travel(run, "home")
	Pre.end_day(run)
	Pre.travel(run, "market")
	for pair in [["seed_radish", 1], ["seed_cabbage", 1], ["jerky", 1]]:
		Pre.buy(run, pair[0], pair[1])
	Pre.end_day(run)
	Inv.add(run.home, "wood", 3)
	Inv.add(run.home, "nails", 2)
