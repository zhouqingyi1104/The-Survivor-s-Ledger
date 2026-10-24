extends Control
## 改键时临时用：收下一个按键（Esc 算取消），跳过纯修饰键。
## 挂在 Dialogs 下常驻，active 开着才收；收到的键交给 captured 信号，自己不做判断。

signal captured(key: int)

var active := false

## 纯修饰键不当热键（按 Shift 是为了组合，不是要把它绑上去）
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]


func _ready() -> void:
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode in MODIFIERS:
			return
		# 收下就不再往下传：焦点已释放，按钮不会被顺带触发
		active = false
		get_viewport().set_input_as_handled()
		captured.emit(key.physical_keycode)
