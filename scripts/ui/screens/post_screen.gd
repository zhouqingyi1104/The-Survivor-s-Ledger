extends "res://scripts/ui/screens/world_screen.gd"
## 劫中宅院（3D，连续时间）。布局与交互参考原版 CoreUI：
##   左上 菜畦清单 + 今夜预警；右上 第几日 / 时刻 / 时辰表盘 + 印章功能按钮 + 环境；右下 状态条；
##   左下 背包 + 常用行为 + 倍速；底部正中 心愿。
##   场景里：鼠标悬停描边、头顶显示名字；点击弹出动作菜单，人自己走过去做；点地面走过去；
##   菜苗、忙碌进度、门的耐久都挂在头顶。

const Hud = preload("res://scripts/ui/hud_kit.gd")
const ClockDial = preload("res://scripts/ui/widgets/clock_dial.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Post = preload("res://scripts/core/post.gd")
const Defense = preload("res://scripts/core/defense.gd")
const HomeWorld = preload("res://scripts/world/home_world.gd")
const Player = preload("res://scripts/world/player.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")
const WaveShow = preload("res://scripts/world/wave_show.gd")
const Outline = preload("res://scripts/world/outline.gd")
const NightFight = preload("res://scripts/core/night_fight.gd")
const Home = preload("res://scripts/core/home.gd")

## 每档流速：游戏分钟 / 现实秒
const SPEEDS := [0.0, 4.0, 10.0, 24.0]
const SPEED_LABELS := ["❚❚", "▶", "▶▶", "▶▶▶"]
const BUSY_RATE := 40.0
## 忙什么就放什么动作
const WORK_ANIMS := {"cook": "Interact", "garden": "Crouch_Idle", "build": "Fixing_Kneeling", "repair": "Fixing_Kneeling",
	"read": "Sitting_Idle", "craft": "Spell_Simple_Idle", "water": "PickUp_Table"}
const SLEEP_RATE := 150.0
## 打更：戌时一更（19:00）敲一下……寅时五更（3:00）敲五下，先一声更鼓
const WATCHES := {19: 1, 21: 2, 23: 3, 1: 4, 3: 5}
## 忙什么出什么声：[开工时, 忙的时候每隔一会儿, 间隔秒]
const WORK_SOUNDS := {
	"cook": ["pot", "knife", 0.45], "garden": ["dig", "dig", 0.5], "build": ["chop", "hammer", 0.32],
	"repair": ["creak", "hammer", 0.32], "read": ["book", "book", 1.2], "craft": ["book_place", "cloth", 0.8],
	"water": ["water_draw", "", 0.0], "rest": ["cloth", "", 0.0], "travel": ["door_open", "", 0.0],
}

## 这个界面上弹的窗用夜色（main.gd 看这个）
var dark_ui := true
var player: CharacterBody3D
var rig: Node3D
var _show: Node3D
var _show_layer: Control
var _tag_layer: Control
var _tags := {}
var _menu: PanelContainer
var _menu_spot := ""
var _hover := ""
var _pending := Callable()
var _pending_spot := ""
var _acc := 0.0
var _press_pos := Vector2.ZERO
var _rpress := Vector2.ZERO
var _live := {}
## 上次按时辰给光的时刻（游戏分钟）
var _lit_t := -1
## 正在忙的事（换了就出声）和忙时的敲打节拍
var _busy_kind := ""
var _busy_beat := 0.0
var _ending_fight := false
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_key := ""
## 夜里偶尔一阵风、远处一声铃
var _night_sfx_in := 6.0


# ---------- 世界 ----------

func build_world() -> void:
	world = HomeWorld.new()
	add_child(world)
	player = Player.new()
	world.add_child(player)
	player.setup(Game.run.role)
	player.position = HomeWorld.SPAWN
	player.arrived.connect(_on_arrived)
	rig = CamRig.new()
	rig.target = player
	world.add_child(rig)
	rig.snap()


func build_overlay() -> void:
	_tag_layer = UI.full_rect(Control.new())
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag_layer)
	move_child(_tag_layer, 1)
	_menu = Hud.panel(VBoxContainer.new())
	_menu.visible = false
	add_child(_menu)
	_show_layer = UI.full_rect(Control.new())
	_show_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_show_layer)


func sync_world() -> void:
	if _show == null:
		world.sync(Game.run)
		world.show_fight(Game.run.get("fight", {}))


func _process(delta: float) -> void:
	if world == null or Game.run.is_empty() or Game.run.phase != "post":
		return
	var run: Dictionary = Game.run
	var ui_blocked := modal_open() or _show != null or _menu.visible
	player.enabled = not ui_blocked and not run.sleeping and not Post.is_busy(run)
	rig.input_enabled = not modal_open() and _show == null
	player.cam_yaw = rig.yaw
	world.update_roofs(player.global_position)
	player.figure.step_sound = "step_wood" if world.indoors(player.global_position) else "step_stone"
	_update_pose(run)
	_work_sounds(run, delta)
	_night_sounds(run, delta)
	_update_hover(ui_blocked)
	_update_ghost()
	if not ui_blocked:
		_step_fight(run, delta)
		# 院门口打着的时候，时辰先不走，免得下一轮叠上来
		if run.fight.is_empty():
			_tick_time(delta)
	_update_live()
	_update_tags()


## 挥一刀（左键 / J；测试也走这里）。
func _swing() -> void:
	var fight: Dictionary = Game.run.get("fight", {})
	if fight.is_empty():
		return
	var p := player.global_position
	var res := NightFight.strike(fight, p.x, p.z)
	player.figure.working = true
	player.figure.work_anim = "Interact"
	get_tree().create_timer(0.22).timeout.connect(func(): player.figure.working = false)
	if res.is_empty():
		return
	if res.get("hit", false):
		Sfx.play("hit_soft", -3.0, 0.02)
		rig.shake = maxf(rig.shake, 0.22)
		if res.get("kill", false):
			Sfx.play("ling", -10.0, 0.12)
	else:
		Sfx.play("cloth", -10.0, 0.02)


