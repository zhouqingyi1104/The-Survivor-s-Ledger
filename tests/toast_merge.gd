extends Node
## 定向时序检查。启动前必须把 APPDATA、LOCALAPPDATA 隔离至本项目 build/ 下。
## tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/toast_merge.tscn

const UI = preload("res://scripts/ui/ui_kit.gd")

var main: Control
var checks := 0
var failures := 0


func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)


func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _ready() -> void:
	var build_dir := ProjectSettings.globalize_path("res://build/").replace("\\", "/").to_lower()
	for env_name in ["APPDATA", "LOCALAPPDATA"]:
		var env_path := OS.get_environment(env_name).replace("\\", "/").to_lower()
		if not env_path.begins_with(build_dir):
			push_error("提示条测试拒绝读取玩家配置：%s 必须隔离至 build/ 下" % env_name)
			get_tree().quit(1)
			return
	check(OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(build_dir), "Godot 用户目录未隔离")
	Game.no_save = true
	Game.save_path = "user://toast-merge-save.json"
	Game.meta_path = "user://toast-merge-meta.json"
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var toasts: VBoxContainer = main._toasts
	var sound_index: int = Sfx._next
	check(toasts.get_child_count() == 0, "测试启动已有其他提示")

	Game.toast.emit("守卫已就位")
	var original := toasts.get_child(0) as PanelContainer
	var label := original.get_child(0) as Label
	check(label.text == "守卫已就位", "首次提示不应显示计数")
	check(original.mouse_filter == Control.MOUSE_FILTER_IGNORE, "提示条截获了鼠标")
	check(label.get_theme_font_size("font_size") == 18 and label.get_theme_color("font_color") == UI.PAPER_LIGHT, "提示条字号或前景样式改变")
	var style := original.get_theme_stylebox("panel") as StyleBoxFlat
	check(style != null and style.bg_color == Color(UI.INK, 0.88), "提示条墨色底样式改变")
	await wait_seconds(0.15)
	Game.toast.emit("守卫已就位")
	check(toasts.get_child_count() == 1 and toasts.get_child(0) == original, "同文短间隔未复用原节点")
	check(label.text == "守卫已就位 ×2", "相同原文没有累计 ×2")

	# 字面上含计数后缀的另一条原文，不能误并入已经格式化的显示文本。
	Game.toast.emit("守卫已就位 ×2")
	var literal := toasts.get_child(1) as PanelContainer
	check(toasts.get_child_count() == 2 and literal != original, "不同原文被合并")
	check((literal.get_child(0) as Label).text == "守卫已就位 ×2", "含后缀的原文被改写")
	await wait_seconds(1.5)
	Game.toast.emit("守卫已就位")
	check(toasts.get_child_count() == 2 and label.text == "守卫已就位 ×3", "第三次提示未按原文累计")
	await wait_seconds(1.0)
	check(is_instance_valid(original) and original.modulate.a == 1.0, "重复提示未从最后一次提示续满驻留时间")
	await wait_seconds(1.38)
	check(is_instance_valid(original) and original.modulate.a < 1.0 and original.modulate.a > 0.0, "未实际等到原提示的淡出阶段")
	check(not is_instance_valid(literal), "不同提示被其他原文错误续命")

	# 在真实淡出阶段再次触发，并等过旧 tween 原本会执行释放回调的时刻。
	Game.toast.emit("守卫已就位")
	check(toasts.get_child_count() == 1 and toasts.get_child(0) == original, "淡出中同文产生重复节点")
	check(original.modulate.a == 1.0 and label.text == "守卫已就位 ×4", "淡出中重发未恢复可见并续上计数")
	await wait_seconds(0.75)
	check(is_instance_valid(original) and original.modulate.a == 1.0 and toasts.get_child_count() == 1, "旧淡出回调误删了续命提示")
	Game.toast.emit("守卫已就位")
	check(toasts.get_child_count() == 1 and label.text == "守卫已就位 ×5", "取消旧淡出后索引丢失，重发未继续合并")
	check(Sfx._next == sound_index, "提示合并新增了原本不存在的提示音")
	await wait_seconds(2.95)
	check(not is_instance_valid(original) and toasts.get_child_count() == 0, "驻留与淡出结束后提示未释放")
	check(main._toast_entries.is_empty(), "提示过期后合并索引未清理")

	Game.toast.emit("守卫已就位")
	var fresh := toasts.get_child(0) as PanelContainer
	check(toasts.get_child_count() == 1 and (fresh.get_child(0) as Label).text == "守卫已就位", "彻底过期后同文不能以首次计数重生")
	# 反例：外部释放旧节点后，同文仍须安全重生，旧清理不能清掉新索引。
	fresh.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.toast.emit("守卫已就位")
	var recovered := toasts.get_child(0) as PanelContainer
	check(toasts.get_child_count() == 1 and (recovered.get_child(0) as Label).text == "守卫已就位", "节点外部释放后残留索引阻止重生")
	main._expire_toast("守卫已就位", null)
	Game.toast.emit("守卫已就位")
	check(toasts.get_child_count() == 1 and (recovered.get_child(0) as Label).text == "守卫已就位 ×2", "旧节点清理回调误清除了新提示索引")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("提示条合并验收：%d 项检查，%d 处失败" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
