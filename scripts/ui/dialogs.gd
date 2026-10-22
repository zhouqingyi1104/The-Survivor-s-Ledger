extends Node
## 各种弹窗（自动加载为 Dialogs）：吃喝用药、灶房、菜畦、营造、读书、外出、事件、夜报、神龛求签、劫余录。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Events = preload("res://scripts/core/events.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Pre = preload("res://scripts/core/pre.gd")

static var GRADE_COLORS := {"不足": UI.CINNABAR, "适当": UI.GOLD, "宽裕": UI.JADE}
static var STATUS_COLORS := {"正常": UI.JADE, "拥挤": UI.GOLD, "哄抢": UI.CINNABAR, "关门": UI.INK_FAINT}
const CAT_ORDER := ["食", "菜", "水", "药", "粮", "柴炭", "守具", "材", "种", "器", "书", "杂"]
const FX_NAMES := {"food": "饱腹", "water": "饮水", "hp": "气血", "mood": "心神", "energy": "精力"}


func _run() -> Dictionary:
	return Game.run


func _act(fn: Callable) -> void:
	Game.act(fn)


## 做成了才出声（买卖的钱币声、吃喝声……）。
func _act_sfx(fn: Callable, sound: String) -> void:
	var res = Game.act(fn)
	if typeof(res) != TYPE_STRING or res == "":
		Sfx.play(sound, -4.0)


## 开工类动作：成功了就把弹窗关掉，好看见人在干活。
func _start(key: String, fn: Callable) -> void:
	var res = Game.act(fn)
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal(key)


static func fx_text(fx: Dictionary) -> String:
	var parts := []
	for k in FX_NAMES:
		if fx.has(k):
			parts.append("%s%+d" % [FX_NAMES[k], int(fx[k])])
	if fx.has("cure"):
		parts.append("祛尸瘟" if float(fx.cure) >= 1.0 else "或可祛尸瘟")
	return " ".join(parts)


## 一行末尾的操作按钮；做不了时把原因直接写在按钮左边（只放在 tooltip 里不容易看到）。
func _action(row: HBoxContainer, text: String, cb: Callable, block: String) -> void:
	if block != "":
		row.add_child(UI.label(block, 15, UI.CINNABAR))
	row.add_child(UI.button(text, cb, block != "", block))


static func req_text(store: Dictionary, req: Dictionary) -> String:
	var parts := []
	for id in req:
		parts.append("%s %d（有 %d）" % [Data.item_name(id), int(req[id]), Inv.count(store, id)])
	return "、".join(parts)


# ---------- 劫余录 ----------

func journal() -> void:
	UI.open_modal("journal", "劫余录", _journal, true, 900)


func _journal(body: VBoxContainer) -> void:
	var lines: Array = _run().get("log", [])
	var s := UI.scroll(UI.log_view(lines, lines.size(), 17), 500)
	var bar := s.get_v_scroll_bar()
	bar.changed.connect(func(): s.scroll_vertical = int(bar.max_value))
	body.add_child(s)


# ---------- 吃喝用药 ----------

func inventory() -> void:
	UI.open_modal("inventory", "家中存货", _inventory, true, 900)


func _inventory(body: VBoxContainer) -> void:
	var run := _run()
	var v := UI.vbox(6)
	for cat in CAT_ORDER:
		var ids := Inv.ids_in_cat(run.home, cat)
		if ids.is_empty():
			continue
		v.add_child(UI.label(cat, 19, UI.CINNABAR))
		var g := UI.grid(3, 12, 4)
		for id in ids:
			var it := Data.item(id)
			var name_label := UI.label("%s ×%d" % [it.name, Inv.count(run.home, id)], 18)
			name_label.tooltip_text = it.desc
			name_label.mouse_filter = Control.MOUSE_FILTER_PASS
			g.add_child(UI.fixed_width(name_label, 240))
			var fx: Dictionary = it.get("eat", it.get("use", {}))
			g.add_child(UI.fixed_width(UI.label(fx_text(fx) if not fx.is_empty() else it.desc, 15, UI.INK_SOFT, true), 460))
			if fx.is_empty():
				g.add_child(Control.new())
			else:
				var verb := "喝" if id == "water" else ("吃" if it.has("eat") else "用")
				g.add_child(UI.button(verb, func(): _use(id)))
		v.add_child(g)
	body.add_child(UI.scroll(v, 460))


