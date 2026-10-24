extends "res://scripts/ui/screens/screen_base.gd"
## 立愿与攀仗（挑战自选）。对应原版 ChallengeSetup 的 Target 与 Ability 两张表。
## 两段都可以不选：什么都不选就是寻常一局。
##   了愿：达成了加道心，没达成结算里写「未成」
##   凭仗：开局多给东西，但这一局的道心倍率下调
## 条件与数值全在 data/challenge.json，这里只负责勾选和显示。

const Ledger = preload("res://scripts/core/ledger.gd")
const Companion = preload("res://scripts/core/companion.gd")
const Opening = preload("res://scripts/core/opening.gd")

## 已勾的愿 / 凭仗 / 誓约 id
var _picked: Array = []
var _boons: Array = []
var _vows: Array = []
## 开局模式：守到死（不设终局）、每日一局（种子按日期）。两个都可以不选。
var _endless := false
var _daily := false
## 同院的人：带谁回来搭伙（最多 2 人）。不是誓约也不是凭仗，不改道心倍率。
var _mates: Array = []
var _opening_id := "plain"
var _setup_read := false
var _starting := false
var _scroll_y := 0


func build() -> void:
	if not _setup_read:
		_setup_read = true
		var setup: Dictionary = Game.pending_opening_setup
		_endless = bool(setup.get("endless", false))
		_daily = bool(setup.get("daily", false))
		_mates = setup.get("mates", []).duplicate()
		Game.pending_opening_setup = {}
	_normalize_opening()
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
	# 开局模式：两件事都不属于"立愿/凭仗/誓约"，单独放一行，选了才展开说明
	var modes := UI.hbox(10)
	var endless_pick := UI.button("□ 守到死（不设终局）" if not _endless else "■ 守到死（不设终局）", func(): _toggle_mode(true))
	endless_pick.set_meta("opening_mode", "endless")
	modes.add_child(endless_pick)
	var daily_pick := UI.button(("□ 每日一局（%s）" if not _daily else "■ 每日一局（%s）") % Game.today_text(), func(): _toggle_mode(false))
	daily_pick.set_meta("opening_mode", "daily")
	modes.add_child(daily_pick)
	modes.add_child(UI.spacer())
	v.add_child(modes)
	if _endless or _daily:
		v.add_child(UI.para(_mode_note(), 15, UI.INK_SOFT))
	if _daily:
		v.add_child(UI.para(Ledger.daily_line(Game.meta, Game.today_text(), _endless), 15, UI.JADE))
	# 同院的人：不改道心倍率，代价是每天天亮的口粮（吃不上就不干活）
	var mates := UI.hbox(8)
	mates.add_child(UI.label("同院的人（最多 2 人）", 18, UI.INK_SOFT))
	for pid in Data.table("companions"):
		var p: Dictionary = Data.table("companions")[pid]
		var on: bool = pid in _mates
		var full: bool = _mates.size() >= 2 and not on
		mates.add_child(UI.button("%s %s" % ["■" if on else "□", str(p.name)],
			func(): _toggle_mate(pid), full, "取消" if on else ("院里已经住满了" if full else "带他进宅院")))
	mates.add_child(UI.spacer())
	mates.add_child(UI.label("每人每天 12 饱腹 + 1 瓢水 · 道心 −5%/人", 15, UI.INK_FAINT))
	v.add_child(mates)
	for pid in _mates:
		var p2: Dictionary = Data.table("companions").get(pid, {})
		v.add_child(UI.para("%s：%s" % [str(p2.get("name", pid)), str(p2.get("desc", ""))], 15, UI.INK_SOFT))
	if "carpenter" in _mates and "no_door" in _vows:
		v.add_child(UI.para("你立了「不修门」——陈木匠修的门也记在你账上，这条誓约会当场作废。", 15, UI.CINNABAR))
	v.add_child(UI.sep())
	# 三张表一共 11 行，竖着排会顶出屏幕（实测 1600×900 下底部按钮被截掉），
	# 所以分两栏：左边誓约，右边凭仗 + 了愿。三栏装进滚动区，底下的开始按钮才不会被顶出屏幕
	# （1280×720 下加了同院的人之后真的被顶出去过）。
	var scroll := ScrollContainer.new()
	scroll.name = "OpeningChoiceScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var contents := UI.vbox(14)
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contents)
	_build_openings(contents)
	contents.add_child(UI.sep())
	var cols := UI.hbox(18)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(cols)
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
	v.add_child(UI.para("当前挑战：" + _start_text().trim_suffix("，开始"), 15, UI.INK_SOFT))
	var foot := UI.hbox()
	foot.add_child(UI.para("开局互斥，挑战可空着。", 15, UI.INK_FAINT))
	foot.add_child(UI.spacer())
	var plain_start := UI.button("普通行囊，跳过挑战", func(): _start(false), false, "使用普通开局并清空誓约、凭仗和了愿；保留已选模式与同院的人。")
	plain_start.set_meta("opening_start", "plain")
	foot.add_child(plain_start)
	var selected_start := UI.seal_button("按所选开局，开始", func(): _start(true), false, _start_text())
	selected_start.set_meta("opening_start", "selected")
	foot.add_child(selected_start)
	v.add_child(foot)
	scroll.set_deferred("scroll_vertical", _scroll_y)


