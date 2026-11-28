extends RefCounted

const Cases = preload("res://scripts/core/side_cases.gd")
const Data = preload("res://scripts/core/data.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

const STAGES := {"offered": "待应约", "field": "待查访", "returned": "证物已到家", "working": "正在合办", "done": "已办妥"}


static func open(preferred := "") -> void:
	var selection := {"id": preferred}
	UI.open_modal("street_cases", "街坊同行", _fill.bind(selection), true, 850)


static func _fill(body: VBoxContainer, selection: Dictionary) -> void:
	var run: Dictionary = Game.run
	selection["dark"] = UI.dark
	var rows := Cases.list_cases(run)
	if rows.is_empty():
		body.add_child(UI.para("还没有人托你查访。", 18))
		return
	if str(selection.id) == "":
		var active := Cases.active(run)
		selection.id = active.get("id", rows.back().id)
	var spread := UI.hbox(16)
	var index := UI.vbox(4)
	var leaf := UI.vbox(9)
	spread.add_child(UI.fixed_width(UI.scroll(index, 330), 205))
	spread.add_child(UI.expand(UI.scroll(leaf, 330)))
	body.add_child(spread)
	var group := ButtonGroup.new()
	var selected := false
	for entry in rows:
		var b := UI.button("%s　%s" % [str(entry.title), str(STAGES.get(entry.stage, ""))], _select.bind(selection, str(entry.id), leaf))
		b.set_meta("side_case_file", str(entry.id))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.set_pressed_no_signal(entry.id == selection.id)
		index.add_child(b)
		selected = selected or b.button_pressed
	if not selected:
		selection.id = rows[0].id
		(index.get_child(0) as Button).set_pressed_no_signal(true)
	_select(selection, str(selection.id), leaf)


static func _select(selection: Dictionary, id: String, leaf: VBoxContainer) -> void:
	selection.id = id
	UI.clear(leaf)
	var run: Dictionary = Game.run
	var entry := Cases.view(run, id)
	if entry.is_empty():
		return
	var previous_palette := UI.dark
	UI.use_dark(selection.dark)
	var route: Dictionary = entry.route
	leaf.add_child(UI.label("第 %d 日起　·　%s" % [entry.day, entry.person], 16, UI.JADE))
	leaf.add_child(UI.heading(str(entry.title), 26))
	leaf.add_child(UI.para(str(entry.lead), 18))
	if str(route.get("why", "")) != "":
		leaf.add_child(UI.para(str(route.why), 16, UI.GOLD))
	var place: String = Data.table("map_points")[route.site].name
	match str(entry.stage):
		"offered", "field":
			leaf.add_child(UI.para("去%s找「%s」。现场约 %d 分钟，阳气外泄 +%d；去程、返程各 60 分钟。" % [place, route.spot, route.minutes, route.risk], 16))
			if entry.stage == "offered":
				_action(leaf, "答应同行", _accept.bind(id), Cases.accept_block(run, id), "side_case_accept", id)
			else:
				leaf.add_child(UI.button("查看出门地图", _map))
				var block := Cases.abandon_block(run, id)
				_action(leaf, "暂放这件事", _abandon.bind(id), block, "side_case_abandon", id)
		"returned":
			leaf.add_child(UI.para("从%s带回的线索　%s" % [place, route.clue], 17, UI.GOLD))
			if str(entry.get("finding", "")) != "":
				leaf.add_child(UI.para(str(entry.finding), 16, UI.JADE))
			for option in entry.options:
				var caption := "%s · %d 分钟" % [option.label, option.minutes]
				if not option.cost.is_empty():
					caption += " · 交" + Data.describe_items(option.cost)
				_action(leaf, caption, _settle.bind(id, str(option.id)), Cases.settle_block(run, id, str(option.id)), "side_case_finish", str(option.id))
			_action(leaf, "归还证物，暂放这件事", _abandon.bind(id), Cases.abandon_block(run, id), "side_case_abandon", id)
		"working":
			leaf.add_child(UI.para("你和%s正忙着。完工后可以在这里翻看结果。" % run.busy.data.get("person", entry.person), 17, UI.GOLD))
		"done":
			leaf.add_child(UI.label("后来", 19, UI.JADE))
			leaf.add_child(UI.para(str(entry.result), 18))
			if entry.epilogue != "" and entry.epilogue != entry.result:
				leaf.add_child(UI.para(str(entry.epilogue), 16, UI.GOLD))
	UI.use_dark(previous_palette)


static func _action(parent: Container, caption: String, callback: Callable, block: String, key: String, value: String) -> void:
	var button := UI.button(caption, callback, block != "", block)
	button.set_meta(key, value)
	parent.add_child(button)
	if block != "":
		parent.add_child(UI.para(block, 14, UI.INK_SOFT))


static func _accept(id: String) -> void:
	Game.act(func(): return Cases.accept(Game.run, id))


static func _abandon(id: String) -> void:
	var prompt := "街坊会带走已交回的证物。以后再应约，需要重新去现场。"
	if Cases.view(Game.run, id).stage == "field":
		prompt = "把这次约定放下，腾出时间陪别的街坊。以后还可以从头查。"
	Dialogs.confirm("暂放这件事？", prompt, "暂放", func(): Game.act(func(): return Cases.abandon(Game.run, id)))


static func _map() -> void:
	for key in ["street_cases", "hundred_days", "journal"]:
		UI.close_modal(key)
	Dialogs.explore_pick()


static func _settle(id: String, choice_id: String) -> void:
	var screen: Node = UI.host.get("_screen")
	if screen != null and screen.has_method("begin_case_work"):
		for key in ["street_cases", "hundred_days", "journal"]:
			UI.close_modal(key)
		screen.begin_case_work(id, choice_id)
