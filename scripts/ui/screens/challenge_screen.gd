extends "res://scripts/ui/screens/screen_base.gd"
## 挑了愿（挑战自选的第一步）。对应原版 ChallengeSetup 的 Target 那一张表。
## 可挑可不挑：不挑就是寻常一局；挑了达成才给道心，没达成结算里标"未成"。
## 条件全在 data/challenge.json，这里只负责勾选和显示。

## 已勾的愿 id
var _picked: Array = []


func build() -> void:
	var v := page(28)
	var head := UI.hbox()
	head.add_child(UI.heading("要立什么愿？", 34))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("difficulty")))
	v.add_child(head)
	var role_id: String = Game.pending_role
	if role_id != "":
		var r: Dictionary = Data.table("roles")[role_id]
		v.add_child(UI.para("身份：%s · 难度：%s　—— 愿可以不立，立了就要还。" % [
			r.name, State.diff_name({"difficulty": Game.pending_difficulty})], 17))
	v.add_child(UI.sep())
	for g in Data.table("challenge").get("goals", []):
		v.add_child(_row(g))
	v.add_child(UI.spacer())
	var foot := UI.hbox()
	foot.add_child(UI.para("可立可不立。立了的愿达成才给道心，没达成会写明「未成」。", 15, UI.INK_FAINT))
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("不立愿，直接开始", func(): _start(false)))
	foot.add_child(UI.seal_button(_start_text(), func(): _start(true)))
	v.add_child(foot)


## 一行一件事：左边打勾，右边名字、说明、奖励道心。
func _row(g: Dictionary) -> Control:
	var id := str(g.get("id", ""))
	var on: bool = id in _picked
	var h := UI.hbox(10)
	var box := CheckBox.new()
	box.button_pressed = on
	box.toggled.connect(func(pressed: bool) -> void: _toggle(id, pressed))
	h.add_child(box)
	var col := UI.vbox(2)
	var title := UI.hbox(8)
	title.add_child(UI.label(str(g.get("name", id)), 20, UI.INK if on else UI.INK_SOFT))
	title.add_child(UI.label("道心 +%d" % int(g.get("bonus", 0)), 17, UI.CINNABAR))
	col.add_child(title)
	col.add_child(UI.para(str(g.get("desc", "")), 16, UI.INK_SOFT))
	h.add_child(col)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return UI.panel(h)


func _toggle(id: String, pressed: bool) -> void:
	if pressed and not id in _picked:
		_picked.append(id)
	elif not pressed:
		_picked.erase(id)
	# 重画一遍，让名字的深浅跟着勾选变。
	# 必须先 clear：build() 只往 self 上追加，不清就会每点一次叠一层。
	UI.clear(self)
	build()


func _start_text() -> String:
	if _picked.is_empty():
		return "就这些，开始"
	var total := 0
	for g in Data.table("challenge").get("goals", []):
		if str(g.get("id", "")) in _picked:
			total += int(g.get("bonus", 0))
	return "立 %d 个愿（满额 +%d），开始" % [_picked.size(), total]


func _start(with_goals: bool) -> void:
	var role_id: String = Game.pending_role
	if role_id == "":
		Game.go("roles")
		return
	var goals: Array = _picked.duplicate() if with_goals else []
	Game.pending_role = ""
	Game.new_game(role_id, Game.pending_difficulty, goals)
