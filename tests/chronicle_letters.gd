extends SceneTree

const Story = preload("res://scripts/core/chronicle_story.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _init() -> void:
	var book: Dictionary = Data.table("hundred_days")
	var seen := {}
	var previous := 0
	var chapters := {}
	var chapter_for_day := []
	for chapter in book.chapters:
		chapters[chapter.id] = 0
		chapter_for_day.append(chapter.id)
	check(chapters.size() == 5, "缺少章节")
	for event in book.events:
		check(not seen.has(event.id) and int(event.day) > previous and int(event.day) - previous <= 5, "事件日历断档或重复：" + str(event.id))
		previous = int(event.day)
		check(event.chapter == chapter_for_day[(previous - 1) / 20], "事件落在错误的章节：" + str(event.id))
		chapters[event.chapter] += 1
		var options := []
		var free := false
		for option in event.options:
			check(not option.id in options and not str(option.result).is_empty(), "选择重复或没有回音")
			options.append(option.id)
			free = free or option.cost.is_empty()
			for basket in [option.cost, option.gain]:
				for id in basket:
					check(not Data.item(id).is_empty() and int(basket[id]) > 0, "无效物资：" + str(id))
		check(options.size() >= 2 and free, "每封信需要两种办法，至少一种免费")
		if event.has("echo"):
			check(event.echo.choice in seen.get(event.echo.event, []), "回音引用的往日选择不存在：" + str(event.id))
		seen[event.id] = options
	check(previous == 100 and int(book.events.front().day) == 1, "来信没有贯穿百日")
	for count in chapters.values():
		check(count >= 5, "单章内容过少")
	for job in Story.SHIFTS.values():
		check(job.choice in seen.get(job.event, []), "差事无法解锁")
	_test_household()
	print("[chronicle_letters] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_household() -> void:
	var run := State.new_run("scholar", State.new_meta(), 224)
	run.hundred_days = {"choices": {}}
	while run.phase == "pre":
		Pre.end_day(run)
	var event := Story.current_event(run)
	var option := Story.option_for(event, "winch")
	if option.is_empty():
		check(false, "修井选择缺失")
		return
	run.home.clear()
	check(Story.decide(run, event.id, "winch") != "" and run.hundred_days.choices.is_empty(), "物资不足却能修井")
	Inv.add_all(run.home, option.cost)
	check(Story.decide(run, event.id, "winch") == "", "手上有料却不能修井")
	check(run.home == option.gain, "修井的物资账不平")
	var home: Dictionary = run.home.duplicate()
	check(Story.decide(run, event.id, "winch") != "" and run.home == home, "旧信可以再次领物")
	check(Story.unlocked(run, "well") and not Story.unlocked(run, "dock"), "差事解锁错误")
	check(Story.journal(run).size() == 1 and Story.journal(run)[0].result == option.result, "已回的信没有留下原话")
	check(Post.street_shift(run, "well") == "", "井班没有正常开工")
	check(run.home == home and Post.street_shift(run, "well") != "", "开工即给水或可以重复排班")
	var stop := Post.advance(run, int(Story.SHIFTS.well.minutes))
	check(stop == "" and Inv.count(run.home, "water") == Inv.count(home, "water") + 3, "当值没有在完工后分水")
	check(Post.street_shift(run, "well") != "", "当日可以重复当班")
	var branch := run.duplicate(true)
	branch.hundred_days.choices[event.id] = "unknown"
	check(not Story.unlocked(branch, "well"), "另一种答复也解锁了绞盘")
