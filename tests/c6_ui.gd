extends Node
## Real C6 viewport interactions. Launch with isolated APPDATA and LOCALAPPDATA.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Director = preload("res://scripts/core/director.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const NeighborHome = preload("res://scripts/core/neighbor_home.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Floors = preload("res://scripts/core/home_floor.gd")

var main: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("C6 UI: " + message)
	return ok

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func click(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(4)

func key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
	await frames(4)

func button(prefix: String, root: Node) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.text.begins_with(prefix): return b
	return null

func pick_spot(target: Vector3, id: String) -> Vector2:
	var screen: Control = main._screen
	var center: Vector2 = screen.rig.cam.unproject_position(target)
	var bounds := get_viewport().get_visible_rect().grow(-10)
	for dx in range(-60, 61, 4):
		for dy in range(-60, 61, 4):
			var p := center + Vector2(dx, dy)
			if bounds.has_point(p) and str(screen.world.pick(screen.rig.cam, p).get("spot", "")) == id: return p
	return Vector2(-1, -1)

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func open_spot(id: String) -> bool:
	var screen: Control = main._screen
	var info: Dictionary = screen._spot_info(id)
	if not check(not info.is_empty(), "缺少入口 " + id): return false
	screen.rig.snap()
	await frames(10)
	var p := pick_spot(info.tag, id)
	if not check(p.x >= 0, "入口不可物理拾取 " + id): return false
	await click(p)
	return check(screen._menu.visible, "点击入口未打开菜单 %s at %s" % [id, str(p)])

func choose(prefix: String) -> bool:
	var screen: Control = main._screen
	var b := button(prefix, screen._menu)
	if not check(b != null and not b.disabled, "缺少可用菜单 " + prefix): return false
	await click(b.get_global_rect().get_center())
	var until := Time.get_ticks_msec() + 12000
	while screen.player.is_walking() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await frames(10)
	return true

func shot(name: String) -> void:
	var directory := OS.get_environment("C6_SHOT_DIR")
	if directory == "": return
	await get_tree().create_timer(1.0).timeout
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func action_button(id: String) -> Button:
	if not main.has_modal("neighbor_home"): return null
	for b in main._modals["neighbor_home"].find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and str(b.get_meta("neighbor_home_action", "")) == id: return b
	return null

func modal_text() -> String:
	if not main.has_modal("neighbor_home"): return ""
	var out := ""
	for label in main._modals["neighbor_home"].find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): out += label.text + "\n"
	return out

func reset_fixture() -> void:
	# A preceding fixture may have opened an unrelated 08:00 event. The entire
	# run is replaced below, so its modal must not leak into the next fixture.
	for modal_id in main._modals.keys(): main.close_modal(str(modal_id))
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 622)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	Game.run.neighbor = Neighbor.fresh()
	Game.run.neighbor.stage = "closed"
	Game.run.pday = 2
	Game.run.t = Post.DAY + 240 # Day 2, 10:00.
	Game.run.home.wood = 10
	Game.run.home.nails = 10
	Game.run.home.rice = 10
	Game.run.attrs.energy = 100
	Game.run.rebirths_left = 1
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	Game.refresh()
	await frames(15)
	var screen: Control = main._screen
	screen.player.stop()
	# Frame the entrance inside the uncovered central viewport, while retaining
	# enough distance to verify that the interaction actually walks to the wall.
	screen.player.global_position = Vector3(-7.0, 0, 3.6)
	screen.rig.snap()
	await frames(10)

func open_neighbor() -> bool:
	if not await open_spot("neighbor_home"): return false
	if not await choose("敲门 · 隔墙交谈"): return false
	return check(main.has_modal("neighbor_home"), "隔墙交谈未打开")

