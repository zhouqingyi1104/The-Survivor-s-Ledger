extends CharacterBody3D
## 主角：WASD 移动（相对镜头方向），或者点地面 / 点物件后自己寻路走过去。
## 路径向导航服务器要一次，自己按水平距离一段段走：导航网格比地面高出一两格（0.25～0.5 米），
## NavigationAgent3D 按三维距离判断"到没到路点"，人站在屋里地面上时永远判不到，会卡在原地。

const Figure = preload("res://scripts/world/character.gd")

signal arrived

## 慢跑的速度（和 Jog_Fwd 动作原速的步子对上）
const SPEED := Figure.JOG_SPEED
const ACCELERATION := 16.0
const BRAKING := 24.0
const ARRIVAL_RADIUS := 0.32

var figure: Node3D
var cam_yaw := 0.0
var enabled := true

var _auto := false
var _goal := Vector3.ZERO
var _path := PackedVector3Array()
var _idx := 0
var _walk_time := 0.0
var _stuck_time := 0.0
var _interaction_facing := Vector3.ZERO


func setup(kind: String) -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	figure = Figure.new()
	figure.xray = true
	figure.hero = true
	add_child(figure)
	figure.setup(kind)


## 寻路走到 pos，到了发 arrived。导航网格还没烘好时就直线走。
func walk_to(pos: Vector3) -> void:
	_goal = pos
	_auto = true
	_walk_time = 0.0
	_stuck_time = 0.0
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, pos, true)
	_path.append(pos)
	_idx = 0


func stop() -> void:
	_auto = false
	_interaction_facing = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if figure != null:
		figure.moving = false
		figure.move_speed = 0.0


func is_walking() -> bool:
	return _auto


func face_point(point: Vector3) -> void:
	_interaction_facing = Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if enabled:
		# 移动走输入动作（project.godot [input] 里 W/S/A/D + 方向键），改键不用动这里
		if Input.is_action_pressed("move_up"):
			input.y -= 1
		if Input.is_action_pressed("move_down"):
			input.y += 1
		if Input.is_action_pressed("move_left"):
			input.x -= 1
		if Input.is_action_pressed("move_right"):
			input.x += 1
	var dir := Vector3(input.x, 0, input.y).normalized().rotated(Vector3.UP, cam_yaw)
	var target_speed := SPEED
	if dir.length() > 0.1:
		_auto = false
	elif _auto and enabled:
		_walk_time += delta
		# 拐角要走到一个物理步长内再转向，否则会抄进家具的碰撞角。
		var waypoint_tolerance := maxf(0.075, SPEED * delta)
		while _idx < _path.size() - 1 and _flat_dist(_path[_idx]) < waypoint_tolerance:
			_idx += 1
		# 到了；或者被挡住一秒多没挪窝、走了太久，就地算到
		var remaining := _flat_dist(_goal)
		if remaining < ARRIVAL_RADIUS or _stuck_time > 1.2 or _walk_time > 10.0:
			stop()
			arrived.emit()
		else:
			var next := _path[_idx]
			dir = Vector3(next.x - global_position.x, 0, next.z - global_position.z).normalized()
			target_speed = minf(SPEED, sqrt(2.0 * BRAKING * maxf(remaining - ARRIVAL_RADIUS + 0.02, 0.0)))
			if _idx < _path.size() - 1:
				var next_leg := _path[_idx + 1] - next
				next_leg.y = 0
				if dir.dot(next_leg.normalized()) < 0.8:
					target_speed = minf(target_speed, sqrt(1.0 + 2.0 * BRAKING * _flat_dist(next)))
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var target := dir * target_speed
	var rate := BRAKING if target.is_zero_approx() or planar.dot(target) < 0.0 else ACCELERATION
	planar = planar.move_toward(target, rate * delta) if enabled else Vector3.ZERO
	velocity.x = planar.x
	velocity.z = planar.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	var real := get_real_velocity()
	var travel := Vector3(real.x, 0.0, real.z)
	if _auto and enabled and dir.length() > 0.1:
		_stuck_time = _stuck_time + delta if travel.length() < planar.length() * 0.2 else 0.0
	figure.move_speed = travel.length()
	figure.moving = figure.move_speed > 0.06 and enabled
	if figure.moving:
		_interaction_facing = Vector3.ZERO
		var heading := dir if dir.dot(travel) < 0.0 else travel
		figure.face_travel(heading, delta)
	elif not _interaction_facing.is_zero_approx():
		figure.face_travel(_interaction_facing, delta)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
