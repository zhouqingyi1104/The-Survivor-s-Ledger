extends RefCounted
## 劫余录（今世 / 人 / 前世 三页）。
##
## 从 dialogs.gd 搬出来（工程债第 1 条第三批）。入口仍是 Dialogs.journal()，那个函数只是转发；
## 面板内容与搬之前逐字一致，控件树导出对照过。三页里的九个子入口仍指向 Dialogs 上的那几个弹窗
## （它们还没搬家），差别只是从 `self.xxx` 变成 `Dialogs.xxx` 的可调用引用，行为一样。
## 翻到哪一页、面板高度、日志落底这些状态存在静态变量里——和原来存在 Dialogs 实例上等价
## （Dialogs 是自动加载单例，本来就是整个进程一份）。
##
## 两处 `call_deferred` 也照着原样发在 Dialogs 上（延后回调需要一个节点实例），
## Dialogs 里留了两个同名的一行转发。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Brief = preload("res://scripts/core/brief.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Notebook = preload("res://scripts/core/story_notebook.gd")


static func open() -> void:
	UI.open_modal("journal", "劫余录", _journal, true, 900)


## 要务的分级配色：要命的说朱砂，要紧的用墨，提醒的更淡
static func _brief_color(level: int) -> Color:
	return UI.CINNABAR if level >= Brief.ALARM else (UI.INK if level == Brief.WARN else UI.INK_FAINT)


## 劫余录按「为什么打开」分三页，不按系统分：玩家开它只有三个动机——
## 现在该干什么（今世）、人和事怎么样（人）、以前发生过什么（前世）。
## 系统没碰上之前不摆入口（路线图 B2），免得第一日就摊开九个入口。
const JOURNAL_TABS := [["now", "今世"], ["people", "人"], ["past", "前世"]]

## 当前翻到哪一页。每次打开都从「今世」翻起，不从上次停的地方。
static var _journal_tab := "now"

## 今世页最下面的日志滚动区。只在打开后落一次底，不做持续跟随。
static var _journal_log_scroll: ScrollContainer

## 外层滚动区与内容根：切页后要按当前页的高度重算，
## 否则「人」「前世」这种只有三个入口的页会顶着一整屏空白。
static var _journal_scroll: ScrollContainer
static var _journal_content: VBoxContainer


static func _journal(body: VBoxContainer) -> void:
	_journal_tab = "now"
	var content := UI.vbox(8)
	var tabs := UI.hbox(6)
	tabs.name = "JournalTabs"
	content.add_child(tabs)
	var pages := {}
	for pair in JOURNAL_TABS:
		var page := UI.vbox(8)
		page.name = "JournalPage_" + str(pair[0])
		pages[str(pair[0])] = page
		content.add_child(page)
	_fill_journal_now(pages["now"])
	_fill_journal_people(pages["people"])
	_fill_journal_past(pages["past"])
	_paint_journal_tabs(tabs, pages)
	var scroll := UI.scroll(content, mini(480, maxi(220, int(UI.host.get_viewport().get_visible_rect().size.y) - 190)))
	scroll.name = "JournalDetailsScroll"
	body.add_child(scroll)
	_journal_scroll = scroll
	_journal_content = content
	Dialogs.call_deferred("_journal_log_to_bottom")
	Dialogs.call_deferred("_fit_journal_height")


## 面板高度跟着当前页走：内容矮就矮，内容高就封顶，剩下的靠滚。
static func _fit_journal_height() -> void:
	if not is_instance_valid(_journal_scroll) or not is_instance_valid(_journal_content):
		return
	var cap := mini(480, maxi(220, int(UI.host.get_viewport().get_visible_rect().size.y) - 190))
	var want := int(_journal_content.get_combined_minimum_size().y)
	_journal_scroll.custom_minimum_size.y = mini(want, cap)


## 打开时让日志落到最新一行。只在页面确实可见时做一次——隐藏的 ScrollContainer
## 上改滚动位置会反复请求布局，主线程会卡在布局里回不来（npc_ui 实测死锁），
## 所以这里既不用 changed 信号，也不跟随时更新。
static func _journal_log_to_bottom() -> void:
	if not is_instance_valid(_journal_log_scroll):
		return
	if not _journal_log_scroll.is_visible_in_tree():
		return
	_journal_log_scroll.scroll_vertical = int(_journal_log_scroll.get_v_scroll_bar().max_value)


## 三个页签：选中的用朱砂实心，其余用普通按钮。切页只改 visible，不重建弹窗。
static func _paint_journal_tabs(tabs: HBoxContainer, pages: Dictionary) -> void:
	UI.clear(tabs)
	for pair in JOURNAL_TABS:
		var id := str(pair[0])
		var cb := func() -> void:
			_journal_tab = id
			for k in pages:
				pages[k].visible = (k == id)
			_paint_journal_tabs(tabs, pages)
		var b: Button = UI.seal_button(str(pair[1]), cb) if id == _journal_tab else UI.button(str(pair[1]), cb)
		b.set_meta("journal_tab", id)
		tabs.add_child(b)
	for k in pages:
		pages[k].visible = (k == _journal_tab)
	Dialogs.call_deferred("_fit_journal_height")


