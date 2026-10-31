extends "res://scripts/ui/screens/screen_base.gd"
## 劫满：熬过第二十夜后的结局三选。对应原版 EndingChoice（继续坚守 / 带着记忆重走 / 合上日志）。

const Ledger = preload("res://scripts/core/ledger.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const EndingReport = preload("res://scripts/core/ending_report.gd")


func build() -> void:
	var run: Dictionary = Game.run
	var outcome := Mainline.ending(run)
	var center := UI.full_rect(CenterContainer.new())
	add_child(center)
	var v := UI.vbox(14)
	v.custom_minimum_size.x = 1080
	center.add_child(v)
	var title := UI.heading(str(outcome.get("title", "劫 满")), 64, UI.CINNABAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var line := UI.para(str(outcome.get("text", "你活下来了。")) + "\n斩尸 %d 只，守住尸潮 %d 次。" % [int(run.kills), int(run.waves_survived)], 21)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)

	var clues: Dictionary = Data.table("clues")
	var known := 0
	for id in clues:
		if id in run.known_clues:
			known += 1
	var truth := "残卷 %d / %d。" % [known, clues.size()]
	truth += "这一世查到的、选下的，都记在这一卷里；合卷或再入轮回时，会写进前世档案。"
	var t := UI.para(truth, 18, UI.DAI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	# 这一世靠什么扛住的：和生死簿残页对称，赢也要知道自己怎么赢的。
	# 拼成一段而不是四行——结局页本来就长，多四行会把下面的选项卡顶出屏幕
	var recap_parts := []
	for entry in EndingReport.lines(run):
		recap_parts.append("%s：%s" % [str(entry.label), str(entry.text)])
	if not recap_parts.is_empty():
		var recap := UI.para("这一世　" + "　".join(recap_parts), 17, UI.DAI)
		recap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(recap)

	var gain := Ledger.daoxin_gain(run, Ledger.ending_bonus(run))
	var bonus := UI.label("这一世的结局奖励：道心 +%d（总收获见下方）" % Ledger.ending_bonus(run), 17, UI.DAI)
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(bonus)
	# 每日一局：这一局还没落盘（道心是点了"重走/合上"才结算），先把记分板预览出来
	var dday := str(run.get("flags", {}).get("daily", ""))
	if dday != "":
		var dl := UI.para("每日一局 · %s：%s" % [dday,
			Ledger.daily_line(Game.meta, dday, bool(run.get("endless", false)), int(gain.total))], 17, UI.JADE)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dl)

	var row := UI.hbox(16)
	v.add_child(row)
	if bool(outcome.get("can_continue", false)):
		row.add_child(_card("留在这里", "「门还在，灶还热，那就接着住。」",
			"继续　在这座宅院里守下去\n之后　每三夜一波尸潮，越来越凶\n结算　等你合上此录时再算道心", "守 下 去", Game.keep_living.bind(str(run.get("past_lives", {}).get("id", "")))))
	else:
		v.add_child(UI.para("这条路已经走完；可以带着记忆重走，或合上这一卷。", 17, UI.DAI))
	row.add_child(_card("再入轮回", "「从头再把门窗钉一遍。」",
		"回到　三日之前，同一身份重新备劫\n保留　心法、残卷；沿用今世开局\n收获　道心 +%d" % gain.total, "重 走", Game.restart_from_cover.bind(str(run.get("past_lives", {}).get("id", "")))))
	row.add_child(_card("合上此录", "「到这里就够了。」",
		"结算　这一卷到此为止\n收获　道心 +%d" % gain.total, "合 上", Game.close_book.bind(str(run.get("past_lives", {}).get("id", "")))))

	var choose := UI.button("另选下一世开局", Game.choose_next_opening.bind(str(run.get("past_lives", {}).get("id", ""))), false, "先结算这一世，身份和难度不变，重新选下一世的开局筹备；「重走」则沿用这一世的开局。")
	choose.set_meta("opening_next", true)
	# 这一页正是玩家最想吐槽的时候：顺手把这一局的取证打包，别等合卷把存档删了
	var tail := UI.hbox(12)
	tail.alignment = BoxContainer.ALIGNMENT_CENTER
	tail.add_child(UI.button("导出试玩报告", _export_report, false,
		"把这一局的种子、死因构成、最后几十条记录和存档打包成一个文件夹，方便发给开发者。"))
	tail.add_child(choose)
	v.add_child(tail)


func _export_report() -> void:
	Dialogs.playtest_exported(Game.export_playtest())


func _card(title: String, quote: String, body_text: String, btn: String, cb: Callable) -> Control:
	var v := UI.vbox(10)
	v.add_child(UI.heading(title, 30))
	v.add_child(UI.para(quote, 17, UI.DAI))
	v.add_child(UI.sep())
	v.add_child(UI.para(body_text, 17, UI.INK))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	v.add_child(UI.seal_button(btn, cb))
	var p := UI.panel(v)
	p.custom_minimum_size.y = 280
	UI.expand(p)
	return p
