extends Node3D
## 跟随镜头：斜俯视，滚轮缩放，右键（或中键）拖动转视角：左右转向、上下调俯仰。
## 演出时可以临时挪到别处（goto / release）。

var target: Node3D
var yaw := 0.0
var pitch := -54.0
var dist := 17.0
var min_dist := 7.0
var max_dist := 26.0
var cam: Camera3D
var input_enabled := true
var shake := 0.0

var _focus := Vector3.ZERO
var _override := false
var _ov_pos := Vector3.ZERO
var _ov_look := Vector3.ZERO


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	if target != null:
		_focus = target.global_position


func _process(delta: float) -> void:
	var cam_pos: Vector3
	var look: Vector3
	if _override:
		cam_pos = cam.global_position.lerp(_ov_pos, 1.0 - exp(-2.5 * delta))
		look = _ov_look
	else:
		if target != null:
			_focus = _focus.lerp(target.global_position + Vector3(0, 1.0, 0), 1.0 - exp(-6.0 * delta))
		var offset := Vector3(0, 0, dist).rotated(Vector3.RIGHT, deg_to_rad(pitch)).rotated(Vector3.UP, yaw)
		cam_pos = _focus + offset
		look = _focus
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.0)
		cam_pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.25
	cam.global_position = cam_pos
	cam.look_at(look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _override:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(min_dist, dist - 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(max_dist, dist + 1.0)
	var mm := event as InputEventMouseMotion
	if mm != null and (mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch - mm.relative.y * 0.25, -80.0, -20.0)


## 演出用：镜头飞到 pos 看着 look。
func goto(pos: Vector3, look: Vector3) -> void:
	_override = true
	_ov_pos = pos
	_ov_look = look


func release() -> void:
	_override = false


func snap() -> void:
	if target != null:
		_focus = target.global_position + Vector3(0, 1.0, 0)
