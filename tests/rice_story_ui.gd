extends Node
## 同一角色在城中用鼠标学艺；灾后将其放到现场标志旁，用交互键读原线索。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const RiceStory = preload("res://scripts/core/rice_story.gd")

var main: Control
var checks := 0


func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 5103)
	Game.go("pre")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames()
	if not await discover(): return
	if not await study(): return
	if not await revisit(): return
	main.queue_free()
	await frames()
	print("[rice_story_ui] checks=%d failures=0" % checks)
	get_tree().quit()


func discover() -> bool:
	if not await click(named(main._screen.hud, "备荒杂事"), "打开备荒杂事"): return false
	if not await click(find_button(modal("prep_work"), "prep_work_travel", "rice_shop"), "前往米行"): return false
	await arrive()
	if not check(action("prep_work", "inspect") == null, "卸粮之前已经露出扁担"): return false
	if not await click(find_button(modal("prep_work"), "prep_work_action", "rice_shop"), "帮米行卸粮"): return false
	var hour := int(Game.run.hour)
	if not await click(action("prep_work", "inspect"), "当场翻看短扁担"): return false
	if not check(RiceStory.stage(Game.run) == "paper" and int(Game.run.hour) == hour, "翻扁担未找到纸条或另扣时辰"): return false
	if not check(text_in("rice_story_paper").contains("书肆"), "纸条没指出可以拜访的铺子"): return false
	record_window("paper")
	if not await click(named(modal("rice_story_paper"), "合上"), "收起纸条"): return false
	if not await click(named(modal("prep_work"), "合上"), "合上杂事簿"): return false
	if not await click(named(main._screen.hud, "米行（在此）"), "回米行柜台"): return false
	if not await click(action("shop", "paper"), "在柜台重读纸条"): return false
	if not check(action("shop", "inspect") == null and int(Game.run.hour) == hour, "重读竟然重复触发"): return false
	if not await click(named(modal("rice_story_paper"), "合上"), "收起重读的纸条"): return false
	return await click(named(modal("shop"), "合上"), "离开米行")


func study() -> bool:
	if not await click(named(main._screen.hud, "书肆"), "去书肆"): return false
	await arrive()
	if not await click(action("shop", "book"), "递给掌柜"): return false
	var terms := text_in("rice_story_book").replace(" ", "")
	if not check(terms.contains("1个时辰") and terms.contains("气血") and terms.contains("+5") and terms.contains("搜寻") and terms.contains("+10"), "选课前看不到耗时和两种收益"): return false
	if not check(action("rice_story_book", "carry") != null, "学挑担入口缺失"): return false
	record_window("lessons")
	var hour := int(Game.run.hour)
	var experience := int(Game.run.prof.search)
	var hp_max := State.attr_max(Game.run, "hp")
	# 先合上再找掌柜，确认可以留到以后再学。
	if not await click(named(modal("rice_story_book"), "合上"), "暂不选课"): return false
	if not check(RiceStory.stage(Game.run) == "paper" and int(Game.run.hour) == hour, "暂不选课也消耗了机会"): return false
	if not await click(action("shop", "book"), "再找掌柜"): return false
	if not await click(action("rice_story_book", "marks"), "认燕尾记"): return false
	if not check(RiceStory.stage(Game.run) == "marks" and int(Game.run.hour) == hour + 1 and int(Game.run.prof.search) == experience + 10 and State.attr_max(Game.run, "hp") == hp_max, "认燕尾记未按预告结算"): return false
	if not check(text_in("rice_story_book").contains("搜寻") and not text_in("rice_story_book").contains("气血上限"), "课后回执没有区分所选本领"): return false
	if not await click(named(modal("rice_story_book"), "合上"), "收起回执"): return false
	if not await click(action("shop", "book"), "重访掌柜"): return false
	if not check(action("rice_story_book", "marks") == null and action("rice_story_book", "carry") == null and int(Game.run.prof.search) == experience + 10, "重访还能再领一课"): return false
	return true


