extends RefCounted
## 按键重绑：默认绑定快照、改绑、冲突检测、user://input.cfg 存取。
## **默认绑定只有一份来源——project.godot 的 [input] 节**，这里不写第二份键位表；
## boot() 在启动时把它快照下来（运行时改过 InputMap 后，project 里的默认值内存里就没了，
## 「恢复默认」靠这份快照）。只认键盘（physical_keycode），鼠标/手柄不在本期。

## 存档路径做成静态变量：测试指向 user:// 下的临时文件，不碰玩家真配置。
static var cfg_path := "user://input.cfg"
const SECTION := "binding"

## boot() 时取下的默认绑定快照。「恢复默认」用它把 InputMap 写回去——
## 运行时改过 InputMap 后，project.godot 里的默认值内存里就没了。
static var _defaults: Dictionary = {}

## 设置界面里的顺序与中文名。没列进来的动作不显示（动作可以加，界面要有名字）。
const ORDER := [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "confirm", "speed_pause", "speed_1", "speed_2", "speed_3",
	"sleep", "wait", "inventory", "journal", "agenda", "guard", "rotate", "night_panel", "cancel",
]
const LABELS := {
	"move_up": "走 · 上",
	"move_down": "走 · 下",
	"move_left": "走 · 左",
	"move_right": "走 · 右",
	"interact": "翻找 / 查看",
	"confirm": "确认",
	"speed_pause": "暂停 / 继续",
	"speed_1": "速度 · 一",
	"speed_2": "速度 · 二",
	"speed_3": "速度 · 三",
	"sleep": "就寝",
	"wait": "等一刻（跳到下个节点）",
	"inventory": "行囊",
	"journal": "劫余录",
	"agenda": "今日差事",
	"guard": "招架",
	"rotate": "转个方向",
	"night_panel": "夜面",
	"cancel": "取消 / 设置",
}

## 启动时调用：先快照默认绑定，再把 cfg 里存过的改绑套回去。
static func boot() -> void:
	_defaults = snapshot()
	var saved := read()
	for action in saved:
		apply(action, saved[action])


## 当前 InputMap 里各动作的物理键码。改绑后这就是新值。
static func keys_of(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(int((ev as InputEventKey).physical_keycode))
	return out


## 把一个动作的整个绑定换成 keys（替换式：改键后旧键位让位，多键默认靠恢复默认拿回）。
static func apply(action: String, keys: Array) -> void:
	InputMap.action_erase_events(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = int(key)
		InputMap.action_add_event(action, ev)


## 这个键现在归哪个动作；没人要返回 ""。
static func owner_of(key: int) -> String:
	for action in ORDER:
		if key in keys_of(action):
			return action
	return ""


## 改绑。返回 false 的两种情况：空动作/空键，或**键已属别的动作**（冲突，
## 界面要提示给了谁）。绑到自己已有的键上算不用改，返回 true 且不动 cfg。
static func rebind(action: String, key: int) -> bool:
	if action == "" or int(key) <= 0:
		return false
	if key in keys_of(action):
		return true
	if owner_of(key) != "":
		return false
	apply(action, [key])
	save(action, [key])
	return true


## 读 cfg。只认 ORDER 里的动作；手改出来的脏值（字符串、0、空数组）一律过滤。
## 不叫 load()——那是 GDScript 内建函数，类内裸调用会解析到它身上去。
static func read() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(cfg_path):
		return out
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return out
	for action in ORDER:
		if not cfg.has_section_key(SECTION, action):
			continue
		var clean: Array = []
		for k in cfg.get_value(SECTION, action, []):
			var code := int(k)
			if code > 0:
				clean.append(code)
		if not clean.is_empty():
			out[action] = clean
	return out


## 把一次改绑并进 cfg（其他动作已存的行不动）。
static func save(action: String, keys: Array) -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(cfg_path):
		cfg.load(cfg_path)
	cfg.set_value(SECTION, action, keys)
	cfg.save(cfg_path)


## 全部恢复默认：InputMap 回到启动快照，cfg 删掉。
static func restore() -> void:
	for action in _defaults:
		apply(action, _defaults[action])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))


## 键位显示名（界面用）。物理键码直接问引擎，不自己抄一张表。
static func key_name(key: int) -> String:
	return OS.get_keycode_string(int(key))


## 第一个绑定键的显示名（HUD 提示用，一行放不下两个键）。没有绑定返回 ""。
static func first_key_name(action: String) -> String:
	var keys := keys_of(action)
	return key_name(keys[0]) if not keys.is_empty() else ""


## 启动默认绑定的快照。boot() 里取，恢复默认时用。
static func snapshot() -> Dictionary:
	var out := {}
	for action in ORDER:
		out[action] = keys_of(action)
	return out
