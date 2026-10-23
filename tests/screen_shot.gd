extends Node
## 开发用：把某个界面摆出来拍一张，检查排版和文案。
## 运行：godot --path . res://tests/screen_shot.tscn -- --screen=difficulty --out=<目录>

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")


func _ready() -> void:
	var which := "difficulty"
	var out := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			which = a.trim_prefix("--screen=")
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
		Game.go(which)
	else:
		Game.go(which)
	for k in 10:
		await get_tree().process_frame
	_report(main, which)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out)
	img.save_png(out.path_join("%s.png" % which))
	print("saved ", which)
	get_tree().quit()


## 界面里到底有什么：节点数、按钮文字、短标签。截图发白时先看这里。
func _report(main: Node, which: String) -> void:
	var holder: Node = main.get_child(1) if main.get_child_count() > 1 else null
	var scr: Node = holder.get_child(0) if holder != null and holder.get_child_count() > 0 else null
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