func _use(id: String) -> void:
	var res = Game.act(func(): return Post.use_item(Game.run, id))
	if typeof(res) == TYPE_STRING and res == "":
		Sfx.use_item(id)


# ---------- 灶房 ----------

func cook() -> void:
	UI.open_modal("cook", "灶房", _cook, true, 860)


func _cook(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("柴 %d 捆 · 木炭 %d 筐（没柴时一筐炭顶两捆）　庖厨 %d 级　每锅另加 %d 份" % [
		Inv.count(run.home, "firewood"), Inv.count(run.home, "charcoal"), State.prof_level(run, "cook"),
		Post.cook_servings(run, "congee") - int(Data.table("recipes").congee.out)], 16))
	var recipes: Dictionary = Data.table("recipes")
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var dish := Data.item(rid)
		info.add_child(UI.label("%s　得 %d 份　%s" % [r.name, Post.cook_servings(run, rid), fx_text(dish.get("eat", {}))], 19))
		info.add_child(UI.para("用料：%s　柴火 %d" % [req_text(run.home, Post.recipe_inputs(run, rid)), r.fuel], 15))
		h.add_child(info)
		var block := Post.recipe_block(run, rid)
		if block == "":
			block = Post.can_act(run)
		_action(h, "下锅（一个时辰）", func(): _start("cook", func(): return Post.act_cook(Game.run, rid)), block)
		body.add_child(h)


# ---------- 菜畦 ----------

func garden() -> void:
	UI.open_modal("garden", "菜畦", _garden, true, 820)


func _garden(body: VBoxContainer) -> void:
	var run := _run()
	var crops: Dictionary = Data.table("crops")
	body.add_child(UI.para("下种随手就行。一天之内浇过水的作物才长；打理一次要四十五分钟、一瓢清水，熟了的顺手收。", 16))
	for k in run.plots.size():
		var plot: Dictionary = run.plots[k]
		var h := UI.hbox(10)
		h.add_child(UI.fixed_width(UI.label("第 %d 畦" % (k + 1), 18, UI.INK_SOFT), 80))
		if plot.crop == "":
			h.add_child(UI.label("空着", 18, UI.INK_FAINT))
			h.add_child(UI.spacer())
			for cid in crops:
				var n := Inv.count(run.home, crops[cid].seed)
				if n > 0:
					h.add_child(UI.button("种%s（%d）" % [crops[cid].name, n], func(): _act(func(): return Post.plant(Game.run, k, cid))))
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
	body.add_child(UI.seal_button("浇水收成（四十五分钟）", func(): _start("garden", func(): return Post.act_garden(Game.run)), block != "", block))


# ---------- 营造 ----------

func build() -> void:
	UI.open_modal("build", "营造守具", _build, true, 900)


func _build(body: VBoxContainer) -> void:
	var run := _run()
	var v := UI.vbox(6)
	v.add_child(UI.label("守具", 20, UI.CINNABAR))
	var devices: Dictionary = Data.table("devices").devices
	for did in devices:
		var d: Dictionary = devices[did]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var lasts := "一直管用" if int(d.dur) >= 99 else "管 %d 夜" % int(d.dur)
		info.add_child(UI.label("%s　守力 %d · %s　%s" % [d.name, d.power, lasts, "（一个半时辰）" if int(d.time) > 0 else "（随手布下）"], 18))
		info.add_child(UI.para("%s　用料：%s" % [d.desc, req_text(run.home, d.cost)], 15))
		h.add_child(info)
		var block := Post.device_block(run, did)
		if int(d.time) > 0:
			_action(h, "动手做", func(): _start("build", func(): return Post.act_build(Game.run, did)), block)
		else:
			_action(h, "布置", func(): _act(func(): return Post.act_build(Game.run, did)), block)
		v.add_child(h)
	if State.flag(run, "learned_talisman"):
		v.add_child(UI.sep())
		v.add_child(UI.label("画符", 20, UI.CINNABAR))
		var crafts: Dictionary = Data.table("devices").crafts
		for cid in crafts:
			var c: Dictionary = crafts[cid]
			var h := UI.hbox(10)
			h.add_child(UI.expand(UI.para("%s：%s　用料：%s" % [c.name, c.desc, req_text(run.home, c["in"])], 16, UI.INK)))
			var block := Post.craft_block(run, cid)
			_action(h, "画（一个时辰）", func(): _start("build", func(): return Post.act_craft(Game.run, cid)), block)
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
		_action(h, "修（一个时辰）", func(): _start("build", func(): return Post.act_repair(Game.run, key)), block)
		v.add_child(h)
	body.add_child(UI.scroll(v, 480))


