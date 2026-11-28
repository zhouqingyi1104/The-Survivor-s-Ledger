extends RefCounted

const UI = preload("res://scripts/ui/ui_kit.gd")
const Story = preload("res://scripts/core/apothecary_story.gd")


static func shop_entry(body: VBoxContainer) -> void:
	if Story.stage(Game.run) == "":
		var row := UI.hbox(10)
		row.add_child(UI.expand(UI.para("柜脚垫着个空药包，纸角有半道朱印。", 16)))
		_action(row, "unfold", "翻看药包")
		body.add_child(row)
	else:
		body.add_child(UI.button("再看七号药签", _open))


static func trade_entry(content: VBoxContainer, actor: String) -> void:
	var step := Story.stage(Game.run)
	if actor != "traveler":
		if step in ["fold", "signed", "sent"]:
			content.add_child(UI.para("你还收着回春堂的七号药签。问渡口的事，可以换一只纸鹤找过路客。", 16, UI.INK_SOFT))
		return
	if step == "":
		return
	content.add_child(UI.button("回春堂的七号药签", _open))


static func _open() -> void:
	UI.open_modal("apothecary_ticket", "回春堂 · 七号药签", _fill, true, 620)


static func _action(parent: Container, action: String, caption: String) -> void:
	var reason := Story.issue(Game.run, action)
	parent.add_child(UI.button(caption, _choose.bind(action), reason != "", reason))
	if reason != "":
		parent.add_child(UI.para(reason, 15, UI.CINNABAR))


static func _choose(action: String) -> void:
	if Game.act(func(): return Story.act(Game.run, action)) == "" and action == "unfold":
		_open()


static func _fill(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var step := Story.stage(run)
	if run.phase == "pre":
		if step == "fold":
			body.add_child(UI.para("青纸包过的是一只小瓶。展开四角，正中写着「七」。另一半压在药师的账底，正缺这个角。", 18))
			if run.role == "herbalist":
				body.add_child(UI.para("你给师父裹过这种瓶子，闻得出膏香，也认得金创药方末尾的押记。", 16))
				_action(body, "identify", "认方，请师父对印")
			else:
				body.add_child(UI.para("柜里还排着三个人。药师腾出手，才好把旧方和寄药簿找出来。", 16))
				_action(body, "identify", "等药师辨方 · 1 时辰")
		elif step == "signed":
			body.add_child(UI.para("两半合拢，是一张寄药凭单。药师盖了印：「七号箱存着一瓶金创药。渡船换了人，也认这张签。」", 18))
			body.add_child(UI.para("灾后第 2 日起，08:00–18:00 在家翻劫余录，选「人」页的纸鹤往来，找过路客。", 16))
		return
	match step:
		"fold":
			body.add_child(UI.para("过路客来信：「没盖印的半张签？我可以替你问问七号箱后来跟了哪条船。」", 18))
			_action(body, "ask", "打听七号箱的去向")
		"signed":
			body.add_child(UI.para("纸鹤上夹着另一半红印。「七号箱还在。渡口那班人缺药，有人缠着破袖子还在抬担架。你留药，我替你送到家；你肯给，我替他们签收。」", 18))
			body.add_child(UI.para("两边合用一张签。给渡口能增进过路客的信任，明天还有回信；你也可以收起药签，改天再定。", 16))
			_action(body, "keep", "把金创药收回家 · 1 瓶")
			_action(body, "send", "把这瓶药留给渡口")
		"kept":
			body.add_child(UI.para("瓶子已经收进家中。旧药签上有过路客的字：「按签交还，共一瓶。」", 18))
		"sent":
			body.add_child(UI.para("签背留下了抬担架人的指印。过路客约你第 %d 日 08:00 起收信，会带回一壶渡灯油。" % int(run.flags.get(Story.REPLY_DAY, 0)), 18))
			_action(body, "reply", "接过回信与灯油")
		"replied":
			body.add_child(UI.para("「夜里三趟，两副担架都回来了。」信纸上五枚指印，一枚深，四枚浅。捎来的那壶渡灯油已经收进家中。", 18))
		"unsigned":
			body.add_child(UI.para("七号箱随伤船走了。过路客给你的渡口旧账末尾，有一行小字：「两副担架，都回来了。」", 18))
