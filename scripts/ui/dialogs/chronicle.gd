extends RefCounted

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Story = preload("res://scripts/core/chronicle_story.gd")
const Post = preload("res://scripts/core/post.gd")

static func open() -> void:
	if not Story.enabled(Game.run):
		return
	UI.open_modal("hundred_days", "百日街坊", _fill, true, 720)


static func _fill(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var event := Story.current_event(run)
	var chapter := Story.chapter(run, event)
	body.add_child(UI.label("%s　·　%s" % [chapter.days, chapter.title], 20, UI.GOLD))
	if event.is_empty():
		body.add_child(UI.para(str(chapter.intro), 18))
	else:
		body.add_child(UI.heading(str(event.title), 29))
		body.add_child(UI.label("第 %d 日　%s" % [event.day, event.person], 16, UI.JADE))
		body.add_child(UI.para(str(event.body), 18))
		var callback := Story.echo(run, event)
		if callback != "":
			body.add_child(UI.para(callback, 17, UI.GOLD))
		for option in event.options:
			var caption := str(option.label)
			if not option.cost.is_empty():
				caption += "　·　交" + Data.describe_items(option.cost)
			var reason := Story.reply_block(run, option)
			var b := UI.button(caption, _decide.bind(str(event.id), str(option.id)), reason != "", reason)
			b.set_meta("chronicle_choice", str(option.id))
			body.add_child(b)
	var pages := Story.journal(run)
	if not pages.is_empty():
		var last: Dictionary = pages.back()
		if event.is_empty():
			body.add_child(UI.sep())
			body.add_child(UI.label("第 %d 日回音　·　%s" % [last.day, last.title], 19, UI.JADE))
			body.add_child(UI.para(str(last.result), 17))
		body.add_child(UI.button("翻看旧信（%d）" % pages.size(), _open_archive))
	for id in Story.SHIFTS:
		if Story.unlocked(run, id) and run.get("phase") == "post" and not run.dawn_due:
			var job: Dictionary = Story.SHIFTS[id]
			var reason := Post.street_shift_block(run, id)
			var fee := "" if job.cost.is_empty() else " · 交" + Data.describe_items(job.cost)
			var tip := "完工分得" + Data.describe_items(job.gain) + "，每日可当一班。"
			var b := UI.button("%s · %d 分钟%s" % [job.label, job.minutes, fee], _work.bind(str(id)), reason != "", reason if reason != "" else tip)
			b.set_meta("chronicle_shift", id)
			body.add_child(b)


static func _decide(id: String, choice: String) -> void:
	Game.act(func(): return Story.decide(Game.run, id, choice))


static func _work(id: String) -> void:
	if Game.act(func(): return Post.street_shift(Game.run, id)) == "":
		UI.close_modal("hundred_days")
		UI.close_modal("journal")


static func _open_archive() -> void:
	UI.open_modal("chronicle_archive", "街坊旧信", _archive, true, 720)


static func _archive(body: VBoxContainer) -> void:
	var pages := Story.journal(Game.run)
	pages.reverse()
	var entries := UI.vbox(8)
	for page in pages:
		entries.add_child(UI.heading("第 %d 日　%s" % [page.day, page.title], 21))
		entries.add_child(UI.para("%s　·　%s" % [page.person, page.label], 16, UI.JADE))
		if page.echo != "":
			entries.add_child(UI.para(str(page.echo), 16, UI.GOLD))
		entries.add_child(UI.para(str(page.result), 17))
		entries.add_child(UI.sep())
	body.add_child(UI.scroll(entries, 340))