# ---------- 读书 ----------

func read() -> void:
	UI.open_modal("read", "读书", _read, true, 760)


func _read(body: VBoxContainer) -> void:
	var run := _run()
	var books := Inv.ids_in_cat(run.home, "书")
	if books.is_empty():
		body.add_child(UI.para("家里一本书也没有。县学里兴许能翻到。", 17))
	for bid in books:
		var h := UI.hbox(10)
		var it := Data.item(bid)
		var done: bool = bid in run.read
		h.add_child(UI.expand(UI.para("%s　%s" % [it.name, it.desc], 17, UI.INK_FAINT if done else UI.INK)))
		var block := "读熟了" if done else Post.can_act(run)
		_action(h, "读（两个时辰）", func(): _start("read", func(): return Post.act_read(Game.run, bid)), block)
		body.add_child(h)


# ---------- 外出 ----------

func explore_pick() -> void:
	UI.open_modal("explore_pick", "出门去哪？", _explore_pick, true, 900)


func _explore_pick(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("来回各要一个时辰的路，酉时（21:00）前必须回家。每翻一处，阳气就外泄一分，满了会被尸群嗅到。", 16))
	var v := UI.vbox(8)
	for pid in Explore.visible_points(run):
		var p: Dictionary = Data.table("map_points")[pid]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		var head := UI.hbox(8)
		head.add_child(UI.label(p.name, 20))
		head.add_child(UI.label("险 " + "★".repeat(int(p.danger)) + "☆".repeat(4 - int(p.danger)), 16, UI.CINNABAR))
		var warn := Explore.fall_warning(run, pid)
		if warn != "":
			head.add_child(UI.tag(warn, UI.CINNABAR))
		if int(run.points.get(pid, {}).get("visits", 0)) == 0:
			head.add_child(UI.tag("未到访", UI.DAI))
		info.add_child(head)
		info.add_child(UI.para(p.desc, 15))
		h.add_child(info)
		var block := Explore.point_block(run, pid)
		if block == "":
			block = Post.can_act(run, 10)
		if block == "" and Post.day_minute(run) + 60 >= Post.CURFEW_AT:
			block = "天快黑了"
		_action(h, "出发", func(): _go_explore(pid), block)
		v.add_child(h)
	body.add_child(UI.scroll(v, 460))


func _go_explore(pid: String) -> void:
	UI.close_modal("explore_pick")
	_act(func(): return Post.act_explore(Game.run, pid))


# ---------- 事件 ----------

func event() -> void:
	var id: String = _run().pending_event
	UI.open_modal("event", Data.table("events")[id].title, _event, false, 720)


func _event(body: VBoxContainer) -> void:
	var run := _run()
	if run.pending_event == "":
		body.add_child(UI.para(run.event_result, 19, UI.INK))
		var row := UI.hbox()
		row.add_child(UI.spacer())
		row.add_child(UI.seal_button("知道了", func(): UI.close_modal("event")))
		body.add_child(row)
		return
	var e: Dictionary = Data.table("events")[run.pending_event]
	body.add_child(UI.para(e.text, 19, UI.INK))
	body.add_child(UI.sep())
	for k in e.choices.size():
		var c: Dictionary = e.choices[k]
		var ok := Events.choice_ok(run, c)
		var text: String = c.text
		if not c.get("req", {}).is_empty():
			text += "　［需：%s］" % _event_req_text(c.req)
		var b := UI.button(text, func(): _act(func(): return Events.choose(Game.run, k)), not ok, "" if ok else "东西不够")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)


static func _event_req_text(req: Dictionary) -> String:
	var parts := []
	for k in req:
		match k:
			"any_food":
				parts.append("吃食 %d 份" % req[k])
			"any_grain":
				parts.append("粮 %d 斗" % req[k])
			"silver":
				parts.append("银 %d 两" % (int(req[k]) / 1000))
			_:
				parts.append("%s %d" % [Data.item_name(k), req[k]])
	return "、".join(parts)


