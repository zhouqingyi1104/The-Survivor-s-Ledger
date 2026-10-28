extends "res://scripts/ui/screens/screen_base.gd"
## 生死簿残页：死后三选。对应原版 RebirthChoice（翻回昨天 / 翻回扉页 / 合上日志）。

const Ledger = preload("res://scripts/core/ledger.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")


func build() -> void:
	var run: Dictionary = Game.run
	var center := UI.full_rect(CenterContainer.new())
	add_child(center)
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 1080
	center.add_child(v)
	var title := UI.heading("生 死 簿 · 残 页", 48, UI.CINNABAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var cause := UI.label(run.death_cause, 22)
	cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cause)
	var sub := UI.label("判官的朱笔停在你的名字上。%s · 残页还能翻 %d 次。" % [State.diff_name(run), int(run.rebirths_left)], 18, UI.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_recap(run))

	var gain := Ledger.daoxin_gain(run)
	var row := UI.hbox(16)
	v.add_child(row)
	var can_rewind: bool = int(run.rebirths_left) > 0 and (Game.snapshots.has(str(int(run.pday) - 1)) or Game.snapshots.has(str(run.pday)))
	var back_day := int(run.pday) - 1 if Game.snapshots.has(str(int(run.pday) - 1)) else int(run.pday)
	row.add_child(_card("翻回昨日", "“昨天那页写着，门还够结实。”",
		"回到　第 %d 日清晨\n保留　你知道的一切（残卷、记忆）\n代价　寿元：气血上限 -10（现为 %d）\n　　　残页 -1" % [back_day, int(run.attrs.hp_max)],
		"翻回去", Game.rewind, not can_rewind, "残页用尽了" if int(run.rebirths_left) <= 0 else ""))
	row.add_child(_card("翻回扉页", "“从第一页重新写——这次你知道该写什么。”",
		"回到　三日之前，同一身份重新备劫\n保留　心法、残卷；沿用今世开局\n收获　道心 +%d" % gain.total,
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

	var choose := UI.button("另选下一世开局", Game.choose_next_opening.bind(str(run.get("past_lives", {}).get("id", ""))), false, "先结算这一世，再保留身份与难度，重新选择下世筹备；原重走按钮会沿用今世开局。")
	choose.set_meta("opening_next", true)
	# 这一页正是玩家最想吐槽的时候：顺手把这一局的取证打包，别等合卷把存档删了
	var tail := UI.hbox(12)
	tail.alignment = BoxContainer.ALIGNMENT_CENTER
	tail.add_child(UI.button("导出试玩报告", _export_report, false,
		"把这一局的种子、死因构成、最后几十条记录和存档打包成一个文件夹，方便发给开发者。"))
	tail.add_child(choose)
	v.add_child(tail)


## 复盘：谁在什么时候把血打光的，前面几步发生了什么，以及一句能落地的提醒。
## 数据不够（老存档没有扣血账本）就少铺几行，绝不编。
func _recap(run: Dictionary) -> Control:
	var reps: Dictionary = DeathReport.report(run)
	var rows := []
	if int(reps.total) > 0:
		var parts := []
		for s in reps.shares:
			parts.append("%s %d" % [s.name, int(s.amount)])
		rows.append(["死因构成", "这一世共失血 %d：%s" % [int(reps.total), " · ".join(parts)]])
	if str(reps.last) != "":
		rows.append(["最后一击", str(reps.last)])
	# 此前：一条一行，最多两条。三条拼成一行会挤得看不出时刻。
	var steps: Array = reps.steps
	for i in mini(2, steps.size()):
		rows.append(["此前" if i == 0 else "", str(steps[i])])
	for i in reps.hints.size():
		rows.append(["留意" if i == 0 else "", str(reps.hints[i])])
	if rows.is_empty():
		return Control.new()
	var v := UI.vbox(6)
	for row in rows:
		var line := UI.hbox(12)
		var tag := UI.label(str(row[0]), 15, UI.DAI)
		tag.custom_minimum_size.x = 76
		line.add_child(tag)
		line.add_child(UI.expand(UI.label(str(row[1]), 15, UI.INK_SOFT, true)))
		v.add_child(line)
	var p := UI.panel(v)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.custom_minimum_size.x = 900
	return p


func _export_report() -> void:
	Dialogs.playtest_exported(Game.export_playtest())


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
	p.custom_minimum_size.y = 270
	UI.expand(p)
	return p
