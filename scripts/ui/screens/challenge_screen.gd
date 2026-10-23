extends "res://scripts/ui/screens/screen_base.gd"
## 立愿与攀仗（挑战自选）。对应原版 ChallengeSetup 的 Target 与 Ability 两张表。
## 两段都可以不选：什么都不选就是寻常一局。
##   了愿：达成了加道心，没达成结算里写「未成」
##   凭仗：开局多给东西，但这一局的道心倍率下调
## 条件与数值全在 data/challenge.json，这里只负责勾选和显示。

## 已勾的愿 / 凭仗 id
var _picked: Array = []
var _boons: Array = []


func build() -> void:
	var v := page(24)
	var head := UI.hbox()
	head.add_child(UI.heading("立什么愿，带什么家伙", 32))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("difficulty")))
	v.add_child(head)
	var role_id: String = Game.pending_role
	if role_id != "":
		var r: Dictionary = Data.table("roles")[role_id]
		v.add_child(UI.para("身份：%s · 难度：%s" % [
			r.name, State.diff_name({"difficulty": Game.pending_difficulty})], 17))
	v.add_child(UI.sep())
	v.add_child(UI.label("凭仗 · 开局多给，这一局的道心打折", 20, UI.INK_SOFT))
	for b in Data.table("challenge").get("boons", []):
		v.add_child(_row(b, _boons, "malus", true))
	v.add_child(UI.sep())
	v.add_child(UI.label("了愿 · 一局的目标，达成才给道心", 20, UI.INK_SOFT))
	for g in Data.table("challenge").get("goals", []):
		v.add_child(_row(g, _picked, "bonus", false))
	v.add_child(UI.spacer())
	var foot := UI.hbox()
	foot.add_child(UI.para("都可空着。", 15, UI.INK_FAINT))
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("什么都不选，开始", func(): _start(false)))
	foot.add_child(UI.seal_button(_start_text(), func(): _start(true)))
	v.add_child(foot)


## 一行一件事：左边方块标记（■ 选了 / □ 没选），右边名字 + 说明 + 分数。
## 不用 CheckBox：主题里没配勾选图标，选了和没选长得一模一样，玩家看不出挑了啥。
func _row(item: Dictionary, bucket: Array, field: String, penalty: bool) -> Control:
	var id := str(item.get("id", ""))
	var on: bool = id in bucket
	var h := UI.hbox(10)
	var mark := UI.button("■" if on else "□", func(): _toggle(id, not on, bucket))
	mark.custom_minimum_size = Vector2(40, 40)
	mark.tooltip_text = "取消" if on else "选中"
	h.add_child(mark)
	var col := UI.vbox(2)
	var title := UI.hbox(8)
	title.add_child(UI.label(str(item.get("name", id)), 20, UI.INK if on else UI.INK_SOFT))
	var v := float(item.get(field, 0.0))
	title.add_child(UI.label(("道心 −%d%%" % int(round(v * 100.0))) if penalty else ("道心 +%d" % int(v)), 17, UI.INK_FAINT if penalty else UI.CINNABAR))
	col.add_child(title)
	col.add_child(UI.para(str(item.get("desc", "")), 16, UI.INK_SOFT))
	h.add_child(col)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return UI.panel(h, Color("#f2e3c2") if on else UI.PANEL)


func _toggle(id: String, pressed: bool, bucket: Array) -> void:
	if pressed and not id in bucket:
		bucket.append(id)
	elif not pressed:
		bucket.erase(id)
	# 必须先 clear：build() 只往 self 上追加，不清就会每点一次叠一层。
	UI.clear(self)
	build()


func _start_text() -> String:
	if _picked.is_empty() and _boons.is_empty():
		return "就这样，开始"
	var mul := 1.0
	for b in Data.table("challenge").get("boons", []):
		if str(b.get("id", "")) in _boons:
			mul -= float(b.get("malus", 0.0))
	var goal_sum := 0
	for g in Data.table("challenge").get("goals", []):
		if str(g.get("id", "")) in _picked:
			goal_sum += int(g.get("bonus", 0))
	return "愿 %d 个（+%d）· 凭仗 %d 个（×%.2f），开始" % [_picked.size(), goal_sum, _boons.size(), maxf(0.5, mul)]


func _start(with_picks: bool) -> void:
	var role_id: String = Game.pending_role
	if role_id == "":
		Game.go("roles")
		return
	var goals: Array = _picked.duplicate() if with_picks else []
	var boons: Array = _boons.duplicate() if with_picks else []
	Game.pending_role = ""
	Game.new_game(role_id, Game.pending_difficulty, goals, boons)