# ---------- 守夜方针（21:00） ----------

func night_plan() -> void:
	UI.open_modal("night_plan", "第 %d 夜 · 定守夜方针" % int(_run().pday), _night_plan, false, 980)


func _night_plan(body: VBoxContainer) -> void:
	var run := _run()
	if not run.plan_due:
		UI.close_modal("night_plan")
		return
	var wave := Defense.wave_for_day(int(run.pday))
	var total := Defense._count(wave)
	var mods := Defense.mod_names(wave)
	body.add_child(UI.para("更鼓敲过二更。街那头铜锣响了，门缝里透进一片火把的光——今夜要来 %d 只%s，分三轮撞门、窗、院墙。" % [
		total, ("（%s）" % mods) if mods != "" else ""], 18, UI.INK))
	body.add_child(UI.para("每漏进来一只，那一面就掉 %d 点耐久。选个方针：想安稳过日子就选前三档，交给它自己守；想自己拿主意就选「亲自调度」。" % Defense.leak_damage(int(run.pday)), 16))
	body.add_child(UI.sep())
	var row := UI.hbox(10)
	for opt in Post.policy_options(run):
		var id: String = opt[0]
		var v := UI.vbox(5)
		UI.expand(v)
		v.add_child(UI.heading(opt[1], 21))
		v.add_child(UI.para(opt[2], 14))
		v.add_child(UI.label("亲守：%s" % Defense.surface_name(str(opt[3])), 15, UI.INK_SOFT))
		var leak := int(opt[4])
		v.add_child(UI.label(("整夜约漏 %d 只" % leak) if leak > 0 else "整夜挡得住", 16, UI.CINNABAR if leak > 0 else UI.JADE))
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(gap)
		v.add_child(UI.seal_button(opt[1], func(): _pick_policy(id)))
		var card := UI.panel(v, UI.PAPER)
		UI.expand(card)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(card)
	body.add_child(row)


func _pick_policy(id: String) -> void:
	var res = Game.act(func(): return Post.choose_policy(Game.run, id))
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("night_plan")
		Sfx.play("bangzi", -6.0)


# ---------- 夜战面板（轮间） ----------

func night_panel() -> void:
	UI.open_modal("night", "夜战 · 第 %d 轮" % (int(_run().night.get("round", 0)) + 1), _night_panel, true, 940)


func _night_panel(body: VBoxContainer) -> void:
	var run := _run()
	var night: Dictionary = run.get("night", {})
	if night.is_empty() or bool(night.get("done", false)):
		UI.close_modal("night")
		return
	var wave: Dictionary = night.wave
	var idx := int(night.round)
	var pv := Defense.preview_round(run, wave, idx)
	body.add_child(UI.para("第 %d / %d 轮。这一轮要来 %d 只。离下一轮还有 %d 分钟——只够做一件事。" % [
		idx + 1, int(night.rounds), int(pv.surfaces.gate.count) + int(pv.surfaces.window.count) + int(pv.surfaces.wall.count),
		maxi(0, Defense.round_minute(idx) - Post.day_minute(run))], 17))
	body.add_child(UI.para("院门%s。开着的时候，这一轮本该撞门的那些会直接走进来，砸菜畦、米袋和家具；关着就只能挨撞。" % (
		"开着" if bool(run.door_open) else "闩着"), 15, UI.CINNABAR if bool(run.door_open) else UI.INK_SOFT))
	body.add_child(UI.sep())
	for sid in Defense.SURFACES:
		var s: Dictionary = pv.surfaces[sid]
		var part := Defense.part_of(run, sid)
		var h := UI.hbox(8)
		var name_label := UI.label(Defense.surface_name(sid), 19, UI.CINNABAR if bool(s.broken) else UI.INK)
		h.add_child(UI.fixed_width(name_label, 52))
		h.add_child(UI.bar(int(part.cur), int(part.max), UI.GOLD, 150))
		h.add_child(UI.fixed_width(UI.label("%d/%d" % [part.cur, part.max], 15, UI.INK_SOFT), 72))
		h.add_child(UI.fixed_width(UI.label("守力 %.1f" % float(s.power), 15, UI.INK_SOFT), 92))
		h.add_child(UI.fixed_width(UI.label("来 %d · 漏 %d" % [int(s.count), int(s.left)], 15, UI.CINNABAR if int(s.left) > 0 else UI.JADE), 112))
		if bool(s.broken):
			h.add_child(UI.label("已破，来的全进院子", 15, UI.CINNABAR))
		else:
			h.add_child(UI.button("修缮", func(): _night_do(func(): return Post.night_mend(Game.run, sid), Defense.mend_block(run, sid))))
			h.add_child(UI.button("贴符", func(): _charm_menu(sid)))
			if sid == "gate":
				h.add_child(UI.button("关门" if bool(run.door_open) else "开门迎敌",
					func(): _night_do(func(): return Post.toggle_gate(Game.run), "")))
		body.add_child(h)
	body.add_child(UI.sep())
	var foot := UI.hbox(10)
	var block := Post.night_block(run, 0)
	if block != "":
		foot.add_child(UI.label(block, 15, UI.CINNABAR))
	# 布守具：只列还做得起的
	var devices: Dictionary = Data.table("devices").devices
	for did in devices:
		if Post.device_block(run, did) != "":
			continue
		if String(devices[did].get("surface", "*")) == "*":
			continue
		foot.add_child(UI.button("布 %s → %s" % [devices[did].name, Defense.surface_name(str(devices[did].surface))],
			func(): _night_do(func(): return Post.night_build(Game.run, did), "")))
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("等下一轮", func(): UI.close_modal("night")))
	body.add_child(foot)


