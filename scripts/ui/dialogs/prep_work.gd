extends RefCounted

const UI = preload("res://scripts/ui/ui_kit.gd")
const Pre = preload("res://scripts/core/pre.gd")


static func open(travel: Callable) -> void:
	UI.open_modal("prep_work", "备荒杂事", _fill.bind(travel), true, 660)


static func _fill(body: VBoxContainer, travel: Callable) -> void:
	body.add_child(UI.para("距宵禁还剩 %d 个时辰。备劫三日里，每件事能做一回。" % maxi(0, Pre.hours_left(Game.run)), 16))
	for place in Pre.PREP_WORK:
		body.add_child(UI.sep())
		add_row(body, place, travel)


## 米行柜台与城内杂事簿共用同一行，实际开工必须到场。
static func add_row(body: VBoxContainer, place: String, travel := Callable()) -> void:
	var run: Dictionary = Game.run
	var work: Dictionary = Pre.PREP_WORK[place]
	var done := Pre.prep_work_done(run, place)
	var away: bool = run.loc != place
	var site := "自家院子" if place == "home" else str(Pre.shop(place).name)
	var row := UI.hbox(12)
	var info := UI.vbox(3)
	var title := "%s · %s" % [site, work.name] if done or away else site
	info.add_child(UI.heading(title, 18))
	info.add_child(UI.para(str(work.result if done else work.description), 16))
	row.add_child(UI.expand(info))
	body.add_child(row)
	if done:
		row.add_child(UI.tag("已做过", UI.JADE))
		return
	var reason := Pre.prep_work_trip_block(run, place)
	var caption := str(work.name)
	var action := _do_work.bind(place)
	var tag := "prep_work_action"
	if away:
		caption = "回家" if place == "home" else "去" + site
		action = travel.bind(place)
		tag = "prep_work_travel"
		info.add_child(UI.label("路上另需约 %d 个时辰" % Pre.travel_cost(run, place), 15, UI.INK_SOFT))
	if reason != "":
		info.add_child(UI.para(reason, 15, UI.CINNABAR))
	var button := UI.button(caption, action, reason != "", reason)
	button.set_meta(tag, place)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)


static func _do_work(place: String) -> void:
	if Game.act(func(): return Pre.do_prep_work(Game.run, place)) == "":
		Game.toast.emit(Pre.PREP_WORK[place].result)
