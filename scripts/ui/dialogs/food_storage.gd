extends RefCounted
const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Home = preload("res://scripts/core/home.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Post = preload("res://scripts/core/post.gd")


static func open(uid: int) -> void:
	var furniture := Home.find(Game.run, uid)
	if furniture.is_empty(): return
	UI.open_modal("food_storage", str(Home.data(furniture.id).name), _build.bind(uid), true, 620)


static func _build(body: VBoxContainer, uid: int) -> void:
	var run: Dictionary = Game.run
	var f := Home.find(run, uid)
	if f.is_empty():
		body.add_child(UI.label("这件家具已经收走了。"))
		return
	body.add_child(UI.para(Home.data(f.id).desc, 17))
	var block := Post.can_act(run, 0)
	if f.id == "rat_trap":
		body.add_child(UI.para("笼中%s。余饵还能放 %d 晚。" % ["已落饵" if f.get("baited", false) else "还没放饵", int(f.get("bait_left", 0))], 18))
		if block == "" and int(f.get("bait_left", 0)) > 0: block = "笼边还有分好的饵。"
		if block == "" and Inv.total(run.home, ["millet", "rice"]) == 0: block = "要一斗杂粮或米作饵。"
		if block != "": body.add_child(UI.para(block, 15, UI.CINNABAR))
		body.add_child(UI.button("分六晚的饵（先用杂粮，无杂粮用米）", func(): _act(uid, "", 0), block != "", block))
		return
	if not f.get("job", {}).is_empty():
		body.add_child(UI.para("这一批：%s。\n成熟后首个清晨入库：%s。" % [Home.job_text(run, f), Data.describe_items(f.job.out)], 18))
		return
	var jar: bool = f.id == "pickle_jar"
	var supply := "salt" if jar else "firewood"
	if block == "" and Inv.count(run.home, supply) < 1: block = "家里缺%s。" % Data.item_name(supply)
	if block != "": body.add_child(UI.para(block, 15, UI.CINNABAR))
	for food: String in (Home.PICKLE_VEG if jar else ["rat"]):
		if Data.item(food).is_empty(): continue
		var qty := Inv.count(run.home, food)
		var row := UI.hbox(8)
		row.add_child(UI.icon(food, 38))
		row.add_child(UI.expand(UI.label("%s　存 %d" % [Data.item_name(food), qty], 18)))
		for n in range(1, mini(4, qty) + 1):
			row.add_child(UI.button(("封 %d 份" if jar else "挂 %d 块") % n, func(): _act(uid, food, n), block != "", block))
		if qty == 0: row.add_child(UI.label("缺%s" % Data.item_name(food), 15, UI.INK_SOFT))
		body.add_child(row)


static func _act(uid: int, food: String, n: int) -> void:
	Game.act(func():
		var run: Dictionary = Game.run
		var err := Post.can_act(run, 0)
		if err != "": return err
		var f := Home.find(run, uid)
		match f.get("id", ""):
			"pickle_jar": return Home.pickle(run, uid, food, n)
			"smoke_rack": return Home.smoke(run, uid, food, n)
			"rat_trap": return Home.fill_trap(run, uid)
		return "这件家具已经收走了。")