func _night_do(cb: Callable, tip: String) -> void:
	if tip != "":
		Game.toast.emit(tip)
		return
	var res = Game.act(cb)
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("night")


func _charm_menu(sid: String) -> void:
	UI.open_modal("charm", "在%s上贴什么" % Defense.surface_name(sid), func(body: VBoxContainer): _charm_list(body, sid), true, 560)


func _charm_list(body: VBoxContainer, sid: String) -> void:
	var run := _run()
	for id in ["talisman", "dog_blood", "glutinous"]:
		var h := UI.hbox(10)
		h.add_child(UI.expand(UI.label("%s（有 %d）　守力 +%d" % [Data.item_name(id), Inv.count(run.home, id), int(Defense.charm_power(id))], 17)))
		var block := Defense.charm_block(run, sid, id)
		h.add_child(UI.button("贴上", func(): _charm_do(sid, id), block != "", block))
		body.add_child(h)


func _charm_do(sid: String, id: String) -> void:
	var res = Game.act(func(): return Post.night_charm(Game.run, sid, id))
	if typeof(res) == TYPE_STRING and res == "":
		UI.close_modal("charm")
		UI.close_modal("night")


# ---------- 战报 / 天亮结算 ----------

func wave_report() -> void:
	UI.open_modal("wave_report", "第 %d 夜 · 战报" % int(_run().pday), _wave_report, false, 760)


func _wave_report(body: VBoxContainer) -> void:
	var run := _run()
	var w: Dictionary = run.wave_report
	if w.is_empty():
		UI.close_modal("wave_report")
		return
	body.add_child(UI.label("尸潮%s" % ("·" + w.name if w.name != "" else ""), 22, UI.CINNABAR))
	body.add_child(UI.label("整夜来 %d 只　斩 %d 只　进院 %d 只" % [w.count, w.killed, w.get("enter", 0)], 18))
	body.add_child(UI.sep())
	body.add_child(UI.label("三轮战况", 19, UI.CINNABAR))
	var g := UI.grid(8, 10, 4)
	for head in ["轮", "来", "斩", "漏", "门", "窗", "墙", "进院"]:
		g.add_child(UI.label(head, 14, UI.INK_FAINT))
	for rep in w.get("rounds", []):
		g.add_child(UI.label("第 %d 轮" % (int(rep.round) + 1), 15))
		g.add_child(UI.label(str(rep.count), 15))
		g.add_child(UI.label(str(rep.killed), 15, UI.JADE))
		g.add_child(UI.label(str(rep.left), 15, UI.INK_SOFT))
		for sid in Defense.SURFACES:
			var s: Dictionary = rep.surfaces.get(sid, {})
			var cur := int(s.get("dmg", 0))
			g.add_child(UI.label("-%d" % cur if cur > 0 else "—", 15, UI.CINNABAR if cur > 0 else UI.INK_FAINT))
		g.add_child(UI.label(str(rep.get("enter", 0)), 15, UI.CINNABAR if int(rep.get("enter", 0)) > 0 else UI.INK_SOFT))
	body.add_child(g)
	if not w.get("broke", []).is_empty():
		var names := []
		for sid in w.broke:
			names.append(Defense.surface_name(sid))
		body.add_child(UI.label("%s被撞破了，来不及修的话，明晚会直接从那儿进来。" % "、".join(names), 17, UI.CINNABAR))
	if int(w.get("hp_loss", 0)) > 0:
		body.add_child(UI.label("被进院的咬伤：气血 -%d" % int(w.hp_loss), 17, UI.CINNABAR))
	if w.get("poisoned", false):
		body.add_child(UI.label("被抓伤，染上了尸毒。", 17, UI.CINNABAR))
	if not w.get("broken", []).is_empty():
		body.add_child(UI.para("用尽的守具：" + "、".join(w.broken), 15))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.seal_button("接着守夜", func(): _act(_ack_wave)))
	body.add_child(row)


