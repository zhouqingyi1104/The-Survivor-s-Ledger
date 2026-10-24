extends Node
## 启动时把玩家存过的设置套回去：按键重绑（InputMap）+ 画面选项（DisplayServer）。
## 逻辑全在 scripts/core/input_cfg.gd 和 video_cfg.gd（可无界面测试），这里只做调用。

const InputCfg = preload("res://scripts/core/input_cfg.gd")
const VideoCfg = preload("res://scripts/core/video_cfg.gd")


func _ready() -> void:
	# 先快照 project.godot 的默认键位，再套玩家改过的；画面同理。
	InputCfg.boot()
	VideoCfg.apply(VideoCfg.read())
