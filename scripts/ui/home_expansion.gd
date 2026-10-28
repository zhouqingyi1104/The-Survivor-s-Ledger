extends RefCounted
## 东侧小院施工入口：各阶段使用真实局内时间和材料。
const UI = preload("res://scripts/ui/ui_kit.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Post = preload("res://scripts/core/post.gd")


static func open() -> void:
	UI.open_modal("home_expansion", "东侧院扩建", _build, true, 640)


static func _build(body: VBoxContainer) -> void:
	body.add_child(UI.para("先清理东侧空地，再备料施工。完工后可走入侧院并安放家具；尸潮期间不能动工，若工程被打断，已备材料保留，未完成的工时须重新投入。", 16))
	var stage := Expansion.stage(Game.run)
	var text := ""
	var action := ""
	match stage:
		"survey":
			text = "尚未清理 · 查勘清理需 60 分钟、5 精力。"
			action = "查勘清理"
		"cleared":
			text = "空地已清理 · 备料需木料 8、铁钉 4，备料后材料不再重复收取。"
			action = "备料"
		"ready":
			text = "材料已备好 · 施工需 120 分钟、8 精力。"
			action = "开始施工"
		"complete":
			text = "东侧院已完工，可从东墙开口进入。"
	body.add_child(UI.sep())
	body.add_child(UI.label(text, 17, UI.CINNABAR))
	if action != "":
		var reason := Post.expansion_block(Game.run)
		if reason != "":
			body.add_child(UI.para(reason, 15, UI.INK_SOFT))
		else:
			body.add_child(UI.button(action, func():
				var result = Game.act(func(): return Post.act_expansion(Game.run))
				if typeof(result) == TYPE_STRING and result == "":
					UI.close_modal("home_expansion")
			))