## 摆放预览：半透明方块跟着鼠标走，绿=放得下，红=不行（堵路、挤在一起、料不够）。
func _update_ghost() -> void:
	if Game.placing == "":
		if _ghost != null:
			_ghost.visible = false
		return
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(1, 0.9, 1)
		_ghost.mesh = m
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ghost_mat.albedo_color = Color(0.42, 0.85, 0.52, 0.30)
		_ghost.material_override = _ghost_mat
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_ghost)
	var hit: Dictionary = world.pick(rig.cam, get_viewport().get_mouse_position())
	if Game.placing_at != null:
		_ghost_at(Game.placing_at)
	elif hit.has("ground"):
		_ghost_at(hit.ground)
	elif Game.no_save:
		# 截图 / 演示时没有真实鼠标位置，就摆在人前面
		_ghost_at(player.global_position + Vector3(0.0, 0.0, 2.4))
	else:
		_ghost.visible = false


func _ghost_at(p: Vector3) -> void:
	var gx := Home.snap(p.x)
	var gz := Home.snap(p.z)
	var key := "%s_%d" % [Game.placing, Game.placing_rot]
	if key != _ghost_key:
		_ghost_key = key
		var box: BoxMesh = _ghost.mesh
		var sz := Home.size_of(Game.placing, 0)
		box.size = Vector3(sz.x, 0.9, sz.y)
	_ghost.visible = true
	_ghost.global_position = Vector3(gx, 0.45, gz)
	_ghost.rotation.y = deg_to_rad(float(Game.placing_rot))
	var block := Home.place_block(Game.run, Game.placing, gx, gz, Game.placing_rot)
	_ghost_mat.albedo_color = Color(0.92, 0.35, 0.28, 0.30) if block != "" else Color(0.42, 0.85, 0.52, 0.30)


## 摆放模式：点地面把选中的家具放下去。
func _place_at(p: Vector3) -> void:
	var id := Game.placing
	Game.placing = ""
	var res = Game.act(func(): return Post.act_furnish(Game.run, id, p.x, p.z, Game.placing_rot))
	if typeof(res) == TYPE_STRING and res != "":
		Game.placing = id       # 放不下：留着继续试
		Game.toast.emit(res)
		return
	Sfx.play("hammer", -6.0)


## 架一刀（K / 右键单击；测试也走这里）。挡住那一口，咬你的被推开。
func _guard() -> void:
	var fight: Dictionary = Game.run.get("fight", {})
	if fight.is_empty():
		return
	if not NightFight.guard(fight):
		# 刀还没收回来，抬不起来
		Sfx.play("cloth", -16.0, 0.05)
		return
	Sfx.play("knife", -7.0, 0.03)
	player.figure.working = true
	player.figure.work_anim = "Interact"
	get_tree().create_timer(0.16).timeout.connect(func(): player.figure.working = false)


## 院门的活人：走位、撞门、进院砸东西。
func _step_fight(run: Dictionary, delta: float) -> void:
	if run.fight.is_empty() or _ending_fight:
		return
	var p := player.global_position
	var passable := bool(run.door_open) or int(run.door.cur) <= 0
	var evs := NightFight.step(run.fight, delta, p.x, p.z, passable)
	for e in evs:
		match str(e[0]):
			"bash":
				run.door.cur = maxi(0, int(run.door.cur) - NightFight.BASH_DMG)
				Sfx.play("hit_door", -7.0)
				rig.shake = maxf(rig.shake, 0.18)
			"bite":
				Sfx.play("punch", -4.0)
				rig.shake = maxf(rig.shake, 0.45)
			"parry":
				Sfx.play("latch", -4.0)
				rig.shake = maxf(rig.shake, 0.12)
			"enter":
				Game.toast.emit("有东西挤进院子了！")
				Sfx.play("creak", -5.0)
			"wreck":
				var idx: int = int(e[1].target)
				var text: String = Post.apply_wreck(run, idx)
				var t: Array = NightFight.TARGETS[idx]
				world.show_wreck(idx, Vector3(float(t[1]), 0.0, float(t[2])), str(t[3]))
				# 存货、柴垛、菜畦按新状态重画（米袋少了、菜畦空了，一眼能看见）
				world.sync(run)
				Sfx.play("hit_plank", -8.0)
				rig.shake = maxf(rig.shake, 0.2)
				if text != "":
					Game.toast.emit(text)
	world.show_fight(run.fight)
	if bool(run.fight.get("done", false)):
		_ending_fight = true
		var sum: Dictionary = NightFight.finish(run.fight)
		Game.act(func():
			Post.end_fight(Game.run, sum)
			return "")
		_ending_fight = false


## 开工那一下、忙的时候的敲打声（忙碌时时间加速，一件事只有一两秒，敲几下就完）。
func _work_sounds(run: Dictionary, delta: float) -> void:
	var kind: String = run.busy.get("kind", "") if Post.is_busy(run) else ""
	if kind != _busy_kind:
		_busy_kind = kind
		_busy_beat = 0.0
		if WORK_SOUNDS.has(kind) and WORK_SOUNDS[kind][0] != "":
			Sfx.play(WORK_SOUNDS[kind][0], -3.0)
		if kind == "cook":
			Sfx.ambience("fire_loop", -6.0, 0.4)
		_scene_audio(run)
		return
	if kind == "" or not WORK_SOUNDS.has(kind) or WORK_SOUNDS[kind][1] == "":
		return
	_busy_beat += delta
	if _busy_beat >= WORK_SOUNDS[kind][2]:
		_busy_beat = 0.0
		Sfx.play(WORK_SOUNDS[kind][1], -6.0)


## 夜里（没睡着、没在演出）每隔十来秒：一阵风，或者远处一声赶尸铃。
func _night_sounds(run: Dictionary, delta: float) -> void:
	if _show != null or run.sleeping or not Post.is_night(run) or Game.speed == 0:
		return
	_night_sfx_in -= delta
	if _night_sfx_in > 0.0:
		return
	_night_sfx_in = randf_range(8.0, 18.0)
	if randf() < 0.25:
		Sfx.play("ling", -22.0, 0.05)
	else:
		Sfx.play("gust", -14.0, 0.1)


