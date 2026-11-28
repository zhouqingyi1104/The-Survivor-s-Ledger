extends "res://tests/sim_test.gd"
## 复用同一套采购、做饭、出城和守夜策略。从备荒进场，每一日均由 Post.advance 走完。

const ChronicleStory = preload("res://scripts/core/chronicle_story.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const SavePack = preload("res://scripts/core/save_pack.gd")
const CAMPAIGN_SEED := 5000

var answered := {}
var chosen_options := {}
var shifts_started := {}
var prefer_last := false


func _init() -> void:
	Data.ensure()
	balance_active = true
	bot_max_trips = 2
	bot_chores = true
	var days := _journey(true, "scholar", CAMPAIGN_SEED)
	if failures == 0:
		var first_choices := chosen_options.duplicate()
		prefer_last = true
		_journey(true, "escort", CAMPAIGN_SEED + 1)
		check(chosen_options != first_choices, "两位玩家的异选没有落入各自的百日记载")
	if failures == 0:
		_journey(false, "scholar", CAMPAIGN_SEED)
	print("[hundred_days_journey] 百日实走 %d 日，失败 %d 处" % [days, failures])
	quit(0 if days == 100 and failures == 0 else 1)


func _journey(long_story: bool, role: String, seed_value: int) -> int:
	answered.clear()
	chosen_options.clear()
	shifts_started.clear()
	var run := State.new_run(role, State.new_meta(), seed_value, "normal", [], [], [], long_story)
	shop_pre(run)
	check(run.phase == "post" and int(run.pday) == 1, "备荒采购未抵达灾后第一日")
	var completed := 0
	var goal_days := 100 if long_story else 20
	var save_chapters := long_story and not prefer_last and "--save-chapters" in OS.get_cmdline_user_args()
	var sampled_chapters := {}
	while run.phase == "post" and completed < goal_days and failures == 0:
		var day := int(run.pday)
		check(day == completed + 1, "昼夜断档：上回走完 %d 日，现在第 %d 日" % [completed, day])
		if long_story:
			if save_chapters:
				var chapter := ChronicleStory.chapter(run)
				var letter := ChronicleStory.current_event(run)
				if day in [1, 21, 41, 61, 81, 100]:
					_save_chapter(run, "day-%03d" % day)
				if not letter.is_empty() and not sampled_chapters.has(chapter.id):
					_save_chapter(run, "chapter-%d" % (sampled_chapters.size() + 1))
					sampled_chapters[chapter.id] = true
			_read_today(run)
			if day in [26, 73]:
				run = _reload(run)
		else:
			check(ChronicleStory.current_event(run).is_empty(), "二十日短卷意外派发百日来访")
		if failures != 0: break
		play_day(run)
		check(run.phase != "dead", "%s寻常年景第 %d 日身死：%s" % [State.role(run).name, day, run.death_cause])
		check(int(run.t) == day * Post.DAY, "第 %d 日没有从卯时走到次日卯时：时钟 %d" % [day, int(run.t)])
		if failures != 0: break
		completed += 1
		if completed < goal_days:
			check(run.phase == "post" and int(run.pday) == day + 1, "第 %d 日提前结局或未翻页" % day)
	check(run.phase == "ending", "预期第 %d 夜后合卷，实际局面 %s" % [goal_days, run.phase])
	check(Mainline.ending(run).get("kind", "") == ("hundred_days" if long_story else "hold"), "末章结局与模式不符")
	if long_story and failures == 0:
		if save_chapters:
			_save_chapter(run, "day-100-ending")
		var total: int = Data.table("hundred_days").events.size()
		check(answered.size() == total, "剧情实际选择 %d/%d 件" % [answered.size(), total])
		check(answered.values().has(100), "百日当天没有走完收尾故事")
		check(run.hundred_days.choices == chosen_options, "玩家所选与角色存档记载不符")
		print("寻常年景，%s，种子 %d：实走 %d 日，完成 %d 件剧情，街坊当值 %d 种，守住 %d 次尸潮，终局气血 %d。" % [
			State.role(run).name, seed_value, completed, answered.size(), shifts_started.size(),
			run.waves_survived, int(State.attr(run, "hp"))])
	return completed


func choose_action(run: Dictionary) -> bool:
	for id in ChronicleStory.SHIFTS:
		if not shifts_started.has(id) and ChronicleStory.unlocked(run, id) and Post.street_shift(run, id) == "":
			shifts_started[id] = int(run.pday)
			return true
	return super.choose_action(run)


func _read_today(run: Dictionary) -> void:
	var event := ChronicleStory.current_event(run)
	if event.is_empty(): return
	var id := str(event.id)
	check(not answered.has(id), "跨日复发了已经办完的来访 " + id)
	var options: Array = event.options.duplicate()
	if prefer_last: options.reverse()
	for option in options:
		# 就着现有粮水办事；手头缺料时选无需出资的一条。
		if not Inv.has_all(run.home, option.get("cost", {})): continue
		var why := ChronicleStory.decide(run, id, str(option.id))
		check(why == "", "可承担的来访未能落定：%s / %s" % [id, why])
		if why == "":
			answered[id] = int(run.pday)
			chosen_options[id] = str(option.id)
		return
	check(false, "来访缺乏可承担的选择 " + id)


func _reload(run: Dictionary) -> Dictionary:
	var data := {"run": run, "snapshots": {}}
	var parsed := SavePack.parse(SavePack.to_text(SavePack.pack(data, "journey-test", "local")))
	check(parsed.get("ok", false), "游玩中的百日卷无法导入：" + str(parsed.get("note", "")))
	if not parsed.get("ok", false): return run
	var restored: Dictionary = parsed.data.run
	check(int(restored.pday) == int(run.pday) and int(restored.t) == int(run.t), "读档后时钟改变")
	check(ChronicleStory.journal(restored) == ChronicleStory.journal(run), "读档后玩家已经历的故事改变")
	return restored


## 按需把实走进度留给窗口验证。默认不写文件，导出的仍是玩家能直接导入的卷宗。
func _save_chapter(run: Dictionary, name: String) -> void:
	var folder := "user://hundred-days-preview"
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		check(false, "无法建立章节试玩目录")
		return
	var path := "%s/%s.jyz" % [folder, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "无法保存百日实走进度：" + path)
	if file:
		var envelope := SavePack.pack({"run": run, "snapshots": {}}, str(ProjectSettings.get_setting("application/config/version")), Time.get_datetime_string_from_system())
		file.store_string(SavePack.to_text(envelope))
		file.close()
