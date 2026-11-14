extends RefCounted
## 事件卡：来客、邻里、世情各式事件的正文、选项与结果。
##
## 从 dialogs.gd 搬出来（工程债第 1 条第二批）。入口仍是 Dialogs.event()，那个函数只是转发；
## 面板内容与搬之前逐字一致，控件树导出对照过。Dialogs._event_req_text 也留了转发，
## 因为 tests/offline_events_ui.gd 直接调它核「几两几文」的写法。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Events = preload("res://scripts/core/events.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Kit = preload("res://scripts/ui/dialogs/kit.gd")


static func open() -> void:
	var run: Dictionary = Game.run
	UI.open_modal("event", Events.entry(run).get("title", "邻里来信"), _build, false, 720)


static func _build(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	if run.pending_event == "":
		body.add_child(UI.para(run.event_result, 19, UI.INK))
		var row := UI.hbox()
		row.add_child(UI.spacer())
		row.add_child(UI.seal_button("知道了", func(): UI.close_modal("event")))
		body.add_child(row)
		return
	var e: Dictionary = Events.entry(run)
	if e.get("story", "") == "neighbor" and Neighbor.state(run).resolution != "":
		body.add_child(UI.para("前情：" + Neighbor.resolution_text(Neighbor.state(run)), 16, UI.GOLD))
	body.add_child(UI.para(e.text, 19, UI.INK))
	body.add_child(UI.sep())
	for k in e.choices.size():
		var c: Dictionary = e.choices[k]
		var block := Events.choice_block(run, c)
		var ok := block == ""
		var text: String = c.text
		if not c.get("req", {}).is_empty():
			text += "　［需：%s］" % req_text(c.req)
		var b := UI.button(text, func(): Kit.act(func(): return Events.choose(Game.run, k)), not ok, block)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)
		if c.get("hint", "") != "":
			body.add_child(UI.para(c.hint, 15, UI.INK_SOFT))
		if str(run.pending_event).begins_with("world:"):
			body.add_child(UI.para(Director.effect_hint(c), 15, UI.INK_SOFT))
		if c.get("pry", false) and not Neighbor.state(run).pry:
			body.add_child(UI.para("未准备撬杆：须在家中打开劫余录 → 邻里事务，用木料 1 制作。", 15, UI.CINNABAR))


static func req_text(req: Dictionary) -> String:
	var parts := []
	for k in req:
		match k:
			"any_food":
				parts.append("吃食 %d 份" % req[k])
			"any_grain":
				parts.append("粮 %d 斗" % req[k])
			"silver":
				var wen := int(req[k])
				var liang := wen / 1000
				var remainder := wen % 1000
				parts.append("%d 文" % wen if liang == 0 else ("%d 两" % liang if remainder == 0 else "%d 两 %d 文" % [liang, remainder]))
			_:
				parts.append("%s %d" % [Data.item_name(k), req[k]])
	return "、".join(parts)