func choose_action(id: String) -> bool:
	var b := action_button(id)
	if not check(b != null and not b.disabled, "选项不可用 " + id): return false
	var scroll: ScrollContainer
	var ancestor: Node = b.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	if scroll != null:
		for i in 80:
			if scroll.get_global_rect().has_point(b.get_global_rect().get_center()): break
			for down in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
				ev.position = scroll.get_global_rect().get_center()
				ev.pressed = down
				get_viewport().push_input(ev)
			await frames(2)
	if not check(get_viewport().get_visible_rect().has_point(b.get_global_rect().get_center()) and (scroll == null or scroll.get_global_rect().has_point(b.get_global_rect().get_center())), "选项无法滚动到可见区域 " + id): return false
	await click(b.get_global_rect().get_center())
	await frames(10)
	return check(not main.has_modal("neighbor_home"), "选择后对话未关闭 " + id)

func settle_at_boundary() -> void:
	# Place the test at the last minute of the next-day boundary; actual polling
	# still runs via Post.advance. Night and dawn are covered by the core tests.
	var due := int(NeighborHome.view(Game.run).due_t)
	Game.run.t = due - 1
	Game.run.pday = int(Game.run.t) / Post.DAY + 1
	Post.advance(Game.run, 1)
	Game.refresh()
	await frames(15)

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://c6_ui_save.json"
	Game.meta_path = "user://c6_ui_meta.json"
	Game.memory_path = "user://c6_ui_memory.md"
	Game.speed = 0
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 622)
	Pre.start_disaster(Game.run)
	Game.screen = "post"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(240).timeout.connect(func(): get_tree().quit(1))
	await frames(40)

	# First visit must be an actual pick + click + walk, then bind the person.
	await reset_fixture()
	var screen: Control = main._screen
	check(str(screen.world.spot_info("neighbor_home").get("name", "")) == "西邻院墙", "相认前不应显示人物住址")
	await shot("courtyard_unmet")
	screen.player.global_position = Vector3(-4, 0, 3.6)
	screen.rig.snap()
	await frames(10)
	var start: Vector3 = screen.player.global_position
	var hud_entry: Button
	for b in screen.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and bool(b.get_meta("neighbor_home_entry", false)): hud_entry = b; break
	if not check(hud_entry != null and not hud_entry.disabled, "缺少西邻 HUD 入口"): get_tree().quit(1); return
	await click(hud_entry.get_global_rect().get_center())
	var until := Time.get_ticks_msec() + 12000
	while screen.player.is_walking() and Time.get_ticks_msec() < until: await get_tree().process_frame
	await frames(10)
	if not check(main.has_modal("neighbor_home"), "HUD 入口没有走到西邻打开交谈"): get_tree().quit(1); return
	var stand: Vector3 = screen.world.spot_info("neighbor_home").stand
	check(flat(start, screen.player.global_position) > 1.0 and flat(screen.player.global_position, stand) < 1.2, "交谈没有实际走到邻墙")
	check(NeighborHome.view(Game.run).knocked and str(screen.world.spot_info("neighbor_home").name).contains("老周"), "相认后没有绑定地点")
	await key(KEY_ESCAPE)
	if not await open_neighbor(): get_tree().quit(1); return
	var text := modal_text()
	check(text.contains("老周") and text.contains("明日") and text.contains("木料 ×2") and text.contains("铁钉 ×1") and text.contains("60 分钟") and text.contains("米 1"), "对话缺少人物、时限或选择成本")
	check(action_button("repair") != null and action_button("trade") != null and action_button("refuse") != null, "对话缺少三个选项")
	await shot("request")
	await key(KEY_ESCAPE)
	await shot("wall_before")
	if not await open_neighbor(): get_tree().quit(1); return
	var before_wood := int(Game.run.home.wood)
	var before_nails := int(Game.run.home.nails)
	var before_energy := float(Game.run.attrs.energy)
	var before_trust := int(Trade.contact(Game.run, "zhou").trust)
	if not await choose_action("repair"): get_tree().quit(1); return
	check(int(Game.run.home.wood) == before_wood - 2 and int(Game.run.home.nails) == before_nails - 1 and float(Game.run.attrs.energy) == before_energy - 6, "施工材料或精力扣除不符")
	check(str(Game.run.busy.get("kind", "")) == "neighbor_wall" and int(Game.run.busy.end) - int(Game.run.busy.start) == 60 and not NeighborHome.view(Game.run).wall_repaired, "施工未占用真实时间或提前完工")
	var before_t := int(Game.run.t)
	Post.advance(Game.run, 59)
	Game.refresh()
	await frames(10)
	check(int(Game.run.t) == before_t + 59 and not NeighborHome.view(Game.run).wall_repaired, "未满 60 分钟时修墙提前完成")
	Post.advance(Game.run, 1)
	Game.refresh()
	await frames(10)
	check(int(Game.run.t) == before_t + 60 and NeighborHome.view(Game.run).wall_repaired and NeighborHome.view(Game.run).choice == "repair", "满 60 分钟后未完成修墙")
	check(int(Trade.contact(Game.run, "zhou").trust) == before_trust and not NeighborHome.view(Game.run).settled, "次日之前错误结算信任")
	check(screen.world._neighbor_visual.get_child_count() >= 3, "完成施工后邻宅墙板未出现")
	await shot("repaired")
	var saved: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	check(bool(saved.ok), "修墙存档失败")
	await settle_at_boundary()
	check(NeighborHome.view(Game.run).settled and int(Trade.contact(Game.run, "zhou").trust) == before_trust + 2, "次日修墙关系未结算")
	check(screen.world._neighbor_visual.get_child_count() >= 4, "次日结果标记未出现")
	# The synthetic 08:00 boundary may also generate an unrelated event. Remove
	# that fixture-only modal before capturing the actual neighbor result.
	Game.run.pending_event = ""
	if main.has_modal("event"): main.close_modal("event")
	await frames(10)
	await shot("settled")
	check(Game.continue_game(), "恢复修墙存档失败")
	await frames(15)
	check(NeighborHome.view(Game.run).wall_repaired and not NeighborHome.view(Game.run).settled, "恢复存档未恢复修墙及待结算状态")
	Game.rewind()
	await frames(15)
	check(not NeighborHome.view(Game.run).knocked and int(Game.run.home.wood) == before_wood, "回溯未恢复互动前及材料")

	# Separate real-click fixture for trade: NPC working stock is authoritative.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	var stock: Dictionary = Npcs.state(Game.run).actors.zhou.stock
	var own_rice := int(Game.run.home.rice)
	var own_wood := int(Game.run.home.wood)
	var npc_rice := int(stock.rice)
	var npc_wood := int(stock.wood)
	before_trust = int(Trade.contact(Game.run, "zhou").trust)
	if not await choose_action("trade"): get_tree().quit(1); return
	check(int(Game.run.home.rice) == own_rice - 1 and int(Game.run.home.wood) == own_wood + 1 and int(stock.rice) == npc_rice + 1 and int(stock.wood) == npc_wood - 1, "换物未同步双方真实库存")
	check(not NeighborHome.view(Game.run).wall_repaired and int(Trade.contact(Game.run, "zhou").trust) == before_trust, "换物错误补墙或提前改变关系")
	await settle_at_boundary()
	check(NeighborHome.view(Game.run).settled and int(Trade.contact(Game.run, "zhou").trust) == before_trust + 1, "换物次日关系未结算")
	Game.run.pending_event = ""
	if main.has_modal("event"): main.close_modal("event")
	if await open_neighbor():
		check(modal_text().contains("实物交换"), "换物后的次日结果未显示")
		await key(KEY_ESCAPE)

	# Refusal is a real option and does not spend anything or mark a breach.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	var home_before: Dictionary = Game.run.home.duplicate(true)
	var contact_before: Dictionary = Trade.contact(Game.run, "zhou")
	if not await choose_action("refuse"): get_tree().quit(1); return
	check(Game.run.home == home_before and not NeighborHome.view(Game.run).wall_repaired, "拒绝不应消耗物资或修墙")
	await settle_at_boundary()
	var after: Dictionary = Trade.contact(Game.run, "zhou")
	check(NeighborHome.view(Game.run).settled and int(after.trust) == int(contact_before.trust) - 1 and int(after.breaches) == int(contact_before.breaches), "拒绝后的关系或失约不符")
	Game.run.pending_event = ""
	if main.has_modal("event"): main.close_modal("event")
	if await open_neighbor():
		check(modal_text().contains("没有答应"), "拒绝后的次日结果未显示")
		await key(KEY_ESCAPE)

	# Insufficient own materials or NPC stock are shown disabled in the actual dialog.
	await reset_fixture()
	Game.run.home.wood = 0
	Npcs.state(Game.run).actors.zhou.stock.wood = 0
	if not await open_neighbor(): get_tree().quit(1); return
	check(action_button("repair") != null and action_button("repair").disabled, "缺材料仍可修墙")
	check(action_button("trade") != null and action_button("trade").disabled, "老周缺货仍可换物")
	check(action_button("refuse") != null and not action_button("refuse").disabled, "缺货时拒绝被错误禁用")
	await key(KEY_ESCAPE)

	# A decision in the last valid minute succeeds through the actual dialog.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	Game.run.t = int(NeighborHome.view(Game.run).deadline_t) - 1
	Game.run.pday = int(Game.run.t) / Post.DAY + 1
	if not await choose_action("refuse"): get_tree().quit(1); return
	check(str(NeighborHome.view(Game.run).choice) == "refuse", "最后一分钟的有效选择未被接受")

	# Stale dialog cannot bypass the exact deadline even if it was left open.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	var deadline := int(NeighborHome.view(Game.run).deadline_t)
	Game.run.t = deadline - 1
	Game.run.pday = int(Game.run.t) / Post.DAY + 1
	var refused := action_button("refuse")
	check(refused != null and not refused.disabled, "期限前没有可选择的拒绝")
	Post.advance(Game.run, 1)
	Game.refresh()
	await frames(10)
	check(str(NeighborHome.view(Game.run).choice) == "timeout", "期限到达未形成超时")
	var timeout_home: Dictionary = Game.run.home.duplicate(true)
	if refused != null:
		await click(refused.get_global_rect().get_center())
	check(str(NeighborHome.view(Game.run).choice) == "timeout" and Game.run.home == timeout_home, "过期的对话按钮覆盖了超时结果")
	if main.has_modal("neighbor_home"): main.close_modal("neighbor_home")

	# A fight checkpoint interrupts an already started job and refunds its paid materials.
	# The clock/job end are deliberately placed around the checkpoint as an adversarial
	# fixture; starting a new repair at night is forbidden by the public UI.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	before_wood = int(Game.run.home.wood)
	before_nails = int(Game.run.home.nails)
	if not await choose_action("repair"): get_tree().quit(1); return
	Game.run.t = Post.RAID_AT - 1
	Game.run.pday = 1
	Game.run.busy.start = Post.RAID_AT - 30
	Game.run.busy.end = Post.RAID_AT + 30
	Game.run.raid_tonight = true
	screen.advance(1)
	await frames(15)
	check(Game.run.busy.is_empty() and not NeighborHome.view(Game.run).wall_repaired and int(Game.run.home.wood) == before_wood and int(Game.run.home.nails) == before_nails, "夜袭中断未退材料或错误完成修墙")

	# A courtyard collision cannot be reached through the C5 interior floors.
	for room in ["cellar", "attic"]:
		await reset_fixture()
		Game.run.facilities.append("cellar")
		Game.run.attic = {"stage": "complete"}
		Game.run.home_floor = room
		Game.refresh()
		await frames(20)
		check(Floors.current(Game.run) == room and screen.world._floor == room and not screen.world._spot_on_floor("neighbor_home") and screen.world.spot_info("neighbor_home").is_empty(), room + " 中仍可访问院墙入口")

	# Reach the guest room through the actual courtyard gate after recognition.
	await reset_fixture()
	if not await open_neighbor(): get_tree().quit(1); return
	await key(KEY_ESCAPE)
	Game.snapshots = {}
	Ledger.snapshot(Game.run, Game.snapshots)
	screen.player.global_position = Vector3(0, 0, 5.8)
	screen.rig.snap()
	await frames(10)
	if not await open_spot("gate"): get_tree().quit(1); return
	if not await choose("拜访老周家"): get_tree().quit(1); return
	check(Floors.current(Game.run) == "guest_zhou" and screen.world._floor == "guest_zhou", "从自家院门未进入老周家")
	check(not screen.world._spot_on_floor("neighbor_home") and screen.world.spot_info("floor_use").is_empty() and screen.actions_for("floor_use").is_empty(), "访客空间错误开放自家存货或隔墙入口")
	var guest_home: Dictionary = Game.run.home.duplicate(true)
	Dialogs.inventory()
	await frames(5)
	check(not main.has_modal("inventory") and Game.run.home == guest_home, "访客空间能够打开或使用自家存货")
	check(Post.can_act(Game.run) != "" and screen.actions_for("f_1").is_empty(), "访客空间仍能操作自家家具")
	await shot("guest_before")
	if not await open_spot("guest_talk"): get_tree().quit(1); return
	if not await choose("与老周交谈"): get_tree().quit(1); return
	check(main.has_modal("neighbor_home") and modal_text().contains("老周在自己家中") and action_button("repair") == null and action_button("trade") == null and action_button("refuse") == null, "访客对话未显示老周或越权提供院墙行动")
	await shot("guest_talk")
	await key(KEY_ESCAPE)
	var guest_save: Dictionary = SaveFile.write(Game.save_path, {"run": Game.run, "snapshots": Game.snapshots})
	check(bool(guest_save.ok) and Game.continue_game(), "老周家存读失败")
	await frames(20)
	check(Floors.current(Game.run) == "guest_zhou" and screen.world._floor == "guest_zhou", "读档未恢复白天访客空间")
	if not await open_spot("floor_exit"): get_tree().quit(1); return
	if not await choose("返回宅院"): get_tree().quit(1); return
	check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard", "老周家出口未回到自家院内")
	# Complete the actual wall work and re-enter at the same spawn/camera as the
	# earlier guest screenshot, allowing a direct visual before/after check.
	screen.player.global_position = Vector3(-7, 0, 3.6)
	screen.rig.snap()
	await frames(10)
	if not await open_neighbor(): get_tree().quit(1); return
	if not await choose_action("repair"): get_tree().quit(1); return
	Post.advance(Game.run, 60)
	Game.refresh()
	await frames(15)
	check(NeighborHome.view(Game.run).wall_repaired, "访客对照前的修墙未实际完成")
	screen.player.global_position = Vector3(0, 0, 5.8)
	screen.rig.snap()
	await frames(10)
	if not await open_spot("gate"): get_tree().quit(1); return
	if not await choose("拜访老周家"): get_tree().quit(1); return
	check(Floors.current(Game.run) == "guest_zhou" and screen.world._floor_rooms.guest_zhou.repaired_wall.visible, "修好后老周屋内墙板未显示")
	await shot("guest_after")
	check(Game.continue_game(), "恢复访客存档失败")
	await frames(20)
	Game.rewind()
	await frames(20)
	check(Floors.current(Game.run) == "courtyard" and screen.world._floor == "courtyard" and NeighborHome.view(Game.run).knocked, "访客回溯未回院或丢失此前相认")
	check(Game.continue_game(), "恢复访客存档以测试天黑失败")
	await frames(20)
	Game.run.t = Post.DAY + Post.DUSK_AT - 1
	Game.run.pday = 2
	screen.advance(1)
	await frames(20)
	check(int(Game.run.t) == Post.DAY + Post.DUSK_AT and str(Game.run.home_floor) == "courtyard" and screen.world._floor == "courtyard", "18:00 未按实际时钟安全回院")
	check(Game.continue_game(), "恢复访客存档以测试夜袭失败")
	await frames(20)
	# Adversarial stale room fixture: a loaded/edited state jumps to the raid
	# boundary, which must still move the player back before combat starts.
	Game.run.t = Post.RAID_AT - 1
	Game.run.pday = 1
	Game.run.raid_tonight = true
	screen.advance(1)
	await frames(20)
	check(str(Game.run.home_floor) == "courtyard" and screen.world._floor == "courtyard" and flat(screen.player.global_position, screen.world.floor_spawn("courtyard")) < 1.0, "夜袭时未将访客安全移回自家院内")
	SaveFile.forget(Game.save_path)
	SaveFile.forget(Game.meta_path)
	print("C6 viewport: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
