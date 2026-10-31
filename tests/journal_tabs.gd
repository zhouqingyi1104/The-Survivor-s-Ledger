extends Node
## 劫余录分页：第一日打开只看见「今世」那一页的三个入口，翻页才看见其余的。
## 运行：godot --headless --path . res://tests/journal_tabs.tscn
##
## 这一条是路线图 B2 的验收标准（第 1 日可见入口 ≤ 3 个）的落地版：
## 分页的意义是让玩家打开就知道先看哪，所以入口不能又摊回一屏。

const State = preload("res://scripts/core/state.gd")

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


func _cleanup() -> void:
	for path in [Game.save_path, Game.meta_path, Game.memory_path]:
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
