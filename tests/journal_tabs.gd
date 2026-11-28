extends Node
## 劫余录分页：第一日打开只看见「今世」那一页的三个入口，翻页才看见其余的。
## 运行：godot --headless --path . res://tests/journal_tabs.tscn
##
## 这一条是路线图 B2 的验收标准（第 1 日可见入口 ≤ 3 个）的落地版：
## 分页的意义是让玩家打开就知道先看哪，所以入口不能又摊回一屏。

const State = preload("res://scripts/core/state.gd")
const Notebook = preload("res://scripts/core/story_notebook.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Ticket = preload("res://scripts/core/apothecary_story.gd")

var failures := 0
var checks := 0
var main: Control


func _ready() -> void:
	_cleanup()
	Game.save_path = "user://test_journal_tabs.json"
	Game.meta_path = "user://test_journal_tabs_meta.json"
	Game.memory_path = "user://test_journal_tabs_memory.md"
	Game.no_save = true
	Game.meta = State.new_meta()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(8)
	Game.new_game("scholar", "normal", [], [], [], false, false)
	await frames(12)
	await run()
	check_notebook_pages()
	await check_notebook_window()
	print("劫余录分页：%d 项，失败 %d" % [checks, failures])
	_cleanup()
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames(count := 4) -> void:
	for k in count:
		await get_tree().process_frame


func journal() -> Node:
	return main._modals.get("journal")


## 当前页里看得见的按钮文字（页签和「合上」不算入口）。
func visible_entries() -> Array:
	var out := []
	var m := journal()
	if m == null:
		return out
	for b in m.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree():
			continue
		if b.has_meta("journal_tab") or b.text == "合上":
			continue
		out.append(b.text)
	return out


func entry(prefix: String) -> Button:
	var m := journal()
	if m == null:
		return null
	for b in m.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.begins_with(prefix):
			return b
	return null


func tab(id: String) -> Button:
	var m := journal()
	if m == null:
		return null
	for b in m.find_children("*", "Button", true, false):
		if b.has_meta("journal_tab") and str(b.get_meta("journal_tab")) == id:
			return b
	return null


func open() -> void:
	Dialogs.journal()
	await frames(6)


func run() -> void:
	await open()
	check(journal() != null, "劫余录没打开")

	# 三个页签
	check(tab("now") != null and tab("people") != null and tab("past") != null, "少了页签")
	check(tab("now").text == "今世" and tab("people").text == "人" and tab("past").text == "前世", "页签文字不是今世 / 人 / 前世")

	# 第一日：今世页只有三个入口
	var now_entries := visible_entries()
	check(now_entries.size() == 3, "今世页可见入口应为 3 个，实际 %d 个：%s" % [now_entries.size(), str(now_entries)])
	check(entry("尸劫来历") != null, "今世页缺「尸劫来历」")
	check(entry("风声与危机") != null, "今世页缺「风声与危机」")
	check(entry("这一世的开局") != null, "今世页缺「这一世的开局」")

	# 另外两页的入口此时不该露出来
	check(entry("邻里事务") == null, "「人」页的入口漏进了今世页")
	check(entry("轮回调查") == null, "「前世」页的入口漏进了今世页")

	# 翻到「人」
	tab("people").pressed.emit()
	await frames(3)
	var people_entries := visible_entries()
	check(people_entries.size() == 3, "「人」页可见入口应为 3 个，实际 %d 个：%s" % [people_entries.size(), str(people_entries)])
	check(entry("邻里事务") != null, "「人」页缺「邻里事务」")
	check(entry("纸鹤往来") != null, "「人」页缺「纸鹤往来」")
	check(entry("邻人与商情") != null, "「人」页缺「邻人与商情」")
	check(entry("尸劫来历") == null, "翻到「人」页后今世页的入口还看得见")

	# 翻到「前世」
	tab("past").pressed.emit()
	await frames(3)
	var past_entries := visible_entries()
	check(past_entries.size() == 3, "「前世」页可见入口应为 3 个，实际 %d 个：%s" % [past_entries.size(), str(past_entries)])
	check(entry("身份与前世") != null, "「前世」页缺「身份与前世」")
	check(entry("轮回调查") != null, "「前世」页缺「轮回调查」")
	check(entry("前世记忆") != null, "「前世」页缺「前世记忆」")

	# 关掉再开：回到「今世」，不从上次那一页起
	main.close_modal("journal")
	await frames(3)
	await open()
	check(entry("尸劫来历") != null and entry("轮回调查") == null, "重新打开没有回到今世页")


func check_notebook_pages() -> void:
	var sample := {"phase":"pre", "t":0, "pday":1}
	check(Notebook.pages(sample).is_empty() and sample.size() == 3, "没有故事字段的旧卷不应生出手记")
	sample["flags"] = {"rice_story_stage":"paper", Ticket.KEY:"fold"}
	var pages := Notebook.pages(sample)
	check(pages.size() == 2 and "书肆" in pages[0].next and "回春堂" in pages[1].next, "备劫的两件旧物没留下去向")
	check("气血" not in str(pages) and "两副担架" not in str(pages) and "灯油" not in str(pages), "起手线索泄露结局")
	sample.phase = "post"
	pages = Notebook.pages(sample)
	check(pages[0].next == "" and "纸鹤" in pages[1].next, "灾后手记还催去已关张的铺子")
	for lesson: String in ["carry", "marks"]:
		sample.flags["rice_story_stage"] = lesson
		sample.flags.erase("rice_story_echo")
		check("旧账" in Notebook.pages(sample)[0].next, "学艺后没留下旧账线索")
		sample.flags["rice_story_echo"] = true
		var note := str(Notebook.pages(sample)[0].note)
		check(("我挑小担" in note) == (lesson == "carry") and ("今儿轮到我送" in note) == (lesson == "marks"), "燕尾担误记了另一种回响")
	for step: String in ["signed", "kept", "sent", "replied", "unsigned"]:
		sample.flags[Ticket.KEY] = step
		sample.flags[Ticket.REPLY_DAY] = 6
		var drug := Notebook.pages(sample)[1]
		check((drug.next != "") == (step in ["signed","sent"]), "药签待办错误：" + step)
		if step == "sent":
			check("6 日" in drug.next and "灯油" not in drug.note, "送药后误报回礼或回信日期")
		if step == "kept":
			check("捎回家" in drug.note and "担架" not in drug.note, "领药后误记渡口回信")
	sample["mainline"] = {}
	sample.t = 12 * 1440 + 120
	check(Notebook.pages(sample).size() == 2, "还没点过灯就泄露了船家")
	sample.mainline.lane_lantern = {"stage":"lit", "reply_t":sample.t + 1440}
	check("08:00" in Notebook.pages(sample).back().next and "娘走不动了" not in str(Notebook.pages(sample)), "船家未回信就预告求住")
	sample.t += 1440
	check("娘走不动了" not in str(Notebook.pages(sample)), "时辰到了却还未收到的内容提前揭示")
	sample.mainline.lane_lantern.notified = true
	check("娘走不动了" in Notebook.pages(sample).back().next, "已收到的船信无法重读")
	sample.mainline.lane_lantern = {"stage":"ferry"}
	check("渡船已过河" in Notebook.pages(sample).back().note and Notebook.pages(sample).back().next == "", "修船这一笔没有收尾")
	sample["supply_trails"] = {"school":{"status":"marked"},"lumber":{"status":"open","remaining":{"nails":2}},"pharmacy_ruin":{"status":"kept"}}
	var saved := JSON.stringify(sample)
	pages = Notebook.pages(sample)
	check(pages.size() == 6 and "义庄" in pages[2].next and pages[3].next == "" and "铁钉" in pages[4].next, "三路旧运单的取舍或余货错误")
	check(JSON.stringify(sample) == saved and Notebook.pages(JSON.parse_string(saved)) == pages, "重读或旧卷载入改变了状态")
	sample.supply_trails.school.status = "found"
	sample.pday = 19
	check("沦陷" in Notebook.pages(sample)[2].note and Notebook.pages(sample)[2].next == "", "已沦陷的源头仍被当作可去")
	sample.supply_trails.school.status = "empty"
	check("最后一件" in Notebook.pages(sample)[2].note and Notebook.pages(sample)[2].next == "", "取空后仍有领取提示")


func click_text(root: Control, caption: String) -> bool:
	for b: Button in root.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree() or (b.text != caption and b.tooltip_text != caption):
			continue
		var parent := b.get_parent()
		while parent:
			if parent is ScrollContainer:
				parent.ensure_control_visible(b)
				await frames()
			parent = parent.get_parent()
		var at := b.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = at
		get_viewport().push_input(motion)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.position = at
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			get_viewport().push_input(click)
			await frames(1)
		await frames()
		return true
	check(false, "窗口里找不到按钮：" + caption)
	return false


func check_notebook_window() -> void:
	check(entry("旧物手记") == null, "空卷露出了手记")
	main.close_modal("journal")
	Game.speed = 0
	Game.run.loc = "pharmacy"
	check(Ticket.act(Game.run, "unfold") == "", "没能从药铺收下真实药签")
	if not await click_text(main._screen.hud, "劫余录"): return
	if not await click_text(journal(), "旧物手记"): return
	check(main.has_modal("story_notebook"), "备劫地图打不开手记")
	if not main.has_modal("story_notebook"): return
	if not await click_text(main._modals.story_notebook, "合上"): return
	if not await click_text(journal(), "合上"): return
	while Game.run.phase == "pre":
		Pre.end_day(Game.run)
	Game.run.dawn_due = false
	Game.run.plan_due = false
	Game.run.flags.rice_story_stage = "marks"
	Game.run.flags.rice_story_echo = true
	Game.go("post")
	await frames(10)
	if not await click_text(main._screen.hud, "劫余录"): return
	var snapshot := Game.run.duplicate(true)
	if not await click_text(journal(), "旧物手记"): return
	var book: Control = main._modals.get("story_notebook")
	check(is_instance_valid(book), "宅院里打不开手记")
	if not is_instance_valid(book): return
	var first := ""
	for label: Label in book.find_children("*","Label",true,false):
		if label.is_visible_in_tree(): first += label.text
	check("纸鹤" in first and "今儿轮到我送" not in first, "待办线索没有优先翻开")
	if not await click_text(book, "燕尾担"): return
	Game.refresh()
	await frames()
	var second := ""
	for label: Label in book.find_children("*","Label",true,false):
		if label.is_visible_in_tree(): second += label.text
	check("今儿轮到我送" in second and "纸鹤" not in second, "翻页或重画后串入另一件旧物")
	check(Game.run == snapshot, "翻阅手记变更了局面")
	var image_path := OS.get_environment("STORY_NOTEBOOK_SHOT")
	if image_path != "":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(image_path) == OK, "手记实机截图未保存")
	if not await click_text(book, "合上"): return
	check(main.has_modal("journal") and not main.has_modal("story_notebook"), "合上手记没有回到日志")


func _cleanup() -> void:
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