## 今世：目标一句、今天该注意的几件事、主线与危机的入口，最后是流水账。
static func _fill_journal_now(page: VBoxContainer) -> void:
	var run := Game.run
	page.add_child(UI.para(Brief.goal(run), 18, UI.GOLD))
	var todos := Brief.lines(run)
	if not todos.is_empty():
		page.add_child(UI.label("今日要务", 15, UI.INK_FAINT))
		for line in todos:
			page.add_child(UI.para("· " + str(line.text), 16, _brief_color(int(line.level))))
	page.add_child(UI.sep())
	var d := Director.state(run)
	page.add_child(UI.para("人情往来：" + " · ".join(Director.ACTORS.keys().map(func(id): return "%s %+d" % [Director.ACTORS[id], int(d.relations[id])])), 16))
	for promise in d.promises:
		page.add_child(UI.para("第 %d 日 · %s 约定送来 %s" % [promise.day, Director.ACTORS[promise.actor], Director.describe(promise.give)], 16))
	var entries := UI.grid(2, 8, 6)
	entries.add_child(UI.expand(UI.button("尸劫来历 · 调查与出路", Dialogs.mainline)))
	entries.add_child(UI.expand(UI.button("风声与危机 · 查验与筹备", Dialogs.crisis)))
	var opening_entry := UI.button("这一世的开局 · 行囊、人情与风声", Dialogs.opening_info)
	opening_entry.set_meta("opening_entry", "journal")
	entries.add_child(UI.expand(opening_entry))
	if not Notebook.pages(run).is_empty():
		entries.add_child(UI.expand(UI.button("旧物手记", _open_notebook)))
	page.add_child(entries)
	var lines: Array = run.get("log", [])
	var s := UI.scroll(UI.log_view(lines, lines.size(), 17), 180)
	_journal_log_scroll = s
	page.add_child(s)


static func _open_notebook() -> void:
	var bookmark := {"title": ""}
	UI.open_modal("story_notebook", "旧物手记", _fill_notebook.bind(bookmark), true, 740)


static func _fill_notebook(body: VBoxContainer, bookmark: Dictionary) -> void:
	var pages := Notebook.pages(Game.run)
	var spread := UI.hbox(20)
	var index := UI.fixed_width(UI.vbox(6), 160)
	var leaves := UI.vbox(0)
	spread.add_child(index)
	spread.add_child(UI.expand(leaves))
	body.add_child(spread)
	var buttons := ButtonGroup.new()
	var current := -1
	for i in pages.size():
		if pages[i].title == bookmark.title:
			current = i
			break
		if current < 0 and pages[i].next != "":
			current = i
	current = maxi(current, 0)
	for i in pages.size():
		var page := pages[i]
		var leaf := UI.vbox(10)
		leaf.add_child(UI.label(page.place, 15, UI.INK_FAINT))
		leaf.add_child(UI.heading(page.title, 24, UI.INK))
		leaf.add_child(UI.sep())
		leaf.add_child(UI.para(page.note, 18, UI.INK))
		if page.next != "":
			leaf.add_child(UI.para(page.next, 16, UI.GOLD))
		leaves.add_child(leaf)
		leaf.visible = i == current
		var turn := UI.button(page.title, func():
			bookmark.title = page.title
			for other in leaves.get_children():
				other.visible = other == leaf)
		turn.toggle_mode = true
		turn.button_group = buttons
		turn.set_pressed_no_signal(leaf.visible)
		index.add_child(turn)


## 人：邻里的事、货郎的账、邻人自己的打算。
static func _fill_journal_people(page: VBoxContainer) -> void:
	var run := Game.run
	page.add_child(UI.para(Neighbor.summary(run), 17))
	var entries := UI.grid(2, 8, 6)
	entries.add_child(UI.expand(UI.button("邻里事务 · 目标与选择记录", Dialogs.neighbor)))
	entries.add_child(UI.expand(UI.button("纸鹤往来 · 交易与欠账", Dialogs.social_trade)))
	entries.add_child(UI.expand(UI.button("邻人与商情 · 目标与行动", Dialogs.npc_autonomy)))
	page.add_child(entries)


## 前世：身份与旧世经验、旧诺查访、生死簿留痕。
static func _fill_journal_past(page: VBoxContainer) -> void:
	var entries := UI.grid(2, 8, 6)
	var identity_entry := UI.button("身份与前世 · 专属解法", Dialogs.identity_paths)
	identity_entry.set_meta("identity_entry", "journal")
	entries.add_child(UI.expand(identity_entry))
	var cycle_entry := UI.button("轮回调查 · 旧诺与今证", Dialogs.cycle_inquiry)
	cycle_entry.set_meta("cycle_entry", "journal")
	entries.add_child(UI.expand(cycle_entry))
	entries.add_child(UI.expand(UI.button("前世记忆 · 查看前世与觉醒", Dialogs.past_lives)))
	page.add_child(entries)
