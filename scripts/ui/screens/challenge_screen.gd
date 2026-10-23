extends "res://scripts/ui/screens/screen_base.gd"
## 立愿与攀仗（挑战自选）。对应原版 ChallengeSetup 的 Target 与 Ability 两张表。
## 两段都可以不选：什么都不选就是寻常一局。
##   了愿：达成了加道心，没达成结算里写「未成」
##   凭仗：开局多给东西，但这一局的道心倍率下调
## 条件与数值全在 data/challenge.json，这里只负责勾选和显示。

## 已勾的愿 / 凭仗 / 誓约 id
var _picked: Array = []
var _boons: Array = []
var _vows: Array = []


func build() -> void:
	var v := page(18)
	var head := UI.hbox()
	head.add_child(UI.heading("立什么愿，带什么家伙", 30))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("difficulty")))
	v.add_child(head)
	var role_id: String = Game.pending_role
	if role_id != "":
		var r: Dictionary = Data.table("roles")[role_id]
		v.add_child(UI.para("身份：%s · 难度：%s" % [
			r.name, State.diff_name({"difficulty": Game.pending_difficulty})], 16))
	v.add_child(UI.sep())
	# 三张表一共 11 行，竖着排会顶出屏幕（实测 1600×900 下底部按钮被截掉），
	# 所以分两栏：左边誓约，右边凭仗 + 了愿。
	var cols := UI.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# 誓约超过 6 条就再开一栏：七条时底部已经贴到按钮，再往下堆必然截断。
	var vow_list: Array = Data.table("challenge").get("vows", [])
	var half: int = int(ceil(vow_list.size() / 2.0)) if vow_list.size() > 6 else vow_list.size()
	var left := UI.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UI.label("誓约 · 放弃一条路，道心抬高", 18, UI.INK_SOFT))
	for i in range(0, half):
		left.add_child(_row(vow_list[i], _vows, "mul", 2))
	cols.add_child(left)
	if half < vow_list.size():
		var mid := UI.vbox(6)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(UI.label("誓约（续）", 18, UI.INK_SOFT))
		for i in range(half, vow_list.size()):
			mid.add_child(_row(vow_list[i], _vows, "mul", 2))
		cols.add_child(mid)
	var right := UI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UI.label("凭仗 · 开局多给，道心打折", 18, UI.INK_SOFT))
	for b in Data.table("challenge").get("boons", []):
		right.add_child(_row(b, _boons, "malus", 1))
	right.add_child(UI.sep())
	right.add_child(UI.label("了愿 · 一局的目标，达成才给道心", 18, UI.INK_SOFT))
	for g in Data.table("challenge").get("goals", []):
		right.add_child(_row(g, _picked, "bonus", 0))
	cols.add_child(right)
	v.add_child(UI.spacer())
	var foot := UI.hbox()
	foot.add_child(UI.para("都可空着。", 15, UI.INK_FAINT))
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("什么都不选，开始", func(): _start(false)))
	foot.add_child(UI.seal_button(_start_text(), func(): _start(true)))
	v.add_child(foot)


## 一行一件事：左边方块标记（■ 选了 / □ 没选），右边名字 + 说明 + 分数。
## 不用 CheckBox：主题里没配勾选图标，选了和没选长得一模一样，玩家看不出挑了啥。
## kind：0=了愿（加分）1=凭仗（扣倍率）2=誓约（抬倍率）
func _row(item: Dictionary, bucket: Array, field: String, kind: int) -> Control:
	var id := str(item.get("id", ""))
	var on: bool = id in bucket
	var h := UI.hbox(10)
	var mark := UI.button("■" if on else "□", func(): _toggle(id, not on, bucket))
	mark.custom_minimum_size = Vector2(38, 38)
	mark.tooltip_text = "取消" if on else "选中"
	h.add_child(mark)
	var col := UI.vbox(2)
	var title := UI.hbox(8)
	title.add_child(UI.label(str(item.get("name", id)), 19, UI.INK if on else UI.INK_SOFT))
	var val := float(item.get(field, 0.0))
	var tag_text := ""
	var tag_col := UI.CINNABAR
	match kind:
		1:
			tag_text = "道心 −%d%%" % int(round(val * 100.0))
			tag_col = UI.INK_FAINT
		2:
			# ×1.00 的誓约不抬倍率（「一趟」实测反而好赢，按数据只给 1.00）。
			# 直接写「×1.00」看着像没算出来，写明"不加成"。
			tag_text = "道心 ×%.2f" % val if val > 1.005 else "道心不加成"
			tag_col = UI.JADE if val > 1.005 else UI.INK_FAINT
		_:
			tag_text = "道心 +%d" % int(val)
	title.add_child(UI.label(tag_text, 16, tag_col))
	col.add_child(title)
	col.add_child(UI.para(str(item.get("desc", "")), 15, UI.INK_SOFT))
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
	if _picked.is_empty() and _boons.is_empty() and _vows.is_empty():
		return "就这样，开始"
	var mul := 1.0
	for vw in Data.table("challenge").get("vows", []):
		if str(vw.get("id", "")) in _vows:
			mul += float(vw.get("mul", 1.0)) - 1.0
	for b in Data.table("challenge").get("boons", []):
		if str(b.get("id", "")) in _boons:
			mul -= float(b.get("malus", 0.0))
	mul = clampf(mul, 0.5, 1.5)
	var goal_sum := 0
	for g in Data.table("challenge").get("goals", []):
		if str(g.get("id", "")) in _picked:
			goal_sum += int(g.get("bonus", 0))
	var parts: Array = []
	if not _vows.is_empty():
		parts.append("立誓 %d" % _vows.size())
	if not _boons.is_empty():
		parts.append("凭仗 %d" % _boons.size())
	if not _picked.is_empty():
		parts.append("了愿 %d" % _picked.size())
	var tail := "道心 ×%.2f" % mul
	if goal_sum > 0:
		tail += "，另加 %d" % goal_sum
	return "%s｜%s，开始" % [" · ".join(parts), tail]


func _start(with_picks: bool) -> void:
	var role_id: String = Game.pending_role
	if role_id == "":
		Game.go("roles")
		return
	var goals: Array = _picked.duplicate() if with_picks else []
	var boons: Array = _boons.duplicate() if with_picks else []
	var vows: Array = _vows.duplicate() if with_picks else []
	Game.pending_role = ""
	Game.new_game(role_id, Game.pending_difficulty, goals, boons, vows)
