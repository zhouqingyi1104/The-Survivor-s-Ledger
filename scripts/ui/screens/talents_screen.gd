extends "res://scripts/ui/screens/screen_base.gd"
## 心法：用道心换跨轮回的永久能力。对应原版 PlanTalent / 信念点学能力。


func build() -> void:
	var v := page(28)
	var head := UI.hbox()
	head.add_child(UI.heading("心法", 34))
	head.add_child(UI.label("  道心 %d" % int(Game.meta.daoxin), 24, UI.CINNABAR))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("title")))
	v.add_child(head)
	v.add_child(UI.para("每一轮死去或劫满，都会结算道心。悟得的心法下一卷起一直有效。", 17))
	var g := UI.grid(2, 14, 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var talents: Dictionary = Data.table("talents")
	for id in talents:
		var t: Dictionary = talents[id]
		var owned: bool = id in Game.meta.talents
		var row := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		info.add_child(UI.label("%s　%s" % [t.name, "（已悟）" if owned else "道心 %d" % t.cost], 20, UI.JADE if owned else UI.INK))
		info.add_child(UI.para(t.desc, 16))
		row.add_child(info)
		if not owned:
			row.add_child(UI.button("参悟", func(): Game.buy_talent(id), int(Game.meta.daoxin) < int(t.cost)))
		var p := UI.panel(row)
		UI.expand(p)
		g.add_child(p)
	v.add_child(UI.scroll(g))
