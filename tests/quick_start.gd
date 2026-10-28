extends Node
## 快速开局（路线图 A2）：标题点一下「新开一卷」就进城备劫——默认身份、寻常年景、不立愿、不带人、普通开局；
## 有旧卷时多一次「合上旧卷」；「自选开局」仍走选身份；第一世的身份卡不提身份解法与旧世。
## 点击走真实鼠标与视口路由；存档、底稿、前世档案都落在一个临时目录，跑完整个删掉，不碰玩家档案。
## 运行（窗口模式）：godot --path . res://tests/quick_start.tscn

const State = preload("res://scripts/core/state.gd")

## 脚本错误只中止当前函数、_ready 照样往下跑：每个测试跑到底才记一次，最后对账
const TESTS := 5

var checks := 0
var failures := 0
var finished := 0
var main: Node
var dir := ""


func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	get_tree().create_timer(120).timeout.connect(func():
		push_error("快速开局测试超时")
		get_tree().quit(1))
	dir = "user://test-tmp/quick-start-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	Game.no_save = false
	StoryDirector.set_process(false)
	Game.save_path = dir + "/save.json"
	Game.meta_path = dir + "/meta.json"
	Game.memory_path = dir + "/Memory.md"
	Game.meta = State.new_meta()
	Game.run = {}
	Game.snapshots = {}
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(10)

	test_first_life_rule()
	await test_custom_first_life()
	await test_quick_no_save()
	await test_quick_with_save()
	await test_roles_after_first_life()
	check(finished == TESTS, "只跑完 %d / %d 个测试，有测试中途崩了" % [finished, TESTS])

	main.queue_free()
	await frames(4)
	_cleanup()
	print("[quick_start] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------- 一、第一世怎么算 ----------

func test_first_life_rule() -> void:
	check(State.first_life(State.new_meta()), "新底稿不算第一世")
	check(State.first_life({}), "缺字段的老底稿不算第一世")
	var settled := State.new_meta()
	settled.runs = 1
	check(not State.first_life(settled), "结算过一世还算第一世")
	var died := State.new_meta()
	died.deaths = 1
	check(not State.first_life(died), "死过一次还算第一世")
	var archived := State.new_meta()
	archived.past_lives.count = 1
	check(not State.first_life(archived), "前世档案里有一世还算第一世")
	finished += 1


# ---------- 二、自选开局：第一世的身份卡只讲眼前 ----------

func test_custom_first_life() -> void:
	check(Game.screen == "title", "开场不在标题：%s" % Game.screen)
	check(not Game.has_save(), "临时目录里不该有旧卷")
	await click(menu_button("自选开局"))
	check(Game.screen == "roles", "「自选开局」没去选身份：%s" % Game.screen)
	var text := labels_in(main._screen)
	for word in ["身份解法", "旧世", "取证"]:
		check(not text.contains(word), "第一世的身份卡出现了「%s」" % word)
	check(text.contains("落第书生") and text.contains("随身"), "身份卡的基本信息不见了")
	Game.go("title")
	await frames(6)
	finished += 1


# ---------- 三、没有旧卷：一次点击进城 ----------

func test_quick_no_save() -> void:
	check(Game.screen == "title", "没回到标题：%s" % Game.screen)
	var quick := menu_button("新开一卷")
	check(quick != null and quick.tooltip_text.contains("寻常年景") and quick.tooltip_text.contains("落第书生"),
		"「新开一卷」没说清用什么身份和难度")
	await click(quick)
	await frames(10)
	check(Game.screen == "pre", "点一次「新开一卷」没有直接进城备劫：%s" % Game.screen)
	var run: Dictionary = Game.run
	check(str(run.get("phase", "")) == "pre", "新局不在备劫阶段")
	check(Game.quick_role() == "scholar" and str(run.get("role", "")) == "scholar", "快速开局的身份不是表里第一个已解锁的")
	check(str(run.get("difficulty", "")) == "normal", "快速开局不是寻常年景")
	var tally: Dictionary = State.tally(run)
	for key in ["goals", "vows", "boons"]:
		check((tally.get(key, []) as Array).is_empty(), "快速开局带上了%s" % key)
	check((run.get("companions", []) as Array).is_empty(), "快速开局带了同院的人")
	check(str(run.get("opening", {}).get("choice", "")) == "plain", "快速开局不是普通开局")
	check(not bool(run.get("endless", false)) and not run.get("flags", {}).has("daily"), "快速开局开了守到死或每日一局")
	check(FileAccess.file_exists(Game.save_path), "新局没落盘")
	finished += 1


# ---------- 四、有旧卷：确认合卷后照样直接进城 ----------

func test_quick_with_save() -> void:
	var old_life := str(Game.run.get("past_lives", {}).get("id", ""))
	Game.go("title")
	await frames(6)
	check(Game.has_save(), "上一局没留下存档")
	# 有旧卷时菜单最长（多一条「续写此录」）：每一项都得在左下角题名印章上方，不能被盖住
	var seal_top := INF
	for label in main._screen.find_children("*", "Label", true, false):
		if label.text == "尸 劫":
			seal_top = label.get_global_rect().position.y
	var lowest := ""
	var lowest_bottom := 0.0
	for b in main._screen.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.get_global_rect().end.y > lowest_bottom:
			lowest_bottom = b.get_global_rect().end.y
			lowest = b.text
	check(seal_top < INF and lowest == "退出" and lowest_bottom <= seal_top,
		"菜单最下一项「%s」下沿 %.0f 压到了题名印章（%.0f）" % [lowest, lowest_bottom, seal_top])
	await click(menu_button("新开一卷"))
	check(main.has_modal("confirm_new"), "有旧卷时没先确认合卷")
	await click(button_in(main._modals.get("confirm_new"), "合上旧卷"))
	await frames(10)
	check(Game.screen == "pre", "合上旧卷后没有直接进城：%s" % Game.screen)
	check(int(Game.meta.runs) == 1, "旧卷没结算：runs=%d" % int(Game.meta.runs))
	var new_life := str(Game.run.get("past_lives", {}).get("id", ""))
	check(old_life != "" and new_life != "" and new_life != old_life, "还是旧的那一局：%s → %s" % [old_life, new_life])
	check(str(Game.run.get("role", "")) == "scholar" and str(Game.run.get("difficulty", "")) == "normal", "第二次快速开局的默认值变了")
	finished += 1


# ---------- 五、走过一世后，身份卡才露出身份解法与旧世 ----------

func test_roles_after_first_life() -> void:
	check(not State.first_life(Game.meta), "结算过一世还算第一世")
	Game.go("roles")
	await frames(6)
	var text := labels_in(main._screen)
	check(text.contains("身份解法") and text.contains("旧世经验"), "走过一世后身份卡仍不提身份解法与旧世")
	finished += 1


# ---------- 小工具 ----------

func menu_button(text: String) -> Button:
	for b in main._screen.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == text:
			return b
	return null


func button_in(node: Node, text: String) -> Button:
	if node == null:
		return null
	for b in node.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == text:
			return b
	return null


func labels_in(node: Node) -> String:
	var lines := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			lines.append(label.text)
	return "\n".join(lines)


## 真实鼠标：先移过去，再按下、抬起，走视口的 GUI 路由，而不是直接发 pressed
func click(button: Button) -> void:
	if not check(button != null and not button.disabled, "找不到能点的按钮"):
		return
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await get_tree().process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event)
		await get_tree().process_frame
	await frames(4)


func frames(n := 6) -> void:
	for k in n:
		await get_tree().process_frame


func check(ok: bool, msg: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("断言失败：" + msg)
	return ok


func _cleanup() -> void:
	var abs_dir := ProjectSettings.globalize_path(dir)
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-tmp"))