func _ack_wave() -> String:
	Post.ack_wave(Game.run)
	return ""


func dawn_report() -> void:
	UI.open_modal("dawn", "天亮了 · 第 %d 日" % int(_run().pday), _dawn_report, false, 720)
	# 青云观的晨钟
	Sfx.strikes(["bell", "bell", "bell"], 1.6, -9.0)


func _dawn_report(body: VBoxContainer) -> void:
	var run := _run()
	var rep: Dictionary = run.report
	if not run.dawn_due or rep.is_empty():
		UI.close_modal("dawn")
		return
	for l in rep.get("night", []):
		body.add_child(UI.para(l, 17, UI.INK))
	if rep.get("night", []).is_empty():
		body.add_child(UI.para("一夜无事。", 17, UI.INK))
	body.add_child(UI.sep())
	body.add_child(UI.label("功过格", 22, UI.CINNABAR))
	var g := UI.grid(2, 30, 2)
	for l in rep.settle.lines:
		g.add_child(UI.label(l[0], 17))
		g.add_child(UI.label("+%d" % l[1], 17, UI.JADE))
	body.add_child(g)
	body.add_child(UI.label("今日积功德 %d，共 %d" % [rep.settle.total, rep.settle.merit], 18))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.seal_button("翻过这一页", func(): _act(_ack_dawn)))
	body.add_child(row)


func _ack_dawn() -> String:
	Post.ack_dawn(Game.run)
	return ""


# ---------- 神龛求签 ----------

func omens() -> void:
	UI.open_modal("omens", "神龛求签", _omens, true, 900)


func _omens(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("功德 %d。签筒里每日三支签，可以花功德求，也可以留一支到明日；同一天求得越多越贵。" % int(run.merit), 17))
	var row := UI.hbox(12)
	for id in run.omens.offer:
		var o: Dictionary = Data.table("omens")[id]
		var v := UI.vbox(6)
		var taken: bool = id in run.omens.taken
		var cost := Ledger.omen_cost(run, id)
		v.add_child(UI.tag(o.tier, UI.CINNABAR if o.tier.begins_with("上") else UI.GOLD))
		v.add_child(UI.heading(o.name, 24, UI.INK_FAINT if taken else UI.INK))
		v.add_child(UI.para("「%s」" % o.verse, 16, UI.DAI))
		v.add_child(UI.para(o.desc, 16))
		v.add_child(UI.label("功德 %d" % cost, 17, UI.CINNABAR))
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(gap)
		if taken:
			v.add_child(UI.tag("已求得", UI.JADE))
		else:
			v.add_child(UI.seal_button("求此签", func(): _act(func(): return Ledger.take_omen(Game.run, id)), int(run.merit) < cost))
			var locked: bool = run.omens.locked == id
			v.add_child(UI.button("不留了" if locked else "留到明日", func(): _act(func(): return _toggle_lock(id))))
		var p := UI.panel(v, UI.PAPER)
		UI.expand(p)
		row.add_child(p)
	body.add_child(row)
	var foot := UI.hbox()
	foot.add_child(UI.spacer())
	foot.add_child(UI.button("摇签筒（%d 功德）" % Ledger.REROLL_COST, func(): _act(func(): return Ledger.reroll_omens(Game.run)), int(run.merit) < Ledger.REROLL_COST))
	body.add_child(foot)


