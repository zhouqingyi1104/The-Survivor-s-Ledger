extends "res://scripts/ui/screens/screen_base.gd"
## 标题：续写 / 新开一卷 / 心法 / 残卷 / 制作名单。


func build() -> void:
	var center := UI.full_rect(CenterContainer.new())
	add_child(center)
	var v := UI.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var title := UI.heading("劫 余 录", 92)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("生死簿残页一张 · 渡临川尸劫", 24, UI.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var seal := UI.hbox()
	seal.alignment = BoxContainer.ALIGNMENT_CENTER
	seal.add_child(UI.tag("原型 v0.4", UI.CINNABAR))
	v.add_child(seal)
	v.add_child(Control.new())

	var meta: Dictionary = Game.meta
	var buttons := UI.vbox(10)
	buttons.custom_minimum_size.x = 300
	if Game.has_save():
		buttons.add_child(UI.seal_button("续写此录", Game.continue_game))
	buttons.add_child(UI.button("新开一卷", _new_game))
	buttons.add_child(UI.button("心法（道心 %d）" % int(meta.daoxin), func(): Game.go("talents")))
	buttons.add_child(UI.button("残卷（%d / %d）" % [meta.clues.size(), Data.table("clues").size()], _show_clues))
	buttons.add_child(UI.button("设置", func(): Dialogs.settings(false)))
	buttons.add_child(UI.button("制作名单", _show_credits))
	buttons.add_child(UI.button("退出", func(): get_tree().quit()))
	var wrap := UI.hbox()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(buttons)
	v.add_child(wrap)

	v.add_child(Control.new())
	var stats := UI.label("已轮回 %d 次 · 最久活到第 %d 日 · 劫满 %d 次" % [int(meta.runs), int(meta.best_day), int(meta.endings)], 16, UI.INK_FAINT)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)


func _new_game() -> void:
	if Game.has_save():
		UI.open_modal("confirm_new", "另起一卷？", _build_confirm, true, 520)
	else:
		Game.go("roles")


func _build_confirm(body: VBoxContainer) -> void:
	body.add_child(UI.para("还有一卷没写完。新开一卷会把它合上（这一轮的道心照常结算）。", 18))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.button("再想想", func(): UI.close_modal("confirm_new")))
	row.add_child(UI.seal_button("合上旧卷", _discard_and_new))
	body.add_child(row)


func _discard_and_new() -> void:
	UI.close_modal("confirm_new")
	Game.continue_game()
	Game.close_book()
	Game.go("roles")


func _show_clues() -> void:
	UI.open_modal("clues", "残卷", _build_clues, true, 640)


func _build_clues(body: VBoxContainer) -> void:
	var clues: Dictionary = Data.table("clues")
	for id in clues:
		var known: bool = id in Game.meta.clues
		var row := UI.vbox(2)
		row.add_child(UI.label(clues[id].name, 20, UI.CINNABAR if known else UI.INK_FAINT))
		row.add_child(UI.para(clues[id].text if known else "（还没读到这一页）", 17, UI.INK if known else UI.INK_FAINT))
		body.add_child(row)
	if Game.meta.clues.size() >= clues.size():
		body.add_child(UI.sep())
		body.add_child(UI.para("五篇残卷拼在一起，真相只有一个：尸劫是青云观主炼尸所致。下一卷，也许可以在血月之前上山。", 18, UI.CINNABAR))


func _show_credits() -> void:
	UI.open_modal("credits", "制作名单", _build_credits, true, 680)


## 第三方美术资源的来源和许可证（data/credits.json）。
func _build_credits(body: VBoxContainer) -> void:
	var credits: Dictionary = Data.table("credits")
	for id in credits:
		var row := UI.vbox(2)
		row.add_child(UI.label(credits[id].name, 20, UI.CINNABAR))
		for line in credits[id].lines:
			row.add_child(UI.para(line, 16))
		body.add_child(row)
