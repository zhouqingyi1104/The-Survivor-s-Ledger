extends CharacterBody3D
## 主角：WASD 移动（相对镜头方向），或者点地面 / 点物件后自己寻路走过去。
## 路径向导航服务器要一次，自己按水平距离一段段走：导航网格比地面高出一两格（0.25～0.5 米），
## NavigationAgent3D 按三维距离判断"到没到路点"，人站在屋里地面上时永远判不到，会卡在原地。

const Figure = preload("res://scripts/world/character.gd")

signal arrived

## 慢跑的速度（和 Jog_Fwd 动作原速的步子对上）
const SPEED := 3.4

var figure: Node3D
var cam_yaw := 0.0
var enabled := true

var _auto := false
var _goal := Vector3.ZERO
var _path := PackedVector3Array()
var _idx := 0
var _walk_time := 0.0
var _stuck_time := 0.0


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


func is_walking() -> bool:
	return _auto


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if enabled:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input.y += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input.x += 1
	var dir := Vector3(input.x, 0, input.y).normalized().rotated(Vector3.UP, cam_yaw)
	if dir.length() > 0.1:
		_auto = false
	elif _auto and enabled:
		_walk_time += delta
		while _idx < _path.size() - 1 and _flat_dist(_path[_idx]) < 0.3:
			_idx += 1
		# 到了；或者被挡住一秒多没挪窝、走了太久，就地算到
		if _flat_dist(_goal) < 0.55 or _stuck_time > 1.2 or _walk_time > 10.0:
			_auto = false
			arrived.emit()
		else:
			var next := _path[_idx]
			dir = Vector3(next.x - global_position.x, 0, next.z - global_position.z).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	var before := global_position
	move_and_slide()
	if _auto and enabled and dir.length() > 0.1:
		_stuck_time = _stuck_time + delta if before.distance_to(global_position) < SPEED * delta * 0.2 else 0.0
	figure.moving = dir.length() > 0.1
	var real := get_real_velocity()
	figure.move_speed = Vector2(real.x, real.z).length()
	if figure.moving:
		figure.face(dir, minf(1.0, delta * 12.0))


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