func _toggle_lock(id: String) -> String:
	Ledger.toggle_lock(Game.run, id)
	return ""


# ---------- 通用确认 ----------

func confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	UI.open_modal("confirm", title, func(body: VBoxContainer): _confirm(body, text, ok_text, on_ok), true, 560)


func _confirm(body: VBoxContainer, text: String, ok_text: String, on_ok: Callable) -> void:
	body.add_child(UI.para(text, 18, UI.INK))
	var row := UI.hbox()
	row.add_child(UI.spacer())
	row.add_child(UI.button("再想想", func(): UI.close_modal("confirm")))
	row.add_child(UI.seal_button(ok_text, func(): _confirm_ok(on_ok)))
	body.add_child(row)


func _confirm_ok(on_ok: Callable) -> void:
	UI.close_modal("confirm")
	on_ok.call()


# ---------- 备劫：铺子 ----------

func shop() -> void:
	var id: String = _run().loc
	if id == "home":
		return
	UI.open_modal("shop", Pre.shop(id).name, _shop, true, 880)


func _shop(body: VBoxContainer) -> void:
	var run := _run()
	var id: String = run.loc
	if run.phase != "pre" or id == "home":
		UI.close_modal("shop")
		return
	var s: Dictionary = Pre.shop(id)
	var head := UI.hbox(10)
	head.add_child(UI.tag(Pre.status(run, id), STATUS_COLORS.get(Pre.status(run, id), UI.INK_SOFT)))
	head.add_child(UI.label("银两 %s　车上 %.0f / %d 斤" % [Pre.money(int(run.silver)), Pre.cart_weight(run), Pre.capacity(run)], 17, UI.INK_SOFT))
	body.add_child(head)
	body.add_child(UI.para(s.desc, 16))
	body.add_child(UI.sep())
	match s.kind:
		"goods":
			_goods(body, run, id)
		"facility":
			_facilities(body, run)
		"pawn":
			_pawn(body, run)


func _goods(v: VBoxContainer, run: Dictionary, shop_id: String) -> void:
	if Pre.status(run, shop_id) == "关门":
		v.add_child(UI.para(Pre.shop(shop_id).get("close", {}).get("text", "已经关门了。"), 18, UI.CINNABAR))
		return
	var g := UI.grid(6, 10, 6)
	for col in ["货品", "价钱", "斤两", "余货", "", ""]:
		g.add_child(UI.label(col, 15, UI.INK_FAINT))
	for item_id in run.shops[shop_id]:
		var it := Data.item(item_id)
		var left := int(run.shops[shop_id][item_id])
		var name_label := UI.label("%s（%s）" % [it.name, it.unit], 18)
		name_label.tooltip_text = it.desc
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		UI.expand(name_label)
		g.add_child(name_label)
		var p := Pre.price(run, shop_id, item_id)
		g.add_child(UI.label(Pre.money(p), 18, UI.CINNABAR if p > int(it.price) else UI.INK))
		g.add_child(UI.label(str(it.weight), 16, UI.INK_SOFT))
		g.add_child(UI.label("余 %d" % left, 16, UI.INK_SOFT if left > 0 else UI.INK_FAINT))
		var block := Pre.buy_block(run, item_id, 1)
		g.add_child(UI.button("买一", func(): _act_sfx(func(): return Pre.buy(Game.run, item_id, 1), "coins"), block != "", block))
		var most := Pre.max_buy(run, item_id)
		g.add_child(UI.button("买 %d" % most if most > 1 else "买尽", func(): _act_sfx(func(): return Pre.buy(Game.run, item_id, Pre.max_buy(Game.run, item_id)), "coins"), most <= 1))
	v.add_child(g)


func _facilities(v: VBoxContainer, run: Dictionary) -> void:
	var facs: Dictionary = Data.table("facilities")
	for fac_id in facs:
		var f: Dictionary = facs[fac_id]
		var h := UI.hbox(10)
		var info := UI.vbox(2)
		UI.expand(info)
		info.add_child(UI.label("%s　%s" % [f.name, Pre.money(int(f.price))], 19))
		info.add_child(UI.para(f.desc, 15))
		h.add_child(info)
		if fac_id in run.orders:
			h.add_child(UI.tag("已订", UI.JADE))
		else:
			_action(h, "订制", func(): _act_sfx(func(): return Pre.order(Game.run, fac_id), "book_place"), Pre.order_block(run, fac_id))
		v.add_child(h)


