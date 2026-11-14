extends RefCounted
## 神龛求签：功德换签、留签到明日、摇签筒重来。
##
## 从 dialogs.gd 搬出来（工程债第 1 条第二批）。入口仍是 Dialogs.omens()，那个函数只是转发；
## 面板内容与搬之前逐字一致，控件树导出对照过。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Kit = preload("res://scripts/ui/dialogs/kit.gd")


static func open() -> void:
	UI.open_modal("omens", "神龛求签", _build, true, 900)


static func _build(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	body.add_child(UI.para("功德 %d。签筒里每日三支签，可以花功德求，也可以留一支到明日；同一天求得越多越贵。" % int(run.merit), 17))
	var row := UI.hbox(12)
	for id in run.omens.offer:
		var o: Dictionary = Data.table("omens")[id]
		var v := UI.vbox(6)
		var taken: bool = id in run.omens.taken
		var cost := Ledger.omen_cost(run, id)
		v.add_child(UI.tag(o.tier, UI.CINNABAR if o.tier.begins_with("上") else UI.GOLD))
		v.add_child(UI.heading(o.name, 24, UI.INK_FAINT if taken else UI.INK))
		v.add_child(UI.para("「%s」" % o.verse, 16, UI.DAI))
		v.add_child(UI.para(o.desc, 16))
		v.add_child(UI.label("功德 %d" % cost, 17, UI.CINNABAR))
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(gap)
		if taken:
			v.add_child(UI.tag("已求得", UI.JADE))
		else:
			v.add_child(UI.seal_button("求此签", func(): Kit.act(func(): return Ledger.take_omen(Game.run, id)), int(run.merit) < cost))
			var locked: bool = run.omens.locked == id
			v.add_child(UI.button("不留了" if locked else "留到明日", func(): Kit.act(func(): return toggle_lock(id))))
		var p := UI.panel(v, UI.PAPER)
		UI.expand(p)
		row.add_child(p)
	body.add_child(row)
	var foot := UI.hbox()
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("摇签筒（%d 功德）" % Ledger.REROLL_COST, func(): Kit.act(func(): return Ledger.reroll_omens(Game.run)), int(run.merit) < Ledger.REROLL_COST))
	body.add_child(foot)


static func toggle_lock(id: String) -> String:
	Ledger.toggle_lock(Game.run, id)
	return ""
