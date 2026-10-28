extends RefCounted
## 唯一正式绑定的西邻：选择和成本由规则层重新校验。
const UI = preload("res://scripts/ui/ui_kit.gd")
const NeighborHome = preload("res://scripts/core/neighbor_home.gd")
const Floors = preload("res://scripts/core/home_floor.gd")


static func open() -> void:
	if Floors.current(Game.run) == "guest_zhou":
		UI.open_modal("neighbor_home", "老周家 · 交谈", _build, true, 700)
	else:
		var result = Game.act(func(): return NeighborHome.knock(Game.run))
		if typeof(result) == TYPE_STRING and result == "":
			UI.open_modal("neighbor_home", "西邻 · 隔墙交谈", _build, true, 700)


static func _when(t: int) -> String:
	var clock := (t + 360) % 1440
	return "第 %d 日 %02d:%02d" % [t / 1440 + 1, clock / 60, clock % 60]


static func _build(body: VBoxContainer) -> void:
	var view: Dictionary = NeighborHome.view(Game.run)
	var opening := "隔墙应声的是木料场老周。他认下西边这户是自己的家。"
	if Floors.current(Game.run) == "guest_zhou":
		opening = "老周在自己家中与你说话。"
	opening += "这处墙已修好。" if bool(view.get("wall_repaired", false)) else "墙上有一处破损，想与你商量如何应对。"
	body.add_child(UI.para(opening, 17))
	if Floors.current(Game.run) == "guest_zhou":
		body.add_child(UI.para("修墙、换物与答复请回宅院隔墙处理；离开时请走门口。", 15, UI.INK_SOFT))
	else:
		body.add_child(UI.para("老周邀请你白天从自家院门前往他家，18:00 前须返家。", 15, UI.INK_SOFT))
	if int(view.get("deadline_t", 0)) > 0 and str(view.get("choice", "")) == "":
		body.add_child(UI.para("答复截止：%s；到点未回应也会有后果。" % _when(int(view.deadline_t)), 16, UI.CINNABAR))
	var result := str(view.get("result", ""))
	if result != "":
		body.add_child(UI.para(result, 16, UI.GOLD))
	if bool(view.get("settled", false)):
		body.add_child(UI.para("这次往来的后果已记入老周的人情与往来记录。", 15, UI.INK_SOFT))
	elif str(view.get("choice", "")) != "":
		body.add_child(UI.para("后续将在 %s 处理；院内时钟照常推进。" % _when(int(view.get("due_t", 0))), 15, UI.INK_SOFT))
	var options: Array = NeighborHome.options(Game.run) if str(view.get("stage", "")) == "open" and Floors.current(Game.run) == "courtyard" else []
	for option in options:
		var reason := str(option.get("block", ""))
		var card := UI.vbox(4)
		card.add_child(UI.para(str(option.get("hint", "")), 15, UI.INK_SOFT))
		if reason != "":
			card.add_child(UI.para(reason, 15, UI.CINNABAR))
		var button := UI.button(str(option.get("text", "")), _choose.bind(str(option.get("id", ""))), reason != "", reason)
		button.set_meta("neighbor_home_action", str(option.get("id", "")))
		card.add_child(button)
		body.add_child(UI.panel(card))


static func _choose(action: String) -> void:
	var result = Game.act(func(): return NeighborHome.act(Game.run, action))
	if typeof(result) == TYPE_STRING and result == "":
		UI.close_modal("neighbor_home")
