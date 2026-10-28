extends RefCounted
## 东侧小院施工入口：各阶段使用真实局内时间和材料。
const UI = preload("res://scripts/ui/ui_kit.gd")
const Expansion = preload("res://scripts/core/home_expansion.gd")
const Post = preload("res://scripts/core/post.gd")


static func open() -> void:
	UI.open_modal("home_expansion", "东侧院扩建", _build, true, 640)


static func _build(body: VBoxContainer) -> void:
	body.add_child(UI.para("先清出东边的空地，再备料、动工。完工后能走进侧院、摆家具。尸潮来时不能动工；被打断的话，备好的料还在，没做完的工得重做。", 16))
	var stage := Expansion.stage(Game.run)
	var text := ""
	var action := ""
	match stage:
		"survey":
			text = "还没清理 · 清理要 60 分钟、精力 5。"
			action = "查勘清理"
		"cleared":
			text = "空地已清好 · 备料要木料 ×8、铁钉 ×4，备一次就够。"
			action = "备料"
		"ready":
			text = "料已备好 · 动工要 120 分钟、精力 8。"
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
