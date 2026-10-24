extends "res://scripts/ui/screens/screen_base.gd"
## 生死簿残页：死后三选。对应原版 RebirthChoice（翻回昨天 / 翻回扉页 / 合上日志）。

const Ledger = preload("res://scripts/core/ledger.gd")


func build() -> void:
	var run: Dictionary = Game.run
	var center := UI.full_rect(CenterContainer.new())
	add_child(center)
	var v := UI.vbox(14)
	v.custom_minimum_size.x = 1080
	center.add_child(v)
	var title := UI.heading("生 死 簿 · 残 页", 54, UI.CINNABAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var cause := UI.label(run.death_cause, 22)
	cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cause)
	var sub := UI.label("判官的朱笔停在你的名字上。%s · 残页还能翻 %d 次。" % [State.diff_name(run), int(run.rebirths_left)], 18, UI.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var gain := Ledger.daoxin_gain(run)
	var row := UI.hbox(16)
	v.add_child(row)
	var can_rewind: bool = int(run.rebirths_left) > 0 and (Game.snapshots.has(str(int(run.pday) - 1)) or Game.snapshots.has(str(run.pday)))
	var back_day := int(run.pday) - 1 if Game.snapshots.has(str(int(run.pday) - 1)) else int(run.pday)
	row.add_child(_card("翻回昨日", "“昨天那页写着，门还够结实。”",
		"回到　第 %d 日清晨\n保留　你知道的一切（残卷、记忆）\n代价　寿元：气血上限 -10（现为 %d）\n　　　残页 -1" % [back_day, int(run.attrs.hp_max)],
		"翻回去", Game.rewind, not can_rewind, "残页用尽了" if int(run.rebirths_left) <= 0 else ""))
	row.add_child(_card("翻回扉页", "“从第一页重新写——这次你知道该写什么。”",
		"回到　三日之前，同一身份重新备劫\n保留　心法、残卷\n收获　道心 +%d" % gain.total,
		"重新来过", Game.restart_from_cover.bind(str(run.get("past_lives", {}).get("id", "")))))
	row.add_child(_card("合上此录", "“到这里就够了。”",
		"结算　这一卷到此为止\n收获　道心 +%d\n之后　回到标题，可去参悟心法" % gain.total,
		"合上", Game.close_book.bind(str(run.get("past_lives", {}).get("id", "")))))
	var detail := []
	for l in gain.lines:
		detail.append("%s +%d" % [l[0], l[1]])
	var d := UI.label("道心明细：" + "　".join(detail), 16, UI.INK_FAINT)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)


func _card(title: String, quote: String, body_text: String, btn: String, cb: Callable, disabled := false, tip := "") -> Control:
	var v := UI.vbox(10)
	v.add_child(UI.heading(title, 30))
	v.add_child(UI.para(quote, 17, UI.DAI))
	v.add_child(UI.sep())
	v.add_child(UI.para(body_text, 17, UI.INK))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	v.add_child(UI.seal_button(btn, cb, disabled, tip))
	var p := UI.panel(v)
	p.custom_minimum_size.y = 300
	UI.expand(p)
	return p
