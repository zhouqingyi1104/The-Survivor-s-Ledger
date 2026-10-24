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
	if _near == -2:
		_hint_label.text = "[E] 回家（背着 %.1f 斤）" % Inv.weight(ex.bag)
	elif _near >= 0 and _near < ex.spots.size():
		var s: Dictionary = ex.spots[_near]
		_hint_label.text = "[E] 翻找 · %s" % s.name if not s.done else "%s · 已经翻过了" % s.name
	_hint.reset_size()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or modal_open():
		return
	if key.keycode in [KEY_E, KEY_SPACE]:
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
	if ex.is_empty() or ex.caught or idx >= ex.spots.size() or ex.spots[idx].done:
		return
	var res = Game.act(func(): return Post.search(Game.run, idx))
	if typeof(res) == TYPE_DICTIONARY and not res.is_empty():
		if res.get("mainline", false):
			Game.toast.emit(str(res.get("text", "已开始调查，完成后再返程。")))
			_near = -99
			return
		if res.get("story", false):
			Game.toast.emit("已检视封存药柜，请选择开锁方式。" if Game.run.pending_event == "n_cabinet" else "药账已贴身收好，回宅决定去向。")
			_near = -99
			return
		Sfx.play("cloth" if res.found.is_empty() else "leather", -2.0)
		var text := "翻到：" + Data.describe_items(res.found) if not res.found.is_empty() else "一无所获"
		if res.full:
			text += "（背不下了）"
		Game.toast.emit(text)
		if res.clue != "":
			Game.toast.emit("得残卷一页！")
	_near = -99


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
	var tip := "被尸群嗅到了！快逃！" if ex.caught else "每翻一处要二十分钟、外泄一分阳气；酉时（21:00）前必须回家。"
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
	var help := UI.label("WASD 走动 · E 翻找 / 回家 · 右键拖动转视角", 15, Color(UI.PAPER_LIGHT, 0.95))
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
