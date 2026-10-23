extends Node
## 开发用：把某个界面摆出来拍一张，检查排版和文案。
## 运行：godot --path . res://tests/screen_shot.tscn -- --screen=pre --goto=rice_shop
##   --screen=  界面 id（difficulty / roles / pre / post）
##   --goto=    仅 pre/post：把角色先挪到某个地点（home / rice_shop / builder …）
##   --out=     输出目录（默认 user://shots）

const State = preload("res://scripts/core/state.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")


func _ready() -> void:
	var which := "difficulty"
	var goto := ""
	var pick := ""
	var out := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			which = a.trim_prefix("--screen=")
		elif a.begins_with("--goto="):
			goto = a.trim_prefix("--goto=")
		elif a.begins_with("--pick="):
			pick = a.trim_prefix("--pick=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	# 主界面是场景不是 autoload，得自己实例化挂上，Game.go() 才有地方放界面
	Game.meta = State.new_meta()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for k in 4:
		await get_tree().process_frame
	Game.pending_role = "scholar"
	if which == "pre" or which == "post":
		# 这两个界面要有局面：先按书生开一局，pre 直接看，post 要求劫后
		Game.new_game("scholar", "normal")
		if which == "post":
			Pre.start_disaster(Game.run)
			Post.begin_day(Game.run)
		if goto != "":
			Game.run.loc = goto
		Game.go(which)
	else:
		Game.go(which)
	# 挑战页想拍"选中态"：--pick=slay_200,extra_oil
	if which == "challenge" and pick != "":
		var scr: Node = _current_screen(main)
		if scr != null:
			for id in pick.split(",", false):
				if id in ["extra_silver", "extra_oil", "free_room"]:
					scr._boons.append(id)
				else:
					scr._picked.append(id)
			UI.clear(scr)
			scr.build()
	# 相机是插值跟上去的（_focus 每帧 lerp），等不够帧就会拍到"还在飞"的机位。
	# 之前按 12 帧拍，量出来的相机位置和算出来的差一大截，白折腾了三轮角度。
	for k in 60:
		await get_tree().process_frame
	_report(main, which)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out)
	var name := which if goto == "" else "%s_%s" % [which, goto]
	img.save_png(out.path_join("%s.png" % name))
	print("saved ", name)
	get_tree().quit()


## 当前挂在 holder 上的那个界面。
func _current_screen(main: Node) -> Node:
	var holder: Node = main.get_child(1) if main.get_child_count() > 1 else null
	return holder.get_child(0) if holder != null and holder.get_child_count() > 0 else null


## 界面里到底有什么：节点数、按钮文字、短标签。截图发白时先看这里。
func _report(main: Node, which: String) -> void:
	var scr: Node = _current_screen(main)
	print("== %s：screen=%s" % [which, scr])
	if scr == null:
		return
	var labels := scr.find_children("*", "Label", true, false)
	var buttons := scr.find_children("*", "Button", true, false)
	print("   标签 %d 个、按钮 %d 个" % [labels.size(), buttons.size()])
	var texts := []
	for b in buttons:
		texts.append(str((b as Button).text))
	print("   按钮：" + " | ".join(texts))
	var heads := []
	for l in labels:
		var t := str((l as Label).text)
		if t.length() > 1 and t.length() < 14:
			heads.append(t)
	print("   短标签：" + " ".join(heads))
	_walker_report(scr)


## 角色在不在画面里、在哪个位置。看不见人时先看这个，别靠眼睛猜。
func _walker_report(scr: Node) -> void:
	var w = scr.get("world")
	if w == null:
		return
	var walker = w.get("walker")
	if walker == null:
		print("   [角色] 世界没有 walker")
		return
	var cam: Camera3D = null
	for c in w.find_children("*", "Camera3D", true, false):
		cam = c
		break
	if cam == null:
		print("   [角色] 没有相机")
		return
	var p: Vector3 = (walker as Node3D).global_position
	var vp := get_viewport().get_visible_rect().size
	if cam.is_position_behind(p):
		print("   [角色] 在相机背后（看不见）")
		return
	var sp := cam.unproject_position(p)
	var inside := sp.x >= 0 and sp.y >= 0 and sp.x <= vp.x and sp.y <= vp.y
	print("   [角色] 世界坐标 %s → 屏幕 (%.0f, %.0f)/%.0fx%.0f　%s" % [
		str(p), sp.x, sp.y, vp.x, vp.y, "在画面内" if inside else "**出了画面**"])
	print("   [相机] 位置 %s　yaw %.0f　pitch %.0f　dist %.0f" % [
		str(cam.global_position), float(scr.get("rig").get("yaw")), float(scr.get("rig").get("pitch")), float(scr.get("rig").get("dist"))])
