extends Node
## 打包版不连世情服务（路线图 A3）：离线判定、局内设置的写法、试玩报告里的写法要对得上。
## 真实包里"导出包就离线"由 export_smoke 在验证包中断言；这里用 offline_override 模拟两种环境。
## 运行：godot --headless --path . res://tests/director_offline.tscn

const State = preload("res://scripts/core/state.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

## 脚本错误只中止当前函数、_ready 照样往下跑：每个测试跑到底才记一次，最后对账
const TESTS := 3

var checks := 0
var failures := 0
var finished := 0
var main: Node


func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.run = State.new_run("scholar", Game.meta, 20261028)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(6)

	test_rule()
	await test_settings()
	test_report_ctx()
	check(finished == TESTS, "只跑完 %d / %d 个测试，有测试中途崩了" % [finished, TESTS])

	StoryDirector.offline_override = -1
	Game.run = {}
	main.queue_free()
	await frames(4)
	print("[director_offline] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func test_rule() -> void:
	StoryDirector.offline_override = -1
	check(FileAccess.file_exists("res://project.godot") and not StoryDirector.offline_build(), "开发工程里被当成了离线包")
	StoryDirector.offline_override = 1
	check(StoryDirector.offline_build(), "模拟打包版没判成离线")
	StoryDirector.offline_override = 0
	check(not StoryDirector.offline_build(), "模拟开发版判成了离线")
	finished += 1


func test_settings() -> void:
	# 打包版：只有一行灰掉的「本包离线」，没有开关
	StoryDirector.offline_override = 1
	Dialogs.settings(true)
	await frames(4)
	var modal: Node = main._modals.get("settings")
	var offline := _button_with_meta(modal, "director_offline")
	check(offline != null and offline.disabled and offline.text == "动态世情：本包离线", "打包版设置里没有灰掉的「本包离线」")
	check(_button_starting(modal, "动态世情：开启") == null and _button_starting(modal, "动态世情：关闭") == null, "打包版设置里还留着开关")
	check(_labels(modal).contains("局内状态和前世档案不会发出"), "打包版设置没说明不发数据")
	UI.close_modal("settings")
	await frames(4)
	# 开发版：照旧是开关
	StoryDirector.offline_override = 0
	Dialogs.settings(true)
	await frames(4)
	modal = main._modals.get("settings")
	check(_button_with_meta(modal, "director_offline") == null, "开发版设置里出现了「本包离线」")
	check(_button_starting(modal, "动态世情：开启") != null, "开发版设置里没有动态世情开关")
	UI.close_modal("settings")
	await frames(4)
	finished += 1


func test_report_ctx() -> void:
	StoryDirector.offline_override = 1
	check(str(Game._report_ctx(Game.run, {}).get("director")) == "offline", "打包版的报告环境没标离线")
	StoryDirector.offline_override = 0
	check(Game._report_ctx(Game.run, {}).get("director") is bool, "开发版的报告环境不再是开关状态")
	finished += 1


# ---------- 小工具 ----------

func _button_with_meta(node: Node, key: String) -> Button:
	if node == null:
		return null
	for b in node.find_children("*", "Button", true, false):
		if b.has_meta(key):
			return b
	return null


func _button_starting(node: Node, prefix: String) -> Button:
	if node == null:
		return null
	for b in node.find_children("*", "Button", true, false):
		if b.text.begins_with(prefix):
			return b
	return null


func _labels(node: Node) -> String:
	var lines := PackedStringArray()
	if node != null:
		for label in node.find_children("*", "Label", true, false):
			lines.append(label.text)
	return "\n".join(lines)


func frames(n := 6) -> void:
	for k in n:
		await get_tree().process_frame


func check(ok: bool, msg: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("断言失败：" + msg)
	return ok
