extends RefCounted
## 宅院里最常开的四个面板：灶房、菜畦、营造守具、读书。
##
## 从 dialogs.gd 搬出来（工程债第 1 条的第一次搬家）。入口仍是 Dialogs.cook() / garden() / build() / read()，
## 那四个只是转发到这里，调用点一个没改；面板内容与搬之前逐字一致，用控件树导出对照过。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Home = preload("res://scripts/core/home.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Kit = preload("res://scripts/ui/dialogs/kit.gd")


# ---------- 灶房 ----------

static func cook() -> void:
	UI.open_modal("cook", "灶房", _cook, true, 860)


static func _cook(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var stove := UI.hbox(8)
	var fuel := UI.para("柴 %d 捆 · 木炭 %d 筐（没柴时一筐炭顶两捆）　庖厨 %d 级　每锅另加 %d 份" % [
		Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal"), State.prof_level(run, "cook"),
		Post.cook_servings(run, "congee") - int(Data.table("recipes").congee.out)], 16)
	stove.add_child(UI.expand(fuel))
	stove.add_child(UI.button("晒匾 · " + Post.Drying.summary(run), func(): UI.open_modal("drying", "灶边晒匾", _drying, true, 690)))
	body.add_child(stove)
	var recipes: Dictionary = Data.table("recipes")
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var h := UI.hbox(10)
		h.add_child(UI.icon(rid, 44))
		var info := UI.vbox(2)
		UI.expand(info)
		var dish := Data.item(rid)
		info.add_child(UI.label("%s　得 %d 份　%s" % [r.name, Post.cook_servings(run, rid), Kit.fx_text(dish.get("eat", {}))], 19))
		info.add_child(UI.para("用料：%s　柴火 %d" % [Kit.req_text(run.home, Post.recipe_inputs(run, rid)), r.fuel], 15))
		h.add_child(info)
		var block := Post.recipe_block(run, rid)
		if block == "":
			block = Post.can_act(run)
		Kit.action(h, "下锅（一个时辰）", func(): Kit.start("cook", func(): return Post.act_cook(Game.run, rid)), block)
		body.add_child(h)


static func _drying(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var batch: Dictionary = run.get("drying_batch", {})
	if batch.is_empty():
		body.add_child(UI.para("家里只有这一面竹匾。薄片先干；到时可先收，也可把厚片翻面，多留一天收全。", 17))
		for kind: String in Post.Drying.RECIPES:
			var recipe: Dictionary = Post.Drying.RECIPES[kind]
			body.add_child(UI.sep())
			var row := UI.hbox(8)
			row.add_child(UI.icon(recipe.item, 44))
			row.add_child(UI.expand(UI.label(recipe.name, 20)))
			var reason := Post.drying_block(run, "start", kind)
			Kit.action(row, "铺匾（精力 4）", func(): Kit.act(func(): return Post.act_drying(Game.run, "start", kind)), reason)
			body.add_child(row)
			var needs := Kit.req_text(run.home, recipe.needs)
			if int(recipe.fuel) > 0: needs += "、柴 1 捆或炭 1 筐"
			body.add_child(UI.para("用料：%s\n%d 日后收%s ×%d，翻晒一日共得 %d。每份%s。" % [needs, recipe.days,
				Data.item_name(recipe.item), recipe.first, recipe.full, Kit.fx_text(Data.item(recipe.item).eat)], 16))
		return
	var recipe: Dictionary = Post.Drying.RECIPES[batch.kind]
	body.add_child(UI.label(Post.Drying.summary(run), 21))
	var amount := int(recipe.full if batch.turned else recipe.first)
	var offer := "翻晒过的厚片干透后，一起收进柜里。" if batch.turned else "若肯再占一天竹匾，翻面后共可收 %d 份。" % recipe.full
	body.add_child(UI.para("这批可收%s ×%d。%s 暂时留在匾上也不会少，收起后才能另铺。" % [Data.item_name(recipe.item), amount, offer], 17))
	var take := UI.hbox(8)
	Kit.action(take, "收进存货", func(): Kit.act(func(): return Post.act_drying(Game.run, "take")), Post.drying_block(run, "take"))
	body.add_child(take)
	if not batch.turned:
		var turn := UI.hbox(8)
		Kit.action(turn, "翻晒一天（精力 2）", func(): Kit.act(func(): return Post.act_drying(Game.run, "turn")), Post.drying_block(run, "turn"))
		body.add_child(turn)


# ---------- 菜畦 ----------

static func garden() -> void:
	UI.open_modal("garden", "菜畦", _garden, true, 820)


static func _garden(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var crops: Dictionary = Data.table("crops")
	body.add_child(UI.para("下种随手就行。一天之内浇过水的作物才长；打理一次要四十五分钟、一瓢清水，熟了的顺手收。", 16))
	for k in run.plots.size():
		var plot: Dictionary = run.plots[k]
		if not Post.plot_on_floor(run, plot):
			continue
		var h := UI.hbox(10)
		var plot_name := "第 %d 畦" % (k + 1)
		if plot.has("pot"):
			var pot := Home.find(run, int(plot.pot))
			plot_name = "花盆 #%d" % int(plot.pot)
			if not pot.is_empty():
				plot_name += "（%.1f, %.1f）" % [float(pot.x), float(pot.z)]
		h.add_child(UI.label(plot_name, 18, UI.INK_SOFT))
		if plot.crop == "":
			h.add_child(UI.label("空着", 18, UI.INK_FAINT))
			h.add_child(UI.spacer())
			for cid in crops:
				var n := Inv.count(run.home, crops[cid].seed)
				if n > 0:
					h.add_child(UI.button("种%s（%d）" % [crops[cid].name, n], func(): Kit.act(func(): return Post.plant(Game.run, k, cid))))
		else:
			var c: Dictionary = crops[plot.crop]
			h.add_child(UI.label(c.name, 18))
			h.add_child(UI.bar(minf(float(plot.days), float(c.days)), float(c.days), UI.JADE, 160))
			var ripe := Post.crop_ripe(plot)
			h.add_child(UI.label("可收" if ripe else "%.1f / %d 日" % [float(plot.days), int(c.days)], 16, UI.JADE if ripe else UI.INK_SOFT))
			var dry := Post.plot_dry(run, plot)
			h.add_child(UI.tag("缺水" if dry else "已浇水", UI.CINNABAR if dry else UI.DAI))
		body.add_child(h)
	body.add_child(UI.sep())
	var block := Post.can_act(run)
	body.add_child(UI.seal_button("浇水收成（四十五分钟）", func(): Kit.start("garden", func(): return Post.act_garden(Game.run)), block != "", block))


# ---------- 营造 ----------

static func build() -> void:
	UI.open_modal("build", "营造守具", _build, true, 900)


static func _build(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var v := UI.vbox(6)
	v.add_child(UI.label("守具", 20, UI.CINNABAR))
	var devices: Dictionary = Data.table("devices").devices
	for did in devices:
		var d: Dictionary = devices[did]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var lasts := "一直管用" if int(d.dur) >= 99 else "管 %d 夜" % int(d.dur)
		var build_time := "（一个半时辰）" if int(d.time) > 0 else "（随手布下）"
		if str(d.get("bonus_mod", "")) != "":
			lasts = "基础管 %d 夜" % int(d.dur)
			build_time = "（90 分钟 · 精力 10）"
		info.add_child(UI.label("%s　守力 %d · %s　%s" % [d.name, d.power, lasts, build_time], 18))
		info.add_child(UI.para("%s　用料：%s" % [d.desc, Kit.req_text(run.home, d.cost)], 15))
		var bonus_mod := str(d.get("bonus_mod", ""))
		if bonus_mod != "":
			var mod: Dictionary = Data.table("waves").mods.get(bonus_mod, {})
			var target_line := UI.para("守%s；遇上%s，这一面守力再 +%d，开门迎战时不算。营造到 2 级，做出来的多管 1 夜。做到一半被打断，料退回，精力不退。" % [Defense.surface_name(str(d.surface)), str(mod.get("name", bonus_mod)), int(d.get("bonus_power", 0))], 15, UI.DAI)
			target_line.set_meta("defense_target", str(did))
			info.add_child(target_line)
		h.add_child(info)
		var block := Post.device_block(run, did)
		if int(d.time) > 0:
			Kit.action(h, "动手做", func(): Kit.start("build", func(): return Post.act_build(Game.run, did)), block)
		else:
			Kit.action(h, "布置", func(): Kit.act(func(): return Post.act_build(Game.run, did)), block)
		if bonus_mod != "":
			h.get_child(-1).set_meta("defense_device", str(did))
		v.add_child(h)
	# 加工：画符要先学会，其余几条谁都能做。不会的也列出来（标"还不会"），
	# 省得玩家猜有没有这回事——藏着的选项等于不存在的选项。
	v.add_child(UI.sep())
	v.add_child(UI.label("加工", 20, UI.CINNABAR))
	var crafts: Dictionary = Data.table("devices").crafts
	for cid in crafts:
		var c: Dictionary = crafts[cid]
		var h := UI.hbox(10)
		var info := UI.vbox(3)
		UI.expand(info)
		info.add_child(UI.para("%s：%s\n用料：%s　产出：%s" % [c.name, c.desc, Kit.req_text(run.home, c["in"]), Data.describe_items(c.out)], 16, UI.INK))
		var block := Post.craft_block(run, cid)
		if block != "": info.add_child(UI.para(block, 15, UI.CINNABAR))
		h.add_child(info)
		var craft_button := UI.button("%s（60 分钟 · 精力 6）" % str(c.get("verb", "做")), func(): Kit.start("build", func(): return Post.act_craft(Game.run, cid)), block != "", block)
		craft_button.set_meta("identity_craft", str(cid))
		h.add_child(craft_button)
		v.add_child(h)
	v.add_child(UI.sep())
	v.add_child(UI.label("修缮　用木料 1 根（有 %d），没木料时拆 2 捆柴顶上（有 %d），耐久 +%d" % [
		Inv.count(run.home, "wood"), Inv.count(run.home, "firewood"), 35 + 5 * State.prof_level(run, "build")], 20, UI.CINNABAR))
	for part in [["door", "门"], ["window", "窗"], ["wall", "墙"]]:
		var h := UI.hbox(10)
		var p: Dictionary = run[part[0]]
		h.add_child(UI.fixed_width(UI.label(part[1], 18), 40))
		h.add_child(UI.bar(int(p.cur), int(p.max), UI.GOLD))
		h.add_child(UI.label("%d / %d" % [p.cur, p.max], 16, UI.INK_SOFT))
		var key: String = part[0]
		var block := "完好" if int(p.cur) >= int(p.max) else Post.can_act(run)
		Kit.action(h, "修（一个时辰）", func(): Kit.start("build", func(): return Post.act_repair(Game.run, key)), block)
		v.add_child(h)
	body.add_child(UI.scroll(v, 480))


# ---------- 读书 ----------

static func read() -> void:
	UI.open_modal("read", "读书", _read, true, 760)


static func _read(body: VBoxContainer) -> void:
	var run: Dictionary = Game.run
	var books := Inv.ids_in_cat(run.home, "书")
	if books.is_empty():
		body.add_child(UI.para("家里一本书也没有。县学里兴许能翻到。", 17))
	for bid in books:
		var h := UI.hbox(10)
		var it := Data.item(bid)
		var done: bool = bid in run.read
		h.add_child(UI.expand(UI.para("%s　%s" % [it.name, it.desc], 17, UI.INK_FAINT if done else UI.INK)))
		var block := "读熟了" if done else Post.can_act(run)
		Kit.action(h, "读（两个时辰）", func(): Kit.start("read", func(): return Post.act_read(Game.run, bid)), block)
		body.add_child(h)
