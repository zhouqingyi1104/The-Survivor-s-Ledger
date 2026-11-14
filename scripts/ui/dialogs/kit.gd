extends RefCounted
## 弹窗公用的小工具：开工、做成了关窗、一行末尾的操作按钮、效果与用料的文字。
##
## 从 dialogs.gd 抽出来，好让拆出去的弹窗（scripts/ui/dialogs/*.gd）不必回头依赖那个大文件。
## dialogs.gd 里的 _act / _start / _action / fx_text / req_text 现在只是转发到这里，
## 另外五十多个还没搬家的面板照旧调用，行为一字未改。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")

const FX_NAMES := {"food": "饱腹", "water": "饮水", "hp": "气血", "mood": "心神", "energy": "精力"}


static func act(fn: Callable) -> void:
	Game.act(fn)


## 开工类动作：成功了就把弹窗关掉，好看见人在干活。
static func start(key: String, fn: Callable) -> void:
	var res = Game.act(fn)
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal(key)


## 一行末尾的操作按钮；做不了时把原因直接写在按钮左边（只放在 tooltip 里不容易看到）。
static func action(row: HBoxContainer, text: String, cb: Callable, block: String) -> void:
	if block != "":
		row.add_child(UI.label(block, 15, UI.CINNABAR))
	row.add_child(UI.button(text, cb, block != "", block))


static func fx_text(fx: Dictionary) -> String:
	var parts := []
	for k in FX_NAMES:
		if fx.has(k):
			parts.append("%s%+d" % [FX_NAMES[k], int(fx[k])])
	if fx.has("cure"):
		parts.append("祛尸瘟" if float(fx.cure) >= 1.0 else "或可祛尸瘟")
	return " ".join(parts)


static func req_text(store: Dictionary, req: Dictionary) -> String:
	var parts := []
	for id in req:
		parts.append("%s %d（有 %d）" % [Data.item_name(id), int(req[id]), Inv.count(store, id)])
	return "、".join(parts)
