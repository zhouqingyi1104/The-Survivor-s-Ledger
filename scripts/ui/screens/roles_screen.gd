extends "res://scripts/ui/screens/screen_base.gd"
## 选身份。对应原版 SelectPeople。

const Pre = preload("res://scripts/core/pre.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")


func build() -> void:
	var v := page(28)
	var head := UI.hbox()
	head.add_child(UI.heading("这一世，你是谁？", 34))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("title")))
	v.add_child(head)
	if not Game.meta.talents.is_empty():
		var names := []
		for t in Game.meta.talents:
			names.append(Data.table("talents")[t].name)
		v.add_child(UI.para("已悟心法：" + "、".join(names), 17, UI.DAI))

	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var roles: Dictionary = Data.table("roles")
	for id in roles:
		row.add_child(_card(id, roles[id]))


func _card(id: String, r: Dictionary) -> Control:
	var unlocked: bool = Game.role_unlocked(id)
	var v := UI.vbox(8)
	v.add_child(UI.heading(r.name, 28, UI.INK if unlocked else UI.INK_FAINT))
	v.add_child(UI.para(r.bio, 17))
	v.add_child(UI.sep())
	var g := UI.grid(2, 10, 4)
	for pair in [["银两", Pre.money(int(r.silver))], ["武力", str(r.fight)], ["负重", "%d 斤" % r.carry], ["气血", str(r.hp_max)]]:
		g.add_child(UI.label(pair[0], 17, UI.INK_SOFT))
		g.add_child(UI.label(pair[1], 17))
	v.add_child(g)
	v.add_child(UI.sep())
	v.add_child(UI.label("【%s】" % r.trait, 19, UI.CINNABAR))
	v.add_child(UI.para(r.trait_desc, 16))
	v.add_child(UI.para("随身：" + Data.describe_items(r.items), 16, UI.INK_FAINT))
	var identity := Identity.preview(id, Game.meta)
	v.add_child(UI.para("身份解法：" + str(identity.get("headline", "")), 15, UI.DAI))
	var source_count: int = identity.get("inheritance", []).size()
	v.add_child(UI.para("旧世经验：%d 条可带入；开局后在劫余录查看来源与代价。" % source_count if source_count > 0 else "旧世经验：尚无符合条件的经历，仍有本职解法。", 15, UI.INK_SOFT))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	if unlocked:
		var pick := UI.seal_button("就是他了", func(): Game.pick_difficulty(id))
		pick.set_meta("identity_role", id)
		v.add_child(pick)
	else:
		v.add_child(UI.button(r.get("unlock_desc", "未解锁"), func(): pass, true))
	var p := UI.panel(v)
	UI.expand(p)
	return p
