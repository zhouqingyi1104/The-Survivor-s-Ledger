extends SceneTree
## 按键重绑与画面选项的无界面测试：默认绑定、改绑、冲突、cfg 往返、脏数据、恢复默认。
## 运行：godot --headless --path . --script res://tests/input_settings.gd
## cfg 路径全部指向 user:// 下的进程临时文件，不碰玩家真配置。

const InputCfg = preload("res://scripts/core/input_cfg.gd")
const VideoCfg = preload("res://scripts/core/video_cfg.gd")

const DEFAULTS := {
	"move_up": [87, 4194320], "move_down": [83, 4194322],
	"move_left": [65, 4194319], "move_right": [68, 4194321],
	"interact": [69], "confirm": [32], "speed_pause": [32],
	"speed_1": [49], "speed_2": [50], "speed_3": [51], "sleep": [78], "wait": [81],
	"inventory": [73, 4194306], "journal": [74], "agenda": [84], "guard": [75], "rotate": [82],
	"night_panel": [70], "cancel": [4194305],
}

var checks := 0
var failures := 0


func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(msg)


func _initialize() -> void:
	InputCfg.cfg_path = "user://test-input-%d.cfg" % OS.get_process_id()
	VideoCfg.cfg_path = "user://test-video-%d.cfg" % OS.get_process_id()
	for path in [InputCfg.cfg_path, VideoCfg.cfg_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 1. 默认绑定齐全且与 docs/24 的表一致（手写 project.godot [input] 的合同）
	for action in DEFAULTS:
		check(InputMap.has_action(action), "InputMap 缺动作：" + action)
		check(InputCfg.keys_of(action) == DEFAULTS[action],
			"%s 默认键位不对：%s" % [action, str(InputCfg.keys_of(action))])

	# 2. 键名显示非空（界面直接用）
	for action in DEFAULTS:
		for key in DEFAULTS[action]:
			check(not InputCfg.key_name(key).is_empty(), "键名显示为空：%d（%s）" % [key, action])
	print("[按键表] " + " · ".join(DEFAULTS.keys().map(func(a): return "%s=%s" % [a, InputCfg.keys_of(a).map(func(k): return InputCfg.key_name(k))])))

	# 3. ORDER/LABELS 对齐：界面每行都有中文名，没有多余项
	for action in InputCfg.ORDER:
		check(InputCfg.LABELS.has(action), "动作没有中文名：" + action)
	check(InputCfg.LABELS.size() == InputCfg.ORDER.size(), "LABELS 与 ORDER 不一致")

	# 4. boot() 快照默认绑定
	InputCfg.boot()
	check(InputCfg._defaults.size() == DEFAULTS.size(), "快照动作数不对：%d" % InputCfg._defaults.size())
	check(InputCfg._defaults["interact"] == [69], "快照内容不对")

	# 5. 改绑生效（InputMap 真的变了）
	# 拿 Z 做改绑靶子：Q 现在是「等一刻」的默认键，不能抢
	check(InputCfg.rebind("interact", KEY_Z), "interact 改绑 Z 失败")
	check(InputCfg.keys_of("interact") == [90], "改绑后 InputMap 没变：%s" % str(InputCfg.keys_of("interact")))
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Z
	ev.pressed = true
	check(ev.is_action_pressed("interact"), "改绑后 Z 按不出 interact")
	ev.physical_keycode = KEY_E
	check(not ev.is_action_pressed("interact"), "改绑后 E 还能触发 interact（旧键没让位）")

	# 6. 冲突拒绝：Q 已是 interact 的，sleep 绑 Q 必须失败且 sleep 不动
	#    （interact 上一步刚让出 E，所以冲突要拿现在有人要的键来测）
	check(not InputCfg.rebind("sleep", KEY_Z), "冲突键竟然绑成功了")
	check(InputCfg.keys_of("sleep") == [78], "冲突拒绝后 sleep 的键位被改了")
	check(InputCfg.owner_of(KEY_Z) == "interact", "owner_of 认不出 Z 归 interact")
	check(InputCfg.owner_of(KEY_Y) == "", "owner_of 把没人的键说成有人要")

	# 7. 绑到自己已有的键 = 不用改，不动 cfg
	InputCfg.rebind("inventory", KEY_H)
	check(InputCfg.rebind("inventory", KEY_H), "绑自己的键返回了 false")
	var before_round := InputCfg.read()
	check(before_round.has("interact") and before_round.has("inventory"), "cfg 没存下改绑：%s" % str(before_round))
	check(not before_round.has("sleep"), "没改过的动作也进了 cfg")

	# 8. 恢复默认：InputMap 回默认、cfg 删掉
	InputCfg.restore()
	check(InputCfg.keys_of("interact") == [69], "恢复默认后 interact 没回 E")
	check(InputCfg.keys_of("inventory") == [73, 4194306], "恢复默认后 inventory 没回 I+Tab")
	check(not FileAccess.file_exists(InputCfg.cfg_path), "恢复默认后 cfg 还在")

	# 9. cfg 往返 + 脏数据过滤（手改 cfg 是权力用户场景）
	var cfg := ConfigFile.new()
	cfg.set_value("binding", "interact", [90])
	cfg.set_value("binding", "sleep", "N")       # 字符串
	cfg.set_value("binding", "journal", [0])     # 0 不是键
	cfg.set_value("binding", "rotate", [])       # 空数组
	cfg.set_value("binding", "no_such_action", [90])  # 不存在的动作
	cfg.save(InputCfg.cfg_path)
	var loaded := InputCfg.read()
	check(loaded.size() == 1 and loaded["interact"] == [90], "脏 cfg 没被过滤干净：%s" % str(loaded))

	# 10. 画面选项往返 + apply 不炸（headless 的 DisplayServer 是哑实现）
	var opts := {"fullscreen": true, "resolution": 2, "vsync": false}
	VideoCfg.save(opts)
	var back := VideoCfg.read()
	check(back == opts, "画面选项往返不一致：%s" % str(back))
	VideoCfg.apply(back)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		or DisplayServer.get_name() == "headless", "全屏没套上（且不是 headless）")
	# 脏值：类型不对回默认、越界夹紧
	cfg = ConfigFile.new()
	cfg.set_value("video", "fullscreen", "yes")
	cfg.set_value("video", "resolution", 99)
	cfg.set_value("video", "vsync", true)
	cfg.save(VideoCfg.cfg_path)
	var dirty := VideoCfg.read()
	check(dirty["fullscreen"] == false and dirty["resolution"] == 2 and dirty["vsync"] == true,
		"画面脏值没处理好：%s" % str(dirty))
	VideoCfg.apply(VideoCfg.defaults())

	# 收尾：删临时 cfg，InputMap 恢复默认再退出
	InputCfg.restore()
	for path in [InputCfg.cfg_path, VideoCfg.cfg_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 11. 真实路径的 boot（Settings autoload 每次启动就走这条路）：
	#     往真正的 user://input.cfg 写一份改绑，boot() 后 InputMap 必须变；
	#     验完恢复原样（本来没有就删掉，本来有就还原），不把测试键位留给以后的局。
	InputCfg.cfg_path = "user://input.cfg"
	var backup := ""
	if FileAccess.file_exists("user://input.cfg"):
		backup = FileAccess.get_file_as_string("user://input.cfg")
	var real := ConfigFile.new()
	real.set_value("binding", "interact", [KEY_Z])
	real.save(InputCfg.cfg_path)
	InputCfg.boot()
	check(InputCfg.keys_of("interact") == [90], "真实 cfg 的改绑没被 boot 套上")
	InputCfg.restore()
	if backup != "":
		var bf := FileAccess.open("user://input.cfg", FileAccess.WRITE)
		bf.store_string(backup)
		bf.close()
	check(FileAccess.file_exists("user://input.cfg") == (backup != ""), "真实 cfg 没还原成原样")
	check(InputCfg.keys_of("interact") == [69], "恢复默认没把 interact 变回 E")

	print("[input_settings] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)