func _normalize_opening() -> void:
	if _daily or "bare" in _vows:
		_opening_id = "plain"
	var found := false
	for option in Opening.options(Game.pending_role, Game.meta, _daily, _vows, Game.pending_difficulty):
		if str(option.id) == _opening_id and str(option.get("block", "")) == "": found = true
	if not found: _opening_id = "plain"


func _build_openings(parent: VBoxContainer) -> void:
	parent.add_child(UI.label("这世带着什么回来 · 只选一项", 22, UI.DAI))
	parent.add_child(UI.para("先花银和时间筹备，换来不同物资、人情与首场危机风声；放下旧世也能照常开始。", 16))
	var grid := UI.grid(2, 12, 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in Opening.options(Game.pending_role, Game.meta, _daily, _vows, Game.pending_difficulty):
		var id := str(option.id)
		var on := _opening_id == id
		var block := str(option.get("block", ""))
		var card := UI.vbox(5)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pick := UI.button(("■ " if on else "□ ") + str(option.get("text", id)), func(): _pick_opening(id), block != "", block)
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.set_meta("opening_choice", id)
		card.add_child(pick)
		card.add_child(UI.para(str(option.get("hint", "")), 15))
		if block != "": card.add_child(UI.para(block, 15, UI.CINNABAR))
		var panel := UI.panel(card, Color("#f2e3c2") if on else UI.PANEL)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
	parent.add_child(grid)


func _pick_opening(id: String) -> void:
	_opening_id = id
	_redraw()


func _redraw() -> void:
	var scroll := find_child("OpeningChoiceScroll", true, false) as ScrollContainer
	if scroll != null: _scroll_y = scroll.scroll_vertical
	UI.clear(self)
	build()


## 一行一件事：左边方块标记（■ 选了 / □ 没选），右边名字 + 说明 + 分数。
## 不用 CheckBox：主题里没配勾选图标，选了和没选长得一模一样，玩家看不出挑了啥。
## kind：0=了愿（加分）1=凭仗（扣倍率）2=誓约（抬倍率）
func _row(item: Dictionary, bucket: Array, field: String, kind: int) -> Control:
	var id := str(item.get("id", ""))
	var on: bool = id in bucket
	var h := UI.hbox(10)
	var mark := UI.button("■" if on else "□", func(): _toggle(id, not on, bucket))
	mark.custom_minimum_size = Vector2(38, 38)
	mark.set_meta("challenge_choice", id)
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


## 选中/取消一种开局模式。endless=true 是守到死，false 是每日一局。
func _toggle_mode(endless: bool) -> void:
	if endless:
		_endless = not _endless
	else:
		_daily = not _daily
	_redraw()


## 带 / 不带一个人进宅院。院里最多住 2 个帮手。
func _toggle_mate(pid: String) -> void:
	if pid in _mates:
		_mates.erase(pid)
	elif _mates.size() < 2:
		_mates.append(pid)
	_redraw()


## 选了模式才展开：说清代价，别让玩家打完才发现"活到终局"不算数。
func _mode_note() -> String:
	var out: Array = []
	if _endless:
		out.append("守到死：第二十日天亮不进结局，尸潮照来，一直守到死为止。道心按活过的天数算，不再另给劫满的 10 点")
		if "survive" in _picked:
			out.append("「活到终局」在这种局里不会达成，别白挑")
	if _daily:
		out.append("每日一局：种子按 %s 给，同一天所有人同一副牌；同一副牌可以重打，记当日最好的一次" % Game.today_text())
	return "；".join(out) + "。"


func _toggle(id: String, pressed: bool, bucket: Array) -> void:
	if pressed and not id in bucket:
		bucket.append(id)
	elif not pressed:
		bucket.erase(id)
	# 必须先 clear：build() 只往 self 上追加，不清就会每点一次叠一层。
	_redraw()


func _start_text() -> String:
	if _picked.is_empty() and _boons.is_empty() and _vows.is_empty() and not _endless and not _daily and _mates.is_empty():
		return "就这样，开始"
	var mul := 1.0
	for vw in Data.table("challenge").get("vows", []):
		if str(vw.get("id", "")) in _vows:
			mul += float(vw.get("mul", 1.0)) - 1.0
	for b in Data.table("challenge").get("boons", []):
		if str(b.get("id", "")) in _boons:
			mul -= float(b.get("malus", 0.0))
	# 同院的人：开局多帮手，道心打折（一人 −5%，折扣见 companion.MATE_MALUS 的实测依据）
	mul -= Companion.MATE_MALUS * _mates.size()
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
	if _endless:
		parts.append("守到死")
	if _daily:
		parts.append("每日一局")
	if not _mates.is_empty():
		parts.append("同院 %d 人" % _mates.size())
	var tail := "道心 ×%.2f" % mul
	if goal_sum > 0:
		tail += "，另加 %d" % goal_sum
	return "%s｜%s，开始" % [" · ".join(parts), tail]


func _start(with_picks: bool) -> void:
	if _starting: return
	var role_id: String = Game.pending_role
	if role_id == "":
		Game.go("roles")
		return
	var goals: Array = _picked.duplicate() if with_picks else []
	var boons: Array = _boons.duplicate() if with_picks else []
	var vows: Array = _vows.duplicate() if with_picks else []
	_starting = true
	var result: String = Game.new_game(role_id, Game.pending_difficulty, goals, boons, vows, _endless, _daily, _mates.duplicate(), _opening_id if with_picks else "plain")
	if result == "":
		Game.pending_role = ""
	else:
		_starting = false
		Game.toast.emit(result)
