extends "res://scripts/ui/screens/screen_base.gd"
## 劫满：熬过第二十夜后的结局三选。对应原版 EndingChoice（继续坚守 / 带着记忆重走 / 合上日志）。

const Ledger = preload("res://scripts/core/ledger.gd")
const ENDING_BONUS := Ledger.ENDING_BONUS


func build() -> void:
	var run: Dictionary = Game.run
	var center := UI.full_rect(CenterContainer.new())
	add_child(center)
	var v := UI.vbox(14)
	v.custom_minimum_size.x = 1080
	center.add_child(v)
	var title := UI.heading("劫 满", 64, UI.CINNABAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var line := UI.label("第二十一日的太阳照进院子。你活下来了——斩尸 %d 只，守住尸潮 %d 次。" % [int(run.kills), int(run.waves_survived)], 21)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)

	var clues: Dictionary = Data.table("clues")
	var known := 0
	for id in clues:
		if id in run.known_clues:
			known += 1
	var truth := "残卷 %d / %d。" % [known, clues.size()]
	if known >= clues.size():
		truth += "五篇残卷拼在一起：尸劫是青云观主炼尸所致。七星灯还亮着——下一卷，也许能在血月前上山。"
	else:
		truth += "这场尸劫的来历，还藏在没读到的残卷里。"
	var t := UI.para(truth, 18, UI.DAI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var gain := Ledger.daoxin_gain(run, ENDING_BONUS)
	# 每日一局：这一局还没落盘（道心是点了"重走/合上"才结算），先把记分板预览出来
	var dday := str(run.get("flags", {}).get("daily", ""))
	if dday != "":
		var dl := UI.para("每日一局 · %s：%s" % [dday,
			Ledger.daily_line(Game.meta, dday, bool(run.get("endless", false)), int(gain.total))], 17, UI.JADE)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dl)

	var row := UI.hbox(16)
	v.add_child(row)
	row.add_child(_card("留在这里", "“门还在，灶还热，那就接着住。”",
		"继续　在这座宅院里守下去\n之后　每三夜一波尸潮，越来越凶\n结算　等你合上此录时再算道心", "守 下 去", Game.keep_living))
	row.add_child(_card("再入轮回", "“这一回，我知道该往哪走。”",
		"回到　三日之前，同一身份重新备劫\n保留　心法、残卷\n收获　道心 +%d" % gain.total, "重 走", Game.restart_from_cover))
	row.add_child(_card("合上此录", "“到这里就够了。”",
		"结算　这一卷到此为止\n收获　道心 +%d" % gain.total, "合 上", Game.close_book))


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