## 配乐和环境声跟着昼夜走：白天一点古筝，入夜只剩风雪；生火做饭、夜里烧炭时有柴火声。
func _scene_audio(run: Dictionary) -> void:
	if _show != null or Game.screen != "post":
		return
	var night: bool = Post.is_night(run)
	Sfx.music("" if night else "lotus_pond", -13.0, 3.0)
	Sfx.ambience("wind_loop", -8.0 if night else -15.0, 3.0)
	var fire: bool = _busy_kind == "cook" or (bool(run.get("heated", false)) and night)
	Sfx.ambience("fire_loop", -9.0 if fire else null, 1.5)


## 忙的时候手上有动作；睡觉、小憩时人躺到床榻上。
func _update_pose(run: Dictionary) -> void:
	var fig: Node3D = player.figure
	var resting: bool = run.sleeping or (Post.is_busy(run) and run.busy.kind == "rest")
	fig.working = Post.is_busy(run) and not resting
	if fig.working:
		fig.work_anim = WORK_ANIMS.get(run.busy.kind, "Interact")
	if resting == fig.lying:
		return
	fig.lying = resting
	if resting:
		Sfx.play("cloth", -4.0)
		player.stop()
		# 人先走到榻前（镜头跟过去），模型再躺到榻上
		player.global_position = HomeWorld.SPOTS.bed.stand
		fig.position = player.to_local(Vector3(-3.1, -0.09, -7.25))
		fig.rotation.y = PI / 2.0
	else:
		fig.position = Vector3.ZERO
		player.global_position = HomeWorld.SPOTS.bed.stand


# ---------- 时间 ----------

func _rate(run: Dictionary) -> float:
	var base: float = SPEEDS[Game.speed]
	if base <= 0.0:
		return 0.0
	if run.sleeping:
		return SLEEP_RATE
	if Post.is_busy(run):
		return maxf(base, BUSY_RATE)
	return base


func _tick_time(delta: float) -> void:
	var run: Dictionary = Game.run
	if Post.blocked(run):
		return
	_acc += _rate(run) * delta
	var mins := int(_acc)
	if mins <= 0:
		return
	_acc -= mins
	advance(mins)


## 让时间走 mins 分钟（测试也走这里）。有事发生就存档、刷新界面。
func advance(mins: int) -> void:
	var run: Dictionary = Game.run
	var busy_before := Post.is_busy(run)
	var sleep_before: bool = run.sleeping
	var hour_before := Post.clock(run) / 60
	var stop := Post.advance(run, mins)
	if stop == "raid" and not run.raid_report.is_empty():
		var r: Dictionary = run.raid_report
		Game.toast.emit("溃兵夜袭：" + ("被挡在门外" if r.repelled else "破门抢走了" + Data.describe_items(r.stolen)))
		Sfx.play("punch", -2.0)
		run.raid_report = {}
	if stop == "wave":
		_start_wave()
		return
	if stop == "wave_round":
		var rep = Game.act(func(): return Post.nod_round(Game.run))
		Game.refresh()
		if not rep.is_empty():
			var line := "第 %d 轮结束：斩 %d 只" % [int(rep.round) + 1, int(rep.killed)]
			if int(rep.get("enter", 0)) > 0:
				line += "，进院 %d 只" % int(rep.enter)
			if not rep.get("broke", []).is_empty():
				line += "，有一面被撞破"
			Game.toast.emit(line)
			Sfx.play("hit_door", -6.0)
		if Post.in_night(Game.run):
			Dialogs.night_panel()
		return
	if stop == "plan":
		Game.refresh()
		Dialogs.night_plan()
		return
	if stop != "" or busy_before != Post.is_busy(run) or sleep_before != run.sleeping:
		Game.refresh()
	elif Post.clock(run) / 60 != hour_before:
		_hourly()
	# 天光跟着钟走（每过三分钟挪一点）。只在整点给光的话，中途一刷新界面，影子会一下跳过去好几十分钟
	if _show == null and absi(int(run.t) - _lit_t) >= 3:
		_lit_t = int(run.t)
		world.set_time(run)


## 整点：存一下档，世界跟着时辰换光、菜苗长一截，HUD 只改会变的字（整个重画要十几毫秒，会顿一下）。
## 夜里逢更打更。
func _hourly() -> void:
	Game.save_game()
	var run: Dictionary = Game.run
	var hour := Post.clock(run) / 60
	if WATCHES.has(hour) and not run.sleeping and _show == null:
		var seq := ["genggu"]
		for k in WATCHES[hour]:
			seq.append("bangzi")
		Sfx.strikes(seq, 0.55, -5.0)
	_scene_audio(run)
	if _show == null:
		world.sync(Game.run)
	_update_live()
	_update_crops()


# ---------- 入夜尸潮 ----------

func _start_wave() -> void:
	var run: Dictionary = Game.run
	if not run.wave_due or _show != null:
		return
	_close_menu()
	player.stop()
	Sfx.play("luo", -1.0, 0.0)
	Sfx.music("dragon_dance", -7.0, 1.2)
	Sfx.ambience("fire_loop", null)
	var before: Dictionary = run.duplicate(true)
	_show = WaveShow.new()
	world.add_child(_show)
	Game.hold_screen = true
	var rep = Game.act(func(): return Post.resolve_wave(Game.run))
	world.sync(before)
	_show.play(world, rig, {"wave": rep}, player.global_position)
	_show.finished.connect(_end_show)
	_build_show_layer()


