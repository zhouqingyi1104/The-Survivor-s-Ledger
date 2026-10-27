extends "res://scripts/ui/screens/world_screen.gd"
## 外出搜寻（3D 废墟）：提着灯笼走到发光处按 E 翻找，回到门口按 E 回家。对应原版 ExploreMap 的探索副本。

const Inv = preload("res://scripts/core/inv.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Post = preload("res://scripts/core/post.gd")
const Hud = preload("res://scripts/ui/hud_kit.gd")
const RuinWorld = preload("res://scripts/world/ruin_world.gd")
const Player = preload("res://scripts/world/player.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")
const K = preload("res://scripts/world/kit.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const InputCfg = preload("res://scripts/core/input_cfg.gd")

## 这个界面上弹的窗用夜色（main.gd 看这个）
var dark_ui := true
var player: CharacterBody3D
var rig: Node3D
var _hint: PanelContainer
var _hint_label: Label
var _near := -1
var _fleeing := false
var _acc := 0.0
var _clock: Label
var _return_button: Button
var _work_label: Label
var _work_hint := false


func build_world() -> void:
	var ex: Dictionary = Game.run.explore
	world = RuinWorld.new()
	add_child(world)
	world.setup(ex.point, ex.spots)
	player = Player.new()
	world.add_child(player)
	player.setup(Game.run.role)
	player.figure.step_sound = "step_wood"
	player.position = RuinWorld.ENTRY + Vector3(0, 0, -1.2)
	player.figure.rotation.y = PI
	K.light(player, Color("#ffb36b"), 3.2, 11.0, Vector3(0.3, 1.8, 0.3), true)
	world.player_ref = player
	rig = CamRig.new()
	rig.target = player
	rig.dist = 12.0
	rig.pitch = -56.0
	world.add_child(rig)
	rig.snap()


func build_overlay() -> void:
	_hint_label = UI.label("", 22, UI.INK)
	_hint = UI.panel(_hint_label, Color(UI.PAPER_LIGHT, 0.92))
	add_child(_hint)
	_hint.visible = false


func sync_world() -> void:
	world.sync(Game.run)
	if Game.run.explore.get("caught", false) and not _fleeing:
		_fleeing = true
		rig.shake = 1.0
		get_tree().create_timer(2.4).timeout.connect(finish)


func _process(delta: float) -> void:
	if world == null or Game.run.explore.is_empty():
		return
	var blocked := modal_open()
	if Game.run.explore.get("curfew_due", false) and not Game.run.explore.get("caught", false) and not blocked and not _fleeing and not Post.is_busy(Game.run) and not Post.blocked(Game.run):
		Game.toast.emit("天快黑透了，得赶紧回家！")
		finish()
		return
	# 废墟里时间照走（正常速度），到酉时（21:00）必须回家
	if not blocked and not _fleeing and not Post.blocked(Game.run) and Game.speed > 0:
		_acc += 4.0 * delta
		if _acc >= 1.0:
			var mins := int(_acc)
			_acc -= mins
			var busy_before := Post.is_busy(Game.run)
			var stop := Post.advance(Game.run, mins)
			if busy_before and not Post.is_busy(Game.run):
				Game.refresh()
				if Game.run.explore.is_empty(): return
			if stop == "curfew":
				Game.toast.emit("天快黑透了，得赶紧回家！")
				finish()
				return
			if stop != "":
				Game.refresh()
	if _clock != null:
		_clock.text = "%s  %s" % [Post.shichen(Game.run), Post.clock_text(Game.run)]
	if is_instance_valid(_return_button): _return_button.disabled = Post.is_busy(Game.run)
	if is_instance_valid(_work_label):
		_work_label.visible = Post.is_busy(Game.run)
		if Post.is_busy(Game.run): _work_label.text = "%s中 · 还需 %d 分钟" % [str(Game.run.busy.get("label", "调查")), maxi(0, int(Game.run.busy.get("end", 0)) - int(Game.run.t))]
	player.enabled = not blocked
	rig.input_enabled = not blocked
	player.cam_yaw = rig.yaw
	var near: int = -1 if blocked else world.nearest(player.global_position)
	if near != _near or Post.is_busy(Game.run) or _work_hint:
		_near = near
		_update_hint()
		_work_hint = Post.is_busy(Game.run)


func _update_hint() -> void:
	var ex: Dictionary = Game.run.explore
	if Post.is_busy(Game.run) and Game.run.busy.get("kind", "") == "mainline":
		_hint.visible = true
		_hint_label.text = "%s中 · 还需 %d 分钟；完成后才能继续翻找或返程。" % [str(Game.run.busy.get("label", "调查")), maxi(0, int(Game.run.busy.get("end", 0)) - int(Game.run.t))]
		_hint.reset_size()
		_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)
		return
	_hint.visible = _near != -1
	# 键位提示读 InputMap：玩家改过 interact 就显示新键，不写死 [E]
	var ek := InputCfg.first_key_name("interact")
	if _near == -2:
		_hint_label.text = "[%s] 回家（背着 %.1f 斤）" % [ek, Inv.weight(ex.bag)]
	elif _near >= 0 and _near < ex.spots.size():
		var s: Dictionary = ex.spots[_near]
		if s.done and not s.has("mainline") and not s.has("neighbor"):
			_hint_label.text = "[%s] 查看 · %s（可整理背囊）" % [ek, s.name]
		else:
			_hint_label.text = "[%s] 翻找 · %s" % [ek, s.name] if not s.done else "%s · 已经查过了" % s.name
	_hint.reset_size()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or modal_open():
		return
	# 翻找 = interact（E）或 confirm（空格），走输入动作，改键不用动这里
	if event.is_action_pressed("interact") or event.is_action_pressed("confirm"):
		if _near == -2:
			finish()
		elif _near >= 0:
			search(_near)


## 翻一处（测试也走这里）。
func search(idx: int) -> void:
	var ex: Dictionary = Game.run.explore
	if Post.is_busy(Game.run):
		Game.toast.emit("先完成眼前的工作，不能同时翻找另一处。")
		return
	if ex.is_empty() or ex.caught or idx < 0 or idx >= ex.spots.size():
		return
	var spot: Dictionary = ex.spots[idx]
	if spot.done:
		if not spot.has("mainline") and not spot.has("neighbor"):
			_open_loot(idx)
		return
	var res = Game.act(func(): return Post.search(Game.run, idx))
	if typeof(res) == TYPE_DICTIONARY and not res.is_empty():
		if str(res.get("blocked", "")) != "":
			Game.toast.emit(str(res.blocked))
			return
		if res.get("mainline", false):
			Game.toast.emit(str(res.get("text", "已开始调查，完成后再返程。")))
			_near = -99
			return
		if res.get("story", false):
			Game.toast.emit("已检视封存药柜，请选择开锁方式。" if Game.run.pending_event == "n_cabinet" else "药账已贴身收好，回宅决定去向。")
			_near = -99
			return
		Sfx.play("cloth" if res.found.is_empty() else "leather", -2.0)
		var text := "发现：" + Data.describe_items(res.found) if not res.found.is_empty() else "一无所获"
		Game.toast.emit(text)
		if res.clue != "":
			Game.toast.emit("得残卷一页！")
		# 翻找本身会推进时间，可能已经触发事件、死亡或宵禁。
		var current: Dictionary = Game.run.get("explore", {})
		if not is_inside_tree() or Game.screen != "explore" or Game.run.get("phase", "") != "post" or current.is_empty():
			return
		if not current.get("caught", false) and not current.get("curfew_due", false) and not Post.blocked(Game.run) and not modal_open():
			_open_loot(idx)
	_near = -99


## 搜过的普通容器始终可以重开；遗留物只在这次探索中保留。
func _open_loot(idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if not is_inside_tree() or Game.screen != "explore" or ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or Post.is_busy(Game.run) or Post.blocked(Game.run) or idx < 0 or idx >= ex.spots.size(): return
	var spot: Dictionary = ex.spots[idx]
	if not spot.done or spot.has("mainline") or spot.has("neighbor"): return
	UI.open_modal("explore_loot", "搜寻 · " + str(spot.name), _loot_panel.bind(idx), true, 760)


func _loot_panel(body: VBoxContainer, idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if ex.is_empty() or ex.get("caught", false) or idx < 0 or idx >= ex.spots.size():
		body.add_child(UI.label("已离开此处，无法取物。", 17))
		return
	var spot: Dictionary = ex.spots[idx]
	var loot: Dictionary = spot.get("loot", {})
	var bag: Dictionary = ex.get("bag", {})
	var left := maxf(0.0, Explore.carry(Game.run) - Inv.weight(bag))
	body.add_child(UI.label("背囊 %.1f / %.1f 斤 · 还能装 %.1f 斤" % [Inv.weight(bag), Explore.carry(Game.run), left], 19, UI.GOLD))
	body.add_child(UI.para("取物不消耗时间。未拿走的物资会留在此处，本次返家后无法带回；可将背囊物资放回这里，腾出位置。", 15))
	var contents := UI.vbox(6)
	contents.add_child(UI.heading("此处物资", 20, UI.GOLD))
	if loot.is_empty():
		contents.add_child(UI.label("这里已经空了。", 16, UI.INK_SOFT))
	for raw_id in loot.keys():
		var id := str(raw_id)
		var item: Dictionary = Data.item(id)
		var row := UI.hbox(8)
		row.add_child(UI.label("%s ×%d · 每件 %.1f 斤" % [item.name, Inv.count(loot, id), float(item.get("weight", 0))], 17))
		row.add_child(UI.spacer())
		row.add_child(UI.button("取 1", func(): _take_loot(idx, id, 1)))
		row.add_child(UI.button("尽量取", func(): _take_loot(idx, id, Inv.count(loot, id))))
		contents.add_child(row)
	contents.add_child(UI.sep())
	contents.add_child(UI.heading("背囊 · 放回此处", 20, UI.GOLD))
	if bag.is_empty():
		contents.add_child(UI.label("背囊是空的。", 16, UI.INK_SOFT))
	for raw_id in bag.keys():
		var id := str(raw_id)
		var item: Dictionary = Data.item(id)
		var row := UI.hbox(8)
		row.add_child(UI.label("%s ×%d · 每件 %.1f 斤" % [item.name, Inv.count(bag, id), float(item.get("weight", 0))], 17))
		row.add_child(UI.spacer())
		row.add_child(UI.button("放回 1", func(): _put_back(idx, id, 1)))
		row.add_child(UI.button("全部放回", func(): _put_back(idx, id, Inv.count(bag, id))))
		contents.add_child(row)
	body.add_child(UI.scroll(contents, mini(400, maxi(180, int(get_viewport().get_visible_rect().size.y) - 320))))


func _take_loot(idx: int, id: String, amount: int) -> void:
	var n := int(Game.act(func(): return Explore.take(Game.run, idx, id, amount)))
	Game.toast.emit("取走 %s ×%d" % [Data.item(id).name, n] if n > 0 else "背囊空间不足，或此处已没有这件物资。")


func _put_back(idx: int, id: String, amount: int) -> void:
	var n := int(Game.act(func(): return Explore.put_back(Game.run, idx, id, amount)))
	Game.toast.emit("放回 %s ×%d" % [Data.item(id).name, n] if n > 0 else "此时无法放回物资。")


func finish() -> void:
	if Game.run.explore.is_empty():
		return
	if Post.is_busy(Game.run):
		Game.toast.emit("先完成眼前的工作；尚未完工的调查不能带回证据。")
		return
	Sfx.play("door_close", -3.0)
	Game.act(func(): return Post.finish_explore(Game.run))


# ---------- HUD ----------

func build_hud() -> void:
	var run: Dictionary = Game.run
	var ex: Dictionary = run.explore
	if ex.is_empty():
		return
	var p: Dictionary = Data.table("map_points")[ex.point]
	var v := UI.vbox(4)
	v.add_child(UI.heading(p.name, 26))
	v.add_child(UI.line(p.desc, 15, UI.INK_SOFT, 300))
	v.add_child(UI.stat_row("气血", State.attr(run, "hp"), State.attr_max(run, "hp"), UI.CINNABAR, 44))
	v.add_child(UI.stat_row("精力", State.attr(run, "energy"), 100, UI.INK_SOFT, 44))
	v.add_child(UI.label("背囊 %.1f / %d 斤" % [Inv.weight(ex.bag), int(Explore.carry(run))], 16))
	var ordinary := 0
	var searched := 0
	for spot in ex.spots:
		if spot.has("mainline") or spot.has("neighbor"): continue
		ordinary += 1
		if spot.done: searched += 1
	v.add_child(UI.label("搜寻 %d / %d 处 · 返程需 %d 分钟" % [searched, ordinary, int(Post.ACTIONS.travel[1])], 15, UI.INK_SOFT))
	v.add_child(UI.line("带着：" + (Data.describe_items(ex.bag) if not ex.bag.is_empty() else "空手"), 15, UI.INK_SOFT, 300))
	v.add_child(UI.line(Neighbor.summary(run), 16, UI.INK_SOFT, 300))
	if Neighbor.state(run).stage in ["fetch", "carrying"]:
		v.add_child(UI.label("送药截止：第 4 日 18:00（含返程）", 15, UI.GOLD))
	if Neighbor.state(run).medicine:
		v.add_child(UI.label("贴身任务药 ×1 · 不占背囊", 16, UI.GOLD))
	var objective := Mainline.objective(run, str(ex.point))
	v.add_child(UI.line(Mainline.summary(run), 15, UI.GOLD, 300))
	if not objective.is_empty():
		v.add_child(UI.line("主线目标：" + str(objective.name), 15, UI.GOLD, 300))
	_work_label = UI.label("", 15, UI.GOLD)
	v.add_child(_work_label)
	corner_panel(v, Control.PRESET_TOP_LEFT)

	var e := UI.vbox(4)
	var row := UI.hbox(10)
	row.add_child(UI.label("阳气外泄", 20, UI.CINNABAR))
	row.add_child(UI.bar(int(ex.exposure), Explore.EXPOSURE_MAX, UI.CINNABAR, 360, 20))
	row.add_child(UI.label("%d / %d" % [ex.exposure, Explore.EXPOSURE_MAX], 18))
	e.add_child(row)
	var risk := Explore.exposure_range(run, str(ex.point))
	var tip := "被尸群嗅到了！快逃！" if ex.caught else "普通翻找 20 分钟，外泄 +%d～%d；21:00 后完成当前调查及事件即返程（%d 分钟）。" % [risk.x, risk.y, int(Post.ACTIONS.travel[1])]
	e.add_child(UI.label(tip, 15, UI.CINNABAR if ex.caught else UI.INK_SOFT))
	corner_panel(e, Control.PRESET_CENTER_TOP, 14, 0.9)

	var top := UI.hbox(6)
	_clock = Hud.text("%s  %s" % [Post.shichen(run), Post.clock_text(run)], 22, Hud.CYAN, true)
	top.add_child(_clock)
	_return_button = UI.seal_button("逃回家" if ex.caught else "回家", finish)
	_return_button.set_meta("mainline_return", true)
	_return_button.disabled = Post.is_busy(run)
	top.add_child(_return_button)
	top.add_child(UI.button("劫余录", Dialogs.journal))
	corner_panel(top, Control.PRESET_TOP_RIGHT)
	corner_panel(UI.log_lines(ex.notes, 4, 15, 560), Control.PRESET_BOTTOM_LEFT, 14, 0.8)
	var help := UI.label("WASD 走动 · %s 翻找 / 查看 / 回家 · 右键拖动转视角" % InputCfg.first_key_name("interact"), 15, Color(UI.PAPER_LIGHT, 0.95))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("outline_size", 4)
	hud.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 废墟里也可能碰上早上的事件。
func after_build() -> void:
	if Game.run.phase == "post" and Game.run.pending_event != "" and not UI.has_modal("event"):
		Dialogs.event()