func revisit() -> bool:
	var run: Dictionary = Game.run
	Pre.start_disaster(run)
	# 跳过日常循环，将赴现场的时间置于晨间事件之后，避免不相干的随机弹窗。
	run.t = Post.EVENT_AT
	if not check(Post.act_explore(run, "rice_ruin") == "", "没能出门去废弃米行"): return false
	Game.go("explore")
	await frames()
	# 第二条线索「仓边木牌」先读；回响只能长在旧账簿上。
	if not await inspect_feature("clue_1"): return false
	if not check(text_in("expedition").contains("仓边木牌") and action("expedition", "echo") == null, "木牌不该显示封底"): return false
	if not await click(named(modal("expedition"), "先离开"), "合上木牌"): return false
	if not await inspect_feature("clue_0"): return false
	if not check(text_in("expedition").contains("残缺账簿") and not RiceStory.heard_echo(run), "看原线索时应由玩家决定是否翻封底"): return false
	var minutes := int(run.t)
	var progress := Expedition.state(run).duplicate(true)
	var bag: Dictionary = run.explore.bag.duplicate(true)
	if not await click(action("expedition", "echo"), "翻账簿封底"): return false
	var ending := RiceStory.echo_text(run)
	if not check(RiceStory.heard_echo(run) and not ending.is_empty() and text_in("expedition").contains(ending), "未显示对应本领的回响"): return false
	if not check(int(run.t) == minutes and run.explore.bag == bag and Expedition.state(run) == progress, "回响意外改变了机关、背囊或时间"): return false
	record_window("ledger")
	if not await click(named(modal("expedition"), "先离开"), "收起账簿"): return false
	if not await inspect_feature("clue_0"): return false
	if not check(text_in("expedition").contains(ending) and int(run.t) == minutes, "重读账簿未保留回响或重复扣时"): return false
	if not await click(named(modal("expedition"), "先离开"), "离开账簿"): return false
	if not await inspect_feature("gate"): return false
	if not check(action("expedition", "echo") == null, "机关题面泄露账簿彩蛋"): return false
	if not await click(find_button(modal("expedition"), "expedition_choice", "west"), "拨西仓栓"): return false
	return check(Expedition.state(run).unlocked, "读完故事后原粮栅机关无法打开")


func inspect_feature(id: String) -> bool:
	var screen: Control = main._screen
	screen.player.position = screen.world.feature_positions[id]
	await frames()
	if not check(screen._near_feature == id, "站在标志旁未显示交互：" + id): return false
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = down
		get_viewport().push_input(event)
		await frames()
	return check(main.has_modal("expedition"), "交互键未打开现场：" + id)


func modal(id: String) -> Control:
	return main._modals.get(id)


func action(window: String, id: String) -> Button:
	return find_button(modal(window), "rice_story_action", id)


func named(scope: Node, caption: String) -> Button:
	return find_button(scope, "", caption)


func find_button(scope: Node, tag: String, value: String) -> Button:
	if not is_instance_valid(scope): return null
	for item in scope.find_children("*", "Button", true, false):
		if not item.is_visible_in_tree(): continue
		if (item.text if tag.is_empty() else item.get_meta(tag, "")) == value:
			return item
	return null


func text_in(window: String) -> String:
	var scope := modal(window)
	if scope == null: return ""
	var lines := PackedStringArray()
	for node in scope.find_children("*", "Control", true, false):
		if (node is Button or node is Label) and node.is_visible_in_tree():
			lines.append(node.text)
	return "\n".join(lines)


func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok:
		push_error(detail)
		get_tree().quit(1)
	return ok


func frames(n := 5) -> void:
	for frame in n:
		await get_tree().process_frame


func arrive() -> void:
	while main._screen.world.walking:
		await get_tree().process_frame
	await frames()


func click(target: Button, description: String) -> bool:
	if not check(is_instance_valid(target) and not target.disabled, "按钮不可用：" + description): return false
	var parent := target.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(target)
			await frames()
		parent = parent.get_parent()
	var center := target.get_global_rect().get_center()
	if not check(get_viewport().get_visible_rect().has_point(center), "按钮在窗口外：" + description): return false
	var motion := InputEventMouseMotion.new()
	motion.position = center
	get_viewport().push_input(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.pressed = down
		get_viewport().push_input(event)
		await frames(2)
	await frames()
	return true


func record_window(label: String) -> void:
	var directory := OS.get_environment("TEMP")
	if not directory.is_empty():
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(directory.path_join("rice-story-" + label + ".png")) == OK, "截图写入失败：" + label)
