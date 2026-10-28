extends RefCounted
## 宅院装修：每次选用非原样均消耗标示材料；恢复原样免费，不返料。
const Inv = preload("res://scripts/core/inv.gd")
const Post = preload("res://scripts/core/post.gd")

const OPTIONS := {
	"wall": {"title": "院墙", "choices": {
		"original": {"name": "原有粉墙", "cost": {}},
		"warm": {"name": "暖赭院墙", "cost": {"wood": 2}},
		"blue": {"name": "青灰院墙", "cost": {"wood": 3}},
	}},
	"floor": {"title": "院内铺地", "choices": {
		"original": {"name": "原有青石", "cost": {}},
		"brick": {"name": "红砖铺地", "cost": {"wood": 3}},
		"slate": {"name": "深灰石板", "cost": {"wood": 4}},
	}},
	"lamps": {"title": "院内灯饰", "choices": {
		"original": {"name": "原有灯饰", "cost": {}},
		"red": {"name": "一对朱灯", "cost": {"wood": 1, "nails": 1}},
		"gold": {"name": "一对暖金灯", "cost": {"wood": 2, "nails": 1}},
	}},
	"plants": {"title": "花木陈设", "choices": {
		"original": {"name": "原有陈设", "cost": {}},
		"bamboo": {"name": "一对盆竹", "cost": {"wood": 2}},
		"plum": {"name": "一对盆梅", "cost": {"wood": 3}},
	}},
}


static func selected(run: Dictionary, category: String) -> String:
	if not OPTIONS.has(category):
		return "original"
	var state = run.get("decoration", {})
	if not state is Dictionary:
		return "original"
	var choice := str(state.get(category, "original"))
	return choice if OPTIONS[category].choices.has(choice) else "original"


static func block(run: Dictionary, category: String, choice: String) -> String:
	if not OPTIONS.has(category) or not OPTIONS[category].choices.has(choice):
		return "没有这种装修。"
	if selected(run, category) == choice:
		return "已经是这个样式。"
	if not run.get("fight", {}).is_empty():
		return "战斗中不能装修。"
	var reason := Post.can_act(run)
	if reason != "":
		return reason
	var home = run.get("home", {})
	if not home is Dictionary or not Inv.has_all(home, OPTIONS[category].choices[choice].cost):
		return "材料不足。"
	return ""


static func apply(run: Dictionary, category: String, choice: String) -> String:
	var reason := block(run, category, choice)
	if reason != "":
		return reason
	Inv.take_all(run.home, OPTIONS[category].choices[choice].cost)
	if not run.get("decoration", null) is Dictionary:
		run.decoration = {}
	run.decoration[category] = choice
	return ""
