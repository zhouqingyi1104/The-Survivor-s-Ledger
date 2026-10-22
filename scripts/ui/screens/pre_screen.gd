extends "res://scripts/ui/screens/world_screen.gd"
## 备劫三日（3D 临川城）：点铺子（或左边的地名）走过去，到了自动打开铺子。对应原版 PreDisasterMap。

const Pre = preload("res://scripts/core/pre.gd")
const CityWorld = preload("res://scripts/world/city_world.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")

static var STATUS_COLORS := {"正常": UI.JADE, "拥挤": UI.GOLD, "哄抢": UI.CINNABAR, "关门": UI.INK_FAINT}

var rig: Node3D


func build_world() -> void:
	world = CityWorld.new()
	add_child(world)
	world.setup_walker(Game.run.role)
	world.arrived.connect(_on_arrived)
	rig = CamRig.new()
	rig.target = world.walker
	rig.pitch = -42.0
	rig.dist = 28.0
	rig.max_dist = 48.0
	world.add_child(rig)


func sync_world() -> void:
	world.sync(Game.run)
	if not world.walking:
		rig.snap()


func _process(_delta: float) -> void:
	if rig != null:
		rig.input_enabled = not modal_open()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if modal_open() or world.walking:
		return
	var id: String = world.pick(rig.cam, mb.position)
	if id != "":
		go_to(id)


## 去某地（点建筑、点地名、测试都走这里）。
func go_to(id: String) -> void:
	var run: Dictionary = Game.run
	if run.phase != "pre" or world.walking:
		return
	if id == run.loc:
		if id != "home":
			Dialogs.shop()
		return
	var block := Pre.travel_block(run, id)
	if block != "":
		Game.toast.emit(block)
		return
	var from: String = run.loc
	Game.act(func(): return Pre.travel(Game.run, id))
	world.walk(from, id)


func _on_arrived(_place: String) -> void:
	Game.changed.emit()
	if Game.run.phase == "pre" and Game.run.loc != "home":
		Dialogs.shop()


## 结束这一日。还剩不少时辰、或者今夜就是尸劫，先确认一下。
func end_day() -> void:
	var run: Dictionary = Game.run
	var left := Pre.hours_left(run)
	var last: bool = int(run.day) >= State.PRE_DAYS
	var text := ""
	if last:
		text = "今夜尸劫降临，之后就再也买不到东西了。\n手里还有 %s，车上的货会一并带回家。" % Pre.money(int(run.silver))
	elif left >= 2:
		text = "离宵禁还有 %d 个时辰，确定今天就歇下？" % left
	if text == "":
		_do_end_day()
	else:
		Dialogs.confirm("熬到天黑" if last else "回家歇息", text, "就这样吧", _do_end_day)


func _do_end_day() -> void:
	Game.act(func(): return Pre.end_day(Game.run))


# ---------- HUD ----------

func build_hud() -> void:
	var run: Dictionary = Game.run
	if run.phase != "pre":
		return
	_status(run)
	_places(run)
	var top := UI.hbox(6)
	top.add_child(UI.button("囤货清单", Dialogs.checklist))
	top.add_child(UI.button("劫余录", Dialogs.journal))
	top.add_child(UI.button("设置", func(): Dialogs.settings(true)))
	corner_panel(top, Control.PRESET_TOP_RIGHT)
	corner_panel(UI.log_lines(run.log, 3, 15, 520), Control.PRESET_BOTTOM_LEFT, 14, 0.8)
	var last: bool = int(run.day) >= State.PRE_DAYS
	var end := UI.seal_button("熬到天黑 · 尸劫降临" if last else "回家歇息，明日再说", end_day)
	end.custom_minimum_size = Vector2(260, 52)
	var p := corner_panel(end, Control.PRESET_BOTTOM_RIGHT, 14, 0.0)
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var help := UI.label("点铺子走过去 · 右键拖动转视角 · 滚轮缩放", 15, Color(UI.PAPER_LIGHT, 0.95))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("outline_size", 4)
	hud.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _status(run: Dictionary) -> void:
	var v := UI.vbox(3)
	v.add_child(UI.heading("备劫 · 第 %d 日 · %s时" % [run.day, State.HOURS[run.hour % 12]], 24))
	var left := Pre.hours_left(run)
	v.add_child(UI.label("距宵禁 %d 个时辰 · 距尸劫 %d 日" % [left, State.PRE_DAYS - int(run.day) + 1], 17, UI.CINNABAR if left <= 2 else UI.INK_SOFT))
	v.add_child(UI.label("银两 %s　负重 %.0f / %d 斤" % [Pre.money(int(run.silver)), Pre.cart_weight(run), Pre.capacity(run)], 17))
	corner_panel(v, Control.PRESET_TOP_LEFT)


func _places(run: Dictionary) -> void:
	var v := UI.vbox(3)
	v.add_child(UI.label("临川城", 18, UI.INK_SOFT))
	var ids := ["home"]
	ids.append_array(Data.table("shops").keys())
	for id in ids:
		var h := UI.hbox(6)
		var here: bool = run.loc == id
		var title: String = "家" if id == "home" else ("★ " if Pre.shop(id).get("must", false) else "") + Pre.shop(id).name
		var block := "" if here else Pre.travel_block(run, id)
		var b := UI.button(title + ("（在此）" if here else ""), func(): go_to(id), block != "" and not here, block)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 150
		h.add_child(b)
		if id != "home":
			var status := Pre.status(run, id)
			h.add_child(UI.label("%d时辰" % Pre.travel_cost(run, id), 14, UI.INK_FAINT))
			h.add_child(UI.tag(status, STATUS_COLORS.get(status, UI.INK_SOFT)))
		v.add_child(h)
	var p := corner_panel(v, Control.PRESET_CENTER_LEFT, 14, 0.82)
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
