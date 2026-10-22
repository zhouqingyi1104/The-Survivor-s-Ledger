extends Node
## 开发用：在真实界面里体检宅院——导航网格覆盖、点地面走路、打水后还能不能走、帧时间。
## 存档只读不回写（no_save）。
## 运行：godot --path . res://tests/play_check.tscn -- [--save=<存档路径> | --demo=post] [--seconds=8]

const Post = preload("res://scripts/core/post.gd")
const Demo = preload("res://scripts/dev/demo.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

var main: Control
var _frame_us: Array = []
var _last := 0


func _ready() -> void:
	var save := ""
	var demo := "post"
	var seconds := 8.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--demo="):
			demo = arg.trim_prefix("--demo=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
	Game.no_save = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	if save != "":
		Game.save_path = save
		Game.continue_game()
	else:
		Demo.setup(demo)
	await _frames(10)
	var home := screen()
	if Game.screen != "post" or home == null:
		print("没进宅院：", Game.screen)
		get_tree().quit()
		return
	var run: Dictionary = Game.run
	print("弹窗：%s 菜单：%s 事件：%s 天亮：%s 尸潮：%s 战报：%s" % [str(main._modals.keys()), str(home._menu.visible), run.pending_event, str(run.dawn_due), str(run.wave_due), str(not run.wave_report.is_empty())])
	# 只为体检：把挡着的事清掉（存档不回写）
	run.pending_event = ""
	run.dawn_due = false
	run.wave_report = {}
	run.busy = {}
	_close_modals()
	await _frames(3)
	print("清掉后：弹窗 %s，能走：%s" % [str(main._modals.keys()), str(home.player.enabled)])
	print("时刻 t=%d 第%d日 %s  busy=%s sleeping=%s" % [int(run.t), int(run.pday), Post.clock_text(run), str(run.busy), str(run.sleeping)])
	_nav_map(home)
	await _walk_tests(home)
	await _audio_test(home)
	await _water_test(home)
	await _camera_test(home)
	await _perf(home, seconds)
	get_tree().quit()


func screen() -> Node:
	var holder: Node = main.get_child(1)
	return holder.get_child(0) if holder.get_child_count() > 0 else null


func _close_modals() -> void:
	for key in main._modals.keys():
		main.close_modal(key)


## 院子里每 0.5 米看一眼有没有导航网格：. 能走  # 走不了
func _nav_map(home: Node) -> void:
	var map: RID = home.world.get_world_3d().navigation_map
	var lines := []
	var z := -8.0
	while z <= 7.0:
		var row := ""
		var x := -10.0
		while x <= 10.0:
			var p := Vector3(x, 0.1, z)
			var c := NavigationServer3D.map_get_closest_point(map, p)
			row += "." if Vector2(c.x - p.x, c.z - p.z).length() < 0.15 else "#"
			x += 0.5
		lines.append(row)
		z += 0.5
	print("导航网格（上北下南，x -10..10，z -8..7）：\n" + "\n".join(lines))


func _walk_tests(home: Node) -> void:
	var targets := [Vector3(0, 0, 3), Vector3(0, 0, -1.5), Vector3(3.5, 0, -0.1), Vector3(-3, 0, 0.1), Vector3(0, 0, -5.5), Vector3(-6, 0, 2), Vector3(6, 0, 4)]
	for t in targets:
		var p: CharacterBody3D = home.player
		p.walk_to(t)
		var waited := 0.0
		while p.is_walking() and waited < 9.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		var d := Vector2(p.global_position.x - t.x, p.global_position.z - t.z).length()
		print("走到 %s：%s，用时 %.1f 秒，差 %.2f 米" % [str(t), "到了" if d < 0.8 else "没到", waited, d])
		if d >= 0.8:
			print("   位置 %s 速度 %s enabled=%s on_floor=%s" % [str(p.global_position), str(p.velocity), str(p.enabled), str(p.is_on_floor())])
			var kc := p.move_and_collide(Vector3(0, 0, -0.3), true)
			print("   试推 0.3 米：", "撞到 " + str(kc.get_collider()) + " " + str(kc.get_collider().get_parent().name) if kc != null else "没撞")


## 声音真的在响：各总线的峰值电平（dB，-200 是静音）。
func _audio_test(_home: Node) -> void:
	var peaks := {"Music": -200.0, "Ambience": -200.0, "Sfx": -200.0}
	Sfx.play("bangzi")
	for k in 60:
		await get_tree().process_frame
		for b in peaks:
			var i := AudioServer.get_bus_index(b)
			peaks[b] = maxf(peaks[b], AudioServer.get_bus_peak_volume_left_db(i, 0))
	print("声音：配乐《%s》，各总线峰值 %s" % [Sfx.music_name(), str(peaks)])


func _water_test(home: Node) -> void:
	if Game.run.well_used:
		Game.run.well_used = false
	home.perform("well", "打水")
	var waited := 0.0
	while not Post.is_busy(Game.run) and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("打水：", "开始了" if Post.is_busy(Game.run) else "没开始 " + str(Post.can_act(Game.run, 2)))
	while Post.is_busy(Game.run) and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await _frames(3)
	var p: CharacterBody3D = home.player
	var before := p.global_position
	p.walk_to(Vector3(0, 0, 3))
	waited = 0.0
	while p.is_walking() and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("打完水后：busy=%s enabled=%s 走了 %.2f 米" % [str(Post.is_busy(Game.run)), str(p.enabled), before.distance_to(p.global_position)])


## 右键拖动能不能转视角；再拍两张：人站在南墙根（被墙挡）、站在正屋檐下（屋顶要淡掉）。
func _camera_test(home: Node) -> void:
	var rig: Node3D = home.rig
	var yaw0: float = rig.yaw
	var pitch0: float = rig.pitch
	var center := get_viewport().get_visible_rect().size / 2.0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = center
	Input.parse_input_event(press)
	for k in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = center + Vector2(20 * (k + 1), 6 * (k + 1))
		mm.relative = Vector2(20, 6)
		mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
		Input.parse_input_event(mm)
		await get_tree().process_frame
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_RIGHT
	rel.pressed = false
	rel.position = center
	Input.parse_input_event(rel)
	await _frames(3)
	print("右键拖动：yaw %.2f → %.2f，pitch %.1f → %.1f" % [yaw0, rig.yaw, pitch0, rig.pitch])
	# 左键点地面：人要走过去
	rig.yaw = 0.0
	rig.pitch = -54.0
	home.player.global_position = Vector3(0, 0, 3)
	rig.snap()
	await _frames(20)
	var target := Vector3(-1.0, 0, 0.0)
	var sp: Vector2 = rig.cam.unproject_position(target)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = sp
		Input.parse_input_event(b)
		await get_tree().process_frame
	var w := 0.0
	await _frames(3)
	while home.player.is_walking() and w < 6.0:
		await get_tree().process_frame
		w += get_process_delta_time()
	var p: Vector3 = home.player.global_position
	print("左键点地面 %s：人到了 %s（差 %.2f 米）" % [str(target), str(p), Vector2(p.x - target.x, p.z - target.z).length()])
	# 滚轮缩放
	var d0: float = rig.dist
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = sp
	Input.parse_input_event(wheel)
	await _frames(2)
	print("滚轮：距离 %.1f → %.1f" % [d0, rig.dist])
	rig.yaw = 0.0
	rig.pitch = -54.0
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
	if out == "":
		return
	for spot in [["south_wall", Vector3(3.2, 0, 6.3)], ["gate", Vector3(0.4, 0, 6.2)], ["hall", Vector3(1.0, 0, -5.4)]]:
		home.player.global_position = spot[1]
		rig.snap()
		await _frames(40)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("occl_%s.png" % spot[0]))
	print("遮挡截图已保存")


func _perf(home: Node, seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Game.speed = 3
	Game.refresh()
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	var refreshes := [0]
	Game.changed.connect(func(): refreshes[0] += 1)
	_frame_us.clear()
	_last = Time.get_ticks_usec()
	var pts := [Vector3(-3, 0, 0.5), Vector3(3, 0, -1), Vector3(0, 0, 4), Vector3(-5, 0, -5.5)]
	var k := 0
	var draw_max := 0
	var obj_max := 0
	while (Time.get_ticks_usec() - t0) / 1e6 < seconds:
		var p: CharacterBody3D = home.player
		if not p.is_walking() and p.enabled:
			p.walk_to(pts[k % pts.size()])
			k += 1
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frame_us.append(now - _last)
		_last = now
		draw_max = maxi(draw_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		obj_max = maxi(obj_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	var arr := _frame_us.duplicate()
	arr.sort()
	var total := 0
	for v in arr:
		total += v
	var n := arr.size()
	print("帧时间（不锁帧）：%d 帧，平均 %.1f ms（%.0f FPS），中位 %.1f，95%% %.1f，最大 %.1f ms" % [n, total / 1000.0 / n, n / (total / 1e6), arr[n / 2] / 1000.0, arr[int(n * 0.95)] / 1000.0, arr[n - 1] / 1000.0])
	var spikes := 0
	for v in arr:
		if v > 33000:
			spikes += 1
	print("超过 33ms 的卡顿帧：%d；刷新界面 %d 次；最多绘制调用 %d，最多物体 %d；节点 %d" % [spikes, refreshes[0], draw_max, obj_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	# 单次刷新（重画 HUD + 同步世界）要多久
	var r0 := Time.get_ticks_usec()
	for i in 5:
		home.refresh()
	print("refresh() 平均 %.1f ms" % ((Time.get_ticks_usec() - r0) / 5000.0))
	var run: Dictionary = Game.run
	for part in ["clear", "sync_world", "_left_top", "_right_top", "_right_bottom", "_left_bottom", "_center_bottom", "after_build"]:
		var p0 := Time.get_ticks_usec()
		for i in 5:
			match part:
				"clear":
					UI.clear(home.hud)
				"sync_world", "after_build":
					home.call(part)
				_:
					home.call(part, run)
		print("   %s 平均 %.2f ms" % [part, (Time.get_ticks_usec() - p0) / 5000.0])
	home.refresh()
	var s0 := Time.get_ticks_usec()
	for i in 5:
		home.world.sync(Game.run)
	print("world.sync() 平均 %.1f ms" % ((Time.get_ticks_usec() - s0) / 5000.0))


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame
