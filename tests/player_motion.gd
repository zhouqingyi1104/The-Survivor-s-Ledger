extends Node3D
## 让真实物理帧驱动主角、输入和碰撞。同一路线分别按 30、60、120 Hz 运行。

const Player = preload("res://scripts/world/player.gd")
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame


func box_obstacle(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = center
	body.add_child(collider)
	add_child(body)


func ground() -> void:
	box_obstacle(Vector3.DOWN / 2, Vector3(40, 1, 40))
	box_obstacle(Vector3(0, 1, -3), Vector3(8, 2, 0.2))
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-12, 0, -12), Vector3(12, 0, -12), Vector3(12, 0, 12), Vector3(-12, 0, 12)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	add_child(region)


func spawn(role: String, at: Vector3) -> Player:
	var player := Player.new()
	player.position = at
	add_child(player)
	player.setup(role)
	check(player.figure.hero and player.figure.kind == role and player.figure._look.body == Player.Figure.HERO_BODY, "%s 没有进入正常主角骨架" % role)
	return player


func horizontal_velocity(player: Player) -> Vector2:
	var v := player.get_real_velocity()
	return Vector2(v.x, v.z)


func start_turn_stop(hz: int, role: String) -> Vector3:
	Engine.physics_ticks_per_second = hz
	var player := spawn(role, Vector3(-5, 0.02, 6))
	await ticks(4)
	Input.action_press("move_up")
	await ticks(1)
	var first := horizontal_velocity(player).length()
	await ticks(1)
	var second := horizontal_velocity(player).length()
	check(first > 0.0 and first < second and second < Player.SPEED, "%d Hz 起步没有逐帧加速" % hz)
	await ticks(hz - 2)
	var straight := horizontal_velocity(player)
	check(absf(straight.y + Player.SPEED) < 0.05 and absf(straight.x) < 0.05, "%d Hz 匀速直行速度有误" % hz)
	var before_turn: Vector3 = player.position
	Input.action_release("move_up")
	Input.action_press("move_right")
	var before_yaw: float = player.figure.rotation.y
	await ticks(1)
	var corner := horizontal_velocity(player)
	check(corner.x > 0 and corner.y < -0.05, "%d Hz 转角一帧切断了来向运动" % hz)
	check(absf(angle_difference(before_yaw, player.figure.rotation.y)) < PI / 4.0, "%d Hz 转向瞬间跳过了大半个直角" % hz)
	await ticks(hz - 1)
	check(horizontal_velocity(player).distance_to(Vector2.RIGHT * Player.SPEED) < 0.06, "%d Hz 转身后走偏" % hz)
	check(player.figure.global_basis.z.normalized().dot(Vector3.RIGHT) > 0.97, "%d Hz 匀速时人物朝向没有跟上方向" % hz)
	var release_x: float = player.position.x
	Input.action_release("move_right")
	await ticks(1)
	var braking := horizontal_velocity(player).length()
	check(braking > 0.0 and braking < Player.SPEED, "%d Hz 松键时没有收步" % hz)
	await ticks(hz / 2)
	check(horizontal_velocity(player).length() < 0.01 and not player.figure.moving, "%d Hz 松键后未站稳" % hz)
	var end: Vector3 = player.position
	var stop_distance := end.x - release_x
	check(stop_distance > 0.04 and stop_distance < 0.55, "%d Hz 松键后滑行异常：%.3f 米" % [hz, stop_distance])
	print("主角 %d Hz　首步 %.2f 米/秒　松键后 %.3f 米" % [hz, first, stop_distance])
	player.queue_free()
	await ticks(2)
	return Vector3(before_turn.z, end.x, stop_distance)


func wall_and_work() -> void:
	var player := spawn("watchman", Vector3(0, 0.02, -1))
	await ticks(4)
	Input.action_press("move_up")
	await ticks(65)
	check(player.position.z > -3.0 and player.position.z < -2.5 and player.is_on_wall(), "卡墙夹具没有挡住主角")
	check(horizontal_velocity(player).length() < 0.02 and not player.figure.moving, "顶住墙仍在原地跑步")
	Input.action_press("move_right")
	await ticks(15)
	check(horizontal_velocity(player).x > 0.5 and player.figure.moving, "贴墙斜行没有据真实位移恢复步态")
	player.enabled = false
	var held_position := player.position
	await ticks(12)
	check(player.position.distance_to(held_position) < 0.02 and not player.figure.moving, "打开面板时仍带速度移动")
	Input.action_release("move_up")
	Input.action_release("move_right")
	player.enabled = true
	var target := player.global_position + Vector3(2, 0, 2)
	var arrivals := []
	player.arrived.connect(func():
		arrivals.append(player.global_position)
		player.figure.working = true
		player.enabled = false)
	player.walk_to(target)
	await ticks(180)
	check(arrivals.size() == 1 and not player.is_walking(), "自动走向工作点未触发一次抵达")
	if not arrivals.is_empty():
		var arrived_at: Vector3 = arrivals[0]
		check(target.distance_to(arrived_at) < 0.6, "未走至工作点便已开工")
		check(player.global_position.distance_to(arrived_at) < 0.02 and not player.figure.moving, "开工后角色继续滑离操作点")
	player.queue_free()
	await ticks(2)


func villager() -> void:
	var npc := Player.Figure.new()
	add_child(npc)
	npc.setup("villager")
	npc.set_process(false)
	npc.moving = true
	npc.move_speed = 3.4
	npc._process(1.0 / 60.0)
	check(npc._ap.current_animation == "Jog_Fwd", "街坊慢跑动作改变")
	npc.moving = false
	npc.working = true
	npc._process(1.0 / 60.0)
	check(npc._ap.current_animation == "Interact", "街坊工作动作改变")
	npc.working = false
	npc._process(1.0 / 60.0)
	check(npc._ap.current_animation == "Idle", "街坊站定后没有恢复待机")
	npc.queue_free()


func _ready() -> void:
	ground()
	var original_hz := Engine.physics_ticks_per_second
	var at_60 := await start_turn_stop(60, "scholar")
	var at_30 := await start_turn_stop(30, "herbalist")
	var at_120 := await start_turn_stop(120, "escort")
	check(at_30.distance_to(at_60) < 0.15 and at_120.distance_to(at_60) < 0.15, "相同输入持续时间在不同物理帧率下轨迹偏差过大")
	Engine.physics_ticks_per_second = 60
	await wall_and_work()
	villager()
	Engine.physics_ticks_per_second = original_hz
	print("[player_motion] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