func _build_show_layer() -> void:
	UI.clear(_show_layer)
	hud.visible = false
	_tag_layer.visible = false
	var p := Hud.panel(Hud.title(_show.banner, 34))
	_show_layer.add_child(p)
	Hud.pin(p, Control.PRESET_CENTER_TOP, 30)
	var skip := Hud.button("跳过", func(): _show.skip(), false, "", 17)
	_show_layer.add_child(skip)
	Hud.pin(skip, Control.PRESET_BOTTOM_RIGHT, 24)


func _end_show() -> void:
	if _show == null:
		return
	_show.queue_free()
	_show = null
	UI.clear(_show_layer)
	hud.visible = true
	_tag_layer.visible = true
	rig.release()
	Game.hold_screen = false
	Game.refresh()
	_scene_audio(Game.run)


## 事件 → 战报 → 天亮结算，自动弹出。
func after_build() -> void:
	var run: Dictionary = Game.run
	if run.phase != "post" or _show != null:
		return
	if run.wave_due:
		_start_wave.call_deferred()
	elif run.pending_event != "" and not UI.has_modal("event"):
		Dialogs.event()
	elif run.plan_due and not UI.has_modal("night_plan"):
		Dialogs.night_plan()
	elif not run.wave_report.is_empty() and not UI.has_modal("wave_report"):
		Dialogs.wave_report()
	elif run.dawn_due and not UI.has_modal("dawn"):
		Dialogs.dawn_report()


# ---------- 交互：悬停、点击、菜单、走过去做 ----------

func _update_hover(ui_blocked: bool) -> void:
	var id := ""
	if not ui_blocked:
		var hit: Dictionary = world.pick(rig.cam, get_viewport().get_mouse_position())
		id = hit.get("spot", "")
	if id == _hover:
		return
	Outline.set_outline(world.spot_nodes.get(_hover), false)
	_hover = id
	Outline.set_outline(world.spot_nodes.get(_hover), true)


func _unhandled_input(event: InputEvent) -> void:
	if _show != null:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		# 右键单击 = 架刀；右键拖动仍然是转视角（靠按下到抬起的位移区分）
		if mb.pressed:
			_rpress = mb.position
		elif mb.position.distance_to(_rpress) < 6.0 and not Game.run.get("fight", {}).is_empty():
			_guard()
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and not modal_open() and not Game.run.get("fight", {}).is_empty():
			_swing()
			return
		if mb.pressed:
			_press_pos = mb.position
		elif mb.position.distance_to(_press_pos) < 6.0:
			_click(mb.position)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or modal_open():
		return
	match key.keycode:
		KEY_E:
			var id: String = world.nearest_spot(player.global_position, 2.2)
			if id != "":
				open_menu(id, rig.cam.unproject_position(HomeWorld.SPOTS[id].tag))
		KEY_SPACE:
			Game.speed = 1 if Game.speed == 0 else 0
			Game.refresh()
		KEY_1, KEY_2, KEY_3:
			Game.speed = key.keycode - KEY_0
			Game.refresh()
		KEY_N:
			perform("bed", "就寝")
		KEY_I, KEY_TAB:
			Dialogs.inventory()
		KEY_J:
			if not Game.run.get("fight", {}).is_empty():
				_swing()
			else:
				Dialogs.journal()
		KEY_K:
			if not Game.run.get("fight", {}).is_empty():
				_guard()
		KEY_R:
			if Game.placing != "":
				Game.placing_rot = (Game.placing_rot + 90) % 360
				Game.toast.emit("转了个方向。")
		KEY_F:
			if Post.in_night(Game.run):
				Dialogs.night_panel()
		KEY_ESCAPE:
			if Game.placing != "":
				Game.placing = ""
				Game.toast.emit("先不摆了。")
			elif _menu.visible:
				_close_menu()
			else:
				Dialogs.settings(true)


func _click(pos: Vector2) -> void:
	if modal_open():
		return
	if Game.placing != "":
		var spot: Dictionary = world.pick(rig.cam, pos)
		if spot.has("ground"):
			_place_at(spot.ground)
		else:
			Game.toast.emit("得点在空地上。")
		return
	if _menu.visible:
		_close_menu()
		return
	var hit: Dictionary = world.pick(rig.cam, pos)
	if hit.has("spot"):
		open_menu(hit.spot, pos)
	elif hit.has("ground") and player.enabled:
		_pending = Callable()
		player.walk_to(hit.ground)


## 物件能做的事：[文字, 回调, 做不了的原因]
func actions_for(id: String) -> Array:
	var run: Dictionary = Game.run
	var can := Post.can_act(run)
	if id.begins_with("f_"):
		var uid := int(id.substr(2))
		if Home.find(run, uid).is_empty():
			return []
		return [["拆掉（退一半料）", _act(func(): return Post.act_unfurnish(Game.run, uid)), can]]
	match id:
		"stove":
			if "stove" in run.get("broken", []):
				return _fix_menu("stove")
			return [["生火做饭…", Dialogs.cook, can]]
		"garden":
			var tend := can
			if tend == "" and run.plots.all(func(p): return p.crop == ""):
				tend = "还没种东西"
			return [["浇水 · 收成（45 分钟）", _act(func(): return Post.act_garden(Game.run)), tend], ["播种 / 查看菜畦…", Dialogs.garden, ""]]
		"well":
			return [["打水（15 分钟）", _act(func(): return Post.draw_water(Game.run)), "今天已经打过了" if run.well_used else Post.can_act(run, 2)]]
		"bed":
			var sleep_block := Post.can_act(run, 0)
			if sleep_block == "" and not Post.is_night(run) and State.attr(run, "energy") >= 30:
				sleep_block = "天还亮着"
			return [["就寝（睡到天亮）", _act(func(): return Post.sleep(Game.run)), sleep_block], ["小憩两个时辰", _act(func(): return Post.act_rest(Game.run)), Post.can_act(run, 0)]]
		"shrine":
			return [["上香求签…", Dialogs.omens, ""]]
		"desk":
			return [["读书…", Dialogs.read, can]]
		"storage":
			return [["打开储物柜", Dialogs.inventory, ""]]
		"bench":
			var can_mend := Inv.count(run.home, "wood") > 0 or Inv.count(run.home, "firewood") >= 2
			var mend := "" if can_mend else "没有木料（两捆柴也行）"
			var out := [["营造守具 · 画符…", Dialogs.build, ""], ["添置家具…", Dialogs.furnish, ""]]
			if "bench" in run.get("broken", []):
				out = _fix_menu("bench") + out
			for row in [["door", "门"], ["window", "窗"], ["wall", "墙"]]:
				var sid: String = row[0]
				var part: Dictionary = run[sid]
				var block := can if can != "" else (mend if int(part.cur) < int(part.max) else "%s完好" % row[1])
				out.append(["修%s（木料 1，一个时辰）" % row[1], _act(func(): return Post.act_repair(Game.run, sid)), block])
			return out
		"gate":
			var out := can
			if out == "" and Post.day_minute(run) + 60 >= Post.CURFEW_AT:
				out = "天快黑了"
			var list := []
			if Post.in_night(run):
				list.append(["关门（闩上就不出去了）" if bool(run.door_open) else "开门（出去打，也会放它们进来）",
					func(): _toggle_gate(), ""])
			list.append(["出门搜寻…", Dialogs.explore_pick, out])
			return list
	return []