func _pawn(v: VBoxContainer, run: Dictionary) -> void:
	var items := Pre.pawnable(run)
	if items.is_empty():
		v.add_child(UI.para("身上没有值钱的东西。", 17))
		return
	for item_id in items:
		var h := UI.hbox(10)
		var n := Inv.count(run.cart, item_id) + Inv.count(run.home, item_id)
		h.add_child(UI.expand(UI.label("%s ×%d" % [Data.item_name(item_id), n], 18)))
		h.add_child(UI.label("当得 %s" % Pre.money(Pre.pawn_value(item_id)), 17, UI.CINNABAR))
		h.add_child(UI.button("当了", func(): _act_sfx(func(): return Pre.pawn(Game.run, item_id), "coins")))
		v.add_child(h)


# ---------- 备劫：囤货清单 ----------

func checklist() -> void:
	UI.open_modal("checklist", "囤货清单", _checklist, true, 620)


func _checklist(body: VBoxContainer) -> void:
	var run := _run()
	body.add_child(UI.para("按二十日的用度估算。家里的和车上的都算。", 15))
	var g := UI.grid(3, 16, 4)
	for row in Pre.checklist(run):
		g.add_child(UI.label(row.name, 18))
		g.add_child(UI.label("%d %s" % [row.value, row.unit], 16, UI.INK_SOFT))
		g.add_child(UI.tag(row.grade, GRADE_COLORS[row.grade]))
	body.add_child(g)
	body.add_child(UI.sep())
	var orders := []
	for fac_id in run.orders:
		orders.append(Data.table("facilities")[fac_id].name)
	body.add_child(UI.para("已订营造：" + ("、".join(orders) if not orders.is_empty() else "还没去营造坊（第二日后就来不及了）"), 16, UI.INK if not orders.is_empty() else UI.CINNABAR))
	body.add_child(UI.para("家中存货：" + (Data.describe_items(run.home) if not run.home.is_empty() else "（空）"), 15))
	body.add_child(UI.para("车上：" + (Data.describe_items(run.cart) if not run.cart.is_empty() else "空着"), 15))


# ---------- 设置 ----------

const VOLUME_ROWS := [["music", "配乐"], ["sfx", "音效"], ["amb", "风声环境"]]


## 设置：三条音量；在游戏里打开时还能回标题（进度已自动存档）。
func settings(in_game := false) -> void:
	UI.open_modal("settings", "设置", _settings.bind(in_game), true, 560)


func _settings(body: VBoxContainer, in_game: bool) -> void:
	for row in VOLUME_ROWS:
		var key: String = row[0]
		var h := UI.hbox(12)
		h.add_child(UI.fixed_width(UI.label(row[1], 18), 96))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Sfx.volume(key)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y = 24
		var pct := UI.fixed_width(UI.label("%d%%" % roundi(slider.value * 100), 16, UI.INK_SOFT), 52)
		slider.value_changed.connect(_on_volume.bind(key, pct))
		# 松手时试听一下、存起来
		slider.drag_ended.connect(_on_volume_done.bind(key))
		h.add_child(slider)
		h.add_child(pct)
		body.add_child(h)
	body.add_child(UI.para("声音素材：Kenney、OpenGameArt、BiteMe Games（CC0）；梆子、更鼓、赶尸铃、铜锣为程序合成。", 14, UI.INK_FAINT))
	if in_game:
		body.add_child(UI.sep())
		var row := UI.hbox()
		row.add_child(UI.para("进度已自动存档，回到标题后可以续写。", 15))
		row.add_child(UI.button("回到标题", func(): Game.go("title")))
		body.add_child(row)


func _on_volume(value: float, key: String, pct: Label) -> void:
	Sfx.set_volume(key, value)
	pct.text = "%d%%" % roundi(value * 100)


func _on_volume_done(_changed: bool, key: String) -> void:
	Game.save_meta()
	match key:
		"music":
			pass
		"sfx":
			Sfx.play("bangzi", -4.0, 0.0)
		"amb":
			Sfx.play("gust", -6.0)
