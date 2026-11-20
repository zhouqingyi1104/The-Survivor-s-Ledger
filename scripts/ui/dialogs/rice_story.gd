extends RefCounted

const UI = preload("res://scripts/ui/ui_kit.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Story = preload("res://scripts/core/rice_story.gd")
const State = preload("res://scripts/core/state.gd")


static func add_rice_entry(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var stage := Story.stage(run)
	if run.loc != "rice_shop" and stage != "paper":
		if stage == "" and (Pre.travel_block(run, "rice_shop") == "" or int(run.day) < State.PRE_DAYS):
			body.add_child(UI.para("临走时回头一瞥，米行门槛外的空粮袋底下，还露着半截红绳。", 15))
		return
	var caption := "再看纸条"
	var action := _open_paper
	var tag := "paper"
	var detail := "你把那张旧纸条收在了袖里。"
	if stage == "":
		if not Story.can_inspect(run):
			return
		caption = "翻看短扁担"
		action = _inspect
		tag = "inspect"
		detail = "粮袋搬开，门槛外露出一根短扁担。两头都系着褪了色的红绳。"
	var row := UI.hbox(12)
	row.add_child(UI.expand(UI.para(detail, 15)))
	var button := UI.button(caption, action)
	button.set_meta("rice_story_action", tag)
	row.add_child(button)
	body.add_child(row)


static func _inspect() -> void:
	if Game.act(func(): return Story.inspect(Game.run)) == "":
		_open_paper()


static func _open_paper() -> void:
	UI.open_modal("rice_story_paper", "担头的纸条", _paper, true, 580)


static func _paper(body: VBoxContainer) -> void:
	body.add_child(UI.para(Story.PAPER_TEXT, 18, UI.INK))


static func add_book_entry(body: VBoxContainer) -> void:
	var stage := Story.stage(Game.run)
	if stage not in ["paper", "carry", "marks"]:
		return
	var button := UI.button("把纸条递给掌柜" if stage == "paper" else "再问燕尾担", _open_book)
	button.set_meta("rice_story_action", "book")
	body.add_child(button)
	body.add_child(UI.sep())


static func _open_book() -> void:
	UI.open_modal("rice_story_book", "燕尾担", _book, true, 640)


static func _book(body: VBoxContainer) -> void:
	var stage := Story.stage(Game.run)
	match stage:
		"paper":
			body.add_child(UI.para("掌柜用指甲顺着纸上的燕尾划了一下。「缺口朝哪家，米就送哪家。我那会儿才这么高。」他拿手比了比柜沿。", 18, UI.INK))
			body.add_child(UI.para("「孩子肩窄，担子就锯短些。进了巷子也别喊人，照着记号走，谁家断炊，街坊不用都知道。」他从门后拎出两个书篮，让你挑一样本事学。", 17))
			body.add_child(UI.sep())
			body.add_child(UI.para("本世只能选一门，各需 1 个时辰。", 16, UI.CINNABAR))
			var issue := Story.lesson_issue(Game.run)
			if issue != "":
				body.add_child(UI.para(issue, 16, UI.CINNABAR))
			_lesson_row(body, "carry", "学挑担", "本世气血上限 +5，当前气血 +5。", issue)
			_lesson_row(body, "marks", "认燕尾记", "本世搜寻经验 +10。搜寻等级越高，翻找时外泄的阳气越少。", issue)
		"carry":
			body.add_child(UI.para("你挑起书篮，跟着掌柜绕过巷口。回来时书还是那些书，担头已经不再磕门框了。", 18, UI.INK))
			body.add_child(UI.para("本世气血上限 +5，当前气血 +5。如今气血上限为 %d。" % State.attr_max(Game.run, "hp"), 16, UI.CINNABAR))
		"marks":
			body.add_child(UI.para("你一路认出门槛、墙角的燕尾。走到第三家，掌柜收回指路的手，让你带他走完了后半程。", 18, UI.INK))
			body.add_child(UI.para("本世搜寻经验 +10。如今搜寻熟练为 %d 级。" % State.prof_level(Game.run, "search"), 16, UI.CINNABAR))
	if stage in ["carry", "marks"]:
		body.add_child(UI.para("临走，掌柜说：「米行的旧账簿也该翻个面了。那帮孩子写字，专拣人家不用的地方。」", 16))


static func _lesson_row(body: VBoxContainer, choice: String, caption: String, effect: String, issue: String) -> void:
	var row := UI.hbox(12)
	var button := UI.button(caption, _learn.bind(choice), issue != "", issue)
	button.set_meta("rice_story_action", choice)
	row.add_child(button)
	row.add_child(UI.expand(UI.para(effect, 16)))
	body.add_child(row)


static func _learn(choice: String) -> void:
	Game.act(func(): return Story.learn(Game.run, choice))


static func add_ledger_page(body: VBoxContainer) -> void:
	if Story.heard_echo(Game.run):
		body.add_child(UI.para(Story.echo_text(Game.run), 17, UI.GOLD))
	elif Story.can_reveal(Game.run):
		body.add_child(UI.para("账簿封底翘起了一角。两道浅浅的刀痕，你在书肆见过。", 16))
		var button := UI.button("翻到账簿封底", _reveal)
		button.set_meta("rice_story_action", "echo")
		body.add_child(button)


static func _reveal() -> void:
	Game.act(func(): return Story.reveal(Game.run))