## 被砸烂的家具只剩一件事：拿材料重做。
func _fix_menu(id: String) -> Array:
	var run: Dictionary = Game.run
	var name: String = Data.table("furniture")[id].name
	var cost := Post.furniture_fix_cost(id)
	var line := "重修%s（%s，一个半时辰）" % [name, Data.describe_items(cost)]
	return [[line, _act(func(): return Post.act_fix_furniture(Game.run, id)), Post.furniture_block(run, id)]]


func _act(fn: Callable) -> Callable:
	return func(): Game.act(fn)


## 开关院门：拉开是门轴响，闩上是闩子响。
func _toggle_gate() -> void:
	var res = Game.act(func(): return Post.toggle_gate(Game.run))
	if typeof(res) == TYPE_STRING and res == "":
		Sfx.play("door_open" if bool(Game.run.door_open) else "latch", -5.0)


func open_menu(id: String, screen_pos: Vector2) -> void:
	_menu_spot = id
	var v: VBoxContainer = _menu.get_child(0)
	UI.clear(v)
	v.add_theme_constant_override("separation", 5)
	v.add_child(Hud.title(HomeWorld.SPOTS[id].name, 20, Hud.GOLD))
	var first := true
	for a in actions_for(id):
		var block: String = a[2]
		var label: String = a[0] + ("（%s）" % block if block != "" else "")
		var cb: Callable = a[1]
		var b: Button
		if first and block == "":
			b = Hud.primary(label, func(): _choose(id, cb), false, "", 15)
		else:
			b = Hud.button(label, func(): _choose(id, cb), block != "", block, 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 210
		v.add_child(b)
		first = false
	_menu.visible = true
	_menu.reset_size()
	var vp := get_viewport_rect().size
	_menu.position = Vector2(clampf(screen_pos.x + 18, 8, vp.x - _menu.size.x - 8), clampf(screen_pos.y - 30, 8, vp.y - _menu.size.y - 8))


func _close_menu() -> void:
	_menu.visible = false
	_menu_spot = ""


func _choose(id: String, cb: Callable) -> void:
	_close_menu()
	do_at(id, cb)


## 走到物件跟前再做（已经在跟前就直接做）。
func do_at(id: String, cb: Callable) -> void:
	var stand: Vector3 = HomeWorld.SPOTS[id].stand
	var flat := Vector3(player.global_position.x, 0, player.global_position.z)
	if flat.distance_to(stand) < 0.8:
		_face(id)
		cb.call()
		return
	_pending = cb
	_pending_spot = id
	player.walk_to(stand)


func _on_arrived() -> void:
	if not _pending.is_valid():
		return
	var cb := _pending
	_pending = Callable()
	_face(_pending_spot)
	cb.call()


func _face(id: String) -> void:
	if id == "":
		return
	var to: Vector3 = HomeWorld.SPOTS[id].tag - player.global_position
	to.y = 0
	player.figure.face(to, 1.0)


## 按文字找到物件上的一个动作直接做（快捷键、常用行为、测试用）。
func perform(id: String, prefix: String) -> void:
	for a in actions_for(id):
		if String(a[0]).begins_with(prefix):
			if a[2] != "":
				Game.toast.emit(a[2])
				return
			do_at(id, a[1])
			return


# ---------- 场景头顶标签 ----------

func _tag(key: String) -> Dictionary:
	if _tags.has(key):
		return _tags[key]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var l := Hud.text("", 13, Hud.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var bar := Hud.mini_bar(Hud.GREEN, 72)
	v.add_child(bar)
	var p := Hud.panel(v, Hud.BG_SOFT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_layer.add_child(p)
	_tags[key] = {"panel": p, "label": l, "bar": bar}
	return _tags[key]


func _show_tag(key: String, world_pos: Vector3, text: String, progress := -1.0, color := Hud.GREEN) -> void:
	var t := _tag(key)
	var p: PanelContainer = t.panel
	if rig.cam.is_position_behind(world_pos):
		p.visible = false
		return
	p.visible = true
	(t.label as Label).text = text
	var bar: ProgressBar = t.bar
	bar.visible = progress >= 0.0
	if progress >= 0.0:
		bar.value = progress
		bar.add_theme_stylebox_override("fill", Hud.box(color, Color(0, 0, 0, 0), 2, 0, 0))
	p.reset_size()
	p.position = rig.cam.unproject_position(world_pos) - Vector2(p.size.x / 2.0, p.size.y)


func _update_tags() -> void:
	var run: Dictionary = Game.run
	var used := {}
	if _show == null:
		var crops: Dictionary = Data.table("crops")
		for k in run.plots.size():
			var plot: Dictionary = run.plots[k]
			if plot.crop == "":
				continue
			var c: Dictionary = crops[plot.crop]
			var pos: Vector3 = HomeWorld.PLOT_POS[k] + Vector3(0, 0.9, 0)
			if Post.crop_ripe(plot):
				_show_tag("plot%d" % k, pos, "✓ %s 可收" % c.name, -1.0)
			elif Post.plot_dry(run, plot):
				_show_tag("plot%d" % k, pos, "%s 缺水" % c.name, float(plot.days) / float(c.days), Hud.CYAN)
			else:
				var left := (float(c.days) - float(plot.days)) * 1440.0
				_show_tag("plot%d" % k, pos, "%s %s" % [c.name, Hud.duration(left)], float(plot.days) / float(c.days))
			used["plot%d" % k] = true
		var head := player.global_position + Vector3(0, 2.3, 0)
		if run.sleeping:
			_show_tag("busy", head, "睡梦中 Zzz")
			used["busy"] = true
		elif Post.is_busy(run):
			_show_tag("busy", head, "%s中 %s" % [run.busy.label, Hud.duration(int(run.busy.end) - int(run.t))], Post.busy_progress(run), Hud.GOLD)
			used["busy"] = true
		if int(run.door.cur) < int(run.door.max):
			_show_tag("gate", HomeWorld.SPOTS.gate.tag, "门 %d/%d" % [run.door.cur, run.door.max], float(run.door.cur) / float(run.door.max), Hud.RED)
			used["gate"] = true
		if _hover != "":
			_show_tag("hover", HomeWorld.SPOTS[_hover].tag + Vector3(0, 0.45, 0), HomeWorld.SPOTS[_hover].name)
			used["hover"] = true
	for key in _tags:
		if not used.has(key):
			_tags[key].panel.visible = false


# ---------- HUD ----------

func build_hud() -> void:
	var run: Dictionary = Game.run
	if run.phase != "post":
		return
	_live = {}
	_left_top(run)
	_right_top(run)
	_right_bottom(run)
	_left_bottom(run)
	_center_bottom(run)
	_update_live()
	_update_crops()
	_scene_audio(run)


func _left_top(run: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	# 菜畦清单
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 3)
	var planted := 0
	for plot in run.plots:
		if plot.crop != "":
			planted += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(Hud.title("菜畦", 19, Hud.GOLD))
	head.add_child(Hud.tag("%d/%d" % [planted, run.plots.size()], Color("#5d7d4f")))
	g.add_child(head)
	var crops: Dictionary = Data.table("crops")
	for plot in run.plots:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		if plot.crop == "":
			h.add_child(Hud.text("○", 13, Hud.FAINT))
			h.add_child(Hud.text("空着", 14, Hud.FAINT))
		else:
			var icon := Hud.text("", 13, Hud.GREEN)
			h.add_child(icon)
			var n := Hud.text(crops[plot.crop].name, 14, Hud.TEXT, true)
			n.custom_minimum_size.x = 48
			h.add_child(n)
			var right := Hud.text("", 13, Hud.SUB)
			h.add_child(right)
			_live.get_or_add("crops", []).append([plot, icon, right])
		g.add_child(h)
	v.add_child(Hud.panel(g))
	# 尸潮预警
	var f := VBoxContainer.new()
	f.add_theme_constant_override("separation", 2)
	var wave := Defense.wave_for_day(run.pday, float(State.diff(run).wave_mul))
	if not wave.is_empty() and int(run.wave_day) != int(run.pday):
		f.add_child(Hud.title("今夜尸潮", 19, Hud.RED))
		var mods := Defense.mod_names(wave)
		f.add_child(Hud.text("亥时 22:00 来袭" + ("（%s）" % mods if mods != "" else ""), 14, Hud.TEXT))
		var cd := Hud.text("", 14, Hud.RED, true)
		f.add_child(cd)
		_live.wave_cd = cd
	else:
		var next := 0
		for d in range(int(run.pday) + 1, int(run.pday) + 10):
			if not Defense.wave_for_day(d, float(State.diff(run).wave_mul)).is_empty():
				next = d
				break
		f.add_child(Hud.title("预兆", 19, Hud.GOLD))
		f.add_child(Hud.text("下一波尸潮：第 %d 夜" % next if next > 0 else "近日无尸潮", 14, Hud.SUB))
	f.add_child(Hud.text("门 %d/%d · 窗 %d/%d · 墙 %d/%d" % [run.door.cur, run.door.max, run.window.cur, run.window.max, run.wall.cur, run.wall.max], 13, Hud.SUB))
	# 院门攻防：门开着没有，外面几只、进来了几只
	var fight: Dictionary = run.get("fight", {})
	if not fight.is_empty():
		var outside: int = NightFight.alive(fight) - NightFight.inside_count(fight)
		f.add_child(Hud.text("院门%s · 门外 %d 只 · 进院 %d 只 · 左键挥刀" % [
			"开着" if bool(run.door_open) else "关着", maxi(0, outside), NightFight.inside_count(fight)],
			13, Hud.RED if NightFight.alive(fight) > 0 else Hud.GREEN))
		# 架刀：亮着就是能架，暗着是还在收刀
		var guard_line := "K / 右键：架刀"
		if NightFight.can_guard(fight):
			guard_line += "（就绪）"
		else:
			guard_line += "（收刀 %.1f 秒）" % NightFight.block_wait(fight)
		if int(fight.get("parries", 0)) > 0:
			guard_line += "　已架住 %d" % int(fight.parries)
		f.add_child(Hud.text(guard_line, 13, Hud.GOLD if NightFight.can_guard(fight) else Hud.SUB))
	elif Post.in_night(run):
		f.add_child(Hud.text("院门%s" % ("开着" if bool(run.door_open) else "闩着"), 13, Hud.GOLD if bool(run.door_open) else Hud.SUB))
	# 摆放家具：这一行常驻，进摆放模式后才显示（面板是建界面时搭的，之后改不了内容）
	var place_line := Hud.text("", 13, Hud.GOLD)
	place_line.visible = false
	f.add_child(place_line)
	_live["place"] = place_line
	# 守具按面挂；夜战时显示第几轮和这一轮各面来几只
	var parts := []
	for sid in Defense.SURFACES:
		parts.append("%s %.0f" % [Defense.surface_name(sid), float(Defense.surface_power(run, sid).total)])
	f.add_child(Hud.text("守力 " + " · ".join(parts), 13, Hud.SUB))
	if Post.in_night(run):
		var night: Dictionary = run.night
		var idx := int(night.round)
		var pv := Defense.preview_round(run, night.wave, idx)
		var line := "夜战第 %d/%d 轮：门 %d · 窗 %d · 墙 %d" % [idx + 1, int(night.rounds),
			int(pv.surfaces.gate.count), int(pv.surfaces.window.count), int(pv.surfaces.wall.count)]
		f.add_child(Hud.text(line, 13, Hud.RED))
		var cd := Defense.round_minute(idx) - Post.day_minute(run)
		f.add_child(Hud.text("下一轮还有 %s" % Hud.duration(maxi(0, cd)), 13, Hud.GOLD))
	elif not wave.is_empty() and int(run.wave_day) != int(run.pday):
		var pv := Defense.preview_night(run, wave)
		var leak := 0
		for sid in Defense.SURFACES:
			var s: Dictionary = pv.get(sid, {})
			leak += maxi(0, int(s.get("count", 0)) - int(floor(float(s.get("power", 0)) / Defense._cost(wave))) * Defense.rounds())
		f.add_child(Hud.text("今夜三面：门 %d · 窗 %d · 墙 %d　%s" % [
			int(pv.gate.count), int(pv.window.count), int(pv.wall.count),
			("预计漏 %d 只" % leak) if leak > 0 else "挡得住"], 13, Hud.RED if leak > 0 else Hud.GREEN))
	v.add_child(Hud.panel(f))
	hud.add_child(v)
	Hud.pin(v, Control.PRESET_TOP_LEFT, 14)


func _right_top(run: Dictionary) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	# 第几日 + 时刻 + 表盘
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_END
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	var day := Hud.title("第 %d 日" % run.pday, 38, Color.WHITE)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	texts.add_child(day)
	var w := State.weather(run)
	var sub := Hud.text("%s · 生死簿残页 %d" % [w.name, run.rebirths_left], 13, Hud.SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	texts.add_child(sub)
	var tm := Hud.text("", 26, Hud.CYAN, true)
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	texts.add_child(tm)
	_live.time = tm
	top.add_child(texts)
	var dial := ClockDial.new()
	dial.custom_minimum_size = Vector2(104, 104)
	if not Defense.wave_for_day(run.pday, float(State.diff(run).wave_mul)).is_empty():
		dial.alert_minute = 22 * 60
	top.add_child(dial)
	_live.dial = dial
	col.add_child(Hud.panel(top, Color(0.05, 0.045, 0.04, 0.72)))
	# 印章功能按钮
	col.add_child(Hud.func_row("劫余录", "J", "录", Dialogs.journal))
	col.add_child(Hud.func_row("神龛求签", "功德 %d" % int(run.merit), "签", func(): perform("shrine", "上香")))
	col.add_child(Hud.func_row("存货", "I", "囊", Dialogs.inventory))
	if Post.in_night(Game.run):
		col.add_child(Hud.func_row("夜战", "第 %d 轮" % (int(Game.run.night.round) + 1), "战", Dialogs.night_panel))
	col.add_child(Hud.func_row("设置", "Esc", "设", func(): Dialogs.settings(true)))
	# 环境：院子冷不冷、今夜有没有生火
	var env := VBoxContainer.new()
	env.add_theme_constant_override("separation", 2)
	var temp: int = -int(round(int(w.cold) / 2.2))
	var feel := "寒冷" if int(w.cold) >= 20 else "微寒"
	env.add_child(Hud.text("院子  %d°  %s" % [temp, feel], 15, Hud.TEXT, true))
	var heat_text := ""
	if run.heated:
		heat_text = "今夜已生火" + ("（发电机）" if bool(run.get("powered", false)) else "")
	elif State.has_facility(Game.run, "generator"):
		heat_text = "20:00 开发电机（柴油 %d 桶）· 烧柴（柴 %d 捆 · 炭 %d 筐）" % [
			Inv.count(run.home, "diesel"), Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal")]
	else:
		heat_text = "20:00 生火（柴 %d 捆 · 炭 %d 筐）" % [Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal")]
	env.add_child(Hud.text(heat_text, 13, Hud.GOLD if run.heated else Hud.SUB))
	env.add_child(Hud.text("灯油 %d 壶 · 清水 %d 瓢 · 存粮 %d 斗" % [Inv.count(run.home, "lamp_oil"), Inv.count(run.home, "water"), Inv.total(run.home, Inv.GRAINS)], 13, Hud.SUB))
	col.add_child(Hud.panel(env))
	for c in col.get_children():
		c.size_flags_horizontal = Control.SIZE_SHRINK_END
	hud.add_child(col)
	Hud.pin(col, Control.PRESET_TOP_RIGHT, 14)


func _right_bottom(run: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_END
	tags.add_theme_constant_override("separation", 6)
	if run.plague:
		tags.add_child(Hud.tag("染尸瘟", Hud.RED))
	if State.attr(run, "warmth") < 30:
		tags.add_child(Hud.tag("受冻", Color("#c06a2a")))
	if State.attr(run, "food") <= 0:
		tags.add_child(Hud.tag("断粮", Hud.RED))
	if State.attr(run, "water") <= 0:
		tags.add_child(Hud.tag("断水", Hud.RED))
	if State.attr(run, "mood") < 20:
		tags.add_child(Hud.tag("心神大乱", Hud.RED))
	if tags.get_child_count() > 0:
		v.add_child(tags)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	_live.bars = {}
	for k in ["food", "water", "mood", "energy", "warmth", "hp"]:
		var r := Hud.stat_row(k, State.ATTR_NAMES[k])
		rows.add_child(r.row)
		_live.bars[k] = r
	v.add_child(Hud.panel(rows))
	hud.add_child(v)
	Hud.pin(v, Control.PRESET_BOTTOM_RIGHT, 14)


## 常用行为：按眼下最缺什么推荐（对应原版 SmartRecommend）。[文字, 回调, 是否不占时间]
func _quick_actions(run: Dictionary) -> Array:
	var q := []
	if State.attr(run, "water") < 70 and Inv.count(run.home, "water") > 0:
		q.append(["喝 清水", func(): Dialogs._use("water"), true])
	if State.attr(run, "food") < 70:
		var foods := Inv.food_ids(run.home)
		if not foods.is_empty():
			var best: String = foods[-1]
			q.append(["吃 " + Data.item_name(best), func(): Dialogs._use(best), true])
	if run.plague and Inv.count(run.home, "plague_powder") > 0:
		q.append(["服 避瘟散", func(): Dialogs._use("plague_powder"), true])
	if not run.well_used and not Post.is_night(run):
		q.append(["打水", func(): perform("well", "打水"), false])
	if Post.is_night(run) and not run.sleeping:
		q.append(["就寝", func(): perform("bed", "就寝"), false])
	elif State.attr(run, "energy") < 30:
		q.append(["小憩", func(): perform("bed", "小憩"), false])
	return q.slice(0, 4)


func _left_bottom(run: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Hud.seal("囊", Dialogs.inventory, "存货（I）", 58))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 6)
	var busy := Post.can_act(run, 0) != ""
	for a in _quick_actions(run):
		q.add_child(Hud.button(a[0], a[1], busy and not a[2], "", 14))
	if q.get_child_count() == 0:
		q.add_child(Hud.text("（暂无急事）", 13, Hud.FAINT))
	v.add_child(q)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 4)
	for k in SPEED_LABELS.size():
		var b: Button
		if Game.speed == k:
			b = Hud.primary(SPEED_LABELS[k], _set_speed.bind(k), false, "", 14)
		else:
			b = Hud.button(SPEED_LABELS[k], _set_speed.bind(k), false, "", 14)
		b.custom_minimum_size = Vector2(46, 30)
		sp.add_child(b)
	var status := Hud.text("", 13, Hud.SUB)
	sp.add_child(status)
	_live.speed_status = status
	v.add_child(sp)
	h.add_child(v)
	var p := Hud.panel(h, Hud.BG_SOFT)
	hud.add_child(p)
	Hud.pin(p, Control.PRESET_BOTTOM_LEFT, 14)


func _set_speed(k: int) -> void:
	Game.speed = k
	Game.refresh()


func _center_bottom(run: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	if not run.wish.is_empty():
		var wish: Dictionary = Data.table("wishes")[run.wish.id]
		var t := Hud.text(("【心愿·已了】" if run.wish.done else "【心愿】") + wish.text, 16, Hud.GREEN if run.wish.done else Color("#f0c674"), true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(Hud.panel(t, Hud.BG_SOFT))
	if not run.log.is_empty():
		var last: String = run.log[-1]
		var cut := last.find("】")
		var l := Hud.text(last.substr(cut + 1) if cut > 0 else last, 13, Hud.SUB)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	hud.add_child(v)
	Hud.pin(v, Control.PRESET_CENTER_BOTTOM, 16)


## 每帧只改数值，不重建。
func _update_live() -> void:
	var run: Dictionary = Game.run
	if _live.is_empty() or run.phase != "post":
		return
	if _live.has("time"):
		(_live.time as Label).text = "%s  %s" % [Post.shichen(run), Post.clock_text(run)]
	if _live.has("dial"):
		_live.dial.minutes = Post.clock(run)
	if _live.has("wave_cd"):
		var left := Post.WAVE_AT - Post.day_minute(run)
		(_live.wave_cd as Label).text = ("还有 %s" % Hud.duration(left)) if left > 0 else "来了！"
	if _live.has("bars"):
		for k in _live.bars:
			var r: Dictionary = _live.bars[k]
			var mx := State.attr_max(run, k)
			(r.bar as ProgressBar).max_value = mx
			(r.bar as ProgressBar).value = float(run.attrs[k])
			(r.value as Label).text = "%d/%d" % [State.attr(run, k), mx]
	if _live.has("place"):
		var pl: Label = _live.place
		pl.visible = Game.placing != ""
		if pl.visible:
			var fd: Dictionary = Home.data(Game.placing)
			var fsz := Home.size_of(Game.placing, Game.placing_rot)
			pl.text = "摆放 %s（%.1f×%.1f）· 左键放下 · R 转向 · Esc 取消" % [
				fd.get("name", ""), fsz.x, fsz.y]
	if _live.has("speed_status"):
		var s := ""
		if Game.speed == 0:
			s = "已暂停（空格继续）"
		elif run.sleeping:
			s = "睡眠加速中"
		elif Post.is_busy(run):
			s = "%s中 · 加速" % run.busy.label
		(_live.speed_status as Label).text = s


## 菜畦清单里的倒计时（整点和重画时更新；每帧改字体颜色会让界面每帧重新排版）。
func _update_crops() -> void:
	var run: Dictionary = Game.run
	var crops: Dictionary = Data.table("crops")
	for row in _live.get("crops", []):
		var plot: Dictionary = row[0]
		if plot.crop == "":
			continue
		var ripe := Post.crop_ripe(plot)
		var dry := Post.plot_dry(run, plot)
		(row[1] as Label).text = "✓" if ripe else ("◌" if dry else "●")
		(row[1] as Label).add_theme_color_override("font_color", Hud.GOLD if ripe else (Hud.CYAN if dry else Hud.GREEN))
		(row[2] as Label).text = "可收获" if ripe else ("缺水停长" if dry else Hud.duration((float(crops[plot.crop].days) - float(plot.days)) * 1440.0))
		(row[2] as Label).add_theme_color_override("font_color", Hud.GOLD if ripe else (Hud.CYAN if dry else Hud.SUB))
