extends "res://tests/mainline_rules.gd"

const Chronicle = preload("res://scripts/core/chronicle_story.gd")
const Post = preload("res://scripts/core/post.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Pack = preload("res://scripts/core/save_pack.gd")


func sample() -> Dictionary:
	var run := super.sample()
	run["hundred_days"] = {"choices": {}}
	return run


func answer_available(run: Dictionary) -> void:
	for _entry in Data.table("hundred_days").events:
		var letter := Chronicle.current_event(run)
		if letter.is_empty(): return
		var free_answer := ""
		for option in letter.options:
			if option.get("cost", {}).is_empty():
				free_answer = str(option.id)
				break
		check(free_answer != "" and Chronicle.decide(run, letter.id, free_answer) == "", "存货不足也能回信：" + str(letter.id))
		if free_answer == "": return


func turn_twentieth_page(run: Dictionary, route: String) -> void:
	at(run, 20, 1440)
	run.dawn_due = true
	answer_available(run)
	Post.ack_dawn(run)
	check(run.pday == 21 and run.phase == "post" and run.hundred_days.first_route == route, route + "继续第21日")
	check(Core.ending(run).is_empty() and Ledger.ending_bonus(run) == 0, "第一章不能提前获得通关奖励")


func _ready() -> void:
	Data.ensure()
	var held := routes()
	check(action(held, "hold") == "", "确定坚守")
	turn_twentieth_page(held, "hold")

	var sealed := routes(true)
	at(sealed, 12)
	check(action(sealed, "prepare_ritual") == "" and finish(sealed) != "", "完成法具")
	var spot := visit(sealed, "taoist_temple")
	check(search(sealed, spot).get("started", false) and finish(sealed) != "", "封住阵眼")
	sealed.explore = {}
	turn_twentieth_page(sealed, "ritual")
	check(Defense.wave_for_run(sealed, 40).count < Defense.wave_for_run(held, 40).count, "封阵让后期防线压力降低")

	var escaped := routes()
	at(escaped, 12)
	check(action(escaped, "prepare_escape") == "" and finish(escaped) != "", "搭好渡船")
	at(escaped, 18)
	check(action(escaped, "escape") == "", "带街坊撤离")
	escaped.t = escaped.busy.end
	Post._check_busy(escaped)
	check(escaped.phase == "post" and escaped.pday == 21 and escaped.t == 20 * Post.DAY and escaped.hundred_days.first_route == "escape", "船队避过残潮后接到第21日同一座城")
	check(escaped.waves_survived == 0 and Ledger.ending_bonus(escaped) == 0, "跳过的夜战没有凭空计功")
	check(not Chronicle.current_event(escaped).is_empty(), "护送期间积下的街坊来信可以补办")
	var snapshot := Past.mainline_snapshot(escaped.mainline)
	check(snapshot.interventions.get("escape_t") == 17 * 1440 + 240, "船队有实际出城时刻")

	at(held, 100, 0)
	check(not Core.finish_dawn(held), "百日一早不可提前结案")
	at(held, 100, 1440)
	held.dawn_due = true
	Post.ack_dawn(held)
	check(held.dawn_due and held.phase == "post", "漏回的末封信在结案前能补办")
	answer_available(held)
	var last: Dictionary = Chronicle.journal(held).back()
	Post.ack_dawn(held)
	var ending := Core.ending(held)
	check(held.phase == "ending" and ending.kind == "hundred_days" and str(ending.text).contains(last.result), "末封信的实际回文进入百日结局")
	check(Ledger.ending_bonus(held) == 10 and Past.mainline_snapshot(held.mainline).ending.kind == "hundred_days", "百日结案可写入前世档案")
	check(State.weather(held).cold == 0 and Defense.wave_for_run(held, 101).is_empty(), "谷雨回暖，百日后不排故事夜战")
	check(Defense.leak_damage(100, held) == Defense.leak_damage(20), "百日夜战没有套用无尽破墙强度")

	var old := State.new_run("scholar", State.new_meta(), 123)
	old.version = 21
	var migrated := Migrate.save({"run": old, "snapshots": {"1": old.duplicate(true)}})
	check(migrated.run.version == 22 and not migrated.run.has("hundred_days") and not migrated.snapshots["1"].has("hundred_days"), "旧卷及快照升级后仍为二十日")
	var corrupt := held.duplicate(true)
	corrupt.hundred_days.choices = []
	check(not Pack.validate_data({"run": held, "snapshots": {"21": corrupt}}).ok, "损坏的百日回溯档在导入时拦截")
	print("[hundred_days_rules] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
