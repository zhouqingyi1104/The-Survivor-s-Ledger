extends RefCounted
## 从工作台打开；选样式后再确认，取消不扣料也不改局面。
const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Decoration = preload("res://scripts/core/home_decoration.gd")


static func open() -> void:
	UI.open_modal("decoration", "宅院装修", _build, true, 760)


static func _build(body: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = clampf(UI.host.get_viewport_rect().size.y - 180.0, 220.0, 540.0)
	UI.expand(scroll)
	body.add_child(scroll)
	var content := UI.vbox(8)
	UI.expand(content)
	scroll.add_child(content)
	content.add_child(UI.para("换院墙、铺地、灯饰和花木的样子，只为好看，不影响照明和守夜。换回原样不花钱，但料不退；再换别的样式要重新备料。灯饰和花木摆在固定的地方，可能和家具挤在一起。", 15))
	for category in ["wall", "floor", "lamps", "plants"]:
		var section: Dictionary = Decoration.OPTIONS[category]
		content.add_child(UI.sep())
		content.add_child(UI.label(str(section.title), 18, UI.CINNABAR))
		for choice in section.choices:
			var spec: Dictionary = section.choices[choice]
			var row := UI.hbox(10)
			var cost: Dictionary = spec.cost
			var cost_text := Data.describe_items(cost) if not cost.is_empty() else "免费"
			var current: bool = Decoration.selected(Game.run, str(category)) == str(choice)
			row.add_child(UI.expand(UI.label("%s　·　%s%s" % [spec.name, cost_text, "　·　当前" if current else ""], 15)))
			if not current:
				var cat := str(category)
				var option := str(choice)
				row.add_child(UI.button("选择", func(): _confirm(cat, option)))
			content.add_child(row)


static func _confirm(category: String, choice: String) -> void:
	UI.open_modal("decoration_confirm", "确认装修", func(body: VBoxContainer):
		var spec: Dictionary = Decoration.OPTIONS[category].choices[choice]
		var cost: Dictionary = spec.cost
		var text := Data.describe_items(cost) if not cost.is_empty() else "免费"
		body.add_child(UI.para("换成%s：%s。确认就换，料不退。" % [spec.name, text], 16))
		var reason := Decoration.block(Game.run, category, choice)
		if reason != "":
			body.add_child(UI.label(reason, 15, UI.CINNABAR))
		var row := UI.hbox(10)
		row.add_child(UI.button("取消", func(): UI.close_modal("decoration_confirm")))
		if reason == "":
			row.add_child(UI.button("确认", func():
				var result = Game.act(func(): return Decoration.apply(Game.run, category, choice))
				if result == "":
					UI.close_modal("decoration_confirm")
					UI.close_modal("decoration")
					Game.toast.emit("宅院装修已更换。")
			))
		body.add_child(row)
	, true, 520)
