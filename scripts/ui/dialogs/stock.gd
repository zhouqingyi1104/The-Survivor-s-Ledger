extends RefCounted
## 家中存货（物资簿）：分类页签、物件格、直接在格子里吃喝用药。
##
## 从 dialogs.gd 搬出来（工程债第 1 条第二批）。入口仍是 Dialogs.inventory()，那个函数只是转发；
## 面板内容与搬之前逐字一致，控件树导出对照过。分类页签的选择存在静态变量里——和搬之前
## 存在 Dialogs 实例上等价（都是整个进程一份）。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Post = preload("res://scripts/core/post.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const Kit = preload("res://scripts/ui/dialogs/kit.gd")
const CAT_ORDER := ["食", "菜", "水", "药", "粮", "柴炭", "守具", "材", "种", "器", "书", "杂"]
const INVENTORY_PAPER = preload("res://assets/ui/inventory/paper.png")

## 当前选中的类目页签（"全部" = 不筛）
static var _filter := "全部"


static func open() -> void:
	if Floors.current(Game.run) == "guest_zhou":
		Game.toast.emit("先回宅院再使用家中存货。")
		return
	_filter = "全部"
	UI.open_modal("inventory", "家中存货", _build, true, 900)


static func _build(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var ledger := UI.vbox(12)
	ledger.add_child(label("物资簿  ·  家中收藏", 16, Color("#765044")))
	var categories: Array[String] = ["全部"]
	var all_ids: Array = []
	for cat in CAT_ORDER:
		var ids := Inv.ids_in_cat(run.home, cat)
		if not ids.is_empty():
			categories.append(cat)
			all_ids.append_array(ids)
	if not _filter in categories:
		_filter = "全部"
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	for cat in categories:
		var tab := UI.button(cat, func():
			_filter = cat
			UI.clear(body)
			_build(body))
		var chosen: bool = cat == _filter
		tab.add_theme_stylebox_override("normal", UI._box(Color("#8d4035") if chosen else Color("#e6d8bf"), Color("#9a7962"), 1, 0, 12, 5))
		tab.add_theme_stylebox_override("hover", UI._box(Color("#a25446"), Color("#843e33"), 1, 0, 12, 5))
		tab.add_theme_color_override("font_color", Color("#f2e6cd") if chosen else Color("#44352d"))
		tab.add_theme_color_override("font_hover_color", Color("#fff0d6"))
		tab.button_pressed = chosen
		tabs.add_child(tab)
	ledger.add_child(tabs)
	var grid := UI.grid(4, 9, 9)
	var visible_ids: Array = all_ids if _filter == "全部" else Inv.ids_in_cat(run.home, _filter)
	for id in visible_ids:
		grid.add_child(item_card(run, id))
	ledger.add_child(grid)
	if all_ids.is_empty():
		ledger.add_child(label("家中暂无存货。", 17, Color("#675b4d")))
	var paper := PanelContainer.new()
	var paper_style := StyleBoxTexture.new()
	paper_style.texture = INVENTORY_PAPER
	paper_style.content_margin_left = 14
	paper_style.content_margin_right = 14
	paper_style.content_margin_top = 12
	paper_style.content_margin_bottom = 12
	paper.add_theme_stylebox_override("panel", paper_style)
	paper.add_child(ledger)
	body.add_child(UI.scroll(paper, mini(470, maxi(180, int(UI.host.get_viewport().get_visible_rect().size.y) - 230))))


## 在深色弹窗主题下也保持纸上的墨色，不继承夜色主题的浅色文字与阴影。
static func label(text: String, size: int, ink: Color, wrap := false) -> Label:
	var l := UI.label(text, size, ink, wrap)
	l.add_theme_color_override("font_color", ink)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


## 物资格仍保留名称、数量、效果和原来的直接使用按钮。
static func item_card(run: Dictionary, id: String) -> Control:
	var it := Data.item(id)
	var n := Inv.count(run.home, id)
	var v := UI.vbox(4)
	UI.expand(v)
	var image_row := CenterContainer.new()
	image_row.custom_minimum_size.y = 72
	var illustration := UI.icon(id, 72)
	if illustration is TextureRect:
		illustration.set_meta("inventory_art", id)
	image_row.add_child(illustration)
	v.add_child(image_row)
	var title := UI.hbox(4)
	title.add_child(label(it.name, 17, Color("#302921")))
	title.add_child(UI.spacer())
	title.add_child(label("×%d" % n, 15, Color("#765b49")))
	v.add_child(title)
	var fx: Dictionary = it.get("eat", it.get("use", {}))
	v.add_child(label("%s · %s" % [it.cat, Kit.fx_text(fx)] if not fx.is_empty() else it.cat, 13, Color("#675b4d"), true))
	if not fx.is_empty():
		var verb := "喝" if id == "water" else ("吃" if it.has("eat") else "用")
		var action := UI.button(verb, func(): use_item(id))
		action.add_theme_stylebox_override("normal", UI._box(Color("#e3d1b6"), Color("#9a7962"), 1, 1, 8, 3))
		action.add_theme_stylebox_override("hover", UI._box(Color("#f0e2cc"), Color("#98483a"), 1, 1, 8, 3))
		action.add_theme_stylebox_override("pressed", UI._box(Color("#d3b99c"), Color("#843e33"), 1, 1, 8, 3))
		action.add_theme_color_override("font_color", Color("#44352d"))
		action.add_theme_color_override("font_hover_color", Color("#8d4035"))
		action.add_theme_color_override("font_pressed_color", Color("#44352d"))
		v.add_child(action)
	var card := PanelContainer.new()
	card.set_meta("inventory_item", id)
	card.add_theme_stylebox_override("panel", UI._box(Color(0.94, 0.90, 0.82, 0.68), Color("#ab9b80"), 1, 0, 9, 8))
	card.add_child(v)
	card.tooltip_text = it.desc
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	return UI.fixed_width(card, 190)


static func use_item(id: String) -> void:
	var res = Game.act(func(): return Post.use_item(Game.run, id))
	if typeof(res) == TYPE_STRING and res == "":
		Sfx.use_item(id)
